import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../crashlytics_api_logger.dart';

final interactionsRepoProvider = Provider<InteractionsRepository>((_) {
  return InteractionsRepository(api: ApiClient.instance);
});

class InteractionsRepository {
  final ApiClient api;
  InteractionsRepository({required this.api});

  Future<Map<String, dynamic>> postInteraction({
    required String action,
    String? providerId,
    String? reelId,
    String? threadId,
    String? text,
    String? message,
    List<dynamic> attachments = const [],
    String surface = 'home',
    String? screen,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'providerId': providerId,
      'reelId': reelId,
      'threadId': threadId,
      'text': text,
      'message': message,
      'attachments': attachments,
      'surface': surface,
    };

    try {
      final res = await api.dio.post(
        ApiConstants.interactions,
        data: body,
        options: Options(extra: {'screen': screen ?? 'Interactions'}),
      );
      final root = res.data;
      if (root is Map) {
        return Map<String, dynamic>.from(root);
      }
      throw StateError('Unexpected interactions response: ${root.runtimeType}');
    } on DioException catch (e) {
      await CrashlyticsApiLogger.logDioError(
        e,
        screen: screen ?? 'Interactions',
      );
      rethrow;
    }
  }
}
