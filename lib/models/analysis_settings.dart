class AnalysisSettings {
  const AnalysisSettings({
    required this.silenceThresholdDb,
    required this.minimumTrackDuration,
    this.leaveGaps = false,
  });

  static const defaults = AnalysisSettings(
    silenceThresholdDb: -22,
    minimumTrackDuration: Duration(seconds: 40),
    leaveGaps: false,
  );

  final double silenceThresholdDb;
  final Duration minimumTrackDuration;
  final bool leaveGaps;

  Map<String, Object> toJson() => {
    'silenceThresholdDb': silenceThresholdDb,
    'minimumTrackDurationSeconds': minimumTrackDuration.inSeconds,
    'leaveGaps': leaveGaps,
  };

  factory AnalysisSettings.fromJson(Map<String, dynamic> json) {
    return AnalysisSettings(
      silenceThresholdDb: (json['silenceThresholdDb'] as num).toDouble(),
      minimumTrackDuration: Duration(
        seconds: (json['minimumTrackDurationSeconds'] as num).round(),
      ),
      leaveGaps: json['leaveGaps'] as bool? ?? false,
    );
  }
}
