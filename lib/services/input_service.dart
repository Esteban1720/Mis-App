// lib/services/input_service.dart
// InputService con comportamiento hold/repeat y logging de debug mejorado.
// Ajustado para menor latencia en gamepad (polling más frecuente y dispatch inmediato).

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:win32_gamepad/win32_gamepad.dart' show Gamepad, GamepadState;
import 'package:window_manager/window_manager.dart';

typedef VoidCb = void Function();

class InputListener {
  VoidCb? onLeft,
      onRight,
      onUp,
      onDown,
      onActivate,
      onBack,
      onToggleFullscreen,
      onSelect,
      onShare,
      onSettings,
      onTriangle;

  InputListener({
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onActivate,
    this.onBack,
    this.onToggleFullscreen,
    this.onSelect,
    this.onShare,
    this.onSettings,
    this.onTriangle,
  });
}

class InputService {
  InputService._internal();
  static final InputService _instance = InputService._internal();
  static InputService get instance => _instance;

  bool _initialized = false;
  // Keep the previous window bounds so we can restore after exiting fullscreen
  Rect? _preFullscreenBounds;
  bool? _preFullscreenWasMaximized;

  // Global fallback handlers (opcional)
  VoidCb? onLeft,
      onRight,
      onUp,
      onDown,
      onActivate,
      onBack,
      onToggleFullscreen,
      onSelect,
      onShare,
      onSettings,
      onTriangle;

  final List<InputListener> _listeners = [];
  final Map<String, int> _lastFired = {};

  // Valores ajustados para mejor reactividad
  int _debounceMs = 30; // menor debounce -> más responsivo
  Timer? _pollTimer;
  Timer? _rescanTimer;

  final List<Gamepad> _pads = [];
  final List<GamepadState?> _prevStates = [];
  final Map<String, Timer?> _repeatTimers = {};
  StreamSubscription<dynamic>? _subscription;

  int _initialRepeatDelay = 220; // reduce delay inicial (antes 300)
  int _repeatInterval = 60; // intervalo repetición (antes 80)

  bool _enableDebug = false;

  void _d(String msg) {
    if (_enableDebug) debugPrint('InputService: $msg');
  }

  Future<void> initialize({
    bool enableDebug = false,
    int? initialDelayMs,
    int? repeatIntervalMs,
    int? debounceMs,
  }) async {
    if (_initialized) return;
    _enableDebug = enableDebug;
    if (initialDelayMs != null) _initialRepeatDelay = initialDelayMs;
    if (repeatIntervalMs != null) _repeatInterval = repeatIntervalMs;
    if (debounceMs != null) _debounceMs = debounceMs;

    if (Platform.isWindows) {
      _startWindowsPolling();
    } else {
      _initGeneric();
    }
    _initialized = true;
  }

  Future<void> suspend() async {
    if (!_initialized) return;
    if (Platform.isWindows) {
      _stopWindowsPolling();
    } else {
      try {
        _subscription?.pause();
      } catch (_) {}
    }
  }

  Future<void> resume() async {
    if (!_initialized) return;
    if (Platform.isWindows) {
      _startWindowsPolling();
    } else {
      try {
        _subscription?.resume();
      } catch (_) {}
    }
  }

  void dispose() {
    if (!_initialized) return;
    if (Platform.isWindows) {
      _stopWindowsPolling();
    } else {
      _subscription?.cancel();
      _subscription = null;
    }
    _initialized = false;
  }

  void _initGeneric() {
    // Implementación para otras plataformas si hace falta
  }

