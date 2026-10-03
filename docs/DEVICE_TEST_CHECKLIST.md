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
- [ ] Header › Bluetooth with two robots on: both are listed, closer one
      first; tap one → connects to that one. Restart the app → it
      reconnects to the same robot, not the other.
- [ ] Open the list right after starting the app (while it is still
      connecting): no "Couldn't connect" message; the list works.
- [ ] Robot switched off → the list says "No robots found"; Search again
      finds it after switching it on.

## 3. USB serial (Uno/Mega/ESP32 over OTG)

- [ ] Connect → USB permission prompt → connected after ~2 s.
- [ ] Unplug the cable while a program runs → state goes to disconnected; replug and reconnect works.

## 4. WiFi (ESP32)

- [ ] Hotspot `ESP32_Robot_XXXX` (XXXX = same suffix as the BLE name `ESP32 Robot XXXX`): connect to `192.168.4.1:4210`.
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
- [ ] **Upside-down mount**, *Phone mounting: Automatic*: turn the phone
      upside down in its holder (camera still forward), also leaning back
      as it rests on the robot. Within ~1 s boxes line up with objects
      again, the program log says "phone is upside down", and a person on
      the robot's right gives a **positive** Target X Offset (robot
      coordinates, same as upright).
- [ ] Open and close the Camera page 10 times: no crash (regression: a
      native crash in XNNPack setup on most opens).
- [ ] Person Follower: walk across the view, briefly half out of frame —
      the lock holds (it is kept for 1 s without a detection).
- [ ] Same with the setting on *Upside down* (no waiting) and on *Upright*
      (an upside-down phone now sees an upside-down picture: detection
      gets worse — expected, the setting overrides the sensor).
- [ ] Automatic: tilting the upright phone briefly (bumps, turning) does
      not flip the picture.
- [ ] Rotate the phone to landscape: the app stays in portrait.
- [ ] Line follower snippet: Line Offset X is negative when the tape is on
      the robot's left, positive on its right — upright and upside down.
- [ ] Performance modes: Battery saver / Balanced / Fast change the HUD
      frame rate; note the ms for each (Pixel 9 on Fast: ~42–45 ms;
      hundreds of ms means something is wrong).
- [ ] 10 minutes of Person Follower: note battery drop and whether the phone throttles (HUD ms rising).

## 7. Voice

- [ ] Voice program: "forward" / "stop" recognized; keeps listening after silence.
- [ ] Open the Microphone page while a voice program runs, then leave it → program keeps listening.
- [ ] Airplane mode: voice either works on-device or logs an error without a restart storm.

## 8. Sensors

- [ ] Upright phone on the robot: Compass Heading matches a real compass (±20°) for the direction the camera faces.
- [ ] Turning the robot left gives positive Rotation Rate; Phone Spinning triggers on fast turns.

## 9. Lifecycle

- [ ] Split screen / resize the window on the Blocks tab: no crash, no lost blocks.
- [ ] Receive a call during a program: program stops; returning to the app works.
- [ ] Open Camera, lock the phone, unlock: preview recovers.

## 10. Block editor

- [ ] Drag a While block onto its own "do" slot: it is refused (regression: crash).
- [ ] Clear All while running: STOP button remains.
- [ ] Horizontal swipe on the palette scrolls instead of dragging a block.

## 11. Firmware (ESP32 2.1, Uno/Mega 1.5)

The firmware logic is covered by host tests (`arduino/test/run_tests.sh`);
these checks cover what only real boards show.

ESP32:

- [ ] BLE name is `ESP32 Robot XXXX` and the hotspot `ESP32_Robot_XXXX` with
      the same XXXX; two boards get different names.
- [ ] Connect over BLE → the Home status shows **ESP32** (the board's HELLO
      arrived); *Set up robot WiFi* says "esp32 (fw 2.1)".
- [ ] Python `robot.pin.digital(6, 1)` → the board does **not** reboot; the
      log shows "Robot: pin 6 can't be used on this board".
- [ ] Same pin as servo, then as LED, then as PWM motor → each one works.
- [ ] Over WiFi: turn phone WiFi off and on during a program, reconnect →
      works at once; no burst of old commands afterwards.
- [ ] Save home WiFi with a wrong password while a phone uses the hotspot →
      the hotspot connection stays stable (no watchdog stops in the log).
- [ ] *Set up robot WiFi* while connected over WiFi → refused ("use
      Bluetooth or USB"); over BLE → works.

Uno / Mega:

- [ ] LED on pin 13 stays on (no flicker) while other commands are sent.
- [ ] Servos on pins 12 and 13 (Uno) move; a 9th servo logs "too many servos".
- [ ] After a servo has moved, a PWM motor on pin 9 (Uno) / 45 (Mega) logs
      "no PWM once servos are used"; other PWM pins keep working.
