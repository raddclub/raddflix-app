/// Phase F2 / BB10 — Word Definition Bottom Sheet
/// Shows Urdu/translated meaning, Roman Urdu, part-of-speech, definitions,
/// pronunciation audio, context sentence, and save/unsave button.
/// Falls back to online lookup (dictionaryapi.dev + MyMemory) when the offline
/// dictionary doesn't have the word.
library word_definition_sheet;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/constants.dart';
import '../../core/player/word_dict.dart';

/// Shows the definition sheet for [word].
/// [contextLine]       — the subtitle sentence the user was reading (shown at top).
/// [dictTargetLanguage] — ISO 639-1 code for the translation target (default 'ur').
Future<void> showWordDefinition(
  BuildContext context,
  String word, {
  Color accentColor = const Color(0xFFD4784A),
  String contextLine = '',
  String dictTargetLanguage = 'ur',
}) {
  final offlineEntry = WordDict.instance.lookup(word);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _WordDefinitionSheet(
      rawWord: word,
      entry: offlineEntry,
      accentColor: accentColor,
      contextLine: contextLine,
      dictTargetLanguage: dictTargetLanguage,
    ),
  );
}

// ── POS labels ────────────────────────────────────────────────────────────────
const _posLabels = <String, String>{
  'n': 'Noun', 'v': 'Verb', 'adj': 'Adjective', 'adv': 'Adverb',
  'pron': 'Pronoun', 'prep': 'Preposition', 'conj': 'Conjunction',
  'interj': 'Interjection', 'det': 'Determiner',
};

// ─────────────────────────────────────────────────────────────────────────────
class _WordDefinitionSheet extends StatefulWidget {
  final String rawWord;
  final WordEntry? entry;
  final Color accentColor;
  final String contextLine;
  final String dictTargetLanguage;

  const _WordDefinitionSheet({
    required this.rawWord,
    required this.entry,
    required this.accentColor,
    required this.contextLine,
    required this.dictTargetLanguage,
  });

  @override
  State<_WordDefinitionSheet> createState() => _WordDefinitionSheetState();
}

class _WordDefinitionSheetState extends State<_WordDefinitionSheet> {
  // Resolved entry (offline or online).
  WordEntry? _resolvedEntry;
  bool _loadingOnline = false;
  bool _onlineFailed  = false;
  bool _saved = false;
  bool _saveBusy = false;
  bool _speaking = false;

  late final FlutterTts _tts;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    _tts.setLanguage('en-US');

