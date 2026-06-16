/// Phase J2 — Color Blind Modes
/// 3 modes: Deuteranopia / Protanopia / Tritanopia
/// Applied as ColorFilter.matrix over the entire video output.
library color_blind;

import 'package:flutter/widgets.dart';

enum ColorBlindMode { none, deuteranopia, protanopia, tritanopia }

ColorBlindMode colorBlindModeFromString(String s) {
  switch (s) {
    case 'deuteranopia': return ColorBlindMode.deuteranopia;
    case 'protanopia':   return ColorBlindMode.protanopia;
    case 'tritanopia':   return ColorBlindMode.tritanopia;
    default:             return ColorBlindMode.none;
  }
}

String colorBlindModeToString(ColorBlindMode m) {
  switch (m) {
    case ColorBlindMode.deuteranopia: return 'deuteranopia';
    case ColorBlindMode.protanopia:   return 'protanopia';
    case ColorBlindMode.tritanopia:   return 'tritanopia';
    default:                          return 'none';
  }
}

const colorBlindModeLabels = {
  ColorBlindMode.none:         'None',
  ColorBlindMode.deuteranopia: 'Deuteranopia',
  ColorBlindMode.protanopia:   'Protanopia',
  ColorBlindMode.tritanopia:   'Tritanopia',
};

const colorBlindModeIcons = {
  ColorBlindMode.none:         '👁',
  ColorBlindMode.deuteranopia: '🟢',
  ColorBlindMode.protanopia:   '🔴',
  ColorBlindMode.tritanopia:   '🔵',
};

/// Returns a ColorFilter for the given color blind mode,
/// or null for ColorBlindMode.none.
ColorFilter? colorBlindFilter(ColorBlindMode mode) {
  switch (mode) {
    case ColorBlindMode.deuteranopia:
      // Green-blind correction (shifts green → yellow, boosts blue channel)
      return const ColorFilter.matrix(<double>[
         0.625, 0.375, 0.000, 0, 0,
         0.700, 0.300, 0.000, 0, 0,
         0.000, 0.300, 0.700, 0, 0,
         0.000, 0.000, 0.000, 1, 0,
      ]);
    case ColorBlindMode.protanopia:
      // Red-blind correction (shifts red toward yellow/green)
      return const ColorFilter.matrix(<double>[
         0.567, 0.433, 0.000, 0, 0,
         0.558, 0.442, 0.000, 0, 0,
         0.000, 0.242, 0.758, 0, 0,
         0.000, 0.000, 0.000, 1, 0,
      ]);
    case ColorBlindMode.tritanopia:
      // Blue-blind correction (shifts blue toward cyan/green)
      return const ColorFilter.matrix(<double>[
         0.950, 0.050, 0.000, 0, 0,
         0.000, 0.433, 0.567, 0, 0,
         0.000, 0.475, 0.525, 0, 0,
         0.000, 0.000, 0.000, 1, 0,
      ]);
    default:
      return null;
  }
}

/// Wraps [child] with the appropriate color-blind correction filter.
Widget withColorBlindFilter(ColorBlindMode mode, Widget child) {
  final filter = colorBlindFilter(mode);
  if (filter == null) return child;
  return ColorFiltered(colorFilter: filter, child: child);
}
