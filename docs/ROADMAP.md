# DO Robotics — review findings and roadmap (2026-09-12)

## What was fixed in this pass

| # | Severity | Area | Problem | Fix |
|---|----------|------|---------|-----|
| 1 | Critical | Vision | Fresh installs never detected anything: default label filter was the old ML Kit set (`Face`, `Fashion item`) which no COCO label matches, so every detection was dropped until the user opened the filter sheet. | Label filter defaults to empty (= all). Settings page rewritten around the real COCO list. |
| 2 | Critical | Line follower | Line mode was only enabled if a line block was a *root* block; the snippet nests it inside `while`, so Sobel never ran and `Line Visible` was always false. | Recursive tree scan (`ScriptUtils.usesLineFollowing`). |
| 3 | High | Sensors | `Phone Tilted` used the gravity-removed accelerometer, so a stationary tilted phone read as not tilted. Dashboard card had the same bug. | Uses gravity-based pitch/roll, threshold 25°. |
| 4 | High | Vision | If the TFLite model failed to load, the isolate silently dropped frames and the `_isProcessing` flag never cleared — vision froze for the session. | Isolate always replies. |
| 5 | High | Safety | Nothing stopped the motors if BLE dropped, the app crashed, or the phone went out of range. | Firmware watchdog (2 s), STOP_ALL command, heartbeats on all three transports, failsafe on BLE/WiFi disconnect. |
| 6 | High | Protocol | Values > 255 (servo `maxAngle` default 3000, unclamped motor speed) produced invalid bytes that desynced the firmware state machine. | Single `RobotProtocol.buildPacket` clamps every field; runner clamps to actuator ranges. |
| 7 | Medium | Motors | A PWM-only motor (no IN1/IN2) was never driven: the runner logged "in1 not configured" and returned. | PWM-only path drives the enable pin directly. |
| 8 | Medium | Voice | `contains()` matching: "stop" fired on "stopwatch"; sessions timed out early. | Whole-word ordered matching; `listenFor` 60 s / `pauseFor` 8 s. |
| 9 | Medium | BLE | Picked the *last* writable characteristic on any service; no heartbeat; scan timeout raced the connect. | Prefers Nordic UART RX UUID, heartbeat, timer cleanup. |
| 10 | Medium | Camera | Leaving the camera page while a script ran killed the script's camera. | Ref-counted stream users. |
| 11 | Medium | Runner | `Repeat` with a string count crashed; `stop()` ran twice per program (double stop-all); long `Wait` ignored STOP. | Lenient parsing, idempotent stop, sliced waits. |
| 12 | Low | Sensors | IMU sampled at the platform default (~200 ms on Android) — tilt steering felt laggy. | 20 ms game interval. |
| 13 | Low | ESP32 | Firmware lacked `SERVO_WRITE_US`, so continuous servos only worked on Uno/Mega. | Added. |
| 14 | Low | Dashboard | A leftover `LogicManager` rule fired pin 2 on the label "Person" (never matched due to case). | Removed. |
| 15 | Low | Build | `google_mlkit_*` and `noise_meter` were imported by unreachable pages only (≈ 10 MB APK). | Dependencies removed; dead pages left in place for you to delete. |

Also: analyzer went from 14 warnings / 79 infos to **0 issues**; 25 unit tests added
(protocol, block JSON round-trip, code generator, voice matching, tracking
association, sensor math); README rewritten.

## Improvements shipped

- **Vision:** XNNPack now uses up to 4 threads; frame planes cross the isolate with
  `TransferableTypedData` (one copy instead of two); row/column maps precomputed
  (no per-pixel divisions); output tensors resolved by shape/name instead of
  assumed order; boxes clamped; line detector uses an energy-weighted centroid so
  tape with two edges resolves to its middle; per-frame inference time shown in
  the camera HUD; confidence threshold and upside-down mounting are user settings.
- **New blocks:** If/Else, Say (text-to-speech), Stop Program.
- **Connectivity:** transport choice and WiFi address persist; WiFi host prompt;
  TCP_NODELAY; USB port waits for the AVR bootloader.
- **Actuators:** pin conflicts now include IN1/IN2 pins.

## Update (same day): Python and ESP32 wireless shipped

Decisions taken: **Python subset interpreted in-app** (not C++, not full
CPython) and **ESP32 joins the home WiFi with mDNS** (hotspot kept as fallback).
Design: `docs/superpowers/specs/2026-09-12-python-and-esp32-wireless-design.md`.

