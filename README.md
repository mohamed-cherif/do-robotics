# DO Robotics — your phone is the robot's brain

DO Robotics turns an Android phone into the brain of a hobby robot, for
learning and experimenting. The phone supplies the expensive parts —
camera + object detection, microphone + speech recognition, motion sensors,
compass, speaker, battery and radios — and a cheap microcontroller (ESP32,
Arduino Uno or Mega) just drives the motors, servos and LEDs. You program
the robot on the phone with drag-and-drop **blocks** (like Scratch) or in
**Python**.

<!-- TODO(screenshot): Home tab, Blocks editor with a Person Follower program, camera view with a locked person. -->

```
┌────────────── phone (this app) ──────────────┐        ┌── controller ──┐
│ camera → EfficientDet-Lite0 (TFLite) → track │  BLE   │ ESP32 / Uno /  │
│ mic    → speech-to-text / loudness           │  USB   │ Mega running   │
│ IMU    → tilt / shake / turn rate / compass  │◀─WiFi─▶│ arduino/*.ino  │
│ blocks → BlockScriptRunner                   │ 5-byte │ motors, servos │
│ python → RoboPython interpreter              │ packets│ LEDs, buzzers  │
│ TTS    → "Say" block / robot.say()           │        │ 2 s watchdog   │
└──────────────────────────────────────────────┘        └────────────────┘
```

> **Status:** pre-release. Android is the supported platform (Android 7.0+,
> built and tested with Flutter 3.38.5). iOS builds are not tested yet — see
> [docs/APPLE_FEASIBILITY.md](docs/APPLE_FEASIBILITY.md).

## Quick start (≈ 10 minutes)

