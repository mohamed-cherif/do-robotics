# Apple (iOS / macOS) feasibility

*Assessment from the 2026-09 pre-release audit. Nothing here was built or
run on Apple hardware (the audit ran on Windows); treat effort numbers as
estimates.*

## Verdict

| | |
|---|---|
| **Difficulty** | **Moderate** (iOS). macOS: not recommended as a product target. |
| **Effort** | **~5–8 person-weeks** for a TestFlight-quality iOS build, including device QA and App Store submission. |
| **Approach** | **Keep the single Flutter codebase.** No rewrite: the port is configuration, a handful of platform adaptations inside existing services, and testing. |
| **Biggest blocker** | USB serial does not exist on iOS → iPhone users need an ESP32 (BLE/WiFi) or a BLE module on the Uno/Mega. |

## How much code is platform-independent?

Measured on `lib/` (17,414 non-blank, non-comment Dart lines):

| Share | What | iOS status |
|---|---|---|
| 47.5 % | UI (Flutter widgets) | Runs as-is. |
| 41.0 % | Pure Dart logic: block runner, RoboPython interpreter, protocol, models, tutorials, stores | Runs as-is. |
| 11.4 % | Services backed by plugins (camera, TFLite, BLE, speech, TTS, sensors, mDNS, USB) | Plugins support iOS except `usb_serial`; behaviour differences below. |
| 0.1 % | Own platform channel (`PlatformService`) | Swift side added in this audit (untested). |

Android-only native code: ~220 lines (Kotlin `MainActivity`, manifest,
Gradle). **≈ 88 % of the code needs no change; the remaining ~12 % needs
testing and a few targeted fixes, not rewrites.**

## Component map

| Component | Android today | Apple equivalent | Work |
|---|---|---|---|
| UI | Flutter | Flutter | None. |
| Camera frames | `camera` (CameraX), YUV420 | `camera` (AVFoundation), BGRA8888 — the fast BGRA path already exists in `_directToTensor` | Verify rotation (`sensorOrientation`), frame size at `ResolutionPreset.low`, performance. |
| Object detection | TFLite (LiteRT 1.4) + XNNPack | Same model via `tflite_flutter` + `TensorFlowLiteC` pod; optional Metal delegate | Build + benchmark; see *Model runtime* below. |
| Line follower | Luma (Y) plane | BGRA has no Y plane: `detectLineInLuma` must get luminance computed from BGRA | Small change in `_detectLine` (compute Y = 0.299R+0.587G+0.114B for the floor band). |
| Speech recognition | Android `SpeechRecognizer` | `SFSpeechRecognizer` via `speech_to_text` (on-device on iOS 13+) | Audio-session conflicts with TTS (see risks); 1-minute request limit is already handled by the restart loop. |
| Loudness | Recognizer RMS dB (−2..10) | Recognizer dBFS (−160..0) | Mapping already in `VoiceService`; tune threshold on device. |
| Text-to-speech | `flutter_tts` | `flutter_tts` (AVSpeechSynthesizer) | Set a shared audio category so TTS doesn't break recognition. |
| IMU / compass | `sensors_plus` | `sensors_plus` (CoreMotion) | Axis conventions match (right-handed, CCW-positive); verify magnetometer calibration UX. |
| Bluetooth LE | `flutter_blue_plus` | `flutter_blue_plus` (CoreBluetooth) | Works; iOS hides MAC addresses (the app matches by name — fine). |
| USB serial | `usb_serial` (OTG) | **Not possible** for Arduino CDC/CH340 without MFi | Hide USB on iOS (done); document ESP32 or HM-10 BLE module for Uno/Mega. |
| WiFi TCP | `dart:io` Socket | Same | Needs local-network permission (strings present). |
| mDNS discovery | `multicast_dns` + Android multicast lock | Raw multicast sockets need Apple's **multicast entitlement** (must be requested) | Recommended: switch both platforms to a Bonjour/NSD plugin (e.g. `bonsoir`) → no entitlement, no multicast lock. `NSBonjourServices` added. |
| Permissions | `permission_handler` + manifest | `permission_handler` + Info.plist + **Podfile macros** | Add `PERMISSION_CAMERA=1`, `PERMISSION_MICROPHONE=1`, `PERMISSION_SPEECH_RECOGNIZER=1`, `PERMISSION_BLUETOOTH=1` to the Podfile `post_install` (otherwise requests silently return *denied*). |
| Keep screen on | `FLAG_KEEP_SCREEN_ON` via `MainActivity` | `UIApplication.isIdleTimerDisabled` | Added in `AppDelegate.swift` (untested). |
| Background | Programs stop when paused | iOS suspends apps anyway | Same policy — nothing to do. |
| Storage | SharedPreferences | NSUserDefaults (same plugin) | Declare in the privacy manifest (reason `CA92.1`). |

## Model runtime options on Apple

