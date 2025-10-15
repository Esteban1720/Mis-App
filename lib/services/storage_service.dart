// lib/services/storage_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import 'emulator_helper.dart';

class StorageService {
  static const String _fileName = 'emulators.json';

  static Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static String _normalizePath(String p) {
    if (p.isEmpty) return p;
    final fixed = p.replaceAll('\\', '/');
    return Platform.isWindows ? fixed.toLowerCase() : fixed;
  }

  static String _canonical(String path) {
    try {
      final file = File(path);
      final resolved = file.resolveSymbolicLinksSync();
      return _normalizePath(resolved);
    } catch (_) {
      return _normalizePath(path);
    }
  }

  static bool _fileExistsLoose(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) return true;
      try {
        final resolved = file.resolveSymbolicLinksSync();
        return File(resolved).existsSync();
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<List<EmulatorData>> loadEmulators() async {
    try {
      final file = await _localFile();
      if (!await file.exists()) return [];

      final contents = await file.readAsString();
      final List<dynamic> list = jsonDecode(contents);

      final loaded = list
          .map((e) => EmulatorData.fromJson(e as Map<String, dynamic>))
          .toList();

      var changed = false;

      for (var emu in loaded) {
        final Map<String, GameData> map = {};
        for (var g in emu.games) {
          final key = _canonical(g.path);
          final defaultName = EmulatorHelper.cleanGameName(g.path);

          if (!map.containsKey(key)) {
            if (!_fileExistsLoose(g.path)) {
              changed = true;
              continue;
            }
            map[key] = g;
          } else {
            final existing = map[key]!;
            final existingIsDefault = (existing.displayName.trim().isEmpty) ||
                (existing.displayName == defaultName);
            final newIsDefault = (g.displayName.trim().isEmpty) ||
                (g.displayName == defaultName);

            if (existingIsDefault && !newIsDefault) {
              map[key] = g;
            } else if (!existingIsDefault && newIsDefault) {
              // keep existing
            } else if (g.coverUrl != null && existing.coverUrl == null) {
              map[key] = g;
            } else {
              map[key] = g;
            }
          }
        }

        final filtered = <GameData>[];
        for (var g in map.values) {
          if (_fileExistsLoose(g.path)) {
            filtered.add(g);
          } else {
            changed = true;
          }
        }
        emu.games = filtered;
      }

      if (changed) {
        try {
          final data = loaded.map((e) => e.toJson()).toList();
          await file.writeAsString(jsonEncode(data));
          print(
              '✅ StorageService: limpiado emulators.json (archivos inexistentes removidos).');
        } catch (e) {
          print('❌ Error al persistir limpieza en storage: $e');
        }
      }

      return loaded;
    } catch (e) {
      print('❌ Error cargando emuladores: $e');
      return [];
    }
  }

  static Future<void> saveEmulators(List<EmulatorData> emulators) async {
    try {
      for (var emu in emulators) {
        final Map<String, GameData> map = {};

        for (var g in emu.games) {
          final n = _canonical(g.path);
          if (!map.containsKey(n)) {
            map[n] = g;
          } else {
            final existing = map[n]!;
            final defaultExisting = (existing.displayName.trim().isEmpty) ||
                (existing.displayName ==
                    EmulatorHelper.cleanGameName(existing.path));
            final defaultNew = (g.displayName.trim().isEmpty) ||
                (g.displayName == EmulatorHelper.cleanGameName(g.path));

            if (defaultExisting && !defaultNew) {
              map[n] = g;
            } else if (!defaultExisting && defaultNew) {
              // keep existing
            } else if (g.coverUrl != null && existing.coverUrl == null) {
              map[n] = g;
            } else {
              map[n] = g;
            }
          }
        }
        emu.games = map.values.toList();
      }

      final file = await _localFile();
      final data = emulators.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print('❌ Error guardando emuladores: $e');
    }
  }

  static Future<void> removeGameFromAllSaved(String gamePath) async {
    try {
      final file = await _localFile();
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      final List<dynamic> list = jsonDecode(contents);
      final loaded = list
          .map((e) => EmulatorData.fromJson(e as Map<String, dynamic>))
          .toList();

      final normTarget = _canonical(gamePath);
      var changed = false;

      for (var emu in loaded) {
        final before = emu.games.length;
        emu.games =
            emu.games.where((g) => _canonical(g.path) != normTarget).toList();
        if (emu.games.length != before) changed = true;
      }

      if (changed) {
        final data = loaded.map((e) => e.toJson()).toList();
        await file.writeAsString(jsonEncode(data));
        print(
            '✅ StorageService: eliminado juego de todas las entradas guardadas.');
      }
    } catch (e) {
      print('❌ Error en removeGameFromAllSaved: $e');
    }
  }

  static Future<void> renameGame(
      List<EmulatorData> emulators, String gamePath, String newName) async {
    final norm = _normalizePath(gamePath);

    for (var emu in emulators) {
      for (var g in emu.games) {
        if (_normalizePath(g.path) == norm) {
          g.displayName = newName.trim();
          await saveEmulators(emulators);
          print('✅ Juego renombrado y guardado: $newName');
          return;
        }
      }
    }
  }
}
