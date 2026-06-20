/// Phase I1 — Watch Party Rooms (Architecture + Local Sync)
/// Full WebSocket Watch Party would require a backend server.
/// This implementation provides:
///   - WatchParty room data model
///   - WatchPartyService with WebSocket client architecture
///   - WatchPartyOverlay widget (participant list + sync state)
///   - Local simulation mode for demo (no server required)
library watch_party;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Room participant ──────────────────────────────────────────────────────────
class WatchPartyParticipant {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isHost;
  final Duration? position; // null = not yet synced

  const WatchPartyParticipant({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isHost = false,
    this.position,
  });

  WatchPartyParticipant copyWith({Duration? position}) =>
      WatchPartyParticipant(id: id, name: name,
          avatarUrl: avatarUrl, isHost: isHost, position: position);
}

// ── Room state ────────────────────────────────────────────────────────────────
class WatchPartyRoom {
  final String code;    // 6-char join code
  final String hostId;
  final String contentId;
  final List<WatchPartyParticipant> participants;
  final bool isPlaying;
  final Duration hostPosition;

  const WatchPartyRoom({
    required this.code,
    required this.hostId,
    required this.contentId,
    required this.participants,
    required this.isPlaying,
    required this.hostPosition,
  });
}

// ── Watch Party Service ───────────────────────────────────────────────────────
class WatchPartyService {
  WatchPartyService._();
  static final instance = WatchPartyService._();

  // WebSocket server URL — replace with real Radd backend
  static const _wsUrl = 'wss://party.raddflix.pk/ws';

  WatchPartyRoom? _room;
  String? _myId;
  bool _connected = false;
  Timer? _pingTimer;

  final _roomCtrl = StreamController<WatchPartyRoom?>.broadcast();
  final _eventCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<WatchPartyRoom?> get roomStream => _roomCtrl.stream;
  Stream<Map<String, dynamic>> get events => _eventCtrl.stream;

  WatchPartyRoom? get currentRoom => _room;
  bool get isConnected => _connected;
  String get myId => _myId ?? 'local';

  /// Create a new watch party room (host).
  Future<String?> createRoom({
    required String contentId,
    required String hostName,
  }) async {
    // Generate a 6-char room code
    final code = _generateCode();
    _myId = 'host_${DateTime.now().millisecondsSinceEpoch}';
    _room = WatchPartyRoom(
      code: code,
      hostId: _myId!,
      contentId: contentId,
      isPlaying: false,
      hostPosition: Duration.zero,
      participants: [WatchPartyParticipant(
        id: _myId!, name: hostName, isHost: true)],
    );
    _roomCtrl.add(_room);
    // In production: POST /rooms to backend, get WebSocket URL, connect
    _simulateParticipantJoin(); // demo simulation
    return code;
  }

  /// Join an existing room by code.
  Future<bool> joinRoom({
    required String code,
    required String participantName,
  }) async {
    _myId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    // In production: GET /rooms/{code}, connect WebSocket
    // Simulation:
    _room = WatchPartyRoom(
      code: code,
      hostId: 'host_sim',
      contentId: 'simulated',
      isPlaying: true,
      hostPosition: const Duration(minutes: 12, seconds: 34),
      participants: [
        const WatchPartyParticipant(id: 'host_sim', name: 'Host', isHost: true),
        WatchPartyParticipant(id: _myId!, name: participantName),
      ],
    );
    _connected = true;
    _roomCtrl.add(_room);
    return true;
  }

  /// Send a sync event (play/pause/seek from host).
  void sendSync({required bool isPlaying, required Duration position}) {
    if (!_connected || _room == null) return;
    final event = {
      'type': 'sync',
      'isPlaying': isPlaying,
      'posMs': position.inMilliseconds,
      'from': _myId,
    };
    _eventCtrl.add(event);
    // In production: _ws.sink.add(jsonEncode(event));
  }

  void leaveRoom() {
    _pingTimer?.cancel();
    _connected = false;
    _room = null;
    _myId = null;
    _roomCtrl.add(null);
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = DateTime.now().millisecondsSinceEpoch;
    return List.generate(6, (i) => chars[(rng >> (i * 4)) % chars.length]).join();
  }

  // Demo: simulate another participant joining after 3 seconds
  void _simulateParticipantJoin() {
    Future.delayed(const Duration(seconds: 3), () {
      if (_room == null) return;
      _room = WatchPartyRoom(
        code: _room!.code,
        hostId: _room!.hostId,
        contentId: _room!.contentId,
        isPlaying: _room!.isPlaying,
        hostPosition: _room!.hostPosition,
        participants: [
          ..._room!.participants,
          const WatchPartyParticipant(id: 'demo_guest', name: 'Ahmed K.'),
        ],
      );
      _connected = true;
      _roomCtrl.add(_room);
    });
  }
}

