// lib/services/profile_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../models.dart';
import '../models/emulator_extensions.dart';

class ProfileService {
  ProfileService._internal();
  static final ProfileService instance = ProfileService._internal();

  /// Perfil actualmente conectado en la sesión de la aplicación.
  /// No se persiste automáticamente; es un estado en memoria para uso runtime.
  Profile? currentProfile;

  static const _kProfilesKey = 'emuchull_profiles_v1';
  static const _salt = 'emuchull_salt_v1';

  Future<List<Profile>> loadProfiles() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = sp.getString(_kProfilesKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = json.decode(jsonStr) as List<dynamic>;
      final profiles = list
          .map((e) => Profile.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Deduplicar emulatorIds dentro de cada perfil para evitar referencias repetidas
      for (var p in profiles) {
        final seen = <String>{};
        final unique = <String>[];
        for (var id in p.emulatorIds) {
          if (!seen.contains(id)) {
            seen.add(id);
            unique.add(id);
          }
        }
        p.emulatorIds = unique;
        // Migrate legacy gamePaths into gamesByEmulator under a special key
        // if gamesByEmulator is empty but gamePaths present.
        if ((p.gamesByEmulator.isEmpty) && p.gamePaths.isNotEmpty) {
          // store legacy paths under key '__legacy__'
          p.gamesByEmulator['__legacy__'] = List<String>.from(p.gamePaths);
        }
      }

      return profiles;
    } catch (e, st) {
      debugPrint('ProfileService.loadProfiles error: $e\n$st');
      return [];
    }
  }

  /// Devuelve la lista de rutas de juegos asociadas a un perfil y emulador.
  /// Si no hay entradas, devuelve lista vacía.
  List<String> getProfileGamesForEmulator(Profile p, String emulatorId) {
    return p.gamesByEmulator[emulatorId] ?? <String>[];
  }

  /// Actualiza las rutas de juegos asociadas a un perfil y emulador y persiste.
  Future<void> setProfileGamesForEmulator(
      Profile p, String emulatorId, List<String> paths) async {
    p.gamesByEmulator[emulatorId] = List<String>.from(paths);
    try {
      final profiles = await loadProfiles();
      final idx = profiles.indexWhere((pr) => pr.id == p.id);
      if (idx >= 0) {
        profiles[idx] = p;
      } else {
        profiles.add(p);
      }
      await saveProfiles(profiles);
    } catch (e, st) {
      debugPrint('setProfileGamesForEmulator error: $e\n$st');
    }
  }

  /// Normaliza los emulatorIds de los perfiles contra la lista de emuladores
  /// cargados (mapea y deduplica en base a EmulatorData.id).
  Future<void> normalizeProfileEmulatorIds(List<EmulatorData> emulators) async {
    try {
      final profiles = await loadProfiles();
      final Map<String, String> canonicalMap = {};
      for (var e in emulators) {
        canonicalMap[e.id] = e.id;
      }

      var changed = false;
      for (var p in profiles) {
        final seen = <String>{};
        final newIds = <String>[];
        for (var id in p.emulatorIds) {
          final mapped = canonicalMap[id] ?? id;
          if (!seen.contains(mapped)) {
            seen.add(mapped);
            newIds.add(mapped);
          } else {
            changed = true;
          }
        }
        if (newIds.length != p.emulatorIds.length) changed = true;
        p.emulatorIds = newIds;
      }
      if (changed) await saveProfiles(profiles);
    } catch (e, st) {
      debugPrint('normalizeProfileEmulatorIds error: $e\n$st');
    }
  }

  Future<void> saveProfiles(List<Profile> profiles) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = json.encode(profiles.map((p) => p.toJson()).toList());
      await sp.setString(_kProfilesKey, jsonStr);
    } catch (e, st) {
      debugPrint('ProfileService.saveProfiles error: $e\n$st');
    }
  }

  String hashPin(String pin) {
    final bytes = utf8.encode(pin + _salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Elimina la referencia a un emulador en todos los perfiles
  Future<void> removeEmulatorFromAllProfiles(String emulatorId) async {
    try {
      final profiles = await loadProfiles();
      var changed = false;
      for (var p in profiles) {
        if (p.emulatorIds.contains(emulatorId)) {
          p.emulatorIds.removeWhere((id) => id == emulatorId);
          changed = true;
        }
      }
      if (changed) await saveProfiles(profiles);
    } catch (e, st) {
      debugPrint('removeEmulatorFromAllProfiles error: $e\n$st');
    }
  }

  /// Marca un perfil como actualmente activo en la sesión.
  void setCurrentProfile(Profile p) {
    currentProfile = p;
  }

  /// Limpia el perfil actual (por ejemplo al cerrar sesión).
  void clearCurrentProfile() {
    currentProfile = null;
  }
}
