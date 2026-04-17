#!/usr/bin/env python3
"""
HeyAgent gaze → UDP JSON for the Swift HUD.
Primary path: EyeTrax (dense/9p calibration, optional filters).

Models:
  Default file: ~/.heyagent/gaze_model.pkl
  Named profiles: ~/.heyagent/gaze_models/<name>.pkl (+ <name>.samples.npz for append)
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from pathlib import Path

import numpy as np

from camera_utils import install_eyetrax_open_camera_patch, list_working_cameras, open_camera_robust
from gaze_calibration import calibrate_and_save

try:
    from screeninfo import get_monitors
except ImportError:
    get_monitors = None


def primary_screen_size() -> tuple[int, int]:
    if get_monitors is None:
        return 1512, 982
    try:
        m = get_monitors()[0]
        return int(m.width), int(m.height)
    except Exception:
        return 1512, 982


def send_udp(sock: socket.socket, host: str, port: int, payload: dict) -> None:
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    if len(data) > 65000:
        return
    sock.sendto(data, (host, port))


def point_in_aoi(sx: float, sy: float, cx: float, cy: float, hw: float, hh: float) -> bool:
    return abs(sx - cx) <= hw / 2 and abs(sy - cy) <= hh / 2


def resolve_model_path(args: argparse.Namespace) -> Path:
    if args.model is not None:
        return Path(args.model).expanduser().resolve()
    if args.profile is not None:
        d = Path(args.model_dir).expanduser().resolve()
        return (d / f"{args.profile}.pkl").resolve()
    return (Path.home() / ".heyagent" / "gaze_model.pkl").resolve()


def list_profiles_action(model_dir: Path) -> int:
    from gaze_calibration import samples_npz_path

    d = Path(model_dir).expanduser().resolve()
    if not d.is_dir():
        print(f"No profile directory at {d} (create it on first --profile use).", flush=True)
        return 0
    paths = sorted(d.glob("*.pkl"))
    if not paths:
        print(f"No *.pkl profiles in {d}", flush=True)
        return 0
    print(f"Profiles in {d}:", flush=True)
    for p in paths:
        sp = samples_npz_path(p)
        extra = ""
        if sp.exists():
            data = np.load(sp)
            n = len(data["X"])
            extra = f"  samples={n} (append-ready)"
        print(f"  {p.stem}  →  {p.name}{extra}", flush=True)
    print("Use:  --profile <name>   or   --model /path/to/file.pkl", flush=True)
    return 0


def run() -> int:
    p = argparse.ArgumentParser(description="EyeTrax → HeyAgent UDP gaze bridge")
    p.add_argument("--udp-host", default="127.0.0.1")
    p.add_argument("--udp-port", type=int, default=19_722)
    p.add_argument("--camera", type=int, default=0)
    p.add_argument(
        "--model",
        type=Path,
        default=None,
        help="Explicit gaze model .pkl (overrides --profile / default path)",
    )
    p.add_argument(
        "--model-dir",
        type=Path,
        default=Path.home() / ".heyagent" / "gaze_models",
        help="Directory for named --profile models",
    )
    p.add_argument(
        "--profile",
        type=str,
        default=None,
        metavar="NAME",
        help="Named model: <model-dir>/NAME.pkl (ignored if --model is set)",
    )
    p.add_argument("--calibration", choices=("dense", "9", "5"), default="dense")
    p.add_argument("--dense-rows", type=int, default=5)
    p.add_argument("--dense-cols", type=int, default=5)
    p.add_argument("--dense-margin", type=float, default=0.1)
    p.add_argument("--ema-alpha", type=float, default=0.35, help="EMA smoothing for gaze (0–1, higher = snappier)")
    p.add_argument("--dwell", type=float, default=0.45)
    p.add_argument("--cooldown", type=float, default=1.25)
    p.add_argument("--aoi-cx", type=float, default=0.5)
    p.add_argument("--aoi-cy", type=float, default=0.08)
    p.add_argument("--aoi-w", type=float, default=0.22)
    p.add_argument("--aoi-h", type=float, default=0.18)
    p.add_argument("--fps-cap", type=float, default=45.0)
    p.add_argument(
        "--list-cameras",
        action="store_true",
        help="List camera indices that OpenCV can open (then exit)",
    )
    p.add_argument(
        "--list-profiles",
        action="store_true",
        help="List named gaze models under --model-dir (then exit)",
    )
    p.add_argument(
        "--calibrate-only",
        action="store_true",
        help="Run calibration, save model (+ samples for append), then exit",
    )
    p.add_argument(
        "--append-calibration",
        action="store_true",
        help="Merge new calibration samples with existing .samples.npz when present",
    )
    p.add_argument(
        "--recalibrate",
        action="store_true",
        help="Run calibration before streaming even if the model file already exists",
    )
    args = p.parse_args()

    if args.list_cameras:
        print("Probing cameras (may take a few seconds)…", flush=True)
        found = list_working_cameras()
        if not found:
            print("No working cameras found.", flush=True)
            print(
                "Check System Settings → Privacy & Security → Camera for this terminal app.",
                flush=True,
            )
        else:
            print("Use one of the indices above with:  --camera N", flush=True)
        return 0 if found else 1

    model_path = resolve_model_path(args)

    if args.list_profiles:
        return list_profiles_action(args.model_dir)

    try:
        from eyetrax import GazeEstimator
    except ImportError as e:
        print("EyeTrax is required: pip install eyetrax  (or uv sync in ./python)", file=sys.stderr)
        print(e, file=sys.stderr)
        return 1

    install_eyetrax_open_camera_patch()

    estimator = GazeEstimator()
    try:
        cal_kw = dict(
            camera_index=args.camera,
            append=args.append_calibration,
            dense_rows=args.dense_rows,
            dense_cols=args.dense_cols,
            dense_margin_ratio=args.dense_margin,
        )

        if args.calibrate_only:
            model_path.parent.mkdir(parents=True, exist_ok=True)
            ok, msg = calibrate_and_save(
                estimator,
                model_path,
                args.calibration,
                **cal_kw,
            )
            print(msg, flush=True)
            if ok:
                print(f"Saved model to {model_path}", flush=True)
            return 0 if ok else 1

        need_calib = not model_path.exists() or args.recalibrate
        if need_calib:
            print(
                "Starting calibration…"
                + (" (append mode)" if args.append_calibration else ""),
                flush=True,
            )
            model_path.parent.mkdir(parents=True, exist_ok=True)
            ok, msg = calibrate_and_save(
                estimator,
                model_path,
                args.calibration,
                **cal_kw,
            )
            print(msg, flush=True)
            if not ok:
                return 1
            print(f"Saved model to {model_path}", flush=True)
        else:
            print(f"Loading model {model_path}", flush=True)
            estimator.load_model(str(model_path))

        try:
            cap = open_camera_robust(args.camera)
        except RuntimeError as e:
            print(e, file=sys.stderr)
            return 1

        sw, sh = primary_screen_size()
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        min_interval = 1.0 / max(1.0, args.fps_cap)
        last_send = 0.0
        in_zone_since: float | None = None
        last_trigger = 0.0

        print(
            f"Streaming gaze → udp://{args.udp_host}:{args.udp_port}  "
            f"(screen {sw}x{sh}, ema={args.ema_alpha}, model={model_path})",
            flush=True,
        )

        ema_sx: float | None = None
        ema_sy: float | None = None
        alpha = max(0.01, min(1.0, float(args.ema_alpha)))

        try:
            while True:
                ok, frame = cap.read()
                if not ok:
                    time.sleep(0.01)
                    continue
                now = time.time()

                features, blink = estimator.extract_features(frame)
                sx = sy = None
                if features is not None and not blink:
                    xy = estimator.predict([features])[0]
                    sx_f, sy_f = float(xy[0]), float(xy[1])
                    rx = max(0.0, min(1.0, sx_f / sw))
                    ry = max(0.0, min(1.0, sy_f / sh))
                    if ema_sx is None:
                        ema_sx, ema_sy = rx, ry
                    else:
                        ema_sx = alpha * rx + (1.0 - alpha) * ema_sx
                        ema_sy = alpha * ry + (1.0 - alpha) * ema_sy
                    sx, sy = ema_sx, ema_sy
                else:
                    ema_sx = ema_sy = None

                in_zone = False
                dwell_s = 0.0
                if sx is not None and sy is not None:
                    in_zone = point_in_aoi(
                        sx, sy, args.aoi_cx, args.aoi_cy, args.aoi_w, args.aoi_h
                    )
                    if in_zone:
                        if in_zone_since is None:
                            in_zone_since = now
                        dwell_s = now - in_zone_since
                    else:
                        in_zone_since = None

                if now - last_send >= min_interval:
                    last_send = now
                    z = 1 if in_zone else 0
                    send_udp(
                        sock,
                        args.udp_host,
                        args.udp_port,
                        {
                            "t": "gaze",
                            "sx": -1.0 if sx is None else sx,
                            "sy": -1.0 if sy is None else sy,
                            "z": z,
                            "d": round(dwell_s, 3),
                        },
                    )

                if (
                    sx is not None
                    and sy is not None
                    and in_zone
                    and dwell_s >= args.dwell
                    and (now - last_trigger) >= args.cooldown
                ):
                    last_trigger = now
                    in_zone_since = now
                    send_udp(sock, args.udp_host, args.udp_port, {"t": "gaze_trig"})

        finally:
            cap.release()
            sock.close()

    finally:
        estimator.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(run())
