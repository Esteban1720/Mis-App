// lib/screens/emuchull_login.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle, RawKeyEvent, RawKeyDownEvent, LogicalKeyboardKey;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dart_vlc/dart_vlc.dart';

import '../models/profile.dart';
import '../services/profile_service.dart';
import '../services/audio_service.dart';
import 'profile_emulator_home.dart';
import '../widgets/onscreen_keyboard.dart';
import '../services/input_service.dart';

typedef VoidCb = void Function();

class EmuChullLoginScreen extends StatefulWidget {
  const EmuChullLoginScreen({super.key});

  @override
  State<EmuChullLoginScreen> createState() => _EmuChullLoginScreenState();
}

class _EmuChullLoginScreenState extends State<EmuChullLoginScreen>
    with WidgetsBindingObserver {
  final ProfileService _svc = ProfileService.instance;
  List<Profile> _profiles = [];
  bool _loading = true;

  int _selectedIndex = 0;
  int _focusSection = 0;
  int? _deleteFocusedIndex;

  final Color bg = const Color(0xFF0F1113);
  final ScrollController _scrollController = ScrollController();

  VoidCb? _removeInputListener;
  final Set<int> _hovered = {};

  // removed unused _isFullscreen
  final FocusNode _keyboardFocus = FocusNode();

  bool get _isPowerFocused => _focusSection == 1;

  // Player libVLC
  Player? _vlcPlayer;
  bool _videoInitialized = false;
  bool _videoInitStarted = false;
  // Flags to temporarily disable platform-heavy plugins while debugging
  static const bool _enableBackgroundVideo = true;
  static const bool _enableAudio =
      true; // habilitado para reproducir SFX de navegación

  // Carga perfiles
  Future<void> _loadProfiles() async {
    _profiles = await _svc.loadProfiles();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfiles();
    try {
      InputService.instance.initialize();
    } catch (_) {}

    // Inicializar controller de vídeo tras primer frame (más seguro)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _keyboardFocus.requestFocus();
      } catch (_) {}
      if (_enableBackgroundVideo) _initBackgroundVideo();
    });

    // Listener global de entrada (gamepad/teclado)
    _removeInputListener = InputService.instance.pushListener(
      InputListener(
        onLeft: () {
          if (_focusSection == 0) _changeSelected(_selectedIndex - 1);
        },
        onRight: () {
          if (_focusSection == 0) _changeSelected(_selectedIndex + 1);
        },
        onUp: () {
          if (_focusSection == 1) _setFocusSection(0);
        },
        onDown: () {
          if (_focusSection == 0) _setFocusSection(1);
        },
        onTriangle: () {
          if (_focusSection == 0 && _selectedIndex > 0) {
            setState(() {
              _deleteFocusedIndex =
                  _deleteFocusedIndex == _selectedIndex ? null : _selectedIndex;
            });
            _maybePlayAction();
          }
        },
        onActivate: _handleActivate,
        onBack: () => Navigator.of(context).maybePop(),
        onToggleFullscreen: () async {
          try {
            await InputService.instance.toggleFullscreen();
          } catch (_) {}
        },
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keyboardFocus.hasFocus) {
        try {
          _keyboardFocus.requestFocus();
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    try {
      _removeInputListener?.call();
    } catch (_) {}
    try {
      _keyboardFocus.dispose();
    } catch (_) {}
    _scrollController.dispose();

    if (_enableBackgroundVideo) {
      try {
        _vlcPlayer?.dispose();
      } catch (_) {}
    }

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _maybePlayAction() {
    if (!_enableAudio) return;
    try {
      AudioService.instance.playAction();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      if (!_videoInitialized) return;
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        try {
          _vlcPlayer?.pause();
        } catch (_) {}
      } else if (state == AppLifecycleState.resumed) {
        try {
          _vlcPlayer?.play();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _initBackgroundVideo() async {
    if (_videoInitStarted) return;
    _videoInitStarted = true;

    try {
      // Crear Player si no existe
      _vlcPlayer ??= Player(id: 0);

      // Copiar asset MP4 a un archivo temporal accesible por libVLC
      String? tmpPath;
      try {
        final data = await rootBundle.load('assets/videos/login.mp4');
        final bytes = data.buffer.asUint8List();
        final dir = await getApplicationDocumentsDirectory();
        final file =
            File('${dir.path}${Platform.pathSeparator}emuchull_login_bg.mp4');
        await file.writeAsBytes(bytes, flush: true);
        tmpPath = file.path;
        debugPrint('Background video temp path: $tmpPath');
      } catch (e) {
        debugPrint('Failed to copy asset to temp file: $e');
        tmpPath = null;
      }

      if (tmpPath == null) {
        if (mounted) setState(() => _videoInitialized = false);
        return;
      }

      // Abrir con libVLC: NO await y NO asignar el resultado (open puede devolver void)
      try {
        _vlcPlayer!.open(Media.file(File(tmpPath)));
      } catch (e) {
        debugPrint('Warning: Player.open falló: $e');
      }

      // Forzar play (también sin await)
      try {
        _vlcPlayer!.play();
      } catch (e) {
        debugPrint('Warning: _vlcPlayer.play() falló: $e');
      }

      // Silenciar background (opcional)
      try {
        _vlcPlayer!.setVolume(0);
      } catch (_) {}

      if (mounted) setState(() => _videoInitialized = true);
    } catch (e, st) {
      debugPrint('VLC bg init error: $e\n$st');
      if (mounted) setState(() => _videoInitialized = false);
    }
  }

  Future<String?> _pickAvatarAndSave(String id) async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res == null || res.files.isEmpty) return null;
      final file = File(res.files.single.path!);
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}${Platform.pathSeparator}avatars_$id.png');
      await file.copy(dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showAddProfile() async {
    // Rebuilt, robust version using a dynamic focusable list and deterministic actions.
    String? avatarPath;
    String? pin;
    bool isPrivate = false;
    final nameCtl = TextEditingController();

    bool dialogOpen = true;
    void Function(void Function())? dialogSetSt;

    Future<void> openNameKeyboard() async {
      final result = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'keyboard',
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (kctx, a1, a2) {
          final mq = MediaQuery.of(kctx);
          final dialogMaxWidth = mq.size.width * 0.95;
          final dialogMaxHeight = mq.size.height * 0.92;
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogMaxWidth,
                  maxHeight: dialogMaxHeight,
                  minWidth: 280,
                ),
                child: OnScreenKeyboard(
                  initialValue: nameCtl.text,
                  title: 'Nombre del perfil',
                  maxLength: 24,
                  isPin: false,
                ),
              ),
            ),
          );
        },
      );
      if (!dialogOpen) return;
      if (result != null) {
        nameCtl.text = result.trim();
        if (dialogSetSt != null) dialogSetSt!(() {});
      }
    }

    Future<void> openPinKeyboard() async {
      final result = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'keyboard_pin',
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (kctx, a1, a2) {
          final mq = MediaQuery.of(kctx);
          final dialogMaxWidth = mq.size.width * 0.95;
          final dialogMaxHeight = mq.size.height * 0.92;
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogMaxWidth,
                  maxHeight: dialogMaxHeight,
                  minWidth: 280,
                ),
                child: OnScreenKeyboard(
                  initialValue: pin ?? '',
                  title: 'Ingrese PIN (4 dígitos)',
                  maxLength: 4,
                  isPin: true,
                ),
              ),
            ),
          );
        },
      );
      if (!dialogOpen) return;
      if (result != null) {
        pin = result.trim();
        if (dialogSetSt != null) dialogSetSt!(() {});
      }
    }

    Future<void> selectAvatar() async {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final path = await _pickAvatarAndSave(id);
      if (!dialogOpen) return;
      if (path != null) {
        avatarPath = path;
        if (dialogSetSt != null) dialogSetSt!(() {});
      }
    }

    Future<void> performCreate() async {
      final name = nameCtl.text.trim();
      if (name.isEmpty) {
        if (!dialogOpen || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El nombre no puede estar vacío')));
        return;
      }
      if (isPrivate) {
        if (pin == null || pin!.length != 4) {
          await openPinKeyboard();
          if (!dialogOpen || !mounted) return;
          if (pin == null || pin!.length != 4) {
            if (!dialogOpen || !mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('El PIN debe tener 4 dígitos')));
            return;
          }
        }
      }
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      String? pinHash;
      if (isPrivate) pinHash = _svc.hashPin(pin!);
      final p = Profile(
        id: id,
        name: name,
        avatarPath: avatarPath,
        isPrivate: isPrivate,
        pinHash: pinHash,
      );
      _profiles.add(p);
      await _svc.saveProfiles(_profiles);
      if (mounted) setState(() {});
      if (!dialogOpen) return;
      if (mounted) Navigator.of(context).pop();
    }

    // Build a dynamic list of focusable actions so indices are deterministic
    List<FocusNode> focusNodes = [];
    VoidCb? removeListener;
    int selected = 0;

    List<String> _buildLabels() {
      final labels = <String>[];
      labels.add('Nombre');
      labels.add('Privado');
      if (isPrivate) labels.add('PIN');
      labels.add('Avatar');
      labels.add('Cancelar');
      labels.add('Crear');
      return labels;
    }

    void _ensureFocusNodes(int count) {
      while (focusNodes.length < count) focusNodes.add(FocusNode());
      while (focusNodes.length > count) {
        final fn = focusNodes.removeLast();
        try {
          fn.dispose();
        } catch (_) {}
      }
    }

    void reapplyFocus() {
      if (!dialogOpen) return;
      final labels = _buildLabels();
      _ensureFocusNodes(labels.length);
      if (selected < 0) selected = 0;
      if (selected >= labels.length) selected = labels.length - 1;
      try {
        focusNodes[selected].requestFocus();
      } catch (_) {}
    }

    void move(int delta) {
      final labels = _buildLabels();
      final len = labels.length;
      int next = (selected + delta) % len;
      if (next < 0) next += len;
      selected = next;
      if (dialogSetSt != null && dialogOpen) {
        dialogSetSt!(() {});
      }
      reapplyFocus();
    }

    removeListener = InputService.instance.pushListener(
      InputListener(
        onLeft: () => move(-1),
        onRight: () => move(1),
        onUp: () => move(-1),
        onDown: () => move(1),
        onActivate: () async {
          if (!dialogOpen) return;
          final labels = _buildLabels();
          final label = labels[selected];
          switch (label) {
            case 'Nombre':
              await openNameKeyboard();
              break;
            case 'Privado':
              // toggle private and rebuild labels/focus nodes
              if (dialogSetSt != null) {
                dialogSetSt!(() {
                  isPrivate = !isPrivate;
                });
              } else {
                isPrivate = !isPrivate;
              }
              if (selected >= _buildLabels().length)
                selected = _buildLabels().length - 1;
              reapplyFocus();
              break;
            case 'PIN':
              await openPinKeyboard();
              break;
            case 'Avatar':
              await selectAvatar();
              break;
            case 'Cancelar':
              try {
                Navigator.of(context).pop();
              } catch (_) {}
              break;
            case 'Crear':
              await performCreate();
              break;
            default:
              break;
          }
        },
        onBack: () {
          try {
            Navigator.of(context).maybePop();
          } catch (_) {}
        },
      ),
    );

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx2, setSt) {
            dialogSetSt = (fn) {
              if (!dialogOpen) return;
              setSt(fn);
            };

            final labels = _buildLabels();
            _ensureFocusNodes(labels.length);
            // ensure selected is within range
            if (selected >= labels.length) selected = labels.length - 1;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              reapplyFocus();
            });

            BoxDecoration itemDecoration(int idx) {
              final highlighted = selected == idx || focusNodes[idx].hasFocus;
              return BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color:
                    highlighted ? const Color(0xFF1E1F21) : Colors.transparent,
                border: highlighted ? Border.all(color: Colors.white24) : null,
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF121316),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nombre
                    FocusableActionDetector(
                      focusNode: focusNodes[0],
                      autofocus: selected == 0,
                      onShowFocusHighlight: (hasFocus) {
                        if (hasFocus && dialogOpen) dialogSetSt?.call(() {});
                      },
                      child: GestureDetector(
                        onTap: () async {
                          selected = 0;
                          reapplyFocus();
                          await openNameKeyboard();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: itemDecoration(0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: nameCtl,
                                  readOnly: true,
                                  decoration: const InputDecoration.collapsed(
                                      hintText: 'Nombre del perfil'),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.keyboard, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Privado
                    FocusableActionDetector(
                      focusNode: focusNodes[1],
                      autofocus: selected == 1,
                      onShowFocusHighlight: (hasFocus) {
                        if (hasFocus && dialogOpen) dialogSetSt?.call(() {});
                      },
                      child: GestureDetector(
                        onTap: () {
                          selected = 1;
                          reapplyFocus();
                          if (dialogSetSt != null)
                            dialogSetSt!(() => isPrivate = !isPrivate);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: itemDecoration(1),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Privado (PIN de 4 dígitos)',
                                  style: TextStyle(color: Colors.white)),
                              Switch(
                                  value: isPrivate,
                                  onChanged: (v) {
                                    if (!dialogOpen) return;
                                    if (dialogSetSt != null)
                                      dialogSetSt!(() => isPrivate = v);
                                    reapplyFocus();
                                  })
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isPrivate)
                      FocusableActionDetector(
                        focusNode: focusNodes[2],
                        autofocus: selected == 2,
                        onShowFocusHighlight: (hasFocus) {
                          if (hasFocus && dialogOpen) dialogSetSt?.call(() {});
                        },
                        child: GestureDetector(
                          onTap: () async {
                            selected = 2;
                            reapplyFocus();
                            await openPinKeyboard();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: itemDecoration(2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    pin != null && pin!.isNotEmpty
                                        ? 'PIN: ****'
                                        : 'PIN (4 dígitos)',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.lock, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    // Avatar
                    FocusableActionDetector(
                      focusNode: focusNodes[isPrivate ? 3 : 2],
                      autofocus: selected == (isPrivate ? 3 : 2),
                      onShowFocusHighlight: (hasFocus) {
                        if (hasFocus && dialogOpen) dialogSetSt?.call(() {});
                      },
                      child: GestureDetector(
                        onTap: () async {
                          selected = isPrivate ? 3 : 2;
                          reapplyFocus();
                          await selectAvatar();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: itemDecoration(isPrivate ? 3 : 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  avatarPath != null
                                      ? 'Avatar seleccionado'
                                      : 'Seleccionar avatar',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.photo, color: Colors.white70),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                // Cancel
                FocusableActionDetector(
                  focusNode: focusNodes[isPrivate ? 4 : 3],
                  autofocus: selected == (isPrivate ? 4 : 3),
                  onShowFocusHighlight: (hasFocus) {
                    if (hasFocus && dialogOpen) dialogSetSt?.call(() {});
                  },
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: (selected == (isPrivate ? 4 : 3))
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white24))
                          : null,
                      child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancelar')),
                    ),
                  ),
                ),
                // Create
                FocusableActionDetector(
                  focusNode: focusNodes[isPrivate ? 5 : 4],
                  autofocus: selected == (isPrivate ? 5 : 4),
                  onShowFocusHighlight: (hasFocus) {
                    if (hasFocus && dialogOpen) dialogSetSt?.call(() {});
                  },
                  child: GestureDetector(
                    onTap: () async {
                      selected = isPrivate ? 5 : 4;
                      reapplyFocus();
                      await performCreate();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: (selected == (isPrivate ? 5 : 4))
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white24))
                          : null,
                      child: ElevatedButton(
                          onPressed: performCreate,
                          child: const Text('Crear perfil')),
                    ),
                  ),
                ),
              ],
            );
          });
        },
      );
    } finally {
      try {
        removeListener.call();
      } catch (_) {}
      dialogOpen = false;
      dialogSetSt = null;

      try {
        nameCtl.dispose();
      } catch (_) {}

      for (final fn in focusNodes) {
        try {
          fn.unfocus();
        } catch (_) {}
        try {
          fn.dispose();
        } catch (_) {}
      }
      // NO dispose del vlc player aquí: queremos que el fondo continúe.
    }
  }

  Future<bool> _askForPinAndVerify(Profile p) async {
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'keyboard',
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, a1, a2) {
        final mq = MediaQuery.of(ctx);
        final dialogMaxWidth = mq.size.width * 0.95;
        final dialogMaxHeight = mq.size.height * 0.92;
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: dialogMaxWidth,
                  maxHeight: dialogMaxHeight,
                  minWidth: 280),
              child: OnScreenKeyboard(
                  initialValue: '',
                  title: 'Ingresa PIN',
                  maxLength: 4,
                  isPin: true),
            ),
          ),
        );
      },
    );
    if (result == null) return false;
    final pinInput = result.trim();
    if (pinInput.length != 4) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El PIN debe tener 4 dígitos')));
      }
      return false;
    }
    final hash = _svc.hashPin(pinInput);
    final ok = hash == p.pinHash;
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('PIN incorrecto')));
      }
    }
    return ok;
  }

  Future<void> _onSelectProfile(Profile p) async {
    // Only ask for PIN if the profile is marked as private.
    if (p.isPrivate) {
      final ok = await _askForPinAndVerify(p);
      if (!ok) return;
    }
    if (!mounted) return;
    ProfileService.instance.setCurrentProfile(p);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ProfileEmulatorHomeScreen(profile: p)));
    try {
      AudioService.instance.playAction();
    } catch (_) {}
  }

  int get _maxIndex => _profiles.length;

  void _changeSelected(int newIndex) {
    final max = _maxIndex;
    if (newIndex < 0) newIndex = 0;
    if (newIndex > max) newIndex = max;
    if (newIndex == _selectedIndex) return;
    setState(() {
      _selectedIndex = newIndex;
      _deleteFocusedIndex = null;
    });
    const defaultItemExtent = 140.0;
    final itemExtent = defaultItemExtent;
    final target = newIndex * itemExtent;
    try {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    } catch (_) {}
    try {
      AudioService.instance.playNav();
    } catch (_) {}
  }

  void _setFocusSection(int s) {
    if (_focusSection == s) return;
    setState(() {
      _focusSection = s;
      if (_focusSection != 0) _deleteFocusedIndex = null;
    });
    try {
      AudioService.instance.playNav();
    } catch (_) {}
  }

  Future<void> _handleActivate() async {
    if (_focusSection == 0) {
      if (_selectedIndex > 0 && _deleteFocusedIndex == _selectedIndex) {
        final profile = _profiles[_selectedIndex - 1];
        await _confirmDeleteProfile(profile);
        setState(() {
          _deleteFocusedIndex = null;
          if (_selectedIndex > _profiles.length) {
            _selectedIndex = _profiles.length;
          }
        });
      } else {
        if (_selectedIndex == 0) {
          await _showAddProfile();
        } else {
          final profile = _profiles[_selectedIndex - 1];
          await _onSelectProfile(profile);
        }
      }
    } else if (_focusSection == 1) {
      _maybePlayAction();
      exit(0);
    }
  }

  Future<void> _confirmDeleteProfile(Profile p) async {
    VoidCb? removeListener;
    int selected = 0;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSt) {
          removeListener ??= InputService.instance.pushListener(
            InputListener(
              onLeft: () {
                try {
                  setSt(() {
                    selected = 0;
                  });
                } catch (_) {}
              },
              onRight: () {
                try {
                  setSt(() {
                    selected = 1;
                  });
                } catch (_) {}
              },
              onActivate: () {
                try {
                  Navigator.of(ctx2).pop(selected == 1);
                } catch (_) {}
              },
              onBack: () {
                try {
                  Navigator.of(ctx2).pop(false);
                } catch (_) {}
              },
            ),
          );

          final cancelDecoration = selected == 0
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                )
              : null;

          final deleteDecoration = selected == 1
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                )
              : null;

          return AlertDialog(
            backgroundColor: const Color(0xFF121316),
            title: const Text('Eliminar perfil'),
            content: Text(
                '¿Eliminar el perfil "${p.name}"? Esta acción no se puede deshacer.'),
            actions: [
              GestureDetector(
                onTap: () => Navigator.of(ctx2).pop(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: cancelDecoration,
                  child: TextButton(
                      onPressed: () => Navigator.of(ctx2).pop(false),
                      child: Text('Cancelar',
                          style: TextStyle(
                              color: selected == 0
                                  ? Colors.white
                                  : Colors.white70))),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(ctx2).pop(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: deleteDecoration,
                  child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx2).pop(true),
                      child: const Text('Eliminar')),
                ),
              ),
            ],
          );
        });
      },
    );

    try {
      removeListener?.call();
    } catch (_) {}

    if (confirmed != true) return;

    _profiles.removeWhere((x) => x.id == p.id);
    await _svc.saveProfiles(_profiles);

    setState(() {
      _deleteFocusedIndex = null;
      if (_selectedIndex > _profiles.length) {
        _selectedIndex = _profiles.length;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _keyboardFocus,
      onKey: (RawKeyEvent ev) {
        if (ev is RawKeyDownEvent) {
          final k = ev.logicalKey;
          if (k == LogicalKeyboardKey.f11) {
            try {
              InputService.instance.toggleFullscreen();
            } catch (_) {}
            return;
          }
          if (k == LogicalKeyboardKey.arrowLeft) {
            _changeSelected(_selectedIndex - 1);
            return;
          }
          if (k == LogicalKeyboardKey.arrowRight) {
            _changeSelected(_selectedIndex + 1);
            return;
          }
          if (k == LogicalKeyboardKey.arrowUp) {
            _setFocusSection(0);
            return;
          }
          if (k == LogicalKeyboardKey.arrowDown) {
            _setFocusSection(1);
            return;
          }
          if (k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter ||
              k == LogicalKeyboardKey.space) {
            _handleActivate();
            return;
          }
          if (k == LogicalKeyboardKey.escape ||
              k == LogicalKeyboardKey.backspace) {
            Navigator.of(context).maybePop();
            return;
          }
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // Fondo de video usando dart_vlc
                  Positioned.fill(
                    child: (_videoInitialized && _vlcPlayer != null)
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              return ClipRect(
                                child: SizedBox.expand(
                                  child: FittedBox(
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                      child: Video(player: _vlcPlayer!),
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(color: bg),
                  ),

                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                    ),
                  ),

                  // ... el resto de tu UI (encabezado, tarjetas, power button) permanece igual
                  Column(
                    children: [
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: 80, left: 18, right: 18, bottom: 12),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      height: 61,
                                      width: 56,
                                      child: const Center(
                                        child: Icon(Icons.videogame_asset,
                                            size: 68, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    const Text(
                                      'EMUCHULL',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Selecciona tu perfil',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ... (aquí continua exactamente tu layout de perfiles y power button)
                      Expanded(
                        child: Center(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final totalCards = _profiles.length + 1;
                              final maxWidth = constraints.maxWidth;
                              final desiredPerRow = math.min(totalCards, 6);
                              final gap = 28.0;
                              final computedWidth =
                                  (maxWidth - gap * (desiredPerRow + 1)) /
                                      desiredPerRow;
                              final cardWidth =
                                  computedWidth.clamp(120.0, 220.0);
                              final cardGap = gap;
                              final neededWidth = totalCards * cardWidth +
                                  (totalCards - 1) * cardGap;

                              bool cardIsSelected(int index) =>
                                  _focusSection == 0 && _selectedIndex == index;

                              if (neededWidth <= maxWidth) {
                                return Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children:
                                        List.generate(totalCards, (index) {
                                      final isAdd = index == 0;
                                      final hovered = _hovered.contains(index);
                                      final selected = cardIsSelected(index);
                                      final deleteFocused =
                                          (_deleteFocusedIndex == index);

                                      Widget inner;
                                      if (isAdd) {
                                        inner = Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: const [
                                            Icon(Icons.add,
                                                size: 38, color: Colors.white),
                                            SizedBox(height: 10),
                                            Text('Crear perfil',
                                                style: TextStyle(
                                                    color: Colors.white))
                                          ],
                                        );
                                      } else {
                                        final p = _profiles[index - 1];
                                        inner = Stack(
                                          children: [
                                            Positioned.fill(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                child: p.avatarPath != null
                                                    ? Image.file(
                                                        File(p.avatarPath!),
                                                        fit: BoxFit.cover)
                                                    : Container(
                                                        color: const Color(
                                                            0xFF1E1F21),
                                                        child: const Center(
                                                          child: Icon(
                                                              Icons.person,
                                                              size: 48,
                                                              color: Colors
                                                                  .white70),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                        horizontal: 6),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.transparent,
                                                      Colors.black
                                                          .withOpacity(0.5)
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                          bottomLeft:
                                                              Radius.circular(
                                                                  24),
                                                          bottomRight:
                                                              Radius.circular(
                                                                  24)),
                                                ),
                                                child: Center(
                                                  child: Text(p.name,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }

                                      return Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: cardGap / 2),
                                        child: MouseRegion(
                                          onEnter: (_) {
                                            if (_focusSection != 0) {
                                              _setFocusSection(0);
                                            }
                                            setState(() => _hovered.add(index));
                                            setState(() {
                                              _selectedIndex = index;
                                              _deleteFocusedIndex = null;
                                            });
                                          },
                                          onExit: (_) => setState(
                                              () => _hovered.remove(index)),
                                          child: GestureDetector(
                                            onTap: () async {
                                              _setFocusSection(0);
                                              _changeSelected(index);
                                              if (isAdd) {
                                                await _showAddProfile();
                                              } else {
                                                await _onSelectProfile(
                                                    _profiles[index - 1]);
                                              }
                                            },
                                            onLongPress: () {
                                              if (!isAdd) {
                                                _confirmDeleteProfile(
                                                    _profiles[index - 1]);
                                              }
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 180),
                                              curve: Curves.easeOut,
                                              width: cardWidth,
                                              height: 180,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                color: selected
                                                    ? const Color(0xFF1E1F21)
                                                        .withOpacity(0.18)
                                                    : Colors.transparent,
                                                border: selected
                                                    ? Border.all(
                                                        color: Colors.white24)
                                                    : null,
                                                boxShadow: (hovered &&
                                                            _focusSection ==
                                                                0) ||
                                                        selected
                                                    ? [
                                                        BoxShadow(
                                                            color: Colors.white
                                                                .withOpacity(
                                                                    0.12),
                                                            blurRadius: hovered
                                                                ? 20
                                                                : 10,
                                                            spreadRadius:
                                                                hovered
                                                                    ? 2
                                                                    : 0.5)
                                                      ]
                                                    : null,
                                              ),
                                              padding: const EdgeInsets.all(0),
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                      child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(24),
                                                          child: inner)),
                                                  if (!isAdd)
                                                    Positioned(
                                                      right: 8,
                                                      top: 8,
                                                      child: GestureDetector(
                                                        onTap: () {
                                                          _confirmDeleteProfile(
                                                              _profiles[
                                                                  index - 1]);
                                                        },
                                                        child:
                                                            AnimatedContainer(
                                                          duration:
                                                              const Duration(
                                                                  milliseconds:
                                                                      120),
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(6),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: deleteFocused
                                                                ? Colors
                                                                    .redAccent
                                                                    .withOpacity(
                                                                        0.2)
                                                                : const Color(
                                                                    0xFF2A2B2D),
                                                            shape:
                                                                BoxShape.circle,
                                                            border: deleteFocused
                                                                ? Border.all(
                                                                    color: Colors
                                                                        .redAccent,
                                                                    width: 2)
                                                                : Border.all(
                                                                    color: Colors
                                                                        .white24),
                                                          ),
                                                          child: Icon(
                                                              Icons.delete,
                                                              size: 18,
                                                              color: deleteFocused
                                                                  ? Colors
                                                                      .redAccent
                                                                  : Colors
                                                                      .white70),
                                                        ),
                                                      ),
                                                    )
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                );
                              }

                              // Si no cabe, renderizar una lista horizontal
                              return SizedBox(
                                height: 220,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  scrollDirection: Axis.horizontal,
                                  itemCount: totalCards,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  itemBuilder: (ctx, index) {
                                    final isAdd = index == 0;
                                    final hovered = _hovered.contains(index);
                                    final selected = (_focusSection == 0 &&
                                        _selectedIndex == index);
                                    final deleteFocused =
                                        (_deleteFocusedIndex == index);

                                    Widget inner;
                                    if (isAdd) {
                                      inner = Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.add,
                                              size: 38, color: Colors.white),
                                          SizedBox(height: 10),
                                          Text('Crear perfil',
                                              style: TextStyle(
                                                  color: Colors.white))
                                        ],
                                      );
                                    } else {
                                      final p = _profiles[index - 1];
                                      inner = Stack(
                                        children: [
                                          Positioned.fill(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              child: p.avatarPath != null
                                                  ? Image.file(
                                                      File(p.avatarPath!),
                                                      fit: BoxFit.cover)
                                                  : Container(
                                                      color: const Color(
                                                          0xFF1E1F21),
                                                      child: const Center(
                                                        child: Icon(
                                                            Icons.person,
                                                            size: 48,
                                                            color:
                                                                Colors.white70),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                      horizontal: 6),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.transparent,
                                                      Colors.black
                                                          .withOpacity(0.5)
                                                    ]),
                                                borderRadius:
                                                    const BorderRadius.only(
                                                        bottomLeft:
                                                            Radius.circular(24),
                                                        bottomRight:
                                                            Radius.circular(
                                                                24)),
                                              ),
                                              child: Center(
                                                child: Text(p.name,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
                                      child: MouseRegion(
                                        onEnter: (_) {
                                          if (_focusSection != 0) {
                                            _setFocusSection(0);
                                          }
                                          setState(() => _hovered.add(index));
                                          setState(() {
                                            _selectedIndex = index;
                                            _deleteFocusedIndex = null;
                                          });
                                        },
                                        onExit: (_) => setState(
                                            () => _hovered.remove(index)),
                                        child: GestureDetector(
                                          onTap: () async {
                                            _setFocusSection(0);
                                            _changeSelected(index);
                                            if (isAdd) {
                                              await _showAddProfile();
                                            } else {
                                              await _onSelectProfile(
                                                  _profiles[index - 1]);
                                            }
                                          },
                                          onLongPress: () {
                                            if (!isAdd) {
                                              _confirmDeleteProfile(
                                                  _profiles[index - 1]);
                                            }
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 180),
                                            curve: Curves.easeOut,
                                            width: cardWidth,
                                            height: 180,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              color: selected
                                                  ? const Color(0xFF1E1F21)
                                                      .withOpacity(0.18)
                                                  : Colors.transparent,
                                              border: selected
                                                  ? Border.all(
                                                      color: Colors.white24)
                                                  : null,
                                              boxShadow: (hovered &&
                                                          _focusSection == 0) ||
                                                      selected
                                                  ? [
                                                      BoxShadow(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.12),
                                                          blurRadius:
                                                              hovered ? 20 : 10,
                                                          spreadRadius:
                                                              hovered ? 2 : 0.5)
                                                    ]
                                                  : null,
                                            ),
                                            padding: const EdgeInsets.all(0),
                                            child: Stack(
                                              children: [
                                                Positioned.fill(
                                                    child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(24),
                                                        child: inner)),
                                                if (!isAdd)
                                                  Positioned(
                                                    right: 8,
                                                    top: 8,
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        _confirmDeleteProfile(
                                                            _profiles[
                                                                index - 1]);
                                                      },
                                                      child: AnimatedContainer(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    120),
                                                        padding:
                                                            const EdgeInsets
                                                                .all(6),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: deleteFocused
                                                              ? Colors.redAccent
                                                                  .withOpacity(
                                                                      0.2)
                                                              : const Color(
                                                                  0xFF2A2B2D),
                                                          shape:
                                                              BoxShape.circle,
                                                          border: deleteFocused
                                                              ? Border.all(
                                                                  color: Colors
                                                                      .redAccent,
                                                                  width: 2)
                                                              : Border.all(
                                                                  color: Colors
                                                                      .white24),
                                                        ),
                                                        child: Icon(
                                                            Icons.delete,
                                                            size: 18,
                                                            color: deleteFocused
                                                                ? Colors
                                                                    .redAccent
                                                                : Colors
                                                                    .white70),
                                                      ),
                                                    ),
                                                  )
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18.0),
                        child: Center(
                          child: MouseRegion(
                            onEnter: (_) => _setFocusSection(1),
                            onExit: (_) {},
                            child: GestureDetector(
                              onTap: () {
                                try {
                                  AudioService.instance.playAction();
                                } catch (_) {}
                                exit(0);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1F21),
                                  borderRadius: BorderRadius.circular(40),
                                  boxShadow: _isPowerFocused
                                      ? [
                                          BoxShadow(
                                              color: Colors.white
                                                  .withOpacity(0.06),
                                              blurRadius: 18,
                                              spreadRadius: 3,
                                              offset: const Offset(0, 6))
                                        ]
                                      : [
                                          BoxShadow(
                                              color: Colors.black54,
                                              blurRadius: 8,
                                              offset: const Offset(0, 4))
                                        ],
                                  border: _isPowerFocused
                                      ? Border.all(
                                          color: Colors.white24, width: 2)
                                      : Border.all(color: Colors.white24),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: const Icon(Icons.power_settings_new,
                                    color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
