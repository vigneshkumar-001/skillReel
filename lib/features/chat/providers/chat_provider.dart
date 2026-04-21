import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/chat_repository.dart';
import '../models/chat_model.dart';

final chatRepoProvider = Provider((_) => ChatRepository());

final threadsProvider = FutureProvider<List<ThreadModel>>((ref) {
  return ref.read(chatRepoProvider).getThreads();
});

final messagesProvider =
    FutureProvider.family<List<MessageModel>, String>((ref, threadId) {
  return ref.read(chatRepoProvider).getMessages(threadId);
});

final chatActionProvider = Provider((ref) => ChatActions(ref));

class ChatActions {
  final Ref _ref;
  ChatActions(this._ref);

  Future<void> sendMessage(String threadId, String text) =>
      _ref.read(chatRepoProvider).sendMessage(threadId, text);
}