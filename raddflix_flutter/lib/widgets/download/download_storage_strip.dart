// lib/widgets/download/download_storage_strip.dart
//
// DOWNLOAD-TAB-V2: always-visible storage summary strip for the Download tab.
// Shows total stored size, item counts and free device space at a glance —
// inspired by 1DM+ / Netflix, which surface storage state without requiring
// the user to open a separate menu.

import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/design/app_icons.dart';
import '../../core/theme/radd_theme.dart';

class DownloadStorageStrip extends StatelessWidget {
  final int totalBytes;
  final int completedCount;
  final int totalCount;
  final int activeCount;
  final double? freeMB;

  const DownloadStorageStrip({
    super.key,
    required this.totalBytes,
    required this.completedCount,
    required this.totalCount,
    required this.activeCount,
    this.freeMB,
  });

  static String _fmtSize(int bytes) {
    if (bytes == 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final freeStr = freeMB != null
        ? (freeMB! >= 1024
            ? '${(freeMB! / 1024).toStringAsFixed(1)} GB free'
            : '${freeMB!.toStringAsFixed(0)} MB free')
        : null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withOpacity(0.12),
            border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          ),
          child: Icon(AppIcons.downloadDone, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_fmtSize(totalBytes),
                style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(' downloaded', style: TextStyle(color: t.textMuted, fontSize: 12)),
            const Spacer(),
            if (activeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$activeCount loading', style: TextStyle(
                    color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Text('$completedCount done', style: TextStyle(color: t.textMuted, fontSize: 11)),
            Text(' · ', style: TextStyle(color: t.textMuted)),
            Text('$totalCount total', style: TextStyle(color: t.textMuted, fontSize: 11)),
            if (freeStr != null) ...[
              Text(' · ', style: TextStyle(color: t.textMuted)),
              Text(freeStr, style: TextStyle(
                  color: (freeMB ?? 999) < 200
                      ? AppColors.error
                      : (freeMB ?? 999) < 500
                          ? AppColors.warning
                          : t.textMuted,
                  fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ]),
        ])),
      ]),
    );
  }
}
