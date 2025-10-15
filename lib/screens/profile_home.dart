// -----------------------------------------------------------------------------
// ProfileHomeScreen (mejorado)
// - Mejora UX visual: espaciado, enfoque, colores consistentes
// - Reutiliza el OnScreenKeyboard a través de un helper
// - Manejo de estado más claro y validaciones mínimas
// -----------------------------------------------------------------------------
import 'dart:io';

import 'package:emuchull/models/profile.dart';
import 'package:emuchull/services/profile_service.dart';
import 'package:emuchull/widgets/gamepad_listener.dart';
import 'package:emuchull/widgets/onscreen_keyboard.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';


class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({Key? key, required this.profile}) : super(key: key);
  final Profile profile;

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  String? _avatarPath;
  bool _saving = false;
  int _selectedIndex =
      0; // 0: avatar, 1: cambiar avatar, 2: nombre, 3: pin, 4: guardar
  final int _maxIndex = 4;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _pinController = TextEditingController();
    _avatarPath = widget.profile.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _changeSelected(int newIndex) {
    if (newIndex < 0) newIndex = 0;
    if (newIndex > _maxIndex) newIndex = _maxIndex;
    setState(() => _selectedIndex = newIndex);
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() => _avatarPath = path);
  }

  Future<String?> _showKeyboard(
      {required String initial,
      required String title,
      required int maxLength,
      bool isPin = false}) async {
    FocusScope.of(context).unfocus();

    return showGeneralDialog<String>(
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
                  initialValue: initial,
                  title: title,
                  maxLength: maxLength,
                  isPin: isPin),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showKeyboardForName() async {
    final result = await _showKeyboard(
        initial: _nameController.text,
        title: 'Editar nombre',
        maxLength: 24,
        isPin: false);
    if (result != null) setState(() => _nameController.text = result);
  }

  Future<void> _showKeyboardForPin() async {
    final result = await _showKeyboard(
        initial: _pinController.text,
        title: 'Editar PIN',
        maxLength: 8,
        isPin: true);
    if (result != null) setState(() => _pinController.text = result);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = widget.profile;
    p.name = _nameController.text.trim();
    p.avatarPath = _avatarPath;
    final pin = _pinController.text.trim();
    if (pin.isNotEmpty) {
      p.pinHash = ProfileService.instance.hashPin(pin);
      p.isPrivate = true;
    }

    final profiles = await ProfileService.instance.loadProfiles();
    final idx = profiles.indexWhere((x) => x.id == p.id);
    if (idx >= 0)
      profiles[idx] = p;
    else
      profiles.add(p);
    await ProfileService.instance.saveProfiles(profiles);

    if (ProfileService.instance.currentProfile?.id == p.id)
      ProfileService.instance.setCurrentProfile(p);

    setState(() => _saving = false);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _activateCurrent() {
    switch (_selectedIndex) {
      case 0:
      case 1:
        _pickAvatar();
        break;
      case 2:
        _showKeyboardForName();
        break;
      case 3:
        _showKeyboardForPin();
        break;
      case 4:
        if (!_saving) _save();
        break;
    }
  }

  Widget _buildAvatar() {
    final avatar = _avatarPath != null ? FileImage(File(_avatarPath!)) : null;
    return FocusableActionDetector(
      autofocus: _selectedIndex == 0,
      onShowFocusHighlight: (hasFocus) {
        if (hasFocus && _selectedIndex != 0) setState(() => _selectedIndex = 0);
      },
      child: GestureDetector(
        onTap: _pickAvatar,
        child: CircleAvatar(
          radius: 54,
          backgroundImage: avatar,
          backgroundColor: _selectedIndex == 0 ? Colors.amber : null,
          child: avatar == null ? const Icon(Icons.person, size: 48) : null,
        ),
      ),
    );
  }

  Widget _buildActionButton(
      {required Widget child,
      required VoidCallback onPressed,
      required int index}) {
    return FocusableActionDetector(
      autofocus: _selectedIndex == index,
      onShowFocusHighlight: (hasFocus) {
        if (hasFocus && _selectedIndex != index)
          setState(() => _selectedIndex = index);
      },
      child: ElevatedButton(
        onPressed: onPressed,
        style: ButtonStyle(
            backgroundColor: MaterialStateProperty.resolveWith(
                (states) => _selectedIndex == index ? Colors.amber : null)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: GamepadListener(
        onLeft: () => _changeSelected(_selectedIndex - 1),
        onRight: () => _changeSelected(_selectedIndex + 1),
        onUp: () => _changeSelected(_selectedIndex - 1),
        onDown: () => _changeSelected(_selectedIndex + 1),
        onActivate: _activateCurrent,
        onBack: () => Navigator.maybePop(context),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            const SizedBox(height: 8),
            _buildAvatar(),
            const SizedBox(height: 12),
            _buildActionButton(
              index: 1,
              onPressed: _pickAvatar,
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.photo),
                SizedBox(width: 8),
                Text('Cambiar avatar')
              ]),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                  border: Border.all(
                      color: _selectedIndex == 2
                          ? Colors.amber
                          : Colors.transparent,
                      width: 2),
                  borderRadius: BorderRadius.circular(8)),
              child: TextField(
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  controller: _nameController,
                  readOnly: true,
                  onTap: _showKeyboardForName),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                  border: Border.all(
                      color: _selectedIndex == 3
                          ? Colors.amber
                          : Colors.transparent,
                      width: 2),
                  borderRadius: BorderRadius.circular(8)),
              child: TextField(
                  decoration: const InputDecoration(
                      labelText: 'PIN (dejar en blanco para no cambiar)'),
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  readOnly: true,
                  onTap: _showKeyboardForPin),
            ),
            const SizedBox(height: 20),
            _buildActionButton(
              index: 4,
              onPressed: _saving ? () {} : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.save),
                      SizedBox(width: 8),
                      Text('Guardar')
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}
