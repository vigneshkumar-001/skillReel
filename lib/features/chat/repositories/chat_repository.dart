import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/chat_model.dart';

class ChatRepository {
  final _api = ApiClient.instance;

  Future<List<ThreadModel>> getThreads() async {
    final res = await _api.get(ApiConstants.threads);
    return (res.data['data'] as List)
        .map((t) => ThreadModel.fromJson(t))
        .toList();
  }

  Future<List<MessageModel>> getMessages(String threadId) async {
    final res = await _api.get('${ApiConstants.messages}/$threadId/messages');
    return (res.data['data'] as List)
        .map((m) => MessageModel.fromJson(m))
        .toList();
  }

  Future<void> sendMessage(String threadId, String text) =>
      _api.post('${ApiConstants.messages}/$threadId/messages',
          data: {'text': text});
}