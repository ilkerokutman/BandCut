import 'dart:developer' as developer;
import 'dart:io';

import 'package:bandcut/services/wav_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analyzes the rehearsal sample', () async {
    final file = File('assets/sample/20261005.wav');
    if (!file.existsSync()) {
      markTestSkipped('Local rehearsal sample is not available.');
      return;
    }
    final result = await WavAnalyzer.analyze(file);

    developer.log(
      'sampleRate=${result.sampleRate}, channels=${result.channels}, '
      'duration=${result.duration}, peaks=${result.peaks.length}',
      name: 'bandcut.sample',
    );
    for (final region in result.regions) {
      developer.log(
        '${region.name}: ${region.start} - ${region.end} '
        '(${region.duration})',
        name: 'bandcut.sample',
      );
    }

    expect(result.sampleRate, 44100);
    expect(result.channels, 1);
    expect(result.duration, const Duration(seconds: 6272));
    expect(result.peaks.length, WavAnalyzer.waveformPoints);
    expect(result.regions, isNotEmpty);
  });
}
