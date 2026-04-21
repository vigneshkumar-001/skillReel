import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../home/repositories/feed_repository.dart';
import '../models/reel_model.dart';
import '../../../core/services/location_service.dart';

class ReelsViewerState {
  final List<ReelModel> reels;
  final int page;
  final bool hasMore;
  final bool isLoadingMore;
  final String? nextCursor;

  final String feedType;
  final bool boostedOnly;

  const ReelsViewerState({
    required this.reels,
    required this.page,
    required this.hasMore,
    required this.isLoadingMore,
    required this.nextCursor,
    required this.feedType,
    required this.boostedOnly,
  });

  ReelsViewerState copyWith({
    List<ReelModel>? reels,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
    String? nextCursor,
    String? feedType,
    bool? boostedOnly,
  }) {
    return ReelsViewerState(
      reels: reels ?? this.reels,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      nextCursor: nextCursor ?? this.nextCursor,
      feedType: feedType ?? this.feedType,
      boostedOnly: boostedOnly ?? this.boostedOnly,
    );
  }
}

class ReelsFeedConfig {
  final String type; // home|trending|nearby|following
  final bool boostedOnly;

  const ReelsFeedConfig({
    required this.type,
    this.boostedOnly = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReelsFeedConfig &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          boostedOnly == other.boostedOnly;

  @override
  int get hashCode => Object.hash(type, boostedOnly);
}

class NearbyLocationRequiredException implements Exception {
  final LocationFailure failure;
  const NearbyLocationRequiredException(this.failure);

  @override
  String toString() {
    return switch (failure) {
      LocationFailure.serviceDisabled => 'Location services are disabled',
      LocationFailure.permissionDenied => 'Location permission denied',
      LocationFailure.permissionDeniedForever =>
        'Location permission permanently denied',
    };
  }
}

final reelsViewerRepoProvider = Provider((_) => FeedRepository());

final reelsViewerControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    ReelsViewerController, ReelsViewerState, ReelsFeedConfig>(
  ReelsViewerController.new,
);

class ReelsViewerController
    extends AutoDisposeFamilyAsyncNotifier<ReelsViewerState, ReelsFeedConfig> {
  static const _limit = 10;

  @override
  Future<ReelsViewerState> build(ReelsFeedConfig arg) async {
    final (latitude, longitude) = await _maybeLocation(arg.type);
    final feed = await ref.read(reelsViewerRepoProvider).getFeedPage(
          arg.type,
          page: 1,
          limit: _limit,
          latitude: latitude,
          longitude: longitude,
        );

    final reels = _applyFilters(feed.reels, boostedOnly: arg.boostedOnly);

    return ReelsViewerState(
      reels: reels,
      page: 1,
      hasMore: feed.hasMore,
      isLoadingMore: false,
      nextCursor: feed.nextCursor,
      feedType: arg.type,
      boostedOnly: arg.boostedOnly,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await build(arg));
  }

  Future<void> fetchNext() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.page + 1;
      final (latitude, longitude) = await _maybeLocation(current.feedType);
      final feed = await ref.read(reelsViewerRepoProvider).getFeedPage(
            current.feedType,
            cursor: current.nextCursor,
            page: nextPage,
            limit: _limit,
            latitude: latitude,
            longitude: longitude,
          );

      final incoming =
          _applyFilters(feed.reels, boostedOnly: current.boostedOnly);

      final seen =
          current.reels.map((r) => r.id).where((e) => e.isNotEmpty).toSet();
      final deduped =
          incoming.where((r) => r.id.isEmpty || !seen.contains(r.id)).toList();

      final newReels = [...current.reels, ...deduped];
      final hasMore = feed.hasMore;

      state = AsyncData(
        current.copyWith(
          reels: newReels,
          page: nextPage,
          hasMore: hasMore,
          isLoadingMore: false,
          nextCursor: feed.nextCursor,
        ),
      );
    } catch (_) {
      // Keep already-loaded reels; just stop "loading more" state.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  List<ReelModel> _applyFilters(
    List<ReelModel> reels, {
    required bool boostedOnly,
  }) {
    if (!boostedOnly) return reels;
    return reels.where((r) => r.isBoosted).toList(growable: false);
  }

  Future<(double?, double?)> _maybeLocation(String type) async {
    if (type != 'nearby') return (null, null);

    final res = await LocationService.instance.getCurrentPosition();
    if (!res.isSuccess) {
      throw NearbyLocationRequiredException(res.failure!);
    }
    final p = res.position!;
    return (p.latitude, p.longitude);
  }
}
