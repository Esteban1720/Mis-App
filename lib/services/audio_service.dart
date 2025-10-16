// lib/services/audio_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:audioplayers/audioplayers.dart';
import 'package:emuchull/services/settings_service.dart';

/// Servicio singleton para efectos de sonido (SFX).
/// - Crea los AudioPlayers dentro de init() (lazy) para evitar crear
///   canales nativos antes de tiempo.
/// - Métodos seguros contra llamadas cuando no está inicializado o ya fue disposed.
class AudioService {
  AudioService._internal();
  static final AudioService instance = AudioService._internal();

  AudioPlayer? _nav;
  AudioPlayer? _action;
  AudioPlayer? _launch;
  AudioPlayer? _bgMusic;
  String? _bgCurrentPath;

  bool _initialized = false;
  bool _disposed = false;
  bool _settingsListenersRegistered = false;

  /// Inicializa los players y aplica volúmenes.
  Future<void> init() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    try {
      // Crear los players aquí, cuando llamas a init() desde main()
      _nav = AudioPlayer();
      _action = AudioPlayer();
      _launch = AudioPlayer();

      // Intentar precargar sources (si fallan, lo ignoramos)
      try {
        await _nav?.setSource(AssetSource('sounds/nav.wav'));
      } catch (_) {}
      try {
        await _action?.setSource(AssetSource('sounds/action.wav'));
      } catch (_) {}
      try {
        await _launch?.setSource(AssetSource('sounds/launch.wav'));
      } catch (_) {}

      // Modo de liberación: stop (no loop)
      try {
        await _launch?.setReleaseMode(ReleaseMode.stop);
        await _nav?.setReleaseMode(ReleaseMode.stop);
        await _action?.setReleaseMode(ReleaseMode.stop);
      } catch (_) {}
    } catch (e) {
      // Si algo falla, marcamos como no-inicializado para reintentar más tarde.
      _initialized = false;
      rethrow;
    }

    // Aplicar volúmenes actuales
    applyVolumesFromSettings();

    // Inicializar background music player (loop) y aplicar según Settings
    try {
      _bgMusic = AudioPlayer();
      await _bgMusic?.setReleaseMode(ReleaseMode.loop);
      // Ensure volume is applied to the newly created bg player before it starts
      applyVolumesFromSettings();
      await _applyBgFromSettings();
    } catch (_) {}

