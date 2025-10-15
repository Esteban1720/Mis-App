import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../models/emulator_extensions.dart';
import 'storage_service.dart';
import 'emulator_helper.dart';

class EmulatorManager {
  String _normalizePath(String p) {
    if (p.isEmpty) return p;
    final fixed = p.replaceAll('\\', '/');
    return Platform.isWindows ? fixed.toLowerCase() : fixed;
  }

  Future<List<EmulatorData>> loadEmulators() async {
    final loaded = await StorageService.loadEmulators();

    // Deduplicar emuladores por id canónico (exePath canonical o name)
    final Map<String, EmulatorData> byId = {};
    for (var emu in loaded) {
      final key = emu.id;
      if (!byId.containsKey(key)) {
        // normalizar juegos por ruta
        final seen = <String>{};
        final unique = <GameData>[];
        for (var g in emu.games) {
          final n = _normalizePath(g.path);
          if (!seen.contains(n)) {
            seen.add(n);
            unique.add(g);
          }
        }
        emu.games = unique;
        byId[key] = emu;
      } else {
        // fusionar juegos y algunos campos si falta info
        final existing = byId[key]!;
        // fusionar juegos evitando duplicados
        final seen = {for (var g in existing.games) _normalizePath(g.path)};
        final mergedGames = List<GameData>.from(existing.games);
        for (var g in emu.games) {
          final n = _normalizePath(g.path);
          if (!seen.contains(n)) {
            mergedGames.add(g);
            seen.add(n);
          }
        }

        // Construir un nuevo EmulatorData que preserve fields y use exePath no vacío si existe
        final newExe =
            existing.exePath.trim().isNotEmpty ? existing.exePath : emu.exePath;

        final merged = EmulatorData(
          name: existing.name.isNotEmpty ? existing.name : emu.name,
          exePath: newExe,
          supportedExts: existing.supportedExts.isNotEmpty
              ? existing.supportedExts
              : emu.supportedExts,
          gamesPath: existing.gamesPath ?? emu.gamesPath,
          games: mergedGames,
          launchFullscreen: existing.launchFullscreen,
          launchArgs: existing.launchArgs.isNotEmpty
              ? existing.launchArgs
              : emu.launchArgs,
          workingDirectory: existing.workingDirectory ?? emu.workingDirectory,
          manualAddsOnly: existing.manualAddsOnly || emu.manualAddsOnly,
        );

        byId[key] = merged;
      }
    }

    final result = byId.values.toList();

    // Guardar de nuevo si hubo merges para mantener storage consistente
    if (result.length != loaded.length) {
      await saveEmulators(result);
    }

    return result;
  }

  Future<void> saveEmulators(List<EmulatorData> emulators) async {
    await StorageService.saveEmulators(emulators);
  }

  Future<void> removeGameGlobally(String gamePath) async {
    try {
      await StorageService.removeGameFromAllSaved(gamePath);
    } catch (e) {
      print('❌ removeGameGlobally error: $e');
    }
  }

  Future<void> cleanMissingGamesAndSave(List<EmulatorData> emulators) async {
    var changed = false;
    for (var emu in emulators) {
      final before = emu.games.length;
      emu.games = emu.games.where((g) => File(g.path).existsSync()).toList();
      if (emu.games.length != before) changed = true;
    }
    if (changed) {
      await saveEmulators(emulators);
      print('✅ EmulatorManager: cleaned missing games and saved.');
    }
  }

  Future<void> renameGamePersistent(String gamePath, String newName) async {
    try {
      final stored = await StorageService.loadEmulators();
      final normTarget = _normalizePath(gamePath);
      var changed = false;

      for (var emu in stored) {
        for (var g in emu.games) {
          if (_normalizePath(g.path) == normTarget) {
            if (g.displayName != newName) {
              g.displayName = newName.trim();
              changed = true;
            }
          }
        }
      }

      if (changed) {
        await StorageService.saveEmulators(stored);
      }
    } catch (e) {
      print('❌ renameGamePersistent error: $e');
    }
  }

  /// Agrega un emulador seleccionando EXE y (opcionalmente) carpeta de juegos.
  Future<EmulatorData?> pickEmulatorAndGames() async {
    FilePickerResult? emulatorResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: Platform.isWindows ? ['exe'] : null,
    );
    if (emulatorResult == null) return null;

    final exePath = emulatorResult.files.single.path!;
    final exeFileName = exePath.split(Platform.pathSeparator).last;
    final exeBaseName = exeFileName.split('.').first.toLowerCase();

    // Detectar por coincidencia parcial con las claves de emulatorExts
    String detectedName = exeBaseName;
    final exeLower = exeFileName.toLowerCase();
    for (final key in EmulatorHelper.emulatorExts.keys) {
      if (exeLower.contains(key.toLowerCase())) {
        detectedName = key;
        break;
      }
    }

