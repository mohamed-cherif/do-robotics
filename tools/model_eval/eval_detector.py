"""Reproducible accuracy + latency harness for the app's object detector.

    pip install -r requirements.txt
    python eval_detector.py --model ../../assets/ml/1.tflite

Downloads the images listed in coco_val2017_subset.json (cached in
./cache), runs them through a bit-exact copy of the app's preprocessing
(app_pipeline.py) and reports COCO box AP plus precision/recall for
"person" at the app's confidence threshold. Latency is measured on the
machine running the script (a PC, not a phone) and is only useful for
comparing variants with each other.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import platform
import statistics
import time
import urllib.request

import numpy as np
from PIL import Image
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval

import app_pipeline as ap

HERE = os.path.dirname(os.path.abspath(__file__))
PERSON = 1  # COCO category id


def load_interpreter(path, threads):
    try:
        from ai_edge_litert.interpreter import Interpreter  # preferred runtime
    except ImportError:
        import tensorflow as tf
        Interpreter = tf.lite.Interpreter
    it = Interpreter(model_path=path, num_threads=threads)
    it.allocate_tensors()
    return it


def fetch_images(subset, cache):
    os.makedirs(cache, exist_ok=True)
    for im in subset["images"]:
        p = os.path.join(cache, im["file_name"])
        if not os.path.exists(p):
            urllib.request.urlretrieve(im["coco_url"], p)


# Each variant maps a 640x480 RGB image to the uint8 model input tensor.
def make_variants(in_w, in_h):
    def app(img, full_range=True, size=(320, 240)):
        Y, U, V = ap.rgb_to_yuv420(ap.camera_frame(img, size), full_range=full_range)
        return ap.app_yuv_to_tensor(Y, U, V, in_w, in_h)

    def fixed_decode(img, resize):
        Y, U, V = ap.rgb_to_yuv420(ap.camera_frame(img), full_range=True)
        rgb = ap.full_range_yuv_to_rgb(Y, U, V)
        return resize(rgb, in_w, in_h)

    return {
        # What the app does today (camera assumed to output full-range YUV).
        "app (320x240, studio-swing decode, NN)": lambda im: app(im),
        # Same, but the camera emits limited-range YUV (decode then matches).
        "app, limited-range camera": lambda im: app(im, full_range=False),
        "full-range decode, NN": lambda im: fixed_decode(im, ap.nn_resize),
        "full-range decode, bilinear": lambda im: fixed_decode(im, ap.bilinear_resize),
        # ResolutionPreset.medium (640x480) through the app pipeline.
        "app at 640x480 camera": lambda im: app(im, size=(640, 480)),
        # Upper bound: clean RGB, bilinear straight to the model input.
        "reference RGB, bilinear": lambda im: ap.bilinear_resize(np.asarray(im.convert("RGB")), in_w, in_h),
    }


def run(model_path, subset_path, cache, threshold, variants_filter, bug):
    subset = json.load(open(subset_path, encoding="utf-8"))
    fetch_images(subset, cache)
    with contextlib.redirect_stdout(io.StringIO()):
        gt = COCO(subset_path)
    it = load_interpreter(model_path, threads=4)
    inp = it.get_input_details()[0]
    in_h, in_w = int(inp["shape"][1]), int(inp["shape"][2])
    outs = it.get_output_details()

    variants = make_variants(in_w, in_h)
    if variants_filter:
        variants = {k: v for k, v in variants.items() if any(f in k for f in variants_filter)}
    runs = [(name, fn, False) for name, fn in variants.items()]
    if bug:
        runs.insert(0, ("BEFORE FIX: swapped class/score outputs", variants["app (320x240, studio-swing decode, NN)"] if "app (320x240, studio-swing decode, NN)" in variants else next(iter(variants.values())), True))

    results = []
    for name, fn, swapped in runs:
        dets = []
        for im in subset["images"]:
            img = Image.open(os.path.join(cache, im["file_name"]))
            x = fn(img)
            it.set_tensor(inp["index"], x[None].astype(np.uint8))
            it.invoke()
            boxes, classes, scores = ap.app_postprocess([it.get_tensor(o["index"]) for o in outs], swapped)
            W, H = im["width"], im["height"]
            for (y0, x0, y1, x1), c, s in zip(boxes, classes, scores):
                if s < 0.01 or x1 <= x0 or y1 <= y0:
                    continue
                dets.append({"image_id": im["id"], "category_id": int(c) + 1,
                             "bbox": [float(x0 * W), float(y0 * H), float((x1 - x0) * W), float((y1 - y0) * H)],
                             "score": float(s)})
        results.append((name, evaluate(gt, dets, threshold)))
    return results, (in_w, in_h)


def evaluate(gt, dets, threshold):
    out = {"dets": len(dets)}
    if not dets:
        return {**out, "AP": 0.0, "AP50": 0.0, "person_AP50": 0.0, "person_P": 0.0, "person_R": 0.0}
    with contextlib.redirect_stdout(io.StringIO()):
        dt = gt.loadRes(dets)
        ev = COCOeval(gt, dt, "bbox")
        ev.evaluate(); ev.accumulate(); ev.summarize()
        out["AP"], out["AP50"] = float(ev.stats[0]), float(ev.stats[1])
        evp = COCOeval(gt, dt, "bbox")
        evp.params.catIds = [PERSON]
        evp.evaluate(); evp.accumulate(); evp.summarize()
        out["person_AP50"] = float(evp.stats[1])
    out["person_P"], out["person_R"] = pr_at(gt, dets, PERSON, threshold)
    return out


def iou(a, b):
    ax0, ay0, aw, ah = a
    bx0, by0, bw, bh = b
    ix = max(0.0, min(ax0 + aw, bx0 + bw) - max(ax0, bx0))
    iy = max(0.0, min(ay0 + ah, by0 + bh) - max(ay0, by0))
    inter = ix * iy
    union = aw * ah + bw * bh - inter
    return inter / union if union > 0 else 0.0


def pr_at(gt, dets, cat, threshold, iou_thr=0.5):
    """Precision/recall for one class using only detections the app would report."""
    tp = fp = 0
    n_gt = 0
    by_img = {}
    for d in dets:
        if d["category_id"] == cat and d["score"] >= threshold:
            by_img.setdefault(d["image_id"], []).append(d)
    for img_id in gt.getImgIds():
        gts = [a["bbox"] for a in gt.loadAnns(gt.getAnnIds(imgIds=img_id, catIds=[cat], iscrowd=False))]
        n_gt += len(gts)
        used = set()
        for d in sorted(by_img.get(img_id, []), key=lambda d: -d["score"]):
            best, bi = 0.0, -1
            for i, g in enumerate(gts):
                if i not in used and (v := iou(d["bbox"], g)) > best:
                    best, bi = v, i
            if best >= iou_thr:
                tp += 1
                used.add(bi)
            else:
                fp += 1
    p = tp / (tp + fp) if tp + fp else 0.0
    r = tp / n_gt if n_gt else 0.0
    return p, r


def threshold_sweep(model_path, subset_path, cache, thresholds):
    """Person precision/recall of the app pipeline at several thresholds."""
    subset = json.load(open(subset_path, encoding="utf-8"))
    with contextlib.redirect_stdout(io.StringIO()):
        gt = COCO(subset_path)
    it = load_interpreter(model_path, threads=4)
    inp = it.get_input_details()[0]
    in_h, in_w = int(inp["shape"][1]), int(inp["shape"][2])
    outs = it.get_output_details()
    app = make_variants(in_w, in_h)["app (320x240, studio-swing decode, NN)"]
    dets = []
    for im in subset["images"]:
        it.set_tensor(inp["index"], app(Image.open(os.path.join(cache, im["file_name"])))[None])
        it.invoke()
        boxes, classes, scores = ap.app_postprocess([it.get_tensor(o["index"]) for o in outs])
        for (y0, x0, y1, x1), c, s in zip(boxes, classes, scores):
            if x1 > x0 and y1 > y0:
                dets.append({"image_id": im["id"], "category_id": int(c) + 1,
                             "bbox": [x0 * 640, y0 * 480, (x1 - x0) * 640, (y1 - y0) * 480], "score": float(s)})
    return [(t, *pr_at(gt, dets, PERSON, t)) for t in thresholds]


def latency(model_path, threads_list, runs=60, warmup=5):
    rows = []
    for t in threads_list:
        t0 = time.perf_counter()
        it = load_interpreter(model_path, threads=t)
        load_ms = (time.perf_counter() - t0) * 1000
        inp = it.get_input_details()[0]
        x = np.random.default_rng(0).integers(0, 255, inp["shape"], dtype=np.uint8)
        it.set_tensor(inp["index"], x)
        t0 = time.perf_counter(); it.invoke(); first = (time.perf_counter() - t0) * 1000
        for _ in range(warmup):
            it.invoke()
        times = []
        for _ in range(runs):
            t0 = time.perf_counter(); it.invoke(); times.append((time.perf_counter() - t0) * 1000)
        rows.append((t, load_ms, first, statistics.median(times), sorted(times)[int(0.9 * len(times))]))
    return rows


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", default=os.path.join(HERE, "..", "..", "assets", "ml", "1.tflite"))
    p.add_argument("--subset", default=os.path.join(HERE, "coco_val2017_subset.json"))
    p.add_argument("--cache", default=os.path.join(HERE, "cache"))
    p.add_argument("--threshold", type=float, default=0.35, help="app default confidence")
    p.add_argument("--variants", nargs="*", help="substring filter on variant names")
    p.add_argument("--with-bug", action="store_true", help="also evaluate the pre-fix swapped outputs")
    p.add_argument("--sweep", action="store_true", help="person P/R vs threshold")
    p.add_argument("--latency", action="store_true")
    p.add_argument("--json", help="write results to this file")
    a = p.parse_args()

    print(f"Model: {os.path.basename(a.model)} ({os.path.getsize(a.model)/1e6:.2f} MB) | host: {platform.processor()} ({os.cpu_count()} logical CPUs)")
    report = {"model": os.path.basename(a.model)}
    res, (w, h) = run(a.model, a.subset, a.cache, a.threshold, a.variants, a.with_bug)
    print(f"Input {w}x{h}. {len(json.load(open(a.subset))['images'])} COCO val2017 images. P/R: person, IoU>=0.5, score>={a.threshold}")
    print("| Variant | AP@[.5:.95] | AP50 | person AP50 | person P | person R |")
    print("|---|---|---|---|---|---|")
    for name, r in res:
        print(f"| {name} | {r['AP']*100:.1f} | {r['AP50']*100:.1f} | {r['person_AP50']*100:.1f} | {r['person_P']*100:.0f}% | {r['person_R']*100:.0f}% |")
    report["accuracy"] = {n: r for n, r in res}
    if a.sweep:
        rows = threshold_sweep(a.model, a.subset, a.cache, [0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.6])
        print("\n| threshold | person precision | person recall |\n|---|---|---|")
        for t, pp, rr in rows:
            print(f"| {t:.2f} | {pp*100:.0f}% | {rr*100:.0f}% |")
        report["sweep"] = rows
    if a.latency:
        rows = latency(a.model, [1, 2, 4])
        print("\n| threads | load ms | first invoke ms | median ms | p90 ms |\n|---|---|---|---|---|")
        for t, lm, f, m, p90 in rows:
            print(f"| {t} | {lm:.0f} | {f:.1f} | {m:.1f} | {p90:.1f} |")
        report["latency_pc"] = rows
    if a.json:
        json.dump(report, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
