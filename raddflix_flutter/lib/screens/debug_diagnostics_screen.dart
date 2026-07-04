import 'dart:async';
import 'package:flutter/material.dart';
import '../core/design/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../core/debug/debug_logger.dart';
  import '../core/debug/playback_timeline.dart';
import '../core/security/keystore.dart';
import '../core/security/request_encoder.dart';
import '../core/security/device_id.dart';
import '../core/services/jazzdrive_service.dart';
import '../core/theme/radd_theme.dart';
import '../providers/auth_provider.dart';

/// Diagnostics screen — accessible in all builds.
/// Entry: tap version text in Profile 5 times.
class DebugDiagnosticsScreen extends ConsumerStatefulWidget {
  const DebugDiagnosticsScreen({super.key});
  @override
  ConsumerState<DebugDiagnosticsScreen> createState() => _DebugDiagnosticsScreenState();
}

class _DebugDiagnosticsScreenState extends ConsumerState<DebugDiagnosticsScreen>
    with SingleTickerProviderStateMixin {

  // ── Timeline tab state ───────────────────────────────────────────────────
    List<PtSession>  _tlSessions   = [];
    PtSession?       _tlCurrent;
    Timer?           _tlTimer;
    int              _tlSelected   = -1; // -1 = current session

    // ── Checks tab state ─────────────────────────────────────────────────────
  final List<_DiagResult> _results = [];
  bool _running = false;

  // ── Logs tab state ───────────────────────────────────────────────────────
  late final TabController _tabs;
  Timer? _logTimer;
  String _logFilter  = 'ALL';
  String _rawLogs    = '';
  bool   _autoScroll = true;
  final ScrollController _logScroll = ScrollController();
  static const _filters = ['ALL', 'ERROR', 'WARN', 'JAZZDRIVE', 'API', 'SYNC', 'DB'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, initialIndex: 1, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_tabs.indexIsChanging) _startLogTimer();
      if (_tabs.index == 0 && !_tabs.indexIsChanging) _stopLogTimer();
      if (_tabs.index == 2 && !_tabs.indexIsChanging) _startTimelineTimer();
      if (_tabs.index != 2 && !_tabs.indexIsChanging) _stopTimelineTimer();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) { _runAll(); _startLogTimer(); _refreshTimeline(); });
  }

  @override
  void dispose() {
    _stopLogTimer();
    _stopTimelineTimer(); // Fix #3: was missing — tlTimer kept firing after screen closed
    _tabs.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  // ── Log timer ─────────────────────────────────────────────────────────────
  void _startLogTimer() {
    _logTimer?.cancel();
    _refreshLogs();
    _logTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshLogs());
  }
  void _stopLogTimer()      { _logTimer?.cancel(); _logTimer = null; }

    void _startTimelineTimer() {
      _tlTimer?.cancel();
      _refreshTimeline();
      _tlTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshTimeline());
    }
    void _stopTimelineTimer() { _tlTimer?.cancel(); _tlTimer = null; }

    void _refreshTimeline() {
      if (!mounted) return;
      setState(() {
        _tlSessions = PlaybackTimeline.sessions.reversed.toList();
        _tlCurrent  = PlaybackTimeline.currentSession;
      });
    }

  void _refreshLogs() {
    if (!mounted) return;
    setState(() => _rawLogs = DebugLogger.getLastLines(500));
    if (_autoScroll && _logScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients && _logScroll.position.hasContentDimensions) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  // ── Checks ────────────────────────────────────────────────────────────────
  Future<void> _runAll() async {
    if (_running) return;
    setState(() { _running = true; _results.clear(); });
    await _check('Oracle Server',  _checkOracle);
    await _check('JazzDrive API',  _checkJazzDrive);
    await _check('XOR Decode',     _checkXor);
    await _check('DB: Row Counts', _checkDb);
    await _check('Auth Tokens',    _checkAuth);
    await _check('Sync Meta',      _checkSyncMeta);
    await _check('Device ID',      _checkDeviceId);
    setState(() => _running = false);
  }

  Future<void> _check(String label, Future<_DiagResult> Function() fn) async {
    setState(() => _results.add(_DiagResult(label: label, status: _Status.running)));
    try {
      final r = await fn().timeout(const Duration(seconds: 15));
      setState(() => _results[_results.length - 1] = r.withLabel(label));
    } catch (e) {
      setState(() => _results[_results.length - 1] =
          _DiagResult(label: label, status: _Status.fail,
              detail: e.toString().split('\n').first));
    }
  }

  Future<_DiagResult> _checkOracle() async {
    try {
      final res  = await ApiClient.instance.get('/healthz');
      final data = res.data;
      if (data is Map) {
        return _DiagResult(label: '', status: _Status.ok,
            detail: 'v${data["version"] ?? "?"} · HTTP ${res.statusCode}');
      }
      return _DiagResult(label: '', status: _Status.ok, detail: 'HTTP ${res.statusCode}');
    } catch (e) {
      return _DiagResult(label: '', status: _Status.fail,
          detail: e.toString().split('\n').first);
    }
  }

  /// Live end-to-end test of the JazzDrive share link chain.
  /// Picks the first episode (or movie) from local SQLite, decodes its
  /// share_url, and runs login → getMedia through the actual JazzDrive API.
  /// Each step result is shown so you can see exactly where a failure occurs.
  Future<_DiagResult> _checkJazzDrive() async {
    final db = await LocalDb.instance;

    // Prefer episode (TV show) so we test the folder-share matching path
    String? fileId;
    String type = '';
    final epRows = await db.rawQuery(
        "SELECT file_id FROM episodes WHERE share_url IS NOT NULL "
        "AND share_url != '' LIMIT 1");
    if (epRows.isNotEmpty) {
      fileId = epRows.first['file_id'] as String?;
      type = 'ep';
    } else {
      final mvRows = await db.rawQuery(
          "SELECT file_id FROM titles "
          "WHERE share_url IS NOT NULL AND share_url != '' "
          "AND media_type='movie' AND file_id IS NOT NULL LIMIT 1");
      if (mvRows.isNotEmpty) {
        fileId = mvRows.first['file_id'] as String?;
        type = 'movie';
      }
    }

    if (fileId == null || fileId.isEmpty) {
      return _DiagResult(
        label: '', status: _Status.warn,
        detail: 'No share URLs in local DB — open Settings → Sync first',
      );
    }

    final shareInfo    = await LocalDb.getShareInfo(fileId);
    final shareUrl     = shareInfo['share_url'] as String?;
    final targetFname  = shareInfo['filename']  as String?;
    final remoteId     = shareInfo['remote_id'] as int? ?? 0;

    if (shareUrl == null || shareUrl.isEmpty) {
      return _DiagResult(
        label: '', status: _Status.warn,
        detail: 'share_url is empty for $type file_id=$fileId',
      );
    }

    final result = await JazzDriveService.diagnosticTest(
      shareUrl: shareUrl,
      targetFilename: targetFname,
      remoteId: remoteId,
    );

    if (result.containsKey('error')) {
      return _DiagResult(
        label: '', status: _Status.fail,
        detail: '[$type id=$fileId]\n${result["error"]}',
      );
    }

    return _DiagResult(
      label: '', status: _Status.ok,
      detail: '[$type id=$fileId]\n'
              'Login: ${result["login"]}\n'
              'Media: ${result["media"]}\n'
              'URL:   ${result["stream_url"]}',
    );
  }

  Future<_DiagResult> _checkXor() async {
    try {
      final res  = await ApiClient.instance.get(ApiPaths.catalogVersion);
      final data = res.data;
      if (data is Map && data['version'] != null) {
        return _DiagResult(label: '', status: _Status.ok,
            detail: 'version=${data["version"]} · count=${data["count"] ?? "?"}');
      }
      return _DiagResult(label: '', status: _Status.fail,
          detail: 'Decode failed — response.data is ${data.runtimeType}');
    } catch (e) {
      return _DiagResult(label: '', status: _Status.fail,
          detail: e.toString().split('\n').first);
    }
  }

  Future<_DiagResult> _checkDb() async {
    final db       = await LocalDb.instance;
    final titles   = (await db.rawQuery('SELECT COUNT(*) c FROM titles'))[0]['c'] as int;
    final episodes = (await db.rawQuery('SELECT COUNT(*) c FROM episodes'))[0]['c'] as int;
    final movies   = (await db.rawQuery("SELECT COUNT(*) c FROM titles WHERE media_type='movie'"))[0]['c'] as int;
    final shows    = (await db.rawQuery("SELECT COUNT(*) c FROM titles WHERE media_type='show'"))[0]['c'] as int;
    return _DiagResult(
      label: '', status: titles > 0 ? _Status.ok : _Status.warn,
      detail: '$titles titles ($movies movies · $shows shows) · $episodes episodes',
    );
  }

  Future<_DiagResult> _checkAuth() async {
    final hasToken = await Keystore.hasTokens();
    if (!hasToken) {
      return _DiagResult(label: '', status: _Status.warn, detail: 'No tokens — not logged in');
    }
    final user    = ref.read(authProvider).user;
    final isGuest = user?.isGuest ?? false;
    return _DiagResult(label: '', status: _Status.ok,
        detail: isGuest
            ? 'Guest session active'
            : '${user?.phone ?? "-"} · plan=${user?.planName ?? "-"}');
  }

  Future<_DiagResult> _checkSyncMeta() async {
    final db   = await LocalDb.instance;
    final rows = await db.query('sync_meta');
    if (rows.isEmpty) {
      return _DiagResult(label: '', status: _Status.warn, detail: 'No sync records yet');
    }
    final map      = {for (final r in rows) r['key'] as String: r['value']};
    final lastSync = map['last_sync_ts'] ?? map['last_sync'] ?? 'none';
    final version  = map['catalog_version'] ?? 'none';
    return _DiagResult(label: '', status: _Status.ok,
        detail: 'last_sync=$lastSync · version=$version');
  }

  Future<_DiagResult> _checkDeviceId() async {
    final id    = await DeviceIdentifier.getDeviceId();
    final short = id.length > 12
        ? '${id.substring(0, 6)}…${id.substring(id.length - 6)}'
        : id;
    final key = RequestEncoder.generateSessionKey(id);
    return _DiagResult(label: '', status: _Status.ok,
        detail: 'id=$short · key=${key.substring(0, 8)}… (hourly rotating)');
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(AppIcons.back, size: 18),
          onPressed: () => Navigator.of(context).pop()),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: const Text('DIAG', style: TextStyle(
                color: Colors.orange, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
          const SizedBox(width: 10),
          const Text('Diagnostics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) {
              if (_tabs.index == 0) {
                return _running
                    ? const Padding(padding: EdgeInsets.only(right: 16),
                        child: Center(child: SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))))
                    : IconButton(icon: const Icon(AppIcons.refresh, color: Colors.orange),
                        tooltip: 'Re-run checks', onPressed: _runAll);
              }
              return Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: Icon(
                    _autoScroll ? AppIcons.arrowDown : AppIcons.pause,
                    color: _autoScroll ? Colors.orange : Colors.grey, size: 20),
                  tooltip: _autoScroll ? 'Auto-scroll ON' : 'Paused',
                  onPressed: () => setState(() => _autoScroll = !_autoScroll)),
                IconButton(
                  icon: const Icon(AppIcons.share, color: Colors.orange, size: 20),
                  tooltip: 'Share log file',
                  onPressed: DebugLogger.shareLogs),
              ]);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.orange,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: 'Checks'), Tab(text: 'Live Logs'), Tab(text: 'Player')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ChecksTab(results: _results, running: _running),
          _LogsTab(
            rawLogs:    _rawLogs,
            filter:     _logFilter,
            autoScroll: _autoScroll,
            scrollCtrl: _logScroll,
            filters:    _filters,
            onFilter:   (f) { setState(() => _logFilter = f); _refreshLogs(); },
            onClear:    () { DebugLogger.clearBuffer(); setState(() => _rawLogs = ''); },
          ),
          _PlayerTimelineTab(
            current:    _tlCurrent,
            sessions:   _tlSessions,
            selected:   _tlSelected,
            onSelect:   (i) => setState(() => _tlSelected = i),
          ),
        ],
      ),
    );
  }
}

