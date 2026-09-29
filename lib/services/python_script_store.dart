import 'package:shared_preferences/shared_preferences.dart';

/// Named Python scripts persisted in SharedPreferences, plus the editor's
/// unsaved draft so a crash or tab switch never loses work.
class PythonScriptStore {
  static const String _prefix = 'python_scripts/';
  static const String _draftKey = 'python_draft';

  Future<List<String>> listNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys()
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toList()
      ..sort();
  }

  Future<void> save(String name, String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$name', source);
  }

  Future<String?> load(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$name');
  }

  Future<void> delete(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$name');
  }

  Future<void> saveDraft(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, source);
  }

  Future<String?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_draftKey);
  }
}
