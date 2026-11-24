import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bandcut/models/analysis_settings.dart';
import 'package:bandcut/services/wav_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a 16-bit mono 44.1 kHz WAV containing a loud segment from
/// [loudStart] to [loudEnd] with silence elsewhere.
File _writeSessionWav({
  required Directory dir,
  required Duration loudStart,
  required Duration loudEnd,
  required Duration total,
}) {
  const sampleRate = 44100;
  final frames = (total.inMilliseconds * sampleRate / 1000).round();
  final data = ByteData(frames * 2);
  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    final loud =
        t >= loudStart.inMilliseconds / 1000 &&
        t < loudEnd.inMilliseconds / 1000;
    final sample = loud ? (math.sin(2 * math.pi * 220 * t) * 0.4) : 0.0;
    data.setInt16(i * 2, (sample * 32767).round(), Endian.little);
  }

  final dataLength = frames * 2;
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits
  ascii(36, 'data');
  header.setUint32(40, dataLength, Endian.little);

  final file = File('${dir.path}/gap_session.wav');
  final raf = file.openSync(mode: FileMode.write);
  try {
    raf.writeFromSync(header.buffer.asUint8List());
    raf.writeFromSync(data.buffer.asUint8List());
  } finally {
    raf.closeSync();
  }
  return file;
}

void main() {
  test(
    'leaveGaps pads each take by one second, clamped to file bounds',
    () async {
      final dir = await Directory.systemTemp.createTemp('bandcut_gap_test');
      addTearDown(() => dir.delete(recursive: true));

      // 5s silence, 50s loud (5–55s), 5s tail.
      final file = _writeSessionWav(
        dir: dir,
        loudStart: const Duration(seconds: 5),
        loudEnd: const Duration(seconds: 55),
        total: const Duration(seconds: 60),
      );

      const strict = AnalysisSettings(
        silenceThresholdDb: -22,
        minimumTrackDuration: Duration(seconds: 40),
        leaveGaps: false,
      );
      const padded = AnalysisSettings(
        silenceThresholdDb: -22,
        minimumTrackDuration: Duration(seconds: 40),
        leaveGaps: true,
      );

      final strictResult = await WavAnalyzer.analyze(file, settings: strict);
      final paddedResult = await WavAnalyzer.analyze(file, settings: padded);

      expect(strictResult.regions, hasLength(1));
      expect(paddedResult.regions, hasLength(1));

      final strictRegion = strictResult.regions.single;
      final paddedRegion = paddedResult.regions.single;

      expect(
        paddedRegion.start,
        strictRegion.start - const Duration(seconds: 1),
      );
      expect(paddedRegion.end, strictRegion.end + const Duration(seconds: 1));
      expect(paddedRegion.start, greaterThanOrEqualTo(Duration.zero));
      expect(paddedRegion.end, lessThanOrEqualTo(paddedResult.duration));
      expect(
        paddedRegion.duration,
        strictRegion.duration + const Duration(seconds: 2),
      );
    },
  );
}
