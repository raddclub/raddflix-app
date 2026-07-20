// IDEA-08 — Phonetic Subtitle Overlay (Roman Urdu / Devanagari)
//
// Shows an offline, character-map-based Romanization below Arabic-script
// (Urdu/Punjabi) or Devanagari (Hindi) subtitle lines.  No ML, no network.
//
// Design goals:
//   • "Phonetically useful" rather than linguistically perfect — the consonant
//     skeleton is enough for bilingual audiences to follow along.
//   • Zero-latency: all work is synchronous, char-by-char map lookup.
//   • Auto-detect: caller does not need to specify the script.
//
// Usage:
//   if (PhoneticSubtitle.shouldRomanize(line)) {
//     final roman = PhoneticSubtitle.romanize(line);
//     // render `roman` below the main subtitle
//   }

/// Script family detected in a subtitle line.
enum PhoneticScript { none, arabic, devanagari }

/// IDEA-08 — Offline Romanization engine.
class PhoneticSubtitle {
  PhoneticSubtitle._();

  // ── Arabic / Urdu character → Roman Urdu ─────────────────────────────────
  //
  // Covers the subset of Arabic Unicode block (U+0600–U+06FF) used in Urdu /
  // Punjabi subtitles.  Multi-character digraphs (ch, sh, kh, …) are produced
  // by single character lookups — no lookahead needed.
  //
  // Characters not in the map (punctuation, digits, Latin, emoji) are passed
  // through unchanged so the output preserves sentence structure.
  static const Map<int, String> _urduMap = {
    0x0621: '',    // ء  hamza         — silent
    0x0622: 'aa',  // آ  alef madda
    0x0623: 'a',   // أ  alef hamza above
    0x0624: 'o',   // ؤ  wao with hamza
    0x0625: 'i',   // إ  alef hamza below
    0x0626: 'y',   // ئ  ye with hamza
    0x0627: 'a',   // ا  alef
    0x0628: 'b',   // ب  be
    0x0629: 'h',   // ة  ta marbuta
    0x062A: 't',   // ت  te
    0x062B: 's',   // ث  se
    0x062C: 'j',   // ج  jeem
    0x062D: 'h',   // ح  he (bari)
    0x062E: 'kh',  // خ  khe
    0x062F: 'd',   // د  dal
    0x0630: 'z',   // ذ  zal
    0x0631: 'r',   // ر  re
    0x0632: 'z',   // ز  ze
    0x0633: 's',   // س  seen
    0x0634: 'sh',  // ش  sheen
    0x0635: 's',   // ص  suad
    0x0636: 'z',   // ض  zuad
    0x0637: 't',   // ط  toe
    0x0638: 'z',   // ظ  zoe
    0x0639: '',    // ع  ain          — often silent
    0x063A: 'gh',  // غ  ghain
    0x0641: 'f',   // ف  fe
    0x0642: 'q',   // ق  qaf
    0x0643: 'k',   // ك  kaf (Arabic form)
    0x0644: 'l',   // ل  lam
    0x0645: 'm',   // م  meem
    0x0646: 'n',   // ن  noon
    0x0647: 'h',   // ه  he (choti — Arabic form)
    0x0648: 'w',   // و  wao
    0x0649: 'y',   // ى  alef maqsura
    0x064A: 'y',   // ي  ye (Arabic)
    // Urdu-specific letters
    0x0679: 't',   // ٹ  ṭe (retroflex t)
    0x0686: 'ch',  // چ  che
    0x0688: 'd',   // ڈ  ḍal (retroflex d)
    0x0691: 'r',   // ڑ  ṛe (retroflex r)
    0x0698: 'zh',  // ژ  zhe
    0x06A4: 'v',   // ڤ  ve
    0x06A9: 'k',   // ک  kaf (Urdu form)
    0x06AF: 'g',   // گ  gaf
    0x06B3: 'ny',  // ڳ  gaf with bar (Sindhi)
    0x06BA: 'n',   // ں  noon ghunna (nasal)
    0x06BB: 'nn',  // ڻ  ṇṇe
    0x06BC: 'n',   // ڼ  noon with ring
    0x06BE: 'h',   // ھ  do chashmi he (h-aspirate marker)
    0x06C1: 'h',   // ہ  he (Urdu/Persian form)
    0x06C2: 'h',   // ہ  he with hamza
    0x06C3: 'h',   // ۃ  te marbuta goal
    0x06CC: 'y',   // ی  Farsi ye (i/y)
    0x06D2: 'e',   // ے  ye (bari — end of word, often "ay")
    0x06D3: 'e',   // ۓ  ye barree with hamza
    // Vowel diacritics (harakat) — present in some romanized/formal Urdu
    0x064E: 'a',   // ◌َ fatha   → a
    0x064F: 'u',   // ◌ُ damma   → u
    0x0650: 'i',   // ◌ِ kasra   → i
    0x0651: '',    // ◌ّ shadda  → gemination (skip for simplicity)
    0x0652: '',    // ◌ْ sukun   → no vowel
    0x0670: 'a',   // ◌ٰ superscript alef → aa/a
    0x0654: '',    // ◌ٔ hamza above → skip
    0x0655: '',    // ◌ٕ hamza below → skip
    // Zero-width / directional marks — discard
    0x200C: '',    // ZWNJ
    0x200D: '',    // ZWJ
    0x200F: '',    // RLM
    0x200E: '',    // LRM
    0x202A: '',
    0x202C: '',
    0x202B: '',
    0x202D: '',
    0x202E: '',
    // Common Urdu punctuation
    0x06D4: '.',   // ۔ Urdu full stop
    0x061B: ';',   // ؛ Arabic semicolon
    0x061F: '?',   // ؟ Arabic question mark
  };

