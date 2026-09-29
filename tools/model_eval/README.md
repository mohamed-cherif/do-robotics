# Model evaluation harness

Measures the object detector *as the app runs it*: `app_pipeline.py` is a
bit-exact Python copy of the app's camera → YUV → tensor → post-processing
path (keep it in sync with `lib/services/object_detector_service.dart`).

```
python -m venv .venv
.venv\Scripts\activate            # Windows  (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt
python eval_detector.py --with-bug --sweep --latency
```

- `coco_val2017_subset.json`: 500 fixed COCO val2017 images (640×480) and
  their box annotations (CC BY 4.0). Regenerate with `make_subset.py`.
- Images are downloaded on first run into `cache/` (git-ignored); they keep
  their original Flickr licenses and are not redistributed.
- Latency is measured on the machine running the script — useful to compare
  variants, not to predict phone performance.

Results and conclusions: [docs/MODELS.md](../../docs/MODELS.md).

Use it before changing the model, the threshold, the camera resolution or
the preprocessing: a change should not lower AP or person precision.