| Option | Conversion | Accuracy risk | Notes |
|---|---|---|---|
| **TFLite (recommended)** | None — same `1.tflite` | None (bit-identical graph) | CPU via TensorFlowLiteC; the XNNPack delegate call is Android-only in code and can be enabled for iOS too. Metal (GPU) delegate supports this uint8 model by dequantizing; the custom post-process op stays on CPU. |
| Core ML (Neural Engine) | TF SavedModel of the float EfficientDet-Lite0 → `coremltools`; the TFLite post-process/NMS op doesn't convert, so NMS moves to Dart | Medium: float16 is usually close, but re-implementing box decoding + NMS is where regressions hide | Fastest and coolest on A12+; requires a separate model file and code path. Only worth it after profiling shows TFLite is too slow. |
| ONNX Runtime Mobile | `tf2onnx` from TFLite; post-process op unsupported → NMS in Dart | Medium (same NMS risk) + larger binary (~10–15 MB) | Gives one runtime for both platforms with CoreML/NNAPI EPs, but adds size and a second model format. Not recommended now. |
| Metal Performance Shaders | Hand-written | High | Not justified. |

Use `tools/model_eval` to check any converted model against the TFLite
baseline before shipping it.

## Build & distribution

- **Signing:** Apple Developer Program ($99/year). Decide who owns the
  account for an open-source project (a person, or an organization account
  with a D-U-N-S number). Contributors build with their own free team for
  on-device testing.
- **CI:** macOS runners (GitHub Actions `macos-latest`) to build the iOS
  app; `flutter build ios --no-codesign` for PR checks.
- **App Store review points for this app:**
  - *Guideline 2.5.2 (executable code):* running user-written RoboPython
    and block programs on-device is allowed for educational apps as long
    as the code is written/viewable by the user and isn't downloaded to
    change the app's features. A future "share programs" feature must keep
    shared code visible and editable.
  - *Kids Category* (if chosen): no third-party analytics/ads, parental gate
    before links out (e.g. GitHub, datasheets), privacy policy required.
  - *Privacy:* speech recognition may send audio to Apple unless on-device
    recognition is used (`speech_to_text` has an `onDevice` option) —
    disclose it in the privacy nutrition label.
  - *Privacy manifest (`PrivacyInfo.xcprivacy`)* declaring UserDefaults use;
    recent plugin versions ship their own.
- **Licensing:** permissive licenses (Apache-2.0/MIT) are compatible with
  App Store distribution. GPL-licensed code is widely considered
  incompatible with the App Store terms — another reason to avoid GPL for
  this project.

## Top 5 risks

1. **No USB serial on iOS.** Uno/Mega users (serial-only firmware) can't use
   an iPhone. Mitigation: recommend ESP32; document an HM-10 BLE module on
   the Uno's serial pins (the app's BLE strategy already falls back to any
   writable characteristic — needs testing).
2. **Speech + TTS audio session conflicts** — a classic iOS failure where
   recognition stops working after the robot speaks. Needs a deliberate
   `AVAudioSession` configuration and device testing.
3. **Local-network discovery** — raw multicast (the current mDNS client)
   needs a special Apple entitlement. Moving to Bonjour/NSD avoids it on
   iOS and the multicast lock on Android.
4. **Vision correctness regressions** (BGRA path, rotation, line follower
   needing luminance from BGRA) that unit tests can't see. Mitigation: run
   the device checklist with the upright robot mount on an iPhone.
5. **Store/account logistics** — developer account ownership, review of an
   app that runs user code, Kids-category rules, and privacy disclosures.

## Recommended plan (≈ 5–8 person-weeks)

1. Week 1: iOS project hygiene — Podfile with permission macros, bundle id,
   signing, `flutter build ios`, fix compile issues; privacy manifest.
2. Weeks 2–3: vision on device (rotation, BGRA luminance for the line
   follower, performance; optional Metal delegate behind the performance
   setting), BLE + WiFi, Bonjour discovery.
3. Week 4: voice/TTS audio session, loudness threshold, on-device speech
   option.
4. Weeks 5–6: device QA with `docs/DEVICE_TEST_CHECKLIST.md`, TestFlight
   with a classroom, fixes.
5. Weeks 6–8 (buffer): App Store submission and review iterations.

## Changes already made to ease the port

- `PlatformService` isolates the app's own native calls; iOS
  implementation of `keepScreenOn` added in `AppDelegate.swift` (untested).
- `NSBonjourServices` (`_dorobot._tcp`) declared in `Info.plist`.
- The USB Serial option is only offered on Android.
- `VoiceService` owns the speech plugin and exposes a platform-neutral
  0–100 level, so iOS dBFS vs Android RMS is handled in one place.
- Vision already has a BGRA8888 fast path; the line detector takes a
  rotation and a luminance plane (`detectLineInLuma`), so iOS only needs to
  supply luminance.
