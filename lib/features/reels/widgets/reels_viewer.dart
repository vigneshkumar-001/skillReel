import 'dart:ui';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../models/reel_model.dart';
import '../providers/reels_viewer_provider.dart';
import '../repositories/reel_interactions_repository.dart';
import '../services/reels_playback_prefs.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/socket_service.dart';
import '../../interactions/repositories/interactions_repository.dart';
import '../../chat/models/chat_header.dart';
import '../../skills/providers/skills_provider.dart';
import '../../../core/router/route_observer.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/url_utils.dart';

class ReelsViewer extends ConsumerStatefulWidget {
  final bool showUploadButton;
  final bool showNotificationsButton;
  final String feedType;
  final String? interactionSurface;
  final bool boostedOnly;
  final bool embed;
  final bool isActive;
  final String title;
  final bool showTopBar;
  final String? initialReelId;

  const ReelsViewer({
    super.key,
    this.showUploadButton = true,
    this.showNotificationsButton = false,
    this.feedType = 'trending',
    this.interactionSurface,
    this.boostedOnly = false,
    this.embed = false,
    this.isActive = true,
    this.title = 'Discovery',
    this.showTopBar = true,
    this.initialReelId,
  });

  @override
  ConsumerState<ReelsViewer> createState() => _ReelsViewerState();
}

