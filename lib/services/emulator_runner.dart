import 'dart:io';
import 'dart:convert';
import 'package:window_manager/window_manager.dart';
import '../services/input_service.dart';
import '../services/audio_service.dart';

class EmulatorRunner {
  bool _wasFullScreenBeforeLaunch = false;

  Future<void> startProcessAndHandle({
    required String exe,
    required List<String> args,
    required String wd,
    required String startingSnack,
    required bool playLaunchSound,
    required Function(String) onStdout,
    required Function(String) onStderr,
    required Function() onCleanup,
    required Function() onRestoreInput,
  }) async {
    if (!File(exe).existsSync()) {
      throw Exception('Archivo no encontrado.');
    }
    try {
      await InputService.instance.suspend();
    } catch (_) {}
    try {
      _wasFullScreenBeforeLaunch = await windowManager.isFullScreen();
    } catch (_) {
      _wasFullScreenBeforeLaunch = false;
    }
    try {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 180));
    } catch (_) {}
    final Process proc = await Process.start(
      exe,
      args,
      workingDirectory: wd,
      runInShell: true,
    );
    proc.stdout.transform(utf8.decoder).listen(onStdout);
    proc.stderr.transform(utf8.decoder).listen(onStderr);
    if (playLaunchSound) AudioService.instance.playLaunch();
    proc.exitCode.then((code) async {
      await onCleanup();
      if (_wasFullScreenBeforeLaunch) {
        try {
          await windowManager.setFullScreen(true);
        } catch (_) {}
      }
      await onRestoreInput();
      _wasFullScreenBeforeLaunch = false;
    });
  }

  Future<void> handleProcessExitCleanup() async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      await windowManager.show();
    } catch (_) {}
    try {
      await windowManager.restore();
    } catch (_) {}
    try {
      await windowManager.setAlwaysOnTop(true);
      await Future.delayed(const Duration(milliseconds: 60));
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
    try {
      await windowManager.focus();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 120));
  }
}
