class GameData {
  String path;
  String displayName;
  String? coverUrl; // mutable ahora

  GameData({
    required this.path,
    required this.displayName,
    this.coverUrl,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'displayName': displayName,
        'coverUrl': coverUrl,
      };

  factory GameData.fromJson(Map<String, dynamic> json) => GameData(
        path: json['path'] as String,
        displayName: json['displayName'] as String,
        coverUrl: json['coverUrl'] as String?,
      );
}

class EmulatorData {
  final String name;
  final String exePath;
  final List<String> supportedExts;

  String? coverPath; // imagen de portada para la tarjeta (nullable)

  String? gamesPath; // 📂 Carpeta de juegos (nullable)
  List<GameData> games;
  bool launchFullscreen; // nueva opción

  // NUEVOS: argumentos extra por emulador y working directory opcional
  List<String> launchArgs;
  String? workingDirectory;

  // NUEVO: marca si esta tarjeta **no debe escanear** y los juegos se añaden manualmente
  final bool manualAddsOnly;

  EmulatorData({
    required this.name,
    required this.exePath,
    required this.supportedExts,
    this.coverPath,
    this.gamesPath,
    List<GameData>? games,
    this.launchFullscreen =
        true, // por defecto true: intentar pantalla completa
    List<String>? launchArgs,
    this.workingDirectory,
    this.manualAddsOnly = false,
  })  : games = games ?? [],
        launchArgs = launchArgs ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'exePath': exePath,
        'supportedExts': supportedExts,
        'coverPath': coverPath,
        'gamesPath': gamesPath,
        'games': games.map((g) => g.toJson()).toList(),
        'launchFullscreen': launchFullscreen,
        'launchArgs': launchArgs,
        'workingDirectory': workingDirectory,
        'manualAddsOnly': manualAddsOnly,
      };

  factory EmulatorData.fromJson(Map<String, dynamic> json) => EmulatorData(
        name: json['name'] as String,
        exePath: json['exePath'] as String,
        supportedExts: (json['supportedExts'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
        coverPath: json['coverPath'] as String?,
        gamesPath: json['gamesPath'] as String?,
        games: (json['games'] as List<dynamic>?)
                ?.map((g) => GameData.fromJson(g as Map<String, dynamic>))
                .toList() ??
            [],
        launchFullscreen: json['launchFullscreen'] as bool? ?? true,
        launchArgs: (json['launchArgs'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        workingDirectory: json['workingDirectory'] as String?,
        manualAddsOnly: json['manualAddsOnly'] as bool? ?? false,
      );
}