class _ReelsViewerState extends ConsumerState<ReelsViewer>
    with WidgetsBindingObserver, RouteAware {
  static const bool _skipEnquiryApiForNow = true;
  final _pageController = PageController();
  final _videoCtrls = <int, VideoPlayerController>{};
  final Map<String, TextEditingController> _enquiryCtrls = {};
  final Map<String, FocusNode> _enquiryFocusNodes = {};
  final Set<String> _enquirySendingReelIds = {};
  int _index = 0;
  bool _muted = false;
  bool _pausedByTap = false;
  bool _scrolling = false;
  final Set<String> _likedReelIds = {};
  final Map<String, int> _likeOpTickByReelId = {};
  final Set<String> _savedReelIds = {};
  final Map<String, int> _saveOpTickByReelId = {};
  final Set<String> _followedProviderIds = {};
  final Map<String, int> _followOpTickByProviderId = {};
  final Map<String, List<String>> _commentsByReelId = {};
  final Map<String, _ReelStats> _statsByReelId = {};
  final Set<String> _seededFlagReelIds = {};
  String? _joinedReelId;
  String? _heartReelId;
  int _heartTick = 0;
  ProviderSubscription<AsyncValue<ReelsViewerState>>? _sub;
  bool _routeSubscribed = false;
  bool _didApplyInitial = false;
  int _initialSeekTries = 0;

  ReelsFeedConfig get _config =>
      ReelsFeedConfig(type: widget.feedType, boostedOnly: widget.boostedOnly);

  String get _surface => (widget.interactionSurface ?? widget.feedType).trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    unawaited(_initRealtime());

    _sub = ref.listenManual<AsyncValue<ReelsViewerState>>(
      reelsViewerControllerProvider(_config),
      (prev, next) {
        final data = next.valueOrNull;
        if (data == null) return;
        _seedFlagsFromApi(data.reels);
        _maybeLoadMore(data);
        _playIndex(_index, data.reels);
      },
    );
  }

  void _seedFlagsFromApi(List<ReelModel> reels) {
    var changed = false;
    for (final r in reels) {
      final id = r.id.trim();
      if (id.isEmpty) continue;
      if (_seededFlagReelIds.contains(id)) continue;
      _seededFlagReelIds.add(id);

      if (r.isLiked) {
        if (_likedReelIds.add(id)) changed = true;
      }
      if (r.isSaved) {
        if (_savedReelIds.add(id)) changed = true;
      }

      _statsByReelId.putIfAbsent(id, () => _ReelStats.fromReel(r));
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _loadPrefs() async {
    final muted = await ReelsPlaybackPrefs.getMuted();
    if (!mounted) return;
    setState(() => _muted = muted);
  }

  TextEditingController _enquiryCtrlFor(String reelId) {
    return _enquiryCtrls.putIfAbsent(reelId, () => TextEditingController());
  }

  FocusNode _enquiryFocusFor(String reelId) {
    return _enquiryFocusNodes.putIfAbsent(reelId, () => FocusNode());
  }

  double _bottomNavHeight(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    final hasBottomNav = scaffold?.widget.bottomNavigationBar != null;
    if (!hasBottomNav) return 0;
    return NavigationBarTheme.of(context).height ?? 80;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      routeObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didUpdateWidget(covariant ReelsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedType != widget.feedType ||
        oldWidget.boostedOnly != widget.boostedOnly) {
      _sub?.close();
      _sub = ref.listenManual<AsyncValue<ReelsViewerState>>(
        reelsViewerControllerProvider(_config),
        (prev, next) {
          final data = next.valueOrNull;
          if (data == null) return;
          setState(() {
            _index = 0;
            _pausedByTap = false;
          });
          _maybeLoadMore(data);
          _playIndex(0, data.reels);
        },
      );
    }

    if (oldWidget.isActive != widget.isActive) {
      if (!widget.isActive) {
        for (final c in _videoCtrls.values) {
          c.pause();
        }
      } else {
        final reels =
            ref.read(reelsViewerControllerProvider(_config)).valueOrNull?.reels;
        if (reels != null) {
          _playIndex(_index, reels);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _leaveReelRoom();
    SocketService.instance.off('feed:reel:stats', _onReelStats);
    SocketService.instance.off('interaction:comment:new', _onCommentNew);
    _sub?.close();
    for (final c in _enquiryCtrls.values) {
      c.dispose();
    }
    for (final n in _enquiryFocusNodes.values) {
      n.dispose();
    }
    _enquiryCtrls.clear();
    _enquiryFocusNodes.clear();
    for (final c in _videoCtrls.values) {
      c.dispose();
    }
    _videoCtrls.clear();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    for (final c in _videoCtrls.values) {
      c.pause();
    }
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    final reels =
        ref.read(reelsViewerControllerProvider(_config)).valueOrNull?.reels;
    if (reels != null) {
      _playIndex(_index, reels);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      for (final c in _videoCtrls.values) {
        c.pause();
      }
    }
  }

  Future<void> _ensureVideoController(int index, ReelModel reel) async {
    final isVideo = reel.mediaType.toLowerCase() == 'video';
    if (!isVideo) return;
    if (_videoCtrls.containsKey(index)) return;
    final url = reel.mediaUrl.isNotEmpty
        ? reel.mediaUrl
        : (reel.mediaUrls.isNotEmpty ? reel.mediaUrls.first : '');
    if (url.isEmpty) return;

    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return;
      }
      final ctrl = VideoPlayerController.networkUrl(uri);
      _videoCtrls[index] = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(_muted ? 0 : 1);

      if (!mounted) return;
      if (_index == index && widget.isActive && !_pausedByTap && !_scrolling) {
        await ctrl.play();
      }
      if (index == _index) {
        setState(() {});
      }
    } catch (_) {
      final c = _videoCtrls.remove(index);
      await c?.dispose();
    }
  }

  Future<void> _playIndex(int index, List<ReelModel> reels) async {
    if (index < 0 || index >= reels.length) return;

    for (final entry in _videoCtrls.entries) {
      if (entry.key != index) {
        await entry.value.pause();
      }
    }

    final reel = reels[index];
    await _joinReelRoom(reel.id);
    await _ensureVideoController(index, reel);
    final ctrl = _videoCtrls[index];
    if (ctrl != null &&
        ctrl.value.isInitialized &&
        widget.isActive &&
        !_pausedByTap &&
        !_scrolling) {
      await ctrl.play();
    }

    for (final nextIndex in [index + 1, index + 2]) {
      if (nextIndex >= reels.length) continue;
      final next = reels[nextIndex];
      Future.microtask(() async {
        await _ensureVideoController(nextIndex, next);
        await _precacheIfImage(next);
      });
    }

    final keep = <int>{index - 1, index, index + 1, index + 2};
    final toDispose = _videoCtrls.keys.where((k) => !keep.contains(k)).toList();
    for (final k in toDispose) {
      final c = _videoCtrls.remove(k);
      await c?.dispose();
    }
  }

  Future<void> _precacheIfImage(ReelModel reel) async {
    if (!mounted) return;
    if (reel.mediaType.toLowerCase() == 'video') return;

    final urls = reel.mediaUrls.isNotEmpty ? reel.mediaUrls : [reel.mediaUrl];
    final clean = urls.where((u) => u.trim().isNotEmpty).take(2).toList();
    for (final url in clean) {
      final uri = Uri.tryParse(url);
      if (uri == null) continue;
      await precacheImage(CachedNetworkImageProvider(uri.toString()), context);
    }
  }

  Future<void> _initRealtime() async {
    await SocketService.instance.ensureConnected();
    SocketService.instance.on('feed:reel:stats', _onReelStats);
    SocketService.instance.on('interaction:comment:new', _onCommentNew);
  }

  Future<void> _joinReelRoom(String reelId) async {
    final id = reelId.trim();
    if (id.isEmpty) return;
    if (_joinedReelId == id) return;

    await SocketService.instance.ensureConnected();
    if (_joinedReelId != null && _joinedReelId!.isNotEmpty) {
      SocketService.instance.interactionLeave(reelId: _joinedReelId);
    }
    _joinedReelId = id;
    SocketService.instance.interactionJoin(reelId: id);
  }

  void _leaveReelRoom() {
    final id = _joinedReelId;
    if (id == null || id.isEmpty) return;
    SocketService.instance.interactionLeave(reelId: id);
    _joinedReelId = null;
  }

  void _onReelStats(dynamic payload) {
    try {
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      final reelId = (map['reelId'] ?? '').toString();
      final statsRaw = map['stats'];
      if (reelId.isEmpty || statsRaw is! Map) return;

      final stats = Map<String, dynamic>.from(statsRaw);
      final next = _ReelStats(
        viewCount: _asInt(stats['viewCount']),
        likeCount: _asInt(stats['likeCount']),
        commentCount: _asInt(stats['commentCount']),
        saveCount: _asInt(stats['saveCount']),
      );

      if (!mounted) return;
      setState(() => _statsByReelId[reelId] = next);
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  void _onCommentNew(dynamic payload) {
    try {
      if (payload is! Map) return;
      final map = Map<String, dynamic>.from(payload);
      final reelId = (map['reelId'] ?? '').toString();
      if (reelId.isEmpty) return;
      if (!mounted) return;

      setState(() {
        final prev = _statsByReelId[reelId];
        if (prev != null) {
          _statsByReelId[reelId] = prev.copyWith(
            commentCount: (prev.commentCount + 1).clamp(0, 1 << 30),
          );
        }
      });
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  void _toggleFollow(String providerId) {
    final id = providerId.trim();
    if (id.isEmpty) return;
    final wasFollowed = _followedProviderIds.contains(id);
    setState(() {
      if (wasFollowed) {
        _followedProviderIds.remove(id);
      } else {
        _followedProviderIds.add(id);
      }
    });
    _syncFollow(id, followed: !wasFollowed);
  }

  Future<void> _syncFollow(String providerId, {required bool followed}) async {
    final tick = (_followOpTickByProviderId[providerId] ?? 0) + 1;
    _followOpTickByProviderId[providerId] = tick;

    try {
      await ref.read(reelInteractionsRepoProvider).setFollow(
            providerId,
            followed: followed,
            surface: _surface,
          );
    } catch (_) {
      if (!mounted) return;
      if (_followOpTickByProviderId[providerId] != tick) return;
      setState(() {
        if (followed) {
          _followedProviderIds.remove(providerId);
        } else {
          _followedProviderIds.add(providerId);
        }
      });
    }
  }

  void _bumpLikeCount(ReelModel reel, {required int delta}) {
    final id = reel.id.trim();
    if (id.isEmpty || delta == 0) return;
    final prev = _statsByReelId[id] ?? _ReelStats.fromReel(reel);
    _statsByReelId[id] = prev.copyWith(
      likeCount: (prev.likeCount + delta).clamp(0, 1 << 30),
    );
  }

  void _bumpCommentCount(ReelModel reel, {required int delta}) {
    final id = reel.id.trim();
    if (id.isEmpty || delta == 0) return;
    final prev = _statsByReelId[id] ?? _ReelStats.fromReel(reel);
    _statsByReelId[id] = prev.copyWith(
      commentCount: (prev.commentCount + delta).clamp(0, 1 << 30),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  void _maybeLoadMore(ReelsViewerState data) {
    if (!data.hasMore || data.isLoadingMore) return;
    if (_index >= data.reels.length - 3) {
      ref.read(reelsViewerControllerProvider(_config).notifier).fetchNext();
    }
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    setState(() => _muted = next);
    await ReelsPlaybackPrefs.setMuted(next);
    for (final c in _videoCtrls.values) {
      await c.setVolume(_muted ? 0 : 1);
    }
  }

  Future<void> _togglePlayPause(ReelModel reel) async {
    if (reel.mediaType.toLowerCase() != 'video') return;
    final ctrl = _videoCtrls[_index];
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (ctrl.value.isPlaying) {
      setState(() => _pausedByTap = true);
      await ctrl.pause();
    } else {
      setState(() => _pausedByTap = false);
      await ctrl.play();
    }
  }

  void _doubleTapLike(ReelModel reel) {
    final id = reel.id;
    if (id.isNotEmpty) {
      final wasLiked = _likedReelIds.contains(id);
      setState(() {
        _likedReelIds.add(id);
        if (!wasLiked) {
          _bumpLikeCount(reel, delta: 1);
        }
        _heartReelId = id;
        _heartTick++;
      });
      _syncLike(reel, liked: true);
    } else {
      setState(() {
        _heartReelId = id;
        _heartTick++;
      });
    }

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (_heartReelId == id) {
        setState(() => _heartReelId = null);
      }
    });
  }

  void _toggleLike(ReelModel reel) {
    final id = reel.id;
    if (id.isEmpty) return;
    final wasLiked = _likedReelIds.contains(id);
    setState(() {
      if (_likedReelIds.contains(id)) {
        _likedReelIds.remove(id);
        _bumpLikeCount(reel, delta: -1);
      } else {
        _likedReelIds.add(id);
        _bumpLikeCount(reel, delta: 1);
        _heartReelId = id;
        _heartTick++;
      }
    });
    _syncLike(reel, liked: !wasLiked);

    if (_heartReelId == id) {
      Future.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        if (_heartReelId == id) {
          setState(() => _heartReelId = null);
        }
      });
    }
  }

  Future<void> _syncLike(ReelModel reel, {required bool liked}) async {
    final id = reel.id;
    if (id.isEmpty) return;

    final tick = (_likeOpTickByReelId[id] ?? 0) + 1;
    _likeOpTickByReelId[id] = tick;

    try {
      await ref
          .read(reelInteractionsRepoProvider)
          .setLike(id, liked: liked, surface: _surface);
    } catch (_) {
      if (!mounted) return;
      if (_likeOpTickByReelId[id] != tick) return;
      setState(() {
        if (liked) {
          _likedReelIds.remove(id);
          _bumpLikeCount(reel, delta: -1);
        } else {
          _likedReelIds.add(id);
          _bumpLikeCount(reel, delta: 1);
        }
      });
    }
  }

  Future<void> _toggleSave(ReelModel reel) async {
    final id = reel.id;
    if (id.trim().isEmpty) return;

    final wasSaved = _savedReelIds.contains(id);
    final nextSaved = !wasSaved;

    setState(() {
      if (nextSaved) {
        _savedReelIds.add(id);
      } else {
        _savedReelIds.remove(id);
      }

      final prev = _statsByReelId[id] ?? _ReelStats.fromReel(reel);
      final delta = nextSaved ? 1 : -1;
      _statsByReelId[id] =
          prev.copyWith(saveCount: (prev.saveCount + delta).clamp(0, 1 << 30));
    });

    final tick = (_saveOpTickByReelId[id] ?? 0) + 1;
    _saveOpTickByReelId[id] = tick;

    try {
      await ref.read(reelInteractionsRepoProvider).setSave(
            id,
            saved: nextSaved,
            surface: _surface,
          );
    } catch (e) {
      if (!mounted) return;
      if (_saveOpTickByReelId[id] != tick) return;

      setState(() {
        if (wasSaved) {
          _savedReelIds.add(id);
        } else {
          _savedReelIds.remove(id);
        }

        final prev = _statsByReelId[id] ?? _ReelStats.fromReel(reel);
        final delta = wasSaved ? 1 : -1;
        _statsByReelId[id] = prev.copyWith(
          saveCount: (prev.saveCount + delta).clamp(0, 1 << 30),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    }
  }

  Future<void> _openComments(ReelModel reel) async {
    final id = reel.id;
    if (id.isEmpty) return;

    final input = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final list = _commentsByReelId[id] ?? const <String>[];
            final bottom = MediaQuery.of(context).viewInsets.bottom;

            Future<void> send() async {
              final text = input.text.trim();
              if (text.isEmpty) return;

              setState(() {
                _commentsByReelId[id] = [...list, text];
                _bumpCommentCount(reel, delta: 1);
              });
              input.clear();
              setModalState(() {});

              try {
                await ref
                    .read(reelInteractionsRepoProvider)
                    .postComment(id, text: text, surface: _surface);
              } catch (_) {
                if (!mounted || !context.mounted) return;
                setState(() {
                  final nextList =
                      List<String>.from(_commentsByReelId[id] ?? []);
                  if (nextList.isNotEmpty && nextList.last == text) {
                    nextList.removeLast();
                    _commentsByReelId[id] = nextList;
                  }
                  _bumpCommentCount(reel, delta: -1);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to send comment'),
                  ),
                );
              }
            }

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(bottom: bottom),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.60,
                decoration: const BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Comments',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(
                              child: Text(
                                'No comments yet',
                                style: TextStyle(color: Colors.white70),
                              ),
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.10),
                                    ),
                                  ),
                                  child: Text(
                                    list[i],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      height: 1.2,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: input,
                                onSubmitted: (_) => send(),
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Add a comment…',
                                  hintStyle:
                                      const TextStyle(color: Colors.white54),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.06),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: Colors.white.withOpacity(0.10),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: Colors.white.withOpacity(0.10),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: Colors.white.withOpacity(0.18),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 50,
                              child: FilledButton(
                                onPressed: send,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C5CE7),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Send',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    input.dispose();
  }

  Future<void> _shareReel(ReelModel reel) async {
    final url = reel.mediaUrl.isNotEmpty
        ? reel.mediaUrl
        : (reel.mediaUrls.isNotEmpty ? reel.mediaUrls.first : '');
    final text = url.isNotEmpty ? '${reel.title}\n$url' : reel.title;
    await Share.share(text);
  }

  Future<void> _sendEnquiry(ReelModel reel) async {
    if (reel.id.isEmpty || reel.providerId.isEmpty) return;

    final ctrl = _enquiryCtrlFor(reel.id);
    final msg = ctrl.text.trim();
    if (msg.isEmpty) return;
    if (_enquirySendingReelIds.contains(reel.id)) return;

    if (_skipEnquiryApiForNow) {
      ctrl.clear();
      _enquiryFocusFor(reel.id).unfocus();

      final title = _firstNonEmpty([reel.providerName, 'Chat']).trim();
      if (!mounted) return;
      context.push(
        '/chat/local_${reel.providerId}_${reel.id}',
        extra: ChatHeader(
          title: title,
          subtitle: null,
          avatarUrl: reel.providerAvatar,
        ),
      );
      return;
    }

    setState(() => _enquirySendingReelIds.add(reel.id));
    try {
      final root = await ref.read(interactionsRepoProvider).postInteraction(
            action: 'enquiry',
            providerId: reel.providerId,
            reelId: reel.id,
            message: msg,
            surface: _surface,
            screen: 'ReelsViewer',
          );

      final dataObj = root['data'];
      final data = dataObj is Map
          ? Map<String, dynamic>.from(dataObj)
          : const <String, dynamic>{};
      final threadId = _firstNonEmpty([
        (data['threadId'] ?? '').toString(),
        _mapGetString(data['thread'], '_id'),
        _mapGetString(data['thread'], 'id'),
      ]);

      if (threadId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enquiry sent, but thread not found')),
        );
        return;
      }

      ctrl.clear();
      _enquiryFocusFor(reel.id).unfocus();

      final title = _firstNonEmpty([reel.providerName, 'Chat']).trim();
      final phone = _pickPhone(data);

      if (!mounted) return;
      context.push(
        '/chat/$threadId',
        extra: ChatHeader(
          title: title,
          subtitle: phone,
          avatarUrl: reel.providerAvatar,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _enquirySendingReelIds.remove(reel.id));
      }
    }
  }

  String _mapGetString(Object? obj, String key) {
    if (obj is! Map) return '';
    final v = obj[key];
    if (v == null) return '';
    return v.toString().trim();
  }

  String _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  String? _pickPhone(Map<String, dynamic> data) {
    // Best-effort: backend payloads vary across environments.
    String? read(Map? m, String key) {
      final v = m?[key];
      final t = v?.toString().trim();
      return (t != null && t.isNotEmpty) ? t : null;
    }

    Map<String, dynamic>? asMap(Object? o) =>
        o is Map ? Map<String, dynamic>.from(o) : null;

    final thread = asMap(data['thread']);
    final enquiry = asMap(data['enquiry']);
    final provider = asMap(data['provider']);
    final userId = asMap(data['userId']);

    final threadUser =
        asMap(thread?['userId']) ?? asMap(thread?['providerUserId']);
    final enquiryUser =
        asMap(enquiry?['userId']) ?? asMap(enquiry?['providerUserId']);

    return read(threadUser, 'mobile') ??
        read(threadUser, 'phone') ??
        read(enquiryUser, 'mobile') ??
        read(enquiryUser, 'phone') ??
        read(userId, 'mobile') ??
        read(userId, 'phone') ??
        read(provider, 'mobile') ??
        read(provider, 'phone');
  }

  @override
  Widget build(BuildContext context) {
    final reelsAsync = ref.watch(reelsViewerControllerProvider(_config));
    final skillsAsync = ref.watch(skillsProvider);
    final skillNameById = <String, String>{
      for (final s in skillsAsync.valueOrNull ?? const []) s.id: s.name,
    };
    String resolveSkillTag(String raw) => skillNameById[raw] ?? raw;

    final body = reelsAsync.when(
      loading: () => const Center(
        child: CupertinoActivityIndicator(radius: 14),
      ),
      error: (e, _) {
        if (e is NearbyLocationRequiredException) {
          final title = switch (e.failure) {
            LocationFailure.serviceDisabled => 'Turn on location',
            LocationFailure.permissionDenied => 'Allow location permission',
            LocationFailure.permissionDeniedForever =>
              'Enable location permission',
          };
          final subtitle = switch (e.failure) {
            LocationFailure.serviceDisabled =>
              'Nearby ads need location services.',
            LocationFailure.permissionDenied =>
              'Nearby ads need location access.',
            LocationFailure.permissionDeniedForever =>
              'Open settings and enable location permission for SkilReel.',
          };

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.2),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => ref.invalidate(
                          reelsViewerControllerProvider(_config),
                        ),
                        child: const Text('Retry'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          if (e.failure == LocationFailure.serviceDisabled) {
                            await LocationService.instance
                                .openLocationSettings();
                          } else {
                            await LocationService.instance.openAppSettings();
                          }
                        },
                        child: const Text('Open settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => ref.invalidate(
                    reelsViewerControllerProvider(_config),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
      data: (data) {
        final reels = data.reels;
        if (reels.isEmpty) {
          return const Center(
            child: Text('No reels', style: TextStyle(color: Colors.white)),
          );
        }

        if (!_didApplyInitial &&
            widget.initialReelId != null &&
            widget.initialReelId!.trim().isNotEmpty) {
          final initialId = widget.initialReelId!.trim();
          final idx = reels.indexWhere((r) => r.id == initialId);
          if (idx >= 0) {
            _didApplyInitial = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (!_pageController.hasClients) return;
              _pageController.jumpToPage(idx);
              setState(() => _index = idx);
              _playIndex(idx, reels);
            });
          } else if (data.hasMore &&
              !data.isLoadingMore &&
              _initialSeekTries < 6) {
            _initialSeekTries++;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(reelsViewerControllerProvider(_config).notifier)
                  .fetchNext();
            });
          } else {
            _didApplyInitial = true;
          }
        } else if (!_didApplyInitial) {
          _didApplyInitial = true;
        }

        final isMyProviderFeed = widget.feedType == 'my_provider';
        final isSavedFeed = widget.feedType == 'saved';
        final showProviderHeader = !(isMyProviderFeed || isSavedFeed);
        final showEnquiryComposer = !(isMyProviderFeed || isSavedFeed);

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification) {
                  if (!_scrolling) {
                    setState(() => _scrolling = true);
                    for (final c in _videoCtrls.values) {
                      c.pause();
                    }
                  }
                } else if (n is ScrollEndNotification) {
                  if (_scrolling) {
                    setState(() => _scrolling = false);
                    _playIndex(_index, reels);
                  }
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                allowImplicitScrolling: false,
                physics: _SnappyPageScrollPhysics(
                  threshold: 0.06,
                  parent: (Theme.of(context).platform == TargetPlatform.iOS ||
                          Theme.of(context).platform == TargetPlatform.macOS)
                      ? const BouncingScrollPhysics()
                      : const ClampingScrollPhysics(),
                ),
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                    _pausedByTap = false;
                  });
                  final d = ref
                      .read(reelsViewerControllerProvider(_config))
                      .valueOrNull;
                  if (d != null) {
                    _maybeLoadMore(d);
                    _playIndex(_index, d.reels);
                  }
                },
                itemCount: reels.length,
                itemBuilder: (context, i) {
                  final reel = reels[i];
                  final isLiked =
                      reel.id.isNotEmpty && _likedReelIds.contains(reel.id);
                  final isSaved =
                      reel.id.isNotEmpty && _savedReelIds.contains(reel.id);
                  final isFollowed = reel.providerId.isNotEmpty &&
                      _followedProviderIds.contains(reel.providerId);
                  final stats =
                      reel.id.isNotEmpty ? _statsByReelId[reel.id] : null;
                  final likeCount = stats?.likeCount ?? reel.likes;
                  final localComments = reel.id.isNotEmpty
                      ? (_commentsByReelId[reel.id]?.length ?? 0)
                      : 0;
                  final commentCount =
                      stats?.commentCount ?? (reel.comments + localComments);
                  final bottomNavHeight = _bottomNavHeight(context);
                  return _ReelPage(
                    reel: reel,
                    video: _videoCtrls[i],
                    muted: _muted,
                    isLiked: isLiked,
                    isSaved: isSaved,
                    isFollowed: isFollowed,
                    likeCount: likeCount,
                    commentCount: commentCount,
                    showHeart: reel.id == _heartReelId,
                    heartTick: _heartTick,
                    paused: i == _index &&
                        reel.mediaType.toLowerCase() == 'video' &&
                        _pausedByTap &&
                        (_videoCtrls[i]?.value.isInitialized ?? false) &&
                        !(_videoCtrls[i]?.value.isPlaying ?? true),
                    bottomNavHeight: bottomNavHeight,
                    enquirySending: _enquirySendingReelIds.contains(reel.id),
                    enquiryController: _enquiryCtrlFor(reel.id),
                    enquiryFocusNode: _enquiryFocusFor(reel.id),
                    onMediaTap: () => _togglePlayPause(reel),
                    onMediaDoubleTap: () => _doubleTapLike(reel),
                    onMuteTap: _toggleMute,
                    onLikeTap: () => _toggleLike(reel),
                    onCommentTap: () => _openComments(reel),
                    onSaveTap: () {
                      if (reel.id.isEmpty) return;
                      HapticFeedback.selectionClick();
                      _toggleSave(reel);
                    },
                    onShareTap: () => _shareReel(reel),
                    onProviderTap: () {
                      final providerId = reel.providerId;
                      if (providerId.isEmpty) return;
                      context.push('/provider/$providerId');
                    },
                    onFollowTap: () {
                      if (reel.providerId.isEmpty) return;
                      _toggleFollow(reel.providerId);
                    },
                    onEnquirySend: () => _sendEnquiry(reel),
                    resolveSkillTag: resolveSkillTag,
                    showProviderHeader: showProviderHeader,
                    showEnquiryComposer: showEnquiryComposer,
                  );
                },
              ),
            ),
            if (widget.showUploadButton)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: IconButton(
                  onPressed: () => context.push('/reel/upload'),
                  icon:
                      const Icon(Icons.add_circle_outline, color: Colors.white),
                ),
              ),
            if (widget.showNotificationsButton)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  onPressed: () => context.push('/notifications'),
                  icon: const Icon(Icons.notifications_outlined,
                      color: Colors.white),
                ),
              ),
            if (data.isLoadingMore)
              const Positioned(
                bottom: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CupertinoActivityIndicator(radius: 11),
                  ),
                ),
              ),
          ],
        );
      },
    );

    final content = Stack(
      children: [
        Positioned.fill(child: body),
        if (widget.showTopBar)
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 8,
            child: _DiscoveryTopBar(
              title: widget.title,
              onSearch: () => context.push('/search'),
              onMenu: () => _openFeedMenu(context),
            ),
          ),
      ],
    );

    if (widget.embed) return ColoredBox(color: Colors.black, child: content);

    return Scaffold(backgroundColor: Colors.black, body: content);
  }
}

