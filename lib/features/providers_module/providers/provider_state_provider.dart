import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/provider_repository.dart';
import '../models/provider_model.dart';
import '../../../core/network/models/my_provider_photos_model.dart';
import '../../../core/network/models/my_provider_reels_model.dart';

final providerRepoProvider = Provider((_) => ProviderRepository());

final providerDetailProvider =
    FutureProvider.family<ProviderModel, String>((ref, id) {
  return ref.read(providerRepoProvider).getProviderById(id);
});

final providerPublicOverviewProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) {
  return ref.read(providerRepoProvider).getProviderOverviewJson(id);
});

class ProviderMediaState<T> {
  final List<T> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextCursor;
  final Object? error;

  const ProviderMediaState({
    this.items = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
  });

  ProviderMediaState<T> copyWith({
    List<T>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextCursor,
    Object? error,
  }) {
    return ProviderMediaState<T>(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      error: error,
    );
  }
}

class ProviderPublicReelsController
    extends StateNotifier<ProviderMediaState<MyProviderReelItem>> {
  final Ref _ref;
  final String providerId;

  ProviderPublicReelsController(this._ref, this.providerId)
      : super(const ProviderMediaState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final res = await _ref
          .read(providerRepoProvider)
          .getProviderReels(providerId: providerId, limit: 12);
      state = state.copyWith(
        items: res.data,
        isLoading: false,
        hasMore: res.meta.pageInfo.hasMore,
        nextCursor: res.meta.pageInfo.nextCursor,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null, items: const []);
    await _loadInitial();
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading) return;
    if (!state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null || cursor.trim().isEmpty) return;

    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final res = await _ref.read(providerRepoProvider).getProviderReels(
            providerId: providerId,
            cursor: cursor,
            limit: 12,
          );
      state = state.copyWith(
        items: [...state.items, ...res.data],
        isLoadingMore: false,
        hasMore: res.meta.pageInfo.hasMore,
        nextCursor: res.meta.pageInfo.nextCursor,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }
}

class ProviderPublicPhotosController
    extends StateNotifier<ProviderMediaState<MyProviderPhotoItem>> {
  final Ref _ref;
  final String providerId;

  ProviderPublicPhotosController(this._ref, this.providerId)
      : super(const ProviderMediaState()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final res = await _ref
          .read(providerRepoProvider)
          .getProviderPhotos(providerId: providerId, limit: 12);
      state = state.copyWith(
        items: res.data,
        isLoading: false,
        hasMore: res.meta.pageInfo.hasMore,
        nextCursor: res.meta.pageInfo.nextCursor,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null, items: const []);
    await _loadInitial();
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading) return;
    if (!state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null || cursor.trim().isEmpty) return;

    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final res = await _ref.read(providerRepoProvider).getProviderPhotos(
            providerId: providerId,
            cursor: cursor,
            limit: 12,
          );
      state = state.copyWith(
        items: [...state.items, ...res.data],
        isLoadingMore: false,
        hasMore: res.meta.pageInfo.hasMore,
        nextCursor: res.meta.pageInfo.nextCursor,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }
}

final providerPublicReelsControllerProvider = StateNotifierProvider.family<
    ProviderPublicReelsController,
    ProviderMediaState<MyProviderReelItem>,
    String>((ref, providerId) {
  return ProviderPublicReelsController(ref, providerId);
});

final providerPublicPhotosControllerProvider = StateNotifierProvider.family<
    ProviderPublicPhotosController,
    ProviderMediaState<MyProviderPhotoItem>,
    String>((ref, providerId) {
  return ProviderPublicPhotosController(ref, providerId);
});

final providerActionProvider = Provider((ref) => ProviderActions(ref));

class ProviderActions {
  final Ref _ref;
  ProviderActions(this._ref);

  Future<Map<String, dynamic>> getMyProviderProfileJson() =>
      _ref.read(providerRepoProvider).getMyProviderProfileJson();

  Future<ProviderModel> getMyProviderProfile() =>
      _ref.read(providerRepoProvider).getMyProviderProfile();

  Future<ProviderModel> updateMyProviderProfile(Map<String, dynamic> data) =>
      _ref.read(providerRepoProvider).updateMyProviderProfile(data);

  Future<void> follow(String providerId) =>
      _ref.read(providerRepoProvider).follow(providerId);

  Future<void> unfollow(String providerId) =>
      _ref.read(providerRepoProvider).unfollow(providerId);

  Future<ProviderModel> becomeProvider(Map<String, dynamic> data) =>
      _ref.read(providerRepoProvider).becomeProvider(data);
}
