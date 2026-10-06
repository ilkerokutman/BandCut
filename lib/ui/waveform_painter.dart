import 'dart:math';

import 'package:flutter/material.dart';

import '../models/track_region.dart';

/// Renders downsampled peaks as a mirrored bar waveform, highlights
/// detected regions, and draws the playback position.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.peaks,
    required this.regions,
    required this.duration,
    required this.playhead,
    required this.colors,
  });

  static const double rulerHeight = 28;

  final List<double> peaks;
  final List<TrackRegion> regions;
  final Duration duration;
  final Duration playhead;
  final ColorScheme colors;

  double xFor(Duration t, double width) => duration.inMicroseconds == 0
      ? 0
      : t.inMicroseconds / duration.inMicroseconds * width;

  @override
  void paint(Canvas canvas, Size size) {
    final waveformRect = Rect.fromLTRB(0, rulerHeight, size.width, size.height);
    _paintRuler(canvas, size, waveformRect);
    _paintWaveform(canvas, waveformRect);
    _paintRegions(canvas, waveformRect);
    _paintPlayhead(canvas, size);
  }

  void _paintRuler(Canvas canvas, Size size, Rect waveformRect) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, rulerHeight),
      Paint()..color = colors.surfaceContainerLow,
    );
    canvas.drawLine(
      Offset(0, rulerHeight),
      Offset(size.width, rulerHeight),
      Paint()
        ..color = colors.outlineVariant
        ..strokeWidth = 1,
    );

    final durationSeconds =
        duration.inMicroseconds / Duration.microsecondsPerSecond;
    if (durationSeconds <= 0 || size.width <= 0) return;
    final interval = _tickInterval(durationSeconds, size.width);
    final minorInterval = interval / 5;
    final minorPaint = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = colors.outline
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    for (
      var seconds = 0.0;
      seconds <= durationSeconds + minorInterval / 2;
      seconds += minorInterval
    ) {
      final x = seconds / durationSeconds * size.width;
      final step = (seconds / minorInterval).round();
      final isMajor = step % 5 == 0;
      canvas.drawLine(
        Offset(x, rulerHeight - (isMajor ? 8 : 4)),
        Offset(x, rulerHeight),
        isMajor ? majorPaint : minorPaint,
      );
      if (!isMajor) continue;
      canvas.drawLine(
        Offset(x, waveformRect.top),
        Offset(x, waveformRect.bottom),
        gridPaint,
      );
      final label = TextPainter(
        text: TextSpan(
          text: _formatTime(Duration(seconds: seconds.round())),
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 4, 4));
    }
  }

  void _paintWaveform(Canvas canvas, Rect rect) {
    final centerY = rect.center.dy;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(rect.width, centerY),
      Paint()
        ..color = colors.outlineVariant.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
    if (peaks.isEmpty) return;

    final path = _waveformPath(rect);
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.onSurfaceVariant.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.outline.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  Path _waveformPath(Rect rect) {
    final path = Path();
    final centerY = rect.center.dy;
    final halfHeight = rect.height * 0.46;
    for (var i = 0; i < peaks.length; i++) {
      final x = peaks.length == 1 ? 0.0 : i / (peaks.length - 1) * rect.width;
      final y = centerY - max(0.75, peaks[i] * halfHeight);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    for (var i = peaks.length - 1; i >= 0; i--) {
      final x = peaks.length == 1 ? 0.0 : i / (peaks.length - 1) * rect.width;
      final y = centerY + max(0.75, peaks[i] * halfHeight);
      path.lineTo(x, y);
    }
    return path..close();
  }

  void _paintRegions(Canvas canvas, Rect rect) {
    final waveformPath = peaks.isEmpty ? null : _waveformPath(rect);
    final checkedColor = colors.brightness == Brightness.dark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF2E7D32);
    final uncheckedColor = colors.brightness == Brightness.dark
        ? const Color(0xFFEF5350)
        : colors.error;
    for (final region in regions) {
      final trackColor = region.enabled ? checkedColor : uncheckedColor;
      final x1 = xFor(region.start, rect.width);
      final x2 = xFor(region.end, rect.width);
      final regionRect = Rect.fromLTRB(x1, rect.top, x2, rect.bottom);
      canvas.drawRect(
        regionRect,
        Paint()..color = trackColor.withValues(alpha: 0.18),
      );
      if (waveformPath != null) {
        canvas.save();
        canvas.clipRect(regionRect);
        canvas.drawPath(
          waveformPath,
          Paint()
            ..color = trackColor.withValues(alpha: 0.86)
            ..style = PaintingStyle.fill,
        );
        canvas.restore();
      }
      final edgePaint = Paint()
        ..color = trackColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(x1, rect.top), Offset(x1, rect.bottom), edgePaint);
      canvas.drawLine(Offset(x2, rect.top), Offset(x2, rect.bottom), edgePaint);
      _paintRegionLabel(canvas, region, regionRect, trackColor);
    }
  }

  void _paintRegionLabel(
    Canvas canvas,
    TrackRegion region,
    Rect regionRect,
    Color trackColor,
  ) {
    if (regionRect.width < 24) return;
    final label = TextPainter(
      text: TextSpan(
        text: region.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: max(0, regionRect.width - 10));
    final boxWidth = label.width + 8;
    final left = regionRect.center.dx - boxWidth / 2;
    final top = regionRect.bottom - label.height - 6;
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxWidth, label.height + 4),
      const Radius.circular(3),
    );
    canvas.drawRRect(box, Paint()..color = trackColor.withValues(alpha: 0.92));
    label.paint(canvas, Offset(left + 4, top + 2));
  }

  void _paintPlayhead(Canvas canvas, Size size) {
    final x = xFor(playhead, size.width).clamp(0.0, size.width);
    final playPaint = Paint()
      ..color = colors.error
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), playPaint);

    final label = TextPainter(
      text: TextSpan(
        text: _formatTime(playhead, includeTenths: true),
        style: TextStyle(
          color: colors.onError,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const horizontalPadding = 5.0;
    const verticalPadding = 2.0;
    final labelWidth = label.width + horizontalPadding * 2;
    final left = (x - labelWidth / 2).clamp(0.0, size.width - labelWidth);
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 2, labelWidth, label.height + verticalPadding * 2),
      const Radius.circular(3),
    );
    canvas.drawRRect(box, Paint()..color = colors.error);
    label.paint(canvas, Offset(left + horizontalPadding, 2 + verticalPadding));
  }

  double _tickInterval(double durationSeconds, double width) {
    final minimumSeconds = durationSeconds * 90 / width;
    const intervals = <double>[
      1,
      2,
      5,
      10,
      15,
      30,
      60,
      120,
      300,
      600,
      900,
      1800,
      3600,
      7200,
      18000,
    ];
    return intervals.firstWhere(
      (interval) => interval >= minimumSeconds,
      orElse: () => 36000,
    );
  }

  String _formatTime(Duration value, {bool includeTenths = false}) {
    String two(int number) => number.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final base = hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
    if (!includeTenths) return base;
    final tenths = value.inMilliseconds.remainder(1000) ~/ 100;
    return '$base.$tenths';
  }

  @override
  bool shouldRepaint(WaveformPainter old) => true;
}
