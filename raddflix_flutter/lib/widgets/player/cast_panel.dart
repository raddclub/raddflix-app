import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/cast_service.dart' show CastDevice, CastDeviceType;

/// Phase O — Cast / External Output Panel
/// Lists available cast targets, mirrors to TV/screen via native APIs.
/// CastDevice and CastDeviceType are defined in cast_service.dart (single source of truth).

class CastPanel extends StatefulWidget {
  final List<CastDevice> devices;
  final CastDevice? connected;
  final bool scanning;
  final Color accentColor;
  final ValueChanged<CastDevice> onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onScanRequested;

  const CastPanel({super.key, required this.devices, this.connected,
      this.scanning = false, required this.accentColor,
      required this.onConnect, required this.onDisconnect, required this.onScanRequested});

  @override State<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends State<CastPanel> {
  @override
  Widget build(BuildContext context) {
    final acc = widget.accentColor;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      decoration: const BoxDecoration(color: Color(0xFF12121E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.fromLTRB(0,12,0,0),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.fromLTRB(16,12,16,0),
          child: Row(children: [
            Icon(Icons.cast_rounded, color: acc, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('Cast & Output',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
            if (widget.scanning)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: acc, strokeWidth: 2))
            else
              GestureDetector(
                onTap: widget.onScanRequested,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: acc.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: acc.withOpacity(0.4))),
                  child: Text('Scan', style: TextStyle(color: acc, fontSize: 12, fontWeight: FontWeight.w600)))),
          ])),
        const Divider(color: Colors.white10, height: 20),
        if (widget.connected != null)
          _ConnectedCard(device: widget.connected!, accent: acc, onDisconnect: widget.onDisconnect),
        const Divider(color: Colors.white10, height: 1),
        Flexible(child: Builder(builder: (context) {
          // CAST-J6: filter connected device out of the available-devices list
          // so it doesn't appear twice (once in the connected card, once in the list).
          final availableDevices = widget.connected == null
              ? widget.devices
              : widget.devices.where((d) => d.id != widget.connected!.id).toList();

          if (availableDevices.isEmpty) {
            // CAST-J5: differentiate "actively scanning" from "scan finished, nothing found"
            return Center(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cast_connected_rounded, color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                Text(
                  widget.scanning ? 'Searching for devices…' : 'No devices found',
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                ),
                const SizedBox(height: 4),
                if (!widget.scanning)
                  const Text('Make sure your TV is on the same Wi-Fi',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
              ]),
            ));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: availableDevices.length,
            itemBuilder: (_, i) => _DeviceRow(
              device: availableDevices[i],
              isConnected: widget.connected?.id == availableDevices[i].id,
              accent: acc,
              onTap: () { widget.onConnect(availableDevices[i]); Navigator.pop(context); },
            ),
          );
        })),
      ]),
    ).animate().slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic)
               .fadeIn(duration: 180.ms);
  }
}

class _ConnectedCard extends StatelessWidget {
  final CastDevice device;
  final Color accent;
  final VoidCallback onDisconnect;
  const _ConnectedCard({required this.device, required this.accent, required this.onDisconnect});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.4))),
    child: Row(children: [
      Icon(_iconFor(device.type), color: accent, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(device.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        Text('Connected · ${device.host}', style: TextStyle(color: accent, fontSize: 10)),
      ])),
      GestureDetector(
        onTap: onDisconnect,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.4))),
          child: const Text('Stop', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700)))),
    ]),
  );
  IconData _iconFor(CastDeviceType t) {
    switch (t) {
      case CastDeviceType.chromecast: return Icons.cast_rounded;
      case CastDeviceType.airplay:    return Icons.airplay_rounded;
      case CastDeviceType.dlna:       return Icons.router_rounded;
      case CastDeviceType.miracast:   return Icons.screen_share_rounded;
      case CastDeviceType.localScreen:return Icons.tv_rounded;
    }
  }
}

class _DeviceRow extends StatelessWidget {
  final CastDevice device;
  final bool isConnected;
  final Color accent;
  final VoidCallback onTap;
  const _DeviceRow({required this.device, required this.isConnected,
      required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (device.type) {
      case CastDeviceType.chromecast: icon = Icons.cast_rounded; break;
      case CastDeviceType.airplay:    icon = Icons.airplay_rounded; break;
      case CastDeviceType.dlna:       icon = Icons.router_rounded; break;
      case CastDeviceType.miracast:   icon = Icons.screen_share_rounded; break;
      case CastDeviceType.localScreen:icon = Icons.tv_rounded; break;
    }
    return InkWell(
      onTap: isConnected ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(
              color: isConnected ? accent.withOpacity(0.15) : Colors.white10,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isConnected ? accent : Colors.white12)),
            child: Icon(icon, color: isConnected ? accent : Colors.white54, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name, style: TextStyle(color: isConnected ? Colors.white : Colors.white70,
                fontSize: 13, fontWeight: isConnected ? FontWeight.w700 : FontWeight.normal)),
            Text(device.host, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ])),
          // Signal bars
          Row(children: List.generate(4, (i) => Container(
            width: 4, height: 8 + i * 3.0, margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: i < device.signalStrength ? accent : Colors.white24,
              borderRadius: BorderRadius.circular(2))))),
          if (isConnected)
            Padding(padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle_rounded, color: accent, size: 18)),
        ])),
    );
  }
}
