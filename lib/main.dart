import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const VideoCompressApp());
}

class VideoCompressApp extends StatelessWidget {
  const VideoCompressApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00D26A),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SqueezeClip',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF030504),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          color: Color(0xFF0A110D),
          margin: EdgeInsets.zero,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

enum QualityPreset {
  high('high', 'High', '1920p, biggest quality'),
  balanced('balanced', 'Balanced', '1280p, sane default'),
  small('small', 'Small', '960p, smaller files'),
  custom('custom', 'Custom', 'Use your own target height');

  const QualityPreset(this.value, this.label, this.hint);

  final String value;
  final String label;
  final String hint;
}

enum RecentSource {
  camera('camera', 'Camera'),
  telegram('telegram', 'Telegram'),
  downloads('downloads', 'Downloads');

  const RecentSource(this.value, this.label);

  final String value;
  final String label;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('video_compress_app/native');
  static const _progressChannel = EventChannel('video_compress_app/progress');

  final List<VideoItem> _selectedVideos = [];
  final List<VideoItem> _recentVideos = [];
  final List<LogEntry> _logEntries = [];
  final TextEditingController _suffixController = TextEditingController(text: '_tg');
  final TextEditingController _customHeightController = TextEditingController(text: '1440');

  StreamSubscription<dynamic>? _progressSub;
  bool _busy = false;
  bool _loadingRecents = true;
  RecentSource _recentSource = RecentSource.camera;
  bool _overwriteExistingByDefault = false;
  String _status = 'Loading camera videos...';
  String _speed = 'idle';
  double _progress = 0;
  int _elapsedMs = 0;
  int _currentEtaMs = 0;
  QualityPreset _quality = QualityPreset.balanced;
  String? _activeSource;
  bool _stopAfterCurrent = false;

  void _setStatus(String status, {String? fileName, LogKind kind = LogKind.info}) {
    setState(() {
      _status = status;
      _logEntries.insert(
        0,
        LogEntry(
          message: status,
          fileName: fileName,
          kind: kind,
          at: DateTime.now(),
        ),
      );
      if (_logEntries.length > 80) {
        _logEntries.removeRange(80, _logEntries.length);
      }
    });
  }

  String get _normalizedSuffix {
    final raw = _suffixController.text.trim();
    if (raw.isEmpty) return '_tg';
    return raw.startsWith('_') ? raw : '_$raw';
  }

  @override
  void initState() {
    super.initState();
    _bindProgress();
    _requestNotificationPermission();
    _loadRecents();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _suffixController.dispose();
    _customHeightController.dispose();
    super.dispose();
  }

  int get _customHeight {
    final parsed = int.tryParse(_customHeightController.text.trim()) ?? 1440;
    return parsed.clamp(320, 4320);
  }

