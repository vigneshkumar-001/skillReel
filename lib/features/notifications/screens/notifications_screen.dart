import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_colors.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;

  Future<void> _refresh() async {
    ref.invalidate(notificationsProvider);
    await ref.read(notificationsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final notifsAsync = ref.watch(notificationsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: notifsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _NotificationsState(
          icon: Icons.wifi_off_rounded,
          title: "Can't load notifications",
          subtitle: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(notificationsProvider),
        ),
        data: (notifs) {
          final items = _unreadOnly
              ? notifs
                  .where((n) => (n is Map) ? (n['isRead'] != true) : true)
                  .toList(growable: false)
              : notifs;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 132,
                  backgroundColor: AppColors.bg,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  systemOverlayStyle: SystemUiOverlayStyle.dark,
                  titleSpacing: 16,
                  title: const Text(
                    'Notifications',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: CustomPaint(
                      painter: _NotifHeaderPainter(),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 74, 16, 0),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: _NotifFilter(
                              unreadOnly: _unreadOnly,
                              onChanged: (v) => setState(() => _unreadOnly = v),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _NotificationsState(
                      icon: _unreadOnly
                          ? Icons.mark_email_unread_rounded
                          : Icons.notifications_none_rounded,
                      title: _unreadOnly ? 'All caught up' : 'No updates yet',
                      subtitle: _unreadOnly
                          ? 'No unread notifications.'
                          : 'Likes, comments, and alerts will show here.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _NotifCard(n: items[i]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotifFilter extends StatelessWidget {
  final bool unreadOnly;
  final ValueChanged<bool> onChanged;

  const _NotifFilter({
    required this.unreadOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterChipLike(
            selected: !unreadOnly,
            label: 'All',
            onTap: () => onChanged(false),
          ),
          _FilterChipLike(
            selected: unreadOnly,
            label: 'Unread',
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _FilterChipLike extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _FilterChipLike({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? AppColors.textPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: fg,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _NotificationsState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(10),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final Map n;
  const _NotifCard({required this.n});

  IconData get _icon {
    final t = (n['type'] ?? '').toString().toLowerCase();
    if (t.contains('like')) return Icons.favorite_rounded;
    if (t.contains('comment')) return Icons.chat_bubble_rounded;
    if (t.contains('enquiry')) return Icons.question_answer_rounded;
    if (t.contains('follow')) return Icons.person_add_alt_1_rounded;
    return Icons.notifications_rounded;
  }

  Color get _tint {
    final t = (n['type'] ?? '').toString().toLowerCase();
    if (t.contains('like')) return AppColors.accent;
    if (t.contains('comment')) return const Color(0xFF3B82F6);
    if (t.contains('enquiry')) return const Color(0xFF06B6D4);
    if (t.contains('follow')) return AppColors.secondary;
    return AppColors.primary;
  }

  String get _when {
    final raw = (n['createdAt'] ?? '').toString();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    return timeago.format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final title = (n['title'] ?? '').toString();
    final body = (n['body'] ?? '').toString();
    final isRead = (n['isRead'] ?? true) == true;
    final tint = _tint;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: tint.withAlpha(10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tint.withAlpha(14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tint.withAlpha(35)),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(_icon, color: tint, size: 20),
                        ),
                        if (!isRead)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: tint,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: AppColors.surface, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title.isEmpty ? 'Update' : title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_when.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Text(
                                _when,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (body.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            body.trim(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotifHeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = AppColors.bg;
    canvas.drawRect(Offset.zero & size, bg);

    void blob({
      required Offset center,
      required double radius,
      required Color a,
      required Color b,
    }) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final shader = RadialGradient(
        colors: [a, b],
        stops: const [0.0, 1.0],
      ).createShader(rect);
      final p = Paint()..shader = shader;
      canvas.drawCircle(center, radius, p);
    }

    blob(
      center: Offset(size.width * 0.15, size.height * 0.35),
      radius: size.width * 0.50,
      a: AppColors.primary.withAlpha(26),
      b: AppColors.primary.withAlpha(0),
    );
    blob(
      center: Offset(size.width * 0.88, size.height * 0.25),
      radius: size.width * 0.46,
      a: const Color(0xFFF59E0B).withAlpha(18),
      b: const Color(0xFFF59E0B).withAlpha(0),
    );
    blob(
      center: Offset(size.width * 0.70, size.height * 0.95),
      radius: size.width * 0.36,
      a: const Color(0xFF3B82F6).withAlpha(18),
      b: const Color(0xFF3B82F6).withAlpha(0),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
