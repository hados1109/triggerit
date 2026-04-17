# slap-bridge

Low-latency **UDP** notifier for Apple Silicon laptop **impacts**. It reuses the same **IOKit HID + vibration detector** stack as [spank](https://github.com/taigrr/spank) but **never decodes MP3** on the detection path — only marshals a tiny JSON packet to the Swift HUD.

## Requirements

- **macOS on Apple Silicon** with HID access supported by upstream (see [spank README](https://github.com/taigrr/spank) chip notes).
- **Go** toolchain compatible with `github.com/taigrr/apple-silicon-accelerometer` (module may require a recent Go; run `go mod tidy` and upgrade Go if prompted).
- **Root**: `sudo go run . ...` or install a setuid-capable wrapper (not provided here).

## Build / run

```bash
go mod tidy
sudo go run . --udp 127.0.0.1:19722
```

Defaults match: `--fast --min-amplitude 0.40 --cooldown 1500` (override any flag as needed).

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--udp` | `127.0.0.1:19722` | Destination for JSON datagrams |
| `--fast` | on | Fast preset (4 ms poll, larger batches); `-fast=false` for calmer polling |
| `--min-amplitude` | `0.40` | Minimum impact strength (g); `-1` restores auto (`0.05` / `0.18`) |
| `--cooldown` | `1500` | Milliseconds between UDP events; `-1` restores auto (`750` / `350`) |

## JSON payload

```json
{"t":"slap","a":0.31,"severity":"MEDIUM","timestamp":1713372812345}
```

The Swift HUD treats any packet with `"t":"slap"` as a trigger.

## Optional comparison

For a second native implementation, try [slap-your-openclaw](https://lib.rs/crates/slap-your-openclaw) and compare end-to-end latency with screen recordings.
