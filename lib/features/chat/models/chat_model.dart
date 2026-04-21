class ThreadModel {
  final String id;
  final String providerId;
  final String? enquiryId;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final List<String> participants;

  ThreadModel({
    required this.id,
    required this.providerId,
    this.enquiryId,
    this.lastMessage,
    this.lastMessageAt,
    required this.participants,
  });

  factory ThreadModel.fromJson(Map<String, dynamic> j) => ThreadModel(
        id: j['_id'] ?? j['id'],
        providerId: j['providerId'] ?? '',
        enquiryId: j['enquiryId'],
        lastMessage: j['lastMessage'],
        lastMessageAt: j['lastMessageAt'] != null
            ? DateTime.tryParse(j['lastMessageAt'])
            : null,
        participants: List<String>.from(j['participants'] ?? []),
      );
}

class MessageModel {
  final String id;
  final String threadId;
  final String senderId;
  final String text;
  final DateTime createdAt;

  MessageModel({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> j) => MessageModel(
        id: j['_id'] ?? j['id'],
        threadId: j['threadId'],
        senderId: j['senderId'],
        text: j['text'],
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}