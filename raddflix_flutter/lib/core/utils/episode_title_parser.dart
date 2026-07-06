// lib/core/utils/episode_title_parser.dart
//
// Pure helper for parsing show/season/episode info out of a download's
// title_text (e.g. "Breaking Bad S05E02 - Ozymandias").
//
// Used by the Download tab (DOWNLOAD-TAB-V2) to group TV episodes by show,
// then by season folder, without needing any schema change to the local
// downloads table.

class EpisodeInfo {
  /// Show title with the "S05E02" suffix stripped, e.g. "Breaking Bad".
  final String showTitle;

  /// Season number, or null if it couldn't be parsed (falls back to season 1).
  final int? season;

  /// Episode number, or null if it couldn't be parsed.
  final int? episode;

  /// The raw "S05E02" code as it appeared in the title, or null.
  final String? code;

  const EpisodeInfo({
    required this.showTitle,
    this.season,
    this.episode,
    this.code,
  });

  /// Season number for grouping purposes — always non-null (defaults to 1
  /// so un-parseable titles still land in a sensible "Season 1" folder).
  int get seasonOrDefault => season ?? 1;

  String get seasonLabel => 'Season $seasonOrDefault';
}

final RegExp _seCodePattern = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');

/// Parses a download's title_text into show/season/episode parts.
///
/// Examples:
///   "Breaking Bad S05E02 - Ozymandias" ->
///       showTitle: "Breaking Bad", season: 5, episode: 2, code: "S05E02"
///   "Some Movie (2023)" ->
///       showTitle: "Some Movie (2023)", season: null, episode: null, code: null
EpisodeInfo parseEpisodeTitle(String raw) {
  final match = _seCodePattern.firstMatch(raw);
  if (match == null) {
    return EpisodeInfo(showTitle: raw.trim());
  }
  final showTitle = raw.substring(0, match.start).trim();
  final season    = int.tryParse(match.group(1)!);
  final episode   = int.tryParse(match.group(2)!);
  return EpisodeInfo(
    showTitle: showTitle.isEmpty ? raw.trim() : showTitle,
    season: season,
    episode: episode,
    code: match.group(0),
  );
}

/// Short display code for an episode row, e.g. "S05E02 - Ozymandias".
/// Falls back to the full title if no season/episode code was found.
String episodeDisplayCode(String raw) {
  final m = _seCodePattern.firstMatch(raw);
  if (m == null) return raw;
  return raw.substring(m.start).trim();
}
