# Architecture

DO Robotics is one Flutter app (Dart, ~17k lines in `lib/`) plus three
Arduino sketches. The phone does all the thinking; the board is a pin server
with a watchdog.

```
                         ┌──────────────── UI (lib/ui) ────────────────┐
                         │ Dashboard (Home / Blocks / Python tabs)     │
                         │ logic_page ─ block editor   python_page     │
                         │ vision_page, sensor pages, settings, tutorials
                         └───────┬──────────────────────────┬──────────┘
                                 │ play/stop                │ run/stop
                   ┌─────────────▼─────────┐     ┌──────────▼───────────┐
                   │ BlockScriptRunner     │     │ PythonScriptRunner    │
                   │ (lib/logic)           │     │ + RoboPython          │
                   │ walks BlockInstance   │     │   (lib/python)        │
                   │ trees                 │     │ robot module → RobotApi
                   └───┬─────────┬─────────┘     └───┬──────────┬────────┘
       sensors (read)  │         │ actuators         │          │
   ┌───────────────────▼──┐   ┌──▼──────────────────▼──┐        │
   │ VisionService         │   │ ActuatorDriver          │        │
   │  └ ObjectDetector     │   │ (per-pin de-dup cache)  │        │
   │    (TFLite isolate)   │   └──────────┬──────────────┘        │
   │ SensorService (IMU)   │              │ packets               │
   │ VoiceService (STT/TTS)│   ┌──────────▼──────────────┐        │
   └───────────────────────┘   │ ConnectivityManager     │◀───────┘
                               │  BLE | USB | WiFi TCP   │
                               └──────────┬──────────────┘
                                          │ 0xAA control / 0xAB text frames
                               ┌──────────▼──────────────┐
                               │ arduino/*.ino firmware  │
                               └─────────────────────────┘
```

## Layers