// ── Checks Tab ────────────────────────────────────────────────────────────────
class _ChecksTab extends StatelessWidget {
  final List<_DiagResult> results;
  final bool running;
  const _ChecksTab({required this.results, required this.running});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty && running) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
        const SizedBox(height: 16),
        Text('Running checks…', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ]));
    }
    return Column(children: [
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _ResultCard(result: results[i]),
      )),
      if (results.isNotEmpty && !running)
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: BorderSide(color: Colors.orange.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(AppIcons.copy, size: 16),
              label: const Text('Copy Report', style: TextStyle(fontSize: 13)),
              onPressed: () {
                final txt = results.map((r) {
                  final ic = r.status == _Status.ok ? '✓' : r.status == _Status.warn ? '⚠' : '✗';
                  return '$ic ${r.label}: ${r.detail}';
                }).join('\n');
                Clipboard.setData(ClipboardData(text: txt));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report copied')));
              })),
        )),
    ]);
  }
}

// ── Logs Tab ──────────────────────────────────────────────────────────────────
class _LogsTab extends StatelessWidget {
  final String rawLogs;
  final String filter;
  final bool autoScroll;
  final ScrollController scrollCtrl;
  final List<String> filters;
  final void Function(String) onFilter;
  final VoidCallback onClear;

  const _LogsTab({
    required this.rawLogs, required this.filter,
    required this.autoScroll, required this.scrollCtrl,
    required this.filters, required this.onFilter, required this.onClear,
  });

