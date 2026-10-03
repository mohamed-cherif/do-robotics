# Security policy

DO Robotics controls physical hardware and is often used by children, so we
treat anything that lets an unauthorised person drive a robot, or exposes
personal data, as a security issue.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately with the
**Report a vulnerability** button on the repository's
[Security tab](https://github.com/mohamed-cherif/do-robotics/security);
only the maintainer can see the report. If the button isn't there, send
the maintainer a message on
[LinkedIn](https://www.linkedin.com/in/mohamedcherif-braham/) asking for a
private channel, without the details. Please include:

- what an attacker can do and what they need (same WiFi? Bluetooth range?),
- steps to reproduce, app version and firmware version,
- your suggested fix, if any.

We aim to acknowledge reports within 7 days.

## Known limitations (by design, for now)

These are documented trade-offs of a hobby/education robot, not bugs, but
please keep them in mind:

- **Bluetooth has no pairing.** Anyone in range who runs a compatible app
  can connect to an idle robot.
- **The ESP32 hotspot uses a shared default password** (`12345678`, see
  `arduino/receiver/receiver.ino`). Change `WIFI_PASS` before flashing if
  your robot will be used around other people.
- **Any device on the same WiFi network (or on the robot's hotspot) can
  connect to TCP port 4210 and take over the robot**, even while a phone is
  driving it: the newest connection wins, so a phone whose WiFi dropped can
  reconnect at once. The robot stops all outputs on every hand-over. Robot
  settings (WiFi, name) can only be changed over Bluetooth or USB.
- WiFi credentials sent with "Set up robot WiFi" are stored unencrypted in
  the ESP32's flash (NVS).
- Speech recognition uses the phone's system recognizer, which may send
  audio to the recognizer's provider (e.g. Google) unless on-device
  recognition is available.

The firmware stops all outputs 2 seconds after the link goes quiet, and the
app stops programs when it goes to the background.