| Layer | Where | Notes |
|---|---|---|
| UI | `lib/ui/` | Plain `StatefulWidget`s, no state-management package. Services are singletons (`Foo()` returns the instance). |
| Program runners | `lib/logic/` | `BlockScriptRunner` (blocks), `PythonScriptRunner` (RoboPython), `ScriptValidator` (checks before RUN), `CodeGenerator` (blocks → Python), `ActuatorDriver` (intent → packets), `RobotApi` (the facade the Python `robot` module uses; faked in tests). |
| Models | `lib/models/` | `BlockDefinition` (what a block is), `BlockInstance` (a placed block: input values, nested slots, `nextBlock` chain, JSON save/load), `BlockFactory` (all definitions), `ActuatorConfig`, tutorials. |
| Python | `lib/python/` | Lexer → parser → async tree-walking interpreter with builtins and the `robot` module. |
| Services | `lib/services/` | Camera/vision, IMU, voice, preferences, connectivity, `PlatformService` (the app's own platform channel), `AppLifecycleGuard`. |
| Utilities | `lib/utils/` | `ExecutionLogger` (the 100-line program log), `SharedLease` (serialized, ref-counted open/close). |
| Firmware | `arduino/` | ESP32 (BLE + WiFi + USB), Uno, Mega (USB). Same control packets everywhere. |
| Tools | `tools/model_eval/` | Python harness that measures the detector exactly as the app runs it. |

## Running a program

1. **RUN** in the Blocks tab → `ScriptValidator` → `BlockScriptRunner.play()`
   with the root blocks sorted top-to-bottom.
2. The runner creates a `_Run` token. Everything it awaits checks
   `run.active`, so STOP (or a new run) can never be confused with an old
   run that is still unwinding.
3. It starts only what the program uses: IMU always; the microphone if a
   voice block is present; the camera if a vision block is present (and
   waits for the first processed frame).
4. Blocks execute: statements run, sensor/boolean/math blocks are
   evaluated by their parent. Loops yield to the event loop every iteration.
5. Device blocks go through `ActuatorDriver` → `ConnectivityManager` →
   5-byte packets. Unchanged values aren't resent; the cache is cleared on
   every link change and on the firmware's `WATCHDOG` message.
6. STOP (or the end of the program, or the app going to the background):
   release the camera/mic, then `stopAll` (per-device stop + firmware
   STOP_ALL).

The Python runner follows the same lifecycle; the two runners refuse to
run at the same time. While any program runs, `AppLifecycleGuard` keeps the
screen on and samples the IMU at game rate.

## Shared resources: the lease rule

The camera and the microphone are shared by pages (Camera, Microphone) and
the runners. Both are **reference-counted**:

- every `VisionService.startStream()` is balanced by exactly one
  `stopStream()`, even if the start threw;
- every `VoiceService.startListening()` by one `stopListening()`.

`SharedLease` serializes the camera's open/close, so a release that arrives
while the camera is still opening is applied after it (this used to leak
the camera). Break this rule and the camera or mic stays on.

## Vision pipeline

`CameraController` (320×240 YUV on Android) → `VisionService._onCameraImage`
→ `ObjectDetectorService.processFrame` (throttled by the Performance
setting, skipped while the isolate is busy) → background isolate:
single-pass YUV→RGB + rotation + nearest-neighbour resize → TFLite
(EfficientDet-Lite0, XNNPack) → each box twice: `uprightBox` in the
robot's frame and `boundingBox` in portrait display space → back to
`VisionService`, which tracks the locked object (IoU + distance) and
exposes `targetOffsetX/Y`, `targetArea`, `isLocked` from the upright box.

The UI is locked to portrait. The phone may be mounted upright or upside
down (`PhoneMount`: Automatic uses gravity via `MountDetector`, or fixed):
upside down, the frame is rotated 180° more so the model always sees an
upright picture, and only the overlay is turned back to match the screen.
Steering values therefore never depend on the mount. Results older than
1.5 s count as "nothing seen". In line-follow mode the isolate runs a Sobel
detector on the luminance plane instead. Details and measurements:
[MODELS.md](MODELS.md).

## Connectivity

`ConnectivityManager` owns one `RobotConnection` strategy at a time
(Bluetooth LE Nordic UART, USB serial at 115200, or WiFi TCP port 4210) and
a `FrameParser` for bytes coming back. Every strategy sends a heartbeat
every 500 ms; the firmware stops all outputs after 2 s of silence. Text
frames (`0xAB`) carry WiFi setup and status, and the board's `ERR` /
`WATCHDOG` messages, which `ConnectivityManager.logLineFor` puts in the
program log. The sketches' logic is tested on the computer by
`arduino/test/` (the `.ino` files compiled unchanged against small
stand-ins for the Arduino, BLE and WiFi APIs). Protocol constants live only in
`robot_protocol.dart` and must be mirrored in all three sketches.

## Persistence

`SharedPreferences` only: configured actuators, saved block scripts
(`saved_scripts/<name>`), the block editor's autosaved draft, Python scripts
and draft, vision settings, last transport and WiFi host. Block scripts are
JSON (`BlockInstance.listToJson` / `loadScript`, which never throws and
reports skipped blocks).

## Adding things

- **A block:** definition in `block_factory.dart` (and a palette list),
  behaviour in `block_script_runner.dart`, Python in `code_generator.dart`,
  checks in `script_validator.dart` if it has slots that can be empty; tests
  in `test/block_runner_test.dart` / `test/block_models_test.dart`.
- **A Python API:** `RobotApi` + `LiveRobotApi` (`robot_api.dart`), expose it
  in `robot_module.dart`, extend `FakeRobotApi` in the tests.
- **A protocol command:** `robot_protocol.dart` + all sketches + README
  table; keep old firmware working.
- **A native capability:** add a method to `PlatformService` and implement
  it in `MainActivity.kt` (and `AppDelegate.swift`); unknown platforms must
  degrade to a no-op.

## Testing

`flutter test` covers the protocol, frame parser, block JSON, the block
runner (logic blocks), the validator, code generation, the Python
interpreter and `robot` module (with a fake robot), vision/sensor math, the
line detector, the camera lease, and the block editor at phone size.
Hardware behaviour is covered by the manual
[DEVICE_TEST_CHECKLIST.md](DEVICE_TEST_CHECKLIST.md).
