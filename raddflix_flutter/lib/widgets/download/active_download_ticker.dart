// lib/widgets/download/active_download_ticker.dart
//
// DOWNLOAD-TAB-V2: compact live ticker showing in-flight downloads with
// progress %, speed and ETA — always visible near the top of the Download
// tab so the user never has to dig for "is it still downloading?" (pattern
// borrowed from 1DM+ and Netflix's download manager).
//
// Reads directly from DownloadsState.activeProgress/speedLabels/etaLabels —
// no schema change needed, those are already tracked per-download.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/design/app_icons.dart';
import '../../core/theme/radd_theme.dart';
import '../../providers/downloads_provider.dart';

class ActiveDownloadTicker extends StatelessWidget {
  final DownloadsState state;
  final String Function(String fileId) titleFor;
  final VoidCallback Function(String fileId) onCancel;

  const ActiveDownloadTicker({
    super.key,
    required this.state,
    required this.titleFor,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final activeIds = state.activeProgress.keys.toList();
    if (activeIds.isEmpty) return const SizedBox.shrink();
    final t = RaddTheme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: activeIds.take(3).map((id) {
          final progress = state.progressOf(id);
          final speed    = state.speedOf(id);
          final eta      = state.etaOf(id);
          final title    = titleFor(id);
          final queuePos = state.queuePositionOf(id);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(AppIcons.cloudDownload, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: t.card,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%'
                  '${speed.isNotEmpty ? "  ·  $speed" : ""}'
                  '${eta.isNotEmpty ? "  ·  $eta" : ""}'
                  '${queuePos > 1 ? "  ·  #$queuePos in queue" : ""}',
                  style: TextStyle(color: t.textMuted, fontSize: 10),
                ),
              ])),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onCancel(id),
                child: Icon(AppIcons.stopIcon, size: 16, color: AppColors.error.withOpacity(0.75)),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}
