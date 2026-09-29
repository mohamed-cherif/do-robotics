import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/block_models.dart';

class InputFieldWidget extends StatefulWidget {
  final InputFieldDefinition input;
  final dynamic value;
  final Function(dynamic) onChanged;

  const InputFieldWidget({
    super.key,
    required this.input,
    required this.value,
    required this.onChanged,
  });

  @override
  State<InputFieldWidget> createState() => _InputFieldWidgetState();
}

class _InputFieldWidgetState extends State<InputFieldWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: (widget.value ?? widget.input.defaultValue ?? '').toString());
  }

  @override
  void didUpdateWidget(InputFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final newValueStr =
          (widget.value ?? widget.input.defaultValue ?? '').toString();
      if (_controller.text != newValueStr) {
        _controller.value = _controller.value.copyWith(
          text: newValueStr,
          selection: TextSelection.collapsed(offset: newValueStr.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.input.type) {
      case InputFieldType.number:
        return _buildNumberInput();
      case InputFieldType.text:
        return _buildTextInput();
      case InputFieldType.dropdown:
        return _buildDropdown();
      case InputFieldType.blockSocket:
        return const SizedBox(); // Handled by parent
      case InputFieldType.color:
        return _buildColorPicker();
    }
  }

  Widget _buildNumberInput() {
    return Container(
      width: 72,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(
          signed: true,
          decimal: true,
        ),
        // Allow digits, minus sign, and decimal point; full validation in onChanged
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[-\d.]')),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: (v) {
          if (v.isEmpty) {
            widget.onChanged(0);
            return;
          }
          // Allow intermediate states while the user is still typing
          // (e.g. "-", "0.", "-0.") — don't notify parent yet
          final isIntermediate = v == '-' || v.endsWith('.');
          if (isIntermediate) return;

          final parsed = double.tryParse(v);
          if (parsed != null) {
            // Pass as int when the value is a whole number, double otherwise
            widget.onChanged(parsed == parsed.truncateToDouble() ? parsed.toInt() : parsed);
          }
        },
      ),
    );
  }

  Widget _buildTextInput() {
    return Container(
      width: 100,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: _controller,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }

  Widget _buildDropdown() {
    final options = widget.input.options ?? [];
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.value ??
              widget.input.defaultValue ??
              (options.isNotEmpty ? options.first : null),
          isDense: true,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          items: options.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (v) => widget.onChanged(v),
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Pick a color'),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Colors.red, Colors.orange, Colors.yellow, Colors.green,
                Colors.blue, Colors.purple, Colors.white, Colors.black,
                Colors.pink, Colors.cyan, Colors.teal, Colors.amber,
              ].map((c) => GestureDetector(
                onTap: () {
                  widget.onChanged(c);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              )).toList(),
            ),
          ),
        );
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: widget.value ?? Colors.red,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}