    // Heurísticos adicionales si no detectó por key
    if (detectedName == exeBaseName) {
      final nameLower = exeBaseName;
      if (nameLower.contains('pcsx') || nameLower.contains('ps2')) {
        detectedName = 'pcsx2';
      } else if (nameLower.contains('dolphin')) {
        detectedName = 'dolphin';
      } else if (nameLower.contains('cemu')) {
        detectedName = 'cemu';
      } else if (nameLower.contains('ppsspp') || nameLower.contains('psp')) {
        detectedName = 'ppsspp';
      } else if (nameLower.contains('epsxe') || nameLower.contains('epsx')) {
        detectedName = 'epsxe';
      } else if (nameLower.contains('duck') ||
          nameLower.contains('duckstation')) {
        detectedName = 'duckstation';
      } else if (nameLower.contains('rpcs3') || nameLower.contains('rpcs')) {
        detectedName = 'rpcs3';
      } else if (nameLower.contains('yuzu')) {
        detectedName = 'yuzu';
      } else if (nameLower.contains('ryujinx')) {
        detectedName = 'ryujinx';
      } else if (nameLower.contains('citron') ||
          nameLower.contains('citron-')) {
        detectedName = 'citron';
      } else if (nameLower.contains('eden') || nameLower.contains('edn')) {
        detectedName = 'eden';
      } else if (nameLower.contains('citra')) {
        detectedName = 'citra';
      } else if (nameLower.contains('desmume') || nameLower.contains('melon')) {
        detectedName = 'desmume';
      } else if (nameLower.contains('mgba') ||
          nameLower.contains('visualboy')) {
        detectedName = 'mgba';
      } else if (nameLower.contains('mame')) {
        detectedName = 'mame';
      } else if (nameLower.contains('dosbox')) {
        detectedName = 'dosbox';
      } else if (nameLower.contains('winuae')) {
        detectedName = 'winuae';
      } else if (nameLower.contains('vice')) {
        detectedName = 'vice';
      }
    }

    final String? gameFolder = await FilePicker.platform.getDirectoryPath(
      dialogTitle:
          'Elige la carpeta donde tienes tus juegos para este emulador',
    );

    final exts = EmulatorHelper.emulatorExts[detectedName] ??
        EmulatorHelper.emulatorExts['generic'] ??
        <String>[];

    final emulator = EmulatorData(
      name: detectedName,
      exePath: exePath,
      supportedExts: exts.map((e) => e.toLowerCase()).toList(),
      gamesPath: gameFolder,
      games: [],
      launchFullscreen: true, // por defecto sugerida
    );

    return emulator;
  }

  /// Crea una tarjeta especial "PC" pensada para añadir .exe manualmente.
  EmulatorData createPcCard({String displayName = 'PC'}) {
    return EmulatorData(
      name: displayName,
      exePath: '', // no hay EXE "emulador" — los juegos serán .exe individuales
      supportedExts: ['.exe'],
      gamesPath: null,
      games: [],
      launchFullscreen: true,
      manualAddsOnly: true,
    );
  }

  /// Escanea juegos de un emulador.
  Future<void> scanGamesForEmulator(EmulatorData emulator,
      {Directory? baseDir}) async {
    // Si la tarjeta está en modo manual, no escaneamos.
    if (emulator.manualAddsOnly) {
      return;
    }

    List<String> exts = List<String>.from(emulator.supportedExts);

    if (exts.isEmpty) {
      final nameLower = emulator.name.toLowerCase();
      for (final entry in EmulatorHelper.emulatorExts.entries) {
        if (nameLower.contains(entry.key)) {
          exts = List<String>.from(entry.value);
          break;
        }
      }
      if (exts.isEmpty) {
        exts = EmulatorHelper.emulatorExts['generic']!;
      }
    }

    Directory? startDir;
    if (baseDir != null) {
      startDir = baseDir;
    } else if (emulator.gamesPath != null) {
      startDir = Directory(emulator.gamesPath!);
    } else {
      return;
    }

    if (!startDir.existsSync()) return;

    final Map<String, GameData> existingByPath = {
      for (var g in emulator.games) _normalizePath(g.path): g
    };

    final files =
        startDir.listSync(recursive: true).whereType<File>().where((f) {
      final pathNorm = _normalizePath(f.path);
      return exts.any((ext) => pathNorm.endsWith(ext.toLowerCase()));
    }).toList();

    final List<GameData> scanned = [];
    for (final f in files) {
      final norm = _normalizePath(f.path);
      final existing = existingByPath[norm];
      if (existing != null) {
        existing.path = f.path;
        scanned.add(existing);
      } else {
        final gameName = EmulatorHelper.cleanGameName(f.path);
        scanned.add(GameData(path: f.path, displayName: gameName));
      }
    }

    final seen = <String>{};
    final unique = <GameData>[];
    for (var g in scanned) {
      final n = _normalizePath(g.path);
      if (!seen.contains(n)) {
        seen.add(n);
        unique.add(g);
      }
    }

    emulator.games
      ..clear()
      ..addAll(unique);
  }
}
