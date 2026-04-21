import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/reel_provider.dart';
import '../../skills/models/skill_model.dart';
import '../../skills/providers/skills_provider.dart';
import '../../skills/widgets/skill_picker_bottom_sheet.dart';
import '../../../core/services/ffmpeg_bridge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/theme/app_colors.dart';

class UploadReelScreen extends ConsumerStatefulWidget {
  final String? initialMediaType;
  const UploadReelScreen({super.key, this.initialMediaType});

  @override
  ConsumerState<UploadReelScreen> createState() => _UploadReelScreenState();
}

class _UploadReelScreenState extends ConsumerState<UploadReelScreen> {
  static const _draftKey = 'reel_upload_draft_v1';
  static const int _maxUploadBytes = 45 * 1024 * 1024;

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  String? _filePath;
  String _mediaType = 'image';
  bool _loading = false;
  double _uploadProgress = 0;
  int _lastUploadProgressUpdateMs = 0;
  final List<String> _skillTagIds = [];
  final Map<String, String> _skillTagNamesById = {};
  VideoPlayerController? _videoPreview;
  int _step = 0;
  bool _processing = false;
  double _compressProgress = 0;
  Subscription? _compressSub;
  bool _previewMuted = true;
  bool _isCompressing = false;
  RangeValues? _trimRange;
  final List<_PendingTextOverlay> _pendingTextOverlays = [];
  Timer? _draftSaveDebounce;
  String? _draftLastError;
  String? _selectedFileSizeLabel;
  String _visibility = 'Public';
  String _audience = 'Everyone';
  bool _commentsAllowed = true;
  bool _autoPicking = false;
  String? _coverPath;
  double? _coverSecond;
  final List<String> _tempCoverFiles = [];
  final List<String> _tempTrimFiles = [];

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialMediaType ?? '').toLowerCase();
    if (initial == 'video' || initial == 'image') {
      _mediaType = initial;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restored = await _maybeRestoreDraft();
      if (!mounted) return;
      final initial = (widget.initialMediaType ?? '').toLowerCase();
      final shouldAutoPick =
          !restored && (initial == 'video' || initial == 'image');
      if (shouldAutoPick && _filePath == null) {
        await _autoPickInitialMedia();
      }
    });

    _title.addListener(_scheduleDraftSave);
    _desc.addListener(_scheduleDraftSave);
    _price.addListener(_scheduleDraftSave);
  }

  void _syncSelectedSkillNames(List<SkillModel> allSkills) {
    if (!mounted || _skillTagIds.isEmpty) return;

    final nameById = <String, String>{
      for (final s in allSkills) s.id: s.name,
    };

    var changed = false;
    for (final id in _skillTagIds) {
      final name = nameById[id];
      if (name == null || name.isEmpty) continue;
      final existing = _skillTagNamesById[id];
      if (existing == null || existing.isEmpty || existing == id) {
        _skillTagNamesById[id] = name;
        changed = true;
      }
    }

    if (changed && mounted) setState(() {});
  }

  Future<bool> _maybeRestoreDraft() async {
    final draft = await _readDraft();
    if (!mounted || draft == null) return false;

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restore draft?'),
        content: const Text('You have an unfinished upload draft.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(false);
              await _clearDraft();
            },
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop(true);
              await _restoreDraft(draft);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    return res == true;
  }

  Future<void> _autoPickInitialMedia() async {
    if (_autoPicking) return;
    if (!mounted) return;
    setState(() => _autoPicking = true);

    await _pick();

    if (!mounted) return;
    setState(() => _autoPicking = false);

    if (_filePath == null) {
      if (context.canPop()) context.pop();
      return;
    }

    final hasVideoEditStep = _mediaType == 'video';
    final detailsStep = hasVideoEditStep ? 2 : 1;
    setState(() => _step = hasVideoEditStep ? 1 : detailsStep);
  }

  Future<Map<String, dynamic>?> _readDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) return obj;
      if (obj is Map) return Map<String, dynamic>.from(obj);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveDraft({String? errorMessage}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastError = (errorMessage ?? _draftLastError)?.toString().trim();
    final draft = <String, dynamic>{
      'mediaType': _mediaType,
      'filePath': _filePath,
      'coverSecond': _coverSecond,
      'title': _title.text,
      'description': _desc.text,
      'price': _price.text,
      'skillTagIds': _skillTagIds,
      'visibility': _visibility,
      'audience': _audience,
      'commentsAllowed': _commentsAllowed,
      if (lastError != null && lastError.isNotEmpty) 'lastError': lastError,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_draftKey, jsonEncode(draft));
    if (!mounted) return;
    setState(() {
      if (errorMessage != null) _draftLastError = errorMessage;
    });
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    if (!mounted) return;
    setState(() {
      _draftLastError = null;
    });
  }

  Future<void> _restoreDraft(Map<String, dynamic> draft) async {
    final mediaType = (draft['mediaType'] ?? '').toString().toLowerCase();
    final filePath = (draft['filePath'] ?? '').toString();
    final coverSecondRaw = draft['coverSecond'];
    final coverSecond = (coverSecondRaw is num)
        ? coverSecondRaw.toDouble()
        : double.tryParse((coverSecondRaw ?? '').toString());
    final tagIds = draft['skillTagIds'];
    final lastError = (draft['lastError'] ?? '').toString().trim();
    final visibility = (draft['visibility'] ?? 'Public').toString().trim();
    final audience = (draft['audience'] ?? 'Everyone').toString().trim();
    final commentsAllowedRaw = draft['commentsAllowed'];
    final commentsAllowed = (commentsAllowedRaw == null)
        ? true
        : (commentsAllowedRaw is bool)
            ? commentsAllowedRaw
            : (commentsAllowedRaw.toString().toLowerCase() == 'true');

    _clearCoverSelection();
    setState(() {
      _mediaType = (mediaType == 'video' || mediaType == 'image')
          ? mediaType
          : _mediaType;
      _filePath = (filePath.isNotEmpty && File(filePath).existsSync())
          ? filePath
          : null;
      _step = 0;
      _processing = false;
      _compressProgress = 0;
      _draftLastError = lastError.isEmpty ? null : lastError;
      _visibility = visibility.isEmpty ? 'Public' : visibility;
      _audience = audience.isEmpty ? 'Everyone' : audience;
      _commentsAllowed = commentsAllowed;
      _coverSecond = coverSecond;
    });

    _title.text = (draft['title'] ?? '').toString();
    _desc.text = (draft['description'] ?? '').toString();
    _price.text = (draft['price'] ?? '').toString();

    _skillTagIds
      ..clear()
      ..addAll(
        (tagIds is List ? tagIds : const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty),
      );
    _skillTagNamesById.clear();

    if (_filePath != null) {
      _selectedFileSizeLabel = await _fileSizeLabel(_filePath!);
      if (mounted) setState(() {});
    }
    if (_mediaType == 'video' && _filePath != null) {
      await _initVideoPreview(_filePath!);
      final s = _coverSecond;
      if (s != null) {
        try {
          _coverPath = await _extractCoverFrame(s);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _initVideoPreview(String path) async {
    final prev = _videoPreview;
    _videoPreview = null;
    await prev?.dispose();

    try {
      final ctrl = VideoPlayerController.file(File(path));
      _videoPreview = ctrl;
      await ctrl.initialize().timeout(const Duration(seconds: 6));
      await ctrl.setLooping(true);
      await ctrl.setVolume(_previewMuted ? 0 : 1);
      await ctrl.play();

      final dur = ctrl.value.duration;
      if (dur > Duration.zero) {
        final maxSec = dur.inMilliseconds / 1000.0;
        _trimRange = RangeValues(0, maxSec);
        if (mounted) setState(() {});
      }

      final sizeLabel = await _fileSizeLabel(path);
      if (!mounted) return;
      if (_filePath == path) {
        setState(() => _selectedFileSizeLabel = sizeLabel);
      } else {
        _selectedFileSizeLabel = sizeLabel;
      }
    } catch (_) {
      final c = _videoPreview;
      _videoPreview = null;
      await c?.dispose();
    }
  }

  Future<void> _pausePreview() async {
    final c = _videoPreview;
    if (c == null) return;
    try {
      await c.pause();
      await c.setVolume(0);
    } catch (_) {}
  }

  Future<void> _togglePreviewPlayPause() async {
    final c = _videoPreview;
    if (c == null || !c.value.isInitialized) return;
    try {
      if (c.value.isPlaying) {
        await c.pause();
        return;
      }

      final dur = c.value.duration;
      final pos = c.value.position;
      if (dur > Duration.zero &&
          pos >= dur - const Duration(milliseconds: 120)) {
        await c.seekTo(Duration.zero);
      }
      await c.play();
    } catch (_) {}
  }

  Future<void> _togglePreviewMute() async {
    setState(() => _previewMuted = !_previewMuted);
    final c = _videoPreview;
    if (c == null) return;
    try {
      await c.setVolume(_previewMuted ? 0 : 1);
    } catch (_) {}
  }

  Future<void> _setMediaType(String next) async {
    if (next == _mediaType) return;
    await _pausePreview();
    final prev = _videoPreview;
    _videoPreview = null;
    await prev?.dispose();
    if (!mounted) return;
    _clearCoverSelection();
    setState(() {
      _mediaType = next;
      _filePath = null;
      _selectedFileSizeLabel = null;
      _processing = false;
      _isCompressing = false;
      _compressProgress = 0;
      _previewMuted = true;
      _trimRange = null;
      _pendingTextOverlays.clear();
    });
    _scheduleDraftSave();
  }

  Future<void> _pick() async {
    final picker = ImagePicker();
    XFile? file;
    if (_mediaType == 'video') {
      file = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      file = await picker.pickImage(source: ImageSource.gallery);
    }
    if (file == null) return;

    setState(() {
      _processing = true;
      _isCompressing = false;
      _compressProgress = 0;
    });

    final pickedPath = file.path;
    final sizeLabel = await _fileSizeLabel(pickedPath);
    if (!mounted) return;
    _clearCoverSelection();
    _filePath = pickedPath;
    _selectedFileSizeLabel = sizeLabel;
    // Keep original file path by default (no auto-compress).

    if (_mediaType == 'video' && _filePath != null) {
      await _initVideoPreview(_filePath!);
    }

    if (!mounted) return;
    setState(() => _processing = false);
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      final hasAnything = (_filePath != null) ||
          _title.text.trim().isNotEmpty ||
          _desc.text.trim().isNotEmpty ||
          _price.text.trim().isNotEmpty ||
          _skillTagIds.isNotEmpty;
      if (!hasAnything) return;
      try {
        await _saveDraft();
      } catch (_) {
        // ignore (draft saving should never block UX)
      }
    });
  }

  String _formatClock(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $ampm';
  }

  String _formatDurationShort(Duration d) {
    final total = d.inSeconds.clamp(0, 24 * 60 * 60);
    final mm = (total ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _formatSecondsShort(double seconds) {
    final s = seconds.isFinite ? seconds : 0.0;
    final whole = s.clamp(0.0, 24 * 60 * 60).floor();
    return _formatDurationShort(Duration(seconds: whole));
  }

  Future<void> _pickVisibility() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Public'),
              onTap: () => Navigator.of(ctx).pop('Public'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Private'),
              onTap: () => Navigator.of(ctx).pop('Private'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _visibility = picked);
    _scheduleDraftSave();
  }

  Future<void> _pickAudience() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Everyone'),
              onTap: () => Navigator.of(ctx).pop('Everyone'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Followers'),
              onTap: () => Navigator.of(ctx).pop('Followers'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _audience = picked);
    _scheduleDraftSave();
  }

  Future<void> _editPrice() async {
    final initial = _price.text.trim();
    final next = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PriceBottomSheet(initialValue: initial),
    );
    if (!mounted || next == null) return;
    setState(() => _price.text = next);
    _scheduleDraftSave();
  }

  Future<void> _trimVideo() async {
    if (_mediaType != 'video' || _filePath == null) return;
    final ctrl = _videoPreview;
    final dur = ctrl?.value.duration ?? Duration.zero;
    if (dur <= Duration.zero) {
      await _showError('Trim not ready', 'Please wait for the video to load.');
      return;
    }

    final maxSec = dur.inMilliseconds / 1000.0;
    final initial = _trimRange ?? RangeValues(0, maxSec);

    await _pausePreview();
    if (!mounted) return;

    _clearTrimTempFiles();
    final picked =
        await Navigator.of(context, rootNavigator: true).push<RangeValues>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TrimClipScreen(
          videoDuration: dur,
          initialRange: initial,
          extractThumb: _extractTrimThumbFrame,
        ),
      ),
    );

    if (!mounted || picked == null) return;
    final startSec = picked.start.clamp(0.0, maxSec).toDouble();
    final endSec = picked.end.clamp(0.0, maxSec).toDouble();
    if (endSec - startSec < 0.5) {
      await _showError('Invalid trim', 'Please select at least 0.5 seconds.');
      return;
    }

    setState(() {
      _trimRange = RangeValues(startSec, endSec);
      _processing = true;
      _isCompressing = true;
      _compressProgress = 0;
    });

    _compressSub?.unsubscribe();
    _compressSub = VideoCompress.compressProgress$.subscribe((p) {
      if (!mounted) return;
      setState(() => _compressProgress = (p / 100).clamp(0, 1));
    });

    try {
      await _pausePreview();
      final info = await VideoCompress.compressVideo(
        _filePath!,
        quality: VideoQuality.HighestQuality,
        deleteOrigin: false,
        includeAudio: true,
        startTime: startSec.floor(),
        duration: (endSec - startSec).ceil(),
      );
      final out = info?.file?.path;
      if (out != null && out.isNotEmpty) {
        _clearCoverSelection();
        _filePath = out;
        await _initVideoPreview(_filePath!);
      }
    } catch (e) {
      await _showError('Trim failed', e.toString());
    } finally {
      _compressSub?.unsubscribe();
      _compressSub = null;
      _isCompressing = false;
      if (mounted) setState(() => _processing = false);
    }
  }

  String _q(String path) => '"${path.replaceAll('"', '\\"')}"';

  void _clearCoverSelection() {
    _coverSecond = null;
    _coverPath = null;
    for (final p in _tempCoverFiles) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
    _tempCoverFiles.clear();
  }

  void _clearTrimTempFiles() {
    for (final p in _tempTrimFiles) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
    _tempTrimFiles.clear();
  }

  void _cleanupCoverTempFiles({String? keepPath}) {
    if (_tempCoverFiles.isEmpty) return;
    final keep = (keepPath ?? '').trim();
    final kept = <String>[];
    for (final p in _tempCoverFiles) {
      if (keep.isNotEmpty && p == keep) {
        kept.add(p);
        continue;
      }
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
    _tempCoverFiles
      ..clear()
      ..addAll(kept);
  }

  Future<String> _extractCoverFrame(double seconds) async {
    final videoPath = _filePath;
    if (videoPath == null || videoPath.trim().isEmpty) {
      throw StateError('Missing video');
    }
    final out =
        '${Directory.systemTemp.path}${Platform.pathSeparator}skilreel_cover_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final ss = seconds.clamp(0.0, 24 * 60 * 60).toStringAsFixed(3);
    final cmd = '-y -ss $ss -i ${_q(videoPath)} -frames:v 1 -q:v 2 ${_q(out)}';
    await FfmpegBridge.execute(cmd, onFailTitle: 'Cover extraction failed');
    _tempCoverFiles.add(out);
    return out;
  }

  Future<Duration?> _probeVideoDuration(String path) async {
    try {
      final ctrl = VideoPlayerController.file(File(path));
      await ctrl.initialize().timeout(const Duration(seconds: 6));
      final dur = ctrl.value.duration;
      await ctrl.dispose();
      return dur;
    } catch (_) {
      return null;
    }
  }

  Future<String> _extractTrimThumbFrame(double seconds) async {
    final videoPath = _filePath;
    if (videoPath == null || videoPath.trim().isEmpty) {
      throw StateError('Missing video');
    }
    final out =
        '${Directory.systemTemp.path}${Platform.pathSeparator}skilreel_trim_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final ss = seconds.clamp(0.0, 24 * 60 * 60).toStringAsFixed(3);
    final cmd =
        '-y -ss $ss -i ${_q(videoPath)} -frames:v 1 -vf scale=160:-1 -q:v 6 ${_q(out)}';
    await FfmpegBridge.execute(cmd, onFailTitle: 'Trim preview failed');
    _tempTrimFiles.add(out);
    return out;
  }

  Future<void> _openCoverPicker() async {
    final path = _filePath;
    if (path == null || path.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a video first.')),
      );
      return;
    }
    if (_mediaType != 'video') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cover will use your image.')),
      );
      return;
    }

    final existing = _videoPreview;
    final existingDur = (existing != null && existing.value.isInitialized)
        ? existing.value.duration
        : Duration.zero;
    final dur = existingDur > Duration.zero
        ? existingDur
        : await _probeVideoDuration(path);
    if (!mounted) return;
    if (dur == null || dur <= Duration.zero) {
      await _showError('Cover not ready', 'Unable to read video duration.');
      return;
    }

    await _pausePreview();
    if (!mounted) return;

    _cleanupCoverTempFiles(keepPath: _coverPath);

    final picked =
        await Navigator.of(context, rootNavigator: true).push<_CoverPickResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _SelectCoverScreen(
          videoDuration: dur,
          initialSeconds: _coverSecond,
          initialPath: _coverPath,
          extractFrame: _extractCoverFrame,
        ),
      ),
    );

    if (!mounted || picked == null) return;
    setState(() {
      _coverPath = picked.path;
      _coverSecond = picked.seconds;
    });
    _scheduleDraftSave();
  }

  Future<void> _runFfmpeg({
    required String command,
    required Duration totalDuration,
    required String onFailTitle,
  }) async {
    if (_processing) return;

    setState(() {
      _processing = true;
      _isCompressing = true;
      _compressProgress = 0;
    });

    try {
      await _pausePreview();
      // totalDuration is kept for future progress improvements.
      await FfmpegBridge.execute(command, onFailTitle: onFailTitle);
    } catch (e) {
      await _showError(onFailTitle, e.toString());
    } finally {
      _isCompressing = false;
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _cropVideo() async {
    if (_mediaType != 'video' || _filePath == null) return;
    final ctrl = _videoPreview;
    if (ctrl == null || !ctrl.value.isInitialized) {
      await _showError('Crop not ready', 'Please wait for the video to load.');
      return;
    }
    final dur = ctrl.value.duration;
    if (dur <= Duration.zero) {
      await _showError('Crop not ready', 'Please wait for the video to load.');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Crop',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.crop_free),
                title: const Text('Custom'),
                subtitle: const Text('Drag / pinch to select area'),
                onTap: () => Navigator.of(ctx).pop('custom'),
              ),
              ListTile(
                leading: const Icon(Icons.smartphone),
                title: const Text('9:16 (Reels)'),
                onTap: () => Navigator.of(ctx).pop('9:16'),
              ),
              ListTile(
                leading: const Icon(Icons.crop_square),
                title: const Text('1:1 (Square)'),
                onTap: () => Navigator.of(ctx).pop('1:1'),
              ),
              ListTile(
                leading: const Icon(Icons.crop_16_9),
                title: const Text('16:9 (Landscape)'),
                onTap: () => Navigator.of(ctx).pop('16:9'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;

    if (picked == 'custom') {
      await _pausePreview();
      if (!mounted) return;
      final rect = await Navigator.of(context).push<_VideoCropRect>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _CustomVideoCropScreen(controller: ctrl),
        ),
      );
      if (!mounted || rect == null) return;
      await _applyCropRect(rect, totalDuration: dur);
      return;
    }

    final srcW = ctrl.value.size.width.toInt();
    final srcH = ctrl.value.size.height.toInt();
    if (srcW <= 0 || srcH <= 0) {
      await _showError('Crop failed', 'Invalid video size.');
      return;
    }

    final parts = picked.split(':');
    final rw = int.tryParse(parts.first) ?? 9;
    final rh = int.tryParse(parts.last) ?? 16;
    final desired = rw / rh;
    final srcRatio = srcW / srcH;

    int cropW;
    int cropH;
    if (srcRatio > desired) {
      cropH = srcH;
      cropW = (srcH * desired).round();
    } else {
      cropW = srcW;
      cropH = (srcW / desired).round();
    }

    // Keep encoder-friendly dimensions.
    cropW = (cropW ~/ 2) * 2;
    cropH = (cropH ~/ 2) * 2;
    if (cropW <= 0 || cropH <= 0) {
      await _showError('Crop failed', 'Invalid crop size.');
      return;
    }

    final x = ((srcW - cropW) / 2).round().clamp(0, srcW);
    final y = ((srcH - cropH) / 2).round().clamp(0, srcH);

    final out =
        '${Directory.systemTemp.path}${Platform.pathSeparator}reel_crop_${DateTime.now().millisecondsSinceEpoch}.mp4';
    // Fast encode settings (optimized for speed while editing).
    final cmd =
        '-y -i ${_q(_filePath!)} -vf crop=$cropW:$cropH:$x:$y -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart ${_q(out)}';

    await _runFfmpeg(
      command: cmd,
      totalDuration: dur,
      onFailTitle: 'Crop failed',
    );

    if (!mounted) return;
    if (File(out).existsSync()) {
      _clearCoverSelection();
      _filePath = out;
      await _initVideoPreview(_filePath!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _applyCropRect(
    _VideoCropRect rect, {
    required Duration totalDuration,
  }) async {
    if (_mediaType != 'video' || _filePath == null) return;
    final ctrl = _videoPreview;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final srcW = ctrl.value.size.width.toInt();
    final srcH = ctrl.value.size.height.toInt();
    if (srcW <= 0 || srcH <= 0) {
      await _showError('Crop failed', 'Invalid video size.');
      return;
    }

    var cropW = rect.width.round();
    var cropH = rect.height.round();
    var x = rect.left.round();
    var y = rect.top.round();

    cropW = (cropW ~/ 2) * 2;
    cropH = (cropH ~/ 2) * 2;
    x = (x ~/ 2) * 2;
    y = (y ~/ 2) * 2;

    cropW = cropW.clamp(2, srcW);
    cropH = cropH.clamp(2, srcH);
    x = x.clamp(0, math.max(0, srcW - cropW));
    y = y.clamp(0, math.max(0, srcH - cropH));

    final out =
        '${Directory.systemTemp.path}${Platform.pathSeparator}reel_crop_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final cmd =
        '-y -i ${_q(_filePath!)} -vf crop=$cropW:$cropH:$x:$y -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart ${_q(out)}';

    await _runFfmpeg(
      command: cmd,
      totalDuration: totalDuration,
      onFailTitle: 'Crop failed',
    );

    if (!mounted) return;
    if (File(out).existsSync()) {
      _clearCoverSelection();
      _filePath = out;
      await _initVideoPreview(_filePath!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _addTextOverlay() async {
    if (_mediaType != 'video' || _filePath == null) return;
    final ctrl = _videoPreview;
    if (ctrl == null || !ctrl.value.isInitialized) {
      await _showError('Text not ready', 'Please wait for the video to load.');
      return;
    }

    await _pausePreview();
    if (!mounted) return;

    final res = await Navigator.of(context).push<_PendingTextOverlay>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FreeTextOverlayScreen(controller: ctrl),
      ),
    );
    if (!mounted || res == null) return;

    setState(() => _pendingTextOverlays.add(res));
  }

  Future<void> _editTextOverlayAt(int index) async {
    if (_mediaType != 'video') return;
    if (index < 0 || index >= _pendingTextOverlays.length) return;
    final ctrl = _videoPreview;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    await _pausePreview();
    if (!mounted) return;

    final initial = _pendingTextOverlays[index];
    final res = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FreeTextOverlayScreen(
          controller: ctrl,
          initial: initial,
          allowDelete: true,
        ),
      ),
    );
    if (!mounted || res == null) return;

    if (res is _DeleteTextOverlay) {
      setState(() => _pendingTextOverlays.removeAt(index));
      return;
    }
    if (res is _PendingTextOverlay) {
      setState(() => _pendingTextOverlays[index] = res);
    }
  }

  Future<void> _bakePendingTextOverlays() async {
    if (_processing) return;
    if (_mediaType != 'video' || _filePath == null) return;
    final ctrl = _videoPreview;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final dur = ctrl.value.duration;
    if (dur <= Duration.zero) return;
    if (_pendingTextOverlays.isEmpty) return;

    // Uses Android system font path. Works on most devices.
    const fontFile = '/system/fonts/Roboto-Regular.ttf';

    final tmpDir = Directory.systemTemp;
    final overlays = List<_PendingTextOverlay>.from(_pendingTextOverlays);
    final filters = <String>[];

    for (final o in overlays) {
      final txtFile = File(
        '${tmpDir.path}${Platform.pathSeparator}reel_text_${DateTime.now().millisecondsSinceEpoch}_${filters.length}.txt',
      );
      await txtFile.writeAsString(o.text, flush: true);

      final nx = o.nx.clamp(0.0, 1.0).toStringAsFixed(6);
      final ny = o.ny.clamp(0.0, 1.0).toStringAsFixed(6);

      // Note: commas in ffmpeg expressions must be escaped inside filtergraphs.
      final xExpr = 'max(0\\,min(w-text_w\\,(w*$nx-text_w/2)))';
      final yExpr = 'max(0\\,min(h-text_h\\,(h*$ny-text_h/2)))';

      String ffColor(Color c, {double? alpha}) {
        final argb = c.toARGB32();
        final a = (alpha ?? (((argb >> 24) & 0xFF) / 255.0)).clamp(0.0, 1.0);
        final rgb = argb & 0x00FFFFFF;
        final hex = rgb.toRadixString(16).padLeft(6, '0');
        return '0x$hex@${a.toStringAsFixed(3)}';
      }

      final parts = <String>[
        "drawtext=fontfile=$fontFile:textfile='${txtFile.path}':reload=1",
        'fontcolor=${ffColor(o.textColor)}',
        'fontsize=${o.fontSize.toStringAsFixed(0)}',
        'x=$xExpr',
        'y=$yExpr',
      ];

      if (o.strokeWidth > 0) {
        parts.add('borderw=${o.strokeWidth.toStringAsFixed(1)}');
        parts.add('bordercolor=${ffColor(o.strokeColor)}');
      }

      if (o.showBackground && o.backgroundOpacity > 0) {
        parts.add('box=1');
        parts.add(
            'boxcolor=${ffColor(o.backgroundColor, alpha: o.backgroundOpacity)}');
        parts.add('boxborderw=12');
      }

      filters.add(parts.join(':'));
    }

    final vf = filters.join(',');
    final out =
        '${tmpDir.path}${Platform.pathSeparator}reel_text_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final cmd =
        '-y -i ${_q(_filePath!)} -vf "$vf" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p '
        '-c:a aac -b:a 128k -movflags +faststart ${_q(out)}';

    await _runFfmpeg(
      command: cmd,
      totalDuration: dur,
      onFailTitle: 'Apply text failed',
    );

    if (!mounted) return;
    if (File(out).existsSync()) {
      _clearCoverSelection();
      _filePath = out;
      _pendingTextOverlays.clear();
      await _initVideoPreview(_filePath!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _replaceAudio() async {
    if (_mediaType != 'video' || _filePath == null) return;
    final ctrl = _videoPreview;
    final dur = ctrl?.value.duration ?? Duration.zero;
    if (dur <= Duration.zero) {
      await _showError('Audio not ready', 'Please wait for the video to load.');
      return;
    }

    final res = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    final audioPath = res?.files.single.path;
    if (!mounted || audioPath == null || audioPath.trim().isEmpty) return;
    if (!File(audioPath).existsSync()) {
      await _showError('Audio failed', 'Selected audio file not found.');
      return;
    }

    final out =
        '${Directory.systemTemp.path}${Platform.pathSeparator}reel_audio_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Replace audio track; keep video stream as-is if possible.
    final cmd =
        '-y -i ${_q(_filePath!)} -i ${_q(audioPath)} -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart ${_q(out)}';

    await _runFfmpeg(
      command: cmd,
      totalDuration: dur,
      onFailTitle: 'Audio failed',
    );

    if (!mounted) return;
    if (File(out).existsSync()) {
      _clearCoverSelection();
      _filePath = out;
      await _initVideoPreview(_filePath!);
      if (mounted) setState(() {});
    }
  }

  Future<void> _compressHighQuality() async {
    if (_mediaType != 'video' || _filePath == null) return;

    setState(() {
      _processing = true;
      _isCompressing = true;
      _compressProgress = 0;
    });

    _compressSub?.unsubscribe();
    _compressSub = VideoCompress.compressProgress$.subscribe((p) {
      if (!mounted) return;
      setState(() => _compressProgress = (p / 100).clamp(0, 1));
    });

    try {
      await _pausePreview();
      final info = await VideoCompress.compressVideo(
        _filePath!,
        quality: VideoQuality.HighestQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final out = info?.file?.path;
      if (out != null && out.isNotEmpty) {
        _clearCoverSelection();
        _filePath = out;
      }
      await _initVideoPreview(_filePath!);
    } catch (e) {
      await _showError('Compress failed', e.toString());
    } finally {
      _compressSub?.unsubscribe();
      _compressSub = null;
      _isCompressing = false;
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openSkillPicker() async {
    final initialSelected = <String, String>{
      for (final id in _skillTagIds) id: (_skillTagNamesById[id] ?? id),
    };
    final selected = await SkillPickerBottomSheet.open(
      context,
      initialSelectedById: initialSelected,
    );
    if (!mounted || selected == null) return;

    setState(() {
      _skillTagNamesById
        ..clear()
        ..addAll(selected);
      _skillTagIds
        ..clear()
        ..addAll(selected.keys);
    });
    _scheduleDraftSave();
  }

  void _removeSkill(String id) {
    setState(() {
      _skillTagIds.remove(id);
      _skillTagNamesById.remove(id);
    });
    _scheduleDraftSave();
  }

  Future<void> _upload() async {
    if (_filePath == null) {
      await _showError('Missing media', 'Please pick an image or video.');
      return;
    }
    final title = _title.text.trim();
    if (title.isEmpty) {
      await _showError('Missing title', 'Please enter a title.');
      return;
    }
    if (_skillTagIds.isEmpty) {
      await _showError(
        'Missing skill tag',
        'Please select at least one skill.',
      );
      return;
    }

    setState(() => _loading = true);
    try {
      setState(() => _uploadProgress = 0);
      if (_mediaType == 'video' && _pendingTextOverlays.isNotEmpty) {
        await _bakePendingTextOverlays();
      }
      await _pausePreview();

      await _compressForUploadIfNeeded();
      if (!mounted) return;

      final rawPrice = _price.text.trim().replaceAll(',', '');
      final price = rawPrice.isEmpty ? null : int.tryParse(rawPrice);

      String? thumbnailPath = _coverPath;
      if (_mediaType == 'video' &&
          (thumbnailPath == null || thumbnailPath.trim().isEmpty)) {
        thumbnailPath = await _extractCoverFrame(0);
      }

      await ref.read(reelRepoProvider).uploadReel(
            title: title,
            caption: title,
            description: _desc.text.trim(),
            filePath: _filePath!,
            mediaType: _mediaType,
            skillTags: _skillTagIds,
            thumbnailPath: thumbnailPath,
            visibility: _visibility.toLowerCase(),
            audience: _audience.toLowerCase(),
            commentsEnabled: _commentsAllowed,
            price: price,
            onSendProgress: (sent, total) {
              if (!mounted) return;
              if (total <= 0) return;
              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final next = (sent / total).clamp(0.0, 1.0);
              if (next >= 1 || nowMs - _lastUploadProgressUpdateMs > 33) {
                _lastUploadProgressUpdateMs = nowMs;
                setState(() => _uploadProgress = next);
              }
            },
          );
      await _clearDraft();
      if (!mounted) return;
      final uploadedAt = DateTime.now();
      final uploadedAtLabel = _formatClock(uploadedAt);
      final sizeLabel =
          _selectedFileSizeLabel ?? await _fileSizeLabel(_filePath!);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Uploaded'),
          content: Text(
            'Your post is uploaded successfully.\n\nUploaded at: $uploadedAtLabel\nFile size: $sizeLabel',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      context.pop();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      String message = e.message ?? 'Upload failed';
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        message = data['message'].toString();
      }

      await _saveDraft(errorMessage: 'HTTP $status: $message');

      if (!mounted) return;
      if (status == 403 && message.toLowerCase().contains('provider')) {
        await _showError(
          'Provider access required',
          'To upload posts, your account must be a provider.',
          primaryLabel: 'Become Provider',
          onPrimary: () => context.push('/provider/become'),
        );
      } else if (status == 413) {
        final size = await _fileSizeLabel(_filePath!);
        await _showError(
          'Video too large',
          'File size: $size\n\nTry a shorter video. We compress automatically, but server has a size limit.',
        );
      } else {
        await _showError(
          'Upload failed',
          '$message\n\nSaved as draft. You can try again.',
        );
      }
    } catch (e) {
      await _saveDraft(errorMessage: e.toString());
      if (mounted) {
        await _showError(
          'Upload failed',
          '${e.toString()}\n\nSaved as draft. You can try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _compressForUploadIfNeeded() async {
    if (_mediaType != 'video' || _filePath == null) return;
    final path = _filePath!;
    if (!File(path).existsSync()) return;

    final size = await File(path).length();
    if (size <= _maxUploadBytes) return;

    final out1 =
        '${Directory.systemTemp.path}${Platform.pathSeparator}reel_upload_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final cmd1 =
        '-y -i ${_q(path)} -vf "scale=720:-2" -c:v libx264 -preset veryfast -crf 28 '
        '-c:a aac -b:a 128k -movflags +faststart ${_q(out1)}';
    final dur = _videoPreview?.value.duration ?? const Duration(seconds: 1);
    await _runFfmpeg(
      command: cmd1,
      totalDuration: dur,
      onFailTitle: 'Upload compress failed',
    );
    if (!mounted) return;

    if (!File(out1).existsSync()) return;
    var finalOut = out1;
    var finalSize = await File(finalOut).length();

    if (finalSize > _maxUploadBytes) {
      final out2 =
          '${Directory.systemTemp.path}${Platform.pathSeparator}reel_upload_${DateTime.now().millisecondsSinceEpoch}_small.mp4';
      final cmd2 =
          '-y -i ${_q(finalOut)} -vf "scale=540:-2" -c:v libx264 -preset veryfast -crf 30 '
          '-c:a aac -b:a 96k -movflags +faststart ${_q(out2)}';
      await _runFfmpeg(
        command: cmd2,
        totalDuration: dur,
        onFailTitle: 'Upload compress failed',
      );
      if (!mounted) return;
      if (File(out2).existsSync()) {
        finalOut = out2;
        finalSize = await File(finalOut).length();
      }
    }

    if (finalSize <= size && mounted) {
      _clearCoverSelection();
      setState(() {
        _filePath = finalOut;
      });
      await _initVideoPreview(finalOut);
    }
  }

  @override
  void dispose() {
    _draftSaveDebounce?.cancel();
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    _videoPreview?.dispose();
    _compressSub?.unsubscribe();
    _clearCoverSelection();
    _clearTrimTempFiles();
    VideoCompress.cancelCompression();
    super.dispose();
  }

  Future<void> _showError(
    String title,
    String message, {
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          if (primaryLabel != null && onPrimary != null)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onPrimary();
              },
              child: Text(primaryLabel),
            ),
        ],
      ),
    );
  }

  Future<String> _fileSizeLabel(String path) async {
    try {
      final bytes = await File(path).length();
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB';
    } catch (_) {
      return 'unknown';
    }
  }

  Widget _mediaSummaryCard({bool showChangeButton = true}) {
    final hasFile = _filePath != null && _filePath!.trim().isNotEmpty;
    final sizeLabel = _selectedFileSizeLabel ?? (hasFile ? 'â€”' : 'â€”');

    String? durationLabel;
    String? resolutionLabel;
    String? clipLabel;
    if (_mediaType == 'video') {
      final c = _videoPreview;
      final dur = c?.value.duration ?? Duration.zero;
      if (dur > Duration.zero) durationLabel = _formatDurationShort(dur);
      if (c != null && c.value.isInitialized) {
        final w = c.value.size.width.round();
        final h = c.value.size.height.round();
        if (w > 0 && h > 0) resolutionLabel = '$wÃ—$h';
      }
      final range = _trimRange;
      if (range != null) {
        final len = (range.end - range.start).clamp(0.0, double.infinity);
        if (len > 0) clipLabel = '${len.toStringAsFixed(1)}s clip';
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              _mediaType == 'video'
                  ? Icons.videocam_outlined
                  : Icons.image_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mediaType == 'video' ? 'Video reel' : 'Image post',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _MetaPill(label: 'Size', value: sizeLabel),
                    if (durationLabel != null)
                      _MetaPill(label: 'Duration', value: durationLabel),
                    if (clipLabel != null)
                      _MetaPill(label: 'Clip', value: clipLabel),
                    if (resolutionLabel != null)
                      _MetaPill(label: 'Resolution', value: resolutionLabel),
                  ],
                ),
              ],
            ),
          ),
          if (showChangeButton)
            TextButton(
              onPressed: hasFile ? () => setState(() => _step = 0) : null,
              child: const Text('Change'),
            ),
        ],
      ),
    );
  }

  Widget _mediaPicker() {
    return InkWell(
      onTap: _pick,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: _filePath == null
                    ? Container(
                        color: AppColors.bg,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  size: 42, color: AppColors.textSecondary),
                              SizedBox(height: 8),
                              Text(
                                'Tap to pick media',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _mediaType == 'video'
                        ? (_videoPreview == null ||
                                !(_videoPreview?.value.isInitialized ?? false))
                            ? Container(
                                color: Colors.black,
                                child: const Center(
                                  child: Icon(Icons.videocam_off_outlined,
                                      color: Colors.white54, size: 42),
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: _videoPreview!.value.size.width,
                                  height: _videoPreview!.value.size.height,
                                  child: VideoPlayer(_videoPreview!),
                                ),
                              )
                        : Image.file(File(_filePath!), fit: BoxFit.cover),
              ),
              if (_mediaType == 'video' && _filePath != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: InkWell(
                    onTap: _togglePreviewMute,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: Icon(
                        _previewMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _mediaType == 'video'
                            ? Icons.videocam_outlined
                            : Icons.image_outlined,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Change media',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.edit, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoEditBody({
    required bool canNext,
    required int detailsStep,
  }) {
    final ctrl = _videoPreview;

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: (ctrl == null || !ctrl.value.isInitialized)
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : RepaintBoundary(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _togglePreviewPlayPause,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: ctrl.value.size.width,
                                height: ctrl.value.size.height,
                                child: VideoPlayer(ctrl),
                              ),
                            ),
                          ),
                          if (_pendingTextOverlays.isNotEmpty)
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final input = ctrl.value.size;
                                  final output = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                  final fitted =
                                      applyBoxFit(BoxFit.cover, input, output);
                                  final scale = fitted.destination.width /
                                      math.max(1, fitted.source.width);
                                  final dx = (output.width -
                                          fitted.destination.width) /
                                      2;
                                  final dy = (output.height -
                                          fitted.destination.height) /
                                      2;

                                  return Stack(
                                    children: _pendingTextOverlays
                                        .asMap()
                                        .entries
                                        .map((entry) {
                                      final index = entry.key;
                                      final o = entry.value;
                                      final px =
                                          o.nx.clamp(0.0, 1.0) * input.width;
                                      final py =
                                          o.ny.clamp(0.0, 1.0) * input.height;
                                      final x = px * scale + dx;
                                      final y = py * scale + dy;

                                      return Positioned(
                                        left: x,
                                        top: y,
                                        child: FractionalTranslation(
                                          translation: const Offset(-0.5, -0.5),
                                          child: GestureDetector(
                                            onTap: () =>
                                                _editTextOverlayAt(index),
                                            child: _VideoTextOverlayChip(
                                              text: o.text,
                                              fontSize: o.fontSize,
                                              textColor: o.textColor,
                                              strokeWidth: o.strokeWidth,
                                              strokeColor: o.strokeColor,
                                              showBackground: o.showBackground,
                                              backgroundColor:
                                                  o.backgroundColor,
                                              backgroundOpacity:
                                                  o.backgroundOpacity,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ),
                          Positioned.fill(
                            child: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: ctrl,
                              builder: (context, value, _) {
                                final show = !value.isPlaying;
                                return IgnorePointer(
                                  child: AnimatedOpacity(
                                    opacity: show ? 1 : 0,
                                    duration: const Duration(milliseconds: 140),
                                    child: Center(
                                      child: Container(
                                        width: 74,
                                        height: 74,
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.35),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 44,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: InkWell(
              onTap: _togglePreviewMute,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Icon(
                  _previewMuted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 80,
            bottom: 120,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _EditorToolButton(
                    icon: Icons.content_cut,
                    label: 'Trim',
                    onTap: _processing ? null : _trimVideo,
                  ),
                  const SizedBox(height: 14),
                  _EditorToolButton(
                    icon: Icons.crop,
                    label: 'Crop',
                    onTap: _processing ? null : _cropVideo,
                  ),
                  const SizedBox(height: 14),
                  _EditorToolButton(
                    icon: Icons.text_fields,
                    label: 'Text',
                    onTap: _processing ? null : _addTextOverlay,
                  ),
                  const SizedBox(height: 14),
                  _EditorToolButton(
                    icon: Icons.library_music_outlined,
                    label: 'Audio',
                    onTap: _processing ? null : _replaceAudio,
                  ),
                  const SizedBox(height: 14),
                  _EditorToolButton(
                    icon: Icons.high_quality,
                    label: 'HQ',
                    onTap: _processing ? null : _compressHighQuality,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 14,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processing
                          ? null
                          : () async {
                              await _saveDraft();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Saved to draft.')),
                              );
                              context.pop();
                            },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        side: BorderSide(color: Colors.white.withAlpha(160)),
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withAlpha(16),
                      ),
                      child: const Text(
                        'Draft',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: AppButton(
                        label: 'Next',
                        isLoading: _processing,
                        onTap: canNext
                            ? () async {
                                await _pausePreview();
                                if (!mounted) return;
                                setState(() => _step = detailsStep);
                              }
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_processing)
            Positioned(
              left: 14,
              right: 14,
              bottom: 74,
              child: SafeArea(
                top: false,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const CupertinoActivityIndicator(color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _isCompressing
                              ? 'Processing... ${(100 * _compressProgress).toStringAsFixed(0)}%'
                              : 'Processing...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailsBody() {
    final hasFile = _filePath != null && _filePath!.trim().isNotEmpty;

    Widget coverPreview() {
      if (!hasFile) {
        return const Center(
          child: Icon(
            Icons.image_outlined,
            color: AppColors.textSecondary,
          ),
        );
      }
      if (_mediaType == 'video') {
        final cover = _coverPath;
        if (cover != null && cover.trim().isNotEmpty) {
          return Image.file(File(cover), fit: BoxFit.cover);
        }
        final c = _videoPreview;
        if (c == null || !c.value.isInitialized) {
          return const Center(
            child: Icon(
              Icons.videocam_off_outlined,
              color: AppColors.textSecondary,
            ),
          );
        }
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        );
      }
      return Image.file(File(_filePath!), fit: BoxFit.cover);
    }

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 132),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DETAILS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openCoverPicker,
                      borderRadius: BorderRadius.circular(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 104,
                          height: 104,
                          color: AppColors.surface,
                          child: Stack(
                            children: [
                              Positioned.fill(child: coverPreview()),
                              if (_mediaType == 'video' && _coverSecond != null)
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(150),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _formatSecondsShort(_coverSecond!),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(140),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Select cover',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned(
                                right: 6,
                                top: 6,
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(0x88000000),
                                  child: Icon(
                                    Icons.edit,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _title,
                      maxLines: 1,
                      maxLength: 70,
                      decoration: InputDecoration(
                        hintText: 'Title',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: AppColors.border.withAlpha(120),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: AppColors.border.withAlpha(120),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: AppColors.primary.withAlpha(160),
                            width: 1.1,
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _desc,
                maxLines: 3,
                maxLength: 220,
                decoration: InputDecoration(
                  hintText: 'Description (optional)',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: AppColors.border.withAlpha(120),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: AppColors.border.withAlpha(120),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: AppColors.primary.withAlpha(160),
                      width: 1.1,
                    ),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'SETTINGS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _DetailsRow(
                      icon: Icons.remove_red_eye_outlined,
                      title: 'Visibility',
                      value: _visibility,
                      onTap: _pickVisibility,
                    ),
                    Divider(
                        height: 1,
                        indent: 44,
                        color: AppColors.border.withAlpha(120)),
                    _DetailsRow(
                      icon: Icons.people_alt_outlined,
                      title: 'Select Audience',
                      value: _audience,
                      onTap: _pickAudience,
                    ),
                    Divider(
                        height: 1,
                        indent: 44,
                        color: AppColors.border.withAlpha(120)),
                    _DetailsSwitchRow(
                      icon: Icons.comment_outlined,
                      title: 'Allow comments',
                      subtitle: _commentsAllowed ? 'Allow all comments' : 'Off',
                      value: _commentsAllowed,
                      onChanged: (v) {
                        setState(() => _commentsAllowed = v);
                        _scheduleDraftSave();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'TAGS & PRICING',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _DetailsRow(
                      icon: Icons.local_offer_outlined,
                      title: 'Skills *',
                      value: _skillTagIds.isEmpty
                          ? 'Select'
                          : '${_skillTagIds.length} selected',
                      onTap: _openSkillPicker,
                    ),
                    Divider(
                        height: 1,
                        indent: 44,
                        color: AppColors.border.withAlpha(120)),
                    _DetailsRow(
                      icon: Icons.payments_outlined,
                      title: 'Price',
                      value: _price.text.trim().isEmpty
                          ? 'Optional'
                          : _price.text.trim(),
                      onTap: _editPrice,
                    ),
                  ],
                ),
              ),
              if (_skillTagIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _skillTagIds
                      .map(
                        (id) => InputChip(
                          label: Text(_skillTagNamesById[id] ?? id),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          side: BorderSide(
                              color: AppColors.border.withAlpha(140)),
                          backgroundColor: AppColors.surface,
                          onDeleted: () => _removeSkill(id),
                        ),
                      )
                      .toList(),
                ),
              ],
              const Text(
                'Keep the app open until upload finishes.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 14,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: _ProgressFillButton(
                label: _mediaType == 'image' ? 'Upload Image' : 'Upload Shorts',
                isLoading: _loading,
                progress: _uploadProgress,
                onTap: (_loading || _processing) ? null : _upload,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canNext = _filePath != null && !_processing;
    final hasVideoEditStep = _mediaType == 'video';
    final detailsStep = hasVideoEditStep ? 2 : 1;
    final hideSelectStep = (widget.initialMediaType ?? '').trim().isNotEmpty;

    ref.listen<AsyncValue<List<SkillModel>>>(skillsProvider, (prev, next) {
      next.whenData(_syncSelectedSkillNames);
    });

    final title = (_step == 1 && hasVideoEditStep)
        ? 'Edit video'
        : (_step == detailsStep)
            ? 'Add details'
            : (hideSelectStep ? 'Upload' : 'Select media');

    final Widget body = (_step == 1 && hasVideoEditStep)
        ? _buildVideoEditBody(canNext: canNext, detailsStep: detailsStep)
        : (_step == detailsStep)
            ? _buildDetailsBody()
            : (hideSelectStep
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            _autoPicking
                                ? 'Opening gallery...'
                                : 'Select your ${_mediaType == 'video' ? 'video' : 'image'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (!_autoPicking) ...[
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _autoPickInitialMedia,
                              child: const Text('Select from gallery'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'image',
                                    label: Text('Image'),
                                    icon: Icon(Icons.image_outlined),
                                  ),
                                  ButtonSegment(
                                    value: 'video',
                                    label: Text('Video'),
                                    icon: Icon(Icons.videocam_outlined),
                                  ),
                                ],
                                selected: {_mediaType},
                                onSelectionChanged: (s) =>
                                    _setMediaType(s.first),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(height: 8),
                        _mediaPicker(),
                        if (_filePath != null) ...[
                          const SizedBox(height: 12),
                          _mediaSummaryCard(showChangeButton: false),
                        ],
                        if (_processing) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const CupertinoActivityIndicator(),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _isCompressing
                                      ? 'Compressing... ${(100 * _compressProgress).toStringAsFixed(0)}%'
                                      : 'Processing...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_isCompressing)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value: _compressProgress == 0
                                    ? null
                                    : _compressProgress,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                        if (_mediaType == 'video') ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  color: AppColors.textSecondary,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Tap Next to trim, crop, and add audio.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        AppButton(
                          label: 'Next',
                          isLoading: _processing,
                          onTap: canNext
                              ? () async {
                                  await _pausePreview();
                                  if (!mounted) return;
                                  setState(() => _step =
                                      hasVideoEditStep ? 1 : detailsStep);
                                }
                              : null,
                        ),
                      ],
                    ),
                  ));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_step == 0 && !hideSelectStep)
            TextButton(
              onPressed: canNext
                  ? () async {
                      await _pausePreview();
                      if (!mounted) return;
                      setState(
                          () => _step = hasVideoEditStep ? 1 : detailsStep);
                    }
                  : null,
              child: const Text('Next'),
            )
          else if (_step == 1 && hasVideoEditStep) ...[
            TextButton(
              onPressed: hideSelectStep
                  ? () {
                      if (context.canPop()) context.pop();
                    }
                  : () => setState(() => _step = 0),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: canNext
                  ? () async {
                      await _pausePreview();
                      if (!mounted) return;
                      setState(() => _step = detailsStep);
                    }
                  : null,
              child: const Text('Next'),
            ),
          ] else if (_step == detailsStep) ...[
            // No extra actions (clean header)
          ] else ...[
            // Fallback (shouldn't happen)
          ],
        ],
      ),
      body: body,
    );
  }
}

class _DetailsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _DetailsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (value.trim().isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border.withAlpha(140)),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceBottomSheet extends StatefulWidget {
  final String initialValue;

  const _PriceBottomSheet({required this.initialValue});

  @override
  State<_PriceBottomSheet> createState() => _PriceBottomSheetState();
}

class _PriceBottomSheetState extends State<_PriceBottomSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue.trim();
    _controller = TextEditingController(text: initial.isEmpty ? '' : initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Future.microtask(() {
      if (!mounted) return;
      Navigator.of(context).pop(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 8,
          bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set price',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'Optional. Enter a number (no decimals).',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _close(_controller.text.trim()),
              decoration: InputDecoration(
                hintText: 'Enter amount',
                prefixIcon: const Icon(Icons.currency_rupee_rounded),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: AppColors.border.withAlpha(120)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: AppColors.border.withAlpha(120)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _close(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _close(_controller.text.trim()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressFillButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final double progress;
  final VoidCallback? onTap;

  const _ProgressFillButton({
    required this.label,
    required this.isLoading,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final p = progress.clamp(0.0, 1.0);
    final bg = enabled ? AppColors.primary : AppColors.primary.withAlpha(120);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isLoading)
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(end: p),
                builder: (context, value, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(color: Colors.black.withAlpha(46)),
                  ),
                ),
              ),
            Center(
              child: Text(
                isLoading
                    ? (p >= 1
                        ? '$label  Processing...'
                        : '$label  ${(p * 100).round()}%')
                    : label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DetailsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetaPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withAlpha(140)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPickResult {
  final String path;
  final double seconds;

  const _CoverPickResult({required this.path, required this.seconds});
}

class _SelectCoverScreen extends StatefulWidget {
  final Duration videoDuration;
  final double? initialSeconds;
  final String? initialPath;
  final Future<String> Function(double seconds) extractFrame;

  const _SelectCoverScreen({
    required this.videoDuration,
    required this.extractFrame,
    this.initialSeconds,
    this.initialPath,
  });

  @override
  State<_SelectCoverScreen> createState() => _SelectCoverScreenState();
}

class _SelectCoverScreenState extends State<_SelectCoverScreen> {
  static const _thumbCount = 12;
  bool _loadingThumbs = true;
  bool _generating = false;
  String? _error;
  final List<_CoverPickResult> _thumbs = [];
  String? _currentPath;
  double _seconds = 0;
  double? _generatedSeconds;
  bool _currentIsExact = false;
  bool _scrubbingStrip = false;

  @override
  void initState() {
    super.initState();
    _seconds = _clampSeconds(widget.initialSeconds ?? 0);
    _currentPath = widget.initialPath;
    _generatedSeconds = widget.initialSeconds;
    _currentIsExact = _currentPath != null;
    _generateCurrent(_seconds);
    _generateThumbnails();
  }

  double _durationSeconds() {
    return (widget.videoDuration.inMilliseconds / 1000.0)
        .clamp(0.0, 24 * 60 * 60);
  }

  double _clampSeconds(double seconds) {
    final total = _durationSeconds();
    final end = math.max(0.0, total - 0.12);
    return seconds.clamp(0.0, end).toDouble();
  }

  String _timeLabel(double seconds) {
    final s = seconds.clamp(0.0, 24 * 60 * 60).toDouble();
    final whole = s.floor();
    final mm = (whole ~/ 60).toString();
    final ss = (whole % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _generateCurrent(double seconds) async {
    final s = _clampSeconds(seconds);
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final path = await widget.extractFrame(s);
      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _generatedSeconds = s;
        _seconds = s;
        _currentIsExact = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  List<double> _thumbnailTimes() {
    final total = _durationSeconds();
    if (total <= 0.2) return const [0.0];
    const count = _thumbCount;
    final end = math.max(0.0, total - 0.12);
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      final t = (i / (count - 1)) * end;
      out.add(t);
    }
    return out;
  }

  Future<void> _generateThumbnails() async {
    try {
      final ts = _thumbnailTimes();
      for (final t in ts) {
        if (!mounted) return;
        final path = await widget.extractFrame(t);
        if (!mounted) return;
        _thumbs.add(_CoverPickResult(path: path, seconds: t));
        if (mounted) setState(() {});
      }
      if (!mounted) return;
      setState(() => _loadingThumbs = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingThumbs = false;
        _error = e.toString();
      });
    }
  }

  void _setSecondsFromStripPosition(double dx, double width) {
    if (width <= 0) return;
    final total = _durationSeconds();
    final end = math.max(0.0, total - 0.12);
    final clampedDx = dx.clamp(0.0, width).toDouble();
    final next = (clampedDx / width) * end;
    final s = _clampSeconds(next);

    if (_thumbs.isNotEmpty) {
      var best = 0;
      var bestDist = double.infinity;
      for (var i = 0; i < _thumbs.length; i++) {
        final d = (_thumbs[i].seconds - s).abs();
        if (d < bestDist) {
          best = i;
          bestDist = d;
        }
      }
      setState(() {
        _seconds = s;
        _currentPath = _thumbs[best].path;
        _currentIsExact = false;
        _error = null;
      });
      return;
    }

    setState(() => _seconds = s);
  }

  @override
  Widget build(BuildContext context) {
    final canDone = _currentPath != null && !_generating;
    final total = _durationSeconds();
    final stripEnd = math.max(0.0, total - 0.12);
    return SafeArea(
      top: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Select cover'),
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            TextButton(
              onPressed: canDone
                  ? () async {
                      final s = _clampSeconds(_seconds);
                      final g = _generatedSeconds;
                      if (!_currentIsExact ||
                          g == null ||
                          (s - g).abs() > 0.04) {
                        await _generateCurrent(s);
                      }
                      if (!context.mounted || _currentPath == null) return;
                      Navigator.of(context).pop(
                        _CoverPickResult(path: _currentPath!, seconds: s),
                      );
                    }
                  : null,
              child: const Text('Done'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const ratio = 9 / 16;
                    var h = constraints.maxHeight;
                    var w = h * ratio;
                    if (w > constraints.maxWidth) {
                      w = constraints.maxWidth;
                      h = w / ratio;
                    }
                    return Center(
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            color: Colors.black,
                            child: _currentPath == null
                                ? const Center(
                                    child: CupertinoActivityIndicator(
                                      color: Colors.white,
                                    ),
                                  )
                                : Image.file(
                                    File(_currentPath!),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _timeLabel(_seconds),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '/ ${_timeLabel(stripEnd)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_generating)
                    const Text(
                      'Loading...',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              Slider(
                value: _seconds.clamp(0.0, stripEnd),
                min: 0,
                max: stripEnd,
                divisions: stripEnd <= 0 ? null : stripEnd.ceil().clamp(1, 600),
                onChanged: (v) => setState(() => _seconds = v),
                onChangeEnd: (v) => _generateCurrent(v),
              ),
              Row(
                children: [
                  const Text(
                    '0:00',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _timeLabel(stripEnd),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loadingThumbs) ...[
                const LinearProgressIndicator(minHeight: 6),
                const SizedBox(height: 12),
              ],
              if (_thumbs.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final selW = width / _thumbs.length;
                    final left = stripEnd <= 0
                        ? 0.0
                        : ((_seconds / stripEnd) * (width - selW))
                            .clamp(0.0, width - selW)
                            .toDouble();
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) {
                        _setSecondsFromStripPosition(d.localPosition.dx, width);
                      },
                      onTapUp: (d) async {
                        _setSecondsFromStripPosition(d.localPosition.dx, width);
                        await _generateCurrent(_seconds);
                      },
                      onPanStart: (_) => setState(() => _scrubbingStrip = true),
                      onPanUpdate: (d) => _setSecondsFromStripPosition(
                          d.localPosition.dx, width),
                      onPanEnd: (_) async {
                        setState(() => _scrubbingStrip = false);
                        await _generateCurrent(_seconds);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IgnorePointer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                height: 72,
                                child: Row(
                                  children: [
                                    for (final t in _thumbs)
                                      Expanded(
                                        child: Image.file(
                                          File(t.path),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: left.clamp(0.0, math.max(0.0, width - selW)),
                            top: -28,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(180),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                child: Text(
                                  _timeLabel(_seconds),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: left,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: selW,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _scrubbingStrip
                                        ? AppColors.primary
                                        : Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 10),
              const Text(
                'Tip: Drag the strip to pick any frame.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimClipScreen extends StatefulWidget {
  final Duration videoDuration;
  final RangeValues initialRange;
  final Future<String> Function(double seconds) extractThumb;

  const _TrimClipScreen({
    required this.videoDuration,
    required this.initialRange,
    required this.extractThumb,
  });

  @override
  State<_TrimClipScreen> createState() => _TrimClipScreenState();
}

class _TrimClipScreenState extends State<_TrimClipScreen> {
  static const _thumbCount = 12;
  static const _minClipSeconds = 0.5;

  bool _loadingThumbs = true;
  String? _error;
  final List<_CoverPickResult> _thumbs = [];

  double _startSec = 0;
  double _endSec = 0;

  @override
  void initState() {
    super.initState();
    final total = _durationSeconds();
    final stripEnd = math.max(0.0, total - 0.12);
    final initStart = widget.initialRange.start.clamp(0.0, stripEnd).toDouble();
    final initEnd = widget.initialRange.end.clamp(0.0, stripEnd).toDouble();
    _startSec = math.min(initStart, initEnd);
    _endSec = math.max(initStart, initEnd);
    if (_endSec - _startSec < _minClipSeconds) {
      _endSec = (_startSec + _minClipSeconds).clamp(0.0, stripEnd).toDouble();
    }
    _generateThumbnails();
  }

  double _durationSeconds() {
    return (widget.videoDuration.inMilliseconds / 1000.0)
        .clamp(0.0, 24 * 60 * 60);
  }

  String _timeLabel(double seconds) {
    final s = seconds.clamp(0.0, 24 * 60 * 60).toDouble();
    final whole = s.floor();
    final mm = (whole ~/ 60).toString();
    final ss = (whole % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  List<double> _thumbnailTimes() {
    final total = _durationSeconds();
    if (total <= 0.2) return const [0.0];
    final end = math.max(0.0, total - 0.12);
    final out = <double>[];
    for (var i = 0; i < _thumbCount; i++) {
      final t = (i / (_thumbCount - 1)) * end;
      out.add(t);
    }
    return out;
  }

  Future<void> _generateThumbnails() async {
    try {
      final ts = _thumbnailTimes();
      for (final t in ts) {
        if (!mounted) return;
        final path = await widget.extractThumb(t);
        if (!mounted) return;
        _thumbs.add(_CoverPickResult(path: path, seconds: t));
        if (mounted) setState(() {});
      }
      if (!mounted) return;
      setState(() => _loadingThumbs = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingThumbs = false;
        _error = e.toString();
      });
    }
  }

  double _clampToStrip(double seconds) {
    final stripEnd = math.max(0.0, _durationSeconds() - 0.12);
    return seconds.clamp(0.0, stripEnd).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final total = _durationSeconds();
    final stripEnd = math.max(0.0, total - 0.12);
    final clipLen = (_endSec - _startSec).clamp(0.0, stripEnd);
    final canApply = clipLen >= _minClipSeconds;

    return SafeArea(
      top: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trim'),
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            TextButton(
              onPressed: canApply
                  ? () => Navigator.of(context).pop(
                        RangeValues(_startSec, _endSec),
                      )
                  : null,
              child: const Text('Apply'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Text(
                    _timeLabel(_startSec),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${clipLen.toStringAsFixed(1)}s',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _timeLabel(_endSec),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loadingThumbs) ...[
                const LinearProgressIndicator(minHeight: 6),
                const SizedBox(height: 12),
              ],
              if (_thumbs.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final pxPerSec = stripEnd <= 0 ? 0.0 : width / stripEnd;
                    final minPx = _minClipSeconds * pxPerSec;
                    final startX = stripEnd <= 0 ? 0.0 : _startSec * pxPerSec;
                    final endX = stripEnd <= 0 ? width : _endSec * pxPerSec;

                    void setStartFromDx(double dx) {
                      final next =
                          _clampToStrip(dx / (pxPerSec == 0 ? 1 : pxPerSec));
                      final maxStart = math.max(0.0, _endSec - _minClipSeconds);
                      setState(() =>
                          _startSec = next.clamp(0.0, maxStart).toDouble());
                    }

                    void setEndFromDx(double dx) {
                      final next =
                          _clampToStrip(dx / (pxPerSec == 0 ? 1 : pxPerSec));
                      final minEnd = _startSec + _minClipSeconds;
                      setState(() =>
                          _endSec = next.clamp(minEnd, stripEnd).toDouble());
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTapDown: (d) {
                            final x = d.localPosition.dx;
                            if (x <= startX + 18) {
                              setStartFromDx(x);
                            } else if (x >= endX - 18) {
                              setEndFromDx(x);
                            }
                          },
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  height: 72,
                                  child: Row(
                                    children: [
                                      for (final t in _thumbs)
                                        Expanded(
                                          child: Image.file(
                                            File(t.path),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                width: startX.clamp(0.0, width),
                                child: Container(
                                    color: Colors.black.withAlpha(130)),
                              ),
                              Positioned(
                                left: endX.clamp(0.0, width),
                                top: 0,
                                bottom: 0,
                                right: 0,
                                child: Container(
                                    color: Colors.black.withAlpha(130)),
                              ),
                              Positioned(
                                left: startX.clamp(0.0, width),
                                top: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (d) => setStartFromDx(
                                      (_startSec * pxPerSec) + d.delta.dx),
                                  child: Container(
                                    width: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(28),
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 3,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: (endX - 34).clamp(0.0, width - 34),
                                top: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (d) => setEndFromDx(
                                      (_endSec * pxPerSec) + d.delta.dx),
                                  child: Container(
                                    width: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(28),
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 3,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: startX.clamp(0.0, width),
                                right: (width - endX).clamp(0.0, width),
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              if (minPx.isFinite && minPx > 0)
                                const SizedBox.shrink(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tip: Drag the left/right handles to select a clip.',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoCropRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const _VideoCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class _PendingTextOverlay {
  final String text;
  final double nx; // 0..1 in source video space (x center)
  final double ny; // 0..1 in source video space (y center)
  final double fontSize;
  final Color textColor;
  final double strokeWidth;
  final Color strokeColor;
  final bool showBackground;
  final Color backgroundColor;
  final double backgroundOpacity;

  const _PendingTextOverlay({
    required this.text,
    required this.nx,
    required this.ny,
    required this.fontSize,
    this.textColor = Colors.white,
    this.strokeWidth = 0,
    this.strokeColor = Colors.black,
    this.showBackground = true,
    this.backgroundColor = Colors.black,
    this.backgroundOpacity = 0.45,
  });
}

class _DeleteTextOverlay {
  const _DeleteTextOverlay();
}

class _VideoTextOverlayChip extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color textColor;
  final double strokeWidth;
  final Color strokeColor;
  final bool showBackground;
  final Color backgroundColor;
  final double backgroundOpacity;

  const _VideoTextOverlayChip({
    required this.text,
    required this.fontSize,
    required this.textColor,
    required this.strokeWidth,
    required this.strokeColor,
    required this.showBackground,
    required this.backgroundColor,
    required this.backgroundOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final size = fontSize.clamp(12, 72).toDouble();
    final hasStroke = strokeWidth > 0.0;
    final bg = showBackground
        ? backgroundColor.withOpacity(backgroundOpacity.clamp(0.0, 1.0))
        : Colors.transparent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Stack(
        children: [
          if (hasStroke)
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: size,
                height: 1.05,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = strokeWidth.clamp(0.5, 10)
                  ..color = strokeColor,
              ),
            ),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: size,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeTextOverlayScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final _PendingTextOverlay? initial;
  final bool allowDelete;

  const _FreeTextOverlayScreen({
    required this.controller,
    this.initial,
    this.allowDelete = false,
  });

  @override
  State<_FreeTextOverlayScreen> createState() => _FreeTextOverlayScreenState();
}

class _FreeTextOverlayScreenState extends State<_FreeTextOverlayScreen> {
  final _text = TextEditingController();
  double _fontSize = 40;
  Offset _norm = const Offset(0.5, 0.5);
  Color _textColor = Colors.white;
  double _strokeWidth = 0;
  Color _strokeColor = Colors.black;
  bool _showBackground = true;
  Color _backgroundColor = Colors.black;
  double _backgroundOpacity = 0.45;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _text.text = initial.text;
      _fontSize = initial.fontSize;
      _norm = Offset(initial.nx, initial.ny);
      _textColor = initial.textColor;
      _strokeWidth = initial.strokeWidth;
      _strokeColor = initial.strokeColor;
      _showBackground = initial.showBackground;
      _backgroundColor = initial.backgroundColor;
      _backgroundOpacity = initial.backgroundOpacity;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.controller.pause();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final ready = ctrl.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.initial == null ? 'Add text' : 'Edit text'),
        actions: [
          if (widget.allowDelete)
            IconButton(
              onPressed: () =>
                  Navigator.of(context).pop(const _DeleteTextOverlay()),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
          TextButton(
            onPressed: () {
              final t = _text.text.trim();
              if (t.isEmpty) return;
              Navigator.of(context).pop(
                _PendingTextOverlay(
                  text: t,
                  nx: _norm.dx.clamp(0.0, 1.0),
                  ny: _norm.dy.clamp(0.0, 1.0),
                  fontSize: _fontSize,
                  textColor: _textColor,
                  strokeWidth: _strokeWidth,
                  strokeColor: _strokeColor,
                  showBackground: _showBackground,
                  backgroundColor: _backgroundColor,
                  backgroundOpacity: _backgroundOpacity,
                ),
              );
            },
            child: Text(widget.initial == null ? 'Add' : 'Save'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ready
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final input = ctrl.value.size;
                          final output = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final fitted =
                              applyBoxFit(BoxFit.cover, input, output);
                          final scale = fitted.destination.width /
                              math.max(1, fitted.source.width);
                          final dx =
                              (output.width - fitted.destination.width) / 2;
                          final dy =
                              (output.height - fitted.destination.height) / 2;

                          Offset toOutput(Offset norm) {
                            final px = norm.dx.clamp(0.0, 1.0) * input.width;
                            final py = norm.dy.clamp(0.0, 1.0) * input.height;
                            return Offset(px * scale + dx, py * scale + dy);
                          }

                          Offset toNorm(Offset out) {
                            final px = (out.dx - dx) / scale;
                            final py = (out.dy - dy) / scale;
                            return Offset(
                              (px / math.max(1, input.width)).clamp(0.0, 1.0),
                              (py / math.max(1, input.height)).clamp(0.0, 1.0),
                            );
                          }

                          var outPos = toOutput(_norm);

                          return Stack(
                            children: [
                              Positioned.fill(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: input.width,
                                    height: input.height,
                                    child: VideoPlayer(ctrl),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (d) {
                                    setState(() {
                                      outPos = outPos + d.delta;
                                      _norm = toNorm(outPos);
                                    });
                                  },
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: outPos.dx,
                                        top: outPos.dy,
                                        child: FractionalTranslation(
                                          translation: const Offset(-0.5, -0.5),
                                          child: _VideoTextOverlayChip(
                                            text: _text.text.isEmpty
                                                ? 'Text'
                                                : _text.text,
                                            fontSize: _fontSize,
                                            textColor: _textColor,
                                            strokeWidth: _strokeWidth,
                                            strokeColor: _strokeColor,
                                            showBackground: _showBackground,
                                            backgroundColor: _backgroundColor,
                                            backgroundOpacity:
                                                _backgroundOpacity,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.80),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Color',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ColorDot(
                                color: Colors.white,
                                selected: _textColor == Colors.white,
                                onTap: () =>
                                    setState(() => _textColor = Colors.white),
                              ),
                              _ColorDot(
                                color: Colors.black,
                                selected: _textColor == Colors.black,
                                onTap: () =>
                                    setState(() => _textColor = Colors.black),
                              ),
                              _ColorDot(
                                color: const Color(0xFFFF3B30),
                                selected: _textColor == const Color(0xFFFF3B30),
                                onTap: () => setState(
                                    () => _textColor = const Color(0xFFFF3B30)),
                              ),
                              _ColorDot(
                                color: const Color(0xFF34C759),
                                selected: _textColor == const Color(0xFF34C759),
                                onTap: () => setState(
                                    () => _textColor = const Color(0xFF34C759)),
                              ),
                              _ColorDot(
                                color: const Color(0xFF0A84FF),
                                selected: _textColor == const Color(0xFF0A84FF),
                                onTap: () => setState(
                                    () => _textColor = const Color(0xFF0A84FF)),
                              ),
                              _ColorDot(
                                color: const Color(0xFFFFD60A),
                                selected: _textColor == const Color(0xFFFFD60A),
                                onTap: () => setState(
                                    () => _textColor = const Color(0xFFFFD60A)),
                              ),
                            ]
                                .map((w) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: w,
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type text',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Size',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          value: _fontSize,
                          min: 18,
                          max: 72,
                          onChanged: (v) => setState(() => _fontSize = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text(
                        'Border',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          value: _strokeWidth.clamp(0, 10),
                          min: 0,
                          max: 10,
                          onChanged: (v) => setState(() => _strokeWidth = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ColorDot(
                        color: Colors.black,
                        selected: _strokeColor == Colors.black,
                        onTap: () =>
                            setState(() => _strokeColor = Colors.black),
                      ),
                      const SizedBox(width: 8),
                      _ColorDot(
                        color: Colors.white,
                        selected: _strokeColor == Colors.white,
                        onTap: () =>
                            setState(() => _strokeColor = Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Switch(
                        value: _showBackground,
                        onChanged: (v) => setState(() => _showBackground = v),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Background',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          value: _backgroundOpacity.clamp(0.0, 0.85),
                          min: 0,
                          max: 0.85,
                          onChanged: (v) =>
                              setState(() => _backgroundOpacity = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ColorDot(
                        color: Colors.black,
                        selected: _backgroundColor == Colors.black,
                        onTap: () =>
                            setState(() => _backgroundColor = Colors.black),
                      ),
                      const SizedBox(width: 8),
                      _ColorDot(
                        color: Colors.white,
                        selected: _backgroundColor == Colors.white,
                        onTap: () =>
                            setState(() => _backgroundColor = Colors.white),
                      ),
                    ],
                  ),
                  Text(
                    'Drag to place anywhere',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomVideoCropScreen extends StatefulWidget {
  final VideoPlayerController controller;

  const _CustomVideoCropScreen({required this.controller});

  @override
  State<_CustomVideoCropScreen> createState() => _CustomVideoCropScreenState();
}

class _CustomVideoCropScreenState extends State<_CustomVideoCropScreen> {
  static const _minCropPx = 64.0;

  double? _aspectLock; // w/h in pixels (null = free)
  late final Size _srcSize;

  Rect _cropPx = Rect.zero;
  Rect _startCropPx = Rect.zero;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    final v = widget.controller.value;
    _srcSize = v.isInitialized ? v.size : const Size(1080, 1920);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.controller.pause();
      } catch (_) {}
    });

    final w = _srcSize.width;
    final h = _srcSize.height;
    final initialW = math.max(_minCropPx, w * 0.78);
    final initialH = math.max(_minCropPx, h * 0.78);
    _cropPx = Rect.fromCenter(
      center: Offset(w / 2, h / 2),
      width: initialW.clamp(_minCropPx, w),
      height: initialH.clamp(_minCropPx, h),
    );
  }

  Rect _clampRect(Rect r) {
    var rect = r;
    var width = rect.width.clamp(_minCropPx, _srcSize.width);
    var height = rect.height.clamp(_minCropPx, _srcSize.height);

    final aspect = _aspectLock;
    if (aspect != null && aspect > 0) {
      height = width / aspect;
      if (height > _srcSize.height) {
        height = _srcSize.height;
        width = height * aspect;
      }
      if (width > _srcSize.width) {
        width = _srcSize.width;
        height = width / aspect;
      }
    }

    rect = Rect.fromCenter(center: rect.center, width: width, height: height);

    var dx = 0.0;
    var dy = 0.0;
    if (rect.left < 0) dx = -rect.left;
    if (rect.top < 0) dy = -rect.top;
    if (rect.right > _srcSize.width) dx = _srcSize.width - rect.right;
    if (rect.bottom > _srcSize.height) dy = _srcSize.height - rect.bottom;
    return rect.shift(Offset(dx, dy));
  }

  void _setAspect(double? aspect) {
    setState(() {
      _aspectLock = aspect;
      _cropPx = _clampRect(_cropPx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final ready = ctrl.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Custom crop'),
        actions: [
          TextButton(
            onPressed: ready
                ? () {
                    final rect = _clampRect(_cropPx);
                    Navigator.of(context).pop(
                      _VideoCropRect(
                        left: rect.left,
                        top: rect.top,
                        width: rect.width,
                        height: rect.height,
                      ),
                    );
                  }
                : null,
            child: const Text('Apply'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CropModeChip(
                      label: 'Free',
                      selected: _aspectLock == null,
                      onTap: () => _setAspect(null),
                    ),
                    const SizedBox(width: 8),
                    _CropModeChip(
                      label: '9:16',
                      selected: _aspectLock == (9 / 16),
                      onTap: () => _setAspect(9 / 16),
                    ),
                    const SizedBox(width: 8),
                    _CropModeChip(
                      label: '1:1',
                      selected: _aspectLock == 1,
                      onTap: () => _setAspect(1),
                    ),
                    const SizedBox(width: 8),
                    _CropModeChip(
                      label: '16:9',
                      selected: _aspectLock == (16 / 9),
                      onTap: () => _setAspect(16 / 9),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ready
                    ? AspectRatio(
                        aspectRatio: ctrl.value.aspectRatio,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final scale = constraints.maxWidth /
                                math.max(1, _srcSize.width);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (d) {
                                _startCropPx = _cropPx;
                                _startFocal = d.localFocalPoint;
                              },
                              onScaleUpdate: (d) {
                                final pixelDelta =
                                    (d.localFocalPoint - _startFocal) / scale;
                                final center = _startCropPx.center + pixelDelta;
                                final s = d.scale.isFinite
                                    ? d.scale.clamp(0.5, 4.0)
                                    : 1.0;

                                var width = _startCropPx.width * s;
                                var height = _startCropPx.height * s;
                                final aspect = _aspectLock;
                                if (aspect != null && aspect > 0) {
                                  height = width / aspect;
                                }

                                setState(() {
                                  _cropPx = _clampRect(
                                    Rect.fromCenter(
                                      center: center,
                                      width: width,
                                      height: height,
                                    ),
                                  );
                                });
                              },
                              child: Stack(
                                children: [
                                  Positioned.fill(child: VideoPlayer(ctrl)),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _CropOverlayPainter(
                                        crop: Rect.fromLTWH(
                                          _cropPx.left * scale,
                                          _cropPx.top * scale,
                                          _cropPx.width * scale,
                                          _cropPx.height * scale,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Text(
                'Drag to move â€¢ Pinch to resize',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CropModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect crop;

  const _CropOverlayPainter({required this.crop});

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(RRect.fromRectXY(crop, 14, 14));
    final overlay = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(overlay, dimPaint);
    canvas.drawRRect(RRect.fromRectXY(crop, 14, 14), borderPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 1; i <= 2; i++) {
      final dx = crop.left + (crop.width / 3) * i;
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), gridPaint);
      final dy = crop.top + (crop.height / 3) * i;
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.crop != crop;
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.25),
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _EditorToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: enabled
                  ? Colors.black.withOpacity(0.45)
                  : Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(enabled ? 0.12 : 0.06),
              ),
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white54,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
