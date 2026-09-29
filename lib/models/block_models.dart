import 'dart:convert';
import 'package:flutter/material.dart';

// Block types determine shape and connection points
enum BlockShape {
  statement,   // Has top/bottom notches (executes action)
  expression,  // Rounded (returns value)
  boolean,     // Pointed ends (returns true/false)
  hat,         // Top-only (start of program)
}

// Input field types within blocks
enum InputFieldType {
  number,
  text,
  dropdown,
  blockSocket, // Accepts nested block
  color,
}

class InputFieldDefinition {
  final String id;
  final String label;
  final InputFieldType type;
  final dynamic defaultValue;
  final List<String>? options; // For dropdown
  final BlockShape? acceptedBlockShape; // For block sockets
  final int? min;
  final int? max;

  InputFieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.defaultValue,
    this.options,
    this.acceptedBlockShape,
    this.min,
    this.max,
  });
}

class BlockDefinition {
  final String id;
  final String label;
  final String emoji;
  final Color color;
  final BlockShape shape;
  final List<InputFieldDefinition> inputs;
  final String? category;

  BlockDefinition({
    required this.id,
    required this.label,
    required this.emoji,
    required this.color,
    required this.shape,
    this.inputs = const [],
    this.category,
  });
}

class BlockInstance {
  final String instanceId;
  final BlockDefinition definition;
  final Map<String, dynamic> inputValues;
  final Map<String, BlockInstance?> nestedBlocks; // For block socket inputs
  
  BlockInstance? nextBlock; // For statement blocks
  Offset position; // For 2D canvas positioning (only relevant for root blocks)

  BlockInstance({
    required this.instanceId,
    required this.definition,
    Map<String, dynamic>? inputValues,
    Map<String, BlockInstance?>? nestedBlocks,
    this.nextBlock,
    this.position = Offset.zero,
  })  : inputValues = inputValues ?? {},
        nestedBlocks = nestedBlocks ?? {};

  BlockInstance copyWith({
    Map<String, dynamic>? inputValues,
    Map<String, BlockInstance?>? nestedBlocks,
    BlockInstance? nextBlock,
    Offset? position,
  }) {
    return BlockInstance(
      instanceId: instanceId,
      definition: definition,
      inputValues: inputValues ?? this.inputValues,
      nestedBlocks: nestedBlocks ?? this.nestedBlocks,
      nextBlock: nextBlock ?? this.nextBlock,
      position: position ?? this.position,
    );
  }

  /// True if [other] is this block or sits anywhere below it (nested slots
  /// or the `nextBlock` chain). Drop targets use it to refuse a drop that
  /// would put a block inside itself — that created a cycle, which crashed
  /// the editor (infinite widget recursion) and hung the runner.
  bool containsInstance(BlockInstance other) {
    final stack = <BlockInstance>[this];
    while (stack.isNotEmpty) {
      final b = stack.removeLast();
      if (identical(b, other)) return true;
      stack.addAll(b.nestedBlocks.values.whereType<BlockInstance>());
      if (b.nextBlock != null) stack.add(b.nextBlock!);
    }
    return false;
  }

  // Execute this block (to be used by interpreter)
  dynamic getValue() {
    // For expression/boolean blocks, evaluate and return
    return inputValues;
  }

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'instanceId': instanceId,
      'definitionId': definition.id,
      'inputValues': inputValues,
      'nestedBlocks': nestedBlocks.map((k, v) => MapEntry(k, v?.toJson())),
      'nextBlock': nextBlock?.toJson(),
      'position': {'dx': position.dx, 'dy': position.dy},
    };
  }

  /// Reconstruct a [BlockInstance] from JSON. Returns null if the block's
  /// definition ID is not found in [allDefinitions] (e.g. deleted actuator).
  static BlockInstance? fromJson(
    Map<String, dynamic> json,
    List<BlockDefinition> allDefinitions,
  ) {
    final defId = json['definitionId'] as String? ?? '';
    final def = allDefinitions.cast<BlockDefinition?>().firstWhere(
      (d) => d?.id == defId,
      orElse: () => null,
    );
    if (def == null) return null;

    final rawNested = json['nestedBlocks'] as Map<String, dynamic>? ?? {};
    final nested = rawNested.map((k, v) => MapEntry(
      k,
      v != null ? BlockInstance.fromJson(v as Map<String, dynamic>, allDefinitions) : null,
    ));

    final rawNext = json['nextBlock'] as Map<String, dynamic>?;
    final pos = json['position'] as Map<String, dynamic>? ?? {};

    return BlockInstance(
      instanceId: json['instanceId'] as String? ?? '',
      definition: def,
      inputValues: Map<String, dynamic>.from(json['inputValues'] as Map? ?? {}),
      nestedBlocks: nested,
      nextBlock: rawNext != null ? BlockInstance.fromJson(rawNext, allDefinitions) : null,
      position: Offset(
        (pos['dx'] as num?)?.toDouble() ?? 0,
        (pos['dy'] as num?)?.toDouble() ?? 0,
      ),
    );
  }

  static List<BlockInstance> listFromJson(
    String jsonString,
    List<BlockDefinition> allDefinitions,
  ) {
    final list = jsonDecode(jsonString) as List;
    return list
        .map((j) => BlockInstance.fromJson(j as Map<String, dynamic>, allDefinitions))
        .whereType<BlockInstance>()
        .toList();
  }

  static String listToJson(List<BlockInstance> blocks) =>
      jsonEncode(blocks.map((b) => b.toJson()).toList());
}

// Pre-defined block colors
class BlockColors {
  static const Color sensor = Color(0xFF8B5CF6);
  static const Color logic = Color(0xFF10B981);
  static const Color action = Color(0xFFF59E0B);
  static const Color value = Color(0xFF3B82F6);
  static const Color boolean = Color(0xFFEC4899);
}
