// File: lib/ui/ps5_theme.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class PS5Theme {
  PS5Theme._();
  static final instance = PS5Theme._();

  // ===== Paleta EmuChull (blanco como acento) =====
  // Accent: blanco puro (puedes ajustar alpha si quieres menos brillo)
  Color get accent => const Color(0xFFFFFFFF);
  // Fondo general oscuro EmuChull
  Color get bg => const Color(0xFF0B0B0D);
  // Overlay sutil sobre cards
  Color get cardOverlay => Colors.white.withOpacity(0.03);
  // Texto secundario
  Color get subtleText => Colors.white70;

  // Card decoration común para estilo "EmuChull"
  BoxDecoration cardDecoration(bool selected) => BoxDecoration(
        color: selected ? cardOverlay : Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? accent.withOpacity(0.95) : Colors.white10,
          width: selected ? 2.6 : 1.0,
        ),
        boxShadow: selected
            ? [
                // glow blanco cuando está seleccionado
                BoxShadow(
                  color: accent.withOpacity(0.22),
                  blurRadius: 24,
                  spreadRadius: 2.6,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 8,
                  offset: const Offset(0, 6),
                ),
              ],
      );

  // Card inner gradient (used by PS5EmulatorCard)
  Gradient cardGradient({bool withCover = false}) {
    if (withCover) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withOpacity(0.02),
          Colors.black.withOpacity(0.64),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF0F1113).withOpacity(0.18),
        const Color(0xFF0B0B0D).withOpacity(0.72),
      ],
    );
  }
}

// Widget reutilizable tipo "PS5 card" adaptado a EmuChull (blanco como acento)
class PS5EmulatorCard extends StatelessWidget {
  final String title;
  final String iconAsset;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final VoidCallback? onChangeIcon;
  final VoidCallback? onRename;
  final Widget? subtitle;
  final String? coverPath;
  final bool actionMode;
  final int actionFocusedIndex;

  const PS5EmulatorCard({
    super.key,
    required this.title,
    required this.iconAsset,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.onChangeIcon,
    this.onRename,
    this.subtitle,
    this.coverPath,
    this.actionMode = false,
    this.actionFocusedIndex = -1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = PS5Theme.instance;

    DecorationImage? bgImage;
    try {
      if (coverPath != null &&
          coverPath!.isNotEmpty &&
          File(coverPath!).existsSync()) {
        bgImage = DecorationImage(
            image: FileImage(File(coverPath!)), fit: BoxFit.cover);
      }
    } catch (_) {
      bgImage = null;
    }

    // Helper para envolver IconButton y forzar ripples blancos
    Widget whiteRippleIconButton({required Widget child}) {
      return Theme(
        data: Theme.of(context).copyWith(
          // ripples / highlights en blanco con opacidades suaves
          splashColor: theme.accent.withOpacity(0.12),
          highlightColor: theme.accent.withOpacity(0.06),
          hoverColor: theme.accent.withOpacity(0.03),
          splashFactory: InkRipple.splashFactory,
        ),
        child: child,
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: theme.cardDecoration(isSelected),
        clipBehavior: Clip.hardEdge,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calcula un tamaño de icono relativo al ancho de la tarjeta:
              // toma 60% del ancho hasta un máximo de 140 y mínimo 64.
              final double maxIcon = 140;
              final double minIcon = 64;
              final double imgSize = math.max(
                  minIcon, math.min(maxIcon, constraints.maxWidth * 0.6));

              return Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.18),
                  image: bgImage,
                ),
                child: Stack(
                  children: [
                    if (bgImage != null)
                      Positioned.fill(
                        child: Container(
                            decoration: BoxDecoration(
                                gradient: theme.cardGradient(withCover: true))),
                      ),

                    // Si NO hay cover, mostramos el icono grande centrado
                    if (bgImage == null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 8),
                          child: Image.asset(
                            iconAsset,
                            fit: BoxFit.contain,
                            width: imgSize,
                            height: imgSize,
                          ),
                        ),
                      ),

                    // Panel inferior con título y acciones
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                            gradient:
                                theme.cardGradient(withCover: bgImage != null)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title.trim(),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: isSelected ? theme.accent : Colors.white,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null && bgImage == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: DefaultTextStyle(
                                    style: TextStyle(
                                        fontSize: 11, color: theme.subtleText),
                                    child: subtitle!),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (onRename != null)
                                  _actionButtonWrapper(
                                    child: whiteRippleIconButton(
                                      child: IconButton(
                                          icon:
                                              const Icon(Icons.edit, size: 22),
                                          color: isSelected
                                              ? theme.accent
                                              : Colors.white70,
                                          tooltip: 'Renombrar',
                                          onPressed: onRename),
                                    ),
                                    focused:
                                        actionMode && actionFocusedIndex == 0,
                                    accent: theme.accent,
                                  ),
                                if (onChangeIcon != null)
                                  _actionButtonWrapper(
                                    child: whiteRippleIconButton(
                                      child: IconButton(
                                          icon:
                                              const Icon(Icons.image, size: 22),
                                          color: isSelected
                                              ? theme.accent
                                              : Colors.white70,
                                          tooltip: 'Cambiar portada',
                                          onPressed: onChangeIcon),
                                    ),
                                    focused:
                                        actionMode && actionFocusedIndex == 1,
                                    accent: theme.accent,
                                  ),
                                if (onDelete != null)
                                  _actionButtonWrapper(
                                    child: whiteRippleIconButton(
                                      child: IconButton(
                                          icon: const Icon(Icons.delete,
                                              size: 22),
                                          color: Colors.redAccent,
                                          tooltip: 'Eliminar',
                                          onPressed: onDelete),
                                    ),
                                    focused:
                                        actionMode && actionFocusedIndex == 2,
                                    accent: theme.accent,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (isSelected)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.accent,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                  color: theme.accent.withOpacity(0.32),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _actionButtonWrapper(
      {required Widget child, required bool focused, required Color accent}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: focused
          ? BoxDecoration(
              border: Border.all(color: accent, width: 2.0),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white10,
              boxShadow: [
                BoxShadow(
                    color: accent.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            )
          : BoxDecoration(borderRadius: BorderRadius.circular(8)),
      child: child,
    );
  }
}