  // Añade un listener al stack y devuelve función para removerlo
  VoidCb pushListener(InputListener listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  InputListener? get _topListener =>
      _listeners.isNotEmpty ? _listeners.last : null;

  // Dispatch inmediato para reducir latencia (evitamos addPostFrameCallback)
  void _dispatch(VoidCb? Function(InputListener l) selector, VoidCb? fallback) {
    final top = _topListener;
    try {
      void call() {
        try {
          if (top != null) {
            final cb = selector(top);
            if (cb != null) {
              cb();
              return;
            }
          }
          if (fallback != null) fallback();
        } catch (e, st) {
          // swallow errors to avoid crash por un listener malicioso
          debugPrint('InputService._dispatch callback error: $e\n$st');
        }
      }

      // Llamada inmediata (más responsiva). Si por alguna razón esto falla,
      // hacemos fallback a scheduleMicrotask.
      try {
        call();
      } catch (_) {
        scheduleMicrotask(() {
          try {
            call();
          } catch (_) {}
        });
      }
    } catch (_) {}
  }

  String _repeatKey(String action, int padIndex) => '$action:$padIndex';

  void _startRepeat(String key, VoidCb trigger) {
    try {
      _repeatTimers[key]?.cancel();
    } catch (_) {}
    Timer? initialTimer;
    initialTimer = Timer(Duration(milliseconds: _initialRepeatDelay), () {
      try {
        trigger();
      } catch (_) {}
      try {
        _repeatTimers[key] =
            Timer.periodic(Duration(milliseconds: _repeatInterval), (_) {
          try {
            trigger();
          } catch (_) {}
        });
      } catch (_) {}
    });
    _repeatTimers[key] = initialTimer;
  }

  void _stopRepeat(String key) {
    try {
      _repeatTimers[key]?.cancel();
    } catch (_) {}
    _repeatTimers.remove(key);
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  bool _shouldFire(String key) {
    final now = _now();
    final last = _lastFired[key] ?? 0;
    if (now - last < _debounceMs) return false;
    _lastFired[key] = now;
    return true;
  }

  void _startWindowsPolling() {
    if (_pollTimer != null) return;

    _pads.clear();
    _prevStates.clear();

    for (var i = 0; i < 4; i++) {
      try {
        final pad = Gamepad(i);
        _pads.add(pad);
        _prevStates.add(pad.state);
      } catch (_) {}
    }

    if (_pads.isEmpty) {
      _d('No gamepads detected, starting rescan timer');
      try {
        _rescanTimer?.cancel();
      } catch (_) {}
      _rescanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          final found = <Gamepad>[];
          final foundPrev = <GamepadState?>[];
          for (var i = 0; i < 4; i++) {
            try {
              final pad = Gamepad(i);
              found.add(pad);
              foundPrev.add(pad.state);
            } catch (_) {}
          }
          if (found.isNotEmpty) {
            _d('Gamepad(s) detected on rescan: ${found.length}');
            try {
              _rescanTimer?.cancel();
            } catch (_) {}
            _rescanTimer = null;
            _pads.clear();
            _prevStates.clear();
            _pads.addAll(found);
            _prevStates.addAll(foundPrev);
            // start normal polling loop (poll rápido para menor latencia)
            _pollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
              _pollLoop();
            });
          }
        } catch (_) {}
      });
      return;
    }

    // If we found pads initially, start the normal polling loop (poll rápido)
    _pollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      _pollLoop();
    });
  }

  // Extraigo el cuerpo del polling a un método para reducir repetición
  void _pollLoop() {
    try {
      for (var i = 0; i < _pads.length; i++) {
        final pad = _pads[i];
        pad.updateState();
        final state = pad.state;
        final prev = _prevStates[i]!;

        // D-Pad
        if (state.dpadUp && !prev.dpadUp) {
          final key = _repeatKey('up', i);
          if (_shouldFire('up:$i')) _dispatch((l) => l.onUp, onUp);
          _startRepeat(key, () => _dispatch((l) => l.onUp, onUp));
        } else if (!state.dpadUp && prev.dpadUp) {
          _stopRepeat(_repeatKey('up', i));
        }

        if (state.dpadDown && !prev.dpadDown) {
          final key = _repeatKey('down', i);
          if (_shouldFire('down:$i')) _dispatch((l) => l.onDown, onDown);
          _startRepeat(key, () => _dispatch((l) => l.onDown, onDown));
        } else if (!state.dpadDown && prev.dpadDown) {
          _stopRepeat(_repeatKey('down', i));
        }

        if (state.dpadLeft && !prev.dpadLeft) {
          final key = _repeatKey('left', i);
          if (_shouldFire('left:$i')) _dispatch((l) => l.onLeft, onLeft);
          _startRepeat(key, () => _dispatch((l) => l.onLeft, onLeft));
        } else if (!state.dpadLeft && prev.dpadLeft) {
          _stopRepeat(_repeatKey('left', i));
        }

        if (state.dpadRight && !prev.dpadRight) {
          final key = _repeatKey('right', i);
          if (_shouldFire('right:$i')) _dispatch((l) => l.onRight, onRight);
          _startRepeat(key, () => _dispatch((l) => l.onRight, onRight));
        } else if (!state.dpadRight && prev.dpadRight) {
          _stopRepeat(_repeatKey('right', i));
        }

        // Buttons
        if (state.buttonA && !prev.buttonA) {
          if (_shouldFire('activate:$i')) {
            _dispatch((l) => l.onActivate, onActivate);
          }
        }
        if (state.buttonB && !prev.buttonB) {
          if (_shouldFire('back:$i')) _dispatch((l) => l.onBack, onBack);
        }
        if (state.buttonStart && !prev.buttonStart) {
          if (_shouldFire('toggle_fs:$i')) {
            _dispatch((l) => l.onToggleFullscreen, onToggleFullscreen);
          }
        }
        if (state.buttonX && !prev.buttonX) {
          // map the SHARE button to toggle fullscreen if no specific handler
          if (_shouldFire('share:$i')) {
            // prefer specific listener.onShare, fallback to toggle fullscreen
            _dispatch((l) => l.onShare, () {
              try {
                toggleFullscreen();
              } catch (_) {}
            });
          }
        }
        if (state.buttonBack && !prev.buttonBack) {
          if (_shouldFire('select:$i')) {
            // map SELECT/back button to toggle fullscreen as well if desired
            _dispatch((l) => l.onSelect, () {
              try {
                toggleFullscreen();
              } catch (_) {}
            });
          }
        }

        // BOTÓN Y => TRIÁNGULO
        if (state.buttonY && !prev.buttonY) {
          if (_shouldFire('triangle:$i')) {
            _dispatch((l) => l.onTriangle, onTriangle);
          }
        }

        // Thumbstick deadzone handling (left stick)
        const dead = 12000;
        if (state.leftThumbstickX <= -dead && prev.leftThumbstickX > -dead) {
          final key = _repeatKey('left', i);
          if (_shouldFire('left:$i')) _dispatch((l) => l.onLeft, onLeft);
          _startRepeat(key, () => _dispatch((l) => l.onLeft, onLeft));
        } else if (state.leftThumbstickX > -dead &&
            prev.leftThumbstickX <= -dead) {
          _stopRepeat(_repeatKey('left', i));
        } else if (state.leftThumbstickX >= dead &&
            prev.leftThumbstickX < dead) {
          final key = _repeatKey('right', i);
          if (_shouldFire('right:$i')) _dispatch((l) => l.onRight, onRight);
          _startRepeat(key, () => _dispatch((l) => l.onRight, onRight));
        } else if (state.leftThumbstickX < dead &&
            prev.leftThumbstickX >= dead) {
          _stopRepeat(_repeatKey('right', i));
        }

        if (state.leftThumbstickY >= dead && prev.leftThumbstickY < dead) {
          final key = _repeatKey('up', i);
          if (_shouldFire('up:$i')) _dispatch((l) => l.onUp, onUp);
          _startRepeat(key, () => _dispatch((l) => l.onUp, onUp));
        } else if (state.leftThumbstickY < dead &&
            prev.leftThumbstickY >= dead) {
          _stopRepeat(_repeatKey('up', i));
        } else if (state.leftThumbstickY <= -dead &&
            prev.leftThumbstickY > -dead) {
          final key = _repeatKey('down', i);
          if (_shouldFire('down:$i')) _dispatch((l) => l.onDown, onDown);
          _startRepeat(key, () => _dispatch((l) => l.onDown, onDown));
        } else if (state.leftThumbstickY > -dead &&
            prev.leftThumbstickY <= -dead) {
          _stopRepeat(_repeatKey('down', i));
        }

        _prevStates[i] = state;
      }
    } catch (e, st) {
      // swallow exceptions to keep loop alive
      debugPrint('InputService._pollLoop error: $e\n$st');
    }
  }

  void _stopWindowsPolling() {
    try {
      _pollTimer?.cancel();
    } catch (_) {}
    _pollTimer = null;
    try {
      _rescanTimer?.cancel();
    } catch (_) {}
    _rescanTimer = null;

    for (final key in _repeatTimers.keys.toList()) {
      try {
        _repeatTimers[key]?.cancel();
      } catch (_) {}
    }
    _repeatTimers.clear();
    _pads.clear();
    _prevStates.clear();
  }

  Future<void> toggleFullscreen() async {
    try {
      final isFull = await windowManager.isFullScreen();
      if (!isFull) {
        // entering fullscreen: remember current bounds and maximized state
        try {
          final b = await windowManager.getBounds();
          _preFullscreenBounds = b;
        } catch (_) {
          _preFullscreenBounds = null;
        }
        try {
          _preFullscreenWasMaximized = await windowManager.isMaximized();
        } catch (_) {
          _preFullscreenWasMaximized = null;
        }
        await windowManager.setFullScreen(true);
        await windowManager.focus();
      } else {
        // exiting fullscreen: unset and restore previous bounds or maximized state
        await windowManager.setFullScreen(false);
        await windowManager.focus();
        try {
          if (_preFullscreenWasMaximized == true) {
            // restore to maximized if it was maximized before
            try {
              await windowManager.maximize();
            } catch (_) {
              // if maximize fails, fall back to bounds restoration
              if (_preFullscreenBounds != null) {
                final b = _preFullscreenBounds!;
                await windowManager
                    .setSize(Size(b.width.toDouble(), b.height.toDouble()));
                await windowManager
                    .setPosition(Offset(b.left.toDouble(), b.top.toDouble()));
              } else {
                await windowManager.center();
              }
            }
          } else if (_preFullscreenBounds != null) {
            final b = _preFullscreenBounds!;
            await windowManager
                .setSize(Size(b.width.toDouble(), b.height.toDouble()));
            await windowManager
                .setPosition(Offset(b.left.toDouble(), b.top.toDouble()));
          } else {
            // fallback: center the window
            await windowManager.center();
          }
        } catch (_) {
          try {
            await windowManager.center();
          } catch (_) {}
        }
        // clear saved state
        _preFullscreenBounds = null;
        _preFullscreenWasMaximized = null;
      }
    } catch (e, st) {
      debugPrint('InputService.toggleFullscreen error: $e\n$st');
    }
  }
}
