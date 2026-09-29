# Design: Python programming + ESP32 wireless parity

Date: 2026-09-12. Status: approved in chat and implemented the same day (Python subset in-app; ESP32 joins home WiFi with mDNS). Deviations from this spec: `robot.mic.heard` consumes the phrase like the block; `robot.motor(...).speed(±v)` added; Uno/Mega discard text bodies without buffering (RAM).

## 1. Goals

1. Programs can be written as **Python text** on the phone and run with the same
   sensors, actuators, STOP button, and execution log as block programs.
2. Block programs convert to runnable Python one way ("Convert to Python").
3. The ESP32 works over **Bluetooth and WiFi exactly like the USB cable**: same
   packets, plus a return channel from board to phone, WiFi credentials set from
   the phone, discovery as `robot.local`, and automatic Bluetooth reconnect.

Non-goals: full CPython, classes, `try/except`, `import` of arbitrary modules,
sensor feedback blocks (the return channel is built; sensor commands come next).

## 2. Python subset ("RoboPython")

### 2.1 Language

| Feature | Supported |
|---|---|
| Literals | int, float, str (single/double quotes, `\n \t \\ \'`), f-strings with `{expr}` and `{expr:.2f}`, `True False None`, lists `[...]` |
| Operators | `+ - * / // % **`, unary `-`, `not`, `and or`, chained comparisons `< <= > >= == !=`, `in`, `not in`, ternary `a if c else b` |
| Statements | assignment and `+= -= *= /=`, `if/elif/else`, `while`, `for x in <iterable>`, `def f(a, b=1):`, `return`, `break`, `continue`, `pass`, `global`, `import robot|time|math`, `from robot import *` (no-op) |
| Builtins | `print len range abs min max int float str bool round list sum enumerate` |
| Methods | str: `lower upper strip split startswith endswith replace`; list: `append pop insert remove index count` |
| Modules | `time.sleep(s)`, `time.time()`, `math.sqrt sin cos atan2 pi floor ceil` |
| Indexing | `a[i]`, negative indices, slices `a[i:j]` |
| Errors | Runtime errors report `line N: message` to the log and stop the program |

Indentation: spaces or tabs (tab = 4). Comments `#`. Blank lines ignored.

### 2.2 Robot API (same vocabulary as the blocks)

```python
import robot, time

left  = robot.motor("Left Wheel")     # by configured actuator name
right = robot.motor("Right Wheel")
led   = robot.led("Headlight")
arm   = robot.servo("Arm")

left.forward(200); left.backward(150); left.stop()      # speed 0-255
arm.angle(90)                                           # positional servo
arm.forward(75); arm.backward(40); arm.stop()           # continuous servo, %
led.on(); led.off(); led.toggle()                       # led / buzzer / switch

robot.vision.detected        # bool — any object in the current frame
robot.vision.lock("person")  # bool — lock on the most confident "person"
robot.vision.locked          # bool
robot.vision.label           # str  — label of the locked object
robot.vision.offset_x        # -1..1 (left..right)
robot.vision.offset_y        # -1..1 (top..bottom)
robot.vision.size            # 0..100 — % of frame, a closeness proxy
robot.vision.objects         # list of labels in frame
robot.vision.line_visible    # bool  (line-following mode)
robot.vision.line_offset     # -1..1
robot.vision.unlock()

robot.imu.pitch, robot.imu.roll        # degrees
robot.imu.yaw_rate                     # deg/s
robot.imu.shaking, robot.imu.tilted, robot.imu.spinning
robot.compass.heading                  # 0..360
robot.compass.facing("North")          # or degrees; ±22.5°
robot.mic.loud                         # bool
robot.mic.heard("go forward")          # bool, consumes the phrase
robot.mic.words                        # last recognized text

robot.say("Hello")                      # text-to-speech (blocks until spoken)
robot.wait(0.5)                         # same as time.sleep
robot.stop_all()                        # every actuator off
robot.pin.digital(13, 1); robot.pin.pwm(9, 128); robot.pin.servo(5, 90)  # raw
robot.connected                         # bool
```

Motors/servos/leds resolve by actuator **name** (case-insensitive) or by id.
Unknown name → runtime error naming the configured actuators.

Camera starts lazily on first `robot.vision` access; line mode when
`line_visible`/`line_offset` is used; microphone on first `robot.mic` access.
The runner pre-scans the source for these names to start subsystems before the
first line runs (so the first loop iteration is not slow).

### 2.3 Components

```
lib/python/
  lexer.dart          source → tokens (INDENT/DEDENT/NEWLINE synthesized)
  ast.dart            node classes
  parser.dart         recursive descent → Module
  values.dart         PyValue wrappers: PyNone/bool/int/float/str/list, PyFunction,
                      PyNative (Dart callable), PyObject (attribute bag with native getters)
  interpreter.dart    async tree walker; cancellation token; yields to the event
                      loop every loop iteration and every 200 statements
  builtins.dart       print/len/range/…, str & list methods, time, math
  robot_module.dart   builds the `robot` PyObject over a RobotApi
lib/logic/robot_api.dart      abstract RobotApi + LiveRobotApi (services)
lib/logic/python_script_runner.dart   run(source)/stop(), state + currentLine streams
lib/ui/python_page.dart       editor, console, run/stop, save/load, examples
lib/services/python_script_store.dart  SharedPreferences slots (like scripts)
```

