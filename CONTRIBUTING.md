# Contributing to DO Robotics

Thanks for helping! DO Robotics is used by students and beginners, so the
bar for changes is: **it must be safe on a real robot, and it must be
understandable to a newcomer.**

## Ground rules

- Be kind. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Security problems (anything that lets someone else drive a robot, or
  leaks WiFi credentials) go to [SECURITY.md](SECURITY.md), not a public issue.
- One logical change per pull request. Small PRs get reviewed fast.

## Set up

1. Install Flutter **3.38.x stable** (see `.metadata` for the exact revision)
   and Android Studio or the Android SDK command-line tools.
2. `flutter pub get`
3. `flutter analyze` must report **No issues found**.
4. `flutter test` must pass. Tests need no phone or robot.
5. `flutter run` on a **physical Android phone**. The camera, Bluetooth, USB
   and speech recognition do not work in the emulator.

Firmware lives in `arduino/` and is built with the Arduino IDE (see the
README for board cores and library versions). `bash arduino/test/run_tests.sh`
runs its logic on your computer (any C++17 compiler, no board); add a test
there with every firmware change.

## Where things live

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first. In short:

| Change | Start here |
|---|---|
| A new block | `lib/models/block_factory.dart` (definition), `lib/logic/block_script_runner.dart` (behavior), `lib/logic/code_generator.dart` (Python conversion) |
| A Python `robot.*` API | `lib/logic/robot_api.dart` + `lib/python/robot_module.dart` |
| Wire protocol | `lib/services/connectivity/robot_protocol.dart` **and all three sketches** in `arduino/` |
| Vision | `lib/services/vision_service.dart`, `lib/services/object_detector_service.dart` |
| A tutorial | `lib/models/tutorial_data.dart` |

## Rules that keep robots safe

- **Every `VisionService.startStream()` needs exactly one `stopStream()`**,
  and every `VoiceService.startListening()` needs one `stopListening()`,
  even if the start threw. Both services are reference-counted.
- Code that runs a program must stop when `stop()` is called: check the
  run's own token, not a shared flag, and never wait more than ~100 ms
  without checking.
- The firmware watchdog stops outputs 2 s after the last packet. Don't add
  features that keep heartbeats flowing while the program is stuck.
- Protocol changes must keep old firmware working, or bump the firmware
  version in `HELLO` and handle both.

## Tests

- Fixing a bug? Add a test that fails before your fix.
- Pure logic (protocol, parsing, math, the Python interpreter, the block
  runner with logic-only blocks) is unit-tested in `test/`. Use the fakes
  in `test/python/robot_module_test.dart` for the `robot` API.
- UI and hardware changes: say in the PR which phone (model + Android
  version) and which board you tested on. Use the checklist in
  [docs/DEVICE_TEST_CHECKLIST.md](docs/DEVICE_TEST_CHECKLIST.md).

## Style

- Follow the existing code. `flutter analyze` is the style checker.
- Comments explain *why*, not *what*.
- Kid-facing text (block labels, tutorials, error messages) should be short,
  concrete and free of jargon.

## Commit messages

Imperative subject line (≤ 72 chars), then a body that explains the problem
and the fix. Reference issues with `Fixes #123`.

## License

The project is licensed under the [Apache License 2.0](LICENSE). By
submitting a contribution you agree that it is licensed under the same
terms (section 5 of the license). Don't add code, models or media you
don't have the right to share; third-party material needs its license
noted in [NOTICE](NOTICE).
