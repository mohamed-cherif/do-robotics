import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/actuator_config.dart';

class ActuatorService {
  static final ActuatorService _instance = ActuatorService._internal();
  factory ActuatorService() => _instance;
  ActuatorService._internal();

  static const String _storageKey = 'configured_actuators';
  
  final List<ActuatorConfig> _actuators = [];
  final StreamController<List<ActuatorConfig>> _actuatorsController =
      StreamController<List<ActuatorConfig>>.broadcast();

  Stream<List<ActuatorConfig>> get actuatorsStream => _actuatorsController.stream;
  List<ActuatorConfig> get actuators => List.unmodifiable(_actuators);

  Future<void> initialize() async {
    await _loadActuators();
  }

  Future<void> _loadActuators() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _actuators.clear();
        _actuators.addAll(
          jsonList.map((json) => ActuatorConfig.fromJson(json as Map<String, dynamic>))
        );
        _actuatorsController.add(_actuators);
      } catch (e) {
        debugPrint("Error loading actuators: $e");
      }
    }
  }

  Future<void> _saveActuators() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_actuators.map((a) => a.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
    _actuatorsController.add(_actuators);
  }

  /// Every GPIO an actuator occupies: its main pin plus H-bridge direction pins.
  static Set<int> pinsOf(ActuatorConfig a) => {
        a.pin,
        if (a.parameters['in1'] is int) a.parameters['in1'] as int,
        if (a.parameters['in2'] is int) a.parameters['in2'] as int,
      };

  /// True when [candidate] shares any pin with another actuator, or with itself
  /// (e.g. IN1 == ENA).
  bool hasPinConflict(ActuatorConfig candidate, {String? excludeActuatorId}) {
    final own = pinsOf(candidate);
    final distinct = [
      candidate.pin,
      if (candidate.parameters['in1'] is int) candidate.parameters['in1'] as int,
      if (candidate.parameters['in2'] is int) candidate.parameters['in2'] as int,
    ];
    if (distinct.length != own.length) return true; // duplicate within itself
    for (final other in _actuators) {
      if (other.id == excludeActuatorId) continue;
      if (pinsOf(other).intersection(own).isNotEmpty) return true;
    }
    return false;
  }

  Future<bool> addActuator(ActuatorConfig actuator) async {
    if (hasPinConflict(actuator)) return false;
    _actuators.add(actuator);
    await _saveActuators();
    return true;
  }

  Future<bool> updateActuator(String id, ActuatorConfig updated) async {
    final index = _actuators.indexWhere((a) => a.id == id);
    if (index == -1) return false;
    if (hasPinConflict(updated, excludeActuatorId: id)) return false;

    _actuators[index] = updated;
    await _saveActuators();
    return true;
  }

  Future<void> deleteActuator(String id) async {
    _actuators.removeWhere((a) => a.id == id);
    await _saveActuators();
  }

  ActuatorConfig? getActuator(String id) {
    try {
      return _actuators.firstWhere((a) => a.id == id);
    } catch (e) {
      return null;
    }
  }

  bool isPinAvailable(int pin, {String? excludeActuatorId}) {
    return !_actuators.any((a) => a.id != excludeActuatorId && pinsOf(a).contains(pin));
  }

  void dispose() {
    _actuatorsController.close();
  }
}
