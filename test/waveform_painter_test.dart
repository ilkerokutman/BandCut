import 'package:bandcut/ui/waveform_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeline coordinates scale with waveform width', () {
    final painter = WaveformPainter(
      peaks: const [0.2, 0.8],
      regions: const [],
      duration: const Duration(minutes: 10),
      playhead: Duration.zero,
      colors: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );

    expect(painter.xFor(const Duration(minutes: 5), 1000), 500);
    expect(painter.xFor(const Duration(minutes: 5), 4000), 2000);
  });
}
