import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/analysis_settings.dart';
import '../models/track_region.dart';

/// Stateless service that decodes WAV audio and detects song takes.
///
/// Uses a dual-stage RMS algorithm: short-window RMS levels separate
/// full-band playing (loud) from chatter/tuning (quiet), then contiguous
/// loud passages are merged across short gaps and filtered by duration.
class WavAnalyzer {
  /// Analysis window length.
  static const Duration windowSize = Duration(milliseconds: 100);

  /// Quiet gaps shorter than this inside a take are bridged.
  static const Duration maxGap = Duration(seconds: 8);

  /// Number of points emitted for waveform rendering.
  static const int waveformPoints = 64000;

  /// Analyzes [file] off the UI thread and returns peaks + detected regions.
  static Future<AnalysisResult> analyze(
    File file, {
    AnalysisSettings settings = AnalysisSettings.defaults,
  }) {
    return compute(_analyzeInIsolate, (
      path: file.path,
      silenceThresholdDb: settings.silenceThresholdDb,
      minimumTrackDurationSeconds: settings.minimumTrackDuration.inSeconds,
    ));
  }

  static Future<AnalysisResult> _analyzeInIsolate(
    ({String path, double silenceThresholdDb, int minimumTrackDurationSeconds})
    request,
  ) async {
    final raf = await File(request.path).open();
    try {
      final header = await _readWavHeader(raf);
      final samples = await _analyzeSamples(raf, header);
      final regions = _detectRegions(
        samples.rms,
        header.windowDuration,
        silenceThresholdDb: request.silenceThresholdDb,
        minimumTrackDuration: Duration(
          seconds: request.minimumTrackDurationSeconds,
        ),
      );
      return AnalysisResult(
        sampleRate: header.sampleRate,
        channels: header.channels,
        duration: header.duration,
        peaks: samples.peaks,
        regions: regions,
      );
    } finally {
      await raf.close();
    }
  }

