import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_client.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../core/security/keystore.dart';
import '../core/security/request_encoder.dart';
import '../core/security/device_id.dart';
import '../core/theme/radd_theme.dart';
import '../providers/auth_provider.dart';

/// Debug-only diagnostics screen.
/// Gated behind kDebugMode — completely absent from release APK.
/// Access: tap the version text in Profile 7 times.
class DebugDiagnosticsScreen extends ConsumerStatefulWidget {
  const DebugDiagnosticsScreen({super.key});
  @override
  ConsumerState<DebugDiagnosticsScreen> createState() => _DebugDiagnosticsScreenState();
}

class _DebugDiagnosticsScreenState extends ConsumerState<DebugDiagnosticsScreen> {
  final List<_DiagResult> _results = [];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
    }
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() { _running = true; _results.clear(); });
    await _check('Oracle Server',  _checkOracle);
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
      final r = await fn().timeout(const Duration(seconds: 10));
      setState(() => _results[_results.length - 1] = r.withLabel(label));
    } catch (e) {
      setState(() => _results[_results.length - 1] =
          _DiagResult(label: label, status: _Status.fail, detail: e.toString().split('\n').first));
    }
  }

  Future<_DiagResult> _checkOracle() async {
    try {
      final res = await ApiClient.instance.get('/healthz');
      final data = res.data;
      if (data is Map) {
        return _DiagResult(label: '', status: _Status.ok,
            detail: 'v${data["version"] ?? "?"} · HTTP ${res.statusCode}');
      }
      return _DiagResult(label: '', status: _Status.ok, detail: 'HTTP ${res.statusCode}');
    } catch (e) {
      return _DiagResult(label: '', status: _Status.fail, detail: e.toString().split('\n').first);
    }
  }

  Future<_DiagResult> _checkXor() async {
    try {
      final res = await ApiClient.instance.get(ApiPaths.catalogVersion);
      final data = res.data;
      if (data is Map && data['version'] != null) {
        return _DiagResult(label: '', status: _Status.ok,
            detail: 'version=${data["version"]} · count=${data["count"] ?? "?"}');
      }
      return _DiagResult(label: '', status: _Status.fail,
          detail: 'Decode failed — response.data is ${data.runtimeType}');
    } catch (e) {
      return _DiagResult(label: '', status: _Status.fail, detail: e.toString().split('\n').first);
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
    final plan    = user?.planName ?? 'unknown';
    final phone   = user?.phone   ?? 'unknown';
    final isGuest = user?.isGuest ?? false;
    return _DiagResult(label: '', status: _Status.ok,
        detail: isGuest ? 'Guest session active' : '$phone · plan=$plan');
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
    final short = id.length > 12 ? '${id.substring(0, 6)}…${id.substring(id.length - 6)}' : id;
    final key   = RequestEncoder.generateSessionKey(id);
    return _DiagResult(label: '', status: _Status.ok,
        detail: 'id=$short · key=${key.substring(0, 8)}… (hourly rotating)');
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final t = RaddTheme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: const Text('DEBUG', style: TextStyle(
                color: Colors.orange, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
          const SizedBox(width: 10),
          const Text('Diagnostics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop()),
        actions: [
          if (_running)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))))
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.orange),
              tooltip: 'Re-run all checks',
              onPressed: _runAll),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.orange.withOpacity(0.08),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            Text('Debug only — stripped from release APK',
                style: TextStyle(color: Colors.orange.withOpacity(0.8), fontSize: 12)),
          ]),
        ),
        Expanded(
          child: _results.isEmpty && _running
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
                  const SizedBox(height: 16),
                  Text('Running checks…',
                      style: TextStyle(color: t.textMuted, fontSize: 13)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ResultCard(result: _results[i]),
                ),
        ),
        if (_results.isNotEmpty && !_running)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: BorderSide(color: Colors.orange.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy Report', style: TextStyle(fontSize: 13)),
                  onPressed: () {
                    final report = _results.map((r) {
                      final icon = r.status == _Status.ok ? '✓'
                          : r.status == _Status.warn ? '⚠' : '✗';
                      return '$icon ${r.label}: ${r.detail}';
                    }).join('\n');
                    Clipboard.setData(ClipboardData(text: report));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Report copied to clipboard')));
                  },
                ),
              ),
            ),
          ),
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
  _DiagResult withLabel(String l) =>
      _DiagResult(label: l, status: status, detail: detail);
}

class _ResultCard extends StatelessWidget {
  final _DiagResult result;
  const _ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (result.status) {
      case _Status.ok:
        color = const Color(0xFF22C55E); icon = Icons.check_circle_rounded; break;
      case _Status.warn:
        color = Colors.orange; icon = Icons.warning_amber_rounded; break;
      case _Status.fail:
        color = const Color(0xFFEF4444); icon = Icons.cancel_rounded; break;
      case _Status.running:
        color = Colors.blueGrey; icon = Icons.hourglass_top_rounded; break;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        result.status == _Status.running
            ? SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(result.label, style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14, fontWeight: FontWeight.w600)),
          if (result.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(result.detail, style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12, fontFamily: 'monospace')),
          ],
        ])),
      ]),
    );
  }
}
