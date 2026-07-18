import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 24-color accent picker shown as a bottom sheet.
/// Selecting any swatch calls [onColorSelected] immediately (live preview).
class ColorPickerSheet extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const ColorPickerSheet({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<ColorPickerSheet> {
  late Color _selected;
  bool _showHex = false;
  final _hexCtrl = TextEditingController();
  String? _hexError;

  static const _bg = Color(0xFF12121E);

  static const _swatches = <_Swatch>[
    _Swatch('RaddFlix Amber', Color(0xFFD4784A)),
    _Swatch('Hot Pink',      Color(0xFFFF4081)),
    _Swatch('Sakura',        Color(0xFFFF80AB)),
    _Swatch('Purple',        Color(0xFF9C27B0)),
    _Swatch('Lavender',      Color(0xFF7C4DFF)),
    _Swatch('Indigo',        Color(0xFF3F51B5)),
    _Swatch('Blue',          Color(0xFF1565C0)),
    _Swatch('Sky',           Color(0xFF29B6F6)),
    _Swatch('Cyan',          Color(0xFF00BCD4)),
    _Swatch('Teal',          Color(0xFF009688)),
    _Swatch('Green',         Color(0xFF4CAF50)),
    _Swatch('Lime',          Color(0xFF76FF03)),
    _Swatch('Yellow',        Color(0xFFFFD700)),
    _Swatch('Amber',         Color(0xFFFFAB00)),
    _Swatch('Orange',        Color(0xFFFF6F00)),
    _Swatch('Coral',         Color(0xFFFF6B6B)),
    _Swatch('Rose Gold',     Color(0xFFE8A09A)),
    _Swatch('Peach',         Color(0xFFFFCCBC)),
    _Swatch('Mint',          Color(0xFFB2DFDB)),
    _Swatch('Neon Green',    Color(0xFF00E676)),
    _Swatch('Matrix',        Color(0xFF69FF47)),
    _Swatch('Gold',          Color(0xFFFFC107)),
    _Swatch('Silver',        Color(0xFFB0BEC5)),
    _Swatch('White',         Color(0xFFFFFFFF)),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _pick(Color c) {
    setState(() => _selected = c);
    widget.onColorSelected(c);
  }

  void _applyHex() {
    var hex = _hexCtrl.text.trim().replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    if (v != null) {
      setState(() => _hexError = null);
      _pick(Color(v));
    } else {
      setState(() => _hexError = 'Invalid hex colour');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          )),
          Row(children: [
            const Text('Player Colour',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _selected,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 2),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: _swatches.length,
            itemBuilder: (_, i) {
              final sw = _swatches[i];
              final isSel = _selected.value == sw.color.value;
              return Tooltip(
                message: sw.name,
                child: GestureDetector(
                  onTap: () => _pick(sw.color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: sw.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSel ? Colors.white : Colors.white24,
                        width: isSel ? 2.5 : 1,
                      ),
                      boxShadow: isSel
                          ? [BoxShadow(color: sw.color.withOpacity(0.6), blurRadius: 8)]
                          : null,
                    ),
                    child: isSel
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() => _showHex = !_showHex),
            child: Row(children: [
              Icon(_showHex ? Icons.expand_less_rounded : Icons.colorize_rounded,
                  color: Colors.white54, size: 18),
              const SizedBox(width: 6),
              const Text('Custom hex colour',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ),
          if (_showHex) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'E8002D',
                    hintStyle: const TextStyle(color: Colors.white30),
                    prefixText: '#',
                    prefixStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _hexError,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _applyHex,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selected,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Apply'),
              ),
            ]),
          ],
          const SizedBox(height: 8),
        ],
      ),
    )
    .animate()
    .slideY(begin: 0.1, end: 0, duration: 240.ms, curve: Curves.easeOutCubic)
    .fadeIn(duration: 200.ms);
  }
}

class _Swatch {
  final String name;
  final Color color;
  const _Swatch(this.name, this.color);
}

Future<void> showColorPicker({
  required BuildContext context,
  required Color initialColor,
  required ValueChanged<Color> onColorSelected,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ColorPickerSheet(
      initialColor: initialColor,
      onColorSelected: onColorSelected,
    ),
  );
}