Shipped:
- `lib/python/` interpreter (lexer, parser, async tree-walker, builtins, `robot`
  module), `PythonScriptRunner`, Python tab with editor/console/examples,
  "Convert to Python" from blocks, 47+ unit tests.
- Shared `ActuatorDriver` and `VoiceService` used by both runners.
- Framed text channel (0xAB) in both directions, ESP32 WiFi station mode with
  NVS credentials, `robot.local` mDNS, BLE TX notifications and auto-reconnect,
  WiFi setup dialog and "Find robot" discovery in the app.

The section below is kept for the record of the options that were weighed.

## Text programming — should it be C++?

Short answer: the *brain* is the phone, so C++ cannot be the runtime without
rewriting the app in native code; the Arduino is deliberately a dumb pin server.
What you want is a **text language that runs on the phone** with a C-family
syntax so it feels like Arduino.

| Option | Feel | Effort | Trade-offs |
|--------|------|--------|-----------|
| **A. JavaScript via QuickJS (`flutter_js`)** — recommended | `setup()`/`loop()` Arduino style, braces and semicolons | Medium | Battle-tested engine, async `await robot.wait()`, syntax highlighting exists. Native dependency; needs a small bridge for sensor reads. |
| B. Lua via `lua_dardo` | `if … then … end` | Low–Medium | Pure Dart (works in tests, no native build), coroutines make `wait` trivial. Syntax is not C-like. |
| C. Custom "RoboC" mini-language | Exactly Arduino C++ subset | High | Full control, great teaching story. 1.5–2k lines of interpreter to write and maintain. |
| D. Export Arduino C++ sketch | Real C++ on the board | Medium | Only works for programs that need no phone sensors — most of the interesting ones do. Useful as an *addition* for standalone timing/LED projects. |

Proposed API (same names in blocks, generated code and the editor):

```js
const left = robot.motor("Left Wheel"), right = robot.motor("Right Wheel");
function loop() {
  if (robot.vision.locked("person")) {
    const x = robot.vision.offsetX;            // -1 .. 1
    left.forward(200 - 120 * x); right.forward(200 + 120 * x);
  } else { left.stop(); right.stop(); }
  robot.wait(0.02);
}
```

Plan if approved: (1) `RobotApi` facade the runner already uses, (2) JS runtime
+ bridge, (3) editor tab with highlighting and the same RUN/STOP and log,
(4) "View Code" becomes "Convert to JavaScript" (one-way, then editable).

## Roadmap (ranked by impact ÷ effort)

1. **Sensor feedback from the board** — reverse packets `[0xBB][ID][HI][LO][CK]`
   for ultrasonic distance, bumpers, encoders, battery voltage. Unlocks obstacle
   avoidance, odometry and low-battery stop. Firmware + protocol + 3 blocks.
2. **Gyro-based motion primitives** — `Turn 90°`, `Drive straight 1 s` using yaw
   integration and a P-controller. Turns stop being open-loop guesses.
3. **Text programming** (above).
4. **Hardware presets** — one-tap configs for L298N 2WD car, TB6612, ESP32-CAM
   rover, servo arm, with pin diagrams.
5. **Vision upgrades** — EfficientDet-Lite0 int8 with NNAPI/GPU delegate (faster
   and more accurate than SSD-MobileNet v1 2018), ArUco/AprilTag markers for "go
   to marker 3" navigation, colour-blob tracking block (the `ColorTracker` class
   exists but is unwired), face tracking for social robots.
6. **Live telemetry while running** — sensor gauges, target crosshair, command
   rate, in the Code tab instead of a separate log page.
7. **Wake word + intent phrases** — "hey robot, go to the kitchen" via on-device
   keyword spotting; voice commands with parameters ("turn left 45").
8. **Share programs** — export/import scripts as JSON via QR code or link.
9. **AI copilot** — describe a behaviour in plain language, get a block program
   (Claude API, key stored on device). Big wow factor for teaching.
10. **Project hygiene** — `git init`, `.gitignore` for `build/`, `*.txt` logs, STL
    files moved to `hardware/`; GitHub Actions running `flutter analyze` + `flutter test`.

## Decisions needed from you

1. Delete the unreachable files `lib/ui/brain_explorer_page.dart`,
   `lib/ui/simple_detector_page.dart`, `lib/logic/logic_manager.dart`? (They
   compile but are not linked from anywhere.)
2. Approve option A (JavaScript) for text programming, or pick another.
3. Which board are you actually running most — ESP32 or Uno? It changes whether
   sensor feedback should go over BLE notify or serial first.
