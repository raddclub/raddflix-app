import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ── Public result type ────────────────────────────────────────────────────────

/// A single subtitle file candidate found by the hunter.
class SubtitleMatch {
  final String path;          // absolute path to file (may be in temp cache for zips)
  final String label;         // display filename
  final String? archiveSource;// non-null when extracted from a .zip archive
  final int score;            // 0-100 confidence
  final List<String> preview; // first ≤5 text lines from the file

  const SubtitleMatch({
    required this.path,
    required this.label,
    this.archiveSource,
    required this.score,
    required this.preview,
  });
}

// ── Cache entry ───────────────────────────────────────────────────────────────

class _CachedResult {
  final DateTime timestamp;
  final List<SubtitleMatch> results;
  const _CachedResult({required this.timestamp, required this.results});
}

// ── Public API ────────────────────────────────────────────────────────────────

class SubtitleHunter {
  static const _cacheTtl = Duration(seconds: 60);
  static final Map<String, _CachedResult> _cache = {};

  /// Walk device storage and return top-5 subtitle candidates for [videoPath].
  /// Heavy work runs in a [compute] isolate — safe to call from UI.
  static Future<List<SubtitleMatch>> findForVideo(String videoPath) async {
    final now = DateTime.now();
    final cached = _cache[videoPath];
    if (cached != null && now.difference(cached.timestamp) < _cacheTtl) {
      return cached.results;
    }

    final roots = await _roots();
    final tmpDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tmpDir.path}/subtitles');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

    final params = _Params(
      videoPath: videoPath,
      roots: roots.map((d) => d.path).toList(),
      cacheDir: cacheDir.path,
    );

    final results = await compute(_runIsolate, params);
    _cache[videoPath] = _CachedResult(timestamp: now, results: results);
    return results;
  }

  static Future<List<Directory>> _roots() async {
    final out = <Directory>[];
    try { out.add(await getApplicationDocumentsDirectory()); } catch (_) {}
    try {
      final ext = await getExternalStorageDirectories();
      if (ext != null) out.addAll(ext);
    } catch (_) {}
    for (final path in ['/storage/emulated/0', '/sdcard']) {
      final d = Directory(path);
      if (d.existsSync()) out.add(d);
    }
    // Deduplicate by path
    final seen = <String>{};
    return out.where((d) => seen.add(d.path)).toList();
  }
}

// ── Isolate parameter bag ─────────────────────────────────────────────────────

class _Params {
  final String videoPath;
  final List<String> roots;
  final String cacheDir;
  const _Params({required this.videoPath, required this.roots, required this.cacheDir});
}

// ── Top-level isolate entry ───────────────────────────────────────────────────

List<SubtitleMatch> _runIsolate(_Params params) {
  final videoBase  = p.basenameWithoutExtension(params.videoPath).toLowerCase();
  final videoToks  = _tokenize(videoBase);
  final candidates = <SubtitleMatch>[];
  final seen       = <String>{};

  for (final root in params.roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    try {
      _walk(dir, videoBase, videoToks, params.cacheDir, candidates, seen);
    } catch (_) {}
    if (candidates.length >= 40) break; // enough to sort from
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.where((m) => m.score >= 25).take(5).toList();
}

// ── Recursive walker ──────────────────────────────────────────────────────────

const _subExts     = {'.srt', '.ass', '.ssa', '.vtt', '.sub', '.sbv'};
const _skipDirs    = {'Android', 'proc', 'sys', 'dev', 'acct', 'obb'};

void _walk(
  Directory dir,
  String videoBase,
  List<String> videoToks,
  String cacheDir,
  List<SubtitleMatch> out,
  Set<String> seen,
) {
  List<FileSystemEntity> entries;
  try { entries = dir.listSync(recursive: false); } catch (_) { return; }

  for (final e in entries) {
    if (e is File) {
      if (!seen.add(e.path)) continue;
      final ext = p.extension(e.path).toLowerCase();
      if (_subExts.contains(ext)) {
        final score = _score(
          p.basenameWithoutExtension(e.path).toLowerCase(),
          videoBase, videoToks,
        );
        if (score >= 25) {
          out.add(SubtitleMatch(
            path: e.path,
            label: p.basename(e.path),
            score: score,
            preview: _preview(e.path),
          ));
        }
      } else if (ext == '.zip') {
        _scanZip(e.path, videoBase, videoToks, cacheDir, out, seen);
      }
    } else if (e is Directory) {
      final name = p.basename(e.path);
      if (!name.startsWith('.') && !_skipDirs.contains(name)) {
        try { _walk(e, videoBase, videoToks, cacheDir, out, seen); } catch (_) {}
      }
    }
    if (out.length >= 40) return;
  }
}

// ── ZIP extraction ────────────────────────────────────────────────────────────

void _scanZip(
  String zipPath,
  String videoBase,
  List<String> videoToks,
  String cacheDir,
  List<SubtitleMatch> out,
  Set<String> seen,
) {
  try {
    final bytes   = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final ext = p.extension(file.name).toLowerCase();
      if (!_subExts.contains(ext)) continue;
      final baseName = p.basenameWithoutExtension(file.name);
      final score    = _score(baseName.toLowerCase(), videoBase, videoToks);
      if (score < 25) continue;
      final outPath  = '$cacheDir/${p.basename(file.name)}';
      if (!seen.add(outPath)) continue;
      try {
        File(outPath).writeAsBytesSync(file.content as List<int>);
        out.add(SubtitleMatch(
          path: outPath,
          label: p.basename(file.name),
          archiveSource: p.basename(zipPath),
          score: score,
          preview: _preview(outPath),
        ));
      } catch (_) {}
    }
  } catch (_) {}
}

// ── Scoring: token overlap (70%) + Levenshtein similarity (30%) ───────────────

int _score(String candidate, String videoBase, List<String> videoToks) {
  if (candidate.isEmpty || videoBase.isEmpty) return 0;
  final cToks   = _tokenize(candidate);
  final common  = videoToks.toSet().intersection(cToks.toSet()).length;
  final overlap = videoToks.isEmpty ? 0.0 : common / videoToks.length;
  final lev     = _levenshtein(candidate, videoBase);
  final maxLen  = candidate.length > videoBase.length ? candidate.length : videoBase.length;
  final levSim  = maxLen == 0 ? 1.0 : 1.0 - (lev / maxLen);
  return ((overlap * 0.70 + levSim * 0.30) * 100).round().clamp(0, 100);
}

List<String> _tokenize(String s) => s
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.length > 1)
    .toList();

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final prev = List<int>.generate(b.length + 1, (j) => j);
  final curr = List<int>.filled(b.length + 1, 0);
  for (int i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (int j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev.setAll(0, curr);
  }
  return prev[b.length];
}

// ── Subtitle text preview ─────────────────────────────────────────────────────

List<String> _preview(String filePath) {
  try {
    final lines  = File(filePath).readAsStringSync().split('\n');
    final result = <String>[];
    for (final raw in lines) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(t)) continue;           // index number
      if (t.contains('-->')) continue;                       // timing line
      // Strip ASS/SSA override tags and HTML tags
      final clean = t
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (clean.isNotEmpty) result.add(clean);
      if (result.length >= 5) break;
    }
    return result;
  } catch (_) {
    return [];
  }
}
