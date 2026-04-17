# Gaze accuracy bake-off

Goal: pick the best **webcam gaze → screen** pipeline for *your* MacBook camera, lighting, and seating. Phase 1 ships **EyeTrax** in `gaze_bridge.py` as the default integrator; this folder documents how to compare alternatives fairly.

## Shared protocol

1. Fix chair height and screen angle for the whole session.
2. Define the same **AOI** (top-center “camera band”) in normalized coordinates — match `gaze_bridge.py` defaults (`--aoi-cx`, `--aoi-cy`, `--aoi-w`, `--aoi-h`) or note deltas.
3. For each library, run **one fresh calibration**, then **60 seconds** of:
   - 20 s: look at AOI (true positives)
   - 20 s: read dock / keyboard (false positives)
   - 20 s: secondary monitor or phone if available (false positives)
4. Record **hit rate** (AOI time / ground-truth) and **false triggers** (HUD flashes while not intending camera).

## Candidates

| Library | Install hint | Notes |
|---------|----------------|-------|
| **EyeTrax** (integrated) | `uv sync` in `./python` | Dense grid calibration; EMA smoothing in bridge. |
| [LaserGaze](https://github.com/tensorsense/LaserGaze) | Follow upstream README | Temporal gaze + MediaPipe; good stability benchmark. |
| [GazeFollower](https://github.com/GanchengZhu/GazeFollower) | `pip install gazefollower` | Lightweight API; compare raw error vs EyeTrax. |
| **OpenFace 3.0** | See [arXiv paper](https://arxiv.org/html/2506.02891v1) / project releases | Heavier stack; use if you need multitask face + gaze. |

## Winner selection

When a candidate clearly wins, either:

- Point `gaze_bridge.py` at that backend (PR / fork), **or**
- Keep EyeTrax and copy tuned AOI / dwell / EMA constants from the winning session into `gaze_bridge.py` flags.

Document the outcome in `docs/ACCEPTANCE.md` under “Gaze bake-off”.
