import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the app's own platform channel (see MainActivity.kt).
/// Every call is best-effort: on platforms without an implementation (iOS,
/// desktop, tests) it quietly does nothing, so callers never need to care.
class PlatformService {
  PlatformService._();

  static const MethodChannel _channel = MethodChannel('do_robotics/platform');

  static Future<void> _call(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Not implemented on this platform.
    } catch (e) {
      debugPrint('PlatformService.$method failed: $e');
    }
  }

  /// Keeps the display (and therefore camera frames and the microphone)
  /// alive while a program is running.
  static Future<void> keepScreenOn(bool on) => _call('keepScreenOn', on);

  /// Runs [body] while holding Android's WiFi multicast lock, which mDNS
  /// needs to receive replies.
  static Future<T> withMulticastLock<T>(Future<T> Function() body) async {
    await _call('acquireMulticastLock');
    try {
      return await body();
    } finally {
      await _call('releaseMulticastLock');
    }
  }
}
