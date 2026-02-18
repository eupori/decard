import 'package:shared_preferences/shared_preferences.dart';

class LibraryPrefs {
  static const _autoSaveKey = 'auto_save_to_library';
  static const _lastFolderIdKey = 'last_folder_id';

  static Future<bool> getAutoSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSaveKey) ?? false;
  }

  static Future<void> setAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSaveKey, value);
  }

  static Future<String?> getLastFolderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastFolderIdKey);
  }

  static Future<void> setLastFolderId(String? folderId) async {
    final prefs = await SharedPreferences.getInstance();
    if (folderId == null) {
      await prefs.remove(_lastFolderIdKey);
    } else {
      await prefs.setString(_lastFolderIdKey, folderId);
    }
  }
}
