import '../constants/api_constants.dart';
import 'api_client.dart';
import 'models/app_bootstrap_model.dart';

class BootstrapRepository {
  final ApiClient _api;

  BootstrapRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  Future<AppBootstrapResponse> fetchBootstrap() async {
    final res = await _api.get(ApiConstants.bootstrap);
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected bootstrap response: ${root.runtimeType}');
    }
    return AppBootstrapResponse.fromJson(Map<String, dynamic>.from(root));
  }
}