  // ── Devanagari → Roman Hindi  ─────────────────────────────────────────────
  //
  // Covers standard Devanagari block (U+0900–U+097F) used in Hindi subtitles.
  // Matras (vowel markers) are included so the consonant+matra sequence
  // produces the correct CV syllable in the output.
  static const Map<int, String> _devanagariMap = {
    // Independent vowels
    0x0905: 'a',   // अ
    0x0906: 'aa',  // आ
    0x0907: 'i',   // इ
    0x0908: 'ee',  // ई
    0x0909: 'u',   // उ
    0x090A: 'oo',  // ऊ
    0x090B: 'ri',  // ऋ
    0x090F: 'e',   // ए
    0x0910: 'ai',  // ऐ
    0x0913: 'o',   // ओ
    0x0914: 'au',  // औ
    0x0972: 'a',   // ॲ (ae/a)
    // Consonants
    0x0915: 'k',   // क
    0x0916: 'kh',  // ख
    0x0917: 'g',   // ग
    0x0918: 'gh',  // घ
    0x0919: 'ng',  // ङ
    0x091A: 'ch',  // च
    0x091B: 'chh', // छ
    0x091C: 'j',   // ज
    0x091D: 'jh',  // झ
    0x091E: 'ny',  // ञ
    0x091F: 't',   // ट (retroflex)
    0x0920: 'th',  // ठ (retroflex)
    0x0921: 'd',   // ड (retroflex)
    0x0922: 'dh',  // ढ (retroflex)
    0x0923: 'n',   // ण (retroflex n)
    0x0924: 't',   // त
    0x0925: 'th',  // थ
    0x0926: 'd',   // द
    0x0927: 'dh',  // ध
    0x0928: 'n',   // न
    0x092A: 'p',   // प
    0x092B: 'f',   // फ (ph/f)
    0x092C: 'b',   // ब
    0x092D: 'bh',  // भ
    0x092E: 'm',   // म
    0x092F: 'y',   // य
    0x0930: 'r',   // र
    0x0932: 'l',   // ल
    0x0933: 'l',   // ळ
    0x0935: 'v',   // व
    0x0936: 'sh',  // श
    0x0937: 'sh',  // ष
    0x0938: 's',   // स
    0x0939: 'h',   // ह
    // Additional consonants (with nukta — used in loanwords)
    0x0958: 'k',   // क़
    0x0959: 'kh',  // ख़
    0x095A: 'g',   // ग़
    0x095B: 'z',   // ज़
    0x095C: 'r',   // ड़
    0x095D: 'rh',  // ढ़
    0x095E: 'f',   // फ़
    0x095F: 'y',   // य़
    // Matras (vowel markers — suffix to a consonant)
    0x093E: 'a',   // ा aa-matra → 'a' (we treat aa as base vowel 'a')
    0x093F: 'i',   // ि i-matra
    0x0940: 'ee',  // ी ee-matra
    0x0941: 'u',   // ु u-matra
    0x0942: 'oo',  // ू oo-matra
    0x0943: 'ri',  // ृ ri-matra
    0x0947: 'e',   // े e-matra
    0x0948: 'ai',  // ै ai-matra
    0x094B: 'o',   // ो o-matra
    0x094C: 'au',  // ौ au-matra
    // Special markers
    0x094D: '',    // ् halant — suppresses inherent vowel (consonant cluster)
    0x0902: 'n',   // ं anusvara — nasal
    0x0903: 'h',   // ः visarga
    0x0901: 'n',   // ँ chandrabindu — nasal
    0x093C: '',    // ़ nukta — modifies previous consonant (skip)
    // Digits (use ASCII equivalents)
    0x0966: '0',   // ०
    0x0967: '1',   // १
    0x0968: '2',   // २
    0x0969: '3',   // ३
    0x096A: '4',   // ४
    0x096B: '5',   // ५
    0x096C: '6',   // ६
    0x096D: '7',   // ७
    0x096E: '8',   // ८
    0x096F: '9',   // ९
    // Zero-width / directional marks
    0x200C: '',    // ZWNJ
    0x200D: '',    // ZWJ
  };

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns the dominant script detected in [line].
  ///
  /// A script is considered "dominant" when its characters make up ≥10% of the
  /// total codepoints in the line (ignoring ASCII and whitespace). In mixed
  /// lines the first to reach threshold wins; Arabic takes priority since Urdu
  /// subtitles sometimes contain embedded Latin loan-word spellings.
  static PhoneticScript detectScript(String line) {
    if (line.isEmpty) return PhoneticScript.none;

    int arabic = 0, devanagari = 0, total = 0;
    for (final rune in line.runes) {
      if (rune <= 0x0020) continue; // skip whitespace and controls
      total++;
      if (rune >= 0x0600 && rune <= 0x06FF) arabic++;
      else if (rune >= 0x0900 && rune <= 0x097F) devanagari++;
    }
    if (total == 0) return PhoneticScript.none;

    final threshold = (total * 0.08).floor().clamp(1, 9999);
    if (arabic >= threshold) return PhoneticScript.arabic;
    if (devanagari >= threshold) return PhoneticScript.devanagari;
    return PhoneticScript.none;
  }