  Color _lineColor(String line) {
    if (line.contains('[ERROR]') || line.contains('[CRASH]')) return const Color(0xFFEF4444);
    if (line.contains('[WARN ]')) return Colors.orange;
    if (line.contains('[JAZZDRIVE]')) return const Color(0xFF34D399);
    if (line.contains('[API  ]')) return const Color(0xFF60A5FA);
    if (line.contains('[SYNC ]')) return const Color(0xFF818CF8);
    if (line.contains('[DB   ]')) return const Color(0xFF22D3EE);
    if (line.contains('[NAV  ]')) return const Color(0xFFA78BFA);
    if (line.contains('[UI   ]')) return const Color(0xFFFBBF24);
    if (line.contains('[INFO ]')) return const Color(0xFF9CA3AF);
    return const Color(0xFF6B7280);
  }

  List<String> _filtered() {
    final lines = rawLogs.split('\n').where((l) => l.isNotEmpty).toList();
    if (filter == 'ALL') return lines;
    if (filter == 'JAZZDRIVE') {
      return lines.where((l) => l.contains('[JAZZDRIVE]')).toList();
    }
    final tag = '[${filter.padRight(5)}]';
    return lines.where((l) => l.contains(tag)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _filtered();
    return Column(children: [
      // Filter chips
      SizedBox(height: 44, child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filters.length + 1,
        itemBuilder: (_, i) {
          if (i == filters.length) {
            return Padding(padding: const EdgeInsets.only(left: 4),
              child: ActionChip(
                label: const Text('Clear', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.red.withOpacity(0.12),
                side: BorderSide(color: Colors.red.withOpacity(0.3)),
                labelStyle: const TextStyle(color: Colors.red),
                onPressed: onClear,
                visualDensity: VisualDensity.compact));
          }
          final f = filters[i]; final selected = filter == f;
          return Padding(padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(f, style: TextStyle(fontSize: 11)),
              selected: selected, onSelected: (_) => onFilter(f),
              selectedColor: Colors.orange.withOpacity(0.2),
              backgroundColor: const Color(0xFF0A0A1A),
              side: BorderSide(color: selected ? Colors.orange : Colors.grey.withOpacity(0.3)),
              labelStyle: TextStyle(color: selected ? Colors.orange : Colors.grey),
              checkmarkColor: Colors.orange,
              visualDensity: VisualDensity.compact));
        })),
      // Stats
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(children: [
          Text('${lines.length} lines', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
          const Spacer(),
          Flexible(child: Text(DebugLogger.getLogPath(),
              style: TextStyle(color: Colors.grey[700], fontSize: 10),
              overflow: TextOverflow.ellipsis, maxLines: 1)),
        ])),
      const SizedBox(height: 4),
      // Log output
      Expanded(child: lines.isEmpty
          ? Center(child: Text(
              rawLogs.isEmpty ? 'No logs yet — navigate the app to generate logs'
                             : 'No $filter entries in buffer',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center))
          : Scrollbar(controller: scrollCtrl,
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                itemCount: lines.length,
                itemBuilder: (_, i) => SelectableText(lines[i],
                  style: TextStyle(
                    color: _lineColor(lines[i]), fontSize: 10.5,
                    fontFamily: 'monospace', height: 1.5,
                    fontWeight: lines[i].contains('[ERROR]') || lines[i].contains('[CRASH]')
                        ? FontWeight.w600 : FontWeight.normal))))),
    ]);
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  final _DiagResult result;
  const _ResultCard({super.key, required this.result});
  @override
  Widget build(BuildContext context) {
    final Color color; final IconData icon;
    switch (result.status) {
      case _Status.ok:      color = const Color(0xFF22C55E); icon = AppIcons.successIcon;  break;
      case _Status.warn:    color = Colors.orange;           icon = AppIcons.warning;  break;
      case _Status.fail:    color = const Color(0xFFEF4444); icon = AppIcons.cancel;         break;
      case _Status.running: color = Colors.blueGrey;         icon = AppIcons.hourglass;  break;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        result.status == _Status.running
            ? SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:color))
            : Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(result.label, style: TextStyle(
              color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w600)),
          if (result.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(result.detail, style: TextStyle(
                color: Colors.white.withOpacity(0.5), fontSize: 12, fontFamily: 'monospace')),
          ],
        ])),
      ]),
    );
  }
}

