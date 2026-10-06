class AnalysisSettings {
  const AnalysisSettings({
    required this.silenceThresholdDb,
    required this.minimumTrackDuration,
  });

  static const defaults = AnalysisSettings(
    silenceThresholdDb: -22,
    minimumTrackDuration: Duration(seconds: 40),
  );

  final double silenceThresholdDb;
  final Duration minimumTrackDuration;

  Map<String, Object> toJson() => {
    'silenceThresholdDb': silenceThresholdDb,
    'minimumTrackDurationSeconds': minimumTrackDuration.inSeconds,
  };

  factory AnalysisSettings.fromJson(Map<String, dynamic> json) {
    return AnalysisSettings(
      silenceThresholdDb: (json['silenceThresholdDb'] as num).toDouble(),
      minimumTrackDuration: Duration(
        seconds: (json['minimumTrackDurationSeconds'] as num).round(),
      ),
    );
  }
}
