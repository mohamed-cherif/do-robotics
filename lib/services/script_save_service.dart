import 'package:shared_preferences/shared_preferences.dart';
import '../models/block_models.dart';

class ScriptSaveService {
  static const String _scriptsKey = 'saved_scripts';

  /// Returns a map of slot name → JSON string, or empty map if nothing saved.
  Future<Map<String, String>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('$_scriptsKey/')).toSet();
    final map = <String, String>{};
    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null) map[k.substring('$_scriptsKey/'.length)] = v;
    }
    return map;
  }

  /// All saved slot names, sorted alphabetically.
  Future<List<String>> listSlots() async {
    final raw = await _loadRaw();
    return raw.keys.toList()..sort();
  }

  Future<void> save(String slotName, List<BlockInstance> blocks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_scriptsKey/$slotName',
      BlockInstance.listToJson(blocks),
    );
  }

  /// Loads a slot. Returns null if it doesn't exist; never throws on a
  /// damaged or partly incompatible script (see [ScriptLoadReport]).
  Future<ScriptLoadReport?> load(
    String slotName,
    List<BlockDefinition> allDefinitions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_scriptsKey/$slotName');
    if (json == null) return null;
    return BlockInstance.loadScript(json, allDefinitions);
  }

  Future<void> delete(String slotName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_scriptsKey/$slotName');
  }
}
