// lib/services/settings_service.dart
// SettingsService — detecta resoluciones del sistema (16:9 / 4:3), aplica window settings robustamente,
// y persiste la configuración en disco (escritura atómica).

import 'package:flutter/material.dart';
import 'settings_audio.dart';
import 'settings_window.dart';
import 'settings_controls.dart';
import 'settings_persistence.dart';
import 'package:window_manager/window_manager.dart';

class SettingsService {
  SettingsService._internal();
  static final SettingsService instance = SettingsService._internal();

  // Submodules
  final SettingsAudio audio = SettingsAudio();
  final SettingsWindow window = SettingsWindow();
  final SettingsControls controls = SettingsControls();
  final SettingsPersistence persistence = SettingsPersistence();

  // Shortcuts for ValueNotifiers
  ValueNotifier<double> get masterVolume => audio.masterVolume;
  ValueNotifier<double> get musicVolume => audio.musicVolume;
  ValueNotifier<double> get sfxVolume => audio.sfxVolume;
  ValueNotifier<bool> get bgMusicEnabled => audio.bgMusicEnabled;

  ValueNotifier<bool> get isFullscreen => window.isFullscreen;
  ValueNotifier<Size> get windowSize => window.windowSize;

  ValueNotifier<double> get controllerSensitivity =>
      controls.controllerSensitivity;
  ValueNotifier<bool> get invertYAxis => controls.invertYAxis;
  // Color chosen for PS4/PS5 controller theming (stored as ARGB int)
  ValueNotifier<int> get controllerColor => controls.controllerColor;

  // Cached resolutions
  List<Size> get availableResolutions => window.availableResolutions;

  Future<void> load() async {
    final json = await persistence.loadJson();
    if (json == null) return;
    audio.load(json);
    window.load(json);
    controls.load(json);
  }

  Future<void> save() async {
    final data = <String, dynamic>{}
      ..addAll(audio.toJson())
      ..addAll(window.toJson())
      ..addAll(controls.toJson());
    await persistence.saveJson(data);
  }

  Future<void> resetToDefaults() async {
    audio.resetToDefaults();
    window.resetToDefaults();
    controls.resetToDefaults();
    await save();
  }

  // --- Window resolution logic ---
  Future<List<Size>> detectAvailableResolutions(
      {bool filterAspect = true}) async {
    // Attempt to produce a sensible list of available resolutions.
    // We avoid calling platform-specific display enumeration to keep this robust.
    // Instead, provide a curated list filtered by the primary display size when possible.
    try {
      // Common desktop resolutions (descending)
      final candidates = <Size>[
        const Size(3840, 2160),
        const Size(2560, 1440),
        const Size(1920, 1200),
        const Size(1920, 1080),
        const Size(1680, 1050),
        const Size(1600, 900),
        const Size(1440, 900),
        const Size(1366, 768),
        const Size(1280, 800),
        const Size(1280, 720),
        const Size(1024, 768),
      ];

      // Try to get current window bounds via window_manager if available.
      Size? screenSize;
      try {
        final b = await windowManager.getBounds();
        screenSize = Size(b.width.toDouble(), b.height.toDouble());
      } catch (_) {
        // ignore; fall back to no screen size
      }

      // If we have a screenSize, filter candidates to those <= screen size
      final result = <Size>[];
      for (final c in candidates) {
        if (screenSize == null ||
            (c.width <= screenSize.width + 8 &&
                c.height <= screenSize.height + 8)) {
          if (!result.any((r) => r.width == c.width && r.height == c.height)) {
            result.add(c);
          }
        }
      }

      // Always include the current configured size as a fallback first item
      final current = window.windowSize.value;
      if (!result
          .any((r) => r.width == current.width && r.height == current.height)) {
        result.insert(0, current);
      }

      // Ensure 1920x1080 is available as an option (user requested up to 1920x1080)
      const target1080 = Size(1920, 1080);
      if (!result.any((r) =>
          r.width == target1080.width && r.height == target1080.height)) {
        // insert after current if current is first, else append
        if (result.isNotEmpty) {
          result.insert(1, target1080);
        } else {
          result.add(target1080);
        }
      }

      // Persist into SettingsWindow.availableResolutions
      window.availableResolutions = result;
      return result;
    } catch (e) {
      // In case of any error, return whatever the window has or a small default set
      if (window.availableResolutions.isNotEmpty) {
        return window.availableResolutions;
      }
      final fallback = <Size>[window.windowSize.value, const Size(1280, 800)];
      window.availableResolutions = fallback;
      return fallback;
    }
  }

  Future<List<Size>> getAvailableResolutions(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && window.availableResolutions.isNotEmpty) {
      return window.availableResolutions;
    }
    return await detectAvailableResolutions();
  }

  bool isAspectMatch(Size s) {
    // compare aspect ratio to current window aspect with tolerance
    final a = s.width / s.height;
    final b = window.windowSize.value.width / window.windowSize.value.height;
    return (a - b).abs() <= SettingsWindow.aspectTolerance;
  }

  Size mapToClosestAvailable(Size target) {
    if (window.availableResolutions.isEmpty) return target;
    double best = double.infinity;
    Size bestSz = window.availableResolutions.first;
    for (final r in window.availableResolutions) {
      final dx = (r.width - target.width).abs();
      final dy = (r.height - target.height).abs();
      final dist = dx * dx + dy * dy;
      if (dist < best) {
        best = dist;
        bestSz = r;
      }
    }
    return bestSz;
  }

  int indexOfAvailable(Size size) {
    for (var i = 0; i < window.availableResolutions.length; i++) {
      final r = window.availableResolutions[i];
      if ((r.width - size.width).abs() <= SettingsWindow.pixelEps &&
          (r.height - size.height).abs() <= SettingsWindow.pixelEps) {
        return i;
      }
    }
    return -1;
  }

  Future<void> applyWindowSettings(
      {bool? fullscreen, Size? size, bool persist = false}) async {
    try {
      // Update runtime notifiers
      if (fullscreen != null) {
        window.isFullscreen.value = fullscreen;
        try {
          await windowManager.setFullScreen(fullscreen);
        } catch (e) {
          debugPrint(
              'SettingsService.applyWindowSettings: setFullScreen failed: $e');
        }
      }

      if (size != null) {
        window.windowSize.value = size;
        try {
          // Only set size when not in fullscreen
          final isFull = await windowManager.isFullScreen();
          if (!isFull) {
            await windowManager.setSize(size);
            await windowManager.setPosition(Offset(0, 0));
            await windowManager.center();
          }
        } catch (e) {
          debugPrint(
              'SettingsService.applyWindowSettings: setSize/center failed: $e');
        }
      }

      // Update availableResolutions mapping if needed
      if (window.availableResolutions.isEmpty) {
        await detectAvailableResolutions();
      }

      // Persist if requested
      if (persist) {
        try {
          await save();
        } catch (e) {
          debugPrint('SettingsService.applyWindowSettings: save failed: $e');
        }
      }
    } catch (e) {
      debugPrint('SettingsService.applyWindowSettings error: $e');
      rethrow;
    }
  }
}
