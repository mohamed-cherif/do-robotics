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
| **ESP32 DevKit** (recommended) | `arduino/receiver/receiver.ino` | Boards Manager: **esp32 by Espressif, 3.x** (2.x does not compile). Library Manager: **ESP32Servo ≥ 3.0**. Board "ESP32 Dev Module", Tools › Partition Scheme **"Huge APP (3MB No OTA)"** (the sketch is about 1.7 MB; the default scheme has room for about 1.3 MB). | Bluetooth, WiFi, USB |
| Arduino Uno | `arduino/receiver_uno/receiver_uno.ino` | Arduino AVR Boards, built-in Servo library | USB only |
| Arduino Mega | `arduino/receiver_mega/receiver_mega.ino` | same as Uno | USB only |

After flashing, the Uno/Mega built-in LED blinks 3 times. Using
`arduino-cli` instead of the IDE? Also run `arduino-cli lib install Servo`
(the IDE bundles it; the CLI doesn't).

**2. Install the app** on the phone:

```
git clone <this repo> && cd do-robotics
flutter pub get
flutter run --release        # phone connected over USB
```

The camera, Bluetooth, USB and speech recognition need a real phone; the
emulator can only show the UI. To make an APK file you can keep and copy
to other phones instead, see [Build an installable app](#build-an-installable-app-apk).

**3. Connect.** On the **Home** tab tap the header ("SYSTEM OFFLINE") and
choose **Bluetooth** (ESP32) or **USB Serial (OTG)** (any board, via an
OTG adapter). Accept the permission prompts. Bluetooth shows the robots in
range, closest first: tap yours — *ESP32 Robot XXXX*, where XXXX are the
last 4 hex digits of the board's MAC address. The app remembers it and
reconnects to that robot next time. The header turns green: *SYSTEM
ONLINE*.

**4. Tell the app what's wired.** Home › **Configure Hardware** › Add
Actuator: e.g. an LED on pin 2 (the ESP32's built-in LED) or pin 13
(the Uno/Mega built-in LED). If a pin can't be used on your board, the
program log says so (*Robot: pin 6 can't be used on this board*).

**5. Run something.** Home › Featured Tutorials › **Connect & Hello LED**,
or Blocks › ⚡ Snippets. Press **RUN** (bottom right) and **STOP** to end.

> **Safety:** put wheeled robots on a stand for the first run. STOP stops
> all outputs; the firmware also stops everything if it hears nothing from
> the phone for 2 seconds, and programs stop when the app leaves the screen.

### WiFi (ESP32 only)

The ESP32 also opens a hotspot `ESP32_Robot_XXXX` (same XXXX as the
Bluetooth name; password `12345678` — change `WIFI_PASS` in the sketch
before using it around other people). To put the robot on your home WiFi:
connect over Bluetooth or USB first, then header menu › **Set up robot
WiFi** (for safety the robot only accepts WiFi settings over Bluetooth or
USB, never over WiFi itself). Afterwards use header › **WiFi** ›
**Find robot** (mDNS `robot.local`), or type the IP address.

## Build an installable app (APK)

`flutter run --release` installs straight from your computer. To get an
APK file you can keep, copy to phones or share:

**1. One-time setup.** Install [Flutter 3.38](https://docs.flutter.dev/get-started/install)
and the Android SDK (installing [Android Studio](https://developer.android.com/studio)
is the easiest way; all of it is free). Run `flutter doctor` until the
*Android toolchain* line has a ✓ (`flutter doctor --android-licenses`
accepts the SDK licenses).

**2. Build.** In the project folder:

```
flutter pub get
flutter build apk --release --split-per-abi
```

The first build is slow (almost 30 minutes on the Windows laptop used to
write this, most of it compiling Android code once). It writes three APKs
to `build/app/outputs/flutter-apk/`:

| File | For |
|---|---|
| `app-arm64-v8a-release.apk` (≈ 29 MB) | almost every phone from the last ~8 years: **use this one** |
| `app-armeabi-v7a-release.apk` | old 32-bit phones |
| `app-x86_64-release.apk` | emulators, some Chromebooks |

Not sure which phone type you have? `adb shell getprop ro.product.cpu.abi`
prints it. `flutter build apk --release` (without `--split-per-abi`) makes
a single, bigger `app-release.apk` that runs on all of them.

**3. Install**, either way:

- **With a USB cable:** on the phone enable *Developer options › USB
  debugging*, plug it in, then
  `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
  (`adb` is in the Android SDK's `platform-tools` folder).
- **Without a cable:** copy the APK to the phone (USB file transfer, Google
  Drive, e-mail …), tap it in the *Files* app, and allow **Install unknown
  apps** for that app when Android asks. Play Protect may warn about an app
  that isn't from the Play Store; the warning lets you install anyway.

**4. First start.** Open **DO Robotics** and allow camera, microphone and
Nearby devices (Bluetooth; called Location on Android 11 and older) when
asked.

**Signing.** With no extra setup the release APK is signed with your
computer's *debug* key. That is fine for your own phones, but Android only
installs an update over an existing copy if both were signed with the same
key (otherwise uninstall first). To share builds for the long term, create
a key once:

```
keytool -genkey -v -keystore ~/do-robotics-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

and create `android/key.properties` (git-ignored; never commit it or the
`.jks`):

```
storeFile=/full/path/to/do-robotics-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Keep a backup of the key: without it you can't ship updates to phones that
already have the app.

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

- Mount the phone **in portrait, back camera facing forward** — the
  vision, compass (direction the camera faces) and turn-rate readings are
  designed for that. A phone lying flat also works for compass and tilt.
  The app stays in portrait.
- **Upside down is fine** (charging port up, e.g. when a holder covers the
  bottom). With *Phone mounting: Automatic* (the default) the app notices
  and flips the camera image, so "target on the left" still means the
  robot's left and steering is unchanged. Choose *Upright* or *Upside
  down* in the camera settings to fix it instead.
- Object detection uses **EfficientDet-Lite0** (80 everyday COCO objects,
  e.g. person, cup, bottle, sports ball — no faces). Accuracy, speed and
  limitations: [docs/MODELS.md](docs/MODELS.md).
- Camera settings (objects to look for, confidence, phone mounting,
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
arrives for 2 s, on BLE disconnect, when the WiFi client drops and when a
new WiFi client takes over.

The board answers a command it can't carry out with an `ERR` text frame
(at most one per second), which the app shows in the program log: a pin
that can't be used, PWM on a pin without PWM, more than 8 servos on
Uno/Mega.

### Pins to avoid

- **ESP32** (the firmware refuses these): 6–11 (flash — using them crashes
  the board), 0 and 1/3 (boot button, USB serial); 34, 35, 36, 39 are
  input-only. Strapping pins 2, 5, 12, 15 work but must not be pulled the
  wrong way at boot.
- **Uno/Mega:** 0/1 (USB serial). Once a servo has been used, PWM stops
  working on pins 9 and 10 (Uno) or 44–46 (Mega) until the board is reset —
  the Servo library takes over their timer. Pin 13 (built-in LED) is
  fine: the activity blink stays off once your program uses it.

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
flutter analyze                 # must report "No issues found"
flutter test                    # 170+ unit/widget tests, no phone needed
flutter run                     # on a physical phone
bash arduino/test/run_tests.sh  # firmware logic on the computer, no board needed (g++ or clang++)
```

CI (`.github/workflows/ci.yml`) runs analyze, tests, a release APK build,
the firmware host tests, and compiles the three sketches.
Debugging on a robot: **Blocks › ⋮ › View Logs** shows every command the
interpreter sends; `#define DEBUG_ECHO` in the ESP32 sketch prints `EXEC:`
lines over USB serial at 115200.

## License

[Apache License 2.0](LICENSE): you may use, change and share the code,
also commercially, as long as you keep the license and [NOTICE](NOTICE)
and mark the files you changed. The documentation in `docs/` may also be
used under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Third-party components keep their licenses: the EfficientDet-Lite0 model
(Apache-2.0, TensorFlow), COCO labels (CC BY 4.0), and the Flutter
packages listed in `pubspec.lock` (BSD-3-Clause, MIT, Apache-2.0; two
Linux-only MPL-2.0 packages).
