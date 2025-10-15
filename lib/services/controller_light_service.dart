import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class ControllerLightService {
  // Try to find the helper exe/dll in common build locations relative to app cwd
  static String? _findHelper() {
    final cwd = Directory.current.path;
    final candidates = [
      // exe (if published)
      '$cwd\\tools\\controller-light\\bin\\Release\\net8.0\\SetControllerLight.exe',
      // dll (run with dotnet)
      '$cwd\\tools\\controller-light\\bin\\Release\\net8.0\\SetControllerLight.dll',
      // alternative net7 path (older builds)
      '$cwd\\tools\\controller-light\\bin\\Release\\net7.0\\SetControllerLight.exe',
      '$cwd\\tools\\controller-light\\bin\\Release\\net7.0\\SetControllerLight.dll',
    ];

    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  // Apply color given an ARGB int (0xAARRGGBB)
  static Future<bool> applyColorFromInt(int argb) async {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return await applyColor(r, g, b);
  }

  // Attempt to run the helper. Returns true if exit code == 0
  static Future<bool> applyColor(int r, int g, int b) async {
    if (!Platform.isWindows) return false;
    try {
      final helper = _findHelper();
      if (helper == null) return false;

      ProcessResult res;
      if (helper.toLowerCase().endsWith('.dll')) {
        // run via dotnet
    res = await Process.run('dotnet', [helper, '--r', '$r', '--g', '$g', '--b', '$b'],
      runInShell: true, stdoutEncoding: utf8, stderrEncoding: utf8);
      } else {
        // exe
    res = await Process.run(helper, ['--r', '$r', '--g', '$g', '--b', '$b'],
      runInShell: true, stdoutEncoding: utf8, stderrEncoding: utf8);
      }

      if (kDebugMode) {
        stdout.writeln('ControllerLight helper stdout: ${res.stdout}');
        stderr.writeln('ControllerLight helper stderr: ${res.stderr}');
      }

      return res.exitCode == 0;
    } catch (e) {
      if (kDebugMode) stderr.writeln('ControllerLight apply error: $e');
      return false;
    }
  }
}
