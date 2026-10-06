/// A detected song take within a continuous session recording.
class TrackRegion {
  TrackRegion({
    required this.start,
    required this.end,
    required this.name,
    this.enabled = true,
  });

  /// Region start within the source file.
  Duration start;

  /// Region end within the source file.
  Duration end;

  /// Output file label (sanitized on export).
  String name;

  /// Whether this region is included in batch export.
  bool enabled;

  Duration get duration => end - start;
}

/// Result of analyzing a WAV file in a background isolate.
class AnalysisResult {
  const AnalysisResult({
    required this.sampleRate,
    required this.channels,
    required this.duration,
    required this.peaks,
    required this.regions,
  });

  final int sampleRate;
  final int channels;
  final Duration duration;

  /// Downsampled peak amplitudes (0..1) for waveform rendering.
  final List<double> peaks;

  /// Detected full-band takes.
  final List<TrackRegion> regions;
}