enum _Status { running, ok, warn, fail }

class _DiagResult {
  final String label;
  final _Status status;
  final String detail;
  const _DiagResult({required this.label, required this.status, this.detail = ''});
  _DiagResult withLabel(String l) => _DiagResult(label: l, status: status, detail: detail);
}

  // ── Player Timeline Tab ───────────────────────────────────────────────────────
  class _PlayerTimelineTab extends StatelessWidget {
    final PtSession?       current;
    final List<PtSession>  sessions;
    final int              selected;   // -1 = current, 0+ = history index
    final void Function(int) onSelect;

    const _PlayerTimelineTab({
      required this.current,
      required this.sessions,
      required this.selected,
      required this.onSelect,
    });

    @override
    Widget build(BuildContext context) {
      final allSessions = <({String label, PtSession? s})>[];
      if (current != null) {
        allSessions.add((label: 'CURRENT', s: current));
      }
      for (int i = 0; i < sessions.length; i++) {
        allSessions.add((label: 'Session ${i + 1}', s: sessions[i]));
      }

      if (allSessions.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(AppIcons.timeline, color: Colors.grey[700], size: 48),
            const SizedBox(height: 12),
            Text('No playback sessions recorded yet.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 6),
            Text('Play a video to see the startup timeline.',
                style: TextStyle(color: Colors.grey[700], fontSize: 11)),
          ]),
        );
      }

      final displayIdx = selected == -1 ? 0 : (selected + (current != null ? 1 : 0));
      final displaySession = displayIdx < allSessions.length
          ? allSessions[displayIdx].s
          : allSessions.first.s;

      return Column(children: [
        // Session selector chips
        Container(
          height: 36,
          color: const Color(0xFF0A0A1A),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            itemCount: allSessions.length,
            itemBuilder: (_, i) {
              final s     = allSessions[i].s;
              final label = allSessions[i].label;
              final active  = i == displayIdx;
              final hasWarn = s != null && (!s.isHealthy || s.hadBlackScreen);
              return GestureDetector(
                onTap: () => onSelect(i == 0 && current != null ? -1 : i - (current != null ? 1 : 0)),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: active
                        ? (hasWarn ? Colors.red.withOpacity(0.25) : Colors.orange.withOpacity(0.2))
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? (hasWarn ? Colors.red.withOpacity(0.7) : Colors.orange.withOpacity(0.6))
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (hasWarn) ...[
                      const Icon(AppIcons.warning, color: Colors.red, size: 11),
                      const SizedBox(width: 3),
                    ],
                    Text(label, style: TextStyle(
                      color: active ? Colors.white : Colors.grey[500],
                      fontSize: 11, fontWeight: FontWeight.w600,
                    )),
                  ]),
                ),
              );
            },
          ),
        ),

        // Session status banner
        if (displaySession != null) _StatusBanner(session: displaySession),

        // Event list
        Expanded(
          child: displaySession == null
              ? const Center(child: Text('No data', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  itemCount: displaySession.events.length,
                  itemBuilder: (_, i) => _EventRow(event: displaySession.events[i]),
                ),
        ),
      ]);
    }
  }

  class _StatusBanner extends StatelessWidget {
    final PtSession session;
    const _StatusBanner({required this.session});

    @override
    Widget build(BuildContext context) {
      final hasBS   = session.hadBlackScreen;
      final hasBad  = session.hadVfGatePassed;
      final isGood  = session.isHealthy;

      final Color  bg     = hasBS  ? Colors.red.withOpacity(0.12)
                          : hasBad ? Colors.orange.withOpacity(0.12)
                          :          Colors.green.withOpacity(0.08);
      final Color  border = hasBS  ? Colors.red.withOpacity(0.5)
                          : hasBad ? Colors.orange.withOpacity(0.5)
                          :          Colors.green.withOpacity(0.3);
      final String icon   = hasBS ? '🖤' : hasBad ? '⚠️' : '✓';
      final String msg    = hasBS  ? 'BLACK SCREEN DETECTED — gate passed + audio at T+3s'
                          : hasBad ? 'GATE PASSED — vf= fired during startup window. Black screen likely.'
                          :          'Healthy — vf gate blocked correctly. No black screen.';
      final Color  textColor = isGood ? Colors.green[300]!
                             : hasBS  ? Colors.red[300]!
                             :          Colors.orange[300]!;

      return Container(
        margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(child: Text(msg,
              style: TextStyle(color: textColor, fontSize: 11,
                  fontWeight: FontWeight.w600))),
        ]),
      );
    }
  }

  class _EventRow extends StatelessWidget {
    final PtEvent event;
    const _EventRow({required this.event});

    @override
    Widget build(BuildContext context) {
      final isWarn  = event.event.contains('PASS') || event.event.contains('BLACK') ||
                      event.event.contains('⚠️');
      final isGood  = event.event.contains('BLOCKED');
      final isMpv   = event.event.startsWith('mpv_playing');
      final isFrame = event.event.startsWith('first_frame');

      final Color nameColor = isWarn  ? Colors.red[300]!
                            : isGood  ? Colors.green[300]!
                            : isMpv   ? Colors.lightBlue[300]!
                            : isFrame ? Colors.purple[300]!
                            :           Colors.grey[300]!;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04))),
          color: isWarn ? Colors.red.withOpacity(0.05) : Colors.transparent,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Timestamp column
          SizedBox(width: 72,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('T+' + event.relMs.toString() + 'ms',
                  style: TextStyle(color: Colors.grey[600], fontSize: 10,
                      fontFamily: 'monospace')),
              Text('+' + event.deltaMs.toString() + 'ms',
                  style: TextStyle(
                    color: event.deltaMs > 200 ? Colors.orange[700] : Colors.grey[700],
                    fontSize: 9, fontFamily: 'monospace',
                  )),
            ]),
          ),
          const SizedBox(width: 8),
          // Status dot
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isWarn ? Colors.red : isGood ? Colors.green : Colors.grey[600]!,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Event name + detail
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.event,
                  style: TextStyle(color: nameColor, fontSize: 11,
                      fontWeight: isWarn || isGood ? FontWeight.w700 : FontWeight.w500,
                      fontFamily: 'monospace')),
              if (event.extra != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(event.extra!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 9,
                          fontFamily: 'monospace')),
                ),
            ]),
          ),
        ]),
      );
    }
  }
  