    if (widget.entry != null) {
      // Offline hit — use immediately.
      _resolvedEntry = widget.entry;
      _saved = WordDict.instance.isSaved(widget.rawWord);
    } else {
      // Check session cache first (instant if already looked up this session).
      final cached = WordDict.instance.getCachedOnlineEntry(widget.rawWord);
      if (WordDict.instance.hasOnlineCacheHit(widget.rawWord)) {
        _resolvedEntry = cached;
        if (cached != null) _saved = WordDict.instance.isSaved(widget.rawWord);
      } else {
        // Not in cache — kick off online lookup.
        _loadingOnline = true;
        _startOnlineLookup();
      }
    }
  }

  Future<void> _startOnlineLookup() async {
    final result = await WordDict.instance.lookupOnline(
      widget.rawWord,
      targetLang: widget.dictTargetLanguage,
    );
    if (!mounted) return;
    setState(() {
      _resolvedEntry = result;
      _loadingOnline = false;
      _onlineFailed  = result == null;
      if (result != null) _saved = WordDict.instance.isSaved(widget.rawWord);
    });
  }

  Future<void> _toggleSave() async {
    final entry = _resolvedEntry;
    if (entry == null) return;
    setState(() => _saveBusy = true);
    if (_saved) {
      await WordDict.instance.unsaveWord(entry.word);
    } else {
      await WordDict.instance.saveWord(entry);
    }
    HapticFeedback.lightImpact();
    if (mounted) setState(() { _saved = !_saved; _saveBusy = false; });
  }

  Future<void> _speak() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    HapticFeedback.selectionClick();
    await _tts.speak(widget.rawWord);
    if (mounted) setState(() => _speaking = false);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingOnline) return _buildLoading();
    if (_resolvedEntry == null) return _buildNotFound();
    return _buildEntry(_resolvedEntry!);
  }

  // ── Loading state ──────────────────────────────────────────────────────────
  Widget _buildLoading() {
    final clean = widget.rawWord.toLowerCase().replaceAll(RegExp(r"[^a-zA-Z']"), '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        const SizedBox(height: 24),
        Text(
          '"$clean"',
          style: const TextStyle(color: Colors.white,
              fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5, color: widget.accentColor),
        ),
        const SizedBox(height: 12),
        const Text(
          'Looking up definition…',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ]),
    );
  }

  // ── Not found state ────────────────────────────────────────────────────────
  Widget _buildNotFound() {
    final clean = widget.rawWord
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-zA-Z']"), '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        const SizedBox(height: 20),
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.search_off_rounded,
              color: Colors.white38, size: 28),
        ),
        const SizedBox(height: 14),
        Text(
          '"$clean"',
          style: const TextStyle(color: Colors.white,
              fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _onlineFailed
              ? 'No definition found'
              : 'Word not in dictionary',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          _onlineFailed
              ? 'Could not reach dictionary — check connection'
              : 'Only common English words are included',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ]),
    );
  }

  // ── Full entry ─────────────────────────────────────────────────────────────
  Widget _buildEntry(WordEntry e) {
    final posLabel = _posLabels[e.pos] ?? e.pos.toUpperCase();
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Handle + save button row ────────────────────────────────────
          Row(children: [
            Expanded(child: Center(child: _handle())),
            // Pronunciation button
            GestureDetector(
              onTap: _speak,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _speaking
                      ? widget.accentColor.withOpacity(0.18)
                      : Colors.white10,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  color: _speaking ? widget.accentColor : Colors.white54,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Save button
            GestureDetector(
              onTap: _saveBusy ? null : _toggleSave,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _saved
                      ? widget.accentColor.withOpacity(0.18)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _saved ? widget.accentColor : Colors.white24,
                    width: 1)),
                child: _saveBusy
                    ? SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: widget.accentColor))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          _saved ? Icons.bookmark_rounded
                                  : Icons.bookmark_add_outlined,
                          color: _saved ? widget.accentColor : Colors.white54,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _saved ? 'Saved' : 'Save',
                          style: TextStyle(
                            color: _saved ? widget.accentColor : Colors.white54,
                            fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ]),
              ),
            ),
          ]),

          const SizedBox(height: 18),

          // ── Context sentence (subtitle line user was reading) ────────────
          if (widget.contextLine.isNotEmpty)
            _buildContextSentence(e.word),

          // ── English word + POS chip ─────────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(
              e.word,
              style: const TextStyle(
                color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
            if (e.phonetic != null && e.phonetic!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                e.phonetic!,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 14,
                    fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: widget.accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: widget.accentColor.withOpacity(0.4), width: 1)),
              child: Text(
                posLabel,
                style: TextStyle(
                  color: widget.accentColor, fontSize: 11,
                  fontWeight: FontWeight.w600, letterSpacing: 0.3),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // ── Urdu / translated meaning ────────────────────────────────────
          if (e.urdu.isNotEmpty)
            _buildMeaningBlock(e),

          const SizedBox(height: 10),

          // ── Roman Urdu row (offline entries only) ───────────────────────
          if (e.roman.isNotEmpty && !e.isOnline)
            _buildRomanRow(e.roman),

          // ── Online definitions ───────────────────────────────────────────
          if (e.isOnline && e.definitions.isNotEmpty) ...[
            const SizedBox(height: 2),
            _buildDefinitions(e.definitions),
          ],

          // ── Example sentence (offline entries) ──────────────────────────
          if (!e.isOnline && e.example.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildExampleRow(e.example),
          ],

          const SizedBox(height: 8),

          // ── Source attribution ───────────────────────────────────────────
          Center(
            child: Text(
              e.isOnline
                  ? 'dictionaryapi.dev · MyMemory translation'
                  : 'Offline dictionary · tap word again to dismiss',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Context sentence widget ────────────────────────────────────────────────
  Widget _buildContextSentence(String word) {
    final line = widget.contextLine;
    final lower = line.toLowerCase();
    final wordLower = word.toLowerCase();
    final idx = lower.indexOf(wordLower);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'From the subtitle',
              style: TextStyle(color: Colors.white30, fontSize: 10,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            idx >= 0
                ? RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13, height: 1.4),
                      children: [
                        TextSpan(text: line.substring(0, idx)),
                        TextSpan(
                          text: line.substring(idx, idx + word.length),
                          style: TextStyle(
                            color: widget.accentColor,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: widget.accentColor,
                          ),
                        ),
                        TextSpan(text: line.substring(idx + word.length)),
                      ],
                    ),
                  )
                : Text(
                    line,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 13, height: 1.4),
                  ),
          ],
        ),
      ),
    );
  }

  // ── Meaning block (Urdu / translation) ────────────────────────────────────
  Widget _buildMeaningBlock(WordEntry e) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            e.isOnline ? 'Translation' : 'اردو',
            style: const TextStyle(color: Colors.white38, fontSize: 11,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          e.isOnline
              ? Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    e.urdu,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                )
              : Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    e.urdu,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  // ── Roman Urdu row ─────────────────────────────────────────────────────────
  Widget _buildRomanRow(String roman) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.translate_rounded, color: Colors.white38, size: 16),
        const SizedBox(width: 8),
        const Text('Roman Urdu: ',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
        Text(
          roman,
          style: const TextStyle(
            color: Colors.white70, fontSize: 13,
            fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }

  // ── Online definitions list ────────────────────────────────────────────────
  Widget _buildDefinitions(List<String> defs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Definitions',
          style: TextStyle(color: Colors.white38, fontSize: 11,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < defs.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: TextStyle(
                      color: widget.accentColor.withOpacity(0.7),
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    defs[i],
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (i < defs.length - 1) const SizedBox(height: 5),
        ],
      ],
    );
  }

  // ── Example sentence ───────────────────────────────────────────────────────
  Widget _buildExampleRow(String example) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.format_quote_rounded, color: Colors.white38, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            example,
            style: const TextStyle(
              color: Colors.white60, fontSize: 13,
              fontStyle: FontStyle.italic),
          ),
        ),
      ]),
    );
  }

  Widget _handle() => Container(
    width: 40, height: 4,
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(2)),
  );
}
