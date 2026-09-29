# Roadmap

The near-term plan (first three months after the public release) and the
open owner decisions are in [AUDIT_2026-09.md](AUDIT_2026-09.md) §7–8. This
file keeps the longer-term ideas. The previous version of this file (the
2026-09-12 review notes and the text-language options that led to
RoboPython) is in git history.

## Next three months (summary)

1. **Stabilize on hardware** — device checklist on real phones and boards
   (the firmware fixes and the portrait lock + phone-mount setting are
   done, but not yet tried on hardware), per-board hotspot password, a
   robot picker for rooms with several robots, signed APK releases.
2. **Learning experience** — variables, accessibility pass, sharing
   programs (JSON/QR), live telemetry while running, phone benchmarks.
3. **Capability** — sensor feedback from the board (distance, bumpers,
   battery), gyro-assisted "turn 90°" / "drive straight", Bonjour/NSD
   discovery, TTS/recognizer audio focus, optional iOS port.

## Later ideas (ranked by impact ÷ effort)

- **Hardware presets** — one-tap configs for common kits (L298N 2WD car,
  TB6612, servo arm) with pin diagrams.
- **Markers** — ArUco/AprilTag detection for "go to marker 3" navigation.
- **Colour-blob tracking block** (an unused draft was removed in the audit; it is in git history).
- **Wake word + parameterised voice commands** ("turn left 45").
- **Accurate-model option** — EfficientDet-Lite1 on capable phones, gated
  by `tools/model_eval` results.
- **AI helper** — describe a behaviour in plain language, get a block
  program to edit (needs a privacy review for classroom use).
