# DO Robotics — your phone is the robot's brain

A Flutter app that turns an Android/iOS phone into the controller for a
hobby robot. The phone supplies the expensive parts (camera + object
detection, microphone + speech recognition, IMU, compass, speaker, battery,
radios) and a cheap microcontroller (ESP32, Arduino Uno/Mega) does nothing but
drive pins. Programs are written as drag-and-drop **blocks** or as **Python**
and run on the phone.

```
┌────────────── phone (this app) ──────────────┐        ┌── controller ──┐
│ camera → TFLite EfficientDet-Lite0 → track   │  BLE   │ ESP32 / Uno /  │
│ mic    → speech-to-text / loudness           │  USB   │ Mega running   │
│ IMU    → tilt / shake / yaw / compass        │◀─WiFi─▶│ arduino/*.ino  │
│ blocks → BlockScriptRunner                   │ framed │ motors, servos │
│ python → RoboPython interpreter (lib/python) │ bytes  │ LEDs, buzzers  │
│ TTS    → "Say" block / robot.say()           │        │ WiFi + mDNS    │
└──────────────────────────────────────────────┘        └────────────────┘
```

## Python

The **Python** tab runs a Python subset ("RoboPython") interpreted on the
phone: ints/floats/strings/lists/dicts, `if/elif/else`, `while`, `for … in
range()`, `def`, f-strings, `time`, `math`, `random`. No classes, no
`try/except`, no third-party imports. Blocks convert to Python with
**Blocks → ⋮ → Convert to Python**.

```python
import robot

left  = robot.motor("Left Wheel")
right = robot.motor("Right Wheel")

while True:
    if robot.vision.lock("person"):
        x = robot.vision.offset_x          # -1 (left) .. 1 (right)
        left.forward(int(160 + 90 * x))
        right.forward(int(160 - 90 * x))
        if robot.vision.size > 30:         # close enough
            left.stop(); right.stop()
            robot.say("Found you")
            break
    else:
        left.stop(); right.stop()
    robot.wait(0.02)
```

API summary (full reference in the app under ⋮ → API reference):

| Object | Members |
|---|---|
| `robot.motor(name)` | `.forward(speed)`, `.backward(speed)`, `.stop()`, `.speed(±v)` |
| `robot.servo(name)` | `.angle(deg)` or, for continuous servos, `.forward(pct)`, `.backward(pct)`, `.stop()` |
| `robot.led/buzzer/switch(name)` | `.on()`, `.off()`, `.toggle()`, `.is_on` |
| `robot.vision` | `.detected`, `.lock(label)`, `.locked`, `.label`, `.offset_x/.offset_y`, `.size`, `.objects`, `.line_visible`, `.line_offset`, `.unlock()` |
| `robot.imu` | `.pitch`, `.roll`, `.yaw_rate`, `.shaking`, `.tilted`, `.spinning` |
| `robot.compass` | `.heading`, `.facing("North" \| degrees)` |
| `robot.mic` | `.loud`, `.heard(phrase)`, `.words` |
| `robot` | `.say(text)`, `.wait(s)`, `.stop_all()`, `.stop()`, `.log(...)`, `.connected`, `.actuators`, `.pin.digital/pwm/servo(pin, v)` |

## Quick start

1. Flash one of the sketches in `arduino/` (`receiver` for ESP32, `receiver_uno`,
   `receiver_mega`). The ESP32 advertises as **ESP32 Robot** over BLE and also
   opens a WiFi AP `ESP32_Robot` / `12345678` with a TCP server on `192.168.4.1:4210`.
2. `flutter pub get && flutter run` on a physical phone (camera/BLE do not work
   in emulators).
3. Home → **Configure Hardware**: add your motors (PWM pin + IN1/IN2), servos, LEDs.
4. Code tab → **Snippets** → load *Motor Forward Test*, press RUN.

## Wire protocol

Every transport sends the same 5-byte packet, defined once in
`lib/services/connectivity/robot_protocol.dart` and mirrored in each sketch:

```
[0xAA][CMD][PIN][VALUE][CHECKSUM]     CHECKSUM = (0xAA + CMD + PIN + VALUE) % 256
```

| CMD  | Name           | VALUE                                           |
|------|----------------|-------------------------------------------------|
| 0x00 | HEARTBEAT      | ignored — sent every 500 ms by the app          |
| 0x01 | DIGITAL_WRITE  | 0 = LOW, 1 = HIGH                               |
| 0x02 | ANALOG_WRITE   | 0–255 PWM duty                                  |
| 0x03 | PIN_MODE       | 0 = INPUT, 1 = OUTPUT, 2 = INPUT_PULLUP          |
| 0x04 | SERVO_WRITE    | angle 0–180                                     |
| 0x05 | SERVO_WRITE_US | continuous servo, (µs − 1300) / 2 → 100 = stop  |
| 0x06 | STOP_ALL       | ignored — every driven pin LOW, servos to 1500 µs |

**Failsafe:** the firmware stops every output it has driven if no packet
arrives for 2 s (link loss, app crash, phone out of range), on BLE disconnect,
and when the WiFi client drops. The app also sends STOP_ALL when a program halts.

**Text frames** share the same byte stream in both directions and carry
configuration and status (`lib/services/connectivity/frame_parser.dart`):

```
[0xAB][LEN][LEN bytes of tab-separated text][CHECKSUM]   CHECKSUM = sum of all preceding bytes % 256
```

