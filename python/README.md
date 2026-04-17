# Gaze bridge (EyeTrax)

Sends compact UDP JSON to the Swift HUD (`TriggerHub`).

```bash
cd python
uv sync
uv run python gaze_bridge.py --udp-port 19722
```

First run: choose calibration (`dense` recommended for accuracy). Model is saved to `~/.heyagent/gaze_model.pkl` by default.

**Multiple setups:** use `--profile office` (stores `~/.heyagent/gaze_models/office.pkl`). Each calibration also writes `office.samples.npz` so you can run **`--append-calibration`** later to merge another session (e.g. different lighting) into one model. **`--list-profiles`** shows saved profiles and sample counts.

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--udp-host` | 127.0.0.1 | HUD address |
| `--udp-port` | 19722 | Must match Swift listener |
| `--camera` | 0 | OpenCV camera index |
| `--model` | (see below) | Explicit path to `.pkl`; overrides `--profile` |
| `--model-dir` | ~/.heyagent/gaze_models | Where `--profile NAME` saves `NAME.pkl` |
| `--profile` | (unset) | Named model: `<model-dir>/NAME.pkl` |
| `--calibration` | dense | `dense`, `9`, or `5` |
| `--dense-rows` / `--dense-cols` | 5 / 5 | Dense grid shape (with `--calibration dense`) |
| `--dense-margin` | 0.1 | Screen margin ratio for dense grid |
| `--calibrate-only` | off | Calibrate, save, exit (no UDP streaming) |
| `--append-calibration` | off | Merge with existing `*.samples.npz` when present |
| `--recalibrate` | off | Run calibration before streaming even if `.pkl` exists |
| `--list-profiles` | off | List `*.pkl` under `--model-dir`, then exit |
| `--ema-alpha` | 0.35 | EMA smoothing on normalized gaze (higher = snappier) |
| `--dwell` | 0.45 | Seconds gaze must stay in AOI |
| `--cooldown` | 1.25 | Seconds after a trigger before another |
| `--aoi-cx` | 0.5 | AOI center x (normalized 0–1) |
| `--aoi-cy` | 0.08 | AOI center y (top of screen ≈ camera) |
| `--aoi-w` | 0.22 | AOI width |
| `--aoi-h` | 0.18 | AOI height |

If neither `--model` nor `--profile` is set, the default path is `~/.heyagent/gaze_model.pkl` (same as before).

### Profile + append examples

```bash
# First session (e.g. daylight) — creates office.pkl + office.samples.npz
uv run python gaze_bridge.py --profile office --calibrate-only

# Later, same profile, different conditions — merges into one model
uv run python gaze_bridge.py --profile office --calibrate-only --append-calibration

# Stream using that profile
uv run python gaze_bridge.py --profile office --udp-port 19722

# See what you have saved
uv run python gaze_bridge.py --list-profiles
```

Camera permission: macOS prompts the first time Python accesses the webcam.

## “Cannot open camera 0 / 1” (common on Mac)

Having **two cameras** usually means the built-in one is **not** index `0` (e.g. Continuity Camera or a USB webcam can take `0`). That is normal.

1. **Allow the camera for your terminal app**  
   **System Settings → Privacy & Security → Camera** — turn **on** for **Terminal** (or **iTerm**, or **Cursor** if you run Python from there).

2. **List which indices work** (from the `python` folder):

   ```bash
   uv run python gaze_bridge.py --list-cameras
   ```

3. **Retry with the right index**, for example:

   ```bash
   uv run python gaze_bridge.py --udp-port 19722 --camera 2
   ```

The bridge patches EyeTrax to use **Apple’s AVFoundation** backend on macOS, which fixes many “OpenCV can’t see the camera” cases.

**Seeing only `index 0` and `index 1` is normal** on a Mac with two camera devices (for example built-in + Continuity Camera, or built-in + one virtual/extra stream). OpenCV only numbers devices `0…N-1`; there is no “index 2” until a third device exists.
