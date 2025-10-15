import 'dart:io';
import 'dart:convert';

class ResolvedShortcut {
  final String targetPath;
  final String arguments;
  final String workingDirectory;
  ResolvedShortcut(
      {required this.targetPath,
      required this.arguments,
      required this.workingDirectory});
}

class EmulatorHelper {
  /// Mapa ampliado de emuladores -> extensiones de ROM típicas (todas en minúsculas).
  static final Map<String, List<String>> emulatorExts = {
    "nes": [".nes"],
    "fceux": [".nes"],
    "nestopia": [".nes"],
    "mesen": [".nes"],
    "snes": [".sfc", ".smc"],
    "snes9x": [".sfc", ".smc"],
    "bsnes": [".sfc", ".smc"],
    "n64": [".z64", ".n64", ".v64"],
    "project64": [".z64", ".n64", ".v64"],
    "mupen": [".z64", ".n64", ".v64"],
    "mupen64plus": [".z64", ".n64", ".v64"],
    "dolphin": [".iso", ".gcm", ".wbfs", ".ciso", ".gcz", ".rvz", ".wad"],
    "gamecube": [".iso", ".gcm", ".wbfs"],
    "cemu": [".rpx", ".wud", ".wux"],
    "yuzu": [".xci", ".nsp", ".nca", ".xcz"],
    "ryujinx": [".xci", ".nsp", ".nca"],
    "citron": [".xci", ".nsp"],
    "eden": [".xci", ".nsp"],
    "mgba": [".gba", ".gb", ".gbc"],
    "visualboyadvance": [".gba"],
    "vba": [".gba"],
    "gambatte": [".gb", ".gbc"],
    "bgb": [".gb", ".gbc"],
    "gba": [".gba"],
    "vba-m": [".gba"],
    "nds": [".nds"],
    "desmume": [".nds"],
    "melonds": [".nds"],
    "3ds": [".3ds", ".cia", ".cxi"],
    "citra": [".3ds", ".cia"],
    "ps1": [".bin", ".cue", ".iso", ".img", ".pbp"],
    "epsxe": [".bin", ".cue", ".iso"],
    "duckstation": [".bin", ".cue", ".iso", ".img"],
    "ps2": [".iso", ".bin", ".img"],
    "pcsx2": [".iso", ".bin", ".img"],
    "ps3": [".iso", ".pkg"],
    "rpcs3": [".iso", ".pkg"],
    "psp": [".iso", ".cso"],
    "ppsspp": [".iso", ".cso"],
    "vita": [".vpk", ".pkg"],
    "vita3k": [".vpk", ".pkg"],
    "xbox": [".iso", ".xiso"],
    "cxbx": [".iso", ".xiso"],
    "xemu": [".iso", ".xiso"],
    "xenia": [".iso", ".xex"],
    "master": [".sms"],
    "gamegear": [".gg"],
    "kegafusion": [".sms", ".gg", ".bin", ".md", ".gen"],
    "gens": [".bin", ".smd", ".md", ".gen"],
    "blastem": [".bin", ".smd", ".md"],
    "saturn": [".cue", ".bin", ".iso"],
    "yabause": [".cue", ".bin", ".iso"],
    "mednafen": [".bin", ".iso", ".cue", ".chd"],
    "dreamcast": [".cdi", ".gdi", ".chd"],
    "redream": [".cdi", ".gdi", ".chd"],
    "flycast": [".cdi", ".gdi", ".chd"],
    "2600": [".bin", ".a26"],
    "stella": [".bin", ".a26"],
    "5200": [".a52"],
    "7800": [".a78"],
    "virtualjaguar": [".j64", ".jag"],
    "handy": [".lnx"],
    "neogeo-pocket": [".ngp", ".ngc"],
    "neogeo": [".zip"],
    "wonderswan": [".ws", ".wsc"],
    "mame": [".zip"],
    "finalburn": [".zip"],
    "fbneo": [".zip"],
    "dosbox": [".exe", ".bat", ".com"],
    "pc": [".exe"], // <- tarjeta PC (ejecutables nativos)
    "generic": [
      ".iso",
      ".bin",
      ".img",
      ".cso",
      ".cue",
      ".pkg",
      ".rpx",
      ".wud",
      ".xci",
      ".nsp",
      ".gba",
      ".nds",
      ".3ds",
      ".nes",
      ".sfc",
      ".smc",
      ".zip"
    ],
  };

  static String cleanGameName(String path) {
    String name = path.split(Platform.pathSeparator).last;
    name = name.replaceAll(RegExp(r'[_\-]'), ' ');
    name = name.replaceAll(RegExp(r'\.[^\.]+$'), '');
    return name.trim();
  }