  void _bindProgress() {
    _progressSub = _progressChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final progress = (event['progress'] as num?)?.toDouble() ?? 0;
      final speed = event['speed']?.toString() ?? 'idle';
      final elapsedMs = (event['elapsedMs'] as num?)?.toInt() ?? 0;
      final etaMs = (event['etaMs'] as num?)?.toInt() ?? 0;
      setState(() {
        _progress = progress.clamp(0, 1);
        _speed = speed;
        _elapsedMs = elapsedMs;
        _currentEtaMs = etaMs;
      });
    });
  }

  Future<void> _loadRecents() async {
    final status = await Permission.videos.request();
    if (!status.isGranted) {
      setState(() {
        _loadingRecents = false;
      });
      _setStatus('No video permission. Android decided to be annoying again.', kind: LogKind.error);
      return;
    }

    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'getRecentCameraVideos',
        {'limit': 8, 'source': _recentSource.value},
      );
      final videos = <VideoItem>[];
      for (final item in raw ?? <dynamic>[]) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final video = VideoItem.fromMap(map);
        videos.add(await _hydrateVideo(video));
      }
      setState(() {
        _recentVideos
          ..clear()
          ..addAll(videos);
        _loadingRecents = false;
      });
      _setStatus(
        videos.isEmpty ? 'No recent ${_recentSource.label.toLowerCase()} videos found.' : 'Recent ${_recentSource.label.toLowerCase()} videos loaded.',
        kind: videos.isEmpty ? LogKind.warning : LogKind.success,
      );
    } on PlatformException catch (e) {
      setState(() {
        _loadingRecents = false;
      });
      _setStatus(_friendlyErrorMessage(e), kind: LogKind.error);
    }
  }

  Future<void> _requestNotificationPermission() async {
    await Permission.notification.request();
  }

  Future<VideoItem> _attachThumbnail(VideoItem video) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'getThumbnail',
        {'source': video.source},
      );
      if (raw is Uint8List) {
        return video.copyWith(thumbnailBytes: raw);
      }
      if (raw is List) {
        return video.copyWith(thumbnailBytes: Uint8List.fromList(raw.cast<int>()));
      }
      if (raw is String) {
        return video.copyWith(thumbnailBytes: base64Decode(raw));
      }
    } on PlatformException {
      return video;
    }
    return video;
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'hevc'],
      dialogTitle: 'Pick videos',
    );
    if (result == null) return;

    final picked = <VideoItem>[];
    for (final file in result.files) {
      final source = file.identifier ?? file.path;
      if (source == null || source.isEmpty) continue;
      final described = await _describeSource(source);
      if (described != null) {
        picked.add(await _hydrateVideo(described));
      }
    }

    if (picked.isEmpty) return;
    setState(() {
      _selectedVideos
        ..clear()
        ..addAll(picked);
    });
    _setStatus('Picked ${picked.length} video(s).', kind: LogKind.success);
  }

  Future<VideoItem?> _describeSource(String source) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'describeSource',
        {'source': source},
      );
      if (raw == null) return null;
      return VideoItem.fromMap(raw);
    } on PlatformException {
      return null;
    }
  }

  Future<VideoItem> _hydrateVideo(VideoItem video) async {
    final withThumb = await _attachThumbnail(video);
    return _attachExistingOutput(withThumb);
  }

  Future<VideoItem> _attachExistingOutput(VideoItem video) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'findExistingCompressed',
        {'source': video.source, 'suffix': _normalizedSuffix},
      );
      if (raw == null) return video;
      final existing = VideoItem.fromMap(raw);
      return video.copyWith(
        outputSource: existing.source,
        outputName: existing.name,
        outputSubtitle: existing.subtitle,
        outputSizeBytes: existing.sizeBytes,
        outputBitrate: existing.bitrate,
        outputFps: existing.fps,
        replaceExisting: _overwriteExistingByDefault,
        state: VideoState.existing,
      );
    } on PlatformException {
      return video;
    }
  }

  Future<void> _loadLatestCameraVideo() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getLatestCameraVideo');
      if (raw == null) return;
      final video = await _hydrateVideo(VideoItem.fromMap(raw));
      setState(() {
        _selectedVideos
          ..clear()
          ..add(video);
      });
      _setStatus('Loaded last camera video.', fileName: video.name, kind: LogKind.success);
    } on PlatformException catch (e) {
      _setStatus(_friendlyErrorMessage(e), kind: LogKind.error);
    }
  }

  Future<void> _compressLatestCameraVideo() async {
    if (_busy) return;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getLatestCameraVideo');
      if (raw == null) return;
      final video = await _hydrateVideo(VideoItem.fromMap(raw));
      setState(() {
        _selectedVideos
          ..clear()
          ..add(video);
      });
      _setStatus('Loaded last camera video and starting compression.', fileName: video.name, kind: LogKind.success);
      await _compress();
    } on PlatformException catch (e) {
      _setStatus(_friendlyErrorMessage(e), kind: LogKind.error);
    }
  }

  Future<void> _queueAllNewRecent() async {
    if (_busy) return;
    final fresh = _recentVideos.where((video) => video.outputSource == null).toList();
    if (fresh.isEmpty) {
      _setStatus('No new recent videos to queue. For once the app is ahead of you.', kind: LogKind.warning);
      return;
    }
    setState(() {
      _selectedVideos
        ..clear()
        ..addAll(fresh);
    });
    _setStatus('Queued ${fresh.length} fresh recent video(s).', kind: LogKind.success);
  }

  Future<void> _setRecentSource(RecentSource source) async {
    if (_busy || _recentSource == source) return;
    setState(() {
      _recentSource = source;
      _loadingRecents = true;
    });
    await _loadRecents();
  }

  Future<void> _applyOutputSettings() async {
    if (_busy) return;
    setState(() {});
    final refreshed = <VideoItem>[];
    for (final video in _selectedVideos) {
      refreshed.add(await _hydrateVideo(video.copyWith(
        outputSource: null,
        outputName: null,
        outputSubtitle: null,
        outputSizeBytes: null,
        outputBitrate: null,
        outputFps: null,
        errorMessage: null,
        state: VideoState.idle,
      )));
    }
    setState(() {
      _selectedVideos
        ..clear()
        ..addAll(refreshed);
    });
    await _loadRecents();
    _setStatus('Output settings applied. Existing-file detection refreshed.', kind: LogKind.success);
  }

  Future<void> _compress() async {
    if (_selectedVideos.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _speed = 'idle';
      _elapsedMs = 0;
      _currentEtaMs = 0;
      _stopAfterCurrent = false;
    });
    _setStatus('Starting compression...', kind: LogKind.info);

    try {
      for (var i = 0; i < _selectedVideos.length; i++) {
        final current = _selectedVideos[i];
        if (current.state == VideoState.existing && !(current.replaceExisting || _overwriteExistingByDefault)) {
          setState(() {
            _selectedVideos[i] = current.copyWith(state: VideoState.skipped);
          });
          _setStatus(
            'Skipped ${current.name}: existing compressed file already there.',
            fileName: current.name,
            kind: LogKind.warning,
          );
          continue;
        }
        setState(() {
          _activeSource = current.source;
          _progress = 0;
          _speed = 'idle';
          _elapsedMs = 0;
          _currentEtaMs = 0;
          _selectedVideos[i] = current.copyWith(
            state: VideoState.compressing,
            outputSource: current.replaceExisting ? null : current.outputSource,
            outputName: current.replaceExisting ? null : current.outputName,
            outputSizeBytes: current.replaceExisting ? null : current.outputSizeBytes,
            outputBitrate: current.replaceExisting ? null : current.outputBitrate,
            outputFps: current.replaceExisting ? null : current.outputFps,
            errorMessage: null,
          );
        });
        _setStatus(
          'Compressing ${i + 1}/${_selectedVideos.length}: ${current.name}',
          fileName: current.name,
          kind: LogKind.info,
        );

        final raw = await _channel.invokeMapMethod<String, dynamic>(
          'compressVideo',
          {
            'source': current.source,
            'quality': _quality.value,
            'customHeight': _customHeight,
            'suffix': _normalizedSuffix,
          },
        );

        if (raw != null) {
          final output = VideoItem.fromMap(raw);
          setState(() {
            _selectedVideos[i] = _selectedVideos[i].copyWith(
              state: VideoState.done,
              outputSource: output.source,
              outputName: output.name,
              outputSubtitle: output.subtitle,
              outputSizeBytes: output.sizeBytes,
              outputBitrate: output.bitrate,
              outputFps: output.fps,
              errorMessage: null,
              replaceExisting: false,
            );
          });
          _setStatus('Compressed ${output.name}', fileName: output.name, kind: LogKind.success);
        }
        if (_stopAfterCurrent) {
          setState(() {
            _busy = false;
            _activeSource = null;
            _progress = 0;
            _speed = 'idle';
            _elapsedMs = 0;
            _currentEtaMs = 0;
            _stopAfterCurrent = false;
          });
          _setStatus('Stopped after current file, like requested.', kind: LogKind.warning);
          await _loadRecents();
          return;
        }
      }

      setState(() {
        _busy = false;
        _activeSource = null;
        _progress = 0;
        _speed = 'idle';
        _elapsedMs = 0;
        _currentEtaMs = 0;
        _stopAfterCurrent = false;
      });
      _setStatus('Done. Files were saved next to the originals.', kind: LogKind.success);
      await _loadRecents();
    } on PlatformException catch (e) {
      final activeItem = _selectedVideos.cast<VideoItem?>().firstWhere(
            (item) => item?.source == _activeSource,
            orElse: () => null,
          );
      setState(() {
        final failedIndex = _selectedVideos.indexWhere((item) => item.source == _activeSource);
        if (failedIndex != -1 && e.code != 'cancelled') {
          _selectedVideos[failedIndex] = _selectedVideos[failedIndex].copyWith(
            state: VideoState.failed,
            errorMessage: e.message ?? 'Compression failed',
          );
        }
        _busy = false;
        _activeSource = null;
        _progress = 0;
        _speed = 'idle';
        _elapsedMs = 0;
        _currentEtaMs = 0;
        _stopAfterCurrent = false;
      });
      _setStatus(
        e.code == 'cancelled' ? 'Compression cancelled.' : _friendlyErrorMessage(e),
        fileName: activeItem?.name,
        kind: e.code == 'cancelled' ? LogKind.warning : LogKind.error,
      );
    }
  }

  Future<void> _cancelCurrent() async {
    if (!_busy) return;
    try {
      await _channel.invokeMethod<void>('cancelCompression');
      setState(() {
        final index = _selectedVideos.indexWhere((item) => item.source == _activeSource);
        if (index != -1) {
          _selectedVideos[index] = _selectedVideos[index].copyWith(
            state: VideoState.cancelled,
            errorMessage: 'Compression cancelled by user',
          );
        }
        _busy = false;
        _activeSource = null;
        _progress = 0;
        _speed = 'idle';
        _elapsedMs = 0;
        _currentEtaMs = 0;
        _stopAfterCurrent = false;
      });
      _setStatus('Current compression cancelled.', kind: LogKind.warning);
    } on PlatformException catch (e) {
      _setStatus(_friendlyErrorMessage(e), kind: LogKind.error);
    }
  }

  void _requestStopAfterCurrent() {
    if (!_busy) return;
    setState(() {
      _stopAfterCurrent = true;
    });
    _setStatus('Will stop after current file.', kind: LogKind.info);
  }

  Future<void> _openVideo(String source) async {
    try {
      await _channel.invokeMethod<void>('openVideo', {'source': source});
    } on PlatformException catch (e) {
      _setStatus(_friendlyErrorMessage(e), kind: LogKind.error);
    }
  }

  Future<void> _shareSelected({required bool telegramOnly}) async {
    final sources = _selectedVideos
        .where((video) => video.shareSelected && video.outputSource != null)
        .map((video) => video.outputSource!)
        .toList();
    if (sources.isEmpty) {
      _setStatus('Mark some compressed files first. Telepathy is not implemented.', kind: LogKind.warning);
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'shareVideos',
        {
          'sources': sources,
          'telegramOnly': telegramOnly,
        },
      );
      setState(() {
        final sharedSources = sources.toSet();
        for (var i = 0; i < _selectedVideos.length; i++) {
          if (sharedSources.contains(_selectedVideos[i].outputSource)) {
            _selectedVideos[i] = _selectedVideos[i].copyWith(state: VideoState.shared);
          }
        }
      });
      _setStatus(
        telegramOnly ? 'Sharing to Telegram...' : 'Opening system share sheet...',
        kind: LogKind.success,
      );
    } on PlatformException catch (e) {
      _setStatus(_friendlyErrorMessage(e), kind: LogKind.error);
    }
  }

  void _useRecent(VideoItem video) {
    setState(() {
      _selectedVideos
        ..clear()
        ..add(video);
    });
    _setStatus('Selected ${video.name}. Tap compress and stop staring at it.', fileName: video.name, kind: LogKind.info);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${video.name} added to selection'),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  void _clearSelection() {
    if (_busy) return;
    setState(() {
      _selectedVideos.clear();
      _progress = 0;
      _speed = 'idle';
      _elapsedMs = 0;
      _currentEtaMs = 0;
      _activeSource = null;
    });
    _setStatus('Selection cleared.', kind: LogKind.info);
  }

  void _removeSelectedVideo(VideoItem video) {
    if (_busy) return;
    setState(() {
      _selectedVideos.removeWhere((item) => item.source == video.source);
    });
    _setStatus(
      _selectedVideos.isEmpty ? 'Selection cleared.' : 'Removed ${video.name} from queue.',
      fileName: video.name,
      kind: LogKind.info,
    );
  }

  void _toggleShareSelection(VideoItem video, bool selected) {
    final index = _selectedVideos.indexWhere((item) => item.source == video.source);
    if (index == -1) return;
    setState(() {
      _selectedVideos[index] = _selectedVideos[index].copyWith(shareSelected: selected);
    });
  }

  int _estimateQueueEtaMs() {
    if (!_busy) return 0;
    final speedValue = double.tryParse(_speed.replaceAll('x', '')) ?? 0;
    if (speedValue <= 0) return 0;

    var total = _currentEtaMs > 0 ? _currentEtaMs : 0;
    var afterActive = _activeSource == null;
    for (final video in _selectedVideos) {
      if (!afterActive) {
        if (video.source == _activeSource) {
          afterActive = true;
        }
        continue;
      }
      if (video.source == _activeSource) continue;
      if (video.state == VideoState.done ||
          video.state == VideoState.shared ||
          video.state == VideoState.skipped ||
          video.state == VideoState.failed) {
        continue;
      }
      if (video.state == VideoState.existing && !video.replaceExisting) {
        continue;
      }
      total += (video.durationMs / speedValue).round();
    }
    return total;
  }

  void _toggleReplaceExisting(VideoItem video, bool selected) {
    final index = _selectedVideos.indexWhere((item) => item.source == video.source);
    if (index == -1) return;
    setState(() {
      _selectedVideos[index] = _selectedVideos[index].copyWith(replaceExisting: selected);
    });
  }

  void _reorderSelectedVideos(int oldIndex, int newIndex) {
    if (_busy) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _selectedVideos.removeAt(oldIndex);
      _selectedVideos.insert(newIndex, item);
    });
    _setStatus('Queue order updated. Revolutionary stuff, I know.', kind: LogKind.info);
  }

  Future<void> _openCompare(VideoItem video) async {
    if (video.outputSource == null) {
      _setStatus('No compressed file yet. Compare with your imagination for now.', kind: LogKind.warning);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF050806),
      builder: (_) => _CompareSheet(video: video),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('SqueezeClip'),
        actions: [
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _PrivacyDialog(),
            ),
            icon: const Icon(Icons.privacy_tip_outlined),
            tooltip: 'Privacy',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecents,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _HeroStatus(
              status: _status,
              busy: _busy,
              progress: _progress,
              speed: _speed,
              elapsedMs: _elapsedMs,
              currentEtaMs: _currentEtaMs,
              queueEtaMs: _estimateQueueEtaMs(),
              stopAfterCurrent: _stopAfterCurrent,
              quality: _quality,
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Recent ${_recentSource.label.toLowerCase()} videos',
              action: IconButton(
                onPressed: _loadingRecents ? null : _loadRecents,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: 10),
            _RecentSourcePicker(
              value: _recentSource,
              onChanged: _loadingRecents ? null : _setRecentSource,
            ),
            const SizedBox(height: 10),
            if (_loadingRecents)
              const SizedBox(
                height: 210,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_recentVideos.isEmpty)
              const _EmptyRecentState()
            else
              SizedBox(
                height: 332,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recentVideos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final video = _recentVideos[index];
                    return _RecentVideoCard(
                      video: video,
                      onUse: () => _useRecent(video),
                      onOpen: () => _openVideo(video.source),
                      selected: _selectedVideos.any((item) => item.source == video.source),
                    );
                  },
                ),
              ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Log',
              action: Text(
                '${_logEntries.length} events',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 10),
            if (_logEntries.isEmpty)
              const _EmptyLogState()
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: _logEntries
                        .take(14)
                        .map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _LogRow(entry: entry),
                            ))
                        .toList(),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Quality',
              action: Text(
                'Pick what you actually want, not random magic.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 10),
            _QualitySelector(
              value: _quality,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() => _quality = value);
                    },
            ),
            if (_quality == QualityPreset.custom) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _customHeightController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom target height',
                      hintText: '1440',
                      suffixText: 'px',
                      prefixIcon: Icon(Icons.height_rounded),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Output',
              action: Text(
                'Suffix and overwrite, because hardcoded crap is for interns.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    TextField(
                      controller: _suffixController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Filename suffix',
                        hintText: '_tg',
                        prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _overwriteExistingByDefault,
                      onChanged: _busy ? null : (value) => setState(() => _overwriteExistingByDefault = value),
                      title: const Text('Overwrite existing by default'),
                      subtitle: const Text('If a compressed file with this suffix already exists, replace it automatically.'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _applyOutputSettings,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Apply output settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _SectionTitle(
              title: 'Selected videos',
              action: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    onPressed: _busy ? _cancelCurrent : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    tooltip: 'Cancel current',
                  ),
                  IconButton(
                    onPressed: _busy && !_stopAfterCurrent ? _requestStopAfterCurrent : null,
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: 'Stop after current',
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => _shareSelected(telegramOnly: true),
                    icon: const Icon(Icons.send_rounded),
                    tooltip: 'Share selected to Telegram',
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => _shareSelected(telegramOnly: false),
                    icon: const Icon(Icons.ios_share_rounded),
                    tooltip: 'Share selected',
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _clearSelection,
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _loadLatestCameraVideo,
                  icon: const Icon(Icons.fiber_smart_record_rounded),
                  label: const Text('Last Camera Video'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _compressLatestCameraVideo,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Compress Last Now'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _queueAllNewRecent,
                  icon: const Icon(Icons.playlist_add_check_circle_rounded),
                  label: const Text('Queue All New'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickVideos,
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('Pick Videos'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_selectedVideos.isEmpty)
              const _EmptySelectionState()
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _selectedVideos.length,
                onReorder: _reorderSelectedVideos,
                itemBuilder: (context, index) {
                  final video = _selectedVideos[index];
                  return Padding(
                    key: ValueKey(video.source),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SelectedVideoCard(
                      video: video,
                      active: _activeSource == video.source,
                      onOpenOriginal: () => _openVideo(video.source),
                      onOpenCompressed: video.outputSource == null
                          ? null
                          : () => _openVideo(video.outputSource!),
                      onUseExisting: video.outputSource == null
                          ? null
                          : () => _openVideo(video.outputSource!),
                      onCompare: video.outputSource == null ? null : () => _openCompare(video),
                      onRemove: () => _removeSelectedVideo(video),
                      onToggleShare: (selected) => _toggleShareSelection(video, selected),
                      onToggleReplaceExisting: (selected) => _toggleReplaceExisting(video, selected),
                      dragHandle: ReorderableDragStartListener(
                        index: index,
                        enabled: !_busy,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FilledButton.icon(
          onPressed: _selectedVideos.isEmpty || _busy ? null : _compress,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.compress_rounded),
          label: Text(_busy ? 'Compressing...' : 'Compress Selected'),
        ),
      ),
    );
  }
}

class _HeroStatus extends StatelessWidget {
  const _HeroStatus({
    required this.status,
    required this.busy,
    required this.progress,
    required this.speed,
    required this.elapsedMs,
    required this.currentEtaMs,
    required this.queueEtaMs,
    required this.stopAfterCurrent,
    required this.quality,
  });

  final String status;
  final bool busy;
  final double progress;
  final String speed;
  final int elapsedMs;
  final int currentEtaMs;
  final int queueEtaMs;
  final bool stopAfterCurrent;
  final QualityPreset quality;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B3A1D), Color(0xFF050806)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent camera videos first, picker only for actual videos. Finally not totally braindead.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(status),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: busy ? progress : 0,
              backgroundColor: Colors.white12,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _StatChip(label: 'Speed', value: speed),
              _StatChip(label: 'Quality', value: quality.label),
              _StatChip(label: 'Progress', value: '${(progress * 100).round()}%'),
              _StatChip(label: 'Elapsed', value: _formatClock(elapsedMs)),
              _StatChip(label: 'ETA file', value: currentEtaMs > 0 ? _formatClock(currentEtaMs) : '--:--'),
              _StatChip(label: 'ETA queue', value: queueEtaMs > 0 ? _formatClock(queueEtaMs) : '--:--'),
              _StatChip(label: 'Stop mode', value: stopAfterCurrent ? 'after current' : 'run queue'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        action,
      ],
    );
  }
}

class _RecentVideoCard extends StatelessWidget {
  const _RecentVideoCard({
    required this.video,
    required this.onUse,
    required this.onOpen,
    required this.selected,
  });

  final VideoItem video;
  final VoidCallback onUse;
  final VoidCallback onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 212,
      child: Card(
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 112,
                      width: double.infinity,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _Thumbnail(bytes: video.thumbnailBytes),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.black.withValues(alpha: 0.12),
                        ),
                        child: const Center(
                          child: Icon(Icons.play_circle_fill_rounded, size: 42),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _ThumbnailBadge(
                        label: _formatDuration(video.durationMs),
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _ThumbnailBadge(
                        label: _formatResolution(video.width, video.height),
                        icon: Icons.straighten_rounded,
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Selected',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    if (video.outputSource != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _ThumbnailBadge(
                          label: 'tg ready',
                          icon: Icons.check_circle_rounded,
                          accent: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  video.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  video.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  _formatBytes(video.sizeBytes),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: onUse,
                        child: const Text('Use'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onOpen,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QualitySelector extends StatelessWidget {
  const _QualitySelector({
    required this.value,
    required this.onChanged,
  });

  final QualityPreset value;
  final ValueChanged<QualityPreset>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: QualityPreset.values.map((preset) {
        final selected = preset == value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: onChanged == null ? null : () => onChanged!(preset),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.white12,
                ),
                color: selected
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.03),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.white54,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(preset.hint),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RecentSourcePicker extends StatelessWidget {
  const _RecentSourcePicker({
    required this.value,
    required this.onChanged,
  });

  final RecentSource value;
  final ValueChanged<RecentSource>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RecentSource>(
      segments: RecentSource.values
          .map(
            (source) => ButtonSegment<RecentSource>(
              value: source,
              label: Text(source.label),
              icon: Icon(
                switch (source) {
                  RecentSource.camera => Icons.photo_camera_rounded,
                  RecentSource.telegram => Icons.send_rounded,
                  RecentSource.downloads => Icons.download_rounded,
                },
              ),
            ),
          )
          .toList(),
      selected: {value},
      onSelectionChanged: onChanged == null ? null : (selection) => onChanged!(selection.first),
      showSelectedIcon: false,
    );
  }
}

class _SelectedVideoCard extends StatelessWidget {
  const _SelectedVideoCard({
    required this.video,
    required this.active,
    required this.onOpenOriginal,
    required this.onOpenCompressed,
    required this.onUseExisting,
    required this.onCompare,
    required this.onRemove,
    required this.onToggleShare,
    required this.onToggleReplaceExisting,
    required this.dragHandle,
  });

  final VideoItem video;
  final bool active;
  final VoidCallback onOpenOriginal;
  final VoidCallback? onOpenCompressed;
  final VoidCallback? onUseExisting;
  final VoidCallback? onCompare;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggleShare;
  final ValueChanged<bool> onToggleReplaceExisting;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (video.state) {
      VideoState.idle => 'Waiting',
      VideoState.compressing => 'Compressing now',
      VideoState.done => 'Compressed',
      VideoState.shared => 'Shared',
      VideoState.existing => 'Existing output found',
      VideoState.skipped => 'Skipped',
      VideoState.failed => 'Failed',
      VideoState.cancelled => 'Cancelled',
    };
    final detailsLine = _buildDetailsLine(video);
    final savingsLine = _buildSavingsLine(video);
    final errorLine = _buildErrorLine(video);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              height: 72,
              child: InkWell(
                onTap: onOpenOriginal,
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Thumbnail(bytes: video.thumbnailBytes),
                      Container(
                        color: Colors.black.withValues(alpha: 0.12),
                        child: const Center(
                          child: Icon(Icons.play_circle_fill_rounded, size: 30),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detailsLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    savingsLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(subtitle),
                      ),
                      if (video.outputName != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            video.outputName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (errorLine != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorLine,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                    ),
                  ],
                  if (video.outputSource != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: video.shareSelected,
                          onChanged: (value) => onToggleShare(value ?? false),
                        ),
                        const SizedBox(width: 2),
                        const Expanded(
                          child: Text('Mark for share / Telegram'),
                        ),
                      ],
                    ),
                  ],
                  if (video.state == VideoState.existing) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Checkbox(
                          value: video.replaceExisting,
                          onChanged: (value) => onToggleReplaceExisting(value ?? false),
                        ),
                        const SizedBox(width: 2),
                        const Expanded(
                          child: Text('Replace existing on next compress'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                dragHandle,
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Remove from queue',
                ),
                IconButton(
                  onPressed: onOpenOriginal,
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  tooltip: 'Open original',
                ),
                IconButton(
                  onPressed: onOpenCompressed,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  tooltip: 'Open compressed',
                ),
                IconButton(
                  onPressed: onCompare,
                  icon: const Icon(Icons.compare_rounded),
                  tooltip: 'Compare original vs compressed',
                ),
                if (video.state == VideoState.existing)
                  IconButton(
                    onPressed: onUseExisting,
                    icon: const Icon(Icons.inventory_2_outlined),
                    tooltip: 'Open existing compressed',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes == null || bytes!.isEmpty) {
      return Container(
        color: const Color(0xFF122217),
        child: const Center(
          child: Icon(Icons.movie_creation_outlined, size: 28),
        ),
      );
    }
    return Image.memory(
      bytes!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        color: const Color(0xFF122217),
        child: const Center(
          child: Icon(Icons.movie_creation_outlined, size: 28),
        ),
      ),
    );
  }
}

class _ThumbnailBadge extends StatelessWidget {
  const _ThumbnailBadge({
    required this.label,
    required this.icon,
    this.accent,
  });

  final String label;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.black.withValues(alpha: 0.72);
    final textColor = accent == null ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareSheet extends StatefulWidget {
  const _CompareSheet({required this.video});

  final VideoItem video;

  @override
  State<_CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends State<_CompareSheet> {
  VideoPlayerController? _originalController;
  VideoPlayerController? _compressedController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayers();
  }

  @override
  void dispose() {
    _originalController?.dispose();
    _compressedController?.dispose();
    super.dispose();
  }

  Future<void> _initPlayers() async {
    try {
      final original = await _createController(widget.video.source);
      final compressed = await _createController(widget.video.outputSource!);
      await Future.wait([
        original.initialize(),
        compressed.initialize(),
      ]);
      original.setLooping(true);
      compressed.setLooping(true);
      if (!mounted) {
        await original.dispose();
        await compressed.dispose();
        return;
      }
      setState(() {
        _originalController = original;
        _compressedController = compressed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<VideoPlayerController> _createController(String source) async {
    if (source.startsWith('content://')) {
      return VideoPlayerController.contentUri(Uri.parse(source));
    }
    return VideoPlayerController.file(File(source));
  }

  void _togglePlayback() {
    final original = _originalController;
    final compressed = _compressedController;
    if (original == null || compressed == null) return;
    final shouldPlay = !(original.value.isPlaying || compressed.value.isPlaying);
    if (shouldPlay) {
      original.play();
      compressed.play();
    } else {
      original.pause();
      compressed.pause();
    }
    setState(() {});
  }

  Future<void> _seekBoth(Duration position) async {
    final original = _originalController;
    final compressed = _compressedController;
    if (original == null || compressed == null) return;
    await Future.wait([
      original.seekTo(position),
      compressed.seekTo(position),
    ]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final original = _originalController;
    final compressed = _compressedController;
    final maxDuration = [
      widget.video.durationMs,
      original?.value.duration.inMilliseconds ?? 0,
      compressed?.value.duration.inMilliseconds ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final currentMs = [
      original?.value.position.inMilliseconds ?? 0,
      compressed?.value.position.inMilliseconds ?? 0,
    ].reduce((a, b) => a > b ? a : b);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Compare before / after',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                widget.video.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Player init failed: $_error',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _ComparePane(
                        title: 'Original',
                        subtitle:
                            '${_formatResolution(widget.video.width, widget.video.height)}  •  ${_formatFps(widget.video.fps)}  •  ${_formatBitrate(widget.video.bitrate)}',
                        controller: original!,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ComparePane(
                        title: 'Compressed',
                        subtitle:
                            '${_formatResolution(widget.video.width, widget.video.height)}  •  ${_formatFps(widget.video.outputFps)}  •  ${_formatBitrate(widget.video.outputBitrate)}',
                        controller: compressed!,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Slider(
                  value: currentMs.clamp(0, maxDuration).toDouble(),
                  min: 0,
                  max: maxDuration <= 0 ? 1 : maxDuration.toDouble(),
                  onChanged: (value) => _seekBoth(Duration(milliseconds: value.round())),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatClock(currentMs)} / ${_formatClock(maxDuration)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _togglePlayback,
                      icon: Icon(
                        (original.value.isPlaying || compressed.value.isPlaying)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        (original.value.isPlaying || compressed.value.isPlaying) ? 'Pause both' : 'Play both',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What changed',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(_buildSavingsLine(widget.video)),
                        const SizedBox(height: 6),
                        Text('Original: ${_buildDetailsLine(widget.video).split('\n').first}'),
                        if (widget.video.outputSizeBytes != null) ...[
                          const SizedBox(height: 6),
                          Text('Compressed: ${_formatFps(widget.video.outputFps)}  •  ${_formatBitrate(widget.video.outputBitrate)}'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparePane extends StatelessWidget {
  const _ComparePane({
    required this.title,
    required this.subtitle,
    required this.controller,
  });

  final String title;
  final String subtitle;
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio <= 0 ? 16 / 9 : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecentState extends StatelessWidget {
  const _EmptyRecentState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'No recent camera videos. Either the folder is empty or Android is being a clown.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _PrivacyDialog extends StatelessWidget {
  const _PrivacyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Privacy'),
      content: const SingleChildScrollView(
        child: Text(
          'SqueezeClip processes selected videos locally on your device.\n\n'
          'What it reads:\n'
          '- video files you choose or preview from Camera / Telegram / Downloads;\n'
          '- video thumbnails and metadata such as duration, resolution, bitrate and file size.\n\n'
          'What it writes:\n'
          '- compressed output files next to the originals, using your chosen suffix.\n\n'
          'What it shares:\n'
          '- only files you explicitly open or share to Telegram / Android share sheet.\n\n'
          'What it does not do by design:\n'
          '- no account system;\n'
          '- no analytics or ads;\n'
          '- no cloud upload for compression.\n\n'
          'Some Android dependencies still declare basic network-related permissions. Store paperwork must reflect the shipped manifest, not your vibes.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EmptySelectionState extends StatelessWidget {
  const _EmptySelectionState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          'Tap a recent video or use the video-only picker. Then compress and open the result right away.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _EmptyLogState extends StatelessWidget {
  const _EmptyLogState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          'No events yet. Start doing something and the app will finally have a memory longer than a goldfish.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.kind) {
      LogKind.success => Theme.of(context).colorScheme.primary,
      LogKind.warning => Colors.amber,
      LogKind.error => Colors.redAccent,
      LogKind.info => Colors.white70,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(Icons.circle, size: 10, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatTime(entry.at)}${entry.fileName == null ? '' : '  •  ${entry.fileName}'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum VideoState { idle, compressing, done, shared, existing, skipped, failed, cancelled }
enum LogKind { info, success, warning, error }

class VideoItem {
  const VideoItem({
    required this.source,
    required this.name,
    required this.subtitle,
    required this.sizeBytes,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.bitrate,
    required this.fps,
    this.thumbnailBytes,
    this.outputSource,
    this.outputName,
    this.outputSubtitle,
    this.outputSizeBytes,
    this.outputBitrate,
    this.outputFps,
    this.errorMessage,
    this.shareSelected = false,
    this.replaceExisting = false,
    this.state = VideoState.idle,
  });

  final String source;
  final String name;
  final String subtitle;
  final int sizeBytes;
  final int durationMs;
  final int width;
  final int height;
  final int bitrate;
  final double fps;
  final Uint8List? thumbnailBytes;
  final String? outputSource;
  final String? outputName;
  final String? outputSubtitle;
  final int? outputSizeBytes;
  final int? outputBitrate;
  final double? outputFps;
  final String? errorMessage;
  final bool shareSelected;
  final bool replaceExisting;
  final VideoState state;

  factory VideoItem.fromMap(Map<dynamic, dynamic> map) {
    return VideoItem(
      source: map['source']?.toString() ?? '',
      name: map['name']?.toString() ?? 'video',
      subtitle: map['subtitle']?.toString() ?? '',
      sizeBytes: int.tryParse(map['sizeBytes']?.toString() ?? '') ?? 0,
      durationMs: int.tryParse(map['durationMs']?.toString() ?? '') ?? 0,
      width: int.tryParse(map['width']?.toString() ?? '') ?? 0,
      height: int.tryParse(map['height']?.toString() ?? '') ?? 0,
      bitrate: int.tryParse(map['bitrate']?.toString() ?? '') ?? 0,
      fps: double.tryParse(map['fps']?.toString() ?? '') ?? 0,
    );
  }

  VideoItem copyWith({
    String? source,
    String? name,
    String? subtitle,
    int? sizeBytes,
    int? durationMs,
    int? width,
    int? height,
    int? bitrate,
    double? fps,
    Uint8List? thumbnailBytes,
    Object? outputSource = _unset,
    Object? outputName = _unset,
    Object? outputSubtitle = _unset,
    Object? outputSizeBytes = _unset,
    Object? outputBitrate = _unset,
    Object? outputFps = _unset,
    Object? errorMessage = _unset,
    bool? shareSelected,
    bool? replaceExisting,
    VideoState? state,
  }) {
    return VideoItem(
      source: source ?? this.source,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      bitrate: bitrate ?? this.bitrate,
      fps: fps ?? this.fps,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      outputSource: identical(outputSource, _unset) ? this.outputSource : outputSource as String?,
      outputName: identical(outputName, _unset) ? this.outputName : outputName as String?,
      outputSubtitle: identical(outputSubtitle, _unset) ? this.outputSubtitle : outputSubtitle as String?,
      outputSizeBytes: identical(outputSizeBytes, _unset) ? this.outputSizeBytes : outputSizeBytes as int?,
      outputBitrate: identical(outputBitrate, _unset) ? this.outputBitrate : outputBitrate as int?,
      outputFps: identical(outputFps, _unset) ? this.outputFps : outputFps as double?,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      shareSelected: shareSelected ?? this.shareSelected,
      replaceExisting: replaceExisting ?? this.replaceExisting,
      state: state ?? this.state,
    );
  }
}

const _unset = Object();

class LogEntry {
  const LogEntry({
    required this.message,
    required this.at,
    required this.kind,
    this.fileName,
  });

  final String message;
  final DateTime at;
  final LogKind kind;
  final String? fileName;
}

String _formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return 'unknown';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatDuration(int? durationMs) {
  final totalSeconds = ((durationMs ?? 0) / 1000).round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatResolution(int width, int height) {
  if (width <= 0 || height <= 0) return 'unknown';
  return '${width}x$height';
}

String _formatBitrate(int? bitrate) {
  if (bitrate == null || bitrate <= 0) return 'unknown bitrate';
  final kbps = bitrate / 1000;
  if (kbps >= 1000) {
    return '${(kbps / 1000).toStringAsFixed(2)} Mbps';
  }
  return '${kbps.toStringAsFixed(0)} kbps';
}

String _formatFps(double? fps) {
  if (fps == null || fps <= 0) return 'unknown fps';
  final rounded = fps.roundToDouble();
  return rounded == fps ? '${rounded.toInt()} fps' : '${fps.toStringAsFixed(1)} fps';
}

String _formatSavedPercent(int originalBytes, int? outputBytes) {
  if (outputBytes == null || originalBytes <= 0 || outputBytes <= 0) return '0%';
  final delta = ((originalBytes - outputBytes) / originalBytes) * 100;
  return '${delta.round()}%';
}

String _buildDetailsLine(VideoItem video) {
  final original = [
    _formatDuration(video.durationMs),
    _formatResolution(video.width, video.height),
    _formatFps(video.fps),
    _formatBitrate(video.bitrate),
  ].join('  •  ');
  if (video.outputSizeBytes == null) {
    return original;
  }
  return '$original\nOut: ${_formatFps(video.outputFps)}  •  ${_formatBitrate(video.outputBitrate)}';
}

String _buildSavingsLine(VideoItem video) {
  if (video.outputSizeBytes == null) {
    return 'Size: ${_formatBytes(video.sizeBytes)}';
  }
  return 'Size: ${_formatBytes(video.sizeBytes)} -> ${_formatBytes(video.outputSizeBytes)}  •  Saved ${_formatSavedPercent(video.sizeBytes, video.outputSizeBytes)}';
}

String? _buildErrorLine(VideoItem video) {
  if (video.errorMessage == null || video.errorMessage!.trim().isEmpty) return null;
  return 'Reason: ${video.errorMessage}';
}

String _friendlyErrorMessage(PlatformException e) {
  return switch (e.code) {
    'bad_source' => 'This video source is unreadable. Android storage did its usual clown act.',
    'thumb_failed' => 'Thumbnail generation failed. The video is still there, preview just choked.',
    'busy' => 'Compression is already running. One meat grinder at a time.',
    'cancelled' => 'Compression cancelled.',
    'transform_failed' => 'Compression failed in the encoder pipeline. The file or codec fought back.',
    'persist_failed' => 'Compression finished, then saving the result failed. Android storage botched the landing.',
    'not_found' => 'No camera video found. Either the folder is empty or permissions are lying again.',
    _ => e.message ?? 'Something failed, and Android was too lazy to explain properly.',
  };
}

String _formatClock(int? ms) {
  final totalSeconds = (((ms ?? 0).clamp(0, 1 << 31)) / 1000).round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime at) {
  final h = at.hour.toString().padLeft(2, '0');
  final m = at.minute.toString().padLeft(2, '0');
  final s = at.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
