/// Phase F2 — Word Definition Bottom Sheet
/// Shows Urdu translation, Roman Urdu, part-of-speech, example sentence,
/// and a "Save Word" button that stores to the user's vocabulary.
library word_definition_sheet;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../core/player/word_dict.dart';

/// Shows the definition sheet for [word]. Returns a Future so the caller
/// can await dismissal if needed.
Future<void> showWordDefinition(BuildContext context, String word,
    {Color accentColor = const Color(0xFFD4784A)}) {
  final entry = WordDict.instance.lookup(word);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _WordDefinitionSheet(
      rawWord: word,
      entry: entry,
      accentColor: accentColor,
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

  const _WordDefinitionSheet({
    required this.rawWord,
    required this.entry,
    required this.accentColor,
  });

  @override
  State<_WordDefinitionSheet> createState() => _WordDefinitionSheetState();
}

class _WordDefinitionSheetState extends State<_WordDefinitionSheet> {
  bool _saved = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.entry != null) {
      _saved = WordDict.instance.isSaved(widget.rawWord);
    }
  }

  Future<void> _toggleSave() async {
    if (widget.entry == null) return;
    setState(() => _loading = true);
    if (_saved) {
      await WordDict.instance.unsaveWord(widget.entry!.word);
    } else {
      await WordDict.instance.saveWord(widget.entry!);
    }
    if (mounted) setState(() { _saved = !_saved; _loading = false; });
    HapticFeedback.lightImpact();
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
      child: widget.entry == null
          ? _buildNotFound()
          : _buildEntry(widget.entry!),
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
        const Text(
          'Word not found in offline dictionary',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          'Only common English words are included',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ]),
    );
  }

  // ── Full entry ─────────────────────────────────────────────────────────────
  Widget _buildEntry(WordEntry e) {
    final posLabel = _posLabels[e.pos] ?? e.pos.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Handle + save button row
        Row(children: [
          Expanded(child: Center(child: _handle())),
          // Save button
          GestureDetector(
            onTap: _loading ? null : _toggleSave,
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
              child: _loading
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

        // English word + POS chip
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(
            e.word,
            style: const TextStyle(
              color: Colors.white, fontSize: 28,
              fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(width: 10),
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

        const SizedBox(height: 16),

        // Urdu translation (large, RTL)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'اردو',
                style: TextStyle(color: Colors.white38, fontSize: 11,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Directionality(
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
        ),

        const SizedBox(height: 10),

        // Roman Urdu row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Icons.translate_rounded,
                color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            const Text('Roman Urdu: ',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            Text(
              e.roman,
              style: const TextStyle(
                color: Colors.white70, fontSize: 13,
                fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
            ),
          ]),
        ),

        // Example sentence (if available)
        if (e.example.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.format_quote_rounded,
                  color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.example,
                  style: const TextStyle(
                    color: Colors.white60, fontSize: 13,
                    fontStyle: FontStyle.italic),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 4),
        // Attribution hint
        const Center(
          child: Text(
            'Offline dictionary · tap word again to dismiss',
            style: TextStyle(color: Colors.white24, fontSize: 10),
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
