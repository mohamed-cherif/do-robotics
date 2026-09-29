# Device test checklist

Automated tests cover logic only (protocol, parsing, the Python
interpreter, the block runner with logic blocks, vision/sensor math).
Everything below needs a real phone and, where noted, a real robot. Run it
before each release and whenever a PR touches runners, vision, voice,
connectivity, permissions or the Android build.

Record: phone model, Android version, RAM, board + firmware, app commit.

**Suggested minimum matrix:** one Android 10 or 11 phone (legacy Bluetooth
permissions), one Android 13–15 phone, one budget device with 3–4 GB RAM.

## 1. Install & permissions

- [ ] Fresh install of a **release** APK (`flutter build apk --release --split-per-abi`) starts without crashing.
- [ ] App name shows as "DO Robotics".
- [ ] Settings › Apps › DO Robotics › Permissions lists only Camera,
      Microphone, Nearby devices (12+) / Location (≤ 11). **No** Phone or
      Storage permission.
- [ ] Deny the camera, then open Camera: a clear error with a way back, no endless spinner.
- [ ] Deny the microphone, then open Microphone page: message + Settings shortcut works.

## 2. Bluetooth (ESP32 with `receiver.ino`)

- [ ] **Android 10/11:** Connect over Bluetooth works (regression: missing
      BLUETOOTH/BLUETOOTH_ADMIN permissions broke BLE on Android ≤ 11).
- [ ] Android 12+: only "Nearby devices" is requested, not location.
- [ ] Robot off → "Couldn't connect over Bluetooth…" SnackBar within ~12 s.
- [ ] Power-cycle the robot while connected → app shows connecting, then reconnects (max 5 tries).
- [ ] While connected, tap the header → menu opens (Disconnect, Set up robot WiFi).

## 3. USB serial (Uno/Mega/ESP32 over OTG)

- [ ] Connect → USB permission prompt → connected after ~2 s.
- [ ] Unplug the cable while a program runs → state goes to disconnected; replug and reconnect works.

## 4. WiFi (ESP32)

- [ ] Hotspot `ESP32_Robot`: connect to `192.168.4.1:4210`.
- [ ] Set up robot WiFi over BLE → robot joins home WiFi → **Find robot** lists it
      (checks the multicast lock) → connect via `robot.local`.
- [ ] Change the WiFi address while connected → app reconnects to the new host.

## 5. Safety

- [ ] Run *Motor Forward Test*, press STOP → motors stop within 0.5 s.
- [ ] Run a vision program, press STOP **within 1 s of RUN** (while the camera
      is still starting) → the camera privacy indicator turns off within ~2 s.
- [ ] Same for a voice program → the microphone indicator turns off.
- [ ] Run a program, press Home → program stops and motors stop.
- [ ] Run a program and leave the phone untouched past the screen timeout →
      screen stays on while running, and turns off normally after STOP.
- [ ] Unplug/kill the link while motors run → firmware stops them within 2 s.
- [ ] Start a Python program, switch to Blocks, press RUN → refused with a log message.

## 6. Vision

- [ ] Camera page: boxes line up with objects; **tap a box locks it** (green).
- [ ] A person in view is labelled **person** with a sensible percentage
      (regression: class/score outputs were swapped — everything was "person 1600%").
- [ ] Lock Object Type [person] + Target X Offset: person on the robot's
      right → positive offset (portrait mount, camera forward).
- [ ] **Upside-down mount** (setting on): record the sign of Target X Offset
      for a person on the robot's right. Expected today: negative (screen
      coordinates) — see "Needs decision" in docs/AUDIT_2026-09.md.
- [ ] Line follower snippet with the phone in portrait: Line Offset X is
      negative when the tape is on the left of the picture, positive on the right.
- [ ] Performance modes: Battery saver / Balanced / Fast change the HUD
      frame rate; note inference ms for each.
- [ ] 10 minutes of Person Follower: note battery drop and whether the phone throttles (HUD ms rising).

## 7. Voice

- [ ] Voice program: "forward" / "stop" recognized; keeps listening after silence.
- [ ] Open the Microphone page while a voice program runs, then leave it → program keeps listening.
- [ ] Airplane mode: voice either works on-device or logs an error without a restart storm.

## 8. Sensors

- [ ] Upright phone on the robot: Compass Heading matches a real compass (±20°) for the direction the camera faces.
- [ ] Turning the robot left gives positive Rotation Rate; Phone Spinning triggers on fast turns.

## 9. Lifecycle

- [ ] Rotate the phone on the Blocks tab: no crash, no lost blocks.
- [ ] Receive a call during a program: program stops; returning to the app works.
- [ ] Open Camera, lock the phone, unlock: preview recovers.

## 10. Block editor

- [ ] Drag a While block onto its own "do" slot: it is refused (regression: crash).
- [ ] Clear All while running: STOP button remains.
- [ ] Horizontal swipe on the palette scrolls instead of dragging a block.
