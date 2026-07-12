import 'dart:async';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../design_system/spacing/radd_space.dart';
import '../design_system/radius/radd_radius.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../core/api/api_client.dart';

class AdminQueueScreen extends StatefulWidget {
  const AdminQueueScreen({super.key});
  @override
  State<AdminQueueScreen> createState() => _AdminQueueScreenState();
}

class _AdminQueueScreenState extends State<AdminQueueScreen> {
  RaddTheme get t => RaddTheme.of(context);

  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res  = await ApiClient.instance.get(ApiPaths.adminQueue);
      final data = res.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _jobs    = List<Map<String, dynamic>>.from(data['jobs'] as List? ?? []);
          _loading = false;
          _error   = null;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AdminQueue] load error: $e');
      if (mounted) setState(() { _loading = false; _error = 'Could not load queue. Please try again.'; });
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'done':       return AppColors.success;
      case 'error':
      case 'failed':     return AppColors.error;
      case 'processing':
      case 'downloading':
      case 'uploading':  return AppColors.info;
      case 'queued':     return AppColors.warning;
      case 'cancelled':  return t.textMuted;
      default:           return t.textMuted;
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'done':        return AppIcons.successIcon;
      case 'error':
      case 'failed':      return AppIcons.errorIcon;
      case 'processing':
      case 'downloading': return AppIcons.downloadAction;
      case 'uploading':   return AppIcons.cloudUpload;
      case 'queued':      return AppIcons.clock;
      case 'cancelled':   return AppIcons.cancel;
      default:            return AppIcons.info;
    }
  }

  String _siteLabel(String? site) {
    const labels = {
      'auto':       'Auto',
      'direct':     'Direct URL',
      'upload':     'Upload',
      'vegamovies': 'VegaMovies',
      'katmoviehd': 'KatMovieHD',
      'ssrmovies':  'SSRMovies',
      'rogmovies':  'RogMovies',
    };
    return labels[site] ?? (site ?? '?');
  }

  String _relativeTime(dynamic ts) {
    if (ts == null) return '';
    // M-05: guard against millisecond timestamps from server.
    // If the server ever changes to return ms instead of seconds, ts * 1000
    // would overflow. A value > 1e12 is already in ms.
    final rawTs = ((ts as num?) ?? 0).toInt();
    final msTs  = rawTs > 1000000000000 ? rawTs : rawTs * 1000;
    final t  = DateTime.fromMillisecondsSinceEpoch(msTs);
    final d  = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final active   = _jobs.where((j) => !['done','error','failed','cancelled'].contains(j['status'])).toList();
    final finished = _jobs.where((j) =>  ['done','error','failed','cancelled'].contains(j['status'])).toList();

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App bar
          SliverAppBar(
            backgroundColor: t.bg,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            leading: IconButton(
              icon: Icon(AppIcons.back,
                  color: t.textPrimary, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text('Server Downloads',
                style: TextStyle(color: t.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                icon: Icon(AppIcons.refresh,
                    color: t.textMuted, size: 22),
                onPressed: _load,
              ),
              SizedBox(width: RaddSpace.sm),
            ],
          ),

          if (_loading && _jobs.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary)),
            )

          else if (_error != null && _jobs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(AppIcons.wifiOff,
                      color: t.textMuted, size: 48),
                  SizedBox(height: 12),
                  Text('Could not reach server',
                      style: TextStyle(color: t.textMuted, fontSize: 15)),
                  SizedBox(height: 6),
                  Text(_error!, style: TextStyle(
                      color: t.textMuted, fontSize: 11),
                      textAlign: TextAlign.center),
                  SizedBox(height: 20),
                  TextButton(onPressed: _load,
                      child: Text('Retry',
                          style: TextStyle(color: AppColors.primary))),
                ]),
              ),
            )

          else if (_jobs.isEmpty)
            SliverFillRemaining(
              child: Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(AppIcons.downloadDone,
                    color: t.textMuted, size: 52),
                SizedBox(height: 12),
                Text('No download jobs yet',
                    style: TextStyle(color: t.textMuted,
                        fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text('Use the admin panel to start a download.',
                    style: TextStyle(color: t.textMuted, fontSize: 13)),
              ])),
            )

          else ...[
            // Stats bar
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: RaddRadius.mdRadius,
                  border: Border.all(color: t.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(label: 'Active',
                        value: active.length.toString(),
                        color: AppColors.info),
                    _Stat(label: 'Done',
                        value: finished.where((j) => j['status'] == 'done').length.toString(),
                        color: AppColors.success),
                    _Stat(label: 'Failed',
                        value: finished.where((j) => ['error','failed'].contains(j['status'])).length.toString(),
                        color: AppColors.error),
                    _Stat(label: 'Total',
                        value: _jobs.length.toString(),
                        color: t.textMuted),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
            ),

            // Active jobs
            if (active.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text('ACTIVE', style: TextStyle(
                      color: t.textMuted, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _JobCard(
                    job: active[i],
                    statusColor: _statusColor(active[i]['status'] as String?),
                    statusIcon: _statusIcon(active[i]['status'] as String?),
                    siteLabel: _siteLabel(active[i]['site'] as String?),
                    relTime: _relativeTime(active[i]['updated_at']),
                  ).animate(delay: Duration(milliseconds: i * 40))
                      .fadeIn(duration: 300.ms)
                      .slideY(begin: 0.1, end: 0, duration: 300.ms),
                  childCount: active.length,
                ),
              ),
            ],

            // Finished jobs
            if (finished.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('RECENT', style: TextStyle(
                      color: t.textMuted, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _JobCard(
                    job: finished[i],
                    statusColor: _statusColor(finished[i]['status'] as String?),
                    statusIcon: _statusIcon(finished[i]['status'] as String?),
                    siteLabel: _siteLabel(finished[i]['site'] as String?),
                    relTime: _relativeTime(finished[i]['updated_at']),
                    dimmed: true,
                  ).animate(delay: Duration(milliseconds: i * 30))
                      .fadeIn(duration: 200.ms),
                  childCount: finished.length,
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(
          color: color, fontSize: 22, fontWeight: FontWeight.w800)),
      SizedBox(height: 2),
      Text(label, style: TextStyle(
          color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
    ]);
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final Color statusColor;
  final IconData statusIcon;
  final String siteLabel, relTime;
  final bool dimmed;

  const _JobCard({
    required this.job,
    required this.statusColor,
    required this.statusIcon,
    required this.siteLabel,
    required this.relTime,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    final status   = job['status'] as String? ?? '';
    final progress = (job['progress'] as num?)?.toDouble() ?? 0.0;
    final message  = job['message'] as String? ?? '';
    final movie    = job['movie']   as String? ?? 'Unknown';
    final isActive = !['done','error','failed','cancelled'].contains(status);

    return Opacity(
      opacity: dimmed ? 0.65 : 1.0,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RaddRadius.mdRadius,
          border: Border.all(
            color: isActive
                ? statusColor.withOpacity(0.35)
                : t.border,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withOpacity(0.15),
              ),
              child: Icon(statusIcon, color: statusColor, size: 16),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(movie, style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(status.toUpperCase(),
                        style: TextStyle(color: statusColor, fontSize: 9,
                            fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ),
                  SizedBox(width: 6),
                  Text(siteLabel,
                      style: TextStyle(color: t.textMuted, fontSize: 11)),
                  const Spacer(),
                  Text(relTime,
                      style: TextStyle(color: t.textMuted, fontSize: 10)),
                ]),
              ]),
            ),
          ]),

          // Progress bar (for active jobs)
          if (isActive && progress > 0) ...[
            SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 4,
              ),
            ),
            SizedBox(height: RaddSpace.xs),
            Text('${progress.toStringAsFixed(1)}%',
                style: TextStyle(color: statusColor,
                    fontSize: 10, fontWeight: FontWeight.w600)),
          ],

          // Indeterminate for queued
          if (status == 'queued') ...[
            SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
                minHeight: 4,
              ),
            ),
          ],

          // Message
          if (message.isNotEmpty) ...[
            SizedBox(height: 6),
            Text(message,
                style: TextStyle(color: t.textMuted, fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
  }
}
