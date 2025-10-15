// New profile-specific home screen
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/onscreen_keyboard.dart';
// file_picker and path_provider were used previously for avatar selection but
// profile editing is now handled by ProfileHomeScreen.

import '../models.dart';
import '../models/profile.dart';
import '../models/emulator_extensions.dart';
import '../services/emulator_helper.dart';
import 'emuchull_login.dart';
import 'settings_panel.dart';
import '../services/emulator_manager.dart';
import '../services/profile_service.dart';
import '../services/input_service.dart';
import '../services/audio_service.dart';
import '../services/settings_service.dart';
import '../ui/ps5_theme.dart';
import 'emulator_screen.dart';
import 'profile_home.dart';

class ProfileEmulatorHomeScreen extends StatefulWidget {
  const ProfileEmulatorHomeScreen({super.key, required this.profile});
  final Profile profile;

  @override
  State<ProfileEmulatorHomeScreen> createState() =>
      _ProfileEmulatorHomeScreenState();
}

class _ProfileEmulatorHomeScreenState extends State<ProfileEmulatorHomeScreen>
    with WindowListener, TickerProviderStateMixin {
  final EmulatorManager manager = EmulatorManager();
  final List<EmulatorData> _allEmulators = [];
  final List<EmulatorData> emulators = [];
  static const int _avatarIndex = -100;
  static const int _logoutIndex = -101;
  static const int _settingsIndex = -102;
  static const int _topRegionIndex = -200;
  int _selectedIndex = _avatarIndex;
  int _topFocusIndex = 0; // 0=Add,1=Edit,2=Panel,3=Logout
  final FocusNode _focusNode = FocusNode();
  late final List<FocusNode> _topFocusNodes;
  // action mode for the selected emulator card
  bool _cardActionMode = false;
  int _cardActionFocusedIndex = 0; // 0=rename,1=changeCover,2=delete
  static const int _columns = 4;

  final AudioPlayer _bgMusic = AudioPlayer();
  final SettingsService _settings = SettingsService.instance;
  late VoidCallback _settingsListener;
  // Removed unused fields: window focus and settings panel flags

  @override
  void initState() {
    super.initState();
    _load();
    _topFocusNodes = List.generate(4, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    windowManager.addListener(this);
    _bindInputCallbacks();
    _preloadSounds();
    // Apply settings (volumes and bg music) and subscribe to changes
    _settingsListener = () {
      // debounce small UI work
      try {
        _applyVolumesFromSettings();
        _onBgMusicChanged();
      } catch (_) {}
    };
    _settings.masterVolume.addListener(_settingsListener);
    _settings.musicVolume.addListener(_settingsListener);
    _settings.sfxVolume.addListener(_settingsListener);
    _settings.bgMusicEnabled.addListener(_settingsListener);
    _settings.audio.bgMusicPath.addListener(_settingsListener);
  }

  Future<void> _performCardAction(int cardIndex, int actionIndex) async {
    switch (actionIndex) {
      case 0:
        await _renameEmulatorAt(cardIndex);
        break;
      case 1:
        await _changeEmulatorCoverAt(cardIndex);
        break;
      case 2:
        await _deleteEmulatorAt(cardIndex);
        break;
    }
  }

  Future<void> _renameEmulatorAt(int index) async {
    if (index < 0 || index >= emulators.length) return;
    final emu = emulators[index];
    // Use the project's OnScreenKeyboard so controller/gamepad can type
    final result = await showDialog<String?>(
      context: context,
      builder: (c) => OnScreenKeyboard(
        initialValue: emu.name,
        title: 'Renombrar emulador',
        maxLength: 64,
        isPin: false,
      ),
    );
    if (result == null) return;
    final newName = result.isNotEmpty ? result : emu.name;

    final oldId = emu.id;
    final globalIdx = _allEmulators.indexWhere((e) => e.id == oldId);

    EmulatorData replaced;
    if (globalIdx >= 0) {
      final old = _allEmulators[globalIdx];
      replaced = EmulatorData(
        name: newName,
        exePath: old.exePath,
        supportedExts: List<String>.from(old.supportedExts),
        gamesPath: old.gamesPath,
        games: List<GameData>.from(old.games),
        launchFullscreen: old.launchFullscreen,
        launchArgs: List<String>.from(old.launchArgs),
        workingDirectory: old.workingDirectory,
        manualAddsOnly: old.manualAddsOnly,
      );
      _allEmulators[globalIdx] = replaced;
    } else {
      replaced = EmulatorData(
        name: newName,
        exePath: emu.exePath,
        supportedExts: List<String>.from(emu.supportedExts),
        gamesPath: emu.gamesPath,
        games: List<GameData>.from(emu.games),
        launchFullscreen: emu.launchFullscreen,
        launchArgs: List<String>.from(emu.launchArgs),
        workingDirectory: emu.workingDirectory,
        manualAddsOnly: emu.manualAddsOnly,
      );
      _allEmulators.add(replaced);
    }

    final shownIdx = emulators.indexWhere((e) => e.id == oldId);
    if (shownIdx >= 0) emulators[shownIdx] = replaced;

    final newId = replaced.id;
    if (newId != oldId) {
      try {
        final profiles = await ProfileService.instance.loadProfiles();
        var changed = false;
        for (var p in profiles) {
          for (var i = 0; i < p.emulatorIds.length; i++) {
            if (p.emulatorIds[i] == oldId) {
              p.emulatorIds[i] = newId;
              changed = true;
            }
          }
          final seen = <String>{};
          p.emulatorIds = p.emulatorIds.where((id) {
            if (seen.contains(id)) return false;
            seen.add(id);
            return true;
          }).toList();
        }
        if (changed) await ProfileService.instance.saveProfiles(profiles);
        final current = ProfileService.instance.currentProfile;
        if (current != null) {
          var updated = false;
          for (var i = 0; i < current.emulatorIds.length; i++) {
            if (current.emulatorIds[i] == oldId) {
              current.emulatorIds[i] = newId;
              updated = true;
            }
          }
          if (updated) ProfileService.instance.setCurrentProfile(current);
        }
      } catch (e) {
        debugPrint('update profiles after rename error: $e');
      }
    }

    await manager.saveEmulators(_allEmulators);
    if (!mounted) return;
    setState(() {
      _cardActionMode = false;
      _selectedIndex = shownIdx >= 0 ? shownIdx : _selectedIndex;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Emulador renombrado a "$newName"')),
    );
  }

  Future<void> _changeEmulatorCoverAt(int index) async {
    if (index < 0 || index >= emulators.length) return;
    // allow picking an image file for the emulator cover
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Elige una imagen para la portada',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final emu = emulators[index];
    final oldId = emu.id;
    final globalIdx = _allEmulators.indexWhere((e) => e.id == oldId);

    EmulatorData replaced;
    if (globalIdx >= 0) {
      final old = _allEmulators[globalIdx];
      replaced = EmulatorData(
        name: old.name,
        exePath: old.exePath,
        supportedExts: List<String>.from(old.supportedExts),
        coverPath: path,
        gamesPath: old.gamesPath,
        games: List<GameData>.from(old.games),
        launchFullscreen: old.launchFullscreen,
        launchArgs: List<String>.from(old.launchArgs),
        workingDirectory: old.workingDirectory,
        manualAddsOnly: old.manualAddsOnly,
      );
      _allEmulators[globalIdx] = replaced;
    } else {
      replaced = EmulatorData(
        name: emu.name,
        exePath: emu.exePath,
        supportedExts: List<String>.from(emu.supportedExts),
        coverPath: path,
        gamesPath: emu.gamesPath,
        games: List<GameData>.from(emu.games),
        launchFullscreen: emu.launchFullscreen,
        launchArgs: List<String>.from(emu.launchArgs),
        workingDirectory: emu.workingDirectory,
        manualAddsOnly: emu.manualAddsOnly,
      );
      _allEmulators.add(replaced);
    }

    final shownIdx = emulators.indexWhere((e) => e.id == oldId);
    if (shownIdx >= 0) emulators[shownIdx] = replaced;
    await manager.saveEmulators(_allEmulators);
    if (!mounted) return;
    // reload shown list so UI reflects the new cover and any id changes
    await _load();
  }

  Future<void> _deleteEmulatorAt(int index) async {
    if (index < 0 || index >= emulators.length) return;
    final emu = emulators[index];
    // show a dialog navigable by gamepad (left/right + activate)
    final input = InputService.instance;
    int focused = 0; // 0=Cancelar,1=Eliminar
    VoidCallback? removeListener;
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
            title: const Text('Eliminar emulador'),
            content: Text(
                '¿Eliminar "${emu.name}" de esta y todas las configuraciones?'),
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
    if (confirm != true) return;
    // remove from global list
    final globalIdx = _allEmulators.indexWhere((e) => e.id == emu.id);
    if (globalIdx >= 0) _allEmulators.removeAt(globalIdx);
    await manager.saveEmulators(_allEmulators);
    try {
      await ProfileService.instance.removeEmulatorFromAllProfiles(emu.id);
    } catch (e) {
      debugPrint('Failed to remove emulator from profiles: $e');
    }
    if (!mounted) return;
    // exit action mode after deletion
    setState(() {
      _cardActionMode = false;
    });
    await _load();
  }

  // helper removed: use ProfileService.saveProfiles/loadProfiles directly when needed

  @override
  void dispose() {
    _unbindInputCallbacks();
    windowManager.removeListener(this);
    for (final n in _topFocusNodes) {
      n.dispose();
    }
    _focusNode.dispose();
    try {
      _settings.masterVolume.removeListener(_settingsListener);
      _settings.musicVolume.removeListener(_settingsListener);
      _settings.sfxVolume.removeListener(_settingsListener);
      _settings.bgMusicEnabled.removeListener(_settingsListener);
      _settings.audio.bgMusicPath.removeListener(_settingsListener);
    } catch (_) {}
    _bgMusic.dispose();
    super.dispose();
  }

  Future<void> _preloadSounds() async {
    try {
      await _bgMusic.setReleaseMode(ReleaseMode.loop);
    } catch (_) {}
    await AudioService.instance.init();
    // prepare background music according to settings
    _applyVolumesFromSettings();
    _prepareBgSource();
  }

  void _applyVolumesFromSettings() {
    final master = _settings.masterVolume.value;
    final music = _settings.musicVolume.value;
    try {
      _bgMusic.setVolume((master * music).clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('bg volume apply error (profile home): $e');
    }
    AudioService.instance.applyVolumesFromSettings();
  }

  Future<void> _prepareBgSource() async {
    try {
      final enabled = _settings.bgMusicEnabled.value;
      final path = _settings.audio.bgMusicPath.value;
      if (enabled && path != null && File(path).existsSync()) {
        await _bgMusic.setSource(DeviceFileSource(path));
      } else {
        await _bgMusic.setSource(AssetSource('sounds/bg_menu.mp3'));
      }
      if (_settings.bgMusicEnabled.value) {
        await _bgMusic.seek(Duration.zero);
        await _bgMusic.resume();
      } else {
        await _bgMusic.stop();
      }
    } catch (e) {
      debugPrint('prepare bg source error (profile home): $e');
      try {
        await _bgMusic.setSource(AssetSource('sounds/bg_menu.mp3'));
      } catch (_) {}
    }
  }

  void _onBgMusicChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _prepareBgSource();
      } catch (e) {
        debugPrint('onBgMusicChanged error (profile home): $e');
      }
    });
  }

  Future<void> _load() async {
    final loaded = await manager.loadEmulators();
    _allEmulators
      ..clear()
      ..addAll(loaded);
    final current = widget.profile;
    final ids = current.emulatorIds.toSet();
    final toShow = loaded.where((e) => ids.contains(e.id)).toList();
    setState(() {
      emulators
        ..clear()
        ..addAll(toShow);
      if (emulators.isNotEmpty &&
          ![_avatarIndex, _settingsIndex, _logoutIndex, _topRegionIndex]
              .contains(_selectedIndex)) {
        _selectedIndex = 0;
      }
    });
  }

  void _bindInputCallbacks() {
    final input = InputService.instance;
    input.onLeft = () {
      // if we're inside card action mode, navigate the action buttons
      if (_cardActionMode &&
          _selectedIndex >= 0 &&
          _selectedIndex < emulators.length) {
        setState(() =>
            _cardActionFocusedIndex = (_cardActionFocusedIndex - 1 + 3) % 3);
        return;
      }
      if (_selectedIndex == _topRegionIndex) {
        setState(() =>
            _topFocusIndex = (_topFocusIndex - 1) % _topFocusNodes.length);
        _topFocusNodes[_topFocusIndex].requestFocus();
        return;
      }
      if (_selectedIndex == _avatarIndex) {
        setState(() => _selectedIndex = _logoutIndex);
        return;
      }
      if (emulators.isEmpty) {
        // If no emulators, ensure top region can be focused
        setState(() {
          _selectedIndex = _topRegionIndex;
        });
        _topFocusNodes[_topFocusIndex].requestFocus();
        return;
      }
      setState(() => _selectedIndex = (_selectedIndex - 1) % emulators.length);
    };
    input.onRight = () {
      // navigate actions when in card action mode
      if (_cardActionMode &&
          _selectedIndex >= 0 &&
          _selectedIndex < emulators.length) {
        setState(
            () => _cardActionFocusedIndex = (_cardActionFocusedIndex + 1) % 3);
        return;
      }
      if (_selectedIndex == _topRegionIndex) {
        setState(() =>
            _topFocusIndex = (_topFocusIndex + 1) % _topFocusNodes.length);
        _topFocusNodes[_topFocusIndex].requestFocus();
        return;
      }
      if (_selectedIndex == _avatarIndex) {
        setState(() => _selectedIndex = _settingsIndex);
        return;
      }
      if (emulators.isEmpty) {
        setState(() => _selectedIndex = _topRegionIndex);
        _topFocusNodes[_topFocusIndex].requestFocus();
        return;
      }
      setState(() => _selectedIndex = (_selectedIndex + 1) % emulators.length);
    };
    input.onUp = () {
      // Move focus to top action bar when moving up from the first row,
      // or always move to top when there are no emulators.
      if (_cardActionMode) return; // ignore up/down while in card action mode
      if (_selectedIndex >= 0 && _selectedIndex < _columns) {
        setState(() => _selectedIndex = _topRegionIndex);
        _topFocusNodes[_topFocusIndex].requestFocus();
        return;
      }
      if (emulators.isEmpty) {
        setState(() => _selectedIndex = _topRegionIndex);
        _topFocusNodes[_topFocusIndex].requestFocus();
        return;
      }
      setState(() =>
          _selectedIndex = (_selectedIndex - _columns) % emulators.length);
    };
    input.onDown = () {
      // Move focus down from the top region or header to the grid (or to avatar)
      if (_cardActionMode) return; // ignore up/down while in card action mode
      if (_selectedIndex == _topRegionIndex ||
          _selectedIndex == _avatarIndex ||
          _selectedIndex == _logoutIndex ||
          _selectedIndex == _settingsIndex) {
        setState(
            () => _selectedIndex = emulators.isNotEmpty ? 0 : _avatarIndex);
        return;
      }
      if (emulators.isEmpty) {
        // If there are no emulators and we're not on top, ensure we go to top
        setState(() => _selectedIndex = _topRegionIndex);
        return;
      }
      setState(() =>
          _selectedIndex = (_selectedIndex + _columns) % emulators.length);
    };
    input.onActivate = () {
      // If we're in card action mode, activate the focused action for the selected card
      if (_cardActionMode &&
          _selectedIndex >= 0 &&
          _selectedIndex < emulators.length) {
        _performCardAction(_selectedIndex, _cardActionFocusedIndex);
        return;
      }
      if (_selectedIndex == _topRegionIndex) {
        // activate focused top button
        switch (_topFocusIndex) {
          case 0:
            _onAddEmulator();
            break;
          case 1:
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => ProfileHomeScreen(profile: widget.profile)),
            );
            break;
          case 2:
            _openSettingsPanel();
            break;
          case 3:
            ProfileService.instance.clearCurrentProfile();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const EmuChullLoginScreen()),
            );
            break;
        }
        return;
      }
      if (_selectedIndex == _avatarIndex) {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => ProfileHomeScreen(profile: widget.profile)),
        );
        return;
      }
      if (_selectedIndex == _logoutIndex) {
        ProfileService.instance.clearCurrentProfile();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const EmuChullLoginScreen()),
        );
        return;
      }
      if (_selectedIndex == _settingsIndex) {
        _openSettingsPanel();
        return;
      }
      if (_selectedIndex >= 0 && _selectedIndex < emulators.length) {
        _openEmulator(_selectedIndex);
      }
    };
    input.onBack = () {
      // if in card action mode, exit it first
      if (_cardActionMode) {
        setState(() => _cardActionMode = false);
        return;
      }
      // fallback: go back to profile selection
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const EmuChullLoginScreen()));
    };

    // triangle toggles action mode on the focused card
    input.onTriangle = () {
      if (_selectedIndex >= 0 && _selectedIndex < emulators.length) {
        setState(() {
          _cardActionMode = !_cardActionMode;
          if (_cardActionMode) _cardActionFocusedIndex = 0;
        });
        return;
      }
    };
  }

  void _unbindInputCallbacks() {
    final input = InputService.instance;
    input.onLeft = null;
    input.onRight = null;
    input.onUp = null;
    input.onDown = null;
    input.onActivate = null;
    input.onBack = null;
  }

  void _openEmulator(int index) {
    if (index < 0 || index >= emulators.length) return;
    _bgMusic.stop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmulatorScreen(
          emulator: emulators[index],
          profile: widget.profile,
          emulatorIdForProfile: emulators[index].id,
          onChanged: () async {
            await manager.saveEmulators(_allEmulators);
            setState(() {});
          },
        ),
      ),
    ).then((_) async {
      if (!mounted) return;
      await _bgMusic.resume();
      _bindInputCallbacks();
    });
  }

  Future<void> _onAddEmulator() async {
    // Show a small two-option menu: 0 = Agregar emulador, 1 = Agregar tarjeta PC
    final input = InputService.instance;
    int focused = 0; // 0=Emulador,1=Tarjeta PC,2=Cancelar
    VoidCallback? removeListener;
    final choice = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        return StatefulBuilder(builder: (c, setState) {
          removeListener ??= input.pushListener(InputListener(
            onLeft: () {
              focused = (focused - 1) < 0 ? 2 : focused - 1;
              AudioService.instance.playNav();
              try {
                setState(() {});
              } catch (_) {}
            },
            onRight: () {
              focused = (focused + 1) % 3;
              AudioService.instance.playNav();
              try {
                setState(() {});
              } catch (_) {}
            },
            onActivate: () {
              AudioService.instance.playAction();
              if (focused == 0) {
                Navigator.of(context).pop(0);
              } else if (focused == 1)
                Navigator.of(context).pop(1);
              else
                Navigator.of(context).pop(-1);
            },
            onBack: () {
              AudioService.instance.playAction();
              Navigator.of(context).pop(-1);
            },
          ));

          return AlertDialog(
            title: const Text('Agregar'),
            content: const Text('Elige qué tipo de tarjeta quieres agregar'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(0),
                child: Text('Agregar emulador',
                    style: TextStyle(
                        color: focused == 0 ? const Color(0xFF66E0FF) : null,
                        fontWeight: focused == 0 ? FontWeight.bold : null)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(1),
                child: Text('Agregar tarjeta PC',
                    style: TextStyle(
                        color: focused == 1 ? const Color(0xFF66E0FF) : null,
                        fontWeight: focused == 1 ? FontWeight.bold : null)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(-1),
                child: Text('Cancelar',
                    style: TextStyle(
                        color: focused == 2 ? Colors.redAccent : null,
                        fontWeight: focused == 2 ? FontWeight.bold : null)),
              ),
            ],
          );
        });
      },
    );
    try {
      removeListener?.call();
    } catch (_) {}
    if (choice == null || choice < 0) return;

    if (choice == 0) {
      // Existing flow: pick emulator and optional games folder
      final emu = await manager.pickEmulatorAndGames();
      if (emu == null) return;
      await _addEmulatorToGlobalAndProfile(emu);
    } else if (choice == 1) {
      // Create a PC card and optionally let the user rename it
      final nameResult = await showDialog<String?>(
        context: context,
        builder: (c) => OnScreenKeyboard(
          initialValue: 'PC',
          title: 'Nombre de la tarjeta PC',
          maxLength: 64,
          isPin: false,
        ),
      );
      final displayName =
          (nameResult != null && nameResult.isNotEmpty) ? nameResult : 'PC';
      final pc = manager.createPcCard(displayName: displayName);
      await _addEmulatorToGlobalAndProfile(pc);
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _addEmulatorToGlobalAndProfile(EmulatorData emu) async {
    // agregar al global y asociar al perfil
    _allEmulators.add(emu);
    // guardar global
    await manager.saveEmulators(_allEmulators);
    // añadir id al perfil si no existe
    final id = emu.id;
    if (!widget.profile.emulatorIds.contains(id)) {
      widget.profile.emulatorIds.add(id);
      // Persist the change: load stored profiles, update the matching one and save.
      try {
        final profiles = await ProfileService.instance.loadProfiles();
        final idx = profiles.indexWhere((p) => p.id == widget.profile.id);
        if (idx >= 0) {
          profiles[idx].emulatorIds =
              List<String>.from(widget.profile.emulatorIds);
          // ensure uniqueness
          profiles[idx].emulatorIds =
              profiles[idx].emulatorIds.toSet().toList();
        } else {
          // If profile not present in storage, append it (defensive)
          profiles.add(widget.profile);
        }
        await ProfileService.instance.saveProfiles(profiles);
        // Keep runtime currentProfile consistent
        if (ProfileService.instance.currentProfile?.id == widget.profile.id) {
          ProfileService.instance.currentProfile = widget.profile;
        }
      } catch (e) {
        debugPrint('Failed to persist emulator association: $e');
      }
    }
  }

  Future<void> _onEditAvatar() async {
    // Open the profile editor to allow editing the avatar and other fields.
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfileHomeScreen(profile: widget.profile)));
  }

  Future<void> _onLogout() async {
    try {
      ProfileService.instance.clearCurrentProfile();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const EmuChullLoginScreen()),
    );
  }

  Future<void> _onOpenPanel() async {
    _openSettingsPanel();
  }

  void _openSettingsPanel() {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPanel(asRoute: true)));
  }

  Widget _buildTopAction({
    required int index,
    required FocusNode focusNode,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final isFocused =
        _selectedIndex == _topRegionIndex && _topFocusIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: Focus(
        focusNode: focusNode,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedIndex = _topRegionIndex;
              _topFocusIndex = index;
              focusNode.requestFocus();
            });
            onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isFocused ? Colors.white12 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isFocused
                  ? Border.all(color: Colors.white70, width: 1.4)
                  : null,
            ),
            child: Tooltip(
              message: tooltip,
              child: Icon(icon, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = PS5Theme.instance;
    final current = widget.profile;
    return Scaffold(
      backgroundColor: theme.bg,
      body: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: (_) {},
        child: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/principal.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12),
              child: Column(
                children: [
                  // Top action bar (focus-aware)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildTopAction(
                          index: 0,
                          focusNode: _topFocusNodes[0],
                          tooltip: 'Agregar emulador',
                          icon: Icons.add,
                          onPressed: _onAddEmulator),
                      _buildTopAction(
                          index: 1,
                          focusNode: _topFocusNodes[1],
                          tooltip: 'Editar avatar',
                          icon: Icons.edit,
                          onPressed: _onEditAvatar),
                      const SizedBox(width: 6),
                      _buildTopAction(
                          index: 2,
                          focusNode: _topFocusNodes[2],
                          tooltip: 'Panel',
                          icon: Icons.settings,
                          onPressed: _onOpenPanel),
                      _buildTopAction(
                          index: 3,
                          focusNode: _topFocusNodes[3],
                          tooltip: 'Cerrar sesión',
                          icon: Icons.logout,
                          onPressed: _onLogout),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    ProfileHomeScreen(profile: current)),
                          );
                        },
                        child: CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white12,
                          backgroundImage: current.avatarPath != null
                              ? FileImage(File(current.avatarPath!))
                              : null,
                          child: current.avatarPath == null
                              ? Text(current.name.isNotEmpty
                                  ? current.name[0].toUpperCase()
                                  : '?')
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              current.name.isNotEmpty
                                  ? current.name
                                  : 'EMUCHULL',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            const Text('emulador universal',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: emulators.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.storage,
                                    size: 56, color: Colors.white38),
                                const SizedBox(height: 12),
                                const Text('No hay emuladores para este perfil',
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.white)),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _columns,
                              crossAxisSpacing: 20,
                              mainAxisSpacing: 20,
                              childAspectRatio: 0.8,
                            ),
                            itemCount: emulators.length,
                            itemBuilder: (context, index) {
                              final emu = emulators[index];
                              final isSelected = index == _selectedIndex;
                              return PS5EmulatorCard(
                                title: emu.name,
                                iconAsset:
                                    EmulatorHelper.getEmulatorIcon(emu.name),
                                isSelected: isSelected,
                                onTap: () {
                                  setState(() => _selectedIndex = index);
                                  // if tapped while in action mode, keep action mode
                                  _openEmulator(index);
                                },
                                onDelete: () async {
                                  await _deleteEmulatorAt(index);
                                },
                                onRename: () async {
                                  await _renameEmulatorAt(index);
                                },
                                onChangeIcon: () async {
                                  await _changeEmulatorCoverAt(index);
                                },
                                coverPath: emu.coverPath,
                                actionMode: _cardActionMode && isSelected,
                                actionFocusedIndex: _cardActionFocusedIndex,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
