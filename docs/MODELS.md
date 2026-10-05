# Models

DO Robotics ships one neural network (object detection). Speech
recognition and text-to-speech use the phone's system engines; the line
follower is classical image processing.

## 1. Object detector — EfficientDet-Lite0 (int8)

### Model card

| | |
|---|---|
| File | `assets/ml/1.tflite` (4.56 MB), labels `assets/ml/labelmap.txt` |
| Identity | **EfficientDet-Lite0 detection, TF Hub / Kaggle `tensorflow/efficientdet/tfLite/lite0-detection-default/1`** — byte-identical (SHA-256 `33a3b622c7cac0762f96089353cd61495f3e993968d133af7871bfc2d5396704`). Earlier docs called it "SSD-MobileNet v1, 300×300"; that was wrong. |
| License | Apache-2.0 (TensorFlow models on TF Hub/Kaggle). Trained on COCO 2017 (annotations CC BY 4.0). Credited in `NOTICE`. |
| Input | `[1, 320, 320, 3]` uint8 RGB, 0–255 (quantization scale 1/128, zero point 127 — the model handles normalization) |
| Outputs | TFLite_Detection_PostProcess (NMS inside the model): boxes `[1,25,4]` (ymin, xmin, ymax, xmax, normalized), class ids `[1,25]`, scores `[1,25]`, count `[1]`. Output 1 = classes, output 2 = scores, even though they are *named* `…:2` and `…:1`. |
| Classes | 80 COCO objects (ids 0–89 with gaps; `labelmap.txt` line = id + 1). No "face" class. |
| Runtime | LiteRT 1.4 via `tflite_flutter` 0.12.1, XNNPack on Android created **without options** (plain-CPU fallback), in a background isolate. Passing `XNNPackDelegateOptions` crashes: the package's options struct is smaller than the one LiteRT 1.4 reads. The input goes in as raw bytes, not a nested list. |

### Pipeline in the app

1. Camera: `ResolutionPreset.low` (320×240 on most phones), YUV_420_888.
2. `_directToTensor`: one pass that converts YUV→RGB (integer BT.601
   limited-range formula), rotates by the sensor orientation (plus 180°
   when the phone is mounted upside down, so the model always sees an
   upright picture) and resizes
   (nearest neighbour) to 320×320 — the 4:3 frame is squashed, as in the
   model's own training resize.
3. Inference; outputs resolved by shape (boxes, count) and by value
   (class ids are integers) — see `resolveClassScoreRoles`.
4. Threshold (default 0.35, user-adjustable), optional label filter. Each
   box is kept upright (robot frame, used for steering) and mapped to
   screen space (for the overlay).
5. Tracking in `VisionService.associate` (IoU + distance). A lock is
   held for 1 s without a detection; detections between 0.2 and the
   threshold only continue an existing lock on an overlapping box of the
   same label. Results older than 1.5 s are ignored.

### Measured accuracy

`tools/model_eval` runs a bit-exact Python copy of steps 1–3 on a fixed
subset of **500 COCO val2017 images** (640×480; 3,913 objects, 1,119
people in 249 images). "P/R" = precision/recall for *person* at IoU ≥ 0.5
using only detections the app would report (score ≥ 0.35).

| Variant | AP@[.5:.95] | AP50 | person AP50 | person P | person R |
|---|---|---|---|---|---|
| **Before the output-role fix** (what the app did until this audit) | 0.0 | 0.0 | 0.0 | 0 % | 2 % |
| **App pipeline today** (camera assumed full-range YUV) | 24.5 | 38.9 | 55.8 | 82 % | 43 % |
| App pipeline, camera emits limited-range YUV | 25.3 | 40.2 | 55.5 | 83 % | 44 % |
| Full-range YUV decode, nearest neighbour | 25.2 | 39.6 | 56.3 | 83 % | 45 % |
| Full-range YUV decode, bilinear | 24.7 | 38.4 | 54.8 | 82 % | 44 % |
| App pipeline with a 640×480 camera (`ResolutionPreset.medium`) | 25.9 | 41.3 | 55.3 | 81 % | 44 % |
| Reference: clean RGB, bilinear (upper bound) | 26.4 | 41.3 | 56.5 | 83 % | 45 % |

For comparison, the SSD-MobileNet v1 quantized model that was also in the
repo (`detect.tflite`, not used by the app) scores **AP 16.3 / person AP50
37.6 / person precision 40 %** through the same pipeline.

Person precision/recall vs. confidence threshold (app pipeline):

| threshold | 0.25 | 0.30 | **0.35** | 0.40 | 0.45 | 0.50 | 0.60 |
|---|---|---|---|---|---|---|---|
| precision | 65 % | 76 % | **82 %** | 91 % | 94 % | 96 % | 98 % |
| recall | 52 % | 46 % | **43 %** | 39 % | 37 % | 33 % | 23 % |

Recall looks low because COCO counts every tiny or occluded person; a
person in front of a desk robot is a large, easy target.

