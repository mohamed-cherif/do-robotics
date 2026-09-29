import 'dart:convert';

enum ActuatorType {
  led,
  motor,
  servo,
  buzzer,
  switchPin;

  String get displayName {
    switch (this) {
      case ActuatorType.led:
        return 'LED';
      case ActuatorType.motor:
        return 'Motor';
      case ActuatorType.servo:
        return 'Servo';
      case ActuatorType.buzzer:
        return 'Buzzer';
      case ActuatorType.switchPin:
        return 'Switch';
    }
  }

  String get emoji {
    switch (this) {
      case ActuatorType.led:
        return '💡';
      case ActuatorType.motor:
        return '⚙️';
      case ActuatorType.servo:
        return '🔄';
      case ActuatorType.buzzer:
        return '🔊';
      case ActuatorType.switchPin:
        return '🔌';
    }
  }
}

class ActuatorConfig {
  final String id;
  final String name;
  final ActuatorType type;
  final int pin;
  final Map<String, dynamic> parameters;

  ActuatorConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.pin,
    Map<String, dynamic>? parameters,
  }) : parameters = parameters ?? {};

  // For motors: min/max speed
  int get minSpeed => parameters['minSpeed'] as int? ?? 0;
  int get maxSpeed => parameters['maxSpeed'] as int? ?? 255;

  // For servos: min/max angle (support raw PWM signals)
  int get minAngle => parameters['minAngle'] as int? ?? 0;
  int get maxAngle => parameters['maxAngle'] as int? ?? 3000;

  // For motors & continuous servos: swap FORWARD ↔ BACKWARD at the protocol level
  bool get invertedDirection => parameters['inverted'] as bool? ?? false;

  // For continuous rotation servos (1300 = full reverse, 1500 = stop, 1700 = full forward)
  bool get isContinuous => parameters['continuous'] as bool? ?? false;
  int get continuousStopPwm => parameters['stopPwm'] as int? ?? 1500;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'pin': pin,
      'parameters': parameters,
    };
  }

  factory ActuatorConfig.fromJson(Map<String, dynamic> json) {
    return ActuatorConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      type: ActuatorType.values.firstWhere((e) => e.name == json['type']),
      pin: json['pin'] as int,
      parameters: json['parameters'] as Map<String, dynamic>? ?? {},
    );
  }

  factory ActuatorConfig.fromJsonString(String jsonString) {
    return ActuatorConfig.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  ActuatorConfig copyWith({
    String? id,
    String? name,
    ActuatorType? type,
    int? pin,
    Map<String, dynamic>? parameters,
  }) {
    return ActuatorConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      pin: pin ?? this.pin,
      parameters: parameters ?? this.parameters,
    );
  }
}
