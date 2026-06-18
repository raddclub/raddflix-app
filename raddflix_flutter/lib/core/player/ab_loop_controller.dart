/// Manages A-B loop state.
/// The player polls [shouldLoop] and calls [maybeSeekBack] every position update.
class AbLoopController {
  Duration? pointA;
  Duration? pointB;

  bool get isActive => pointA != null && pointB != null;
  bool get hasA => pointA != null;
  bool get hasB => pointB != null;

  void setA(Duration pos) {
    pointA = pos;
    if (pointB != null && pointB! <= pos) pointB = null;
  }

  // L-04: use an epsilon gap to prevent A and B being identical (or within 1s)
  // — if the user accidentally taps B at the same position as A, the loop would
  // be 0ms and cause rapid position-reset flicker.
  static const _minLoopMs = 1000;

  void setB(Duration pos) {
    if (pointA == null) return;
    if (pos.inMilliseconds - pointA!.inMilliseconds < _minLoopMs) return;
    pointB = pos;
  }

  void clear() {
    pointA = null;
    pointB = null;
  }

  /// Returns the A point if position has passed B (so caller can seek back to A).
  Duration? maybeSeekBack(Duration current) {
    if (!isActive) return null;
    // L-04: trigger 100ms before pointB to avoid a single-frame overshoot
    if (current >= pointB! - const Duration(milliseconds: 100)) return pointA;
    return null;
  }

  String get aLabel => pointA == null ? '--:--' : _fmt(pointA!);
  String get bLabel => pointB == null ? '--:--' : _fmt(pointB!);

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
