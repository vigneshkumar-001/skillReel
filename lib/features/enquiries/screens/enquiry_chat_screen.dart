import 'package:flutter/material.dart';

import '../../chat/models/chat_header.dart';
import '../../chat/screens/chat_screen.dart';

/// Separate screen for enquiry chats.
///
/// UI is intentionally identical to `ChatScreen`, but we keep it separate so we
/// can add enquiry-only behaviors (e.g. pinned reel context) without impacting
/// normal chats.
class EnquiryChatScreen extends StatelessWidget {
  final String threadId;
  final ChatHeader? header;

  const EnquiryChatScreen({
    super.key,
    required this.threadId,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return ChatScreen(threadId: threadId, header: header);
  }
}
