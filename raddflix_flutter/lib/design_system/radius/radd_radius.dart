// lib/design_system/radius/radd_radius.dart
//
// RaddRadius — the app-wide corner radius scale (Volume II).
// sm = chips/badges, md = cards/inputs, lg = sheets/dialogs, pill = buttons/tags.
//
// Note: this is the *new design-system* radius scale used by Radd* components
// going forward. The legacy `AppRadius` in `core/constants.dart` remains in
// place for existing screens until they're migrated — do not delete it.

import 'package:flutter/widgets.dart';

class RaddRadius {
  RaddRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
}
