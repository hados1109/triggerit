# HeyAgent — Phase 1 attention triggers

Native **SwiftUI HUD** plus two **UDP JSON** producers:

1. **Gaze** — Python + [EyeTrax](https://github.com/ck-zhang/EyeTrax) (default “winner” after bake-off), dense calibration, AOI dwell → `{"t":"gaze_trig"}`.
2. **Slap** — Go + [apple-silicon-accelerometer](https://github.com/taigrr/apple-silicon-accelerometer) (same stack as [spank](https://github.com/taigrr/spank)), **no audio on the hot path**, UDP `{"t":"slap"}`.

## Run the HUD

```bash
cd "/Users/vinyas/Cursor projects/HeyAgent"
swift run HeyAgent
```

Grant nothing special for Swift; it only **listens** on UDP `19722` by default.

## Run gaze (Python)

Use [uv](https://github.com/astral-sh/uv) or `pip install -r python/requirements.txt`.

```bash
cd python
uv sync
uv run python gaze_bridge.py --udp-port 19722
```

First launch runs calibration (see `python/README.md`), then streams `{"t":"gaze",...}` and fires `gaze_trig` when you dwell on the top-center AOI.

## Run slap (Go, root)

Requires **Apple Silicon** per upstream; **sudo** for HID.

```bash
cd slap-bridge
go mod tidy
sudo go run . --udp 127.0.0.1:19722
```

(`slap-bridge` defaults: fast on, `--min-amplitude 0.40`, `--cooldown 1500`.)

See [slap-bridge/README.md](slap-bridge/README.md) for flags and chip notes.

## Bake-off (other gaze libraries)

See [python/bakeoff/README.md](python/bakeoff/README.md) for how to compare LaserGaze, GazeFollower, or OpenFace 3.0 against EyeTrax on your desk.

## Acceptance

Checklist and tuning notes: [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md).
