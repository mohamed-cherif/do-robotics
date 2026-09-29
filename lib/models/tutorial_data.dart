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

  /// When true the block is rendered with a hexagonal/pill outline, like a
  /// boolean sensor block.
  final bool isBoolean;

  /// Optional text shown in an inline "condition chip" (e.g. the sensor name
  /// that goes inside an If/While condition slot).
  final String? inlineCondition;

  /// Color of the inline condition chip (default: purple sensor color).
  final int inlineConditionColor;

  /// Blocks rendered inside this block's body (do / then slot).
  final List<VisualBlockNode> bodyNodes;

  const VisualBlockNode({
    required this.emoji,
    required this.label,
    required this.colorValue,
    this.isBoolean = false,
    this.inlineCondition,
    this.inlineConditionColor = 0xFF8B5CF6,
    this.bodyNodes = const [],
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
const int _sensor = 0xFF8B5CF6; // purple
const int _logic = 0xFF10B981; // green
const int _action = 0xFFF59E0B; // amber
const int _boolean = 0xFFEC4899; // pink

// ─────────────────────────────────────────────────────────────────────────────
// Tutorial repository
// ─────────────────────────────────────────────────────────────────────────────

class TutorialRepository {
  static const List<TutorialData> tutorials = [
    // ── 1 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_clap_light',
      title: 'Clap-On Smart Light',
      emoji: '👏',
      shortDescription: 'Turn an LED on and off by clapping loudly!',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFFFDE68A),
      requiredParts: [
        '1x LED module (e.g. Pin 13)',
        'Phone Microphone enabled',
      ],
      conceptDescription:
          'Microphones turn sound into electricity. We can use our '
          "phone's microphone to listen for sudden bursts of loudness—like a "
          'clap—and use it as a switch!',
      steps: [
        TutorialStep(
          text: 'Go to Actuators Settings and configure your LED on Pin 13.',
        ),
        TutorialStep(
          text: 'Drag out a While loop from the Logic tab. Drop a True boolean '
              'block into its condition slot so it runs forever.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '✅  True',
              inlineConditionColor: _boolean,
            ),
          ],
        ),
        TutorialStep(
          text: 'Inside the loop, drag an If block into the "do" slot.',
        ),
        TutorialStep(
          text: 'Drag the Loud Noise sensor block into the If condition slot.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🔊  Loud Noise',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '…',
                  label: 'then do:  (next step)',
                  colorValue: 0xFF64748B,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text: 'Inside the "then do" section, drag in your LED block and set '
              'it to TOGGLE.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🔊  Loud Noise',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '💡',
                  label: 'LED (Pin 13)   [ TOGGLE ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text: "Below the If block (still inside the While loop), add a Wait "
              "0.5s block so it doesn't trigger multiple times on one long clap.",
          blockPreview: [
            VisualBlockNode(
              emoji: '⏱️',
              label: 'Wait   [ 0.5 ]   seconds',
              colorValue: _logic,
            ),
          ],
        ),
        TutorialStep(
          text: 'Tap Play and clap loudly at your phone!',
        ),
      ],
    ),

    // ── 2 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_person_follower',
      title: 'Person-Following Robot Car',
      emoji: '🤖',
      shortDescription:
          'Wire a 2-wheel car to your phone and watch it follow you '
          'using live AI person detection — no coding required!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFF93C5FD),
      requiredParts: [
        'Arduino Uno',
        'L298N H-Bridge motor driver',
        '2x DC motors (Left & Right wheels)',
        'External battery for motors (4–9 V)',
        'USB cable (Arduino ↔ phone, with OTG adapter)',
        'Phone Camera (back camera recommended)',
      ],
      conceptDescription:
          'Your phone\'s AI camera detects a person and returns a Target X '
          'Offset value: –1 means the person is all the way to the left of '
          'the frame, +1 means all the way to the right, 0 is perfectly '
          'centred. We use this number to steer a differential-drive car: '
          'when the person drifts left we pivot left by stopping the left '
          'wheel; when they drift right we pivot right; when centred we '
          'drive straight forward. The L298N H-Bridge amplifies the tiny '
          'Arduino signal into enough power to spin the motors. Because IN2 '
          'and IN4 are wired directly to GND, each motor has two states: '
          'FORWARD (pin HIGH) and STOP (pin LOW) — simple and reliable.',
      steps: [
        // ── Hardware wiring ────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 1 — Wire the H-Bridge to the Arduino.\n\n'
              '• L298N  IN1  →  Arduino pin 5   (Left motor direction)\n'
              '• L298N  IN3  →  Arduino pin 6   (Right motor direction)\n'
              '• L298N  IN2  →  GND  (solder or jumper directly on the board)\n'
              '• L298N  IN4  →  GND  (same)\n'
              '• Leave the ENA and ENB jumper caps ON — motors run at full '
              'speed automatically.\n'
              '• L298N  GND  →  Arduino GND  AND  battery negative\n'
              '• L298N  +12V →  motor battery positive (4–9 V)\n'
              '• L298N  +5V  →  Arduino 5V (only safe if motor battery ≤ 12 V)\n\n'
              'Your motors are already connected to OUT1/OUT2 (Left) and '
              'OUT3/OUT4 (Right) — that part is done.',
        ),
        // ── Firmware upload ────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 2 — Upload the DO Robotics firmware to the Arduino.\n\n'
              '1. Open Arduino IDE on your computer.\n'
              '2. Open the file:  arduino/receiver_uno/receiver_uno.ino\n'
              '   (inside the DO Robotics project folder).\n'
              '3. Select Board: Arduino Uno and the correct COM port.\n'
              '4. Click Upload (→ arrow button).\n'
              '5. The built-in LED (pin 13) will flash 3 times when the '
              'firmware boots — that means it\'s ready.\n\n'
              'The firmware listens for 5-byte packets from the app and '
              'sets each pin HIGH or LOW accordingly.',
        ),
        // ── Connect the app ────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 3 — Connect your phone to the Arduino.\n\n'
              '1. Plug the USB cable into the Arduino and into your phone '
              '(you may need a USB-OTG adapter).\n'
              '2. Open the DO Robotics app.\n'
              '3. Go to the Connect tab and tap "USB Serial".\n'
              '4. Select the Arduino port and tap Connect.\n'
              '5. The status indicator should turn green. The Arduino LED '
              'will flash each time the app sends a command.',
        ),
        // ── Configure actuators ────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 4 — Configure the two motors in the app.\n\n'
              'Go to Actuator Settings (⚙️ icon) and tap + twice:\n\n'
              'Motor 1 — Left Motor:\n'
              '  • Name: Left Motor\n'
              '  • Type: Motor\n'
              '  • Pin: (leave at any value, it is not used)\n'
              '  • IN1 Pin: 5\n'
              '  • IN2 Pin: None  ← important! leave blank\n\n'
              'Motor 2 — Right Motor:\n'
              '  • Name: Right Motor\n'
              '  • Type: Motor\n'
              '  • Pin: (leave at any value)\n'
              '  • IN1 Pin: 6\n'
              '  • IN2 Pin: None  ← same here\n\n'
              'With IN2 set to None the app uses single-pin mode: '
              'FORWARD = pin HIGH, STOP = pin LOW.',
        ),
        // ── While loop ────────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 5 — Start the program with a While loop.\n\n'
              'Drag a While block onto the canvas. Drag the '
              '"🎯 Lock: person" sensor block into its condition slot. '
              'The loop runs only while a person is visible — as soon as '
              'the person leaves the frame it exits and both motors stop.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '🎯  Lock: person',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '…',
                  label: 'steering logic goes here  (steps 6 – 8)',
                  colorValue: 0xFF64748B,
                ),
              ],
            ),
          ],
        ),
        // ── Pivot left ────────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 6 — Steer LEFT when the person drifts left.\n\n'
              'Inside the While loop, add an If block. Set its condition to:\n'
              '"↔️ X Offset  <  −0.20"\n\n'
              'Inside the If body:\n'
              '  • Left Motor  [ STOP ]\n'
              '  • Right Motor [ FORWARD ]\n\n'
              'Stopping the left wheel while the right keeps spinning '
              'pivots the car to the left — chasing the person.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '↔️  X Offset  <  −0.20',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ STOP ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ FORWARD ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        // ── Pivot right ───────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 7 — Steer RIGHT when the person drifts right.\n\n'
              'Add a second If block (below the first, still inside While):\n'
              '"↔️ X Offset  >  0.20"\n\n'
              'Inside the If body:\n'
              '  • Left Motor  [ FORWARD ]\n'
              '  • Right Motor [ STOP ]\n\n'
              'Now the right wheel stops and the left spins, pivoting right.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '↔️  X Offset  >  0.20',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ FORWARD ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ STOP ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        // ── Drive forward ─────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 8 — Drive forward when the person is centred and '
              'not too close.\n\n'
              'Add a third If block inside the While loop. Use an AND block '
              'as the condition with three sub-conditions:\n'
              '  • X Offset  >  −0.20\n'
              '  • X Offset  <   0.20\n'
              '  • Target Size  <  40\n\n'
              '"Target Size" is how much of the screen the person fills '
              '(0–100 %). Keeping it under 40 % prevents the car from '
              'running into the person.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '&  Centred  AND  not too close',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ FORWARD ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ FORWARD ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        // ── Safety stop ───────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 9 — The Pulsed Movement Trick!\n\n'
              'To stop the car from moving too fast and overshooting, we add a '
              'pulsed delay at the bottom of the While loop (inside it, below the Ifs):\n'
              '  • Wait [ 0.06 ] seconds\n'
              '  • Left Motor [ STOP ]\n'
              '  • Right Motor [ STOP ]\n'
              '  • Wait [ 0.08 ] seconds\n\n'
              'This forces the robot to take small "steps" and gives the camera '
              'time to process the next frame. You can edit the 0.06 (pulse) and 0.08 (pause) values '
              'to find the perfect speed and accuracy for your robot!',
          blockPreview: [
            VisualBlockNode(
              emoji: '⏱️',
              label: 'Wait   [ 0.06 ]   seconds',
              colorValue: _logic,
            ),
            VisualBlockNode(
              emoji: '⚙️',
              label: 'Left Motor   [ STOP ]',
              colorValue: _action,
            ),
            VisualBlockNode(
              emoji: '⚙️',
              label: 'Right Motor   [ STOP ]',
              colorValue: _action,
            ),
            VisualBlockNode(
              emoji: '⏱️',
              label: 'Wait   [ 0.08 ]   seconds',
              colorValue: _logic,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Step 10 — Add a safety stop after the While loop.\n\n'
              'Drag two motor blocks BELOW and OUTSIDE the While loop '
              '(not inside its body). Set both to STOP.\n\n'
              'When the person leaves the frame the loop exits and these '
              'blocks run immediately — the car halts cleanly.',
          blockPreview: [
            VisualBlockNode(
              emoji: '⚙️',
              label: 'Left Motor   [ STOP ]',
              colorValue: _action,
            ),
            VisualBlockNode(
              emoji: '⚙️',
              label: 'Right Motor   [ STOP ]',
              colorValue: _action,
            ),
          ],
        ),
        // ── Run it ────────────────────────────────────────────────────────
        TutorialStep(
          text:
              'Step 11 — Run it!\n\n'
              '1. Place the phone on top of the car, camera facing forward.\n'
              '2. Make sure the Arduino is connected via USB.\n'
              '3. Tap ▶ Play.\n'
              '4. Step in front of the car — it will lock on to you and '
              'start following!\n\n'
              'Troubleshooting:\n'
              '• Car turns the wrong way → swap the motor wires on OUT1/OUT2 '
              'or OUT3/OUT4 on the H-bridge.\n'
              '• Car doesn\'t move → check USB connection and that the '
              'firmware is uploaded.\n'
              '• Car overshoots and keeps turning → increase the 0.08 pause to 0.10, or '
              'expand the 0.20 threshold.\n'
              '• Person not detected → go to the Vision tab and confirm the '
              '"person" label is enabled.',
        ),
      ],
    ),

    // ── 3 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_servo_follower',
      title: 'Servo-Wheel Person Follower',
      emoji: '🔄',
      shortDescription:
          'Use two continuous rotation servos as wheels to build a person-following '
          'robot — no motor driver needed!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFA5F3FC),
      requiredParts: [
        '2x Continuous Rotation Servos (e.g. FS90R)',
        'Phone Camera (back camera recommended)',
      ],
      conceptDescription:
          'Continuous rotation servos work like motors but are controlled by a '
          'PWM pulse width instead of a speed voltage. A 1500 µs pulse = stop, '
          '1700 µs = full forward, 1300 µs = full reverse. In the app, enable '
          '"Continuous Rotation" when configuring each servo — then use the '
          'familiar FORWARD / BACKWARD / STOP commands with a 0–100 % speed '
          'slider. The steering logic is identical to the DC motor follower: '
          'compare Target X Offset to decide which wheel to slow down or reverse.',
      steps: [
        TutorialStep(
          text:
              'In Actuator Settings, tap + and add a servo named "Left Wheel". '
              'Enable the "Continuous Rotation Servo" toggle — the min/max '
              'fields will auto-fill to 1300 / 1700 µs. Repeat for "Right Wheel" '
              'on a different pin.',
        ),
        TutorialStep(
          text:
              'Start the script with a While loop. Drop the Object Locked sensor '
              '(set to person) into the condition slot so it runs only while a '
              'person is visible.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '🎯  Lock: person',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '…',
                  label: 'steering logic goes here (steps 3–5)',
                  colorValue: 0xFF64748B,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Steer LEFT: if the person drifts to the left (X Offset < -0.15), '
              'stop the left servo and drive the right servo forward.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '↔️ X Offset  <  -0.15',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔄',
                  label: 'Left Wheel   [ STOP ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '🔄',
                  label: 'Right Wheel   [ FORWARD ]   60 %',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Steer RIGHT: if the person drifts to the right (X Offset > 0.15), '
              'drive the left servo forward and stop the right servo.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '↔️ X Offset  >  0.15',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔄',
                  label: 'Left Wheel   [ FORWARD ]   60 %',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '🔄',
                  label: 'Right Wheel   [ STOP ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Drive forward when centred and not too close. Use an AND block: '
              '(X Offset > -0.15) AND (X Offset < 0.15) AND (Target Size < 40).',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '& Centred AND not too close',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '🔄',
                  label: 'Left Wheel   [ FORWARD ]   50 %',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '🔄',
                  label: 'Right Wheel   [ FORWARD ]   50 %',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Safety stop! After the While loop (outside it), add STOP blocks '
              'for both servos. When the person leaves frame the loop exits and '
              'the app sends 1500 µs automatically — wheels halt.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔄',
              label: 'Left Wheel   [ STOP ]',
              colorValue: _action,
            ),
            VisualBlockNode(
              emoji: '🔄',
              label: 'Right Wheel   [ STOP ]',
              colorValue: _action,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tip: if a wheel spins the wrong way, swap FORWARD ↔ BACKWARD in '
              'its blocks — or physically flip the servo on the chassis so both '
              'wheels face the same direction.',
        ),
        TutorialStep(
          text:
              'Tap Play, step in front of the camera, and watch the servo robot '
              'track you! Tune the speed % (try 40–70 %) to match your chassis.',
        ),
      ],
    ),

    // ── 4 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_voice_bot',
      title: 'Voice Commanded Robot',
      emoji: '🗣️',
      shortDescription:
          'Tell your robot to "drive", "turn", or "stop" using live voice '
          'recognition.',
      difficulty: Difficulty.hard,
      cardColor: Color(0xFFC4B5FD),
      requiredParts: [
        '2x DC Motors (Left & Right wheels)',
        'Phone Microphone enabled',
      ],
      conceptDescription:
          'The neural engine in the app transcribes spoken words into text in '
          'real-time. By comparing the text we hear against specific command '
          'words, we can trigger different physical actions.',
      steps: [
        TutorialStep(
          text:
              'Drag out a While True endless loop to keep the robot listening.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '✅  True',
              inlineConditionColor: _boolean,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Inside the loop, drag an If block. Use the Heard voice sensor '
              'as the condition and type "drive" in the text field.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🗣️  Heard "drive"',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ FORWARD ]   200',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ FORWARD ]   200',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text: 'Add an If block for turning right.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🗣️  Heard "right"',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ FORWARD ]   150',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ BACKWARD ]   150',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text: 'Add an If block for the "stop" command.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🗣️  Heard "stop"',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ STOP ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ STOP ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Tip: Voice commands execute the moment they are heard. Motors '
              'keep their last commanded state until a new command arrives—so '
              'saying "drive" once makes the robot keep driving until you say '
              '"stop"!',
        ),
      ],
    ),

    // ── 4 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_beat_dancer',
      title: 'Beat Reactive Dancer',
      emoji: '🎵',
      shortDescription:
          'Make your robot spin and boogie whenever it hears loud music or '
          'clapping!',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFF86EFAC),
      requiredParts: [
        '2x DC Motors (Left & Right wheels)',
        '1x H-Bridge Motor Driver',
        'Phone Microphone enabled',
      ],
      conceptDescription:
          "Your phone's microphone continuously measures how loud the "
          'environment is. When the sound level crosses a threshold (a sudden '
          'beat or clap), we trigger FORWARD on one motor and BACKWARD on the '
          'other—making the robot spin in place. When it goes quiet, both '
          'motors stop. The result: a dancing robot!',
      steps: [
        TutorialStep(
          text:
              'In Actuator Settings, configure a Left Motor and a Right Motor '
              '(both with H-Bridge enabled).',
        ),
        TutorialStep(
          text:
              'Create a While True loop so the dancer is always listening for '
              'a beat.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '✅  True',
              inlineConditionColor: _boolean,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Inside the loop, add an If block with Loud Noise as the '
              'condition. In the do section, set both motors to spin in '
              'opposite directions—this creates a dance spin!',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🔊  Loud Noise',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ FORWARD ]   200',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ BACKWARD ]   200',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Add a second If block right below the first. Use a NOT block '
              'around the Loud Noise sensor—this handles the quiet moments and '
              'stops the robot.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '!  NOT  🔊 Loud Noise',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Left Motor   [ STOP ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '⚙️',
                  label: 'Right Motor   [ STOP ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'At the bottom of the While loop (after both If blocks), add a '
              'Wait 0.2s block to prevent flickering on sustained loud noise.',
          blockPreview: [
            VisualBlockNode(
              emoji: '⏱️',
              label: 'Wait   [ 0.2 ]   seconds',
              colorValue: _logic,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Press Play and blast some music! The robot will start spinning '
              'on every beat. Experiment with motor speeds to change the dance '
              'style.',
        ),
      ],
    ),

    // ── 5 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_ai_guard',
      title: 'AI Security Guard',
      emoji: '🚨',
      shortDescription:
          'Use the AI camera to detect motion or a face and trigger an LED '
          'alarm!',
      difficulty: Difficulty.hard,
      cardColor: Color(0xFFFCA5A5),
      requiredParts: [
        '1x LED module (e.g. Pin 13)',
        '1x Buzzer module (e.g. Pin 12)',
        'Phone Camera (front or back)',
      ],
      conceptDescription:
          'The object-detection model inside the app can spot people, faces, '
          'and common objects in real time. By monitoring whether anything is '
          'detected in the camera frame, we can trigger an alarm circuit. '
          'When no object is present, the alarm stays off. The moment '
          'something appears, LED and buzzer fire simultaneously—just like a '
          'real security system!',
      steps: [
        TutorialStep(
          text:
              'In Actuator Settings, add an LED on Pin 13 and a Buzzer on '
              'Pin 12.',
        ),
        TutorialStep(
          text:
              'Go to Vision Settings and make sure "Face" (or the object you '
              'want to detect) is enabled. Point the camera toward the area '
              'you want to guard.',
        ),
        TutorialStep(
          text:
              'Build the main loop: While True so the guard never sleeps.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '✅  True',
              inlineConditionColor: _boolean,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Intruder detected! Add an If block with Object Detected as the '
              'condition. Inside, turn ON both the LED and the Buzzer.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '👁️  Object Detected',
              inlineConditionColor: _sensor,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '💡',
                  label: 'LED (Pin 13)   [ ON ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '🔔',
                  label: 'Buzzer (Pin 12)   [ ON ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'All clear! Add a second If block for when nothing is detected—'
              'turn both the LED and Buzzer OFF.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '!  NOT  👁️ Object Detected',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '💡',
                  label: 'LED (Pin 13)   [ OFF ]',
                  colorValue: _action,
                ),
                VisualBlockNode(
                  emoji: '🔔',
                  label: 'Buzzer (Pin 12)   [ OFF ]',
                  colorValue: _action,
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Add a Wait 0.5s block at the bottom of the loop to prevent '
              'rapid flickering when objects briefly pass in and out of frame.',
          blockPreview: [
            VisualBlockNode(
              emoji: '⏱️',
              label: 'Wait   [ 0.5 ]   seconds',
              colorValue: _logic,
            ),
          ],
        ),
        TutorialStep(
          text:
              'Press Play, then walk in front of the camera. The alarm will '
              'trigger immediately! Try adjusting the camera angle to cover '
              'a doorway or window.',
        ),
      ],
    ),

    // ── 7 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_fetch_bot',
      title: 'Fetch Bot',
      emoji: '🎾',
      shortDescription: 'Robot finds a ball, drives to it, and stops when it gets close!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFFEF3C7),
      requiredParts: [
        '2x DC motors + L298N H-bridge',
        'Arduino Uno + USB-OTG or Bluetooth',
        'A tennis ball, sports ball, or bottle',
        'Phone Camera enabled',
      ],
      conceptDescription:
          'Instead of chasing a moving person, the robot hunts for a stationary '
          'object using AI object detection. It spins to search, locks on, '
          'steers toward it, and stops when the target fills 35% of the frame '
          '(meaning it is close). Much more reliable than person following '
          'because the target does not move!',
      steps: [
        TutorialStep(
          text:
              'Place a tennis ball (or any COCO object like a bottle or cup) '
              'about 1.5–2 m in front of the robot. Set up your motors as in '
              'the Person Follower tutorial and confirm connection.',
        ),
        TutorialStep(
          text:
              'First, the search loop. Add a While loop that runs while the robot is NOT '
              'locked onto the ball. Inside, create a pulse: turn for 0.06s, then stop and Wait for 0.08s. '
              'This makes the robot search in small, deliberate steps. '
              'You can tweak these values to spin faster or slower.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '!  NOT  🎯 Lock: sports ball',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]   180', colorValue: _action),
                VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '⏱️', label: 'Wait   [ 0.06 ]   seconds', colorValue: _logic),
                VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
                // Right motor is already stopped
                VisualBlockNode(emoji: '⏱️', label: 'Wait   [ 0.08 ]   seconds', colorValue: _logic),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Next, the tracking loop. Add a While loop that runs while locked on the ball '
              'AND target size is less than 35% (not yet close). '
              'Inside, we will build a pulsed movement that drives forward and corrects steering.\n\n'
              'You can edit the Wait times (0.06s and 0.08s) to fine-tune the tracking speed.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '🎯 Locked  AND  📏 Size% < 35',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                    emoji: '⚙️', label: 'Left Motor  [ FORWARD ]   180', colorValue: _action),
                VisualBlockNode(
                    emoji: '⚙️', label: 'Right Motor  [ FORWARD ]   180', colorValue: _action),
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '↔️ Target X Offset  >  0.20',
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
                  ],
                ),
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '↔️ Target X Offset  <  -0.20',
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
                  ],
                ),
                VisualBlockNode(emoji: '⏱️', label: 'Wait   [ 0.06 ]   seconds', colorValue: _logic),
                VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '⏱️', label: 'Wait   [ 0.08 ]   seconds', colorValue: _logic),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'After the second loop (ball is close), add STOP blocks for both '
              'motors. Optionally add a buzzer ON block to celebrate reaching the ball!',
          blockPreview: [
            VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
            VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
            VisualBlockNode(emoji: '🔊', label: 'Buzzer  [ ON ]', colorValue: _action),
          ],
        ),
        TutorialStep(
          text:
              'Press Play. The robot will spin until the camera finds the ball, '
              'then drive toward it and stop when it arrives. '
              'Try hiding the ball and letting the robot search for it! '
              'Swap "sports ball" for "bottle", "cup", or "cat" to fetch anything in the COCO object list.',
        ),
      ],
    ),

    // ── 8 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_line_follower',
      title: 'Line Follower',
      emoji: '🛤️',
      shortDescription: 'Mount phone facing down — robot follows any tape line on the floor!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFDCFCE7),
      requiredParts: [
        '2x DC motors + L298N H-bridge',
        'Arduino Uno + USB-OTG or Bluetooth',
        'Any contrasting tape (black, white, red…)',
        'Phone Camera enabled',
      ],
      conceptDescription:
          'Line following uses real computer vision — Sobel edge detection, '
          'the same algorithm in self-driving cars and OpenCV. '
          'The phone camera points at the floor and detects the sharpest edge '
          'in each frame. No AI model needed — works with any color tape on any floor.',
      steps: [
        TutorialStep(
          text:
              'Lay a line of tape on the floor in a gentle curve or loop. '
              'Any contrasting tape works: black on light floor, white on dark floor, '
              'or colored tape. Keep curves gentle — sharper than 45° may lose tracking.',
        ),
        TutorialStep(
          text:
              'Mount the phone pointing straight DOWN on the robot, '
              'roughly 10–20 cm above the floor. The USB cable end should '
              'face forward (direction of travel). '
              'In the Vision sensor settings, make sure the phone orientation matches.',
        ),
        TutorialStep(
          text:
              'Wire two DC motors to an L298N H-bridge. '
              'Add "Left Motor" and "Right Motor" in Hardware Setup. '
              'Confirm the connection indicator is green.',
        ),
        TutorialStep(
          text:
              'Open the Code editor. Build a While loop that runs while Line Visible is true. '
              'Inside, steer based on the Line Offset X value.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '🛤️ Line Visible',
              bodyNodes: [
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If  — line left',
                  colorValue: _logic,
                  inlineCondition: '↔️ Line Offset X  <  -0.15',
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
                    VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ FORWARD ]', colorValue: _action),
                  ],
                ),
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If  — line right',
                  colorValue: _logic,
                  inlineCondition: '↔️ Line Offset X  >  0.15',
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]', colorValue: _action),
                    VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
                  ],
                ),
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If  — centered',
                  colorValue: _logic,
                  inlineCondition: 'X > -0.15  AND  X < 0.15',
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]', colorValue: _action),
                    VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ FORWARD ]', colorValue: _action),
                  ],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'After the While loop, add STOP blocks for both motors — '
              'so the robot halts when it loses the line.',
          blockPreview: [
            VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
            VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
          ],
        ),
        TutorialStep(
          text:
              'Press Play. The app switches to Sobel edge detection automatically '
              '(no TFLite model runs — it is faster). '
              'Place the robot on the line and watch it follow! '
              'If it steers the wrong way, swap Left and Right motor assignments in Hardware Setup.',
        ),
      ],
    ),

    // ── 9 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_tilt_steering',
      title: 'Tilt Steering Robot',
      emoji: '📱',
      shortDescription: 'Steer your robot by tilting your phone like a joystick!',
      difficulty: Difficulty.easy,
      cardColor: Color(0xFFD1FAE5),
      requiredParts: [
        '2x DC motors + L298N H-bridge',
        'Arduino Uno + USB-OTG cable',
        'Phone Gyroscope (built-in)',
      ],
      conceptDescription:
          'Your phone has a gyroscope that measures how fast it rotates. '
          'Tilt it left — the rotation rate goes negative. Tilt right — positive. '
          'We use that value to steer motors in real time, exactly like a '
          'game controller.',
      steps: [
        TutorialStep(
          text:
              'Wire two DC motors to an L298N H-bridge and connect IN1/IN2 for '
              'the left motor and IN3/IN4 for the right motor. Connect to your '
              'Arduino and pair via USB-OTG or Bluetooth.',
        ),
        TutorialStep(
          text:
              'In Hardware Setup, add two motors: "Left Motor" (IN1 pin) and '
              '"Right Motor" (IN3 pin). For full speed, leave ENA/ENB jumpered.',
        ),
        TutorialStep(
          text:
              'Go to the Sensors tab and confirm the Gyroscope shows as active. '
              'No configuration needed — it works automatically.',
        ),
        TutorialStep(
          text:
              'Open the Code editor. Build a While True loop. '
              'Inside, add an If block that checks if Rotation Rate°/s is less than -20 '
              '(tilting right = steer right).',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '✅ True',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '🔃 Rotation Rate°/s  <  -20',
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]', colorValue: _action),
                    VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
                  ],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Add a second If block for tilting left (Rotation Rate°/s greater than 20). '
              'Left Motor STOP, Right Motor FORWARD.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🔃 Rotation Rate°/s  >  20',
              bodyNodes: [
                VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ FORWARD ]', colorValue: _action),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Add a third If block for when the phone is level '
              '(Rotation Rate°/s between -20 and 20): both motors FORWARD. '
              'Add a Wait 0.05s block at the bottom of the loop.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🔃 Rotation Rate°/s  >  -20  AND  <  20',
              bodyNodes: [
                VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]', colorValue: _action),
                VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ FORWARD ]', colorValue: _action),
              ],
            ),
            VisualBlockNode(emoji: '⏱️', label: 'Wait   [ 0.05 ]   seconds', colorValue: _logic),
          ],
        ),
        TutorialStep(
          text:
              'Press Play, hold the phone in landscape and tilt it left and right. '
              'The robot steers in the direction of your tilt! '
              'Adjust the ±20 threshold to make steering more or less sensitive.',
        ),
      ],
    ),

    // ── 8 ─────────────────────────────────────────────────────────────────────
    TutorialData(
      id: 'tutorial_compass_patrol',
      title: 'Compass Patrol Bot',
      emoji: '🧭',
      shortDescription: 'Robot patrols and always returns to face North!',
      difficulty: Difficulty.medium,
      cardColor: Color(0xFFE0E7FF),
      requiredParts: [
        '2x DC motors + L298N H-bridge',
        'Arduino Uno + USB-OTG cable',
        'Phone Compass (built-in magnetometer)',
      ],
      conceptDescription:
          'Your phone has a magnetometer that measures the Earth\'s magnetic '
          'field, giving a compass heading from 0° (North) to 360°. We can '
          'use this to make the robot always realign to a specific direction — '
          'like a compass needle snapping back to North.',
      steps: [
        TutorialStep(
          text:
              'Wire two motors as in the Person Follower tutorial. Connect via '
              'USB-OTG or Bluetooth and confirm the connection indicator turns green.',
        ),
        TutorialStep(
          text:
              'Go to the Sensors tab and check the Compass entry. '
              'Keep the phone away from metal objects and the Arduino power '
              'supply when calibrating — these distort the magnetic field.',
        ),
        TutorialStep(
          text:
              'Open the Code editor. The main loop checks if the robot is '
              'facing North. If not, it spins right until it is.',
          blockPreview: [
            VisualBlockNode(
              emoji: '🔁',
              label: 'While',
              colorValue: _logic,
              inlineCondition: '✅ True',
              inlineConditionColor: _boolean,
              bodyNodes: [
                VisualBlockNode(
                  emoji: '❓',
                  label: 'If',
                  colorValue: _logic,
                  inlineCondition: '!  NOT  🧭 Facing North',
                  inlineConditionColor: _boolean,
                  bodyNodes: [
                    VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ FORWARD ]', colorValue: _action),
                    VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
                  ],
                ),
              ],
            ),
          ],
        ),
        TutorialStep(
          text:
              'Add an else-style second If block: if Facing North → both motors STOP. '
              'The robot will spin in place until the phone compass points North, then halt.',
          blockPreview: [
            VisualBlockNode(
              emoji: '❓',
              label: 'If',
              colorValue: _logic,
              inlineCondition: '🧭 Facing Direction  [ North ]',
              bodyNodes: [
                VisualBlockNode(emoji: '⚙️', label: 'Left Motor  [ STOP ]', colorValue: _action),
                VisualBlockNode(emoji: '⚙️', label: 'Right Motor  [ STOP ]', colorValue: _action),
              ],
            ),
            VisualBlockNode(emoji: '⏱️', label: 'Wait   [ 0.1 ]   seconds', colorValue: _logic),
          ],
        ),
        TutorialStep(
          text:
              'To make a patrol route, add a Repeat 4 block before the alignment '
              'loop: drive both motors FORWARD for 1 second, then align to North. '
              'The robot drives forward, realigns, drives again — making a consistent path.',
        ),
        TutorialStep(
          text:
              'Press Play outdoors or away from electronics. '
              'The robot will spin until it faces North, then stop. '
              'Rotate it by hand — it will always find its way back. '
              'Change "North" to any of the 8 compass directions to set a custom home heading.',
        ),
      ],
    ),
  ];
}
