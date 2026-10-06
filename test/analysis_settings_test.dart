import 'package:bandcut/models/analysis_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysis settings round-trip through JSON', () {
    const settings = AnalysisSettings(
      silenceThresholdDb: -30,
      minimumTrackDuration: Duration(seconds: 75),
    );

    final restored = AnalysisSettings.fromJson(settings.toJson());

    expect(restored.silenceThresholdDb, -30);
    expect(restored.minimumTrackDuration, const Duration(seconds: 75));
  });

  test('defaults match the original detection values', () {
    expect(AnalysisSettings.defaults.silenceThresholdDb, -22);
    expect(
      AnalysisSettings.defaults.minimumTrackDuration,
      const Duration(seconds: 40),
    );
  });
}
