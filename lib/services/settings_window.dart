// Window settings logic for SettingsService
import 'package:flutter/material.dart';

class SettingsWindow {
  final ValueNotifier<bool> isFullscreen = ValueNotifier<bool>(false);
  final ValueNotifier<Size> windowSize =
      ValueNotifier<Size>(const Size(1280, 800));
  List<Size> availableResolutions = [];

  static const double aspectTolerance = 0.04;
  static const double pixelEps = 1.0;

  void load(Map<String, dynamic> json) {
    isFullscreen.value = json['isFullscreen'] as bool? ?? isFullscreen.value;
    final w = (json['windowWidth'] as num?)?.toDouble();
    final h = (json['windowHeight'] as num?)?.toDouble();
    if (w != null && h != null) windowSize.value = Size(w, h);
  }

  Map<String, dynamic> toJson() => {
        'isFullscreen': isFullscreen.value,
        'windowWidth': windowSize.value.width,
        'windowHeight': windowSize.value.height,
      };

  void resetToDefaults() {
    isFullscreen.value = false;
    windowSize.value = const Size(1280, 800);
  }
}
