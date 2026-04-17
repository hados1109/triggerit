# Phase 1 acceptance checklist

## Gaze (EyeTrax + `gaze_bridge.py`)

- [ ] **Calibration**: dense (default) completes without abort; model saved under `~/.triggerit/gaze_model.pkl` (or `--profile NAME` → `~/.triggerit/gaze_models/NAME.pkl` plus optional `NAME.samples.npz` for `--append-calibration`).
- [ ] **True positive**: while looking at the **camera / menu-bar band**, HUD shows `gaze_trig` roughly within `dwell` seconds (default 0.45 s) and respects `cooldown` (default 1.25 s).
- [ ] **False negative rate**: acceptable under your normal desk lighting; if poor, reduce `--ema-alpha` (snappier) or widen AOI (`--aoi-w`, `--aoi-h`).
- [ ] **False positive rate**: reading keyboard/dock should not spam triggers; if it does, raise `--dwell`, narrow AOI, or re-calibrate.
- [ ] **UDP**: Swift “Packets (UDP)” counter increases while the bridge runs.

Record final flags in your notes:

```
uv run python gaze_bridge.py --udp-port 19722 --dwell ... --aoi-cy ...
```

## Slap (`slap-bridge`)

- [ ] **Privilege**: `sudo` confirmed; without root the binary exits with a clear error.
- [ ] **True positive**: firm palm-rest tap triggers within a perceptually instant window.
- [ ] **False positives**: ordinary typing should stay below your tolerance; tune `--min-amplitude` and `--cooldown` (defaults: fast on, `0.40`, `1500` ms; use `-fast=false` if too twitchy).
- [ ] **UDP**: each slap increments Swift packet counter and fires orange flash + sound.

## Bake-off (optional)

Follow `python/bakeoff/README.md` and summarize the winner here:

| Metric | EyeTrax | Candidate B | Candidate C |
|--------|---------|---------------|---------------|
| Hit rate (60 s script) | | | |
| False triggers | | | |
| Subjective stability | | | |

**Winner**:

## Known limitations

- Webcam gaze has a hard ceiling vs IR eye trackers.
- HID accelerometer access is **undocumented** and may break on macOS upgrades.
- `swift run` opens a dev window; packaging a signed `.app` is out of scope for Phase 1.
