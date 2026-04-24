class ThreadModel {
  final String id;
  final String providerId;
  final String? enquiryId;
  final String? title;
  final String? subtitle;
  final String? avatarUrl;
  final String? contextTitle;
  final String? contextImageUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String? lastSenderId;
  final List<String> participants;

  ThreadModel({
    required this.id,
    required this.providerId,
    this.enquiryId,
    this.title,
    this.subtitle,
    this.avatarUrl,
    this.contextTitle,
    this.contextImageUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.lastSenderId,
    required this.participants,
  });

  factory ThreadModel.fromJson(Map<String, dynamic> j) => ThreadModel(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        providerId: (j['providerId'] ?? '').toString(),
        enquiryId: j['enquiryId'],
        title: j['title']?.toString(),
        subtitle: j['subtitle']?.toString(),
        avatarUrl: j['avatarUrl']?.toString(),
        contextTitle: j['contextTitle']?.toString(),
        contextImageUrl: j['contextImageUrl']?.toString(),
        lastMessage: j['lastMessage'],
        lastMessageAt: j['lastMessageAt'] != null
            ? DateTime.tryParse(j['lastMessageAt'])
            : null,
        unreadCount: (j['unreadCount'] is num)
            ? (j['unreadCount'] as num).toInt()
            : int.tryParse('${j['unreadCount'] ?? 0}') ?? 0,
        lastSenderId: j['lastSenderId']?.toString(),
        participants: List<String>.from(j['participants'] ?? []),
      );
}

class MessageModel {
  final String id;
  final String threadId;
  final String senderId;
  final String text;
  final List<String> readBy;
  final DateTime createdAt;

  MessageModel({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    this.readBy = const [],
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> j) => MessageModel(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        threadId: (j['threadId'] ?? '').toString(),
        senderId: (j['senderId'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        readBy: List<String>.from(j['readBy'] ?? const []),
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}
