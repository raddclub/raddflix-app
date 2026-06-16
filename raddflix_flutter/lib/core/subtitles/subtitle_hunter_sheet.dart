import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/subtitles/subtitle_hunter.dart';

/// Bottom sheet shown when user taps "Search Device" from the subtitle panel.
///
/// 1. Launches [SubtitleHunter.findForVideo] in the background.
/// 2. Shows ranked results with confidence bar, archive badge, preview lines.
/// 3. One-tap loads the chosen subtitle into the player.
/// 4. URL field to download and load subtitles from the web.
class SubtitleHunterSheet extends StatefulWidget {
  final String videoPath;
  final Future<void> Function(String filePath) onLoad;

  const SubtitleHunterSheet({
    super.key,
    required this.videoPath,
    required this.onLoad,
  });

  @override
  State<SubtitleHunterSheet> createState() => _SubtitleHunterSheetState();
}

class _SubtitleHunterSheetState extends State<SubtitleHunterSheet> {
  List<SubtitleMatch>? _results;
  bool _searching = true;
  String? _error;

  // URL download
  final _urlCtrl = TextEditingController();
  bool _downloading = false;
  String? _downloadError;

  // Expanded preview index
  int? _expandedIdx;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() { _searching = true; _error = null; });
    try {
      final results = await SubtitleHunter.findForVideo(widget.videoPath);
      if (mounted) setState(() { _results = results; _searching = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _searching = false; });
    }
  }

  Future<void> _loadMatch(SubtitleMatch match) async {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    await widget.onLoad(match.path);
  }

  Future<void> _downloadUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _downloading = true; _downloadError = null; });
    try {
      final tmpDir  = await getTemporaryDirectory();
      final cacheDir = Directory('${tmpDir.path}/subtitles');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      final filename = url.contains('/') ? url.split('/').last.split('?').first : 'subtitle.srt';
      final outPath  = '${cacheDir.path}/$filename';
      await Dio().download(url, outPath);
      if (mounted) {
        Navigator.of(context).pop();
        await widget.onLoad(outPath);
      }
    } catch (e) {
      if (mounted) setState(() { _downloadError = 'Download failed: ${e.toString()}'; _downloading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: const BoxDecoration(
        color: Color(0xF2101018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          Flexible(child: _buildBody()),
          _buildUrlSection(),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildHandle() => Center(
    child: Container(
      width: 36, height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 4, 14, 12),
    child: Row(children: [
      const Icon(Icons.search_rounded, color: Color(0xFF4DB6FF), size: 22),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          'Subtitle Hunter',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      if (_searching)
        const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4DB6FF)),
        )
      else
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
          onPressed: _search,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Rescan',
        ),
      const SizedBox(width: 12),
      IconButton(
        icon: const Icon(Icons.close, color: Colors.white38, size: 20),
        onPressed: () => Navigator.of(context).pop(),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    ]),
  );

  Widget _buildBody() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Color(0xFF4DB6FF)),
            SizedBox(height: 16),
            Text(
              'Scanning device storage…',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            SizedBox(height: 6),
            Text(
              'Checking ZIP archives too',
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ]),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $_error', style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
      );
    }

    final results = _results ?? [];
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.subtitles_off_rounded, color: Colors.white24, size: 48),
            SizedBox(height: 14),
            Text(
              'No subtitle files found on device',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            SizedBox(height: 6),
            Text(
              'Use the URL field below to load from the web',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ]),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
      itemBuilder: (_, i) => _buildMatchTile(results[i], i),
    );
  }

  Widget _buildMatchTile(SubtitleMatch match, int idx) {
    final isExpanded = _expandedIdx == idx;
    final pct = match.score;
    final barColor = pct >= 70
        ? const Color(0xFF43A047)   // green
        : pct >= 45
            ? const Color(0xFFFFB300) // amber
            : const Color(0xFFEF5350); // red

    return InkWell(
      onTap: () => setState(() => _expandedIdx = isExpanded ? null : idx),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  // Archive badge
                  if (match.archiveSource != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B1FA2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('ZIP', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      match.label,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                // Folder / archive source
                Text(
                  match.archiveSource != null
                      ? 'From: ${match.archiveSource}'
                      : _shortenPath(match.path),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // Confidence bar
                Row(children: [
                  SizedBox(
                    width: 100,
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$pct% match',
                    style: TextStyle(color: barColor, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            // Load button
            ElevatedButton(
              onPressed: () => _loadMatch(match),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Load', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
          // Expandable preview
          if (isExpanded && match.preview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PREVIEW',
                    style: TextStyle(color: Colors.white30, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...match.preview.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        line,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildUrlSection() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Load from URL',
          style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://… .srt / .ass / .vtt',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4DB6FF)),
                ),
                suffixIcon: _downloading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4DB6FF))),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_rounded, color: Color(0xFF4DB6FF), size: 20),
                        onPressed: _downloadUrl,
                        tooltip: 'Download & load',
                      ),
              ),
              onSubmitted: (_) => _downloadUrl(),
            ),
          ),
        ]),
        if (_downloadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _downloadError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ),
      ]),
    );
  }

  String _shortenPath(String fullPath) {
    final parts = fullPath.split('/');
    if (parts.length <= 3) return fullPath;
    return '…/${parts.skip(parts.length - 2).join('/')}';
  }
}
