import 'dart:typed_data';

  class LocalVideo {
    final int id;
    final String title;
    final String displayName;
    final String filePath;
    final String folderName;
    final String folderPath;
    final int durationMs;
    final int sizeBytes;
    final int width;
    final int height;
    final int dateModifiedMs;
    final String? mimeType;
    Uint8List? thumbnail;
    String? subtitlePath;

    LocalVideo({
      required this.id,
      required this.title,
      required this.displayName,
      required this.filePath,
      required this.folderName,
      required this.folderPath,
      required this.durationMs,
      required this.sizeBytes,
      required this.width,
      required this.height,
      required this.dateModifiedMs,
      this.mimeType,
      this.thumbnail,
      this.subtitlePath,
    });

    bool get hasSrt => subtitlePath != null;

  String get formattedDuration {
      final total = durationMs ~/ 1000;
      final h = total ~/ 3600;
      final m = (total % 3600) ~/ 60;
      final s = total % 60;
      if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
      return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    }

    String get formattedSize {
      if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
      if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    String get resolution {
      if (width == 0 || height == 0) return '';
      final shortSide = width < height ? width : height;
      if (shortSide >= 2160) return '4K';
      if (shortSide >= 1440) return '1440p';
      if (shortSide >= 1080) return '1080p';
      if (shortSide >= 720)  return '720p';
      if (shortSide >= 480)  return '480p';
      if (shortSide >= 360)  return '360p';
      return '${shortSide}p';
    }

    bool get isHighRes => (width < height ? width : height) >= 1080;
  }

  class LocalFolder {
    final String name;
    final String path;
    final List<LocalVideo> videos;
    int newCount; // unviewed count badge

    LocalFolder({
      required this.name,
      required this.path,
      required this.videos,
      this.newCount = 0,
    });

    int get totalSizeBytes => videos.fold(0, (sum, v) => sum + v.sizeBytes);

    String get formattedTotalSize {
      final bytes = totalSizeBytes;
      if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    LocalVideo? get firstVideo => videos.isNotEmpty ? videos.first : null;
  }
  