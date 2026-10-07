import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/analysis_settings.dart';
import '../models/track_region.dart';
import '../services/analysis_settings_store.dart';
import '../services/export_service.dart';
import '../services/project_name_service.dart';
import '../services/wav_analyzer.dart';
import 'waveform_painter.dart';

/// Main BandCut screen: import WAV, review detected takes, label, export.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _minWaveformZoom = 1.0;
  static const _maxWaveformZoom = 128.0;

  final _player = AudioPlayer();
  final _waveformScrollController = ScrollController();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  File? _sourceFile;
  String? _projectName;
  AnalysisResult? _result;
  Duration _position = Duration.zero;
  Duration? _scrubPosition;
  Duration? _pendingSeekPosition;
  double _waveformZoom = _minWaveformZoom;
  AnalysisSettings _analysisSettings = AnalysisSettings.defaults;

  bool _settingsLoaded = false;
  bool _isPlaying = false;
  bool _analyzing = false;
  bool _exporting = false;
  (int, int)? _exportProgress;
  String? _error;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _positionSub = _player.positionStream.listen((position) {
      if (mounted && _pendingSeekPosition == null) {
        setState(() => _position = position);
      }
    });
    _playingSub = _player.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _loadAnalysisSettings();
  }

  Future<void> _loadAnalysisSettings() async {
    try {
      final settings = await AnalysisSettingsStore.load();
      if (mounted) {
        setState(() {
          _analysisSettings = settings;
          _settingsLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _settingsLoaded = true;
          _error = 'Could not load analysis settings: $error';
        });
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _positionSub?.cancel();
    _playingSub?.cancel();
    _waveformScrollController.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav'],
    );
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null) return;

    final projectName =
        ProjectNameService.fromWavPath(path) ?? await _requestProjectName();
    if (projectName == null) return;

    final file = File(path);
    setState(() {
      _sourceFile = file;
      _projectName = projectName;
      _result = null;
      _error = null;
      _scrubPosition = null;
      _pendingSeekPosition = null;
      _waveformZoom = _minWaveformZoom;
    });
    await _analyzeFile(file, loadPlayer: true);
  }

  Future<String?> _requestProjectName() async {
    final formKey = GlobalKey<FormState>();
    var value = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Project name required'),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'e.g. 20261005',
            ),
            onChanged: (text) => value = text,
            validator: (text) =>
                (text?.trim().isEmpty ?? true) ? 'Enter a project name.' : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, value.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeFile(File file, {bool loadPlayer = false}) async {
    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      if (loadPlayer) await _player.setFilePath(file.path);
      final result = await WavAnalyzer.analyze(
        file,
        settings: _analysisSettings,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _redetectTracks() async {
    final source = _sourceFile;
    if (source == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-detect tracks?'),
        content: const Text(
          'This replaces all renamed, adjusted, added, and deleted tracks '
          'using the current detection settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-detect'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _analyzeFile(source);
  }

  Future<void> _seekTo(Duration position) async {
    _pendingSeekPosition = position;
    setState(() => _position = position);
    try {
      await _player.seek(position);
    } finally {
      if (_pendingSeekPosition == position) {
        _pendingSeekPosition = null;
        if (mounted) setState(() => _position = position);
      }
    }
  }

  Duration? _scrubPositionFor(Offset local, double width) {
    final result = _result;
    if (result == null || result.duration.inMicroseconds == 0) return null;
    final fraction = (local.dx / width).clamp(0.0, 1.0);
    const precisionMicroseconds = 100000;
    final rawMicroseconds = (result.duration.inMicroseconds * fraction).round();
    final roundedMicroseconds =
        ((rawMicroseconds + precisionMicroseconds ~/ 2) ~/
            precisionMicroseconds) *
        precisionMicroseconds;
    return Duration(
      microseconds: roundedMicroseconds
          .clamp(0, result.duration.inMicroseconds)
          .toInt(),
    );
  }

  void _previewScrub(Offset local, double width) {
    final position = _scrubPositionFor(local, width);
    if (position == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _scrubPosition = position);
  }

  void _commitScrub() {
    final position = _scrubPosition;
    if (position == null) return;
    setState(() => _scrubPosition = null);
    unawaited(_seekTo(position));
  }

  void _cancelScrub() {
    if (_scrubPosition != null) setState(() => _scrubPosition = null);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.space ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final isEditing =
        focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isEditing) return false;
    unawaited(_togglePlayback());
    return true;
  }

  Future<void> _togglePlayback() async {
    if (_sourceFile == null) return;
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    await _player.seek(_position);
    unawaited(_player.play());
  }

  Future<void> _toggleTrackPlayback(TrackRegion region) async {
    final isCurrent =
        _position >= region.start && _position < region.end && _isPlaying;
    if (isCurrent) {
      await _player.pause();
      return;
    }
    await _player.seek(region.start);
    setState(() => _position = region.start);
    if (!_isPlaying) unawaited(_player.play());
  }

  void _setRegionStart(TrackRegion region) {
    if (_position >= region.end) {
      _showBoundaryError('Start must be before the track end.');
      return;
    }
    setState(() => region.start = _position);
  }

  void _setRegionEnd(TrackRegion region) {
    if (_position <= region.start) {
      _showBoundaryError('End must be after the track start.');
      return;
    }
    setState(() => region.end = _position);
  }

  Future<void> _renameRegion(TrackRegion region) async {
    final formKey = GlobalKey<FormState>();
    var name = region.name;
    final updatedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename track'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: region.name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Filename'),
            onChanged: (value) => name = value,
            validator: (value) =>
                (value?.trim().isEmpty ?? true) ? 'Enter a filename.' : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, name.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, name.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (updatedName != null && mounted) {
      setState(() => region.name = updatedName);
    }
  }

  void _deleteRegion(TrackRegion region) {
    final regions = _result?.regions;
    if (regions == null) return;
    if (_isPlaying && _position >= region.start && _position < region.end) {
      unawaited(_player.pause());
    }
    setState(() => regions.remove(region));
  }

  Future<void> _removeAllTracks() async {
    final regions = _result?.regions;
    if (regions == null || regions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all tracks?'),
        content: const Text(
          'This removes every track from the session. You can restore '
          'automatically detected tracks with Re-detect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    if (_isPlaying) await _player.pause();
    if (mounted) setState(regions.clear);
  }

  void _addTrackAtPlayhead() {
    final result = _result;
    if (result == null || _position >= result.duration) return;
    final containsPlayhead = result.regions.any(
      (region) => _position >= region.start && _position < region.end,
    );
    if (containsPlayhead) {
      _showBoundaryError('The playhead is already inside a track.');
      return;
    }

    final laterStarts =
        result.regions
            .map((region) => region.start)
            .where((start) => start > _position)
            .toList()
          ..sort();
    final end = laterStarts.isEmpty ? result.duration : laterStarts.first;
    if (end <= _position) return;
    final usedNumbers = result.regions
        .map((region) => RegExp(r'^Take (\d+)$').firstMatch(region.name))
        .whereType<RegExpMatch>()
        .map((match) => int.parse(match.group(1)!));
    final nextNumber =
        usedNumbers.fold<int>(
          0,
          (highest, value) => value > highest ? value : highest,
        ) +
        1;

    setState(() {
      result.regions.add(
        TrackRegion(start: _position, end: end, name: 'Take $nextNumber'),
      );
      result.regions.sort((a, b) => a.start.compareTo(b.start));
    });
  }

  void _showBoundaryError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _setWaveformZoom(double value, double viewportWidth, {double? focalX}) {
    final zoom = value.clamp(_minWaveformZoom, _maxWaveformZoom);
    if (zoom == _waveformZoom) return;
    final focalPoint = (focalX ?? viewportWidth / 2).clamp(0.0, viewportWidth);
    final oldWidth = viewportWidth * _waveformZoom;
    final oldOffset = _waveformScrollController.hasClients
        ? _waveformScrollController.offset
        : 0.0;
    final focalFraction = (oldOffset + focalPoint) / oldWidth;

    setState(() => _waveformZoom = zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_waveformScrollController.hasClients) return;
      final target = focalFraction * viewportWidth * zoom - focalPoint;
      _waveformScrollController.jumpTo(
        target.clamp(0.0, _waveformScrollController.position.maxScrollExtent),
      );
    });
  }

  void _handleWaveformScroll(PointerSignalEvent event, double viewportWidth) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs()) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      final factor = math.exp(-scrollEvent.scrollDelta.dy * 0.002);
      _setWaveformZoom(
        _waveformZoom * factor,
        viewportWidth,
        focalX: scrollEvent.localPosition.dx,
      );
    });
  }

  Future<void> _openAnalysisSettings() async {
    var thresholdDb = _analysisSettings.silenceThresholdDb;
    var minimumDurationSeconds = _analysisSettings
        .minimumTrackDuration
        .inSeconds
        .toDouble();
    final settings = await showDialog<AnalysisSettings>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Track detection settings'),
          content: SizedBox(
            width: 420,
            child: Form(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Silence detection threshold: '
                    '${thresholdDb.round()} dBFS',
                  ),
                  Slider(
                    value: thresholdDb,
                    min: -60,
                    max: -5,
                    divisions: 55,
                    label: '${thresholdDb.round()} dBFS',
                    onChanged: (value) =>
                        setDialogState(() => thresholdDb = value),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Minimum track duration: '
                    '${minimumDurationSeconds.round()} seconds',
                  ),
                  Slider(
                    value: minimumDurationSeconds,
                    min: 5,
                    max: 180,
                    divisions: 35,
                    label: '${minimumDurationSeconds.round()} s',
                    onChanged: (value) =>
                        setDialogState(() => minimumDurationSeconds = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                AnalysisSettings(
                  silenceThresholdDb: thresholdDb,
                  minimumTrackDuration: Duration(
                    seconds: minimumDurationSeconds.round(),
                  ),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (settings == null) return;

    try {
      await AnalysisSettingsStore.save(settings);
      if (!mounted) return;
      setState(() => _analysisSettings = settings);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save analysis settings: $error');
      }
      return;
    }

    final source = _sourceFile;
    if (source == null || _result == null || !mounted) return;
    final reanalyze = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply new detection settings?'),
        content: const Text(
          'The settings are saved. Choose whether to keep the current '
          'detected tracks or check this recording again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check with new values'),
          ),
        ],
      ),
    );
    if (reanalyze ?? false) await _analyzeFile(source);
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Image.asset(
          'assets/images/bandcut_icon.png',
          width: 72,
          height: 72,
        ),
        title: const Text('BandCut'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'BandCut turns long rehearsal WAV recordings into named MP3 '
            'tracks. Open a WAV, review the detected regions, scrub and zoom '
            'the waveform, fine-tune track boundaries, choose which tracks '
            'to export, then export the session as individual MP3 files.\n\n'
            'This software uses FFmpeg under the LGPL v2.1 or later and LAME '
            'under the LGPL v2.0 or later.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    final source = _sourceFile;
    final projectName = _projectName;
    final regions = _result?.regions ?? [];
    if (source == null || projectName == null || regions.isEmpty) return;

    final dirPath = await FilePicker.getDirectoryPath(dialogTitle: 'Export to');
    if (dirPath == null) return;

    setState(() {
      _exporting = true;
      _exportProgress = (0, regions.where((r) => r.enabled).length);
      _error = null;
    });
    try {
      await ExportService.exportAll(
        source: source,
        projectName: projectName,
        regions: regions,
        outputDir: Directory(dirPath),
        onProgress: (done, total) =>
            setState(() => _exportProgress = (done, total)),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Exported to $dirPath')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 80,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/images/bandcut_icon.png',
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 10),
            Text(_projectName == null ? 'BandCut' : 'BandCut : $_projectName'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showAboutDialog,
            tooltip: 'About BandCut',
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            onPressed: (_settingsLoaded && !_analyzing)
                ? _openAnalysisSettings
                : null,
            tooltip: 'Track detection settings',
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          if (result != null) ...[
            _SessionInfoBar(
              result: result,
              analyzing: _analyzing,
              exporting: _exporting,
              exportProgress: _exportProgress,
              error: _error,
              onPick: _pickFile,
              onRedetect: _redetectTracks,
              onExport: _export,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final waveformWidth =
                          constraints.maxWidth * _waveformZoom;
                      return SizedBox(
                        height: 160,
                        child: Listener(
                          onPointerSignal: (event) => _handleWaveformScroll(
                            event,
                            constraints.maxWidth,
                          ),
                          child: Scrollbar(
                            controller: _waveformScrollController,
                            thumbVisibility: _waveformZoom > _minWaveformZoom,
                            trackVisibility: _waveformZoom > _minWaveformZoom,
                            thickness: 8,
                            radius: const Radius.circular(4),
                            scrollbarOrientation: ScrollbarOrientation.bottom,
                            child: SingleChildScrollView(
                              controller: _waveformScrollController,
                              scrollDirection: Axis.horizontal,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: _waveformZoom > _minWaveformZoom
                                      ? 12
                                      : 0,
                                ),
                                child: GestureDetector(
                                  onTapDown: (details) => _previewScrub(
                                    details.localPosition,
                                    waveformWidth,
                                  ),
                                  onTapUp: (_) => _commitScrub(),
                                  onTapCancel: _cancelScrub,
                                  onHorizontalDragStart: (details) =>
                                      _previewScrub(
                                        details.localPosition,
                                        waveformWidth,
                                      ),
                                  onHorizontalDragUpdate: (details) =>
                                      _previewScrub(
                                        details.localPosition,
                                        waveformWidth,
                                      ),
                                  onHorizontalDragEnd: (_) => _commitScrub(),
                                  onHorizontalDragCancel: _cancelScrub,
                                  child: CustomPaint(
                                    size: Size(
                                      waveformWidth,
                                      _waveformZoom > _minWaveformZoom
                                          ? 140
                                          : 150,
                                    ),
                                    painter: WaveformPainter(
                                      peaks: result.peaks,
                                      regions: result.regions,
                                      duration: result.duration,
                                      playhead: _scrubPosition ?? _position,
                                      colors: Theme.of(context).colorScheme,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: _waveformZoom <= _minWaveformZoom
                              ? null
                              : () => _setWaveformZoom(
                                  _waveformZoom / 2,
                                  constraints.maxWidth,
                                ),
                          tooltip: 'Zoom out',
                          icon: const Icon(Icons.zoom_out),
                        ),
                        Text('${_waveformZoom.toStringAsFixed(1)}×'),
                        IconButton(
                          onPressed: _waveformZoom >= _maxWaveformZoom
                              ? null
                              : () => _setWaveformZoom(
                                  _waveformZoom * 2,
                                  constraints.maxWidth,
                                ),
                          tooltip: 'Zoom in',
                          icon: const Icon(Icons.zoom_in),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _TransportBar(
              isPlaying: _isPlaying,
              position: _scrubPosition ?? _position,
              duration: result.duration,
              onTogglePlayback: _togglePlayback,
              onAddTrack: _addTrackAtPlayhead,
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    'Tracks',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: result.regions.isEmpty ? null : _removeAllTracks,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Remove all tracks'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _TrackList(
                regions: result.regions,
                position: _position,
                isPlaying: _isPlaying,
                onTogglePlayback: _toggleTrackPlayback,
                onRename: _renameRegion,
                onSetStart: _setRegionStart,
                onSetEnd: _setRegionEnd,
                onDelete: _deleteRegion,
                onChanged: () => setState(() {}),
              ),
            ),
          ] else
            Expanded(
              child: _EmptyState(
                analyzing: _analyzing,
                error: _error,
                onPick: _pickFile,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.analyzing,
    required this.error,
    required this.onPick,
  });

  final bool analyzing;
  final String? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/bandcut_icon.png',
                width: 180,
                height: 180,
              ),
            ),
            const SizedBox(height: 20),
            Text('BandCut', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            if (analyzing) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Analyzing WAV…'),
            ] else
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.audio_file),
                label: const Text('Pick a WAV file to start a session'),
              ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SessionInfoBar extends StatelessWidget {
  const _SessionInfoBar({
    required this.result,
    required this.analyzing,
    required this.exporting,
    required this.exportProgress,
    required this.error,
    required this.onPick,
    required this.onRedetect,
    required this.onExport,
  });

  final AnalysisResult result;
  final bool analyzing;
  final bool exporting;
  final (int, int)? exportProgress;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onRedetect;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: analyzing || exporting ? null : onPick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Change WAV…'),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${_fmt(result.duration)} • ${result.sampleRate} Hz • '
                  '${result.channels} ch • ${result.regions.length} tracks',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: analyzing || exporting ? null : onRedetect,
                icon: analyzing
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(analyzing ? 'Analyzing…' : 'Re-detect'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: exporting || analyzing ? null : onExport,
                icon: exporting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  exporting && exportProgress != null
                      ? 'Exporting ${exportProgress!.$1}/${exportProgress!.$2}'
                      : 'Export MP3s',
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onTogglePlayback,
    required this.onAddTrack,
  });

  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlayback;
  final VoidCallback onAddTrack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          IconButton.filled(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: onTogglePlayback,
          ),
          const SizedBox(width: 8),
          Text('${_fmtPrecise(position)} / ${_fmt(duration)}'),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: onAddTrack,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add track'),
          ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.regions,
    required this.position,
    required this.isPlaying,
    required this.onTogglePlayback,
    required this.onRename,
    required this.onSetStart,
    required this.onSetEnd,
    required this.onDelete,
    required this.onChanged,
  });

  final List<TrackRegion> regions;
  final Duration position;
  final bool isPlaying;
  final ValueChanged<TrackRegion> onTogglePlayback;
  final ValueChanged<TrackRegion> onRename;
  final ValueChanged<TrackRegion> onSetStart;
  final ValueChanged<TrackRegion> onSetEnd;
  final ValueChanged<TrackRegion> onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) {
      return const Center(child: Text('No takes detected.'));
    }
    return ListView.builder(
      itemCount: regions.length,
      itemBuilder: (context, i) {
        final region = regions[i];
        final isCurrent =
            isPlaying && position >= region.start && position < region.end;
        return ListTile(
          leading: Checkbox(
            value: region.enabled,
            onChanged: (v) {
              region.enabled = v ?? true;
              onChanged();
            },
          ),
          title: Text(
            region.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(
                '${_fmt(region.start)} – ${_fmt(region.end)}  '
                '(${_fmt(region.duration)})',
              ),
              const SizedBox(width: 6),
              _BoundaryButton(
                icon: Icons.north_east,
                tooltip: 'Set start to playhead',
                onPressed: () => onSetStart(region),
              ),
              _BoundaryButton(
                icon: Icons.south_east,
                tooltip: 'Set end to playhead',
                onPressed: () => onSetEnd(region),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename track',
                onPressed: () => onRename(region),
              ),
              IconButton(
                icon: Icon(
                  isCurrent
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                tooltip: isCurrent ? 'Pause' : 'Play from track start',
                onPressed: () => onTogglePlayback(region),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete track',
                onPressed: () => onDelete(region),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BoundaryButton extends StatelessWidget {
  const _BoundaryButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      padding: EdgeInsets.zero,
      iconSize: 15,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

String _fmt(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:'
      '${two(d.inSeconds % 60)}';
}

String _fmtPrecise(Duration duration) {
  final base = _fmt(duration);
  final tenths = duration.inMilliseconds.remainder(1000) ~/ 100;
  return '$base.$tenths';
}
