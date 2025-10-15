// lib/models/emulator_extensions.dart
import 'dart:io';
import '../models.dart'; // si tu EmulatorData está en models.dart ajusta el path

extension EmulatorIdExt on EmulatorData {
  /// ID estable del emulador: usa exePath normalizado si existe,
  /// sino usa name en lowercase.
  String get id {
    final p = exePath.trim();
    if (p.isEmpty) return name.toLowerCase();
    try {
      final resolved = File(p).resolveSymbolicLinksSync();
      final fixed = resolved.replaceAll('\\', '/');
      return Platform.isWindows ? fixed.toLowerCase() : fixed;
    } catch (_) {
      final fixed = p.replaceAll('\\', '/');
      return Platform.isWindows ? fixed.toLowerCase() : fixed;
    }
  }
}