  /// Returns true when [line] contains enough Arabic or Devanagari script to
  /// warrant a phonetic overlay. Use this as a fast gate before calling
  /// [romanize] so non-applicable lines (Latin subtitles) add no cost.
  static bool shouldRomanize(String line) =>
      detectScript(line) != PhoneticScript.none;

  /// Transliterate [line] to a Roman representation using the offline
  /// character maps.
  ///
  /// The script is auto-detected from the content. Characters not in the map
  /// (Latin letters, digits, common punctuation) are passed through unchanged
  /// so the output preserves sentence structure.
  ///
  /// Returns an empty string when no applicable script is detected.
  static String romanize(String line) {
    final script = detectScript(line);
    if (script == PhoneticScript.none) return '';
    final map = script == PhoneticScript.arabic ? _urduMap : _devanagariMap;
    return _applyMap(line, map);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static String _applyMap(String line, Map<int, String> map) {
    final buf = StringBuffer();
    for (final rune in line.runes) {
      if (map.containsKey(rune)) {
        buf.write(map[rune]);
      } else {
        // Pass-through: ASCII, punctuation, digits, unknown scripts.
        buf.writeCharCode(rune);
      }
    }
    // Collapse runs of 3+ spaces → single space and trim.
    return buf.toString().replaceAll(RegExp(r' {3,}'), ' ').trim();
  }
}
