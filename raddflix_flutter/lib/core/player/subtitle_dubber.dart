// subtitle_dubber.dart — Phase 59: Android TTS-based AI Dubbing (Method 1)
// Parses SRT, synthesizes each line via flutter_tts synthesizeToFile(),
// then assembles a single WAV with silence gaps matching subtitle timestamps.
// Result: music+effects (via MPV karaoke filter on original) + dubbed voices (this WAV).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────
class SrtEntry {
  final Duration start;
  final Duration end;
  final String text;
  const SrtEntry(this.start, this.end, this.text);
}

class _AudioClip {
  final Duration start;
  final Duration end;
  final Uint8List pcm;
  const _AudioClip(this.start, this.end, this.pcm);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SubtitleDubber
// ─────────────────────────────────────────────────────────────────────────────
class SubtitleDubber {

  // ── SRT parser ─────────────────────────────────────────────────────────────
  static List<SrtEntry> parseSrt(String content) {
    final entries = <SrtEntry>[];
    final blocks  = content.trim().split(RegExp(r'\r?\n\s*\r?\n'));
    for (final block in blocks) {
      final lines = block.trim().split(RegExp(r'\r?\n'));
      if (lines.length < 2) continue;
      String? timeLine;
      int textStart = 0;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLine  = lines[i].trim();
          textStart = i + 1;
          break;
        }
      }
      if (timeLine == null || textStart >= lines.length) continue;
      final halves = timeLine.split('-->');
      if (halves.length < 2) continue;
      final start = _parseTime(halves[0].trim());
      final end   = _parseTime(halves[1].trim());
      if (start == null || end == null) continue;
      final raw  = lines.sublist(textStart).join(' ');
      final text = raw
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\{[^\}]*\}'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;
      entries.add(SrtEntry(start, end, text));
    }
    return entries;
  }

  static Duration? _parseTime(String s) {
    final clean = s.replaceAll(',', '.');
    final parts = clean.split(':');
    if (parts.length < 3) return null;
    try {
      final h       = int.parse(parts[0].trim());
      final m       = int.parse(parts[1].trim());
      final secPart = parts[2].trim().split('.');
      final sec     = int.parse(secPart[0]);
      final ms      = secPart.length > 1
          ? int.parse(secPart[1].padRight(3, '0').substring(0, 3))
          : 0;
      return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
    } catch (_) { return null; }
  }

  // ── WAV header reader ───────────────────────────────────────────────────────
  static Map<String, int>? _readWavHeader(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;
    int pos = 12;
    while (pos + 8 <= bytes.length) {
      final id   = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = _u32(bytes, pos + 4);
      if (id == 'fmt ' && size >= 16) {
        final channels      = _u16(bytes, pos + 10);
        final sampleRate    = _u32(bytes, pos + 12);
        final bitsPerSample = _u16(bytes, pos + 22);
        int dPos = pos + 8 + size;
        int dataOffset = dPos + 8;
        while (dPos + 8 <= bytes.length) {
          final did = String.fromCharCodes(bytes.sublist(dPos, dPos + 4));
          if (did == 'data') { dataOffset = dPos + 8; break; }
          dPos += 8 + _u32(bytes, dPos + 4);
        }
        return {'sampleRate': sampleRate, 'channels': channels,
                'bitsPerSample': bitsPerSample, 'dataOffset': dataOffset};
      }
      pos += 8 + size;
    }
    return null;
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o+1] << 8) | (b[o+2] << 16) | (b[o+3] << 24);

  // ── WAV builder ─────────────────────────────────────────────────────────────
  static Uint8List _buildWav(Uint8List pcm, int sr, int ch, int bps) {
    final byteRate   = sr * ch * (bps ~/ 8);
    final blockAlign = ch * (bps ~/ 8);
    final hdr        = BytesBuilder();
    void str(String s) { for (final c in s.codeUnits) hdr.addByte(c); }
    void u16(int v)    { hdr.add([v & 0xFF, (v >> 8) & 0xFF]); }
    void u32(int v)    { hdr.add([v & 0xFF, (v>>8) & 0xFF, (v>>16) & 0xFF, (v>>24) & 0xFF]); }
    str('RIFF'); u32(36 + pcm.length); str('WAVE');
    str('fmt '); u32(16); u16(1); u16(ch); u32(sr); u32(byteRate); u16(blockAlign); u16(bps);
    str('data'); u32(pcm.length);
    final out = BytesBuilder();
    out.add(hdr.toBytes());
    out.add(pcm);
    return out.toBytes();
  }

  // ── Main entry point ────────────────────────────────────────────────────────
  /// Generates a dubbed WAV file from [entries] using on-device TTS.
  /// Each synthesized clip is placed at its subtitle timestamp; gaps are silence.
  /// Returns the file path on success, null on failure.
  static Future<String?> generateDub({
    required List<SrtEntry>    entries,
    required String            language,      // 'ur-PK' | 'hi-IN'
    required Duration          totalDuration,
    required void Function(int current, int total, String status) onProgress,
    required String            cacheKey,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final dubDir = Directory('${tmpDir.path}/radd_dub');
    if (!dubDir.existsSync()) dubDir.createSync(recursive: true);

    // BB2: use ApplicationDocumentsDirectory — always writable without
    // WRITE_EXTERNAL_STORAGE permission, avoids null on low-RAM devices that
    // have no external storage. flutter_tts synthesizeToFile accepts a full
    // absolute path on the versions we target (flutter_tts ≥ 3.x).
    final ttsDir = await getApplicationDocumentsDirectory();

    final outPath = '${dubDir.path}/dub_$cacheKey.wav';
    // Fix #12: verify the cached file is non-empty. A zero-byte file left by
    // a previous crash would be returned as a valid hit and play as silence.
    final cachedFile = File(outPath);
    if (cachedFile.existsSync() && cachedFile.lengthSync() > 100) return outPath; // cache hit

    final tts = FlutterTts();
    // BB2 fix 1: target Google TTS explicitly. Samsung/Xiaomi built-in engines
    // may report voices as available but fail to synthesize to file.
    try { await tts.setEngine('com.google.android.tts'); } catch (_) {}

    // BB2 fix 2: getVoices() returns the voices that are actually installed.
    // setLanguage() can return LANG_COUNTRY_AVAILABLE (0) even when the voice
    // pack for that locale has not been downloaded — the negative-value check
    // alone was insufficient. Filter installed voices by locale before committing.
    final rawVoices = await tts.getVoices;
    final voicesList = rawVoices is List ? rawVoices : <dynamic>[];
    final localeVariants = <String>[
      language,                         // e.g. 'ur-PK'
      language.replaceAll('-', '_'),    // e.g. 'ur_PK' (Xiaomi format)
      language.split('-').first,        // e.g. 'ur'  (base fallback)
    ];
    final langAvailable = voicesList.any((v) {
      final locale = (v is Map ? (v['locale'] ?? v['name'] ?? '') : v).toString();
      return localeVariants.any(
          (l) => locale.toLowerCase().startsWith(l.toLowerCase()));
    });
    if (!langAvailable) {
      onProgress(0, entries.length, 'LANG_NOT_INSTALLED');
      return null;
    }

    // Try locale variants in priority order; stop at the first accepted one.
    String? chosenLang;
    for (final loc in localeVariants) {
      final r = await tts.setLanguage(loc);
      if (r is! int || r >= 0) { chosenLang = loc; break; }
    }
    if (chosenLang == null) {
      onProgress(0, entries.length, 'LANG_NOT_INSTALLED');
      return null;
    }

    await tts.setSpeechRate(0.45);
    await tts.setVolume(1.0);
    await tts.setPitch(1.0);

    // C1+C2 fix: Run a preflight synthesis to confirm TTS can actually produce
    // audio before spending time on the full subtitle loop.
    final _preflightClip = '${ttsDir.path}/preflight_$cacheKey.wav';
    try {
      final _preflightResult = await tts.synthesizeToFile('test', _preflightClip);
      final _preflightFile = File(_preflightClip);
      if (_preflightResult != 1 ||
          !_preflightFile.existsSync() ||
          _preflightFile.lengthSync() < 50) {
        onProgress(0, entries.length, 'LANG_NOT_INSTALLED');
        return null;
      }
    } catch (_) {
      onProgress(0, entries.length, 'LANG_NOT_INSTALLED');
      return null;
    }

    // ── Phase 1: synthesize clips ────────────────────────────────────────────
    int sampleRate = 22050, channels = 1, bitsPerSample = 16;
    bool fmtOk = false;
    final clips = <_AudioClip>[];

    for (int i = 0; i < entries.length; i++) {
      onProgress(i + 1, entries.length, 'Synthesizing line ${i+1} of ${entries.length}');
      final entry    = entries[i];
      // BB2: pass full absolute path — flutter_tts ≥ 3.x writes to the
      // given path; ApplicationDocumentsDirectory is always writable.
      final clipPath = '${ttsDir.path}/clip_${cacheKey}_$i.wav';
      try {
        final r = await tts.synthesizeToFile(entry.text, clipPath);
        if (r != 1) continue;
        final f = File(clipPath);
        if (!f.existsSync()) continue;
        final bytes  = f.readAsBytesSync();
        final header = _readWavHeader(bytes);
        if (header == null) continue;
        if (!fmtOk) {
          sampleRate    = header['sampleRate']!;
          channels      = header['channels']!;
          bitsPerSample = header['bitsPerSample']!;
          fmtOk = true;
        }
        clips.add(_AudioClip(entry.start, entry.end, bytes.sublist(header['dataOffset']!)));
      } catch (e) {
        // Fix #11: log instead of silently swallowing — helps debug bad SRT/WAV.
        if (kDebugMode) print('[SubtitleDubber] clip $i synthesis error: $e'); // ignore: avoid_print
        continue;
      }
    }

    if (clips.isEmpty) return null;

    // ── Phase 2: assemble PCM buffer ─────────────────────────────────────────
    // Fix #23: report phase-2 start; without this the progress bar stalls at
    // 100% during PCM assembly which can take several seconds on long content.
    onProgress(clips.length, entries.length, 'Assembling ${clips.length}/${entries.length} clips...');
    final bytesPerSec = sampleRate * channels * (bitsPerSample ~/ 8);
    final minBytes    = clips.isNotEmpty
        ? ((clips.last.end.inMilliseconds / 1000.0 + 1.0) * bytesPerSec).ceil()
        : 0;
    final totalBytes  = math.max(
      (totalDuration.inMilliseconds / 1000.0 * bytesPerSec).ceil(), minBytes);
    // Fix #2: OOM guard — a 2-hr film @ 22 kHz/16-bit/mono is ~350 MB, enough
    // to crash entry-level 1-2 GB devices. Bail cleanly instead of OOM-killing.
    const maxDubBytes = 200 * 1024 * 1024; // 200 MB ceiling
    if (totalBytes > maxDubBytes) {
      onProgress(0, entries.length, 'Error: audio too large to dub on this device (>200 MB)');
      return null;
    }
    final buf = Uint8List(totalBytes); // silence = 0x00

    for (final c in clips) {
      final startByte = ((c.start.inMilliseconds / 1000.0) * bytesPerSec).round();
      final endByte   = ((c.end.inMilliseconds   / 1000.0) * bytesPerSec).round();
      final window    = (endByte - startByte).clamp(0, buf.length - startByte);
      final toCopy    = math.min(c.pcm.length, window);
      if (startByte >= 0 && startByte < buf.length && toCopy > 0) {
        buf.setRange(startByte, startByte + toCopy, c.pcm);
      }
    }

    // ── Phase 3: write WAV + clean clips ─────────────────────────────────────
    File(outPath).writeAsBytesSync(_buildWav(buf, sampleRate, channels, bitsPerSample));
    for (int i = 0; i < entries.length; i++) {
      final f = File('${ttsDir.path}/clip_${cacheKey}_$i.wav');
      if (f.existsSync()) f.deleteSync();
    }
    return outPath;
  }

  /// Delete cached dub WAV for [cacheKey].
  static Future<void> clearCache(String cacheKey) async {
    final tmpDir = await getTemporaryDirectory();
    final f = File('${tmpDir.path}/radd_dub/dub_$cacheKey.wav');
    if (f.existsSync()) f.deleteSync();
  }
}