You need: an Android phone (USB debugging enabled), a computer with
[Flutter 3.38](https://docs.flutter.dev/get-started/install) and the
[Arduino IDE 2](https://www.arduino.cc/en/software), and one of the boards
below with a USB cable.

**1. Flash the robot board** (Arduino IDE)

| Board | Sketch | Arduino IDE setup | Links |
|---|---|---|---|
| **ESP32 DevKit** (recommended) | `arduino/receiver/receiver.ino` | Boards Manager: **esp32 by Espressif, 3.x** (2.x does not compile). Library Manager: **ESP32Servo ≥ 3.0**. Board "ESP32 Dev Module", Tools › Partition Scheme **"Huge APP (3MB No OTA)"**. | Bluetooth, WiFi, USB |
| Arduino Uno | `arduino/receiver_uno/receiver_uno.ino` | Arduino AVR Boards, built-in Servo library | USB only |
| Arduino Mega | `arduino/receiver_mega/receiver_mega.ino` | same as Uno | USB only |

**2. Install the app** on the phone:

```
git clone <this repo> && cd do_robotics
flutter pub get
flutter run --release        # phone connected over USB
```

The camera, Bluetooth, USB and speech recognition need a real phone; the
emulator can only show the UI.

**3. Connect.** On the **Home** tab tap the header ("SYSTEM OFFLINE") and
choose **Bluetooth** (ESP32 — it advertises as *ESP32 Robot*) or **USB
Serial (OTG)** (any board, via an OTG adapter). Accept the permission
prompts. The header turns green: *SYSTEM ONLINE*.

**4. Tell the app what's wired.** Home › **Configure Hardware** › Add
Actuator: e.g. an LED on pin 2 (the ESP32's built-in LED) or pin 12
(Uno/Mega — avoid pin 13, the firmware blinks it on every command).

**5. Run something.** Home › Featured Tutorials › **Connect & Hello LED**,
or Blocks › ⚡ Snippets. Press **RUN** (bottom right) and **STOP** to end.

> **Safety:** put wheeled robots on a stand for the first run. STOP stops
> all outputs; the firmware also stops everything if it hears nothing from
> the phone for 2 seconds, and programs stop when the app leaves the screen.

### WiFi (ESP32 only)

The ESP32 also opens a hotspot `ESP32_Robot` (password `12345678` —
change `WIFI_PASS` in the sketch before using it around other people). To
put the robot on your home WiFi: connect over Bluetooth or USB first, then
header menu › **Set up robot WiFi**. Afterwards use header › **WiFi** ›
**Find robot** (mDNS `robot.local`), or type the IP address.

## Programming

### Blocks

Drag blocks from the palette onto the canvas; separate stacks run top to
bottom. Undo/redo are in the header; **⋮** has Save, Load, View Logs and
Convert to Python. Before running, the editor points out common mistakes
(an If with no condition, a device that was removed, the robot not
connected).

- **Sensors:** Object Detected, Lock Object Type, Object Locked, Target X/Y
  Offset, Target Size %, Line Visible / Line Offset X, Phone Shaking /
  Tilted / Spinning, Tilt Pitch/Roll, Rotation Rate, Compass Heading /
  Facing, Loud Noise, Heard *phrase*.
- **Logic:** If, If/Else, Forever, While, Repeat, Repeat Until, Wait,
  True/False, And/Or/Not, Print, Say, Stop Program, Expression.
- **Math:** Number, Random, + − × ÷, Less Than, Greater Than, Equals.
- **Devices:** one block per configured device (LED, motor, positional or
  continuous servo, buzzer, switch), *Track X* for servos, and **Smart
  Follow** (a ready-made follow/fetch controller for two-motor robots).

### Python

The **Python** tab runs "RoboPython", a Python subset interpreted on the
phone: numbers, strings, lists, dicts, tuples, `if/elif/else`, `while`,
`for`, `def`, recursion (up to 1000 calls), f-strings, slicing, and the
`time`, `math`, `random` modules. Not supported: classes, `try/except`,
comprehensions, other imports. Blocks convert to Python with **Blocks › ⋮ ›
Convert to Python**; the full API is in the Python tab under **⋮ › API
reference**.

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

| Object | Members |
|---|---|
| `robot.motor(name)` | `.forward(speed)`, `.backward(speed)`, `.stop()`, `.speed(±v)` |
| `robot.servo(name)` | `.angle(deg)` or, for continuous servos, `.forward(pct)`, `.backward(pct)`, `.stop()` |
| `robot.led/buzzer/switch(name)` | `.on()`, `.off()`, `.toggle()`, `.is_on` |
| `robot.vision` | `.detected`, `.lock(label)`, `.locked`, `.label`, `.offset_x/.offset_y`, `.size`, `.objects`, `.line_visible`, `.line_offset`, `.unlock()` |
| `robot.imu` | `.pitch`, `.roll`, `.yaw_rate`, `.shaking`, `.tilted`, `.spinning` |
| `robot.compass` | `.heading`, `.facing("North" \| degrees)` |
| `robot.mic` | `.loud`, `.heard(phrase)`, `.words` |
| `robot` | `.say(text)`, `.wait(s)`, `.stop_all()`, `.stop()`, `.log(...)`, `.connected`, `.actuators`, `.motors`, `.pin.digital/pwm/servo(pin, v)` |

## Sensors, the phone mount, and the camera

- Mount the phone **upright (portrait), back camera facing forward** — the
  vision, compass (direction the camera faces) and turn-rate readings are
  designed for that. A phone lying flat also works for compass and tilt.
- Object detection uses **EfficientDet-Lite0** (80 everyday COCO objects,
  e.g. person, cup, bottle, sports ball — no faces). Accuracy, speed and
  limitations: [docs/MODELS.md](docs/MODELS.md).
- Camera settings (objects to look for, confidence, upside-down mount,
  **Performance**: Battery saver / Balanced / Fast) are under Home ›
  Configure Sensors › Camera › ⚙.
- Speech recognition uses the phone's system recognizer, which may send
  audio to its provider (usually Google) unless an offline language pack is
  installed.

## Wire protocol

Every transport carries the same bytes, defined in
`lib/services/connectivity/robot_protocol.dart` and mirrored in each sketch:

```
control  [0xAA][CMD][PIN][VALUE][CHECKSUM]   CHECKSUM = (0xAA + CMD + PIN + VALUE) % 256
text     [0xAB][LEN][LEN bytes][CHECKSUM]     CHECKSUM = sum of all preceding bytes % 256
```

| CMD  | Name           | VALUE                                           |
|------|----------------|-------------------------------------------------|
| 0x00 | HEARTBEAT      | ignored — sent every 500 ms by the app          |
| 0x01 | DIGITAL_WRITE  | 0 = LOW, 1 = HIGH                               |
| 0x02 | ANALOG_WRITE   | 0–255 PWM duty                                  |
| 0x03 | PIN_MODE       | 0 = INPUT, 1 = OUTPUT, 2 = INPUT_PULLUP          |
| 0x04 | SERVO_WRITE    | angle 0–180                                     |
| 0x05 | SERVO_WRITE_US | continuous servo, (µs − 1300) / 2 → 100 = stop  |
| 0x06 | STOP_ALL       | driven pins LOW, continuous servos to 1500 µs; positional servos hold their angle |

Text frames (ESP32 only; Uno/Mega answer `ERR\tunsupported`): phone → board
`WIFI\t<ssid>\t<password>`, `NAME\t<hostname>`, `STATUS`, `FORGET`; board →
phone `HELLO`, `WIFI\t…`, `STATUS\t…`, `OK`/`ERR`, `WATCHDOG\tlink lost`.

**Failsafe:** the firmware stops every output it has driven if no packet
arrives for 2 s, on BLE disconnect and when the WiFi client drops.

### Pins to avoid

- **ESP32:** 6–11 (flash — using them crashes the board), 1/3 (USB serial),
  34–39 are input-only; strapping pins 0, 2, 5, 12, 15 must not be pulled
  the wrong way at boot.
- **Uno/Mega:** 0/1 (USB serial), 13 (activity LED). On the Uno, attaching
  any servo disables PWM on pins 9 and 10.

## Documentation

| Document | For |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the app is put together, data flow, where to change what |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Setting up, safety rules for contributors, tests, PRs |
| [docs/MODELS.md](docs/MODELS.md) | Detection model card, measured accuracy/latency, evaluation harness |
| [docs/DEVICE_TEST_CHECKLIST.md](docs/DEVICE_TEST_CHECKLIST.md) | Manual release testing on phones and robots |
| [docs/APPLE_FEASIBILITY.md](docs/APPLE_FEASIBILITY.md) | What an iOS port would take |
| [docs/AUDIT_2026-09.md](docs/AUDIT_2026-09.md) | Pre-release audit: fixes, open findings, roadmap |
| [SECURITY.md](SECURITY.md) | Reporting vulnerabilities, known limitations |

## Developing

```
flutter analyze        # must report "No issues found"
flutter test           # 130+ unit/widget tests, no phone needed
flutter run            # on a physical phone
```

CI (`.github/workflows/ci.yml`) runs analyze, tests and a release APK build.
Debugging on a robot: **Blocks › ⋮ › View Logs** shows every command the
interpreter sends; `#define DEBUG_ECHO` in the ESP32 sketch prints `EXEC:`
lines over USB serial at 115200.

## License

TODO(owner): not chosen yet — see "Needs decision" in
[docs/AUDIT_2026-09.md](docs/AUDIT_2026-09.md). Third-party components keep
their licenses: the EfficientDet-Lite0 model (Apache-2.0, TensorFlow), COCO
labels (CC BY 4.0), and the Flutter packages listed in `pubspec.lock`
(BSD-3-Clause, MIT, Apache-2.0; two Linux-only MPL-2.0 packages).
