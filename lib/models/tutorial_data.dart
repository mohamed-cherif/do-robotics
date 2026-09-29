import 'package:flutter/material.dart';

enum Difficulty { easy, medium, hard }

// ─────────────────────────────────────────────────────────────────────────────
// Visual Block Tree (for in-tutorial block previews)
// Uses int color values so the class can be `const`.
// ─────────────────────────────────────────────────────────────────────────────

/// A single visual block node used to render colorful block diagrams inside
/// tutorial steps. Uses [int] color values so it can live in a `const` tree.
class VisualBlockNode {
  /// Emoji prefix shown on the block face.
  final String emoji;

  /// Label text shown on the block face.
  final String label;

  /// Background color of this block (as a `Color(0xFF...)` int value).
  final int colorValue;

  /// When true the block is drawn on its own as a hexagonal boolean block
  /// (used to show a single condition block, e.g. a comparison).
  final bool isBoolean;

  /// Optional text shown in an inline "condition chip" (the block that sits in
  /// an If/While condition slot). `[ ]` marks what goes in each hole.
  final String? inlineCondition;

  /// Color of the inline condition chip: purple for a plain sensor block, pink
  /// for comparison / AND / OR / NOT blocks (as in the editor).
  final int inlineConditionColor;

  /// Blocks rendered inside this block's body (do / then do slot).
  final List<VisualBlockNode> bodyNodes;

  /// Blocks rendered in the "else do" slot (If / Else blocks only).
  final List<VisualBlockNode> elseNodes;

  const VisualBlockNode({
    required this.emoji,
    required this.label,
    required this.colorValue,
    this.isBoolean = false,
    this.inlineCondition,
    this.inlineConditionColor = _sensor,
    this.bodyNodes = const [],
    this.elseNodes = const [],
  });

  Color get color => Color(colorValue);
  Color get chipColor => Color(inlineConditionColor);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tutorial model classes
// ─────────────────────────────────────────────────────────────────────────────

class TutorialData {
  final String id;
  final String title;
  final String emoji;
  final String shortDescription;
  final Difficulty difficulty;
  final Color cardColor;
  final List<String> requiredParts;
  final String conceptDescription;
  final List<TutorialStep> steps;

  const TutorialData({
    required this.id,
    required this.title,
    required this.emoji,
    required this.shortDescription,
    required this.difficulty,
    required this.cardColor,
    required this.requiredParts,
    required this.conceptDescription,
    required this.steps,
  });

  String get difficultyLabel {
    switch (difficulty) {
      case Difficulty.easy:
        return "Easy";
      case Difficulty.medium:
        return "Medium";
      case Difficulty.hard:
        return "Hard";
    }
  }

  Color get difficultyColor {
    switch (difficulty) {
      case Difficulty.easy:
        return Colors.greenAccent[400]!;
      case Difficulty.medium:
        return Colors.orangeAccent;
      case Difficulty.hard:
        return Colors.redAccent;
    }
  }
}

class TutorialStep {
  final String text;

  /// Optional visual block tree shown below the step text.
  final List<VisualBlockNode>? blockPreview;

  const TutorialStep({required this.text, this.blockPreview});
}

// ─────────────────────────────────────────────────────────────────────────────
// Block color constants (mirror BlockColors in block_models.dart)
// ─────────────────────────────────────────────────────────────────────────────
const int _sensor = 0xFF8B5CF6; // purple — sensor blocks
const int _logic = 0xFF10B981; // green — If, Forever, Wait…
const int _action = 0xFFF59E0B; // amber — motors, LEDs, Say, Print
const int _boolean = 0xFFEC4899; // pink — < > = AND OR NOT
const int _hint = 0xFF64748B; // slate — "next step goes here" placeholders

// ─────────────────────────────────────────────────────────────────────────────
// Shared text
// ─────────────────────────────────────────────────────────────────────────────

const String _connectHowTo =
    'On the Home tab, tap the header that says SYSTEM OFFLINE and pick '
    'USB Serial (OTG) for an Uno/Mega (Android only) or Bluetooth for an '
    'ESP32. It turns to SYSTEM ONLINE when connected.';

const String _carSetup =
    'Set up, test and connect the robot car exactly as in "Beat Reactive '
    'Dancer" (steps 1–3): Left Motor on IN1 pin 5, Right Motor on IN1 pin 6 '
    '(ESP32: GPIO 25 / 26), tested with ⚡ Snippets › Motor Forward Test.';

const String _visionSettingsPath =
    'Home › Configure Sensors › Camera › ⚙ gear › Vision Settings';

const String _comparisonHowTo =
    'Build a comparison from three blocks: drag Math › Less Than < (or '
    'Greater Than >) into the condition slot, drop the sensor into its LEFT '
    'hole and a Math › Number into its RIGHT hole, then tap the Number (it '
    'starts at 90) and type your own number.';

// ─────────────────────────────────────────────────────────────────────────────
// Reusable preview blocks
// ─────────────────────────────────────────────────────────────────────────────

const _next = VisualBlockNode(emoji: '…', label: 'next step goes here', colorValue: _hint);

const _leftFwd = VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]', colorValue: _action);
const _rightFwd = VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ FORWARD ]', colorValue: _action);
const _leftStop = VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action);
const _rightStop = VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action);

const _lampOn = VisualBlockNode(emoji: '💡', label: 'Lamp  [ ON ]', colorValue: _action);
const _lampOff = VisualBlockNode(emoji: '💡', label: 'Lamp  [ OFF ]', colorValue: _action);

