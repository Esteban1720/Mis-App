import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/input_service.dart';
import '../services/audio_service.dart';
// cleaned unused imports

// -----------------------------------------------------------------------------
// Constantes visuales
// -----------------------------------------------------------------------------
const _kDialogHorizontalPadding = 14.0;
const _kDialogVerticalPadding = 12.0;
const _kKeyboardBorderRadius = 14.0;
const _kTileCornerRadius = 12.0;
const _kHeaderHeight = 56.0;
const _kTextFieldHeight = 58.0;

// -----------------------------------------------------------------------------
// OnScreenKeyboard (mejorado)
// - Mantiene compatibilidad con isPin
// - Extrae KeyTile como widget
// - Usa Semantics y controles más claros
// -----------------------------------------------------------------------------
class OnScreenKeyboard extends StatefulWidget {
  final String initialValue;
  final String title;
  final int maxLength;
  final bool isPin;

  const OnScreenKeyboard({
    super.key,
    required this.initialValue,
    required this.title,
    required this.maxLength,
    this.isPin = false,
  });

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  late final TextEditingController _controller;
  late final FocusNode _textFocus;

  late List<String> _keys;
  late int _cols;
  int _focused = 0;
  final Set<int> _pressed = {};
  VoidCallback? _removeListener;
  bool _caps = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _textFocus = FocusNode();
    _initLayout();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachInput();
      final len = _controller.text.length;
      _controller.selection = TextSelection.collapsed(offset: len);
      if (mounted) _textFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _removeListener?.call();
    _textFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _initLayout() {
    if (widget.isPin) {
      _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'BACK', '0', 'OK'];
      _cols = 3;
    } else {
      _keys = [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '0',
        'q',
        'w',
        'e',
        'r',
        't',
        'y',
        'u',
        'i',
        'o',
        'p',
        'a',
        's',
        'd',
        'f',
        'g',
        'h',
        'j',
        'k',
        'l',
        'ñ',
        'z',
        'x',
        'c',
        'v',
        'b',
        'n',
        'm',
        ',',
        '.',
        '-',
        'CAPS',
        'SPACE',
        'LEFT',
        'RIGHT',
        'BACK',
        'CLEAR',
        'OK',
        'CANCEL'
      ];
      _cols = 10;
    }
    if (_focused >= _keys.length) _focused = 0;
  }

  void _playNav() => AudioService.instance.playNav();
  void _playAction() => AudioService.instance.playAction();

  void _attachInput() {
    final input = InputService.instance;
    _removeListener = input.pushListener(InputListener(
      onLeft: () {
        _playNav();
        setState(() =>
            _focused = (_focused - 1) < 0 ? _keys.length - 1 : _focused - 1);
      },
      onRight: () {
        _playNav();
        setState(() => _focused = (_focused + 1) % _keys.length);
      },
      onUp: () {
        _playNav();
        setState(() {
          final cand = _focused - _cols;
          if (cand < 0) {
            final base = (_keys.length - 1) ~/ _cols;
            _focused = _focused % _cols + base * _cols;
            if (_focused >= _keys.length) _focused = _keys.length - 1;
          } else {
            _focused = cand;
          }
        });
      },
      onDown: () {
        _playNav();
        setState(() {
          final cand = _focused + _cols;
          if (cand >= _keys.length) {
            _focused = _focused % _cols;
          } else {
            _focused = cand;
          }
        });
      },
      onActivate: () async => await _activateAt(_focused),
      onBack: () {
        _playAction();
        Navigator.of(context).pop(null);
      },
    ));
  }

  int _validPos([int? fallback]) {
    final pos = _controller.selection.baseOffset;
    if (pos < 0) return fallback ?? _controller.text.length;
    return pos.clamp(0, _controller.text.length);
  }

  Future<void> _activateAt(int idx) async {
    _playAction();
    final key = _keys[idx];
    setState(() => _pressed.add(idx));
    await Future.delayed(const Duration(milliseconds: 110));
    setState(() => _pressed.remove(idx));

    if (key == 'OK') {
      final out = widget.isPin ? _controller.text : _controller.text.trim();
      Navigator.of(context).pop(out);
      return;
    }

    if (key == 'CANCEL') {
      Navigator.of(context).pop(null);
      return;
    }

    if (key == 'BACK') {
      if (_controller.text.isNotEmpty) {
        int pos = _validPos(_controller.text.length);
        if (pos > 0) {
          final newText = _controller.text.substring(0, pos - 1) +
              _controller.text.substring(pos);
          _controller.text = newText;
          final newPos = (pos - 1).clamp(0, _controller.text.length);
          _controller.selection = TextSelection.collapsed(offset: newPos);
        } else {
          final txt = _controller.text;
          if (txt.isNotEmpty) {
            _controller.text = txt.substring(0, txt.length - 1);
            _controller.selection =
                TextSelection.collapsed(offset: _controller.text.length);
          }
        }
      }
      return;
    }

    if (key == 'CLEAR') {
      _controller.clear();
      _controller.selection = const TextSelection.collapsed(offset: 0);
      return;
    }

    if (key == 'CAPS') {
      setState(() => _caps = !_caps);
      return;
    }

    if (key == 'LEFT' || key == 'RIGHT') {
      int pos = _validPos(_controller.text.length);
      int newPos = pos;
      if (key == 'LEFT' && pos > 0) newPos = pos - 1;
      if (key == 'RIGHT' && pos < _controller.text.length) newPos = pos + 1;
      _controller.selection = TextSelection.collapsed(offset: newPos);
      return;
    }

    if (key == 'SPACE') {
      final pos = _validPos(_controller.text.length);
      if (_controller.text.length < widget.maxLength) {
        final newText =
            '${_controller.text.substring(0, pos)} ${_controller.text.substring(pos)}';
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(offset: pos + 1);
      }
      return;
    }

    if (RegExp(r'^[0-9a-zñ,\.\-]$', caseSensitive: false).hasMatch(key)) {
      if (_controller.text.length < widget.maxLength) {
        final newKey = _caps ? key.toUpperCase() : key.toLowerCase();
        final pos = _validPos(_controller.text.length);
        final newText = _controller.text.substring(0, pos) +
            newKey +
            _controller.text.substring(pos);
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(offset: pos + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPin = widget.isPin;
    final screenSize = MediaQuery.of(context).size;

    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = min(
        constraints.maxWidth.isFinite ? constraints.maxWidth : screenSize.width,
        screenSize.width * 0.98,
      );

      const spacing = 10.0;
      final baseKeyboardWidth = isPin
          ? min(availableWidth * 0.78, 380.0)
          : min(availableWidth * 0.92, 1200.0);
      final double minTileWidth = isPin ? 44.0 : 64.0;
      final double usableWidthForTiles =
          baseKeyboardWidth - _kDialogHorizontalPadding;

      int effectiveCols = _cols;
      if (usableWidthForTiles > 0) {
        final int colsFromWidth =
            max(3, (usableWidthForTiles / (minTileWidth + spacing)).floor());
        effectiveCols = min(_cols, colsFromWidth);
      }
      effectiveCols = max(3, effectiveCols);

      double tileWidth = (baseKeyboardWidth -
              _kDialogHorizontalPadding -
              (effectiveCols - 1) * spacing) /
          effectiveCols;
      tileWidth = max(tileWidth, minTileWidth);

      final rows = (_keys.length / effectiveCols).ceil();

      final screenH = screenSize.height;
      double availableH = min(
              constraints.maxHeight.isFinite ? constraints.maxHeight : screenH,
              screenH * 0.92) -
          24.0;
      double remainingForGrid = availableH -
          _kHeaderHeight -
          _kTextFieldHeight -
          _kDialogVerticalPadding -
          12.0;
      final minTileHeight = isPin ? 36.0 : 40.0;
      if (remainingForGrid < minTileHeight) {
        remainingForGrid = minTileHeight + 8.0;
      }

      double tileHeight =
          max((remainingForGrid - (rows - 1) * spacing) / rows, minTileHeight);
      final childAspectRatio = max(0.4, tileWidth / tileHeight);

      final double gridHeight =
          (rows * tileHeight + max(0, (rows - 1)) * spacing)
              .clamp(minTileHeight, remainingForGrid);
      final keyboardWidth = baseKeyboardWidth;
      final keyboardHeight = _kHeaderHeight +
          _kTextFieldHeight +
          _kDialogVerticalPadding +
          12.0 +
          gridHeight;

      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: keyboardWidth,
              maxHeight: min(keyboardHeight, availableH + _kHeaderHeight),
              minWidth: 280),
          child: Material(
            color: const Color(0xFF0E0F11),
            elevation: 6,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_kKeyboardBorderRadius)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: _kDialogHorizontalPadding,
                  vertical: _kDialogVerticalPadding),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18))),
                  IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(null)),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  height: _kTextFieldHeight,
                  child: TextField(
                    controller: _controller,
                    focusNode: _textFocus,
                    maxLength: widget.maxLength,
                    obscureText: false,
                    showCursor: true,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                    cursorColor: Colors.white,
                    keyboardType:
                        isPin ? TextInputType.number : TextInputType.text,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white10,
                      counterStyle: const TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: gridHeight,
                  child: FocusTraversalGroup(
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(6),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: effectiveCols,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: _keys.length,
                      itemBuilder: (context, i) {
                        if (_focused >= _keys.length) _focused = 0;
                        final k = _keys[i];
                        String visualKey = k;
                        if (k.length == 1 &&
                            RegExp(r'[a-zñ]', caseSensitive: false)
                                .hasMatch(k)) {
                          visualKey = _caps ? k.toUpperCase() : k.toLowerCase();
                        }
                        final isFocused = i == _focused;
                        final isPressed = _pressed.contains(i);
                        final fs = isPin
                            ? (visualKey.length > 3 ? 14.0 : 20.0)
                            : (visualKey.length > 3 ? 14.0 : 18.0);
                        final label = (isPin && k == 'OK') ? 'OK' : visualKey;

                        return Semantics(
                          button: true,
                          label: 'Tecla $label',
                          child: GestureDetector(
                            onTap: () async {
                              setState(() => _focused = i);
                              await _activateAt(i);
                            },
                            child: _KeyTile(
                                label: label,
                                isFocused: isFocused,
                                isPressed: isPressed,
                                fontSize: fs),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

class _KeyTile extends StatelessWidget {
  final String label;
  final bool isFocused;
  final bool isPressed;
  final double fontSize;

  const _KeyTile(
      {required this.label,
      required this.isFocused,
      required this.isPressed,
      required this.fontSize});

  @override
  Widget build(BuildContext context) {
    String display = label;
    if (label == 'BACK') display = '←';
    if (label == 'OK') display = 'ACEPTAR';
    if (label == 'SPACE') display = 'ESPACIO';
    if (label == 'CAPS') display = label; // ya viene en el texto apropiado

    final base = Colors.white12;
    final bg = isPressed ? Colors.white24 : (isFocused ? Colors.white24 : base);
    final scale = isPressed ? 0.96 : (isFocused ? 1.06 : 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.identity()..scale(scale),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_kTileCornerRadius),
        border: Border.all(
            color: isFocused ? Colors.white : Colors.white30,
            width: isFocused ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: Text(display,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white,
              fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
              fontSize: fontSize)),
    );
  }
}
