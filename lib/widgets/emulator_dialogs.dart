// File: lib/widgets/emulator_dialogs.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/emulator_manager.dart';
import '../services/input_service.dart';
import '../services/audio_service.dart';

typedef VoidCb = void Function();

/// Dialog de acciones por juego (navegable por gamepad).
///
/// Nota: `onChanged` ahora acepta `Future<void> Function()?` para que puedas
/// pasar `widget.onChanged` (que es `Future<void> Function()?`) desde
/// `EmulatorScreen` sin incompatibilidades de tipos.
Future<void> showGameActionsDialog({
  required BuildContext context,
  required GameData game,
  required EmulatorManager manager,
  required Future<void> Function(GameData) onLaunch,
  required Future<void> Function(GameData) onRename,
  required Future<void> Function(GameData) onChangeIcon,
  required Future<void> Function(GameData) onDelete,
  Future<void> Function()? onChanged,
}) async {
  final input = InputService.instance;
  int focused = 0;
  final items = [
    ['Lanzar', Icons.play_arrow],
    ['Renombrar', Icons.edit],
    ['Cambiar ícono', Icons.image],
    ['Eliminar', Icons.delete],
    ['Cancelar', Icons.close],
  ];

  final remover = input.pushListener(InputListener(
    onLeft: () {
      focused = (focused - 1) < 0 ? items.length - 1 : focused - 1;
      AudioService.instance.playNav();
    },
    onRight: () {
      focused = (focused + 1) % items.length;
      AudioService.instance.playNav();
    },
    onUp: () {
      focused = (focused - 2) < 0 ? (focused - 2 + items.length) : focused - 2;
      focused %= items.length;
      AudioService.instance.playNav();
    },
    onDown: () {
      focused = (focused + 2) % items.length;
      AudioService.instance.playNav();
    },
    onActivate: () async {
      AudioService.instance.playAction();
      switch (focused) {
        case 0:
          Navigator.pop(context);
          await onLaunch(game);
          break;
        case 1:
          Navigator.pop(context);
          await onRename(game);
          if (onChanged != null) await onChanged();
          break;
        case 2:
          Navigator.pop(context);
          await onChangeIcon(game);
          if (onChanged != null) await onChanged();
          break;
        case 3:
          Navigator.pop(context);
          await onDelete(game);
          if (onChanged != null) await onChanged();
          break;
        default:
          Navigator.pop(context);
      }
    },
    onBack: () => Navigator.pop(context),
  ));

  await showDialog(
    context: context,
    builder: (c) {
      return StatefulBuilder(builder: (c, setState) {
        return AlertDialog(
          title: Text(game.displayName.isEmpty
              ? game.path.split(Platform.pathSeparator).last
              : game.displayName),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(items.length, (i) {
              final isF = i == focused;
              return GestureDetector(
                onTap: () async {
                  setState(() => focused = i);
                  AudioService.instance.playAction();
                  switch (i) {
                    case 0:
                      Navigator.pop(context);
                      await onLaunch(game);
                      break;
                    case 1:
                      Navigator.pop(context);
                      await onRename(game);
                      if (onChanged != null) await onChanged();
                      break;
                    case 2:
                      Navigator.pop(context);
                      await onChangeIcon(game);
                      if (onChanged != null) await onChanged();
                      break;
                    case 3:
                      Navigator.pop(context);
                      await onDelete(game);
                      if (onChanged != null) await onChanged();
                      break;
                    default:
                      Navigator.pop(context);
                  }
                },
                child: Container(
                  width: 120,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isF ? Colors.white10 : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                    border: isF
                        ? Border.all(color: const Color(0xFF66E0FF), width: 2)
                        : null,
                  ),
                  child: Column(children: [
                    Icon(items[i][1] as IconData, size: 28),
                    const SizedBox(height: 6),
                    Text(items[i][0] as String, textAlign: TextAlign.center)
                  ]),
                ),
              );
            }),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'))
          ],
        );
      });
    },
  );

  try {
    remover();
  } catch (_) {}
}

Future<bool?> showDeleteGameDialog({
  required BuildContext context,
  required GameData game,
}) async {
  final input = InputService.instance;
  VoidCb? removeListener;
  int focused = 0;
  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      return StatefulBuilder(builder: (c, setState) {
        removeListener ??= input.pushListener(InputListener(
          onLeft: () {
            focused = (focused - 1) < 0 ? 1 : focused - 1;
            AudioService.instance.playNav();
            try {
              setState(() {});
            } catch (_) {}
          },
          onRight: () {
            focused = (focused + 1) % 2;
            AudioService.instance.playNav();
            try {
              setState(() {});
            } catch (_) {}
          },
          onUp: () {
            AudioService.instance.playNav();
          },
          onDown: () {
            AudioService.instance.playNav();
          },
          onActivate: () {
            AudioService.instance.playAction();
            if (focused == 1) {
              Navigator.of(context).pop(true);
            } else {
              Navigator.of(context).pop(false);
            }
          },
          onBack: () {
            AudioService.instance.playAction();
            Navigator.of(context).pop(false);
          },
        ));
        return AlertDialog(
          title: const Text('Eliminar juego'),
          content: Text(
              'Eliminar "${game.displayName}" de la lista? (no borra archivo)'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancelar',
                  style: TextStyle(
                      color: focused == 0 ? const Color(0xFF66E0FF) : null,
                      fontWeight: focused == 0 ? FontWeight.bold : null)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Eliminar',
                  style: TextStyle(
                      color: focused == 1 ? Colors.redAccent : null,
                      fontWeight: focused == 1 ? FontWeight.bold : null)),
            ),
          ],
        );
      });
    },
  );
  try {
    removeListener?.call();
  } catch (_) {}
  return confirm;
}
