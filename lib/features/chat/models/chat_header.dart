class ChatHeader {
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final String? contextTag;
  final String? contextTitle;
  final String? contextImageUrl;
  final String? enquiryPreview;

  const ChatHeader({
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.contextTag,
    this.contextTitle,
    this.contextImageUrl,
    this.enquiryPreview,
  });
}
