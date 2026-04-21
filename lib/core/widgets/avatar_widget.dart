import 'package:flutter/material.dart';
import '../utils/url_utils.dart';

class AvatarWidget extends StatelessWidget {
  const AvatarWidget({
    super.key,
    this.radius = 18,
    this.imageUrl,
    this.fallbackText,
    this.backgroundColor,
    this.fallbackIcon,
  });

  final double radius;
  final String? imageUrl;
  final String? fallbackText;
  final Color? backgroundColor;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = UrlUtils.normalizeMediaUrl(imageUrl);

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundImage:
          normalizedUrl.isNotEmpty ? NetworkImage(normalizedUrl) : null,
      onForegroundImageError: (_, __) {},
      child: fallbackIcon != null
          ? Icon(fallbackIcon, size: radius, color: Colors.white70)
          : Text(
              (fallbackText ?? '?').isEmpty
                  ? '?'
                  : fallbackText!.characters.first,
            ),
    );
  }
}