| phone → board | board → phone |
|---|---|
| `WIFI\t<ssid>\t<password>` join a network (saved in NVS) | `HELLO\tesp32\t2.0` on connect |
| `NAME\t<hostname>` mDNS / BLE name | `WIFI\tCONNECTED\t<ip>` / `WIFI\tFAILED\t<why>` / `WIFI\tAP\t192.168.4.1` |
| `STATUS` | `STATUS\tsta=…\tip=…\tap=…\tname=…\tble=…\tuptime=…` |
| `FORGET` erase credentials | `OK\t…` / `ERR\t…` / `WATCHDOG\tlink lost` |

Uno/Mega answer every text command with `ERR\tunsupported`.

### ESP32 wireless setup

1. Flash `arduino/receiver/receiver.ino`. The board advertises **ESP32 Robot**
   over Bluetooth and starts the hotspot `ESP32_Robot` (password `12345678`).
2. In the app, connect over **Bluetooth** (or USB), then open the connection
   menu → **Set up robot WiFi** and enter your home network. The board joins it,
   announces itself as `robot.local`, and reports its IP.
3. From then on choose **WiFi → Find robot** (mDNS) or type `robot.local`.
   The hotspot keeps working as a fallback at `192.168.4.1:4210`.

Bluetooth reconnects automatically (5 attempts, 2 s apart) after a drop.

## Project layout

| Path | What lives there |
|------|------------------|
| `lib/logic/block_script_runner.dart` | Block interpreter. Evaluates conditions, drives actuators, runs the Smart Follow controller. `ScriptUtils` holds the pure helpers (voice matching, tree scans). |
| `lib/python/` | RoboPython: `lexer`, `parser`, `interpreter` (async, cancellable), `builtins`, `robot_module` (the `robot` API over `RobotApi`). |
| `lib/logic/python_script_runner.dart` | Runs Python with the block runner's lifecycle (start subsystems, stop-all, release camera/mic). |
| `lib/logic/robot_api.dart`, `actuator_driver.dart` | `RobotApi` facade (fakeable in tests) and the shared motor/servo/LED driver with per-pin de-duplication. |
| `lib/services/voice_service.dart` | Speech recognition with auto-restart, loudness, text-to-speech. |
| `lib/ui/python_page.dart` | Python editor with highlighting, line numbers, console, examples. |
| `lib/models/block_factory.dart` | Every block definition (sensors, logic, math, per-actuator blocks). |
| `lib/models/block_models.dart` | `BlockDefinition` / `BlockInstance` + JSON save/load. |
| `lib/services/vision_service.dart` | Camera ownership (ref-counted), detection → tracking, `targetOffsetX/Y`, `targetArea`, line-following outputs. |
| `lib/services/object_detector_service.dart` | TFLite in a background isolate: fused YUV→RGB→resize→rotate, XNNPack multithreaded, Sobel line detector. |
| `lib/services/sensor_service.dart` | IMU at 20 ms: pitch/roll from gravity, shake, yaw rate, compass. `SensorMath` is pure. |
| `lib/services/connectivity/` | `RobotProtocol` + `BluetoothStrategy` / `SerialStrategy` / `WifiStrategy` behind `ConnectivityManager`. |
| `lib/ui/logic_page.dart` | Block editor canvas, palette, snippets, save/load. |
| `lib/models/tutorial_data.dart` | Built-in tutorials with visual block previews. |
| `arduino/` | Firmware for ESP32, Uno, Mega. |
| `test/` | Unit tests for protocol + frame parser, block JSON, block→Python conversion, voice matching, tracking and sensor math, and the Python interpreter + `robot` module (with a fake robot). |

## Blocks at a glance

- **Sensors:** Object Detected, Lock Object Type, Target X/Y Offset, Target Size %,
  Line Visible / Line Offset X, Phone Shaking / Tilted / Spinning, Tilt Pitch/Roll,
  Rotation Rate, Compass Heading / Facing, Loud Noise, Heard *phrase*.
- **Logic:** If, If/Else, While, Repeat, Wait, True/False, And/Or/Not, Print,
  Say (text-to-speech), Stop Program, Expression.
- **Math:** Number, + − × ÷, < >.
- **Actuators:** one block per configured device (LED on/off/toggle, motor
  direction + speed, positional or continuous servo, buzzer, switch), *Track X*
  for servos, and **Smart Follow** (native follow/fetch controller).

## Vision notes

- Model: `assets/ml/1.tflite` — EfficientDet-Lite0 int8 (TF Hub/Kaggle), 320×320
  input, COCO labels in `labelmap.txt` (line 0 is the background placeholder).
  Accuracy, latency and limitations: [docs/MODELS.md](docs/MODELS.md).
- Camera runs at `ResolutionPreset.low`; frames are throttled to ~25 FPS and
  skipped while the isolate is busy. Bounding boxes are normalized (0..1) in
  portrait display space.
- Vision settings (which labels to report, confidence threshold, phone mounted
  upside down) live in **Camera → gear icon** and persist.

## Developing

```
flutter analyze        # must be clean
flutter test           # pure-logic tests, no device needed
flutter run            # physical device
```

Useful debugging: **Code tab → ⋮ → View Logs** shows every command the
interpreter sends; the firmware echoes `EXEC:` lines over USB serial at 115200.
