import 'dart:async';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';

/// G3 (TEN_POINT_PLAN Phase G): frame extraction via media_kit instead of
/// `video_thumbnail` (v0.5.3), which is known to cause ANRs (Application Not
/// Responding) on Android 12+ because it decodes the frame on the
/// platform/UI thread.
///
/// media_kit's `Player` is FFI-based (libmpv) — the same native decoder
/// already linked in for playback via `media_kit_libs_android_video` — so
/// the seek + screenshot round trip below runs through native code without
/// blocking the UI thread, and adds no extra native dependency.
///
/// Trade-off: unlike `video_thumbnail`, `Player.screenshot()` has no
/// built-in resize/quality knobs — it returns a JPEG at the source video's
/// resolution. Callers that render this in a small grid tile should pass
/// `cacheWidth`/`cacheHeight` to `Image.memory` so Flutter downsamples at
/// decode time instead of holding the full-resolution bitmap in memory.
class MediaKitThumbnailExtractor {
  MediaKitThumbnailExtractor._();

  /// Extract a single JPEG frame from [videoPath] at [timeMs].
  /// Returns null on any failure (missing file, unsupported codec, no
  /// frame available by the time we give up waiting, etc.) — callers
  /// already treat a null thumbnail as "no thumbnail available".
  static Future<Uint8List?> extractFrame(
    String videoPath, {
    int timeMs = 3000,
  }) async {
    if (videoPath.isEmpty) return null;
    Player? player;
    try {
      player = Player();
      await player.open(Media(videoPath), play: false);

      // Wait for the player to report a real duration before seeking —
      // seeking immediately after open() on some containers silently no-ops
      // because tracks haven't been probed yet.
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5), onTimeout: () => Duration.zero);

      final target = Duration(milliseconds: timeMs);
      await player.seek(target);
      // Give the decoder a moment to land on the seeked frame before capture —
      // screenshot() right after seek() can otherwise return the pre-seek frame.
      await Future.delayed(const Duration(milliseconds: 150));

      return await player.screenshot(format: 'image/jpeg');
    } catch (_) {
      return null;
    } finally {
      await player?.dispose();
    }
  }
}