  /// Parses RIFF/WAVE chunks; supports PCM 16/24/32-bit and float32.
  static Future<_WavHeader> _readWavHeader(RandomAccessFile raf) async {
    final riff = await raf.read(12);
    if (riff.length < 12 ||
        String.fromCharCodes(riff.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(riff.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }
    int? sampleRate, channels, bitsPerSample, blockAlign;
    int formatTag = 0;
    int dataOffset = 0, dataLength = 0;
    while (true) {
      final chunkHead = await raf.read(8);
      if (chunkHead.length < 8) break;
      final id = String.fromCharCodes(chunkHead.sublist(0, 4));
      final size = ByteData.sublistView(chunkHead).getUint32(4, Endian.little);
      if (id == 'fmt ') {
        final fmt = await raf.read(size);
        final b = ByteData.sublistView(fmt);
        formatTag = b.getUint16(0, Endian.little);
        channels = b.getUint16(2, Endian.little);
        sampleRate = b.getUint32(4, Endian.little);
        blockAlign = b.getUint16(12, Endian.little);
        bitsPerSample = b.getUint16(14, Endian.little);
      } else if (id == 'data') {
        dataOffset = await raf.position();
        dataLength = size;
        await raf.setPosition(dataOffset + size);
      } else {
        await raf.setPosition(await raf.position() + size);
      }
      if (size.isOdd) await raf.setPosition(await raf.position() + 1);
    }
    if (sampleRate == null || channels == null || dataLength == 0) {
      throw const FormatException('Missing fmt or data chunk');
    }
    if (!{
      (1, 16),
      (1, 24),
      (1, 32),
      (3, 32),
    }.contains((formatTag, bitsPerSample))) {
      throw FormatException(
        'Unsupported format: tag=$formatTag bits=$bitsPerSample',
      );
    }
    final frames = dataLength ~/ blockAlign!;
    return _WavHeader(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample!,
      blockAlign: blockAlign,
      formatTag: formatTag,
      dataOffset: dataOffset,
      dataLength: dataLength,
      duration: Duration(microseconds: (frames * 1e6 / sampleRate).round()),
      windowDuration: Duration(microseconds: (windowSize.inMicroseconds)),
    );
  }

  /// Streams the data chunk in ~4 MB reads and emits RMS analysis windows
  /// alongside high-resolution linear sample peaks for waveform rendering.
  static Future<({List<double> rms, List<double> peaks})> _analyzeSamples(
    RandomAccessFile raf,
    _WavHeader h,
  ) async {
    await raf.setPosition(h.dataOffset);
    final samplesPerWindow = (h.sampleRate * 0.1).round();
    final totalFrames = h.dataLength ~/ h.blockAlign;
    final rms = <double>[];
    final peaks = List<double>.filled(waveformPoints, 0);
    var sumSquares = 0.0;
    var rmsCount = 0;
    var frameIndex = 0;
    var remainingBytes = h.dataLength;
    var carry = Uint8List(0);
    const chunkBytes = 4 * 1024 * 1024;

    while (remainingBytes > 0) {
      final bytes = await raf.read(min(chunkBytes, remainingBytes));
      if (bytes.isEmpty) break;
      remainingBytes -= bytes.length;

      final joined = Uint8List(carry.length + bytes.length)
        ..setAll(0, carry)
        ..setAll(carry.length, bytes);
      final usableLength = joined.length - joined.length % h.blockAlign;
      final data = ByteData.sublistView(joined, 0, usableLength);
      var offset = 0;
      while (offset < usableLength) {
        var framePeak = 0.0;
        for (var channel = 0; channel < h.channels; channel++) {
          final sample = _sampleAt(
            data,
            offset + channel * (h.bitsPerSample ~/ 8),
            h,
          );
          framePeak = max(framePeak, sample.abs());
        }

        final bucket = totalFrames == 0
            ? 0
            : min(
                waveformPoints - 1,
                frameIndex * waveformPoints ~/ totalFrames,
              );
        peaks[bucket] = max(peaks[bucket], framePeak);
        sumSquares += framePeak * framePeak;
        rmsCount++;
        frameIndex++;
        offset += h.blockAlign;
        if (rmsCount == samplesPerWindow) {
          rms.add(_normalize(sqrt(sumSquares / rmsCount)));
          sumSquares = 0;
          rmsCount = 0;
        }
      }
      carry = Uint8List.fromList(joined.sublist(usableLength));
    }
    if (rmsCount > 0) rms.add(_normalize(sqrt(sumSquares / rmsCount)));
    return (rms: rms, peaks: peaks);
  }

  static double _sampleAt(ByteData d, int i, _WavHeader h) {
    switch ((h.formatTag, h.bitsPerSample)) {
      case (1, 16):
        return d.getInt16(i, Endian.little) / 32768;
      case (1, 24):
        var v =
            d.getUint8(i) |
            (d.getUint8(i + 1) << 8) |
            (d.getUint8(i + 2) << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        return v / 8388608;
      case (1, 32):
        return d.getInt32(i, Endian.little) / 2147483648;
      case (3, 32):
        return d.getFloat32(i, Endian.little).clamp(-1.0, 1.0);
      default:
        return 0;
    }
  }

  static double _normalize(double linear) {
    if (linear <= 0) return 0;
    final db = 20 * log(linear) / ln10;
    return ((db + 60) / 60).clamp(0.0, 1.0); // -60..0 dBFS -> 0..1
  }

  static double _toDb(double normalized) =>
      normalized * 60 - 60; // inverse of _normalize

  /// Finds contiguous loud regions, merges short gaps, drops short takes.
  static List<TrackRegion> _detectRegions(
    List<double> rms,
    Duration window, {
    required double silenceThresholdDb,
    required Duration minimumTrackDuration,
  }) {
    final loudNorm = _normalize(pow(10, silenceThresholdDb / 20).toDouble());
    final maxGapWindows = maxGap.inMilliseconds ~/ window.inMilliseconds;
    final minWindows =
        minimumTrackDuration.inMilliseconds ~/ window.inMilliseconds;

    final regions = <(int, int)>[]; // window index ranges
    int? start;
    var gap = 0;
    for (var i = 0; i < rms.length; i++) {
      final loud = _toDb(rms[i]) >= _toDb(loudNorm);
      if (loud) {
        start ??= i;
        gap = 0;
      } else if (start != null) {
        if (++gap > maxGapWindows) {
          regions.add((start, i - gap + 1));
          start = null;
          gap = 0;
        }
      }
    }
    if (start != null) regions.add((start, rms.length - gap));

    var index = 1;
    return [
      for (final (s, e) in regions)
        if (e - s >= minWindows)
          TrackRegion(
            start: window * s,
            end: window * e,
            name: 'Take ${index++}',
          ),
    ];
  }
}

class _WavHeader {
  const _WavHeader({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.blockAlign,
    required this.formatTag,
    required this.dataOffset,
    required this.dataLength,
    required this.duration,
    required this.windowDuration,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int blockAlign;
  final int formatTag;
  final int dataOffset;
  final int dataLength;
  final Duration duration;
  final Duration windowDuration;
}
