// Persistence logic for SettingsService
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SettingsPersistence {
  static const fileName = 'emuchull_settings.json';

  Future<File> getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<void> atomicWrite(File file, String contents) async {
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(contents);
      if (await file.exists()) {
        await file.delete();
      }
      await tmp.rename(file.path);
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loadJson() async {
    try {
      final file = await getLocalFile();
      if (!await file.exists()) return null;
      final str = await file.readAsString();
      if (str.isEmpty) return null;
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveJson(Map<String, dynamic> data) async {
    try {
      final file = await getLocalFile();
      final jsonStr = jsonEncode(data);
      await atomicWrite(file, jsonStr);
    } catch (e) {}
  }
}
