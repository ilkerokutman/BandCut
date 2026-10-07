import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/track_region.dart';

/// Slices detected regions out of the source WAV via FFmpeg and encodes
/// them as high-quality VBR MP3s (libmp3lame -q:a 2).
class ExportService {
  /// Resolves the FFmpeg executable bundled beside the application binary.
  static Future<String> findFfmpeg() async {
    final ffmpeg = p.join(
      File(Platform.resolvedExecutable).parent.path,
      'ffmpeg',
    );
    if (await File(ffmpeg).exists()) return ffmpeg;
    throw StateError('The bundled FFmpeg executable is missing.');
  }

  static String slugify(String value, {String fallback = 'track'}) {
    final slug = value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? fallback : slug;
  }

  static String outputFileName(String projectName, String trackName) {
    final project = slugify(projectName, fallback: 'project');
    final track = slugify(trackName);
    return '${project}_$track.mp3';
  }

  static String formatTimestamp(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:'
        '${two(d.inSeconds % 60)}.$ms';
  }

  /// Exports [regions] from [source] into [outputDir].
  ///
  /// Reports progress as `(completed, total)` via [onProgress].
  static Future<void> exportAll({
    required File source,
    required String projectName,
    required List<TrackRegion> regions,
    required Directory outputDir,
    void Function(int completed, int total)? onProgress,
  }) async {
    final ffmpeg = await findFfmpeg();
    final selected = regions.where((r) => r.enabled).toList();
    var done = 0;
    for (final region in selected) {
      final outPath = p.join(
        outputDir.path,
        outputFileName(projectName, region.name),
      );
      final result = await Process.run(ffmpeg, [
        '-y',
        '-ss',
        formatTimestamp(region.start),
        '-to',
        formatTimestamp(region.end),
        '-i',
        source.path,
        '-vn',
        '-codec:a',
        'libmp3lame',
        '-q:a',
        '2',
        outPath,
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(ffmpeg, [], '${result.stderr}', result.exitCode);
      }
      onProgress?.call(++done, selected.length);
    }
  }
}
