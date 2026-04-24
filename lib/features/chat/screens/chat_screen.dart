import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/chat_header.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/url_utils.dart';
import '../models/chat_model.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String threadId;
  final ChatHeader? header;
  const ChatScreen({super.key, required this.threadId, this.header});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  String? _myId;
  final List<_LocalMessage> _localMessages = [];
  final Map<String, MessageModel> _incomingById = {};
  bool _joined = false;
  bool _otherTyping = false;
  Timer? _typingTimer;

  bool get _isDraftThread => widget.threadId.startsWith('draft_provider_');

  @override
  void initState() {
    super.initState();
    StorageService.instance.getUserId().then((id) {
      if (!mounted) return;
      setState(() => _myId = id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Socket is best-effort: chat screen should not crash if socket fails.
        await SocketService.instance.ensureConnected();
      } catch (_) {
        // Ignore; REST still works and draft threads are read-only anyway.
      }
      if (!mounted) return;
      SocketService.instance.on('chat:message', _onSocketMessage);
      SocketService.instance.on('chat:typing', _onSocketTyping);
      SocketService.instance.on('chat:error', _onSocketError);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    if (_joined) {
      SocketService.instance.emit('thread:leave', {'threadId': widget.threadId});
    }
    SocketService.instance.off('chat:message', _onSocketMessage);
    SocketService.instance.off('chat:typing', _onSocketTyping);
    SocketService.instance.off('chat:error', _onSocketError);
    super.dispose();
  }

  void _onSocketError(dynamic data) {
    if (!mounted) return;
    final msg = data is Map
        ? (data['message'] ?? data['error'] ?? '').toString()
        : data?.toString();
    if ((msg ?? '').trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg!)));
  }

  void _onSocketTyping(dynamic data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final threadId = (map['threadId'] ?? '').toString().trim();
    if (threadId != widget.threadId) return;
    final userId = (map['userId'] ?? '').toString().trim();
    final isTyping = map['isTyping'] == true;
    final me = (_myId ?? 'me').trim();
    if (userId.isEmpty || userId == me) return;
    if (!mounted) return;
    setState(() => _otherTyping = isTyping);
  }

  void _onSocketMessage(dynamic data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final threadId = (map['threadId'] ?? '').toString().trim();
    if (threadId != widget.threadId) return;
    final msgObj = map['message'];
    if (msgObj is! Map) return;
    final msg = MessageModel.fromJson(Map<String, dynamic>.from(msgObj));
    if (!mounted) return;
    setState(() => _incomingById[msg.id] = msg);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _joinIfNeeded() async {
    if (_isDraftThread) return;
    if (_joined) return;
    try {
      await SocketService.instance.ensureConnected();
      await SocketService.instance.emitWithAck(
        'thread:join',
        {'threadId': widget.threadId, 'markRead': true},
      );
      if (!mounted) return;
      setState(() => _joined = true);
      // Best-effort: also emit read event for read receipts.
      SocketService.instance.emit('chat:read', {'threadId': widget.threadId});
    } catch (_) {
      // Don't crash the screen if socket join fails.
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    if (_isDraftThread) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Messaging is not available yet. Start an enquiry to unlock chat.',
          ),
        ),
      );
      return;
    }
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    SocketService.instance.emit(
      'chat:typing',
      {'threadId': widget.threadId, 'isTyping': false},
    );

    try {
      await ref.read(chatActionProvider).sendMessage(widget.threadId, text);
      ref.invalidate(messagesProvider(widget.threadId));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    final msgsAsync =
        _isDraftThread ? const AsyncValue<List<MessageModel>>.data([]) : ref.watch(messagesProvider(widget.threadId));
    final me = _myId ?? 'me';
    final title = widget.header?.title.trim().isNotEmpty == true
        ? widget.header!.title.trim()
        : 'Chat';
    final subtitle = widget.header?.subtitle?.trim();
    final avatarUrl =
        UrlUtils.normalizeMediaUrl(widget.header?.avatarUrl ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.person_rounded, color: AppColors.primary)
                  : CachedNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => const SizedBox.shrink(),
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
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
          ],
        ),
      ),
      body: Column(
        children: [
          if (widget.header != null) _ContextStrip(header: widget.header!),
          if (_isDraftThread)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.textSecondary.withAlpha(220),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chat is locked until an enquiry is started/accepted.',
                        style: TextStyle(
                          color: AppColors.textSecondary.withAlpha(235),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: msgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ChatList(
                messages: _mergeMessages(
                  base: const <MessageModel>[],
                  incoming: _incomingById.values,
                  local: _localMessages,
                ),
                myId: me,
                controller: _scroll,
              ),
              data: (msgs) => _ChatList(
                messages: _mergeMessages(
                  base: msgs,
                  incoming: _incomingById.values,
                  local: _localMessages,
                ),
                myId: me,
                controller: _scroll,
              ),
            ),
          ),
          if (_otherTyping)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'typing…',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onChanged: (_) => _handleTyping(),
                    enabled: !_isDraftThread,
                    decoration: InputDecoration(
                      hintText: _isDraftThread
                          ? 'Chat locked — start an enquiry first'
                          : 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isDraftThread
                          ? AppColors.primary.withAlpha(120)
                          : AppColors.primary,
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

  void _handleTyping() {
    if (_isDraftThread) return;
    _typingTimer?.cancel();
    SocketService.instance.emit(
      'chat:typing',
      {'threadId': widget.threadId, 'isTyping': true},
    );
    _typingTimer = Timer(const Duration(milliseconds: 850), () {
      SocketService.instance.emit(
        'chat:typing',
        {'threadId': widget.threadId, 'isTyping': false},
      );
    });
  }

  List<_ChatMessage> _mergeMessages({
    required Iterable base,
    required Iterable<MessageModel> incoming,
    required List<_LocalMessage> local,
  }) {
    // Join socket before showing content (per spec: REST first, then join).
    _joinIfNeeded();

    final List<_ChatMessage> out = [];

    final baseList = base is List ? base : const <dynamic>[];
    final isBaseModels = baseList.isNotEmpty && baseList.first is MessageModel;
    final isBaseUi = baseList.isNotEmpty && baseList.first is _ChatMessage;

    if (isBaseModels) {
      final sorted = List<MessageModel>.from(baseList.cast<MessageModel>())
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final m in sorted) {
        out.add(
          _ChatMessage(
            id: m.id,
            senderId: m.senderId,
            text: m.text,
            createdAt: m.createdAt,
            readBy: m.readBy,
          ),
        );
      }
    } else if (isBaseUi) {
      out.addAll(baseList.cast<_ChatMessage>());
    }

    // Append any incoming messages not already present.
    final existingIds = out.map((m) => m.id).whereType<String>().toSet();
    final incSorted = List<MessageModel>.from(incoming)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final m in incSorted) {
      if (m.threadId != widget.threadId) continue;
      if (existingIds.contains(m.id)) continue;
      out.add(
        _ChatMessage(
          id: m.id,
          senderId: m.senderId,
          text: m.text,
          createdAt: m.createdAt,
          readBy: m.readBy,
        ),
      );
    }

    for (final m in local) {
      out.add(
        _ChatMessage(
          id: null,
          senderId: m.senderId,
          text: m.text,
          createdAt: m.createdAt,
          readBy: const [],
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });
    return out;
  }
}