Future<void> _openFeedMenu(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Options',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh feed'),
              onTap: () {
                Navigator.of(ctx).pop();
                messenger?.showSnackBar(
                  const SnackBar(content: Text('Pull down to refresh')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.push('/notifications');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _DiscoveryTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onSearch;
  final VoidCallback onMenu;

  const _DiscoveryTopBar({
    required this.title,
    required this.onSearch,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 34),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.search, color: Colors.white),
            ),
            IconButton(
              onPressed: onMenu,
              icon: const Icon(Icons.more_vert, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReelPage extends StatelessWidget {
  final ReelModel reel;
  final VideoPlayerController? video;
  final bool muted;
  final bool isLiked;
  final bool isSaved;
  final bool isFollowed;
  final int likeCount;
  final int commentCount;
  final bool showHeart;
  final int heartTick;
  final bool paused;
  final double bottomNavHeight;
  final bool enquirySending;
  final TextEditingController enquiryController;
  final FocusNode enquiryFocusNode;
  final VoidCallback onMediaTap;
  final VoidCallback onMediaDoubleTap;
  final VoidCallback onMuteTap;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback onSaveTap;
  final VoidCallback onShareTap;
  final VoidCallback onFollowTap;
  final VoidCallback onEnquirySend;
  final VoidCallback onProviderTap;
  final String Function(String) resolveSkillTag;
  final bool showProviderHeader;
  final bool showEnquiryComposer;

  const _ReelPage({
    required this.reel,
    required this.video,
    required this.muted,
    required this.isLiked,
    required this.isSaved,
    required this.isFollowed,
    required this.likeCount,
    required this.commentCount,
    required this.showHeart,
    required this.heartTick,
    required this.paused,
    required this.bottomNavHeight,
    required this.enquirySending,
    required this.enquiryController,
    required this.enquiryFocusNode,
    required this.onMediaTap,
    required this.onMediaDoubleTap,
    required this.onMuteTap,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onSaveTap,
    required this.onShareTap,
    required this.onFollowTap,
    required this.onEnquirySend,
    required this.onProviderTap,
    required this.resolveSkillTag,
    required this.showProviderHeader,
    required this.showEnquiryComposer,
  });

  @override
  Widget build(BuildContext context) {
    final location = [
      if ((reel.providerCity ?? '').trim().isNotEmpty)
        reel.providerCity!.trim(),
      if ((reel.providerState ?? '').trim().isNotEmpty)
        reel.providerState!.trim(),
    ].join(', ').trim();

    final isVideo = reel.mediaType.toLowerCase() == 'video';
    final priceLabel =
        (isVideo && reel.price != null) ? '₹${reel.price}' : null;
    final tagLabels =
        reel.skillTags.map(resolveSkillTag).toList(growable: false);

    const titleStyle = TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.w900,
      height: 1.08,
      letterSpacing: -0.2,
      shadows: [
        Shadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6)),
      ],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMediaTap,
            onDoubleTap: onMediaDoubleTap,
            child: _ReelMedia(reel: reel, video: video),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.10),
                    Colors.transparent,
                    Colors.black.withOpacity(0.55),
                  ],
                  stops: const [0, 0.60, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 220,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.00),
                  ],
                  stops: const [0, 1],
                ),
              ),
            ),
          ),
        ),
        if (paused)
          const Center(
            child:
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 96),
          ),
        if (showHeart)
          Center(
            child: _BigHeart(key: ValueKey('heart-$heartTick')),
          ),
        if (showProviderHeader)
          Positioned(
            top: MediaQuery.of(context).padding.top + 18,
            left: 12,
            right: 12,
            child: _ProviderHeader(
              name: reel.providerName ?? 'Provider',
              avatarUrl: reel.providerAvatar,
              verified: reel.providerIsVerified == true,
              isFollowed: isFollowed,
              heroTag:
                  'reel_provider_avatar_${reel.providerId}_${reel.id.isNotEmpty ? reel.id : 'profile'}',
              onProviderTap: onProviderTap,
              onFollowTap: onFollowTap,
            ),
          ),
        Positioned(
          right: 12,
          bottom: bottomNavHeight + 120,
          child: Column(
            children: [
              _SideButton(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                label: _formatCount(likeCount),
                onTap: onLikeTap,
                iconColor: isLiked ? const Color(0xFFFF4D67) : Colors.white,
              ),
              const SizedBox(height: 10),
              _SideButton(
                icon: Icons.mode_comment_outlined,
                label: _formatCount(commentCount),
                onTap: onCommentTap,
              ),
              const SizedBox(height: 10),
              _SideButton(
                icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                label: '',
                onTap: onSaveTap,
              ),
              const SizedBox(height: 10),
              _SideButton(
                icon: muted ? Icons.volume_off : Icons.volume_up,
                label: '',
                onTap: onMuteTap,
              ),
              const SizedBox(height: 10),
              _SideButton(
                icon: Icons.share_outlined,
                label: '',
                onTap: onShareTap,
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 96,
          bottom: bottomNavHeight + 66,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (priceLabel != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Text(
                      '$priceLabel${reel.isBoosted ? '/unit' : ''}',
                      style: const TextStyle(
                        color: Color(0xFFFF4D67),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  reel.title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((reel.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _ExpandableText(
                    text: reel.description!.trim(),
                    trimLines: 1,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.20,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        )
                      ],
                    ),
                    actionStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        )
                      ],
                    ),
                  ),
                ],
                if (tagLabels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tagLabels
                        .where((t) => t.trim().isNotEmpty)
                        .take(2)
                        .map((t) => _ChipLabel(text: t))
                        .toList(),
                  ),
                ],
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    location,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        )
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showEnquiryComposer)
          Positioned(
            left: 12,
            right: 96,
            bottom: bottomNavHeight + 12,
            child: SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: _EnquiryComposer(
                  controller: enquiryController,
                  focusNode: enquiryFocusNode,
                  loading: enquirySending,
                  onSend: onEnquirySend,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000.0;
    final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '${s}k';
  }
  final v = n / 1000000.0;
  final s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s}M';
}

