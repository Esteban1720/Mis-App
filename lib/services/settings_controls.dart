// Controls settings logic for SettingsService
import 'package:flutter/material.dart';

class SettingsControls {
  final ValueNotifier<double> controllerSensitivity =
      ValueNotifier<double>(0.5);
  final ValueNotifier<bool> invertYAxis = ValueNotifier<bool>(false);
  // Color chosen for PS4/PS5 controller theming
  final ValueNotifier<int> controllerColor = ValueNotifier<int>(0xFF1E88E5);

  void load(Map<String, dynamic> json) {
    controllerSensitivity.value =
        (json['controllerSensitivity'] as num?)?.toDouble() ??
            controllerSensitivity.value;
    invertYAxis.value = json['invertYAxis'] as bool? ?? invertYAxis.value;
    controllerColor.value =
        (json['controllerColor'] as int?) ?? controllerColor.value;
  }

  Map<String, dynamic> toJson() => {
        'controllerSensitivity': controllerSensitivity.value,
        'invertYAxis': invertYAxis.value,
        'controllerColor': controllerColor.value,
      };

  void resetToDefaults() {
    controllerSensitivity.value = 0.5;
    invertYAxis.value = false;
    controllerColor.value = 0xFF1E88E5; // default blue
  }
}
