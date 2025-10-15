// lib/widgets/emulator_card.dart
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/emulator_helper.dart';

class EmulatorCard extends StatelessWidget {
  final EmulatorData emulator;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onHover; // notify parent when mouse entra/sale

  const EmulatorCard({
    super.key,
    required this.emulator,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    this.onHover,
  });

  Color _accentColor() => const Color(0xFF00A3FF);

  @override
  Widget build(BuildContext context) {
    final double innerScale = isSelected ? 1.06 : 1.0;

    return MouseRegion(
      onEnter: (_) => onHover?.call(),
      onExit: (_) => onHover?.call(),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTap: () {
          // para click derecho en desktop, dejar que el padre muestre el menú
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isSelected ? 0.06 : 0.14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isSelected ? _accentColor() : Colors.white.withOpacity(0.22),
              width: isSelected ? 2.6 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _accentColor().withOpacity(0.18),
                      blurRadius: 18,
                      spreadRadius: 1,
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedScale(
                      scale: innerScale,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        alignment: Alignment.center,
                        child: Image.asset(
                          EmulatorHelper.getEmulatorIcon(emulator.name),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6.0),
                child: Text(
                  emulator.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? _accentColor() : Colors.white,
                    shadows: isSelected
                        ? const [
                            Shadow(
                                color: Colors.black45,
                                offset: Offset(1, 1),
                                blurRadius: 4)
                          ]
                        : null,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                onPressed: onDelete,
                tooltip: 'Eliminar emulador',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
