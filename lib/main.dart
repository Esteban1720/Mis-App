// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dart_vlc/dart_vlc.dart'; // dart_vlc para usar libVLC

// Screens
import 'screens/emuchull_login.dart';

// Services
import 'services/input_service.dart';
import 'services/audio_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // -----------------------------
  // Inicializar libVLC (dart_vlc) con argumentos para evitar MMDevice
  // -----------------------------
  try {
    String? vlcFolder;

    // Candidate 1: proyecto/windows/vlc
    final cand1 = Directory(
        '${Directory.current.path}${Platform.pathSeparator}windows${Platform.pathSeparator}vlc');
    if (await cand1.exists()) {
      final lib1 = File('${cand1.path}${Platform.pathSeparator}libvlc.dll');
      final lib2 = File('${cand1.path}${Platform.pathSeparator}libvlccore.dll');
      if (await lib1.exists() && await lib2.exists()) {
        vlcFolder = cand1.path;
        debugPrint(
            'DartVLC: encontrada carpeta vlc en el proyecto: $vlcFolder');
      }
    }

    // Candidate 2: carpeta 'vlc' junto al ejecutable
    if (vlcFolder == null) {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final cand2 = Directory('${exeDir.path}${Platform.pathSeparator}vlc');
      if (await cand2.exists()) {
        final lib1 = File('${cand2.path}${Platform.pathSeparator}libvlc.dll');
        final lib2 =
            File('${cand2.path}${Platform.pathSeparator}libvlccore.dll');
        if (await lib1.exists() && await lib2.exists()) {
          vlcFolder = cand2.path;
          debugPrint(
              'DartVLC: encontrada carpeta vlc junto al exe: $vlcFolder');
        }
      }
    }

    // Candidate 3: instalación en Program Files
    if (vlcFolder == null) {
      final prog1 = Directory(r'C:\Program Files\VideoLAN\VLC');
      final prog2 = Directory(r'C:\Program Files (x86)\VideoLAN\VLC');
      if (await prog1.exists()) {
        vlcFolder = prog1.path;
        debugPrint(
            'DartVLC: encontrada instalación VLC en Program Files: $vlcFolder');
      } else if (await prog2.exists()) {
        vlcFolder = prog2.path;
        debugPrint(
            'DartVLC: encontrada instalación VLC en Program Files (x86): $vlcFolder');
      }
    }

    // Argumentos que queremos pasar a libVLC para evitar MMDevice
    // (usa directsound en lugar de mmdevice). Si prefieres silenciar por completo:
    // sustituye por ['--no-audio'].
    // dentro de main(), donde defines vlcArgs:
    final vlcArgs = <String>['--no-audio'];

    // Usamos una llamada dinámica para intentar varias formas posibles de initialize()
    final initFn = DartVLC.initialize;
    bool initialized = false;

    // Si tenemos ruta a libVLC, intentamos pasarla con nombres de parámetro comunes.
    if (vlcFolder != null) {
      for (final sym in [#libVLCPath, #libVlcPath, #libvlcPath]) {
        try {
          Function.apply(initFn, [], {sym: vlcFolder, #args: vlcArgs});
          debugPrint(
              'DartVLC.initialize(libVLCPath: ..., args: ...) -> OK (sym: $sym)');
          initialized = true;
          break;
        } catch (_) {
          // ignore and try next
        }
      }
    }

    // Intentar solo con args
    if (!initialized) {
      try {
        Function.apply(initFn, [], {#args: vlcArgs});
        debugPrint('DartVLC.initialize(args: ...) -> OK');
        initialized = true;
      } catch (_) {
        // ignore
      }
    }

    // Fallback simple (llamada sin parámetros)
    if (!initialized) {
      try {
        initFn();
        debugPrint('DartVLC.initialize() -> OK (fallback).');
        initialized = true;
      } catch (e) {
        debugPrint('DartVLC.initialize() falló por completo: $e');
      }
    }
  } catch (e, st) {
    debugPrint('Error durante inicialización de DartVLC: $e\n$st');
  }

  // -----------------------------
  // Resto de inicializaciones
  // -----------------------------
  try {
    await windowManager.ensureInitialized();
  } catch (e) {
    debugPrint('window_manager.ensureInitialized() error: $e');
  }

  try {
    await SettingsService.instance.load();
  } catch (e) {
    debugPrint('SettingsService.load() error: $e');
  }

  final initialSize = SettingsService.instance.windowSize.value;
  final initialFullscreen = SettingsService.instance.isFullscreen.value;

  final WindowOptions windowOptions = WindowOptions(
    size: initialSize,
    center: true,
    backgroundColor: Colors.transparent,
    title: 'EmuChull',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    try {
      await windowManager.show();
      await windowManager.focus();
      try {
        await SettingsService.instance.applyWindowSettings(
          fullscreen: initialFullscreen,
          size: initialSize,
          persist: false,
        );
      } catch (e) {
        debugPrint('applyWindowSettings error: $e');
      }
    } catch (e) {
      debugPrint('window_manager show/focus error: $e');
    }
  });

  try {
    await AudioService.instance.init();
  } catch (e) {
    debugPrint('AudioService.init() error: $e');
  }

  try {
    await InputService.instance.initialize();
  } catch (e) {
    debugPrint('InputService.initialize() error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlayStations',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        cardColor: Colors.grey[900],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const EmuChullLoginScreen(),
    );
  }
}