class _ChatList extends StatelessWidget {
  final List<_ChatMessage> messages;
  final String myId;
  final ScrollController controller;

  const _ChatList({
    required this.messages,
    required this.myId,
    required this.controller,
  });

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
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final isMe = msg.senderId == myId;
        final time = TimeOfDay.fromDateTime(msg.createdAt).format(context);
        final isRead = isMe && msg.readBy.any((id) => id != myId);
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
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.text,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isMe ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: (isMe ? Colors.white : AppColors.textSecondary)
                            .withAlpha(isMe ? 210 : 235),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Icon(
                        isRead
                            ? Icons.done_all_rounded
                            : Icons.check_rounded,
                        size: 14,
                        color: Colors.white.withAlpha(isRead ? 235 : 200),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatMessage {
  final String? id;
  final String senderId;
  final String text;
  final List<String> readBy;
  final DateTime createdAt;

  const _ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.readBy,
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

class _ContextStrip extends StatelessWidget {
  final ChatHeader header;
  const _ContextStrip({required this.header});

  @override
  Widget build(BuildContext context) {
    final tag = (header.contextTag ?? '').trim();
    final title = (header.contextTitle ?? '').trim();
    final preview = (header.enquiryPreview ?? '').trim();
    final img = UrlUtils.normalizeMediaUrl(header.contextImageUrl ?? '').trim();
    final show = tag.isNotEmpty || title.isNotEmpty || img.isNotEmpty;
    if (!show) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(6),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          if (img.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 54,
                height: 54,
                child: CachedNetworkImage(
                  imageUrl: img,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (_, __) => const ColoredBox(color: AppColors.bg),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: AppColors.bg),
                ),
              ),
            )
          else
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.play_circle_rounded,
                  color: AppColors.primary),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tag.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: AppColors.primary.withAlpha(34)),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: AppColors.primary,
                        height: 1.0,
                      ),
                    ),
                  ),
                if (tag.isNotEmpty) const SizedBox(height: 6),
                Text(
                  title.isEmpty ? 'Context' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
