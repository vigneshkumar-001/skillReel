import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/chat_header.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String threadId;
  final ChatHeader? header;
  const ChatScreen({super.key, required this.threadId, this.header});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  String? _myId;
  final List<_LocalMessage> _localMessages = [];

  @override
  void initState() {
    super.initState();
    StorageService.instance.getUserId().then((id) {
      setState(() => _myId = id);
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    try {
      await ref.read(chatActionProvider).sendMessage(widget.threadId, text);
      ref.invalidate(messagesProvider(widget.threadId));
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localMessages.add(
          _LocalMessage(
            senderId: _myId ?? 'me',
            text: text,
            createdAt: DateTime.now(),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(messagesProvider(widget.threadId));
    final me = _myId ?? 'me';
    final title = widget.header?.title.trim().isNotEmpty == true
        ? widget.header!.title.trim()
        : 'Chat';
    final subtitle = widget.header?.subtitle?.trim();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ChatList(
                messages: [
                  ..._demoMessages(me: me),
                  ..._localMessages.map((m) => _ChatMessage(
                        senderId: m.senderId,
                        text: m.text,
                        createdAt: m.createdAt,
                      )),
                ],
                myId: me,
              ),
              data: (msgs) => _ChatList(
                messages: [
                  ...msgs.map(
                    (m) => _ChatMessage(
                      senderId: m.senderId,
                      text: m.text,
                      createdAt: m.createdAt,
                    ),
                  ),
                  ..._localMessages.map((m) => _ChatMessage(
                        senderId: m.senderId,
                        text: m.text,
                        createdAt: m.createdAt,
                      )),
                ],
                myId: me,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  final List<_ChatMessage> messages;
  final String myId;

  const _ChatList({required this.messages, required this.myId});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final isMe = msg.senderId == myId;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: isMe ? null : Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withAlpha(8),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isMe ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatMessage {
  final String senderId;
  final String text;
  final DateTime createdAt;

  const _ChatMessage({
    required this.senderId,
    required this.text,
    required this.createdAt,
  });
}

class _LocalMessage {
  final String senderId;
  final String text;
  final DateTime createdAt;

  const _LocalMessage({
    required this.senderId,
    required this.text,
    required this.createdAt,
  });
}

List<_ChatMessage> _demoMessages({required String me}) {
  const other = 'provider';
  final now = DateTime.now();
  return [
    _ChatMessage(
      senderId: other,
      text: 'Hello! What service do you need?',
      createdAt: now.subtract(const Duration(minutes: 8)),
    ),
    _ChatMessage(
      senderId: me,
      text: 'Bathroom leak issue. Today evening possible ah?',
      createdAt: now.subtract(const Duration(minutes: 6)),
    ),
    _ChatMessage(
      senderId: other,
      text: 'Yes, 6 PM available. Please share location.',
      createdAt: now.subtract(const Duration(minutes: 4)),
    ),
  ];
}
