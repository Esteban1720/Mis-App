import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models.dart';
import '../models/profile.dart';
import '../services/emulator_manager.dart';
import '../services/emulator_helper.dart';
import '../services/profile_service.dart';
import '../services/input_service.dart';
import '../services/settings_service.dart';
import '../services/audio_service.dart';
import 'settings_panel.dart';
import 'emulator_input_binder.dart';
import '../widgets/onscreen_keyboard.dart';
import '../widgets/emulator_game_grid.dart';
import '../services/emulator_runner.dart';
import '../widgets/emulator_dialogs.dart';

typedef VoidCb = void Function();

class EmulatorScreen extends StatefulWidget {
  final EmulatorData emulator;
  final Future<void> Function()? onChanged;
  // Optional: the profile that opened this emulator and the emulator id
  // used to load/save per-profile game lists.
  final Profile? profile;
  final String? emulatorIdForProfile;

  const EmulatorScreen({
    super.key,
    required this.emulator,
    this.onChanged,
    this.profile,
    this.emulatorIdForProfile,
  });

  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  final EmulatorManager _manager = EmulatorManager();
  final FocusNode _focusNode = FocusNode();
  final SettingsService _settings = SettingsService.instance;

  int _selectedIndex = 0;
  bool _scanning = false;
  static const int _columns = 4;

  // removed unused _wasFullScreenBeforeLaunch

  late EmulatorInputBinder _inputBinder;
  final EmulatorRunner _runner = EmulatorRunner();

  Future<void> _openGameActions(GameData game) async {
    await showGameActionsDialog(
      context: context,
      game: game,
      manager: _manager,
      onLaunch: (g) async => await _launchGame(g),
      onRename: (g) async => await _renameGame(g),
      onChangeIcon: (g) async => await _changeIcon(g),
      onDelete: (g) async => await _deleteGame(g),
      onChanged: widget.onChanged,
    );
    _focusNode.unfocus();
    _requestFocus();
  }

  late VoidCallback _settingsListener;
  bool _settingsPanelOpen = false;
  int _focusedAppBar = -1;
  static const int _appBarActionsCount = 6;
  int _focusedActionIndex = -1;

  bool _appBarIndexHasVisibleWidget(int idx) {
    if (idx < 0 || idx >= _appBarActionsCount) return false;
    // index 5 corresponds to the manual-add (.exe) action which is only
    // rendered when emulator.manualAddsOnly is true.
    if (idx == 5 && !widget.emulator.manualAddsOnly) return false;
    // other indices (0..4) are always present
    return true;
  }

