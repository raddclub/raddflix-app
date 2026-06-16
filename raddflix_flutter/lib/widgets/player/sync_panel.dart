import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Reusable Audio/Subtitle sync panel — ±50/100/500ms buttons + slider + Reset.
/// [label]: 'Audio' or 'Subtitle'
/// [delayMs]: current delay in milliseconds
/// [onChanged]: called with new delay value
class SyncPanel extends StatefulWidget {
  final String label;
  final int delayMs;
  final ValueChanged<int> onChanged;
  final VoidCallback onDone;

  const SyncPanel({
    super.key,
    required this.label,
    required this.delayMs,
    required this.onChanged,
    required this.onDone,
  });

  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  late int _delay;

  @override
  void initState() {
    super.initState();
    _delay = widget.delayMs;
  }

  void _adjust(int delta) {
    setState(() => _delay = (_delay + delta).clamp(-5000, 5000));
    widget.onChanged(_delay);
  }

  void _reset() {
    setState(() => _delay = 0);
    widget.onChanged(0);
  }

  String get _hint {
    if (widget.label == 'Audio') {
      return _delay > 0
          ? 'Speech comes BEFORE lip movement → tap [−]'
          : _delay < 0
              ? 'Speech comes AFTER lip movement → tap [+]'
              : 'Audio and video are in sync';
    } else {
      return _delay > 0
          ? 'Subtitles appear too early → tap [−]'
          : _delay < 0
              ? 'Subtitles appear too late → tap [+]'
              : 'Subtitles are in sync';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFE8002D);
    final delayStr = _delay == 0
        ? '0 ms'
        : '${_delay > 0 ? '+' : ''}$_delay ms';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Center(child: Container(width:36,height:4,
          decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(2)))),
        const SizedBox(height:16),

        // Title
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
          Text('${widget.label} Sync',
            style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600)),
          TextButton(onPressed:widget.onDone,
            child:const Text('Done',style:TextStyle(color:Color(0xFFE8002D)))),
        ]),
        const SizedBox(height:12),

        // Delay display
        Text(
          '${widget.label} is ${_delay == 0 ? 'in sync' : (_delay > 0 ? 'delayed by  +' : 'advanced by  ')}${_delay == 0 ? '' : '${_delay.abs()} ms'}',
          style:const TextStyle(color:Colors.white70,fontSize:13),
          textAlign:TextAlign.center,
        ).animate(key:ValueKey(_delay)).fadeIn(duration:200.ms),
        const SizedBox(height:16),

        // ±Buttons row
        Row(mainAxisAlignment:MainAxisAlignment.center, children:[
          _OffsetBtn('−500', () => _adjust(-500)),
          _OffsetBtn('−100', () => _adjust(-100)),
          _OffsetBtn('−50',  () => _adjust(-50)),
          const SizedBox(width:8),
          _ResetBtn(onTap: _reset),
          const SizedBox(width:8),
          _OffsetBtn('+50',  () => _adjust(50)),
          _OffsetBtn('+100', () => _adjust(100)),
          _OffsetBtn('+500', () => _adjust(500)),
        ]),
        const SizedBox(height:12),

        // Slider
        Slider(
          value: _delay.toDouble().clamp(-5000, 5000),
          min: -5000, max: 5000,
          activeColor: accent,
          inactiveColor: Colors.white24,
          label: delayStr,
          divisions: 200,
          onChanged: (v) {
            setState(() => _delay = v.toInt());
            widget.onChanged(_delay);
          },
        ),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[
          const Text('−5000ms',style:TextStyle(color:Colors.white38,fontSize:10)),
          const Text('+5000ms',style:TextStyle(color:Colors.white38,fontSize:10)),
        ]),
        const SizedBox(height:10),

        // Hint
        Row(children:[
          const Icon(Icons.lightbulb_outline_rounded,color:Colors.amber,size:14),
          const SizedBox(width:6),
          Expanded(child:Text(_hint,style:const TextStyle(color:Colors.white54,fontSize:11))),
        ]),
      ]),
    );
  }
}

class _OffsetBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OffsetBtn(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
    padding:const EdgeInsets.symmetric(horizontal:2),
    child:TextButton(
      onPressed:onTap,
      style:TextButton.styleFrom(
        backgroundColor:Colors.white12,
        foregroundColor:Colors.white,
        minimumSize:const Size(44,36),
        padding:const EdgeInsets.symmetric(horizontal:6),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
      ),
      child:Text(label,style:const TextStyle(fontSize:12)),
    ),
  );
}

class _ResetBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _ResetBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed:onTap,
    icon:const Icon(Icons.refresh_rounded,size:14,color:Color(0xFFE8002D)),
    label:const Text('Reset ↺',style:TextStyle(fontSize:12,color:Color(0xFFE8002D))),
    style:TextButton.styleFrom(
      backgroundColor:const Color(0x22E8002D),
      minimumSize:const Size(72,36),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
    ),
  );
}