class _EnquiryComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onSend;

  const _EnquiryComposer({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSend,
  });

  @override
  State<_EnquiryComposer> createState() => _EnquiryComposerState();
}

class _EnquiryComposerState extends State<_EnquiryComposer> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _EnquiryComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final hasFocus = widget.focusNode.hasFocus;
    if (hasFocus) {
      setState(() => _expanded = true);
      return;
    }

    if (widget.controller.text.trim().isEmpty) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const radius = 999.0;
    final canSend = !widget.loading && widget.controller.text.trim().isNotEmpty;
    const base = Color(0xFF0B1220);
    final glassA =
        Color.alphaBlend(AppColors.accent.withAlpha(36), base.withAlpha(210));
    final glassB = Color.alphaBlend(
      AppColors.secondary.withAlpha(18),
      base.withAlpha(235),
    );

    Widget inputChild() {
      if (!_expanded) {
        return InkWell(
          onTap: () {
            widget.focusNode.requestFocus();
            setState(() => _expanded = true);
          },
          borderRadius: BorderRadius.circular(radius),
          child: const Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: Colors.white70,
              ),
              SizedBox(width: 10),
              Text(
                'Enquiry',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }

      return Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: Colors.white,
            selectionColor: Colors.white.withOpacity(0.22),
            selectionHandleColor: Colors.white.withOpacity(0.85),
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          cursorColor: Colors.white,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => widget.onSend(),
          minLines: 1,
          maxLines: 1,
          textAlignVertical: TextAlignVertical.center,
          decoration: const InputDecoration.collapsed(
            hintText: 'Send enquiry…',
            hintStyle: TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 52,
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      glassA,
                      glassB,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white.withAlpha(26)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(85),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius),
                            gradient: LinearGradient(
                              begin: const Alignment(-1, -1),
                              end: const Alignment(1, 1),
                              colors: [
                                Colors.white.withAlpha(18),
                                Colors.transparent,
                                Colors.black.withAlpha(18),
                              ],
                              stops: const [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeOut,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.02, 0),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Align(
                        key: ValueKey(_expanded),
                        alignment: Alignment.centerLeft,
                        child: inputChild(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canSend ? widget.onSend : null,
                borderRadius: BorderRadius.circular(999),
                splashColor: Colors.white.withAlpha(18),
                highlightColor: Colors.white.withAlpha(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(
                          canSend
                              ? AppColors.accent.withAlpha(96)
                              : Colors.white.withAlpha(16),
                          const Color(0xFF0B1220).withAlpha(215),
                        ),
                        const Color(0xFF0B1220).withAlpha(240),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(canSend ? 0.16 : 0.22),
                    ),
                    boxShadow: [
                      if (canSend)
                        BoxShadow(
                          color: AppColors.accent.withAlpha(120),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      BoxShadow(
                        color: Colors.black.withAlpha(85),
                        blurRadius: 18,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Center(
                    child: widget.loading
                        ? const CupertinoActivityIndicator(radius: 10)
                        : const Icon(
                            Icons.send_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool verified;
  final bool isFollowed;
  final String heroTag;
  final VoidCallback onProviderTap;
  final VoidCallback onFollowTap;

  const _ProviderHeader({
    required this.name,
    required this.avatarUrl,
    required this.verified,
    required this.isFollowed,
    required this.heroTag,
    required this.onProviderTap,
    required this.onFollowTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            InkWell(
              onTap: onProviderTap,
              borderRadius: BorderRadius.circular(999),
              child: Hero(
                tag: heroTag,
                child: _Avatar(url: avatarUrl),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onProviderTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                )
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 16,
                            color: Color(0xFF64B5F6),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'PROVIDER',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: onFollowTap,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isFollowed ? Colors.white10 : const Color(0xFF5E60CE),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  isFollowed ? 'Following' : 'Follow',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isFollowed ? Colors.white70 : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  const _Avatar({required this.url});

  @override
  Widget build(BuildContext context) {
    final u = UrlUtils.normalizeMediaUrl(url);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.12),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: ClipOval(
        child: u.isEmpty
            ? const Icon(Icons.person, color: Colors.white70, size: 20)
            : CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.cover,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => const Icon(
                  Icons.person,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  final String text;
  const _ChipLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          shadows: [
            Shadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 3),
            )
          ],
        ),
      ),
    );
  }
}

class _ReelMedia extends StatelessWidget {
  final ReelModel reel;
  final VideoPlayerController? video;
  const _ReelMedia({required this.reel, required this.video});

  @override
  Widget build(BuildContext context) {
    final isVideo = reel.mediaType.toLowerCase() == 'video';
    if (isVideo) {
      final v = video;
      if (v == null || !v.value.isInitialized) {
        return const Center(
          child: CupertinoActivityIndicator(radius: 14),
        );
      }

      final size = v.value.size;
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(v),
        ),
      );
    }

    final urls = reel.mediaUrls.isNotEmpty ? reel.mediaUrls : [reel.mediaUrl];
    final clean = urls.where((u) => u.trim().isNotEmpty).toList();
    if (clean.length <= 1) {
      final url = clean.isNotEmpty ? clean.first : '';
      return _ImageCover(url: url);
    }

    return _ImageCarousel(urls: clean);
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final int trimLines;
  final TextStyle style;
  final TextStyle actionStyle;

  const _ExpandableText({
    required this.text,
    required this.trimLines,
    required this.style,
    required this.actionStyle,
  });

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle(bool canToggle) {
    if (!canToggle) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    // Avoid LayoutBuilder/TextPainter overflow checks here. Hot reload can
    // trigger a debug assertion in LayoutBuilder's layout callback.
    final canToggle =
        text.length > 120 || text.split(RegExp(r'\\s+')).length > 22;
    final showAction = canToggle || _expanded;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => _toggle(canToggle),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: widget.style,
              maxLines: _expanded ? null : widget.trimLines,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (showAction) ...[
              const SizedBox(height: 4),
              Text(
                _expanded ? 'less' : 'more',
                style: widget.actionStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageCover extends StatelessWidget {
  final String url;
  const _ImageCover({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, color: Colors.white54, size: 42),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => Shimmer.fromColors(
        baseColor: Colors.white10,
        highlightColor: Colors.white24,
        child: Container(color: Colors.white10),
      ),
      errorWidget: (_, __, ___) => const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 42),
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<String> urls;
  const _ImageCarousel({required this.urls});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final _ctrl = PageController();
  int _i = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.urls.length,
          allowImplicitScrolling: true,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => _ImageCover(url: widget.urls[i]),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_i + 1}/${widget.urls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SideButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  State<_SideButton> createState() => _SideButtonState();
}

class _SideButtonState extends State<_SideButton> {
  double _scale = 1.0;

  void _bump() {
    if (!mounted) return;
    setState(() => _scale = 1.12);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() => _scale = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showLabel = widget.label.trim().isNotEmpty;
    final tint = widget.iconColor ?? Colors.white;
    const base = Color(0xFF0B1220);
    final glassA = Color.alphaBlend(tint.withAlpha(46), base.withAlpha(210));
    final glassB = base.withAlpha(235);
    return Column(
      children: [
        AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutBack,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _bump();
                    widget.onTap();
                  },
                  splashColor: Colors.white.withAlpha(18),
                  highlightColor: Colors.white.withAlpha(8),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          glassA,
                          glassB,
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withAlpha(22),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: LinearGradient(
                                  begin: const Alignment(-1, -1),
                                  end: const Alignment(1, 1),
                                  colors: [
                                    tint.withAlpha(24),
                                    Colors.transparent,
                                    Colors.black.withAlpha(18),
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor ?? Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class _BigHeart extends StatefulWidget {
  const _BigHeart({super.key});

  @override
  State<_BigHeart> createState() => _BigHeartState();
}

class _BigHeartState extends State<_BigHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  late final Animation<double> _scale = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
  );

  late final Animation<double> _fade = Tween<double>(begin: 0.0, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            colors: [Color(0xFFFF4D67), Color(0xFFB76DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: const Icon(Icons.favorite, size: 120, color: Colors.white),
        ),
      ),
    );
  }
}

class _SnappyPageScrollPhysics extends PageScrollPhysics {
  final double threshold;

  const _SnappyPageScrollPhysics({
    required this.threshold,
    super.parent,
  }) : assert(threshold > 0 && threshold < 0.5);

  @override
  _SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SnappyPageScrollPhysics(
      threshold: threshold,
      parent: buildParent(ancestor),
    );
  }

  double _getPageValue(ScrollMetrics position) {
    if (position is PageMetrics) {
      return position.page ?? (position.pixels / position.viewportDimension);
    }
    return position.pixels / position.viewportDimension;
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final parentSim = super.createBallisticSimulation(position, velocity);
    if (position.outOfRange) return parentSim;
    if (position is! PageMetrics) return parentSim;

    final tol = toleranceFor(position);
    final page = _getPageValue(position);
    final current = page.roundToDouble();

    double targetPage = current;
    if (velocity.abs() > tol.velocity) {
      targetPage = velocity > 0 ? current + 1 : current - 1;
    } else {
      final delta = page - current;
      if (delta.abs() >= threshold) {
        targetPage = current + delta.sign;
      }
    }

    final minPage = (position.minScrollExtent / position.viewportDimension)
        .clamp(double.negativeInfinity, double.infinity);
    final maxPage = (position.maxScrollExtent / position.viewportDimension)
        .clamp(double.negativeInfinity, double.infinity);
    targetPage = targetPage.clamp(minPage, maxPage).toDouble();
    final targetPixels = targetPage * position.viewportDimension;

    if ((targetPixels - position.pixels).abs() < 0.5) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels,
      velocity,
      tolerance: tol,
    );
  }
}

class _ReelStats {
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int saveCount;

  const _ReelStats({
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.saveCount,
  });

  factory _ReelStats.fromReel(ReelModel reel) {
    return _ReelStats(
      viewCount: reel.viewCount,
      likeCount: reel.likes,
      commentCount: reel.comments,
      saveCount: reel.saves,
    );
  }

  _ReelStats copyWith({
    int? viewCount,
    int? likeCount,
    int? commentCount,
    int? saveCount,
  }) {
    return _ReelStats(
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      saveCount: saveCount ?? this.saveCount,
    );
  }
}