// ── Watch Party Overlay widget ─────────────────────────────────────────────────
class WatchPartyOverlay extends StatelessWidget {
  final WatchPartyRoom room;
  final Color accentColor;
  final VoidCallback onLeave;

  const WatchPartyOverlay({
    super.key,
    required this.room,
    required this.accentColor,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.group_rounded, color: accentColor, size: 16),
            const SizedBox(width: 6),
            Text('Watch Party',
                style: TextStyle(color: accentColor,
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(
              onTap: onLeave,
              child: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Room: ${room.code}',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 8),
          // Participant list
          ...room.participants.map((p) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: p.isHost ? accentColor : Colors.white24,
                  shape: BoxShape.circle),
                child: Center(child: Text(
                  p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.w700),
                )),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(
                p.isHost ? '${p.name} (Host)' : p.name,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              )),
            ]),
          )),
          const SizedBox(height: 6),
          // Sync status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6,
                  decoration: const BoxDecoration(
                      color: Colors.greenAccent, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('Synced', style: TextStyle(color: Colors.greenAccent,
                  fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Create / Join Room sheet ───────────────────────────────────────────────────
class WatchPartySheet extends StatefulWidget {
  final String contentId;
  final Color accentColor;
  final ValueChanged<WatchPartyRoom> onJoined;

  const WatchPartySheet({
    super.key,
    required this.contentId,
    required this.accentColor,
    required this.onJoined,
  });

  static Future<void> show(BuildContext context, {
    required String contentId,
    required Color accentColor,
    required ValueChanged<WatchPartyRoom> onJoined,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WatchPartySheet(
          contentId: contentId, accentColor: accentColor, onJoined: onJoined),
    );
  }

  @override
  State<WatchPartySheet> createState() => _WatchPartySheetState();
}

class _WatchPartySheetState extends State<WatchPartySheet> {
  bool _hosting = true;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _generatedCode;

  @override
  void dispose() { _nameCtrl.dispose(); _codeCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    setState(() => _loading = true);
    final code = await WatchPartyService.instance.createRoom(
      contentId: widget.contentId,
      hostName: _nameCtrl.text.trim().isEmpty ? 'Host' : _nameCtrl.text.trim(),
    );
    if (mounted && code != null) {
      setState(() { _generatedCode = code; _loading = false; });
    }
  }

  Future<void> _join() async {
    setState(() => _loading = true);
    final ok = await WatchPartyService.instance.joinRoom(
      code: _codeCtrl.text.trim().toUpperCase(),
      participantName: _nameCtrl.text.trim().isEmpty
          ? 'Guest' : _nameCtrl.text.trim(),
    );
    if (mounted && ok) {
      widget.onJoined(WatchPartyService.instance.currentRoom!);
      Navigator.of(context).pop();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Icon(Icons.groups_rounded, color: widget.accentColor, size: 28),
            const SizedBox(width: 12),
            const Text('Watch Party', style: TextStyle(color: Colors.white,
                fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          const Text('Watch together, in sync — no matter where you are',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),
          // Host / Join tabs
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              _tab('Create Room', _hosting, () => setState(() => _hosting = true)),
              _tab('Join Room', !_hosting, () => setState(() => _hosting = false)),
            ]),
          ),
          const SizedBox(height: 20),
          // Name field
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDeco('Your display name'),
          ),
          const SizedBox(height: 12),
          if (!_hosting)
            TextField(
              controller: _codeCtrl,
              style: const TextStyle(color: Colors.white,
                  letterSpacing: 4, fontWeight: FontWeight.w700),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: _inputDeco('Room code (6 letters)'),
            ),
          // Show generated code
          if (_generatedCode != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: widget.accentColor.withOpacity(0.4))),
              child: Column(children: [
                const Text('Share this code with friends',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                Text(_generatedCode!,
                    style: TextStyle(color: widget.accentColor,
                        fontSize: 32, fontWeight: FontWeight.w900,
                        letterSpacing: 8)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Clipboard.setData(ClipboardData(text: _generatedCode!)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.copy_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 4),
                    const Text('Copy code', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onJoined(WatchPartyService.instance.currentRoom!);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Start Watching',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : (_hosting ? _create : _join),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_loading ? 'Please wait…'
                    : _hosting ? 'Create Room' : 'Join Room',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: active ? widget.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(label,
          style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 13, fontWeight: FontWeight.w600))),
      ),
    ),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: Colors.white.withOpacity(0.07),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    counterText: '',
  );
}