`RobotApi` is an abstract class so the interpreter tests use `FakeRobotApi`
that records commands. `LiveRobotApi` wraps ActuatorService, VisionService,
SensorService, ConnectivityManager, FlutterTts, SpeechToText and reuses the
same dedup + clamping rules as the block runner (moved into shared code).

### 2.4 Editor

- Monospace `TextField` with a custom controller that colours keywords,
  strings, numbers, comments and `robot` API names (regex highlighter, no
  package).
- Line-number gutter, the executing line highlighted while running, Tab inserts
  four spaces, Enter after `:` auto-indents.
- Console at the bottom fed by ExecutionLogger (print output, errors, robot
  events). RUN/STOP floating button identical to the block editor.
- Menu: Save / Load / Examples (Motor test, Person follower, Voice control,
  Line follower, Tilt steering) / Clear.
- Dashboard gets a third tab **Python**. Block editor menu item "View Code"
  becomes "Convert to Python" and opens the Python tab with the generated code.

### 2.5 Error handling

Lexer/parser errors show `line N: …` before anything runs. Runtime errors stop
the program, log the line, and the runner performs the same stop-all as blocks.
Infinite loops are interruptible because every loop iteration awaits a timer.

## 3. ESP32 wireless parity

### 3.1 Protocol additions (all transports, both directions)

Existing 5-byte control packets are unchanged. Two new frame types share the
byte stream; the state machine dispatches on the first byte:

```
0xAA  control    [0xAA][CMD][PIN][VAL][CK]                      phone → board
0xAB  text       [0xAB][LEN][LEN bytes ASCII][CK]               both directions
      CK = (sum of all preceding bytes) % 256, LEN ≤ 120
```

Text frames carry line commands and replies:

| Direction | Text | Meaning |
|---|---|---|
| phone → board | `WIFI\t<ssid>\t<password>` | store credentials in NVS, connect in station mode |
| phone → board | `NAME\t<hostname>` | mDNS/BLE name (default `robot`) |
| phone → board | `STATUS` | ask for a status line |
| phone → board | `FORGET` | erase WiFi credentials |
| board → phone | `HELLO\tesp32\t<fw-version>` | on connect |
| board → phone | `WIFI\tCONNECTED\t<ip>` / `WIFI\tFAILED\t<reason>` / `WIFI\tAP\t192.168.4.1` | |
| board → phone | `OK\t<cmd>` / `ERR\t<msg>` | acknowledgements |

Board → phone text goes out on the transport the request came from (BLE
notify on the TX characteristic, USB serial, TCP). `EXEC:` debug prints move
behind a `DEBUG_ECHO` define so the serial stream stays clean for framing.

### 3.2 Firmware (receiver.ino)

- `WiFi.mode(WIFI_AP_STA)`: the hotspot stays up as a fallback; if NVS has
  credentials, also join that network (10 s timeout, retry every 30 s).
- `MDNS.begin(name)` on station connect; advertise `_dorobot._tcp` on 4210.
- Create the NUS **TX characteristic** (NOTIFY) and send text frames on it.
- Watchdog/failsafe from the previous pass unchanged.

### 3.3 App

- `RobotConnection` gains `Stream<Uint8List> get inbound`. `ConnectivityManager`
  runs a `FrameParser` over it and exposes `Stream<String> messages`.
- `BluetoothStrategy` subscribes to TX notifications; auto-reconnects to the
  last device up to 5 times (2 s apart) after an unexpected drop.
- `WifiStrategy.connect` accepts `robot.local` (resolved with the `multicast_dns`
  package, 3 s timeout) or an IP; keeps the last successful address.
- Connection dialog: **WiFi → Find robot.local / enter address**, and a new
  **Robot WiFi setup** dialog (SSID + password) that sends the `WIFI` text frame
  over the current link and shows the board's reply.
- Uno/Mega: text frames are parsed and answered with `ERR unsupported` so the
  app can tell which board it talks to.

## 4. Testing

- `test/python/lexer_test.dart`, `parser_test.dart`, `interpreter_test.dart`
  (arithmetic, control flow, functions, strings, lists, f-strings, errors with
  line numbers, cancellation), `robot_module_test.dart` with `FakeRobotApi`.
- `test/frame_parser_test.dart` for text/control frame parsing incl. resync
  after garbage.
- Firmware compiled in the Arduino IDE by the user (no toolchain here).

## 5. Order of work

1. Lexer + parser + interpreter + builtins with tests.
2. `RobotApi` (abstract + fake + live) and `robot` module with tests.
3. `PythonScriptRunner`, editor page, dashboard tab, block → Python converter.
4. Protocol framing in Dart + firmware text channel, WiFi provisioning, mDNS,
   BLE TX/notify and reconnect, connection UI.