  static String getEmulatorIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains("cemu")) return "assets/icons/wiiu.png";
    if (n.contains("dolphin") || n.contains("gamecube")) {
      return "assets/icons/wii.png";
    }
    if (n.contains("pcsx2") || n.contains("ps2")) return "assets/icons/ps2.png";
    if (n.contains("ppsspp") || n.contains("psp")) {
      return "assets/icons/psp.png";
    }
    if (n.contains("epsxe") ||
        n.contains("epsx") ||
        n.contains("ps1") ||
        n.contains("duck")) {
      return "assets/icons/ps1.png";
    }
    if (n.contains("rpcs3") || n.contains("ps3")) return "assets/icons/ps3.png";
    if (n.contains("yuzu") ||
        n.contains("ryujinx") ||
        n.contains("citron") ||
        n.contains("eden")) {
      return "assets/icons/switch.png";
    }
    if (n.contains("citra") || n.contains("3ds")) return "assets/icons/3ds.png";
    if (n.contains("mgba") ||
        n.contains("gambatte") ||
        n.contains("bgb") ||
        n.contains("gba") ||
        n.contains("vba")) {
      return "assets/icons/gb.png";
    }
    if (n.contains("nes") ||
        n.contains("fceux") ||
        n.contains("nestopia") ||
        n.contains("mesen")) {
      return "assets/icons/nes.png";
    }
    if (n.contains("snes") || n.contains("snes9x") || n.contains("bsnes")) {
      return "assets/icons/snes.png";
    }
    if (n.contains("n64") || n.contains("project64") || n.contains("mupen")) {
      return "assets/icons/n64.png";
    }
    if (n.contains("xbox") ||
        n.contains("xemu") ||
        n.contains("xenia") ||
        n.contains("cxbx")) {
      return "assets/icons/xbox.png";
    }
    if (n.contains("dreamcast") ||
        n.contains("redream") ||
        n.contains("flycast") ||
        n.contains("nulldc")) {
      return "assets/icons/dreamcast.png";
    }
    if (n.contains("mame") || n.contains("fbneo") || n.contains("finalburn")) {
      return "assets/icons/arcade.png";
    }
    if (n.contains("dosbox") ||
        n.contains("pcem") ||
        n.contains("86box") ||
        n.contains("pc")) {
      return "assets/icons/pc.png";
    }
    if (n.contains("amiga") || n.contains("winuae")) {
      return "assets/icons/amiga.png";
    }
    // fallback
    return "assets/icons/default.png";
  }

  static String getEmulatorBackground(String name) {
    final n = name.toLowerCase();
    if (n.contains("cemu")) return 'assets/images/wiiu.jpg';
    if (n.contains("dolphin") || n.contains("gamecube")) {
      return 'assets/images/wii.jpg';
    }
    if (n.contains("pcsx2") || n.contains("ps2")) {
      return 'assets/images/ps2.jpg';
    }
    if (n.contains("ppsspp") || n.contains("psp")) {
      return 'assets/images/psp.jpg';
    }
    if (n.contains("rpcs3") || n.contains("ps3")) {
      return 'assets/images/ps3.jpg';
    }
    if (n.contains("epsxe") || n.contains("ps1") || n.contains("duck")) {
      return 'assets/images/ps1.jpg';
    }
    if (n.contains("yuzu") ||
        n.contains("ryujinx") ||
        n.contains("citron") ||
        n.contains("eden")) {
      return 'assets/images/switch.jpg';
    }
    if (n.contains("citra") || n.contains("3ds")) {
      return 'assets/images/3ds.jpg';
    }
    if (n.contains("nes") ||
        n.contains("fceux") ||
        n.contains("nestopia") ||
        n.contains("mesen")) {
      return 'assets/images/nes.jpg';
    }
    if (n.contains("snes") || n.contains("snes9x") || n.contains("bsnes")) {
      return 'assets/images/snes.jpg';
    }
    if (n.contains("n64") || n.contains("project64") || n.contains("mupen")) {
      return 'assets/images/n64.jpg';
    }
    if (n.contains("mame") || n.contains("fbneo") || n.contains("finalburn")) {
      return 'assets/images/arcade.jpg';
    }
    if (n.contains("dosbox") ||
        n.contains("pc") ||
        n.contains("pcem") ||
        n.contains("86box")) {
      return 'assets/images/pc.jpg';
    }
    if (n.contains("dosbox") || n.contains("pcem") || n.contains("86box")) {
      return 'assets/images/pc.jpg';
    }
    if (n.contains("dosbox") || n.contains("pc")) {
      return 'assets/images/pc.jpg';
    }
    if (n.contains("dosbox") || n.contains("pcem")) {
      return 'assets/images/pc.jpg';
    }
    // fallback
    return 'assets/images/principal.jpg';
  }

  /// Resultado de resolver un acceso directo (.lnk) en Windows.
  /// target: ruta al ejecutable real
  /// arguments: argumentos del acceso directo (cadena)
  /// workingDirectory: directorio de trabajo sugerido
  /// Retorna null si no pudo resolverse o no está en Windows.
  static Future<ResolvedShortcut?> resolveWindowsShortcut(
      String lnkPath) async {
    if (!Platform.isWindows) return null;
    try {
      // Escapar comillas simples en la ruta
      final safe = lnkPath.replaceAll("'", "''");
      // Construir el comando PowerShell de forma segura usando comillas dobles
      // y escapando comillas dobles dentro de la ruta si las hay.
      final escapedSafe = safe.replaceAll('"', '""');
      final psTemplate =
          r'$sc=(New-Object -ComObject WScript.Shell).CreateShortcut("{SAFE}"); $obj=@{TargetPath=$sc.TargetPath; Arguments=$sc.Arguments; WorkingDirectory=$sc.WorkingDirectory}; $obj|ConvertTo-Json -Compress';
      final ps = psTemplate.replaceAll('{SAFE}', escapedSafe);

      final proc = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', ps],
      );
      if (proc.exitCode != 0) return null;
      final out = proc.stdout?.toString() ?? '';
      if (out.trim().isEmpty) return null;
      final Map<String, dynamic> map = json.decode(out);
      final target = (map['TargetPath'] as String?)?.trim();
      final args = (map['Arguments'] as String?)?.trim() ?? '';
      final wd = (map['WorkingDirectory'] as String?)?.trim() ?? '';
      if (target == null || target.isEmpty) return null;
      return ResolvedShortcut(
          targetPath: target, arguments: args, workingDirectory: wd);
    } catch (e) {
      try {
        // silencioso
      } catch (_) {}
      return null;
    }
  }

  /// Divide una cadena de argumentos en tokens respetando comillas.
  static List<String> splitArgsRespectingQuotes(String src) {
    final List<String> out = [];
    StringBuffer cur = StringBuffer();
    String? quote; // ' or " when inside quotes
    bool escape = false;
    for (int i = 0; i < src.length; i++) {
      final ch = src[i];
      if (escape) {
        cur.write(ch);
        escape = false;
        continue;
      }
      if (ch == '\\') {
        escape = true;
        continue;
      }
      if (quote != null) {
        if (ch == quote) {
          // close quote
          quote = null;
        } else {
          cur.write(ch);
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch.trim().isEmpty) {
        if (cur.isNotEmpty) {
          out.add(cur.toString());
          cur = StringBuffer();
        }
        continue;
      }
      cur.write(ch);
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out;
  }

  /// Construye argumentos de lanzamiento para un juego según el emulador.
  /// Añade la ruta del juego y los flags de pantalla completa conocidos.
  static List<String> buildLaunchArgsForGame({
    required String emulatorName,
    required String gamePath,
    required bool fullscreen,
    List<String>? extraArgs,
  }) {
    final n = emulatorName.toLowerCase();
    final args = <String>[];

    // Cemu: -g <game>  y -f para fullscreen (comúnmente usado en shortcuts).
    if (n.contains('cemu')) {
      args.addAll(['-g', gamePath]);
      if (fullscreen) args.add('-f');
      if (extraArgs != null) args.addAll(extraArgs);
      return args;
    }

    // PPSSPP: --fullscreen (y ruta del juego)
    if (n.contains('ppsspp')) {
      if (fullscreen) args.addAll(['--fullscreen']);
      args.add(gamePath);
      if (extraArgs != null) args.addAll(extraArgs);
      return args;
    }

    // PCSX2: -fullscreen (algunos builds) y ruta
    if (n.contains('pcsx2') || n.contains('ps2')) {
      if (fullscreen) args.add('-fullscreen');
      args.add(gamePath);
      if (extraArgs != null) args.addAll(extraArgs);
      return args;
    }

    // Dolphin / GameCube: usar --config para forzar fullscreen y -e/--exec para ejecutar la ISO
    if (n.contains('dolphin') || n.contains('gamecube')) {
      if (fullscreen) {
        // --config acepta System.Section.Key=Value
        args.addAll(['--config=Dolphin.Display.Fullscreen=True']);
      }
      // -e o --exec se usa para ejecutar la imagen directamente
      args.addAll(['-e', gamePath]);
      if (extraArgs != null) args.addAll(extraArgs);
      return args;
    }

    // Para "pc" (tarjeta manual) devolvemos vacío: el launcher ejecutará el .exe directamente.
    if (n.contains('pc')) {
      if (extraArgs != null) args.addAll(extraArgs);
      return args;
    }

    // DuckStation / epsxe / others: por defecto pasar la ruta
    args.add(gamePath);
    if (extraArgs != null) args.addAll(extraArgs);

    // Nota: para emuladores sin flag conocido, permitimos que el usuario
    // añada el flag necesario en EmulatorData.launchArgs (extraArgs).
    return args;
  }
}
