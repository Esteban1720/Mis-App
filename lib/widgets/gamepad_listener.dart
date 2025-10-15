// lib/widgets/gamepad_listener.dart
import 'package:flutter/material.dart';
import '../services/input_service.dart';

/// GamepadListener: widget que registra un InputListener mientras el widget
/// está montado y mapea eventos del mando a navegación por foco y acciones
/// estándar de Flutter (ActivateIntent, pop, next/previous focus).
///
/// Ahora acepta callbacks opcionales que reemplazan el comportamiento por
/// defecto: onLeft/onRight/onUp/onDown/onActivate/onBack/onTriangle.
class GamepadListener extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onActivate;
  final VoidCallback? onBack;
  final VoidCallback? onTriangle; // <-- añadido

  const GamepadListener({
    super.key,
    required this.child,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onActivate,
    this.onBack,
    this.onTriangle, // <-- añadido
  });

  @override
  State<GamepadListener> createState() => _GamepadListenerState();
}

class _GamepadListenerState extends State<GamepadListener> {
  late VoidCallback _remove;

  @override
  void initState() {
    super.initState();
    final listener = InputListener(
      onLeft: widget.onLeft ?? _onLeft,
      onRight: widget.onRight ?? _onRight,
      onUp: widget.onUp ?? _onUp,
      onDown: widget.onDown ?? _onDown,
      onActivate: widget.onActivate ?? _onActivate,
      onBack: widget.onBack ?? _onBack,
      onTriangle: widget.onTriangle ?? _onTriangle, // <-- pasado al listener
    );
    _remove = InputService.instance.pushListener(listener);
  }

  void _onLeft() {
    try {
      // intentar moverse al foco previo
      FocusScope.of(context).previousFocus();
    } catch (_) {}
  }

  void _onRight() {
    try {
      FocusScope.of(context).nextFocus();
    } catch (_) {}
  }

  void _onUp() {
    try {
      FocusScope.of(context).previousFocus();
    } catch (_) {}
  }

  void _onDown() {
    try {
      FocusScope.of(context).nextFocus();
    } catch (_) {}
  }

  void _onActivate() {
    try {
      Actions.invoke(context, const ActivateIntent());
    } catch (_) {}
  }

  void _onBack() {
    try {
      Navigator.maybePop(context);
    } catch (_) {}
  }

  void _onTriangle() {
    // Comportamiento por defecto para TRIÁNGULO: no hace nada aquí
    // pero el widget que esté dentro del GamepadListener puede proporcionar
    // widget.onTriangle para sobreescribirlo (por ejemplo tu pantalla emuchull).
    try {
      // si tienes AudioService: AudioService.instance.playAction();
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _remove();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
