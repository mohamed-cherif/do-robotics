import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class ColorTrackingPreferences {
  static const String _keyEnabled = 'color_tracking_enabled';
  static const String _keyTargetColor = 'color_tracking_target';
  static const String _keyTolerance = 'color_tracking_tolerance';
  
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }
  
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }
  
  static Future<Color?> getTargetColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyTargetColor);
    return value != null ? Color(value) : null;
  }
  
  static Future<void> setTargetColor(Color? color) async {
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_keyTargetColor);
    } else {
      await prefs.setInt(_keyTargetColor, color.toARGB32());
    }
  }
  
  static Future<double> getTolerance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyTolerance) ?? 30.0; // Default 30 degrees in HSV
  }
  
  static Future<void> setTolerance(double tolerance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTolerance, tolerance);
  }
  
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnabled);
    await prefs.remove(_keyTargetColor);
  }
}
