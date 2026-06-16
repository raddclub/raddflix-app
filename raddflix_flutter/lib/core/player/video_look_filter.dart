/// Phase D2 — Color Look Presets (6 cinematic looks via ColorFilter.matrix)
/// No paid APIs. No shaders. Pure Flutter ColorFilter.matrix.
library video_look_filter;
import 'package:flutter/material.dart';

/// Returns a [ColorFilter] for the given look name.
/// Falls back to identity if the name is unknown or 'none'.
ColorFilter? videoLookFilter(String look) {
  switch (look) {
    case 'teal_orange':    return const ColorFilter.matrix(_tealOrange);
    case 'moody_blue':     return const ColorFilter.matrix(_moodyBlue);
    case 'golden_hour':    return const ColorFilter.matrix(_goldenHour);
    case 'bw_classic':     return const ColorFilter.matrix(_bwClassic);
    case 'faded_film':     return const ColorFilter.matrix(_fadedFilm);
    case 'cool_shadow':    return const ColorFilter.matrix(_coolShadow);
    case 'warm_sunset':    return const ColorFilter.matrix(_warmSunset);
    case 'crime_thriller': return const ColorFilter.matrix(_crimeThriller);
    default:               return null; // 'none' → no filter
  }
}

/// Human-readable label for each look.
const videoLookLabel = <String, String>{
  'none':           'None',
  'teal_orange':    'Teal-Orange',
  'moody_blue':     'Moody Blue',
  'golden_hour':    'Golden Hour',
  'bw_classic':     'B&W Classic',
  'faded_film':     'Faded Film',
  'cool_shadow':    'Cool Shadow',
  'warm_sunset':    'Warm Sunset',
  'crime_thriller': 'Crime Thriller',
};

const videoLookIds = [
  'none', 'teal_orange', 'moody_blue', 'golden_hour',
  'bw_classic', 'faded_film', 'cool_shadow', 'warm_sunset', 'crime_thriller',
];

// ── Color matrices (5×4 RGBA, row-major, last row always 0 0 0 0 1) ──────────
// Each matrix maps: [R' G' B' A']ᵀ = M × [R G B A 1]ᵀ

// Teal-Orange (Hollywood blockbuster) — shifts mids warm, shadows cool
const _tealOrange = <double>[
   1.08,  0.00, -0.08,  0.00, 0.02,   // R: amplify, suppress blue
  -0.02,  0.98,  0.00,  0.00, 0.00,   // G: slight desaturate
  -0.12,  0.00,  1.10,  0.00,-0.04,   // B: teal boost in shadows
   0.00,  0.00,  0.00,  1.00, 0.00,
];

// Moody Blue — cold, desaturated, blue-pushed
const _moodyBlue = <double>[
   0.82,  0.00,  0.00,  0.00,-0.04,   // R: desaturate reds
   0.00,  0.88,  0.00,  0.00,-0.02,   // G: reduce greens
   0.10,  0.10,  1.05,  0.00, 0.04,   // B: boost blues
   0.00,  0.00,  0.00,  1.00, 0.00,
];

// Golden Hour — warm golden light, slightly blown highlights
const _goldenHour = <double>[
   1.15,  0.05,  0.00,  0.00, 0.04,   // R: push warm
  -0.02,  1.00,  0.02,  0.00, 0.01,   // G: slight golden
  -0.08, -0.04,  0.80,  0.00,-0.02,   // B: reduce blue for warmth
   0.00,  0.00,  0.00,  1.00, 0.00,
];

// B&W Classic — luminosity-weighted grayscale
const _bwClassic = <double>[
   0.299,  0.587,  0.114,  0.00, 0.00,  // R
   0.299,  0.587,  0.114,  0.00, 0.00,  // G
   0.299,  0.587,  0.114,  0.00, 0.00,  // B
   0.000,  0.000,  0.000,  1.00, 0.00,
];

// Faded Film — washed-out, lifted blacks, old film look
const _fadedFilm = <double>[
   0.90, 0.05, 0.00, 0.00, 0.06,   // R: fade + lift
   0.00, 0.88, 0.00, 0.00, 0.06,   // G: fade + lift
   0.00, 0.00, 0.85, 0.00, 0.08,   // B: fade + lift more
   0.00, 0.00, 0.00, 1.00, 0.00,
];

// Cool Shadow — blue-tinted shadows, neutral highlights
const _coolShadow = <double>[
   0.88, 0.02, 0.02, 0.00,-0.03,   // R: reduce reds in shadows
   0.02, 0.92, 0.02, 0.00, 0.00,   // G: slight mid
   0.04, 0.06, 1.08, 0.00, 0.03,   // B: push blues
   0.00, 0.00, 0.00, 1.00, 0.00,
];

// Warm Sunset — orange-amber glow, pulled blues
const _warmSunset = <double>[
   1.20, 0.05,-0.02, 0.00, 0.05,   // R: strong warm push
   0.00, 0.95, 0.05, 0.00, 0.02,   // G: slight amber
  -0.10,-0.05, 0.75, 0.00,-0.02,   // B: pull blues hard
   0.00, 0.00, 0.00, 1.00, 0.00,
];

// Crime Thriller — desaturated, high contrast, green-black shadows
const _crimeThriller = <double>[
   0.80, 0.10, 0.10, 0.00,-0.06,   // R: desaturate
   0.05, 0.80, 0.05, 0.00,-0.04,   // G: desaturate
   0.00, 0.08, 0.85, 0.00,-0.08,   // B: slight green tint
   0.00, 0.00, 0.00, 1.00, 0.00,
];
