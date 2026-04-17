// slap-bridge forwards Apple Silicon laptop impacts to the Triggerit HUD over UDP.
// Sensor + detector logic mirrors github.com/taigrr/spank (MIT) but omits audio.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/taigrr/apple-silicon-accelerometer/detector"
	"github.com/taigrr/apple-silicon-accelerometer/sensor"
	"github.com/taigrr/apple-silicon-accelerometer/shm"
)

type runtimeTuning struct {
	minAmplitude float64
	cooldown     time.Duration
	pollInterval time.Duration
	maxBatch     int
}

func defaultTuning() runtimeTuning {
	return runtimeTuning{
		minAmplitude: 0.05,
		cooldown:     750 * time.Millisecond,
		pollInterval: 10 * time.Millisecond,
		maxBatch:     200,
	}
}

func applyFastOverlay(base runtimeTuning) runtimeTuning {
	base.pollInterval = 4 * time.Millisecond
	base.cooldown = 350 * time.Millisecond
	if base.minAmplitude > 0.18 {
		base.minAmplitude = 0.18
	}
	if base.maxBatch < 320 {
		base.maxBatch = 320
	}
	return base
}

func main() {
	var (
		udpAddr    = flag.String("udp", "127.0.0.1:19722", "UDP destination host:port for JSON {\"t\":\"slap\"}")
		fast       = flag.Bool("fast", true, "Low-latency preset (4ms poll, larger batches); pass -fast=false to disable")
		minAmp     = flag.Float64("min-amplitude", 0.20, "Minimum impact amplitude (g); use -1 for auto (0.05 without fast, 0.18 with fast only)")
		cooldownMs = flag.Int("cooldown", 1500, "Cooldown between emitted events (ms); use -1 for auto (750 without fast, 350 with fast only)")
	)
	flag.Parse()

	if os.Geteuid() != 0 {
		log.Fatal("slap-bridge must run as root for HID accelerometer access: sudo go run . --udp ...")
	}

	tuning := defaultTuning()
	if *fast {
		tuning = applyFastOverlay(tuning)
	}
	if *cooldownMs >= 0 {
		tuning.cooldown = time.Duration(*cooldownMs) * time.Millisecond
	}
	if *minAmp >= 0 {
		tuning.minAmplitude = *minAmp
	}

	udp, err := net.ResolveUDPAddr("udp", *udpAddr)
	if err != nil {
		log.Fatalf("bad --udp: %v", err)
	}
	conn, err := net.DialUDP("udp", nil, udp)
	if err != nil {
		log.Fatalf("udp dial: %v", err)
	}
	defer conn.Close()

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	accelRing, err := shm.CreateRing(shm.NameAccel)
	if err != nil {
		log.Fatalf("shm: %v", err)
	}
	defer accelRing.Close()
	defer accelRing.Unlink()

	sensorReady := make(chan struct{})
	sensorErr := make(chan error, 1)
	go func() {
		close(sensorReady)
		if err := sensor.Run(sensor.Config{AccelRing: accelRing, Restarts: 0}); err != nil {
			sensorErr <- err
		}
	}()

	select {
	case <-sensorReady:
	case err := <-sensorErr:
		log.Fatalf("sensor: %v", err)
	case <-ctx.Done():
		return
	}
	time.Sleep(100 * time.Millisecond)

	det := detector.New()
	var lastAccelTotal uint64
	var lastEventTime time.Time
	var lastEmit time.Time

	ticker := time.NewTicker(tuning.pollInterval)
	defer ticker.Stop()

	log.Printf("slap-bridge → %s (poll=%s cooldown=%s minAmp=%.3f fast=%v)",
		*udpAddr, tuning.pollInterval, tuning.cooldown, tuning.minAmplitude, *fast)

	for {
		select {
		case <-ctx.Done():
			return
		case err := <-sensorErr:
			log.Fatalf("sensor worker: %v", err)
		case <-ticker.C:
		}

		now := time.Now()
		tNow := float64(now.UnixNano()) / 1e9

		samples, newTotal := accelRing.ReadNew(lastAccelTotal, shm.AccelScale)
		lastAccelTotal = newTotal
		if len(samples) > tuning.maxBatch {
			samples = samples[len(samples)-tuning.maxBatch:]
		}

		nSamples := len(samples)
		for idx, sample := range samples {
			tSample := tNow - float64(nSamples-idx-1)/float64(det.FS)
			det.Process(sample.X, sample.Y, sample.Z, tSample)
		}

		if len(det.Events) == 0 {
			continue
		}
		ev := det.Events[len(det.Events)-1]
		if ev.Time.Equal(lastEventTime) {
			continue
		}
		lastEventTime = ev.Time

		if now.Sub(lastEmit) <= tuning.cooldown {
			continue
		}
		if ev.Amplitude < tuning.minAmplitude {
			continue
		}
		lastEmit = now

		payload := map[string]any{
			"t":         "slap",
			"a":         ev.Amplitude,
			"severity":  string(ev.Severity),
			"timestamp": now.UnixMilli(),
		}
		b, err := json.Marshal(payload)
		if err != nil {
			continue
		}
		if _, err := conn.Write(b); err != nil {
			log.Printf("udp write: %v", err)
		}
	}
}
