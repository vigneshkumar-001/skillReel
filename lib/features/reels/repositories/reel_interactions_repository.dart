import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../crashlytics_api_logger.dart';
import '../../interactions/repositories/interactions_repository.dart';

final reelInteractionsRepoProvider = Provider<ReelInteractionsRepository>((_) {
  return ReelInteractionsRepository(api: _.read(interactionsRepoProvider));
});

class ReelInteractionsRepository {
  final InteractionsRepository api;
  ReelInteractionsRepository({required this.api});

  Future<Map<String, dynamic>?> setLike(
    String reelId, {
    required bool liked,
    String surface = 'home',
  }) async {
    if (reelId.trim().isEmpty) return null;
    try {
      final root = await api.postInteraction(
        action: liked ? 'like' : 'unlike',
        reelId: reelId,
        surface: surface,
        screen: 'ReelsViewer',
      );
      return root['data'] is Map
          ? Map<String, dynamic>.from(root['data'])
          : null;
    } on DioException catch (e) {
      await CrashlyticsApiLogger.logDioError(
        e,
        screen: 'ReelsViewer',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> postComment(
    String reelId, {
    required String text,
    String surface = 'home',
  }) async {
    final t = text.trim();
    if (reelId.trim().isEmpty || t.isEmpty) return null;
    try {
      final root = await api.postInteraction(
        action: 'comment',
        reelId: reelId,
        text: t,
        surface: surface,
        screen: 'ReelsViewer',
      );
      return root['data'] is Map
          ? Map<String, dynamic>.from(root['data'])
          : null;
    } on DioException catch (e) {
      await CrashlyticsApiLogger.logDioError(
        e,
        screen: 'ReelsViewer',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> setFollow(
    String providerId, {
    required bool followed,
    String surface = 'home',
  }) async {
    if (providerId.trim().isEmpty) return null;
    try {
      final root = await api.postInteraction(
        action: followed ? 'follow' : 'unfollow',
        providerId: providerId,
        surface: surface,
        screen: 'ReelsViewer',
      );
      return root['data'] is Map
          ? Map<String, dynamic>.from(root['data'])
          : null;
    } on DioException catch (e) {
      await CrashlyticsApiLogger.logDioError(
        e,
        screen: 'ReelsViewer',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> setSave(
    String reelId, {
    required bool saved,
    String surface = 'home',
  }) async {
    if (reelId.trim().isEmpty) return null;
    try {
      final root = await api.postInteraction(
        action: saved ? 'save' : 'unsave',
        reelId: reelId,
        surface: surface,
        screen: 'ReelsViewer',
      );
      return root['data'] is Map
          ? Map<String, dynamic>.from(root['data'])
          : null;
    } on DioException catch (e) {
      await CrashlyticsApiLogger.logDioError(
        e,
        screen: 'ReelsViewer',
      );
      rethrow;
    }
  }
}
