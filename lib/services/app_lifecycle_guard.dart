import 'package:flutter/widgets.dart';

import '../logic/block_script_runner.dart';
import '../logic/python_script_runner.dart';
import 'platform_service.dart';

/// App-wide safety net for running programs.
///
/// * Keeps the screen on while a block or Python program runs. Android stops
///   camera frames and blocks the microphone for apps that are not in the
///   foreground, so a screen timeout used to leave the robot driving on the
///   last (frozen) camera result while heartbeats kept the firmware watchdog
///   happy.
/// * If the app still goes to the background (home button, incoming call,
///   user locks the phone), every program is stopped, which also sends
///   stop-all to the robot.
class AppLifecycleGuard with WidgetsBindingObserver {
  AppLifecycleGuard._();
  static final AppLifecycleGuard instance = AppLifecycleGuard._();

  bool _started = false;
  bool _screenKeptOn = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    BlockScriptRunner().stateStream.listen((_) => _syncScreen());
    PythonScriptRunner().stateStream.listen((_) => _syncScreen());
  }

  static bool get anyProgramRunning =>
      BlockScriptRunner().state == ExecutionState.running ||
      PythonScriptRunner().state == ExecutionState.running;

  void _syncScreen() {
    final running = anyProgramRunning;
    if (running == _screenKeptOn) return;
    _screenKeptOn = running;
    PlatformService.keepScreenOn(running);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `paused` = no longer visible. (`inactive` also fires for permission
    // dialogs and the notification shade, which must not stop a program.)
    if (state == AppLifecycleState.paused && anyProgramRunning) {
      debugPrint('App went to background — stopping the running program');
      BlockScriptRunner().stop();
      PythonScriptRunner().stop();
    }
  }
}
