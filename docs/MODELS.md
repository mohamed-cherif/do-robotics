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
   upright picture) and resizes (nearest neighbour) into the 320×320
   input. Where the picture goes is `pictureArea`:
   - phone upright: the 240×320 picture is stretched to 320×320 (4/3
     wider);
   - phone on its side: the 320×240 picture keeps its proportions at the
     top of the input, with grey (127) below.

   The model was *not* trained on squashed pictures: the automl
   EfficientDet input pipeline normalizes ((x − 127) / 128), resizes
   keeping the aspect ratio and pads the bottom/right with 0, i.e. grey
   127. Stretching the sideways picture taller cost 2.7 person AP; the
   upright picture is better stretched than padded (see "Phone upright vs
   on its side" below). Boxes are mapped back to the picture by
   `modelBoxToUpright` (boxes only on the padding are dropped).
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

The tables above were measured on landscape images with the 4:3 picture
stretched to the square input, as the app did in every orientation until
October 2026; `tools/model_eval` still runs that pipeline.

### Phone upright vs on its side (measured on COCO val2017)

Every val2017 image of exactly 640×480 (**1,061 landscape**, 8,777
objects, 2,318 people) or 480×640 (**336 portrait**, 2,044 objects, 564
people). Each is shrunk to the camera's 320×240 / 240×320 (bilinear, like
the camera's own scaling), turned into the sensor's orientation and
converted to YUV 4:2:0, then fed through a Python copy of
`_directToTensor` with the rotation the app uses on a Pixel-style 90°
sensor (0 = phone on its side, 90 = upright). Boxes are mapped back to the
original image (one-off scripts, not in the repo). AP / AP50 / AR@100:
pycocotools, all 80 classes. "P / R" = precision / recall at the app's
threshold 0.35, IoU ≥ 0.5. Sports balls are left out: 33 and 3 of them,
too few to compare.

| Phone | Input | AP | AP50 | AR@100 | person AP | person P / R | bottle P / R | cup P / R | all classes P / R |
|---|---|---|---|---|---|---|---|---|---|
| on its side | stretched (before) | 23.7 | 38.2 | 30.6 | 29.5 | 83 / 45 % | 55 / 18 % | 52 / 21 % | 75 / 32 % |
| on its side | **proportions kept, grey below (now)** | 23.9 | 37.7 | 30.6 | **32.2** | 82 / 48 % | 62 / 18 % | 58 / 20 % | 74 / 34 % |
| on its side | proportions kept, centred, grey | 23.1 | 36.5 | 29.9 | 31.6 | 82 / 47 % | 62 / 16 % | 54 / 19 % | 74 / 33 % |
| on its side | proportions kept, black below | 23.5 | 37.4 | 30.3 | 31.8 | 83 / 47 % | 63 / 18 % | 56 / 19 % | 74 / 33 % |
| upright | **stretched (before and now)** | 30.0 | 45.4 | 36.4 | 37.2 | 87 / 55 % | 77 / 17 % | 61 / 29 % | 75 / 40 % |
| upright | proportions kept, grey right | 29.4 | 46.6 | 35.3 | 36.1 | 86 / 54 % | 73 / 16 % | 66 / 28 % | 75 / 39 % |
| upright | proportions kept, centred, grey | 29.3 | 45.0 | 35.3 | 36.7 | 86 / 53 % | 71 / 17 % | 68 / 30 % | 77 / 40 % |

Paired bootstrap over images (200–300 resamples, 95 % interval), keeping
proportions minus stretching: on its side, person AP **+2.7 [+1.9,
+3.4]**, all-class AP +0.4 [−0.2, +1.0]; upright, person AP −1.1 [−2.7,
+0.5], all-class AP −0.3 [−1.8, +1.1]. Small objects lose a little when
the sideways picture is no longer stretched (AP-small 6.2 → 4.6; it had
4/3 more rows), large ones gain (45.0 → 46.8).

The two orientations are different photos, so their rows can't be
compared with each other directly. To isolate the stretch, the central
480×480 square of all 1,397 images was shrunk to 240×240 and stretched
4/3 taller (what the sideways phone did) or 4/3 wider (what the upright
phone does), same content: person AP 29.9 vs 32.8 (+2.8 [+2.0, +3.7] for
wider), person recall at 0.35 46 vs 49 %, median score of the people
found 0.54 vs 0.63; all-class AP 23.3 vs 23.0. People and bottles are
taller than wide, so stretching them taller takes them further from
anything the model was trained on, and their scores sink towards the
threshold. That is a real but modest part of "sideways is worse"; the
rest is probably the scene: on its side the camera sees 25 % less
height, so a standing person is cut off or has to be further away.

A 640×480 camera with the old stretch scored AP +1.4 in both orientations
(L 25.0, P 31.3; intervals exclude 0) but no person gain on its side
(29.7), and keeping proportions gains nothing from it (the picture is
320×240 in the input either way); see the decisions below.

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
- **Phone on its side: keep the proportions** (October 2026). The
  sideways picture is no longer stretched taller: person AP +2.7, people
  found at 0.35 +3 points, all-class AP unchanged within noise; the
  upright picture is still stretched, so portrait results are bit-for-bit
  the same. Not adopted: padding the upright picture too (person AP −1.1),
  centring (−0.8 AP), black padding (−0.4 AP vs grey).
- **Camera 640×480** would add ~1.4 AP to the old stretch in both
  orientations but nothing to the sideways picture now, costs 4× the
  bytes per frame and on Android `ResolutionPreset.medium` is 720×480
  (3:2, a cropped view). Not changed; test on phones first if wanted.
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
