import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/design/app_icons.dart';
import '../core/theme/radd_theme.dart';
import '../core/services/usage_service.dart';
import '../core/db/local_db.dart';
import '../design_system/components/radd_button.dart';
import '../design_system/radius/radd_radius.dart';
import '../providers/subscription_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DA-1 · Data & Bandwidth screen
//  Shows: animated arc gauge, streaming vs downloads breakdown,
//         daily usage sparkline for the current billing cycle,
//         plan renewal countdown, and data-saver toggle.
// ─────────────────────────────────────────────────────────────────────────────

class DataUsageScreen extends ConsumerStatefulWidget {
  /// Pre-loaded values from the caller to avoid a blank gauge on first paint.
  final double? initialUsedGb;
  final double? initialLimitGb;
  const DataUsageScreen({super.key, this.initialUsedGb, this.initialLimitGb});

  @override
  ConsumerState<DataUsageScreen> createState() => _DataUsageScreenState();
}

class _DataUsageScreenState extends ConsumerState<DataUsageScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _arcCtrl;
  late Animation<double>   _arcAnim;

  double _usedGb   = 0;
  double _limitGb  = 0;
  double _streamGb = 0;
  double _dlGb     = 0;
  List<_DayEntry> _daily = [];
  int?    _daysLeft;
  String? _renewalLabel;
  bool    _loading = true;

  @override
  void initState() {
    super.initState();
    _arcCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _arcAnim = CurvedAnimation(parent: _arcCtrl, curve: AppCurves.standard);

    if (widget.initialUsedGb != null) {
      _usedGb  = widget.initialUsedGb!;
      _limitGb = widget.initialLimitGb ?? 0;
    }
    _loadData();
  }

  @override
  void dispose() {
    _arcCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // 1 ── Fresh server quota ─────────────────────────────────────────────────
    try {
      final q = await UsageService.fetchQuota();
      if (q != null && mounted) {
        setState(() {
          _usedGb  = (q['monthly_used_gb']  as num?)?.toDouble() ?? _usedGb;
          _limitGb = (q['monthly_limit_gb'] as num?)?.toDouble() ?? _limitGb;
        });
      }
    } catch (_) {
      final cached = await UsageService.getCachedQuota();
      if (mounted) {
        setState(() {
          _usedGb  = (cached['monthly_used_gb']  as num?)?.toDouble() ?? _usedGb;
          _limitGb = (cached['monthly_limit_gb'] as num?)?.toDouble() ?? _limitGb;
        });
      }
    }

    // 2 ── Plan expiry info ───────────────────────────────────────────────────
    try {
      final sub = ref.read(subscriptionProvider);
      final expiresAt = sub.status?.expiresAt;
      if (expiresAt != null) {
        final dt = DateTime.tryParse(expiresAt);
        if (dt != null && mounted) {
          final diff = dt.difference(DateTime.now()).inDays;
          const m = ['Jan','Feb','Mar','Apr','May','Jun',
                     'Jul','Aug','Sep','Oct','Nov','Dec'];
          setState(() {
            _daysLeft     = diff > 0 ? diff : 0;
            _renewalLabel = '${m[dt.month - 1]} ${dt.day}';
          });
        }
      }
    } catch (_) {}

    // 3 ── Local daily breakdown (from start of current calendar month) ───────
    final now        = DateTime.now();
    final cycleStart = DateTime(now.year, now.month, 1);
    final epochSec   = cycleStart.millisecondsSinceEpoch ~/ 1000;
    try {
      final rows      = await LocalDb.getDailyUsage(cycleStartEpoch: epochSec);
      final breakdown = await LocalDb.getKindBreakdown(cycleStartEpoch: epochSec);
      if (mounted) {
        setState(() {
          _daily = rows
              .map((r) => _DayEntry(
                    // "2026-07-20" → extract day "20"
                    label: (r['day'] as String).substring(8),
                    bytes: (r['bytes'] as int?) ?? 0,
                  ))
              .toList();
          // bytes → GB
          _streamGb = (breakdown['stream']   ?? 0) / 1073741824.0;
          _dlGb     = (breakdown['download'] ?? 0) / 1073741824.0;
        });
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
      _arcCtrl.forward();
    }
  }

  Color _gaugeColor(double pct) {
    if (pct < 0.60) return AppColors.success;
    if (pct < 0.85) {
      return Color.lerp(AppColors.success, AppColors.warning,
          (pct - 0.60) / 0.25)!;
    }
    return Color.lerp(AppColors.warning, AppColors.error,
        (pct - 0.85) / 0.15)!;
  }

  @override
  Widget build(BuildContext context) {
    final t   = RaddTheme.of(context);
    final pct = _limitGb > 0 ? (_usedGb / _limitGb).clamp(0.0, 1.0) : 0.0;
    final gc  = _gaugeColor(pct);
    final rem = (_limitGb - _usedGb).clamp(0.0, _limitGb);

    return Scaffold(
      backgroundColor: null,
      appBar: AppBar(
        title: const Text('Data & Bandwidth',
            style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: Icon(AppIcons.back, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading && _usedGb == 0
          ? Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
              strokeCap: StrokeCap.round))
          : RefreshIndicator(
              onRefresh: () async {
                _arcCtrl.reset();
                await _loadData();
              },
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                  // ── Arc gauge ─────────────────────────────────────────────
                  _GaugeCard(
                    arcAnim:      _arcAnim,
                    pct:          pct,
                    gaugeColor:   gc,
                    usedGb:       _usedGb,
                    limitGb:      _limitGb,
                    remaining:    rem,
                  ).animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.12, end: 0,
                              duration: 400.ms, curve: AppCurves.standard),

                  const SizedBox(height: 20),

                  // ── Streaming vs Downloads chips ───────────────────────────
                  if (_streamGb > 0 || _dlGb > 0) ...[
                    _SectionLabel('This Cycle', t),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: _BreakdownChip(
                          icon:  AppIcons.wifi,
                          label: 'Streaming',
                          gb:    _streamGb,
                          color: AppColors.primary,
                        ).animate(delay: 100.ms)
                            .fadeIn(duration: 280.ms)
                            .scale(begin: const Offset(0.85, 0.85),
                                   duration: 280.ms,
                                   curve: AppCurves.spring),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _BreakdownChip(
                          icon:  AppIcons.cloudDownload,
                          label: 'Downloads',
                          gb:    _dlGb,
                          color: AppColors.info,
                        ).animate(delay: 180.ms)
                            .fadeIn(duration: 280.ms)
                            .scale(begin: const Offset(0.85, 0.85),
                                   duration: 280.ms,
                                   curve: AppCurves.spring),
                      ),
                    ]),
                    const SizedBox(height: 20),
                  ],

                  // ── Daily sparkline ────────────────────────────────────────
                  if (_daily.isNotEmpty) ...[
                    Row(children: [
                      Expanded(child: _SectionLabel('Daily Usage', t)),
                      Text(
                        '${_monthName(DateTime.now().month)} ${DateTime.now().year}',
                        style: TextStyle(color: t.textMuted, fontSize: 12),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _SparklineCard(daily: _daily, barColor: gc)
                        .animate(delay: 220.ms)
                        .fadeIn(duration: 350.ms)
                        .slideY(begin: 0.08, end: 0,
                                duration: 350.ms, curve: AppCurves.standard),
                    const SizedBox(height: 20),
                  ],

                  // ── Renewal strip ──────────────────────────────────────────
                  if (_daysLeft != null) ...[
                    _RenewalStrip(
                      daysLeft:     _daysLeft!,
                      renewalLabel: _renewalLabel,
                      t:            t,
                    ).animate(delay: 300.ms).fadeIn(duration: 300.ms),
                    const SizedBox(height: 12),
                  ],

                  // ── Data Saver tile ────────────────────────────────────────
                  _DataSaverTile(t: t)
                      .animate(delay: 360.ms).fadeIn(duration: 280.ms),

                  const SizedBox(height: 24),

                  // ── Manage subscription CTA ────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.subscription),
                      icon: Icon(AppIcons.crown, size: 16),
                      label: const Text('Manage Subscription',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md)),
                      ),
                    ),
                  ).animate(delay: 420.ms).fadeIn(duration: 280.ms),
                ]),
              ),
            ),
    );
  }

  String _monthName(int m) => const [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ][m - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────

class _DayEntry {
  final String label; // "01"–"31"
  final int bytes;
  const _DayEntry({required this.label, required this.bytes});
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section label helper
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final RaddTheme t;
  const _SectionLabel(this.text, this.t);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: t.textPrimary, fontSize: 15,
          fontWeight: FontWeight.w700, letterSpacing: -0.3));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Arc Gauge Card
