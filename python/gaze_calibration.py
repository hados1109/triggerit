"""
EyeTrax calibration sample collection + merged training for Triggerit.

EyeTrax's bundled calibration routines train immediately and do not return
samples. We duplicate the capture flow using the same helpers so we can:

- Save a `.samples.npz` sidecar (X, y) next to the `.pkl` model
- Optionally concatenate new samples with prior sessions (`append`)
"""

from __future__ import annotations

from pathlib import Path
from typing import Literal

import numpy as np

from camera_utils import open_camera_robust

CalibrationKind = Literal["dense", "9", "5"]


def samples_npz_path(model_path: Path) -> Path:
    return model_path.parent / f"{model_path.stem}.samples.npz"


def load_stored_samples(model_path: Path) -> tuple[np.ndarray, np.ndarray] | None:
    path = samples_npz_path(model_path)
    if not path.exists():
        return None
    data = np.load(path)
    return data["X"], data["y"]


def collect_calibration_samples(
    gaze_estimator,
    calibration: CalibrationKind,
    *,
    camera_index: int = 0,
    dense_rows: int = 5,
    dense_cols: int = 5,
    dense_margin_ratio: float = 0.1,
    dense_order: str = "serpentine",
    pulse_d: float = 0.9,
    cd_d: float = 0.9,
) -> tuple[np.ndarray, np.ndarray] | None:
    """
    Run one interactive calibration and return (X, y) feature matrices, or None
    if the user aborted (Esc) or no samples were collected.
    """
    import cv2

    from eyetrax.calibration.common import (
        _pulse_and_capture,
        compute_grid_points,
        compute_grid_points_from_shape,
        wait_for_face_and_countdown,
    )
    from eyetrax.utils.screen import get_screen_size

    sw, sh = get_screen_size()
    cap = open_camera_robust(camera_index)
    try:
        if not wait_for_face_and_countdown(cap, gaze_estimator, sw, sh, 2):
            return None

        if calibration == "dense":
            pts = compute_grid_points_from_shape(
                dense_rows,
                dense_cols,
                sw,
                sh,
                margin_ratio=dense_margin_ratio,
                order=dense_order,
            )
        elif calibration == "9":
            order = [
                (1, 1),
                (0, 0),
                (2, 0),
                (0, 2),
                (2, 2),
                (1, 0),
                (0, 1),
                (2, 1),
                (1, 2),
            ]
            pts = compute_grid_points(order, sw, sh)
        else:
            order = [(1, 1), (0, 0), (2, 0), (0, 2), (2, 2)]
            pts = compute_grid_points(order, sw, sh)

        res = _pulse_and_capture(
            gaze_estimator, cap, pts, sw, sh, pulse_d=pulse_d, cd_d=cd_d
        )
    finally:
        cap.release()
        cv2.destroyAllWindows()

    if res is None:
        return None
    feats, targs = res
    if not feats:
        return None
    return np.asarray(feats, dtype=np.float32), np.asarray(targs, dtype=np.float32)


def merge_samples(
    X_prev: np.ndarray | None,
    y_prev: np.ndarray | None,
    X_new: np.ndarray,
    y_new: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    if X_prev is None or y_prev is None or len(X_prev) == 0:
        return X_new, y_new
    if X_prev.shape[1] != X_new.shape[1]:
        raise ValueError(
            f"Feature dimension mismatch: stored {X_prev.shape[1]} vs new {X_new.shape[1]}. "
            "Cannot merge — recalibrate without append or use a fresh profile."
        )
    X = np.vstack([X_prev, X_new])
    y = np.vstack([y_prev, y_new])
    return X, y


def train_and_persist(
    gaze_estimator,
    model_path: Path,
    X: np.ndarray,
    y: np.ndarray,
) -> None:
    """Fit EyeTrax regression on X,y and save model + sample sidecar."""
    model_path.parent.mkdir(parents=True, exist_ok=True)
    gaze_estimator.train(X, y)
    gaze_estimator.save_model(str(model_path))
    np.savez_compressed(samples_npz_path(model_path), X=X, y=y)


def calibrate_and_save(
    gaze_estimator,
    model_path: Path,
    calibration: CalibrationKind,
    *,
    camera_index: int = 0,
    append: bool = False,
    dense_rows: int = 5,
    dense_cols: int = 5,
    dense_margin_ratio: float = 0.1,
    dense_order: str = "serpentine",
) -> tuple[bool, str]:
    """
    Collect samples, optionally merge with prior `.samples.npz`, train, persist.

    Returns (ok, message) where ok is False on user abort or empty calibration.
    """
    collected = collect_calibration_samples(
        gaze_estimator,
        calibration,
        camera_index=camera_index,
        dense_rows=dense_rows,
        dense_cols=dense_cols,
        dense_margin_ratio=dense_margin_ratio,
        dense_order=dense_order,
    )
    if collected is None:
        return False, "Calibration aborted or no samples collected."

    X_new, y_new = collected
    X_prev = y_prev = None
    if append:
        prev = load_stored_samples(model_path)
        if prev is None:
            msg = (
                "Append requested but no .samples.npz found for this model — "
                "training on this session only. Future appends will merge."
            )
        else:
            X_prev, y_prev = prev
            msg = f"Merging with {len(X_prev)} stored samples + {len(X_new)} new."
        try:
            X, y = merge_samples(X_prev, y_prev, X_new, y_new)
        except ValueError as e:
            return False, str(e)
    else:
        X, y = X_new, y_new
        msg = f"Trained on {len(X)} samples."

    train_and_persist(gaze_estimator, model_path, X, y)
    return True, f"{msg} Total samples saved: {len(X)}."
