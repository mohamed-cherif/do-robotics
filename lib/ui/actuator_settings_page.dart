import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/actuator_config.dart';
import '../services/actuator_service.dart';

class ActuatorSettingsPage extends StatefulWidget {
  const ActuatorSettingsPage({super.key});

  @override
  State<ActuatorSettingsPage> createState() => _ActuatorSettingsPageState();
}

class _ActuatorSettingsPageState extends State<ActuatorSettingsPage> {
  final ActuatorService _service = ActuatorService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 2,
        title: const Text(
          "Configure Hardware",
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1F2937)),
      ),
      body: StreamBuilder<List<ActuatorConfig>>(
        stream: _service.actuatorsStream,
        initialData: _service.actuators,
        builder: (context, snapshot) {
          final actuators = snapshot.data ?? [];

          if (actuators.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: actuators.length,
            itemBuilder: (context, index) {
              return _buildActuatorCard(actuators[index]);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddActuatorDialog(),
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add),
        label: const Text("Add Actuator"),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_input_component, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            "No Actuators Configured",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Tap + to add motors, servos, and LEDs",
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildActuatorCard(ActuatorConfig actuator) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Text(
                actuator.type.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actuator.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buildActuatorSubtitle(actuator),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showEditActuatorDialog(actuator),
              icon: const Icon(Icons.edit_outlined),
              color: const Color(0xFF6366F1),
              tooltip: 'Edit ${actuator.name}',
            ),
            IconButton(
              onPressed: () => _confirmDelete(actuator),
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: 'Delete ${actuator.name}',
            ),
          ],
        ),
      ),
    );
  }

  String _buildActuatorSubtitle(ActuatorConfig actuator) {
    if (actuator.type == ActuatorType.motor) {
      final in1 = actuator.parameters['in1'];
      final in2 = actuator.parameters['in2'];
      if (in1 != null && in2 != null) return "Motor • IN1: $in1 · IN2: $in2 · ENA: ${actuator.pin}";
      if (in1 != null) return "Motor • IN1: $in1 (single-pin mode)";
    }
    return "${actuator.type.displayName} • Pin ${actuator.pin}";
  }

  void _showAddActuatorDialog() {
    showDialog(
      context: context,
      builder: (_) => ActuatorDialog(
        onSave: (config) async {
          final success = await _service.addActuator(config);
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Pin already in use!")),
            );
          }
        },
      ),
    );
  }

  void _showEditActuatorDialog(ActuatorConfig actuator) {
    showDialog(
      context: context,
      builder: (_) => ActuatorDialog(
        existing: actuator,
        onSave: (config) async {
          final success = await _service.updateActuator(actuator.id, config);
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Pin already in use!")),
            );
          }
        },
      ),
    );
  }

  void _confirmDelete(ActuatorConfig actuator) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Actuator?"),
        content: Text("Remove ${actuator.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _service.deleteActuator(actuator.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}

class ActuatorDialog extends StatefulWidget {
  final ActuatorConfig? existing;
  final Function(ActuatorConfig) onSave;

  const ActuatorDialog({super.key, this.existing, required this.onSave});

  @override
  State<ActuatorDialog> createState() => _ActuatorDialogState();
}

class _ActuatorDialogState extends State<ActuatorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late ActuatorType _selectedType;
  late int _selectedPin;
  late int _minSpeed;
  late int _maxSpeed;
  late int _minAngle;
  late int _maxAngle;
  late bool _isContinuous;
  late bool _invertDirection;

  int? _in1Pin;
  int? _in2Pin;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _selectedType = widget.existing!.type;
      _selectedPin = widget.existing!.pin;
      _minSpeed = widget.existing!.minSpeed;
      _maxSpeed = widget.existing!.maxSpeed;
      _minAngle = widget.existing!.minAngle;
      _maxAngle = widget.existing!.maxAngle;
      _isContinuous = widget.existing!.isContinuous;
      _invertDirection = widget.existing!.invertedDirection;
      _in1Pin = widget.existing!.parameters['in1'] as int?;
      _in2Pin = widget.existing!.parameters['in2'] as int?;
    } else {
      _selectedType = ActuatorType.motor;
      _selectedPin = 2;
      _minSpeed = 0;
      _maxSpeed = 255;
      _minAngle = 0;
      _maxAngle = 180;
      _isContinuous = false;
      _invertDirection = false;
    }
  }

  // Common Pin Labels for ESP32/Uno
  String _getPinLabel(int pin) {
    if (pin == 0 || pin == 1) return "Reserved for Serial (Uno)";
    if (pin == 2) return "Built-in LED (ESP32)";
    if (pin == 13) return "Built-in LED (Uno)";
    if (pin >= 34 && pin <= 39) return "Input Only (ESP32)";
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? "Add Actuator" : "Edit Actuator"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Name",
                  hintText: "Left Wheel, Arm Servo...",
                ),
                validator: (v) => v?.isEmpty ?? true ? "Required" : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ActuatorType>(
                initialValue: _selectedType,
                decoration: const InputDecoration(labelText: "Type"),
                items: ActuatorType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text("${type.emoji} ${type.displayName}"),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedType = v!),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              const Text("Select Pin Number", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(40, (index) {
                      final pin = index;
                      final isSelected = _selectedPin == pin;
                      final label = _getPinLabel(pin);
                      
                      return ChoiceChip(
                        label: Text("$pin"),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedPin = pin);
                        },
                        selectedColor: const Color(0xFF6366F1),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: label.isEmpty ? Colors.white : Colors.blueGrey.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFF6366F1) : Colors.grey[300]!,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              if (_getPinLabel(_selectedPin).isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text(
                        _getPinLabel(_selectedPin),
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              if (_selectedType == ActuatorType.motor) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text("H-Bridge Direction Pins (Optional)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 4),
                const Text(
                  "IN1 = direction pin 1, IN2 = direction pin 2.\n"
                  "Single-pin mode: set IN1 only, leave IN2 as None (wire IN2 directly to GND on the H-bridge). "
                  "HIGH = forward, LOW = stop. No reverse available in this mode.",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _in1Pin,
                        decoration: const InputDecoration(labelText: "IN1 Pin", labelStyle: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text("None", style: TextStyle(fontSize: 12))),
                          ...List.generate(40, (i) => i).map((p) => DropdownMenuItem(value: p, child: Text("Pin $p", style: TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (v) => setState(() => _in1Pin = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _in2Pin,
                        decoration: const InputDecoration(labelText: "IN2 Pin", labelStyle: TextStyle(fontSize: 12)),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text("None", style: TextStyle(fontSize: 12))),
                          ...List.generate(40, (i) => i).map((p) => DropdownMenuItem(value: p, child: Text("Pin $p", style: TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (v) => setState(() => _in2Pin = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _minSpeed.toString(),
                        decoration: const InputDecoration(labelText: "Min Speed"),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _minSpeed = (int.tryParse(v) ?? 0).clamp(0, 255),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        initialValue: _maxSpeed.toString(),
                        decoration: const InputDecoration(labelText: "Max Speed"),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _maxSpeed = (int.tryParse(v) ?? 255).clamp(0, 255),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Invert direction", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Swap FORWARD and BACKWARD for this motor", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  value: _invertDirection,
                  onChanged: (v) => setState(() => _invertDirection = v),
                ),
              ],
              if (_selectedType == ActuatorType.servo) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber[800], size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Servos require high current. Use an external battery if the board resets when moving.",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    "Continuous Rotation Servo",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isContinuous
                        ? "PWM 1300 µs = full reverse · 1500 µs = stop · 1700 µs = full forward"
                        : "Standard positional servo (0–180°)",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: _isContinuous,
                  onChanged: (v) => setState(() {
                    _isContinuous = v;
                    if (v) {
                      _minAngle = 1300;
                      _maxAngle = 1700;
                    } else {
                      _minAngle = 0;
                      _maxAngle = 180;
                    }
                  }),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('minAngle_$_isContinuous'),
                        initialValue: _minAngle.toString(),
                        decoration: InputDecoration(
                          labelText: _isContinuous ? "Min PWM (µs)" : "Min Angle",
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _minAngle = _isContinuous
                            ? (int.tryParse(v) ?? 1300).clamp(1000, 2000)
                            : (int.tryParse(v) ?? 0).clamp(0, 180),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        key: ValueKey('maxAngle_$_isContinuous'),
                        initialValue: _maxAngle.toString(),
                        decoration: InputDecoration(
                          labelText: _isContinuous ? "Max PWM (µs)" : "Max Angle",
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _maxAngle = _isContinuous
                            ? (int.tryParse(v) ?? 1700).clamp(1000, 2000)
                            : (int.tryParse(v) ?? 180).clamp(0, 180),
                      ),
                    ),
                  ],
                ),
                if (_isContinuous) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Invert direction", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text("Swap FORWARD and BACKWARD for this servo", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    value: _invertDirection,
                    onChanged: (v) => setState(() => _invertDirection = v),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text("Save"),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final config = ActuatorConfig(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      type: _selectedType,
      pin: _selectedPin,
      parameters: {
        if (_selectedType == ActuatorType.motor) ...{
          'minSpeed': _minSpeed,
          'maxSpeed': _maxSpeed,
          if (_in1Pin != null) 'in1': _in1Pin,
          if (_in2Pin != null) 'in2': _in2Pin,
          if (_invertDirection) 'inverted': true,
        },
        if (_selectedType == ActuatorType.servo) ...{
          'minAngle': _minAngle,
          'maxAngle': _maxAngle,
          'continuous': _isContinuous,
          if (_isContinuous && _invertDirection) 'inverted': true,
        },
      },
    );

    widget.onSave(config);
    Navigator.pop(context);
  }
}