// ─────────────────────────────────────────────────────────────────────────────

class _GaugeCard extends StatelessWidget {
  final Animation<double> arcAnim;
  final double pct, usedGb, limitGb, remaining;
  final Color gaugeColor;

  const _GaugeCard({
    required this.arcAnim,
    required this.pct,
    required this.gaugeColor,
    required this.usedGb,
    required this.limitGb,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gaugeColor.withOpacity(0.11),
            gaugeColor.withOpacity(0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: gaugeColor.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
              color: gaugeColor.withOpacity(0.09),
              blurRadius: 28,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(children: [
        // Arc + center text
        AnimatedBuilder(
          animation: arcAnim,
          builder: (_, __) {
            final animPct = pct * arcAnim.value;
            return SizedBox(
              width: 210, height: 210,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: const Size(210, 210),
                  painter: ArcGaugePainter(
                    progress:    animPct,
                    arcColor:    gaugeColor,
                    bgColor:     t.border.withOpacity(0.45),
                    strokeWidth: 16.0,
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  // Animated counter
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: usedGb),
                    duration: const Duration(milliseconds: 1300),
                    curve: AppCurves.standard,
                    builder: (_, v, __) => Text(
                      v.toStringAsFixed(1),
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.0,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Text('GB used',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: gaugeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      limitGb > 0
                          ? '${remaining.toStringAsFixed(1)} GB left'
                          : 'Unlimited',
                      style: TextStyle(
                          color: gaugeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ]),
            );
          },
        ),

        const SizedBox(height: 16),

        // Fraction + percent row
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${usedGb.toStringAsFixed(1)} GB',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          Text(' of ${limitGb > 0 ? limitGb.toInt() : "∞"} GB',
              style: TextStyle(color: t.textMuted, fontSize: 13)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: gaugeColor.withOpacity(0.13),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: gaugeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Arc Gauge Painter  (exported so data_usage_ring.dart can also use it)
// ─────────────────────────────────────────────────────────────────────────────

/// Draws a partial arc with a glowing tip dot.
/// Start angle: 150° (7-o'clock). Full sweep: 240°.
class ArcGaugePainter extends CustomPainter {
  final double progress;    // 0.0 – 1.0
  final Color  arcColor;
  final Color  bgColor;
  final double strokeWidth;

  const ArcGaugePainter({
    required this.progress,
    required this.arcColor,
    required this.bgColor,
    required this.strokeWidth,
  });

  static const double _startDeg = 150.0;
  static const double _sweepDeg = 240.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = cx - strokeWidth / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final startRad = _startDeg * pi / 180;
    final sweepRad = _sweepDeg * pi / 180;

    // Track
    canvas.drawArc(rect, startRad, sweepRad, false,
        Paint()
          ..color       = bgColor
          ..style       = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap   = StrokeCap.round);

    if (progress <= 0) return;

    final fillRad = sweepRad * progress;

    // Fill
    canvas.drawArc(rect, startRad, fillRad, false,
        Paint()
          ..color       = arcColor
          ..style       = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap   = StrokeCap.round);

    // Glow dot at tip
    if (progress > 0.02) {
      final endAngle = startRad + fillRad;
      final tx = cx + r * cos(endAngle);
      final ty = cy + r * sin(endAngle);
      canvas.drawCircle(
        Offset(tx, ty),
        strokeWidth * 0.65,
        Paint()
          ..color      = arcColor.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
  }

  @override
  bool shouldRepaint(ArcGaugePainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Breakdown chip
// ─────────────────────────────────────────────────────────────────────────────

class _BreakdownChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final double   gb;
  final Color    color;
  const _BreakdownChip({
    required this.icon,
    required this.label,
    required this.gb,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = RaddTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Icon(icon, color: color, size: 16)),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          Text(gb >= 1.0
              ? '${gb.toStringAsFixed(1)} GB'
              : '${(gb * 1024).toStringAsFixed(0)} MB',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Daily sparkline card
// ─────────────────────────────────────────────────────────────────────────────

class _SparklineCard extends StatefulWidget {
  final List<_DayEntry> daily;
  final Color barColor;
  const _SparklineCard({required this.daily, required this.barColor});

  @override
  State<_SparklineCard> createState() => _SparklineCardState();
}

class _SparklineCardState extends State<_SparklineCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = CurvedAnimation(parent: _ctrl, curve: AppCurves.standard);
    // Slight delay so it doesn't compete with the main arc animation
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t          = RaddTheme.of(context);
    final todayLabel = DateTime.now().day.toString().padLeft(2, '0');
    final maxBytes   = widget.daily.map((e) => e.bytes).fold(0, max);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                entries:     widget.daily,
                maxBytes:    maxBytes > 0 ? maxBytes : 1,
                progress:    _anim.value,
                todayLabel:  todayLabel,
                barColor:    widget.barColor,
                mutedColor:  widget.barColor.withOpacity(0.35),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // First / last day labels
        if (widget.daily.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.daily.first.label,
                  style: TextStyle(color: t.textMuted, fontSize: 9)),
              Text('Day of cycle',
                  style: TextStyle(color: t.textMuted, fontSize: 9)),
              Text(widget.daily.last.label,
                  style: TextStyle(color: t.textMuted, fontSize: 9)),
            ],
          ),
      ]),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<_DayEntry> entries;
  final int    maxBytes;
  final double progress;
  final String todayLabel;
  final Color  barColor;
  final Color  mutedColor;

  const _SparklinePainter({
    required this.entries,
    required this.maxBytes,
    required this.progress,
    required this.todayLabel,
    required this.barColor,
    required this.mutedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;
    final n    = entries.length;
    final gap  = 2.0;
    final barW = (size.width - gap * (n - 1)) / n;

    for (int i = 0; i < n; i++) {
      final e       = entries[i];
      final isToday = e.label == todayLabel;
      final norm    = (e.bytes / maxBytes).clamp(0.0, 1.0);
      final barH    = max(3.0, norm * size.height * progress);
      final x       = i * (barW + gap);
      final y       = size.height - barH;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          const Radius.circular(2.5),
        ),
        Paint()..color = isToday ? barColor : mutedColor,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.progress != progress || old.barColor != barColor;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Renewal strip
// ─────────────────────────────────────────────────────────────────────────────

class _RenewalStrip extends StatelessWidget {
  final int    daysLeft;
  final String? renewalLabel;
  final RaddTheme t;
  const _RenewalStrip({
    required this.daysLeft,
    required this.renewalLabel,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final urgent = daysLeft <= 7;
    final color  = urgent ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(urgent ? AppIcons.warning : AppIcons.calendar,
            color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, color: t.textPrimary),
              children: [
                TextSpan(
                  text: urgent
                      ? 'Plan renews in $daysLeft day${daysLeft == 1 ? "" : "s"}'
                      : '$daysLeft days remaining',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: color),
                ),
                if (renewalLabel != null)
                  TextSpan(
                    text: '  ·  $renewalLabel',
                    style: TextStyle(
                        color: t.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data Saver toggle tile
// ─────────────────────────────────────────────────────────────────────────────

class _DataSaverTile extends StatefulWidget {
  final RaddTheme t;
  const _DataSaverTile({required this.t});

  @override
  State<_DataSaverTile> createState() => _DataSaverTileState();
}

class _DataSaverTileState extends State<_DataSaverTile> {
  bool _on     = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _on     = p.getBool('jm_data_saver') ?? false;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _on = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('jm_data_saver', v);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
              child: Icon(AppIcons.dataSaver, color: AppColors.primary, size: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Data Saver',
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text('Reduces quality to preserve your quota',
                style: TextStyle(color: t.textMuted, fontSize: 11)),
          ]),
        ),
        if (_loaded)
          Switch(
            value: _on,
            onChanged: _toggle,
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        else
          const SizedBox(width: 48, height: 24),
      ]),
    );
  }
}
