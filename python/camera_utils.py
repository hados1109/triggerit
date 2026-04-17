"""
macOS-friendly camera open + optional EyeTrax monkeypatch.

EyeTrax bundles `open_camera()` that uses plain `cv2.VideoCapture(n)`, which often
fails on macOS even when cameras exist. We replace it with AVFoundation + a real
frame read, and (for default camera 0) auto-pick the first working index.
"""

from __future__ import annotations

import importlib
import os
import sys
from typing import Callable, Optional

import cv2

# Fewer scary "out device of bound" lines when probing past the last camera.
try:
    if hasattr(cv2, "utils") and hasattr(cv2.utils, "logging"):
        log_mod = cv2.utils.logging
        silent = getattr(log_mod, "LOG_LEVEL_SILENT", getattr(log_mod, "LOG_LEVEL_ERROR", 3))
        log_mod.setLogLevel(silent)
except Exception:
    os.environ.setdefault("OPENCV_LOG_LEVEL", "ERROR")


def _backends() -> list[Optional[int]]:
    if sys.platform != "darwin":
        return [None]
    avf = getattr(cv2, "CAP_AVFOUNDATION", None)
    if avf is None:
        return [None]
    return [int(avf), None]


# Submodules that bind `from eyetrax.utils.video import open_camera` at import time.
_EYETRAX_OPEN_CAMERA_MODULES = (
    "eyetrax.utils.video",
    "eyetrax.calibration.dense_grid",
    "eyetrax.calibration.nine_point",
    "eyetrax.calibration.five_point",
    "eyetrax.calibration.lissajous",
    "eyetrax.calibration.adaptive",
    "eyetrax.filters.kalman",
)


def _try_open(index: int, backend: Optional[int]) -> cv2.VideoCapture | None:
    cap = (
        cv2.VideoCapture(index, backend)
        if backend is not None
        else cv2.VideoCapture(index)
    )
    if not cap.isOpened():
        cap.release()
        return None
    ok, frame = cap.read()
    if not ok or frame is None or frame.size == 0:
        cap.release()
        return None
    return cap


def open_camera_robust(index: int = 0) -> cv2.VideoCapture:
    """
    Prefer AVFoundation on macOS, verify a frame can be read, optionally fall back
    when the default index fails (same idea as EyeTrax's 0→1 fallback, but broader).
    """
    backends = _backends()

    tried: set[int] = set()

    def attempt(idx: int) -> cv2.VideoCapture | None:
        if idx in tried:
            return None
        tried.add(idx)
        for be in backends:
            cap = _try_open(idx, be)
            if cap is not None:
                return cap
        return None

    cap = attempt(index)
    if cap is not None:
        return cap

    # Default index 0: try higher indices until several misses in a row (no gaps on Mac).
    if index == 0:
        miss = 0
        for alt in range(1, 16):
            cap = attempt(alt)
            if cap is not None:
                print(
                    f"[triggerit] Camera 0 did not work; opened camera index {alt} instead.",
                    file=sys.stderr,
                    flush=True,
                )
                return cap
            miss += 1
            if miss >= 3:
                break

    hint = _privacy_hint()
    mac_note = " AVFoundation + default backend" if sys.platform == "darwin" else ""
    raise RuntimeError(f"Cannot open camera index {index} (tried{mac_note}).{hint}")


def _privacy_hint() -> str:
    return (
        "\n\nmacOS checks:\n"
        "  • System Settings → Privacy & Security → Camera → turn ON for Terminal "
        "(or iTerm, or the app running Python).\n"
        "  • Quit other apps using the camera (Zoom, FaceTime, photo booth, browser tabs).\n"
        "  • List devices:  uv run python gaze_bridge.py --list-cameras\n"
        "  • Then retry with:  --camera N   (built-in is often 0 or 1, not always).\n"
    )


def install_eyetrax_open_camera_patch() -> None:
    """Must run after `eyetrax` is importable, before calibration."""
    fn: Callable[[int], cv2.VideoCapture] = open_camera_robust
    for mod_name in _EYETRAX_OPEN_CAMERA_MODULES:
        try:
            mod = importlib.import_module(mod_name)
        except ImportError:
            continue
        if hasattr(mod, "open_camera"):
            setattr(mod, "open_camera", fn)


def list_working_cameras(max_scan: int = 12) -> list[tuple[int, tuple[int, int]]]:
    """
    Return [(index, (width, height)), ...].

    Stops after several consecutive indices with no camera, so we do not keep
    opening non-existent indices (which spams OpenCV warnings on macOS).
    """
    out: list[tuple[int, tuple[int, int]]] = []
    avf = getattr(cv2, "CAP_AVFOUNDATION", None)
    consecutive_miss = 0

    for i in range(max_scan + 1):
        opened = False
        for be in _backends():
            cap = _try_open(i, be)
            if cap is None:
                continue
            w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or 0
            h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 0
            if w <= 0 or h <= 0:
                ok, frame = cap.read()
                if ok and frame is not None and frame.size > 0:
                    h, w = frame.shape[:2]
            cap.release()
            if w > 0 and h > 0:
                be_name = "AVFoundation" if avf is not None and be == avf else "default"
                print(f"  index {i}  ({w}x{h})  backend={be_name}", flush=True)
                out.append((i, (w, h)))
                consecutive_miss = 0
                opened = True
                break
        if opened:
            continue
        consecutive_miss += 1
        if out and consecutive_miss >= 3:
            break
        if not out and i >= 8:
            break

    return out