const _wait005 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 0.05 ]  seconds', colorValue: _logic);
const _wait006 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 0.06 ]  seconds', colorValue: _logic);
const _wait008 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 0.08 ]  seconds', colorValue: _logic);
const _wait01 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 0.1 ]  seconds', colorValue: _logic);
const _wait02 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 0.2 ]  seconds', colorValue: _logic);
const _wait05 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 0.5 ]  seconds', colorValue: _logic);
const _wait1 = VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 1 ]  seconds', colorValue: _logic);

/// Pivot left: stop the left wheel, drive the right one.
const _pivotLeft = [_leftStop, _rightFwd];

/// Pivot right: drive the left wheel, stop the right one.
const _pivotRight = [_leftFwd, _rightStop];
const _bothFwd = [_leftFwd, _rightFwd];
const _bothStop = [_leftStop, _rightStop];

// ─────────────────────────────────────────────────────────────────────────────
// Tutorial repository (ordered from first-ever program to hardest project)
// ─────────────────────────────────────────────────────────────────────────────

class TutorialRepository {
  static const List<TutorialData> tutorials = [
    // ── 1 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_hello_led',
      title: 'Connect & Hello LED',
      emoji: '💡',
      shortDescription:
          'Connect the app to your robot board and blink your very first LED.',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFFFEF08A),
      requiredParts: [
        'Arduino Uno or Mega (USB) — or an ESP32 (Bluetooth / WiFi)',
        'USB cable (+ USB-OTG adapter to plug an Uno/Mega into an Android phone)',
        '1x LED + 220 Ω resistor (an ESP32 can use its built-in LED instead)',
        'A computer with Arduino IDE (one-time firmware upload)',
      ],
      conceptDescription:
          'The phone is the robot\'s brain and the little board is its hands. '
          'The board runs the DO Robotics firmware, which switches its pins on '
          'and off whenever the app says so. An LED is the simplest thing a '
          'pin can switch — if it blinks, your whole setup works!',
      steps: [
        TutorialStep(
          text:
              'Upload the firmware (one time only). On a computer, open Arduino '
              'IDE and open the sketch for your board from the project\'s '
              'arduino/ folder:\n'
              '• Uno → receiver_uno    • Mega → receiver_mega\n'
              '• ESP32 → receiver (also install the ESP32 board package and '
              'the ESP32Servo library)\n'
              'Pick your board and port and click Upload. The README\'s Quick '
              'start has the details. On an Uno/Mega the built-in LED blinks '
              '3 times when the firmware starts.',
        ),
        TutorialStep(
          text:
              'Wire the LED (Uno/Mega): long leg → 220 Ω resistor → pin 12, '
              'short leg → GND. (No wiring? Pin 13 is the built-in LED; with '
              'firmware older than 1.5 it also flashes on every command.)\n'
              'ESP32: no wiring needed — use the built-in LED on GPIO 2.',
        ),
        TutorialStep(
          text:
              'Connect. $_connectHowTo\n'
              'Uno/Mega: plug the board into the phone with the OTG adapter and '
              'allow USB access. ESP32: it shows up as "ESP32 Robot" plus 4 characters.',
        ),
        TutorialStep(
          text:
              'Tell the app about your LED: Home › ⚙️ Configure Hardware › '
              'Add Actuator.\n'
              '• Name: Lamp\n'
              '• Type: LED  (it starts on Motor — change it!)\n'
              '• Pin: 12  (ESP32: 2)\n'
              'Tap Save. A "Lamp" block now appears in the Blocks tab under '
              'Actuators.',
        ),
        TutorialStep(
          text:
              'Open the Blocks tab. From Logic, drag a Forever block onto the '
              'canvas. Everything inside its "do" slot repeats until you stop '
              'the program.',
          blockPreview: [
            VisualBlockNode(emoji: '♾️', label: 'Forever', colorValue: _logic),
          ],
        ),
        TutorialStep(
          text:
              'From Actuators, drag the Lamp block into Forever\'s "do" slot and '
              'set it to ON. From Logic, snap a Wait block under it and type 1. '
              'Then add Lamp [ OFF ] and another Wait 1.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [_lampOn, _wait1, _lampOff, _wait1],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap the green RUN button (bottom-right). The LED blinks once a '
              'second! Tap the red STOP button to end.\n'
              'If a "Before you run…" box pops up, read it — it lists problems '
              'such as a robot that isn\'t connected.\n'
              'Nothing happens? In the Blocks tab tap ⋮ › View Logs to see every '
              'command, and check that the Home header says SYSTEM ONLINE.\n'
              'Try it: change both Waits to 0.2 for a fast blink.',
        ),
      ],
    ),

    // ── 2 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_clap_light',
      title: 'Clap-On Smart Light',
      emoji: '👏',
      shortDescription: 'Turn your LED on and off by clapping loudly!',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFFFDE68A),
      requiredParts: [
        'The Lamp LED from "Connect & Hello LED" (pin 12, or GPIO 2 on ESP32)',
        'Robot board connected (Home header says SYSTEM ONLINE)',
        'Phone microphone (allow microphone access)',
      ],
      conceptDescription:
          'Microphones turn sound into electricity. The Loud Noise block is '
          'true only at the moment the sound is loud — a clap lasts a split '
          'second — so the program must check it many times a second and only '
          'pause right after it has reacted.',
      steps: [
        TutorialStep(
          text:
              'Finish "Connect & Hello LED" first: your Lamp is set up and the '
              'Home header says SYSTEM ONLINE. Tip: test how loud your clap is '
              'on Home › Configure Sensors › Microphone.',
        ),
        TutorialStep(
          text:
              'In the Blocks tab, drag a Forever block from Logic. Put an If '
              'block (Logic) into its "do" slot, then drag Loud Noise '
              '(Sensors) into the If\'s condition slot.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '🔊 Loud Noise',
                  bodyNodes: [_next],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Inside the If\'s "then do", add your Lamp block set to TOGGLE and '
              'snap a Wait block under it: type 0.5. The Wait sits INSIDE the '
              'If, so the program only pauses after a clap — the rest of the '
              'time it checks the microphone about 50 times a second and '
              'won\'t miss your clap.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '🔊 Loud Noise',
                  bodyNodes: [
                    VisualBlockNode(emoji: '💡', label: 'Lamp  [ TOGGLE ]', colorValue: _action),
                    _wait05,
                  ],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap RUN (allow microphone access the first time) and clap loudly '
              'near the phone — the light toggles on and off!\n'
              'Nothing happens? ⋮ › View Logs should show "🎙️ Voice: listening" '
              'when the microphone is on.',
        ),
      ],
    ),

    // ── 3 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_ai_guard',
      title: 'AI Security Guard',
      emoji: '🚨',
      shortDescription:
          'Use the AI camera to spot a person and set off an LED + buzzer alarm!',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFFFCA5A5),
      requiredParts: [
        'The Lamp LED from "Connect & Hello LED"',
        '1x active buzzer module (Uno/Mega pin 8, ESP32 GPIO 27)',
        'Phone back camera pointed at a doorway',
      ],
      conceptDescription:
          'The app\'s AI model (trained on the COCO data set) recognises about '
          '80 kinds of things — people, cats, chairs, cups… It can\'t recognise '
          'faces or motion, but it is great at spotting a person. We tell the '
          'camera to report only people, then sound the alarm whenever one is '
          'seen. The If / Else block picks one of two actions every time: alarm '
          'on, or alarm off.',
      steps: [
        TutorialStep(
          text:
              'Home › ⚙️ Configure Hardware › Add Actuator: Name Buzzer, Type '
              'Buzzer, Pin 8 (ESP32: 27). Wire the buzzer\'s + to that pin and '
              '− to GND. Use an "active" buzzer — it beeps by itself when '
              'switched on. Keep the Lamp from the first tutorial and make sure '
              'the robot is connected.',
        ),
        TutorialStep(
          text:
              'Tell the camera what counts as an intruder: '
              '$_visionSettingsPath. Under "Objects to detect" select only '
              'person, then tap Save Settings. (With nothing selected it reports '
              'EVERY object — a chair or TV would set off the alarm.)',
        ),
        TutorialStep(
          text:
              'In Blocks, drag a Forever block. Put an If / Else block (Logic) '
              'inside it and drop Object Detected (Sensors) into its condition.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '👁️ Object Detected',
                  bodyNodes: [_next],
                  elseNodes: [_next],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'In "then do": Lamp [ ON ] and Buzzer [ ON ]. In "else do": Lamp '
              '[ OFF ] and Buzzer [ OFF ]. Under the If / Else (still inside '
              'Forever) add Wait 0.5 so the alarm doesn\'t flicker.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '👁️ Object Detected',
                  bodyNodes: [
                    _lampOn,
                    VisualBlockNode(emoji: '🔊', label: 'Buzzer  [ ON ]', colorValue: _action),
                  ],
                  elseNodes: [
                    _lampOff,
                    VisualBlockNode(emoji: '🔊', label: 'Buzzer  [ OFF ]', colorValue: _action),
                  ],
                ),
                _wait05,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Point the phone\'s back camera (the program always uses the back '
              'camera) at a doorway, tap RUN and walk into view — the alarm goes '
              'off! Walk away and it stops.\n'
              'Try it: guard your snack instead — select "banana" or "cup" in '
              'Vision Settings instead of person.',
        ),
      ],
    ),

    // ── 4 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_beat_dancer',
      title: 'Beat Reactive Dancer',
      emoji: '🎵',
      shortDescription:
          'Build your first robot car and make it dance whenever the music is loud!',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFF86EFAC),
      requiredParts: [
        'Arduino Uno (USB) or ESP32 (Bluetooth) with the firmware from "Connect & Hello LED"',
        'L298N motor driver + 2 DC motors (Left & Right wheels) on a car chassis',
        'Motor battery pack (6–9 V)',
        'Phone microphone',
      ],
      conceptDescription:
          'Motors need far more power than a board pin can give, so an L298N '
          'motor driver (an "H-bridge") switches the battery power for us. We '
          'use the simplest wiring: each motor has ONE control pin — HIGH = '
          'forward, LOW = stop. This same car is used in every robot-car '
          'tutorial after this one. When the music is loud the robot wiggles '
          'by driving one wheel and then the other; when it\'s quiet it stops.',
      steps: [
        TutorialStep(
          text:
              'Wire the L298N motor driver:\n'
              '• IN1 → pin 5 (ESP32: GPIO 25) — Left motor\n'
              '• IN3 → pin 6 (ESP32: GPIO 26) — Right motor\n'
              '• IN2 and IN4 → GND\n'
              '• Leave the ENA and ENB jumper caps ON (full speed)\n'
              '• Left motor → OUT1/OUT2, Right motor → OUT3/OUT4\n'
              '• L298N GND → board GND and battery −;  L298N +12V → battery +\n'
              'Don\'t connect the L298N 5V pin to an Uno that the phone powers '
              'over USB. An ESP32 on Bluetooth can run from a USB power bank.',
        ),
        TutorialStep(
          text:
              'Home › ⚙️ Configure Hardware › Add Actuator (twice):\n'
              '• Name Left Motor · Type Motor · Pin 9 · IN1 Pin 5 · IN2 Pin None\n'
              '• Name Right Motor · Type Motor · Pin 10 · IN1 Pin 6 · IN2 Pin None\n'
              '(ESP32: Pin 32 / 33 and IN1 Pin 25 / 26.)\n'
              'The "Pin" (ENA) isn\'t wired while the jumpers are on, but every '
              'motor needs its own unused pin — otherwise you\'ll see "Pin '
              'already in use!".',
        ),
        TutorialStep(
          text:
              'Connect and test. $_connectHowTo\n'
              'Lift the car so the wheels are off the table, open Blocks › ⚡ '
              'Snippets › Motor Forward Test › Load and tap RUN: both wheels '
              'should spin forward for 3 seconds. A wheel spins backwards? Swap '
              'that motor\'s two wires on the L298N.',
        ),
        TutorialStep(
          text:
              'Build the dance: tap ⋮ › Clear All, drag a Forever block, put an '
              'If / Else block inside it and drop Loud Noise (Sensors) into its '
              'condition.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🔊 Loud Noise',
                  bodyNodes: [_next],
                  elseNodes: [_next],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'In "then do" (loud) add the wiggle: Left Motor [ FORWARD ], Right '
              'Motor [ STOP ], Wait 0.2, Left Motor [ STOP ], Right Motor '
              '[ FORWARD ], Wait 0.2. In "else do" (quiet): both motors '
              '[ STOP ].',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🔊 Loud Noise',
                  bodyNodes: [..._pivotRight, _wait02, ..._pivotLeft, _wait02],
                  elseNodes: _bothStop,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Put the car on the floor, tap RUN and play loud music next to the '
              'phone — it dances while the music is loud and freezes when it\'s '
              'quiet! Change the Wait numbers for a faster or slower dance.\n'
              'Want it to spin in place? That needs reverse: wire IN2 / IN4 to '
              'two more pins (e.g. 7 and 8), set them as each motor\'s IN2 Pin, '
              'and use BACKWARD on one wheel.',
        ),
      ],
    ),

    // ── 5 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_voice_bot',
      title: 'Voice Commanded Robot',
      emoji: '🗣️',
      shortDescription:
          'Say "drive", "left", "right" or "stop" and your robot car obeys.',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFC4B5FD),
      requiredParts: [
        'The robot car from "Beat Reactive Dancer" (Left Motor + Right Motor)',
        'Phone microphone (speech recognition may need an internet connection)',
      ],
      conceptDescription:
          'The phone\'s speech recogniser turns what you say into text. A Heard '
          'block is true when that text contains its word. The motors keep '
          'doing the last command until a new one arrives, so we check "stop" '
          'FIRST — that way "stop" always wins, even if the phone heard "drive" '
          'and "stop" together.',
      steps: [
        TutorialStep(text: _carSetup),
        TutorialStep(
          text:
              'Drag a Forever block. Inside it add an If with the Heard block '
              '(Sensors) as its condition. Tap Heard\'s text box and type stop '
              '(it starts as "go"). In "then do": both motors [ STOP ]. This If '
              'goes first so "stop" always wins.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '🗣️ Heard  [ stop ]',
                  bodyNodes: _bothStop,
                ),
                _next,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Below it (still inside Forever) add If Heard [ drive ] → both '
              'motors [ FORWARD ].',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🗣️ Heard  [ drive ]',
              bodyNodes: _bothFwd,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Add two more Ifs for turning. Stopping one wheel makes the car '
              'pivot toward that side.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🗣️ Heard  [ left ]',
              bodyNodes: _pivotLeft,
            ),
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🗣️ Heard  [ right ]',
              bodyNodes: _pivotRight,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap RUN (allow microphone access the first time) and speak '
              'clearly: "drive", "left", "right", "stop". The robot keeps doing '
              'the last command until you say a new one.\n'
              'What the phone heard shows on the Home header; ⋮ › View Logs '
              'lists every motor command. ⚡ Snippets › Voice Control is a '
              'ready-made version (it uses "forward").',
        ),
      ],
    ),

    // ── 6 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_compass_patrol',
      title: 'Compass Patrol Bot',
      emoji: '🧭',
      shortDescription: 'A robot that always turns back to face North!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFE0E7FF),
      requiredParts: [
        'The robot car from "Beat Reactive Dancer"',
        'Phone standing upright on the car, back camera facing forward',
        'Phone compass (built-in magnetometer)',
      ],
      conceptDescription:
          'The magnetometer feels the Earth\'s magnetic field, so the phone '
          'knows which way it points: 0° = North, 90° = East, 180° = South, '
          '270° = West. With the phone upright on the robot, the heading is the '
          'direction the back camera looks — the way the robot faces. Facing '
          'Direction [ North ] is true when the robot points within about 22° '
          'of North.',
      steps: [
        TutorialStep(
          text:
              '$_carSetup\n'
              'Stand the phone upright on the car with the back camera looking '
              'forward, like a windshield.',
        ),
        TutorialStep(
          text:
              'Open Home › Configure Sensors › Compass and turn the car by hand: '
              'the heading should change smoothly. Stuck or jumpy? Wave the '
              'phone in a figure-8 to calibrate, and keep it away from metal, '
              'magnets and the motors.',
        ),
        TutorialStep(
          text:
              'In Blocks, drag a Forever block with an If / Else inside. Drop '
              'Facing Direction (Sensors) into the condition and leave it on '
              'North.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🧭 Facing Direction  [ North ]',
                  bodyNodes: [_next],
                  elseNodes: [_next],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              '"then do" (already facing North): both motors [ STOP ]. "else do" '
              '(not yet): Left Motor [ FORWARD ], Right Motor [ STOP ] — the car '
              'pivots right. Under the If / Else add Wait 0.1.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🧭 Facing Direction  [ North ]',
                  bodyNodes: _bothStop,
                  elseNodes: _pivotRight,
                ),
                _wait01,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap RUN: the car spins until it faces North, then stops. Turn it '
              'by hand — it spins back! Pick any of the 8 directions in the '
              'dropdown to choose a new "home".',
        ),
        TutorialStep(
          text:
              'Make a patrol: clear the canvas and build this. Each lap drives '
              'forward for 1 second, then Repeat Until pivots until the car faces '
              'North again. ⚡ Snippets › Compass Patrol drives a square '
              '(North, then East).',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔢',
              label: 'Repeat  [ 4 ]  times',
              colorValue: _logic,
              bodyNodes: [
                ..._bothFwd,
                _wait1,
                VisualBlockNode(
                  emoji: '🔂',
                  label: 'Repeat Until',
                  colorValue: _logic,
                  inlineCondition: '🧭 Facing Direction  [ North ]',
                  bodyNodes: _pivotRight,
                ),
                ..._bothStop,
              ],
            ),
          ],
        ),
      ],
    ),

    // ── 7 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_tilt_steering',
      title: 'Tilt Steering Robot',
      emoji: '📱',
      shortDescription:
          'Steer your robot by tilting your phone like a game controller!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFD1FAE5),
      requiredParts: [
        'The robot car from "Beat Reactive Dancer" with an ESP32 board — the '
            'phone stays in your hand, so it connects over Bluetooth, not USB',
        'USB power bank for the ESP32',
        'Phone accelerometer (built-in)',
      ],
      conceptDescription:
          'Your phone feels which way gravity pulls, so it knows how far it is '
          'tilted. Tilt Roll ° measures left/right tilt and Tilt Pitch ° '
          'forward/back tilt, in degrees (0 = flat). We compare those numbers '
          'with 20 to steer. This tutorial is all about comparisons: a check '
          'like "Tilt Roll ° > 20" is built from three blocks.',
      steps: [
        TutorialStep(
          text:
              'Build the car from "Beat Reactive Dancer" with an ESP32 (IN1 → '
              'GPIO 25, IN3 → GPIO 26; in Configure Hardware Pin 32 / 33, IN1 '
              'Pin 25 / 26). Connect: Home header › Bluetooth ("ESP32 Robot …").',
        ),
        TutorialStep(
          text:
              'Check your phone\'s numbers: Home › Configure Sensors › '
              'Accelerometer. Hold the phone flat like a tray (screen facing up, '
              'portrait). Tilt it to the RIGHT and watch Roll; tilt the top edge '
              'AWAY from you and watch Pitch.\n'
              'The steps below use what most phones show: tilt right = Roll '
              'below -20, tilt away = Pitch below -20. If your phone shows the '
              'opposite sign, swap the number (20 ↔ -20) and the comparison '
              'block (< ↔ >) in that step.',
        ),
        TutorialStep(
          text:
              '$_comparisonHowTo In the previews, [ ] shows what sits in each '
              'hole. Here is "Tilt Roll ° is less than -20":',
          blockPreview: [
            VisualBlockNode(
              emoji: '🤏',
              label: 'Less Than <   [ 📏 Tilt Roll ° ]  <  [ -20 ]',
              colorValue: _boolean,
              isBoolean: true,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Drag a Forever block with an If / Else inside. Use the comparison '
              'as its condition. "then do": Left Motor [ FORWARD ], Right Motor '
              '[ STOP ] (turn right). Under the If / Else add Wait 0.05.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🤏 [ 📏 Tilt Roll ° ] < [ -20 ]',
                  inlineConditionColor: _boolean,
                  bodyNodes: _pivotRight,
                  elseNodes: [_next],
                ),
                _wait005,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'In that "else do" put a second If / Else: Greater Than > with '
              'Tilt Roll ° and 20 → Left Motor [ STOP ], Right Motor [ FORWARD ] '
              '(turn left).',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔀',
              label: 'If / Else',
              colorValue: _logic,
              inlineCondition: '👐 [ 📏 Tilt Roll ° ] > [ 20 ]',
              inlineConditionColor: _boolean,
              bodyNodes: _pivotLeft,
              elseNodes: [_next],
            ),
          ],
        ),
        TutorialStep(
          text:
              'In the second "else do" put a third If / Else: Tilt Pitch ° < -20 '
              '→ both motors [ FORWARD ] (tilted away = drive), else both '
              '[ STOP ] (flat = stop). Because each check sits in the previous '
              '"else", exactly one action runs each time — no jitter.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔀',
              label: 'If / Else',
              colorValue: _logic,
              inlineCondition: '🤏 [ 📐 Tilt Pitch ° ] < [ -20 ]',
              inlineConditionColor: _boolean,
              bodyNodes: _bothFwd,
              elseNodes: _bothStop,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap RUN, hold the phone flat and tilt it: away = drive, right / '
              'left = turn, flat = stop. Turns the wrong way? Swap the signs as '
              'in step 2. Change 20 to make steering more or less sensitive. '
              '⚡ Snippets › Tilt Steering has a version that also reverses '
              '(it needs IN2 / IN4 wired for BACKWARD).',
        ),
      ],
    ),

    // ── 8 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_line_follower',
      title: 'Line Follower',
      emoji: '🛤️',
      shortDescription:
          'The camera watches the floor and your robot follows a tape line!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFDCFCE7),
      requiredParts: [
        'The robot car from "Beat Reactive Dancer"',
        'Dark tape on a light floor (or light tape on a dark floor)',
        'Phone holder: phone upright, back camera tilted down at the floor ahead',
      ],
      conceptDescription:
          'Line following uses real computer vision — Sobel edge detection, '
          'no AI model. The app looks at the bottom part of the camera picture, '
          'finds the strongest edge (your tape) and reports Line Offset X: -1 = '
          'far left of the picture, 0 = centre, +1 = far right. Line Visible is '
          'true while a clear line is seen.',
      steps: [
        TutorialStep(
          text:
              'Lay the tape in a big, gentle loop (no bends sharper than 45°). '
              'Keep the floor around it plain — patterns and shadows look like '
              'lines too.',
        ),
        TutorialStep(
          text:
              '$_carSetup\n'
              'Mount the phone upright on the front of the car, back camera '
              'facing forward and tilted down so it sees the floor 20–40 cm '
              'ahead.',
        ),
        TutorialStep(
          text:
              'Test the camera first: build Forever { Print to Log [ Line Offset '
              'X ], Wait 0.5 } (Print to Log is in Logic), tap RUN and open ⋮ › '
              'View Logs. Slide the tape left and right in front of the camera: '
              'the number goes negative on the left, positive on the right.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🖨️',
                  label: 'Print to Log',
                  colorValue: _action,
                  inlineCondition: '↔️ Line Offset X',
                ),
                _wait05,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Now the real program (clear the canvas first): Forever with an If '
              '/ Else inside, Line Visible as the condition, and both motors '
              '[ STOP ] in "else do". The car waits when it loses the line and '
              'carries on when it sees it again.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🛤️ Line Visible',
                  bodyNodes: [_next],
                  elseNodes: _bothStop,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'In "then do" add three Ifs. $_comparisonHowTo The third one needs '
              'AND (Logic): it has two holes — a Greater Than goes in the left one '
              'and a Less Than in the right one.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — line on the left',
              colorValue: _logic,
              inlineCondition: '🤏 [ ↔️ Line Offset X ] < [ -0.15 ]',
              inlineConditionColor: _boolean,
              bodyNodes: _pivotLeft,
            ),
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — line on the right',
              colorValue: _logic,
              inlineCondition: '👐 [ ↔️ Line Offset X ] > [ 0.15 ]',
              inlineConditionColor: _boolean,
              bodyNodes: _pivotRight,
            ),
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — line in the middle',
              colorValue: _logic,
              inlineCondition:
                  '& [ 👐 [ ↔️ Line Offset X ] > [ -0.15 ] ]  AND  '
                  '[ 🤏 [ ↔️ Line Offset X ] < [ 0.15 ] ]',
              inlineConditionColor: _boolean,
              bodyNodes: _bothFwd,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Put the car on the tape, tap RUN and watch it follow!\n'
              '• Wobbles a lot → widen 0.15 to 0.25.\n'
              '• Turns away from the line → swap the motor blocks between the '
              'first two Ifs.\n'
              '• Too fast → add Wait 0.05, both motors [ STOP ], Wait 0.05 at the '
              'end of "then do" so it moves in little steps.\n'
              '⚡ Snippets › Line Follower loads a ready-made version.',
        ),
      ],
    ),

    // ── 9 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_fetch_bot',
      title: 'Fetch Bot',
      emoji: '🎾',
      shortDescription:
          'Your robot searches for a bottle or ball, drives to it and stops when it arrives!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFFEF3C7),
      requiredParts: [
        'The robot car from "Beat Reactive Dancer"',
        'Phone standing upright on the car, back camera facing forward',
        'A bottle or a sports ball (big and colourful works best)',
      ],
      conceptDescription:
          'The robot hunts for an object: it turns in small steps until the AI '
          'camera locks on, drives toward it while steering to keep it centred, '
          'and stops when the object fills 35% of the picture (that means it is '
          'close). Target X Offset says where the object is (-1 left … +1 '
          'right) and Target Size % how big it looks (0–100).',
      steps: [
        TutorialStep(
          text:
              '$_carSetup\n'
              'Stand the phone upright, camera forward, and put a bottle 0.5–1 m '
              'in front of the robot. In Vision Settings ($_visionSettingsPath) '
              'select bottle, or leave nothing selected.',
        ),
        TutorialStep(
          text:
              'The whole program lives in a Forever block. First the search: '
              'inside Forever add Repeat Until (Logic) with Lock Object Type '
              '(Sensors) set to bottle as its condition. Inside: turn for 0.06 s, '
              'then stop and wait 0.08 s — the robot turns in small steps until it '
              'locks on.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔂',
                  label: 'Repeat Until',
                  colorValue: _logic,
                  inlineCondition: '🎯 Lock Object Type  [ bottle ]',
                  bodyNodes: [..._pivotRight, _wait006, _leftStop, _wait008],
                ),
                _next,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Next the approach, below the Repeat Until (still inside Forever): '
              'a While whose condition is AND with Object Locked in the left hole '
              'and "Target Size % < 35" in the right hole. Inside, drive in '
              'pulses and steer: if the bottle is right of centre, stop the right '
              'wheel; if it is left, stop the left wheel.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition:
                  '& [ 🎯 Object Locked ]  AND  [ 🤏 [ 📏 Target Size % ] < [ 35 ] ]',
              inlineConditionColor: _boolean,
              bodyNodes: [
                ..._bothFwd,
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '👐 [ ↔️ Target X Offset ] > [ 0.2 ]',
                  inlineConditionColor: _boolean,
                  bodyNodes: [_rightStop],
                ),
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '🤏 [ ↔️ Target X Offset ] < [ -0.2 ]',
                  inlineConditionColor: _boolean,
                  bodyNodes: [_leftStop],
                ),
                _wait006,
                ..._bothStop,
                _wait008,
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Arrived, or lost it? Below the While (still inside Forever) add an '
              'If: when Target Size % is above 34 the robot has arrived — stop, '
              'say something and end the program. If the lock was lost instead, '
              'Target Size % is 0, so Forever simply starts searching again.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '👐 [ 📏 Target Size % ] > [ 34 ]',
              inlineConditionColor: _boolean,
              bodyNodes: [
                ..._bothStop,
                VisualBlockNode(emoji: '💬', label: 'Say  [ Got it! ]', colorValue: _action),
                VisualBlockNode(emoji: '🛑', label: 'Stop Program', colorValue: _logic),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap RUN. The robot searches, locks on, drives to the bottle and '
              'says "Got it!". Hide the bottle and try again, or pick "sports '
              'ball", "cup" or "teddy bear" in the Lock Object Type dropdown (and '
              'in Vision Settings). Tune the 0.06 / 0.08 Waits for speed.\n'
              '⚡ Snippets › Fetch Bot does all of this with one Smart Follow '
              'block.',
        ),
      ],
    ),

    // ── 10 ────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_person_follower',
      title: 'Person-Following Robot Car',
      emoji: '🤖',
      shortDescription:
          'Your robot car follows you around using live AI person detection.',
      difficulty: Difficulty.hard,
      cardColor: Color(0xFF93C5FD),
      requiredParts: [
        'The robot car from "Beat Reactive Dancer"',
        'Phone standing upright on the car, back camera facing forward',
        'Plenty of floor space',
      ],
      conceptDescription:
          'The AI camera finds a person and reports Target X Offset: -1 means '
          'the person is at the far left of the picture, +1 the far right, 0 '
          'perfectly centred. When the person drifts left we pivot left by '
          'stopping the left wheel; drifting right, we stop the right wheel; '
          'centred, we drive straight — unless Target Size % says they are '
          'already close. We move in short pulses so the camera gets a sharp '
          'picture between moves.',
      steps: [
        TutorialStep(
          text:
              '$_carSetup\n'
              'Stand the phone upright, back camera facing forward. In Vision '
              'Settings ($_visionSettingsPath) select person, or leave nothing '
              'selected.',
        ),
        TutorialStep(
          text:
              'The pattern: Forever with an If / Else inside. Condition: Lock '
              'Object Type (Sensors) set to person. "else do": both motors '
              '[ STOP ]. If the person disappears for a moment, the car stops '
              'and waits instead of ending the program.',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🎯 Lock Object Type  [ person ]',
                  bodyNodes: [_next],
                  elseNodes: _bothStop,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Steer LEFT: in "then do" add an If. $_comparisonHowTo Here: Less '
              'Than <, Target X Offset, and -0.2.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🤏 [ ↔️ Target X Offset ] < [ -0.2 ]',
              inlineConditionColor: _boolean,
              bodyNodes: _pivotLeft,
            ),
          ],
        ),
        TutorialStep(
          text: 'Steer RIGHT: below it add a second If with Greater Than > and 0.2.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '👐 [ ↔️ Target X Offset ] > [ 0.2 ]',
              inlineConditionColor: _boolean,
              bodyNodes: _pivotRight,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Drive forward when centred AND not too close — three checks. AND '
              'has only two holes, so put an AND inside the left hole of another '
              'AND:\n'
              '• inner AND: Target X Offset > -0.2 and Target X Offset < 0.2\n'
              '• outer AND: that inner AND and Target Size % < 40\n'
              'Target Size % is how much of the picture the person fills; under '
              '40 means not too close.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition:
                  '& [ & [ 👐 [ ↔️ X Offset ] > [ -0.2 ] ] AND [ 🤏 [ ↔️ X Offset ] < [ 0.2 ] ] ]'
                  '  AND  [ 🤏 [ 📏 Target Size % ] < [ 40 ] ]',
              inlineConditionColor: _boolean,
              bodyNodes: _bothFwd,
            ),
          ],
        ),
        TutorialStep(
          text:
              'The pulse trick: at the bottom of "then do" (below the three Ifs) '
              'add Wait 0.06, both motors [ STOP ], Wait 0.08. The car moves in '
              'small steps and the camera gets a steady picture. 0.06 is the '
              'move time and 0.08 the pause — tune them for your robot.',
          blockPreview: [_wait006, _leftStop, _rightStop, _wait008],
        ),
        TutorialStep(
          text:
              'Tap RUN and step in front of the car — it follows you!\n'
              '• A wheel spins backwards → swap its wires on OUT1/OUT2 (or '
              'OUT3/OUT4).\n'
              '• The car turns AWAY from you → in Configure Hardware swap the IN1 '
              'pins of Left Motor and Right Motor (5 ↔ 6).\n'
              '• Overshoots → raise 0.08 to 0.10 or widen 0.2 to 0.3.\n'
              '• Not detected → check Vision Settings and the lighting, and '
              'look in ⋮ › View Logs.\n'
              '⚡ Snippets › Person Follower loads a complete version.',
        ),
      ],
    ),

    // ── 11 ────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_servo_follower',
      title: 'Servo-Wheel Person Follower',
      emoji: '🔄',
      shortDescription:
          'Build a person follower with two continuous-rotation servos as wheels — no motor driver!',
      difficulty: Difficulty.hard,
      cardColor: Color(0xFFA5F3FC),
      requiredParts: [
        '2x continuous-rotation servos (e.g. FS90R) as wheels on a chassis',
        'Arduino Uno / Mega or ESP32 with the firmware from "Connect & Hello LED"',
        '4x AA battery pack for the servos (its − joined to the board GND)',
        'Phone standing upright on the robot, back camera facing forward',
      ],
      conceptDescription:
          'Continuous-rotation servos work like motors, but they are steered by '
          'the length of a pulse: 1500 µs = stop, 1700 µs = full forward, '
          '1300 µs = full reverse. Their signal wire goes straight to a board '
          'pin — no motor driver. A servo keeps doing its last command, so the '
          'program must stop the wheels itself when the person is close.',
      steps: [
        TutorialStep(
          text:
              'Wire each servo: signal (yellow/white) → pin 9 for the left wheel '
              'and pin 10 for the right (ESP32: GPIO 18 / 19); red → battery +; '
              'brown/black → battery − AND board GND.',
        ),
        TutorialStep(
          text:
              'Home › ⚙️ Configure Hardware › Add Actuator: Name Left Wheel, Type '
              'Servo (change it from Motor!), Pin 9 (ESP32: 18), and switch on '
              '"Continuous Rotation Servo" (min/max fill in 1300 / 1700 µs). '
              'Repeat for Right Wheel on pin 10 (ESP32: 19). The servos sit '
              'mirrored on the chassis, so switch on "Invert direction" for one '
              'of them. Ignore the extra "Track X" blocks — they are for normal '
              'servos.',
        ),
        TutorialStep(
          text:
              'Connect ($_connectHowTo) and test: build Left Wheel [ FORWARD ] '
              '50 %, Right Wheel [ FORWARD ] 50 %, Wait 2, both [ STOP ] and tap '
              'RUN. Both wheels should roll forward. One goes backwards? Flip its '
              '"Invert direction". A wheel creeps on STOP? Turn the small trim '
              'screw on that servo until it stands still.',
          blockPreview: [
            VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ FORWARD ]  50 %', colorValue: _action),
            VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ FORWARD ]  50 %', colorValue: _action),
            VisualBlockNode(emoji: '⏱️', label: 'Wait  [ 2 ]  seconds', colorValue: _logic),
            VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ STOP ]', colorValue: _action),
            VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ STOP ]', colorValue: _action),
          ],
        ),
        TutorialStep(
          text:
              'Use the same pattern as the Person-Following car: Forever › If / '
              'Else with Lock Object Type [ person ]; "else do": both wheels '
              '[ STOP ].',
          blockPreview: [
            VisualBlockNode(
              emoji: '♾️',
              label: 'Forever',
              colorValue: _logic,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔀',
                  label: 'If / Else',
                  colorValue: _logic,
                  inlineCondition: '🎯 Lock Object Type  [ person ]',
                  bodyNodes: [_next],
                  elseNodes: [
                    VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ STOP ]', colorValue: _action),
                    VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ STOP ]', colorValue: _action),
                  ],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'In "then do" add four Ifs (build the comparisons as in the '
              'Person-Following car). The last one is important: servos keep '
              'their last command, so when the person is close we must stop '
              'them — otherwise the robot drives right into them.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — person on the left',
              colorValue: _logic,
              inlineCondition: '🤏 [ ↔️ Target X Offset ] < [ -0.15 ]',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ FORWARD ]  60 %', colorValue: _action),
              ],
            ),
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — person on the right',
              colorValue: _logic,
              inlineCondition: '👐 [ ↔️ Target X Offset ] > [ 0.15 ]',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ FORWARD ]  60 %', colorValue: _action),
                VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ STOP ]', colorValue: _action),
              ],
            ),
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — centred and far',
              colorValue: _logic,
              inlineCondition:
                  '& [ & [ 👐 [ ↔️ X Offset ] > [ -0.15 ] ] AND [ 🤏 [ ↔️ X Offset ] < [ 0.15 ] ] ]'
                  '  AND  [ 🤏 [ 📏 Target Size % ] < [ 40 ] ]',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ FORWARD ]  50 %', colorValue: _action),
                VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ FORWARD ]  50 %', colorValue: _action),
              ],
            ),
            VisualBlockNode(
              emoji: '❓',
              label: 'If  — too close',
              colorValue: _logic,
              inlineCondition: '👐 [ 📏 Target Size % ] > [ 40 ]',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(emoji: '🔄', label: 'Left Wheel  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '🔄', label: 'Right Wheel  [ STOP ]', colorValue: _action),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tap RUN and step in front of the camera — the servo robot follows '
              'you! Tune the speed % (try 40–70 %) for your chassis. It turns '
              'away from you? Swap the pins of Left Wheel and Right Wheel in '
              'Configure Hardware.',
        ),
      ],
    ),
  ];
}
