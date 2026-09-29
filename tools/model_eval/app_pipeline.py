"""Bit-exact Python mirror of the app's detection pipeline.

Keep in sync with lib/services/object_detector_service.dart:
  * camera frames: YUV420 (Android) at ResolutionPreset.low (320x240)
  * _directToTensor: integer BT.601 "studio swing" YUV->RGB + nearest-
    neighbour resize to the model input, in one pass
  * post-processing: TFLite_Detection_PostProcess outputs
    (boxes, classes, scores, count); label = labelmap[class + 1]
"""
from __future__ import annotations

import numpy as np
from PIL import Image

# ── Camera simulation ────────────────────────────────────────────────────────


def camera_frame(rgb: Image.Image, size=(320, 240)) -> np.ndarray:
    """What the camera ISP hands the app: a downscaled RGB frame (HxWx3 u8)."""
    return np.asarray(rgb.convert("RGB").resize(size, Image.BILINEAR), dtype=np.uint8)


def rgb_to_yuv420(rgb: np.ndarray, full_range: bool = True):
    """RGB -> planar YUV 4:2:0 as a camera would produce it.

    full_range=True is JFIF (Y 0..255), which many Android camera HALs emit for
    YUV_420_888; full_range=False is BT.601 limited range (Y 16..235).
    """
    f = rgb.astype(np.float64)
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = -0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 0.5 * r - 0.418688 * g - 0.081312 * b
    if full_range:
        Y = y
        U = cb + 128
        V = cr + 128
    else:
        Y = 16 + y * 219 / 255
        U = 128 + cb * 224 / 255
        V = 128 + cr * 224 / 255
    h, w = Y.shape
    # 2x2 chroma subsampling (average), like the sensor pipeline.
    U = U[: h // 2 * 2, : w // 2 * 2].reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3))
    V = V[: h // 2 * 2, : w // 2 * 2].reshape(h // 2, 2, w // 2, 2).mean(axis=(1, 3))
    q = lambda a: np.clip(np.round(a), 0, 255).astype(np.int32)
    return q(Y), q(U), q(V)


# ── App preprocessing (mirror of _directToTensor, rotation 0) ────────────────


def app_yuv_to_tensor(Y, U, V, out_w: int, out_h: int) -> np.ndarray:
    """Integer studio-swing decode + nearest-neighbour resize, as the app does."""
    src_h, src_w = Y.shape
    sx = (np.arange(out_w) * src_w) // out_w
    sy = (np.arange(out_h) * src_h) // out_h
    yy = Y[sy[:, None], sx[None, :]] - 16
    d = U[(sy >> 1)[:, None], (sx >> 1)[None, :]] - 128
    e = V[(sy >> 1)[:, None], (sx >> 1)[None, :]] - 128
    r = np.clip((298 * yy + 409 * e + 128) >> 8, 0, 255)
    g = np.clip((298 * yy - 100 * d - 208 * e + 128) >> 8, 0, 255)
    b = np.clip((298 * yy + 516 * d + 128) >> 8, 0, 255)
    return np.stack([r, g, b], axis=-1).astype(np.uint8)


def full_range_yuv_to_rgb(Y, U, V) -> np.ndarray:
    """Correct inverse for full-range (JFIF) YUV, at full resolution."""
    h, w = Y.shape
    u = np.repeat(np.repeat(U, 2, 0), 2, 1)[:h, :w] - 128.0
    v = np.repeat(np.repeat(V, 2, 0), 2, 1)[:h, :w] - 128.0
    y = Y.astype(np.float64)
    r = y + 1.402 * v
    g = y - 0.344136 * u - 0.714136 * v
    b = y + 1.772 * u
    return np.clip(np.round(np.stack([r, g, b], -1)), 0, 255).astype(np.uint8)


def nn_resize(rgb: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    src_h, src_w = rgb.shape[:2]
    sx = (np.arange(out_w) * src_w) // out_w
    sy = (np.arange(out_h) * src_h) // out_h
    return rgb[sy[:, None], sx[None, :]]


def bilinear_resize(rgb: np.ndarray, out_w: int, out_h: int) -> np.ndarray:
    return np.asarray(Image.fromarray(rgb).resize((out_w, out_h), Image.BILINEAR), dtype=np.uint8)


# ── Post-processing ──────────────────────────────────────────────────────────


def resolve_roles(a: np.ndarray, b: np.ndarray):
    """Mirror of ObjectDetectorService.resolveClassScoreRoles."""
    def integral(v):
        return bool(np.all(np.isfinite(v) & (v >= 0) & (np.abs(v - np.round(v)) < 1e-6)))
    ai, bi = integral(a), integral(b)
    if ai == bi:
        return None
    return ai


def app_postprocess(outputs, swapped_names_bug: bool = False):
    """Returns (boxes[N,4] ymin,xmin,ymax,xmax normalized, classes[N], scores[N]).

    outputs: list of the 4 output arrays in model output order.
    swapped_names_bug=True reproduces the pre-fix behaviour for the bundled
    model (class and score tensors exchanged).
    """
    boxes_i = next(i for i, o in enumerate(outputs) if o.ndim == 3 and o.shape[-1] == 4)
    count_i = next(i for i, o in enumerate(outputs) if o.size == 1)
    rest = [i for i in range(len(outputs)) if i not in (boxes_i, count_i)]
    cls_i, score_i = rest[0], rest[1]  # post-process op order
    a, b = outputs[cls_i].reshape(-1), outputs[score_i].reshape(-1)
    classes_first = resolve_roles(a, b)
    if classes_first is False:
        a, b = b, a
    if swapped_names_bug:
        a, b = b, a
    n = int(outputs[count_i].reshape(-1)[0])
    n = n if 0 < n <= len(b) else len(b)
    boxes = np.clip(outputs[boxes_i].reshape(-1, 4)[:n], 0.0, 1.0)
    return boxes, a[:n], b[:n]