### Measured latency (PC — for relative comparison only)

Intel Core Ultra 7 255U laptop, TensorFlow Lite 2.21 with XNNPack,
random input, 60 runs after 5 warm-ups:

| threads | first invoke | median | p90 |
|---|---|---|---|
| 1 | 49.8 ms | 41.2 ms | 61.5 ms |
| 2 | 26.8 ms | 25.0 ms | 40.3 ms |
| 4 | 18.5 ms | 21.6 ms | 26.9 ms |

### Measured latency (phones)

| Phone | Model (invoke) | Whole frame (convert + model + results) | How |
|---|---|---|---|
| Pixel 9, Android 17 | 40–43 ms | 42–45 ms | "Timing" log line (average of 50 frames), 7 batches, Camera page, *Fast* |
| Pixel 9, before the fix (nested-list input, XNNPack options) | — | 460–495 ms (HUD) | camera HUD |
| x86_64 emulator, for comparison | 95 ms with XNNPack, 2004 ms without | +4 ms | "Timing" log line |

The app writes `Timing (last 50 frames): model … ms, whole frame … ms` to
the log (`adb logcat | grep Timing`). **Not measured:** a 4 GB mid-range
phone, memory and power. Google's published figure for EfficientDet-Lite0
is ~37 ms on a Pixel 4 CPU with 4 threads (TFLite Model Maker
documentation); collect more numbers with the device checklist.

### Conclusions and decisions

- **Keep EfficientDet-Lite0 int8.** It is already quantized (no further
  INT8/FP16 win on CPU), and it beats SSD-MobileNet v1 by +8 AP and doubles
  person precision for ~1.5× the PC latency. EfficientDet-Lite1 (384 px)
  would add accuracy at roughly twice the cost — not right for low-end
  phones; could be an opt-in "accurate" model later.
- **The biggest accuracy problem was a post-processing bug, not the model**
  (swapped outputs → AP 0). Fixed and covered by tests.
- **Preprocessing is fine.** The app loses 1.9 AP vs. the clean-RGB upper
  bound; 1.4 of that is the 320×240 camera. Nearest-neighbour resizing is
  not worse than bilinear here. Whether the YUV decode should use
  full-range constants (+0.7 AP) depends on each phone's camera — check
  Y-plane min/max on real devices before changing it.
- **Threshold:** 0.35 favours recall; 0.40 gives 91 % precision for −4
  points recall and may suit following robots better (fewer "ghost"
  targets). Left at 0.35 (user-adjustable); owner decision.
- **Speed/battery:** the new Performance setting (Battery saver / Balanced
  / Fast) caps frames and threads. Warm-up inference was measured as a
  small effect on PC (first invoke ≈ median) and was not added.
- **Hardware acceleration:** CPU/XNNPack. GPU delegate and NNAPI not used
  (see docs/AUDIT_2026-09.md).

### Known limitations and biases

- Trained on COCO: everyday Western indoor/outdoor photos. Expect weaker
  results for unusual viewpoints (a robot's knee-height camera looking
  up), low light, motion blur while the robot turns, and objects under ~30
  px in the 320×240 frame (≈ 1.5–2 m for a ball).
- "person" covers everyone; COCO has known demographic imbalances, so
  detection rates can differ across skin tones, clothing and ages. Don't
  build anything security-relevant on it (the "AI Guard" tutorial is a
  toy).
- Only 80 classes; no faces, no hands, no custom objects.

### Reproduce

```
cd tools/model_eval
python -m venv .venv && .venv/Scripts/activate      # or source .venv/bin/activate
pip install -r requirements.txt
python eval_detector.py --with-bug --sweep --latency
python eval_detector.py --model ../../assets/ml/detect.tflite --variants "app (320" reference --latency
```

The first run downloads the 500 images (~80 MB) into `tools/model_eval/cache/`.

## 2. Speech recognition

System recognizer via `speech_to_text` 7.3 (Android `SpeechRecognizer`,
usually Google; iOS `SFSpeechRecognizer`). No model ships with the app.

- **Privacy:** on most Android phones audio is sent to the recognizer's
  cloud service unless an offline language pack is installed. Disclose this
  (SECURITY.md does). `speech_to_text` has an `onDevice` option that could
  become a setting.
- **Accuracy:** not measured (no audio test set in this audit). Matching is
  whole-word and ordered (`ScriptUtils.matchesPhrase`), so "stop" does not
  fire on "stopwatch"; accents and background noise are handled only by
  the system engine.
- **Robustness added in this audit:** restart back-off on repeated errors,
  fatal errors stop the restart loop, single owner of the recognizer.

## 3. Text-to-speech

System engine via `flutter_tts`. The robot can hear itself while speaking
(no audio-focus coordination yet).

## 4. Line detector (no ML)

Sobel edge energy in the bottom 40 % of the upright frame. Now rotation-
aware; covered by synthetic tests in `test/line_detection_test.dart`. Not
evaluated on real floor footage.
