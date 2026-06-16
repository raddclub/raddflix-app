/// Phase U — Urdu / Desi Language Features
/// U1 — Urdu UI Strings (RTL layout switch + localisation keys)
/// U2 — Urdu Subtitle Rendering (Nastaleeq font support)
/// U3 — Desi Content Tags (Drama / Telefilm / OST / Mazaaq)
/// U4 — Ramadan Mode (special late-night schedule + Suhoor reminder)
library u_series;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// U2 — Urdu Subtitle Font
// ─────────────────────────────────────────────────────────────────────────────

/// Nastaleeq rendering: uses 'NotoNastaliqUrdu' asset font.
/// Falls back to system Urdu rendering if unavailable.
TextStyle urduSubtitleStyle({
  double fontSize = 22,
  Color color = Colors.white,
}) {
  return TextStyle(
    fontFamily: 'NotoNastaliqUrdu',
    fontSize: fontSize,
    color: color,
    height: 2.0,            // Nastaleeq needs extra line height for diacritics
    shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
  );
}

/// Wraps subtitle text in an RTL directionality scope for Urdu/Arabic.
class UrduSubtitleText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const UrduSubtitleText({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: style ?? urduSubtitleStyle(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// U3 — Desi Content Tags
// ─────────────────────────────────────────────────────────────────────────────

enum DesiTag {
  drama, telefilm, ost, mazaaq, morning_show, reality, game_show,
  news_special, documentary, kids, ramadan_special, eid_special
}

const desiTagLabels = {
  DesiTag.drama:            'ڈرامہ',
  DesiTag.telefilm:         'ٹیلی فلم',
  DesiTag.ost:              'OST',
  DesiTag.mazaaq:           'مزاق',
  DesiTag.morning_show:     'مارننگ شو',
  DesiTag.reality:          'ریئیلٹی شو',
  DesiTag.game_show:        'گیم شو',
  DesiTag.news_special:     'خصوصی خبریں',
  DesiTag.documentary:      'دستاویزی',
  DesiTag.kids:             'بچوں کا',
  DesiTag.ramadan_special:  'رمضان خصوصی',
  DesiTag.eid_special:      'عید خصوصی',
};

const desiTagColors = {
  DesiTag.drama:            Color(0xFF7B1FA2),
  DesiTag.telefilm:         Color(0xFF1565C0),
  DesiTag.ost:              Color(0xFFE65100),
  DesiTag.mazaaq:           Color(0xFF558B2F),
  DesiTag.morning_show:     Color(0xFFF57F17),
  DesiTag.reality:          Color(0xFFC62828),
  DesiTag.game_show:        Color(0xFF00838F),
  DesiTag.news_special:     Color(0xFF37474F),
  DesiTag.documentary:      Color(0xFF4E342E),
  DesiTag.kids:             Color(0xFFAD1457),
  DesiTag.ramadan_special:  Color(0xFF1B5E20),
  DesiTag.eid_special:      Color(0xFF880E4F),
};

class DesiTagChip extends StatelessWidget {
  final DesiTag tag;

  const DesiTagChip({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    final color = desiTagColors[tag] ?? Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6))),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Text(
          desiTagLabels[tag] ?? tag.name,
          style: TextStyle(color: color, fontSize: 11.5,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// U4 — Ramadan Mode
// ─────────────────────────────────────────────────────────────────────────────

class RamadanModeService {
  RamadanModeService._();
  static final instance = RamadanModeService._();

  bool _enabled = false;
  bool get isEnabled => _enabled;

  void setEnabled(bool v) => _enabled = v;

  // Suhoor reminder: schedule notification at 30 mins before Fajr
  // Actual scheduling handled by platform notification plugin.
  // Here we return the reminder payload.
  Map<String, dynamic> suhoorReminderPayload({
    required DateTime fajrTime,
    required String city,
  }) {
    final reminderTime =
        fajrTime.subtract(const Duration(minutes: 30));
    return {
      'type': 'suhoor_reminder',
      'city': city,
      'reminderAt': reminderTime.toIso8601String(),
      'fajrAt': fajrTime.toIso8601String(),
      'title': 'سحری کا وقت',
      'body': 'فجر سے 30 منٹ پہلے سحری کر لیں',
    };
  }

  // Ramadan schedule badge (shows on content cards)
  bool get isIftar => _enabled && _isEveningTime();

  bool _isEveningTime() {
    final h = DateTime.now().hour;
    return h >= 17 && h <= 21; // 5pm–9pm = Iftar window
  }
}

class RamadanBadge extends StatelessWidget {
  const RamadanBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)]),
        borderRadius: BorderRadius.circular(12)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Text('🌙', style: TextStyle(fontSize: 12)),
        SizedBox(width: 4),
        Text('رمضان خصوصی',
            style: TextStyle(color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// U1 — Basic Urdu/English language toggle strings
// ─────────────────────────────────────────────────────────────────────────────

const _en = {
  'play': 'Play', 'pause': 'Pause', 'settings': 'Settings',
  'subtitles': 'Subtitles', 'quality': 'Quality', 'speed': 'Speed',
  'skip_intro': 'Skip Intro', 'next_episode': 'Next Episode',
  'my_list': 'My List', 'share': 'Share', 'download': 'Download',
};

const _ur = {
  'play': 'چلائیں', 'pause': 'روکیں', 'settings': 'ترتیبات',
  'subtitles': 'ذیلی عنوانات', 'quality': 'معیار', 'speed': 'رفتار',
  'skip_intro': 'تعارف چھوڑیں', 'next_episode': 'اگلی قسط',
  'my_list': 'میری فہرست', 'share': 'شیئر کریں', 'download': 'ڈاؤن لوڈ',
};

String tr(String key, {bool urdu = false}) =>
    (urdu ? _ur[key] : _en[key]) ?? key;
