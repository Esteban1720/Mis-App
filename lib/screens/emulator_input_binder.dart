// Helper to bind emulator input callbacks in a compact, testable class.
import '../services/input_service.dart';

typedef VoidCb = void Function();

class EmulatorInputBinder {
  final InputService input;
  VoidCb? prevOnLeft;
  VoidCb? prevOnRight;
  VoidCb? prevOnUp;
  VoidCb? prevOnDown;
  VoidCb? prevOnActivate;
  VoidCb? prevOnBack;
  VoidCb? prevOnToggleFullscreen;
  VoidCb? prevOnSettings;
  VoidCb? prevOnSelect;
  VoidCb? prevOnShare;

  final VoidCb onLeft;
  final VoidCb onRight;
  final VoidCb onUp;
  final VoidCb onDown;
  final VoidCb onActivate;
  final VoidCb onBack;
  final VoidCb onToggleFullscreen;
  final VoidCb onSettings;
  final VoidCb onSelect;
  final VoidCb onShare;

  EmulatorInputBinder({
    required this.input,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
    required this.onDown,
    required this.onActivate,
    required this.onBack,
    required this.onToggleFullscreen,
    required this.onSettings,
    required this.onSelect,
    required this.onShare,
  });

  void bind() {
    // save previous handlers
    prevOnLeft = input.onLeft;
    prevOnRight = input.onRight;
    prevOnUp = input.onUp;
    prevOnDown = input.onDown;
    prevOnActivate = input.onActivate;
    prevOnBack = input.onBack;
    prevOnToggleFullscreen = input.onToggleFullscreen;
    prevOnSettings = input.onSettings;
    prevOnSelect = input.onSelect;
    prevOnShare = input.onShare;

    // set new handlers
    input.onLeft = onLeft;
    input.onRight = onRight;
    input.onUp = onUp;
    input.onDown = onDown;
    input.onActivate = onActivate;
    input.onBack = onBack;
    input.onToggleFullscreen = onToggleFullscreen;
    input.onSettings = onSettings;
    input.onSelect = onSelect;
    input.onShare = onShare;
  }

  void unbindAndRestore() {
    // restore previous handlers (best-effort)
    try {
      input.onLeft = prevOnLeft;
      input.onRight = prevOnRight;
      input.onUp = prevOnUp;
      input.onDown = prevOnDown;
      input.onActivate = prevOnActivate;
      input.onBack = prevOnBack;
      input.onToggleFullscreen = prevOnToggleFullscreen;
      input.onSettings = prevOnSettings;
      input.onSelect = prevOnSelect;
      input.onShare = prevOnShare;
    } catch (_) {}
  }
}
