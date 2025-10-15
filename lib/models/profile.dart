// lib/models/profile.dart

class Profile {
  String id;
  String name;
  String? avatarPath;
  bool isPrivate;
  String? pinHash;

  /// IDs de emuladores asociados (usar EmulatorData.id)
  List<String> emulatorIds;

  /// Rutas de juegos guardados manualmente para este perfil
  /// Legacy: list of global game paths (kept for backward compatibility).
  List<String> gamePaths;

  /// Map of emulatorId -> list of GameData.path (per-profile saved games per emulator)
  ///
  /// Nota: almacenamos solo rutas/paths aquí para mantener la serialización
  /// sencilla y evitar duplicar metadatos pesado. La UI reconstruye GameData
  /// a partir de esos paths cuando carga la pantalla del emulador.
  Map<String, List<String>> gamesByEmulator;

  Profile({
    required this.id,
    required this.name,
    this.avatarPath,
    this.isPrivate = false,
    this.pinHash,
    List<String>? emulatorIds,
    List<String>? gamePaths,
    Map<String, List<String>>? gamesByEmulator,
  })  : emulatorIds = emulatorIds ?? [],
        gamePaths = gamePaths ?? [],
        gamesByEmulator = gamesByEmulator ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarPath': avatarPath,
        'isPrivate': isPrivate,
        'pinHash': pinHash,
        'emulatorIds': emulatorIds,
        'gamePaths': gamePaths,
        'gamesByEmulator': gamesByEmulator,
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        avatarPath: j['avatarPath'] as String?,
        isPrivate: j['isPrivate'] as bool? ?? false,
        pinHash: j['pinHash'] as String?,
        emulatorIds: (j['emulatorIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        gamePaths: (j['gamePaths'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        gamesByEmulator: (j['gamesByEmulator'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k,
                    (v as List<dynamic>).map((e) => e as String).toList())) ??
            {},
      );

  @override
  String toString() {
    return 'Profile(id: $id, name: $name, private: $isPrivate, emus: ${emulatorIds.length}, games: ${gamePaths.length})';
  }
}
