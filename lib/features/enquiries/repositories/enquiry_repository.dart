import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../../crashlytics_api_logger.dart';

final enquiryRepoProvider = Provider((_) => EnquiryRepository());

class EnquiryRepository {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> createEnquiry({
    required String providerId,
    String? reelId,
    required String message,
    String? screen,
  }) async {
    final body = <String, dynamic>{
      'providerId': providerId,
      'message': message
    };
    final cleanReelId = (reelId ?? '').trim();
    if (cleanReelId.isNotEmpty) body['reelId'] = cleanReelId;

    try {
      final res = await _api.dio.post(
        ApiConstants.enquiries,
        data: body,
        options: _api.optionsWithExtra(
          extra: {'screen': screen ?? 'Enquiry'},
        ),
      );
      final root = res.data;
      if (root is Map) return Map<String, dynamic>.from(root);
      return <String, dynamic>{'success': true, 'data': root};
    } on DioException catch (e) {
      // Back-compat: older servers used `/enquiries` (non-social namespace).
      final is404 = e.response?.statusCode == 404;
      if (is404) {
        try {
          final res = await _api.dio.post(
            '/enquiries',
            data: body,
            options: _api.optionsWithExtra(
              extra: {'screen': screen ?? 'Enquiry'},
            ),
          );
          final root = res.data;
          if (root is Map) return Map<String, dynamic>.from(root);
          return <String, dynamic>{'success': true, 'data': root};
        } on DioException catch (e2) {
          await CrashlyticsApiLogger.logDioError(
            e2,
            screen: screen ?? 'Enquiry',
          );
          rethrow;
        }
      }

      await CrashlyticsApiLogger.logDioError(
        e,
        screen: screen ?? 'Enquiry',
      );
      rethrow;
    }
  }

  Future<List<dynamic>> getMyEnquiries() async {
    try {
      final res = await _api.get(ApiConstants.enquiries);
      final root = res.data;
      if (root is Map && root['data'] is List) return root['data'] as List;
      if (root is List) return root;
      return const <dynamic>[];
    } on DioException catch (e) {
      final is404 = e.response?.statusCode == 404;
      if (!is404) rethrow;
      final res = await _api.get('/enquiries');
      final root = res.data;
      if (root is Map && root['data'] is List) return root['data'] as List;
      if (root is List) return root;
      return const <dynamic>[];
    }
  }
}