  int _findNextVisibleAppBarIndex(int start, int delta) {
    // start is the current index; we search forward/backward by delta (1 or -1)
    if (delta == 0) return -1;
    int idx = start;
    for (int i = 0; i < _appBarActionsCount; i++) {
      idx = (idx + delta) % _appBarActionsCount;
      if (idx < 0) idx += _appBarActionsCount;
      if (_appBarIndexHasVisibleWidget(idx)) return idx;
    }
    return -1;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

    // If opened with a profile, load profile-specific game list for this emulator
    if (widget.profile != null && widget.emulatorIdForProfile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final paths = ProfileService.instance.getProfileGamesForEmulator(
              widget.profile!, widget.emulatorIdForProfile!);
          final newGames = paths
              .map((p) => GameData(
                  path: p, displayName: EmulatorHelper.cleanGameName(p)))
              .toList();
          if (!mounted) return;
          setState(() {
            widget.emulator.games
              ..clear()
              ..addAll(newGames);
            if (widget.emulator.games.isNotEmpty) _selectedIndex = 0;
          });
        } catch (e) {
          debugPrint('Profile-specific games load failed: $e');
        }
      });
    }

    _inputBinder = EmulatorInputBinder(
      input: InputService.instance,
      onLeft: () {
        if (_focusedAppBar != -1) {
          _playNav();
          final next = _findNextVisibleAppBarIndex(_focusedAppBar, -1);
          if (next >= 0) _focusedAppBar = next;
          setState(() {});
          return;
        }
        if (_focusedActionIndex != -1) {
          _playNav();
          final cnt = _actionsCountForSelected();
          if (cnt > 0) {
            _focusedActionIndex = (_focusedActionIndex - 1 + cnt) % cnt;
            setState(() {});
          }
          return;
        }
        _playNav();
        _moveLeft();
      },
      onRight: () {
        if (_focusedAppBar != -1) {
          _playNav();
          final next = _findNextVisibleAppBarIndex(_focusedAppBar, 1);
          if (next >= 0) _focusedAppBar = next;
          setState(() {});
          return;
        }
        if (_focusedActionIndex != -1) {
          _playNav();
          final cnt = _actionsCountForSelected();
          if (cnt > 0) {
            _focusedActionIndex = (_focusedActionIndex + 1) % cnt;
            setState(() {});
          }
          return;
        }
        _playNav();
        _moveRight();
      },
      onUp: () {
        if (_focusedAppBar != -1) return;
        if (_focusedActionIndex != -1) {
          _playNav();
          return;
        }
        if (_isInTopRow()) {
          _playNav();
          final next = _findNextVisibleAppBarIndex(-1, 1);
          _focusedAppBar = next >= 0 ? next : -1;
          setState(() {});
          return;
        }
        _playNav();
        _moveUp();
      },
      onDown: () {
        if (_focusedAppBar != -1) {
          _playNav();
          final targetCol = _focusedAppBar.clamp(0, _columns - 1);
          final newIndex = targetCol < widget.emulator.games.length
              ? targetCol
              : (widget.emulator.games.isNotEmpty ? 0 : -1);
          if (newIndex >= 0) {
            _selectedIndex = newIndex;
          }
          _focusedAppBar = -1;
          setState(() {});
          _requestFocus();
          return;
        }
        if (_focusedActionIndex != -1) {
          _playNav();
          return;
        }
        _playNav();
        _moveDown();
      },
      onActivate: () {
        if (_focusedAppBar != -1) {
          _playAction();
          _activateAppBarAction(_focusedAppBar);
          return;
        }
        if (_focusedActionIndex != -1) {
          _playAction();
          _activateFocusedAction();
          return;
        }
        _playAction();
        _onActivate();
      },
      onBack: () async {
        if (_focusedAppBar != -1) {
          _playAction();
          _focusedAppBar = -1;
          setState(() {});
          _requestFocus();
          return;
        }
        if (_focusedActionIndex != -1) {
          _playAction();
          setState(() => _focusedActionIndex = -1);
          _requestFocus();
          return;
        }
        _playAction();
        await _handleBack();
      },
      onToggleFullscreen: () => _toggleFullScreen(),
      onSelect: () {
        _playAction();
        _openSettingsPanel();
      },
      onShare: () {
        _playAction();
        _openSettingsPanel();
      },
      onSettings: () {
        if (_focusedAppBar != -1) return;
        if (widget.emulator.games.isEmpty) return;
        if (_focusedActionIndex == -1) {
          _playAction();
          _focusedActionIndex = 0;
          setState(() {});
        } else {
          _playAction();
          setState(() => _focusedActionIndex = -1);
          _requestFocus();
        }
      },
    );

    _inputBinder.bind();
    // Also listen for the Triangle/Y button to toggle focused-action mode
    try {
      InputService.instance.onTriangle = () {
        if (widget.emulator.games.isEmpty) return;
        if (_focusedAppBar != -1) return; // ignore when app bar focused
        _playAction();
        setState(() {
          _focusedActionIndex = _focusedActionIndex == -1 ? 0 : -1;
        });
      };
    } catch (_) {}

    AudioService.instance.applyVolumesFromSettings();
    _settingsListener = () {
      AudioService.instance.applyVolumesFromSettings();
    };
    _settings.masterVolume.addListener(_settingsListener);
    _settings.sfxVolume.addListener(_settingsListener);
    _settings.musicVolume.addListener(_settingsListener);
  }

  @override
  void dispose() {
    try {
      _inputBinder.unbindAndRestore();
    } catch (_) {}
    try {
      InputService.instance.onTriangle = null;
    } catch (_) {}
    _focusNode.dispose();
    _settings.masterVolume.removeListener(_settingsListener);
    _settings.sfxVolume.removeListener(_settingsListener);
    _settings.musicVolume.removeListener(_settingsListener);
    super.dispose();
  }

  void _playNav() => AudioService.instance.playNav();
  void _playAction() => AudioService.instance.playAction();
  void _playLaunch() => AudioService.instance.playLaunch();

  Future<void> _activateAppBarAction(int idx) async {
    switch (idx) {
      case 0:
        _scanGames();
        break;
      case 1:
        await _changeGamesFolder();
        break;
      case 2:
        await _openSettingsPanel();
        break;
      case 3:
        if (widget.onChanged != null) await widget.onChanged!();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Guardado')));
        break;
      case 4:
        await _openEmulatorExe();
        break;
      case 5:
        await _addPcGame();
        break;
    }
  }

  bool _isInTopRow() {
    if (widget.emulator.games.isEmpty) return true;
    if (_selectedIndex < 0) return true;
    return _selectedIndex < _columns;
  }

  int _actionsCountForSelected() {
    if (widget.emulator.games.isEmpty || _selectedIndex < 0) return 0;
    int c = 0;
    if (true) c++;
    if (true) c++;
    if (true) c++;
    return c;
  }

  Future<void> _activateFocusedAction() async {
    if (_selectedIndex < 0 || _selectedIndex >= widget.emulator.games.length) {
      return;
    }
    final game = widget.emulator.games[_selectedIndex];
    final idx = _focusedActionIndex;
    setState(() => _focusedActionIndex = -1);

    try {
      switch (idx) {
        case 0:
          final typed = await _showOnScreenKeyboard(initial: game.displayName);
          if (typed != null && typed.isNotEmpty) {
            final oldPath = game.path;
            setState(() => game.displayName = typed);
            try {
              await _manager.renameGamePersistent(oldPath, typed);
            } catch (e) {
              debugPrint(
                  'rename persistent error after on-screen keyboard: $e');
            }
            // persist per-profile if applicable
            if (widget.profile != null && widget.emulatorIdForProfile != null) {
              final paths = widget.emulator.games.map((g) => g.path).toList();
              await ProfileService.instance.setProfileGamesForEmulator(
                  widget.profile!, widget.emulatorIdForProfile!, paths);
            } else {
              if (widget.onChanged != null) await widget.onChanged!();
            }
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nombre actualizado')));
          }
          break;
        case 1:
          await _changeIcon(game);
          break;
        case 2:
          await _deleteGame(game);
          break;
        default:
          break;
      }
    } catch (e, st) {
      debugPrint('_activateFocusedAction error: $e\n$st');
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _moveLeft() {
    final games = widget.emulator.games;
    if (games.isEmpty) return;
    setState(() {
      if (_selectedIndex <= 0) {
        _selectedIndex = games.length - 1;
      } else {
        _selectedIndex--;
      }
    });
    _requestFocus();
  }

  void _moveRight() {
    final games = widget.emulator.games;
    if (games.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + 1) % games.length;
    });
    _requestFocus();
  }

  void _moveUp() {
    final games = widget.emulator.games;
    if (games.isEmpty) return;
    final posInCol = _selectedIndex % _columns;
    final rows = (games.length / _columns).ceil();
    final currRow = (_selectedIndex / _columns).floor();
    int targetRow = currRow - 1;
    if (targetRow < 0) targetRow = rows - 1;
    int target = targetRow * _columns + posInCol;
    if (target >= games.length) target = games.length - 1;
    setState(() => _selectedIndex = target);
    _requestFocus();
  }

  void _moveDown() {
    final games = widget.emulator.games;
    if (games.isEmpty) return;
    final posInCol = _selectedIndex % _columns;
    final rows = (games.length / _columns).ceil();
    final currRow = (_selectedIndex / _columns).floor();
    int targetRow = currRow + 1;
    if (targetRow >= rows) targetRow = 0;
    int target = targetRow * _columns + posInCol;
    if (target >= games.length) target = games.length - 1;
    setState(() => _selectedIndex = target);
    _requestFocus();
  }

  void _onActivate() {
    final games = widget.emulator.games;
    if (games.isEmpty) {
      _scanGames();
      return;
    }
    if (_selectedIndex < 0 || _selectedIndex >= games.length) return;
    _launchGame(games[_selectedIndex]);
  }

  Future<void> _toggleFullScreen() async {
    try {
      await InputService.instance.toggleFullscreen();
    } catch (e) {
      debugPrint('toggle fullscreen error: $e');
    }
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _handleBack() async {
    if (widget.onChanged != null) {
      try {
        await widget.onChanged!();
      } catch (e) {
        debugPrint('onChanged callback error: $e');
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _scanGames() async {
    if (widget.emulator.manualAddsOnly) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Esta tarjeta no realiza escaneos. Usa "Agregar juego" para añadir .exe manualmente.')));
      return;
    }

    setState(() => _scanning = true);
    try {
      await _manager.scanGamesForEmulator(widget.emulator);
      if (widget.profile != null && widget.emulatorIdForProfile != null) {
        final paths = widget.emulator.games.map((g) => g.path).toList();
        await ProfileService.instance.setProfileGamesForEmulator(
            widget.profile!, widget.emulatorIdForProfile!, paths);
      } else {
        if (widget.onChanged != null) await widget.onChanged!();
      }
      setState(() {
        if (widget.emulator.games.isEmpty) {
          _selectedIndex = 0;
        } else if (_selectedIndex >= widget.emulator.games.length) {
          _selectedIndex = widget.emulator.games.length - 1;
        }
      });
      _playAction();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Escaneo completado')));
    } catch (e) {
      debugPrint('scan error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al escanear: $e')));
    } finally {
      setState(() => _scanning = false);
    }
  }

  Future<void> _startProcessAndHandle(
    String exe,
    List<String> args,
    String wd, {
    required String startingSnack,
    required bool playLaunchSound,
    String? stdoutTag,
  }) async {
    try {
      await _runner.startProcessAndHandle(
        exe: exe,
        args: args,
        wd: wd,
        startingSnack: startingSnack,
        playLaunchSound: playLaunchSound,
        onStdout: (d) => debugPrint('${stdoutTag ?? exe} STDOUT: $d'),
        onStderr: (d) => debugPrint('${stdoutTag ?? exe} STDERR: $d'),
        onCleanup: () async {
          await _runner.handleProcessExitCleanup();
        },
        onRestoreInput: () async {
          if (!_settingsPanelOpen) {
            try {
              _inputBinder.bind();
              await InputService.instance.resume();
              debugPrint(
                  'EmulatorScreen: input resumed and callbacks re-bound');
            } catch (e) {
              debugPrint('InputService.resume() error: $e');
            }
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusNode.requestFocus();
          });
        },
      );
      if (playLaunchSound) _playLaunch();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(startingSnack)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo no encontrado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.emulator.games;
    final bg = EmulatorHelper.getEmulatorBackground(widget.emulator.name);
    return WillPopScope(
      onWillPop: () async {
        await _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.emulator.name.toUpperCase()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _playAction();
              _handleBack();
            },
          ),
          actions: [
            _buildAppBarAction(
              icon: Icons.refresh,
              tooltip: 'Escanear juegos',
              index: 0,
              onPressed: () {
                if (_scanning) return;
                _playAction();
                _scanGames();
              },
            ),
            _buildAppBarAction(
              icon: Icons.folder_open,
              tooltip: 'Cambiar carpeta de juegos',
              index: 1,
              onPressed: () {
                _playAction();
                _changeGamesFolder();
              },
            ),
            _buildAppBarAction(
              icon: Icons.settings,
              tooltip: 'Abrir panel de ajustes',
              index: 2,
              onPressed: () {
                _playAction();
                _openSettingsPanel();
              },
            ),
            _buildAppBarAction(
              icon: Icons.save,
              tooltip: 'Forzar guardar',
              index: 3,
              onPressed: () async {
                _playAction();
                if (widget.onChanged != null) await widget.onChanged!();
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Guardado')));
              },
            ),
            _buildAppBarAction(
              icon: Icons.play_arrow,
              tooltip: 'Abrir emulador',
              index: 4,
              onPressed: () async {
                _playAction();
                await _openEmulatorExe();
              },
            ),
            if (widget.emulator.manualAddsOnly)
              _buildAppBarAction(
                icon: Icons.add_box,
                tooltip: 'Agregar juego (.exe)',
                index: 5,
                onPressed: () async {
                  _playAction();
                  await _addPcGame();
                },
              ),
          ],
        ),
        body: RawKeyboardListener(
          focusNode: _focusNode,
          onKey: _onRawKey,
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(bg),
                fit: BoxFit.cover,
              ),
            ),
            child: Column(
              children: [
                if (widget.emulator.gamesPath != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Carpeta: ${widget.emulator.gamesPath}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                Expanded(
                  child: games.isEmpty
                      ? const Center(
                          child: Text('No se encontraron juegos',
                              style: TextStyle(color: Colors.white)))
                      : EmulatorGameGrid(
                          games: games,
                          columns: _columns,
                          selectedIndex: _selectedIndex,
                          focusedAppBar: _focusedAppBar,
                          focusedActionIndex: _focusedActionIndex,
                          emulatorName: widget.emulator.name,
                          onSelect: (i) {
                            setState(() {
                              _selectedIndex = i;
                              _focusedActionIndex = -1;
                            });
                            _playAction();
                            _launchGame(games[i]);
                          },
                          onLongPress: (i) {
                            setState(() {
                              _selectedIndex = i;
                              _focusedActionIndex = 0;
                            });
                            _playAction();
                            _openGameActions(games[i]);
                          },
                          onDelete: (i) {
                            _playAction();
                            _deleteGame(games[i]);
                          },
                          onRename: (i) {
                            _playAction();
                            _renameGame(games[i]);
                          },
                          onChangeIcon: (i) {
                            _playAction();
                            _changeIcon(games[i]);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsPanel() async {
    if (!mounted) return;

    final controller = SettingsPanelController();
    final input = InputService.instance;

    final settingsListener = InputListener(
      onLeft: () => controller.onLeft?.call(),
      onRight: () => controller.onRight?.call(),
      onUp: () => controller.onUp?.call(),
      onDown: () => controller.onDown?.call(),
      onActivate: () => controller.onActivate?.call(),
      onBack: () => controller.onBack?.call(),
      onToggleFullscreen: () {},
      onSelect: () {},
      onShare: () => controller.onReset?.call(),
      onSettings: () => controller.onApply?.call(),
    );

    final removeListener = input.pushListener(settingsListener);

    try {
      _inputBinder.unbindAndRestore();
    } catch (_) {}

    _focusNode.unfocus();

    try {
      AudioService.instance.applyVolumesFromSettings();
    } catch (_) {}

    _settingsPanelOpen = true;

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsPanel(controller: controller, asRoute: true),
          fullscreenDialog: true,
        ),
      );
    } finally {
      try {
        removeListener();
      } catch (_) {}

      _settingsPanelOpen = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } catch (_) {}
      });
    }
  }

  Widget _buildAppBarAction({
    required IconData icon,
    required String tooltip,
    required int index,
    required VoidCb onPressed,
  }) {
    final focused = _focusedAppBar == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          decoration: focused
              ? BoxDecoration(
                  border:
                      Border.all(color: const Color(0xFF66E0FF), width: 2.0),
                  borderRadius: BorderRadius.circular(6.0),
                )
              : null,
          child: IconButton(
            icon: Icon(icon, color: focused ? Colors.white : Colors.white70),
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  Future<String?> _showOnScreenKeyboard({String initial = ''}) async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OnScreenKeyboard(
          initialValue: initial, title: 'Renombrar', maxLength: 64),
    );
    return result;
  }

  Future<void> _launchGame(GameData game) async {
    try {
      if (widget.emulator.manualAddsOnly) {
        String exePath = game.path;
        List<String> extraArgs = [];
        String wd = File(exePath).parent.path;
        // Si es un acceso directo de Windows, intentar resolverlo
        if (Platform.isWindows && exePath.toLowerCase().endsWith('.lnk')) {
          try {
            final resolved =
                await EmulatorHelper.resolveWindowsShortcut(exePath);
            if (resolved != null) {
              exePath = resolved.targetPath;
              if (resolved.workingDirectory.isNotEmpty) {
                wd = resolved.workingDirectory;
              }
              if (resolved.arguments.isNotEmpty) {
                extraArgs = EmulatorHelper.splitArgsRespectingQuotes(
                    resolved.arguments);
              }
            }
          } catch (e) {
            debugPrint('resolve shortcut error: $e');
          }
        }

        await _startProcessAndHandle(
          exePath,
          <String>[...extraArgs],
          wd,
          startingSnack: 'Lanzando ${game.displayName}',
          playLaunchSound: true,
          stdoutTag: 'PC GAME',
        );
        return;
      }

      final exe = widget.emulator.exePath;
      if (!File(exe).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Archivo del emulador no encontrado.')));
        return;
      }

      final argsFromHelper = EmulatorHelper.buildLaunchArgsForGame(
        emulatorName: widget.emulator.name,
        gamePath: game.path,
        fullscreen: widget.emulator.launchFullscreen,
        extraArgs: widget.emulator.launchArgs,
      );

      final lowerName = widget.emulator.name.toLowerCase();
      final args = <String>[];
      if (lowerName.contains('dolphin') ||
          exe.toLowerCase().contains('dolphin')) {
        args.addAll(['--batch']);
        if (argsFromHelper.any((a) => a == '-e' || a.startsWith('--exec'))) {
          args.addAll(argsFromHelper);
        } else {
          args.addAll(['--exec=${game.path}']);
          if (widget.emulator.launchArgs.isNotEmpty) {
            args.addAll(widget.emulator.launchArgs);
          }
        }
      } else {
        args.addAll(argsFromHelper);
      }

      final wd = widget.emulator.workingDirectory ??
          File(widget.emulator.exePath).parent.path;

      await _startProcessAndHandle(
        exe,
        args,
        wd,
        startingSnack: 'Lanzando ${game.displayName}',
        playLaunchSound: true,
        stdoutTag: 'EMU',
      );
    } catch (e, st) {
      debugPrint('Launch error: $e$st');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al lanzar: $e')));
    }
  }

  Future<void> _openEmulatorExe() async {
    try {
      final exe = widget.emulator.exePath;
      if (!File(exe).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Archivo del emulador no encontrado.')));
        return;
      }

      final args = List<String>.from(widget.emulator.launchArgs);
      final wd = widget.emulator.workingDirectory ??
          File(widget.emulator.exePath).parent.path;

      await _startProcessAndHandle(
        exe,
        args,
        wd,
        startingSnack: 'Abriendo emulador...',
        playLaunchSound: false,
        stdoutTag: 'EMU EXE',
      );
    } catch (e, st) {
      debugPrint('_openEmulatorExe error: $e$st');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al abrir emulador: $e')));
    }
  }

  Future<void> _changeGamesFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle:
            'Selecciona la carpeta de juegos para ${widget.emulator.name}',
      );
      if (path == null) return;

      setState(() {
        widget.emulator.gamesPath = path;
      });

      await _manager.saveEmulators([widget.emulator]);
      await _manager.scanGamesForEmulator(widget.emulator,
          baseDir: Directory(path));
      if (widget.onChanged != null) await widget.onChanged!();

      _playAction();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Carpeta actualizada: $path')));
    } catch (e) {
      debugPrint('changeGamesFolder error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error cambiando carpeta: $e')));
    }
  }

  Future<void> _addPcGame() async {
    try {
      if (!widget.emulator.manualAddsOnly) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'La función Agregar .exe solo está disponible en tarjetas PC.')));
        return;
      }
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: Platform.isWindows ? ['exe', 'lnk'] : ['exe'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final newGame =
          GameData(path: path, displayName: EmulatorHelper.cleanGameName(path));
      setState(() {
        widget.emulator.games.removeWhere((g) => g.path == newGame.path);
        widget.emulator.games.add(newGame);
        _selectedIndex = widget.emulator.games.length - 1;
      });
      if (widget.profile != null && widget.emulatorIdForProfile != null) {
        final paths = widget.emulator.games.map((g) => g.path).toList();
        await ProfileService.instance.setProfileGamesForEmulator(
            widget.profile!, widget.emulatorIdForProfile!, paths);
      } else {
        await _manager.saveEmulators([widget.emulator]);
        if (widget.onChanged != null) await widget.onChanged!();
      }
      _playAction();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Juego agregado: ${newGame.displayName}')));
    } catch (e) {
      debugPrint('_addPcGame error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error agregando .exe: $e')));
    }
  }

  Future<void> _changeIcon(GameData game) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      setState(() => game.coverUrl = path);
      _playAction();
      if (widget.profile != null && widget.emulatorIdForProfile != null) {
        final paths = widget.emulator.games.map((g) => g.path).toList();
        await ProfileService.instance.setProfileGamesForEmulator(
            widget.profile!, widget.emulatorIdForProfile!, paths);
      } else {
        if (widget.onChanged != null) {
          await widget.onChanged!();
        } else {
          await _manager.saveEmulators([widget.emulator]);
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Icono/portada actualizada')));
    } catch (e) {
      debugPrint('changeIcon error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al cambiar icono: $e')));
    }
  }

  Future<void> _deleteGame(GameData game) async {
    final confirm = await showDeleteGameDialog(context: context, game: game);
    if (confirm == true) {
      setState(() {
        widget.emulator.games.removeWhere((g) => g.path == game.path);
        if (_selectedIndex >= widget.emulator.games.length) {
          _selectedIndex = widget.emulator.games.isEmpty
              ? 0
              : widget.emulator.games.length - 1;
        }
      });
      _playAction();
      if (widget.profile != null && widget.emulatorIdForProfile != null) {
        final paths = widget.emulator.games.map((g) => g.path).toList();
        await ProfileService.instance.setProfileGamesForEmulator(
            widget.profile!, widget.emulatorIdForProfile!, paths);
      } else {
        if (widget.onChanged != null) await widget.onChanged!();
      }
    } else {
      _requestFocus();
    }
  }

  Future<void> _renameGame(GameData game) async {
    final typed = await _showOnScreenKeyboard(initial: game.displayName);
    if (typed != null && typed.isNotEmpty) {
      final oldPath = game.path;
      setState(() => game.displayName = typed);
      await _manager.renameGamePersistent(oldPath, typed);
      _playAction();
      if (widget.profile != null && widget.emulatorIdForProfile != null) {
        final paths = widget.emulator.games.map((g) => g.path).toList();
        await ProfileService.instance.setProfileGamesForEmulator(
            widget.profile!, widget.emulatorIdForProfile!, paths);
      } else {
        if (widget.onChanged != null) await widget.onChanged!();
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nombre actualizado')));
    }
  }

  void _onRawKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    final key = event.logicalKey;
    if (_focusedAppBar != -1) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _playNav();
        final next = _findNextVisibleAppBarIndex(_focusedAppBar, -1);
        if (next >= 0) setState(() => _focusedAppBar = next);
        return;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _playNav();
        final next = _findNextVisibleAppBarIndex(_focusedAppBar, 1);
        if (next >= 0) setState(() => _focusedAppBar = next);
        return;
      } else if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _playAction();
        _activateAppBarAction(_focusedAppBar);
        return;
      } else if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        _playAction();
        setState(() => _focusedAppBar = -1);
        _requestFocus();
        return;
      }
    }

    if (_focusedActionIndex != -1) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _playNav();
        final cnt = _actionsCountForSelected();
        _focusedActionIndex = (_focusedActionIndex - 1 + cnt) % cnt;
        setState(() {});
        return;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _playNav();
        final cnt = _actionsCountForSelected();
        _focusedActionIndex = (_focusedActionIndex + 1) % cnt;
        setState(() {});
        return;
      } else if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _playAction();
        _activateFocusedAction();
        return;
      } else if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        _playAction();
        setState(() => _focusedActionIndex = -1);
        _requestFocus();
        return;
      }
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _playNav();
      _moveDown();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _playNav();
      if (_isInTopRow()) {
        setState(() => _focusedAppBar = 0);
        return;
      }
      _moveUp();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _playNav();
      _moveLeft();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _playNav();
      _moveRight();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _playAction();
      _onActivate();
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _playAction();
      _handleBack();
    } else if (key == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
    }
  }
}
