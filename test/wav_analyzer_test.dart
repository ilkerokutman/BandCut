import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bandcut/models/analysis_settings.dart';
import 'package:bandcut/services/wav_analyzer.dart';

/// Verifies detection against a synthesized session:
/// 60s loud - 30s quiet - 50s loud - 20s quiet - 45s loud.
void main() {
  test('detects full-band takes and rejects chatter', () async {
    final file = File('/tmp/test_session.wav');
    if (!file.existsSync()) {
      markTestSkipped('Generate /tmp/test_session.wav to run this test.');
      return;
    }
    final result = await WavAnalyzer.analyze(file);

    expect(result.sampleRate, 44100);
    expect(result.channels, 2);
    expect(result.duration.inSeconds, greaterThan(200));
    expect(result.peaks.length, WavAnalyzer.waveformPoints);
    expect(result.peaks.every((peak) => peak >= 0 && peak <= 1), isTrue);
    expect(result.peaks.toSet().length, greaterThan(3));

    expect(result.regions.length, 3);
    for (final region in result.regions) {
      expect(region.duration.inSeconds, greaterThanOrEqualTo(40));
    }
    expect(result.regions[0].start.inSeconds, 0);
    expect(result.regions[1].start.inSeconds, greaterThanOrEqualTo(85));
    expect(result.regions[2].start.inSeconds, greaterThanOrEqualTo(135));

    final stricterResult = await WavAnalyzer.analyze(
      file,
      settings: const AnalysisSettings(
        silenceThresholdDb: -22,
        minimumTrackDuration: Duration(seconds: 55),
      ),
    );
    expect(stricterResult.regions.length, 1);
  });
}
