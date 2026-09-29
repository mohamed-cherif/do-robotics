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
  })  : inputValues = {
          // Start from the definition's defaults so what the editor shows is
          // what runs. Palette blocks used to start empty: the editor showed
          // e.g. Number = 90 or Heard "go", while the runner and the Python
          // converter fell back to 0 / "" — a fresh "Heard [go]" never fired.
          for (final input in definition.inputs)
            if (input.type != InputFieldType.blockSocket && input.defaultValue != null)
              input.id: input.defaultValue,
          ...?inputValues,
        },
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

  /// Reconstruct a [BlockInstance] (and the chain after it) from JSON.
  /// Blocks whose definition no longer exists (e.g. a deleted actuator) are
  /// skipped; the blocks chained after them are kept.
  static BlockInstance? fromJson(
    Map<String, dynamic> json,
    List<BlockDefinition> allDefinitions,
  ) =>
      _chainFromJson(json, {for (final d in allDefinitions) d.id: d}, ScriptLoadReport._(), 0);

  static List<BlockInstance> listFromJson(
    String jsonString,
    List<BlockDefinition> allDefinitions,
  ) =>
      loadScript(jsonString, allDefinitions).blocks;

  /// Parses a saved script without ever throwing: malformed JSON, wrong
  /// types, unknown blocks and absurd nesting are reported in the result.
  static ScriptLoadReport loadScript(String jsonString, List<BlockDefinition> allDefinitions) {
    final report = ScriptLoadReport._();
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (_) {
      report.damaged = true;
      return report;
    }
    if (decoded is! List) {
      report.damaged = true;
      return report;
    }
    final defs = {for (final d in allDefinitions) d.id: d};
    for (final entry in decoded) {
      if (entry is Map) {
        final b = _chainFromJson(entry, defs, report, 0);
        if (b != null) report.blocks.add(b);
      } else {
        report.malformed++;
      }
    }
    return report;
  }

  /// Deepest nesting accepted when loading (a real program is < 20 deep).
  static const int maxLoadDepth = 100;

  static BlockInstance? _chainFromJson(
      Map node, Map<String, BlockDefinition> defs, ScriptLoadReport report, int depth) {
    if (depth > maxLoadDepth) {
      report.malformed++;
      return null;
    }
    BlockInstance? head, tail;
    Object? current = node;
    // Iterative over nextBlock so long chains don't recurse.
    while (current is Map) {
      final block = _singleFromJson(current, defs, report, depth);
      if (block != null) {
        if (tail == null) {
          head = block;
        } else {
          tail.nextBlock = block;
        }
        tail = block;
      }
      current = current['nextBlock'];
    }
    if (current != null) report.malformed++;
    return head;
  }

  static BlockInstance? _singleFromJson(
      Map json, Map<String, BlockDefinition> defs, ScriptLoadReport report, int depth) {
    final defId = json['definitionId'];
    final def = defId is String ? defs[defId] : null;
    if (def == null) {
      report.skipped++;
      if (defId is String) report.unknownIds.add(defId);
      return null;
    }

    final nested = <String, BlockInstance?>{};
    final rawNested = json['nestedBlocks'];
    if (rawNested is Map) {
      rawNested.forEach((k, v) {
        if (k is! String) return;
        nested[k] = v is Map ? _chainFromJson(v, defs, report, depth + 1) : null;
      });
    }

    final rawInputs = json['inputValues'];
    final pos = json['position'];
    double coord(String k) {
      final v = pos is Map ? pos[k] : null;
      return v is num && v.isFinite ? v.toDouble() : 0;
    }

    return BlockInstance(
      instanceId: json['instanceId'] is String ? json['instanceId'] as String : '',
      definition: def,
      inputValues: rawInputs is Map
          ? {for (final e in rawInputs.entries) if (e.key is String) e.key as String: e.value}
          : null,
      nestedBlocks: nested,
      position: Offset(coord('dx'), coord('dy')),
    );
  }

  static String listToJson(List<BlockInstance> blocks) =>
      jsonEncode(blocks.map((b) => b.toJson()).toList());
}

/// What happened when a saved script was loaded.
class ScriptLoadReport {
  ScriptLoadReport._();

  /// Root blocks that could be restored.
  final List<BlockInstance> blocks = [];
  /// Blocks dropped because their definition no longer exists.
  int skipped = 0;
  final Set<String> unknownIds = {};
  /// Entries with the wrong shape (ignored).
  int malformed = 0;
  /// The file is not a block script at all (bad JSON / wrong top level).
  bool damaged = false;
}

// Pre-defined block colors
class BlockColors {
  static const Color sensor = Color(0xFF8B5CF6);
  static const Color logic = Color(0xFF10B981);
  static const Color action = Color(0xFFF59E0B);
  static const Color value = Color(0xFF3B82F6);
  static const Color boolean = Color(0xFFEC4899);
}