    // Escuchar cambios en settings para seguir sincronizados (una sola vez)
    if (!_settingsListenersRegistered) {
      final s = SettingsService.instance;
      try {
        s.masterVolume.addListener(applyVolumesFromSettings);
        s.sfxVolume.addListener(applyVolumesFromSettings);
        s.musicVolume.addListener(applyVolumesFromSettings);
        // listen to bg music enable/path changes
        s.bgMusicEnabled.addListener(_applyBgFromSettings);
        s.audio.bgMusicPath.addListener(_applyBgFromSettings);
        _settingsListenersRegistered = true;
      } catch (_) {
        // Si no son ValueNotifiers o falla, no hacemos nada
      }
    }
  }

  /// Aplica valores de SettingsService (si los players están creados).
  void applyVolumesFromSettings() {
    if (_disposed) return;
    final s = SettingsService.instance;

    // Asegurarnos de trabajar con double y limitar entre 0.0 y 1.0
    final double master =
        (s.masterVolume.value as num).toDouble().clamp(0.0, 1.0);
    final double sfx = (s.sfxVolume.value as num).toDouble().clamp(0.0, 1.0);
    final double vol = (master * sfx).clamp(0.0, 1.0);

    try {
      _nav?.setVolume(vol);
    } catch (_) {}
    try {
      _action?.setVolume(vol);
    } catch (_) {}
    try {
      _launch?.setVolume(vol);
    } catch (_) {}
    try {
      // bg music uses master * music volume
      final music = (s.musicVolume.value as num).toDouble().clamp(0.0, 1.0);
      final double bgVol = (master * music).clamp(0.0, 1.0);
      _bgMusic?.setVolume(bgVol);
    } catch (_) {}
  }

  Future<void> _applyBgFromSettings() async {
    if (_disposed) return;
    final s = SettingsService.instance;
    final enabled = s.bgMusicEnabled.value;
    final path = s.audio.bgMusicPath.value;
    try {
      if (enabled) {
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          if (_bgCurrentPath != path) {
            // new file selected -> start from zero
            _bgCurrentPath = path;
            await _bgMusic?.setSource(DeviceFileSource(path));
            await _bgMusic?.seek(Duration.zero);
            // ensure correct volume before resuming
            applyVolumesFromSettings();
            await _bgMusic?.resume();
          } else {
            // same file, just ensure it's playing
            applyVolumesFromSettings();
            await _bgMusic?.resume();
          }
        } else {
          // fallback to packaged asset
          if (_bgCurrentPath != 'asset:bg_menu') {
            _bgCurrentPath = 'asset:bg_menu';
            await _bgMusic?.setSource(AssetSource('sounds/bg_menu.mp3'));
            await _bgMusic?.seek(Duration.zero);
            applyVolumesFromSettings();
            await _bgMusic?.resume();
          } else {
            applyVolumesFromSettings();
            await _bgMusic?.resume();
          }
        }
      } else {
        await _bgMusic?.stop();
      }
    } catch (e) {
      debugPrint('AudioService: applyBgFromSettings error: $e');
      try {
        await _bgMusic?.setSource(AssetSource('sounds/bg_menu.mp3'));
      } catch (_) {}
    }
  }

  /// Called on logout to stop and reset background music so next login restarts.
  Future<void> resetBgOnLogout() async {
    try {
      await _bgMusic?.stop();
      _bgCurrentPath = null;
    } catch (_) {}
  }

  /// Pausa la música de fondo (por ejemplo, al abrir un emulador en pantalla completa)
  Future<void> pauseBgMusic() async {
    if (_disposed) return;
    try {
      await _bgMusic?.pause();
    } catch (_) {}
  }

  /// Reanuda la música de fondo si corresponde
  Future<void> resumeBgMusic() async {
    if (_disposed) return;
    try {
      await _bgMusic?.resume();
    } catch (_) {}
  }

  // Ejecuta la función de forma "segura" y devuelve un Future que completa cuando la tarea termina.
  Future<void> _safeRun(FutureOr<void> Function() fn) async {
    if (_disposed) return;
    try {
      final res = fn();
      if (res is Future) {
        // Esperamos pero atrapamos errores para no romper el flujo del app
        await res.catchError((_) {});
      }
    } catch (_) {}
  }

  /// Reproducir SFX de navegación
  Future<void> playNav() async {
    if (_disposed) return;
    await _safeRun(() async {
      try {
        if (_nav == null) {
          _nav = AudioPlayer();
          await _nav?.setReleaseMode(ReleaseMode.stop);
          await _nav?.setSource(AssetSource('sounds/nav.wav'));
          applyVolumesFromSettings();
        }
        await _nav?.seek(Duration.zero);
        await _nav?.resume();
      } catch (_) {
        try {
          await _nav?.play(AssetSource('sounds/nav.wav'));
        } catch (_) {}
      }
    });
  }

  /// Reproducir SFX de acción
  Future<void> playAction() async {
    if (_disposed) return;
    await _safeRun(() async {
      try {
        if (_action == null) {
          _action = AudioPlayer();
          await _action?.setReleaseMode(ReleaseMode.stop);
          await _action?.setSource(AssetSource('sounds/action.wav'));
          applyVolumesFromSettings();
        }
        await _action?.seek(Duration.zero);
        await _action?.resume();
      } catch (_) {
        try {
          await _action?.play(AssetSource('sounds/action.wav'));
        } catch (_) {}
      }
    });
  }

  /// Reproducir SFX de lanzamiento
  Future<void> playLaunch() async {
    if (_disposed) return;
    await _safeRun(() async {
      try {
        if (_launch == null) {
          _launch = AudioPlayer();
          await _launch?.setReleaseMode(ReleaseMode.stop);
          await _launch?.setSource(AssetSource('sounds/launch.wav'));
          applyVolumesFromSettings();
        }
        await _launch?.seek(Duration.zero);
        await _launch?.resume();
      } catch (_) {
        try {
          await _launch?.play(AssetSource('sounds/launch.wav'));
        } catch (_) {}
      }
    });
  }

  /// Dispose seguro
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _initialized = false;

    // Remover listeners de settings (si fueron añadidos)
    try {
      final s = SettingsService.instance;
      if (_settingsListenersRegistered) {
        s.masterVolume.removeListener(applyVolumesFromSettings);
        s.sfxVolume.removeListener(applyVolumesFromSettings);
        s.musicVolume.removeListener(applyVolumesFromSettings);
      }
    } catch (_) {}

    try {
      await _nav?.dispose();
    } catch (_) {}
    _nav = null;

    try {
      await _action?.dispose();
    } catch (_) {}
    _action = null;

    try {
      await _launch?.dispose();
    } catch (_) {}
    _launch = null;
  }
}
