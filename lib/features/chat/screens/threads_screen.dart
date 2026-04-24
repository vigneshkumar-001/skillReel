import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/chat_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../models/chat_model.dart';
import '../models/chat_header.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/url_utils.dart';

class ThreadsScreen extends ConsumerStatefulWidget {
  const ThreadsScreen({super.key});

  @override
  ConsumerState<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends ConsumerState<ThreadsScreen> {
  List<ThreadModel>? _threads;
  ProviderSubscription<AsyncValue<List<ThreadModel>>>? _threadsSub;

  void _applyThreadUpdate(Map<String, dynamic> payload) {
    final threadId = (payload['threadId'] ?? '').toString().trim();
    if (threadId.isEmpty) return;
    final lastMessage = payload['lastMessage']?.toString();
    final lastMessageAt = payload['lastMessageAt'] != null
        ? DateTime.tryParse(payload['lastMessageAt'].toString())
        : null;
    final unreadCount = (payload['unreadCount'] is num)
        ? (payload['unreadCount'] as num).toInt()
        : int.tryParse('${payload['unreadCount'] ?? 0}') ?? 0;
    final lastSenderId = payload['lastSenderId']?.toString();

    final list = List<ThreadModel>.from(_threads ?? const <ThreadModel>[]);
    final idx = list.indexWhere((t) => t.id == threadId);
    if (idx >= 0) {
      final existing = list.removeAt(idx);
      list.insert(
        0,
        ThreadModel(
          id: existing.id,
          providerId: existing.providerId,
          enquiryId: existing.enquiryId,
          title: existing.title,
          subtitle: existing.subtitle,
          avatarUrl: existing.avatarUrl,
          contextTitle: existing.contextTitle,
          contextImageUrl: existing.contextImageUrl,
          lastMessage: lastMessage ?? existing.lastMessage,
          lastMessageAt: lastMessageAt ?? existing.lastMessageAt,
          unreadCount: unreadCount,
          lastSenderId: lastSenderId ?? existing.lastSenderId,
          participants: existing.participants,
        ),
      );
    }
    setState(() => _threads = list);
  }

  void _onThreadUpdate(dynamic data) {
    if (data is Map) {
      _applyThreadUpdate(Map<String, dynamic>.from(data));
    }
  }

  @override
  void initState() {
    super.initState();
    _threadsSub = ref.listenManual(threadsProvider, (prev, next) {
      next.whenData((value) {
        if (!mounted) return;
        setState(() => _threads = value);
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SocketService.instance.ensureConnected();
      SocketService.instance.on('chat:thread:update', _onThreadUpdate);
    });
  }

  @override
  void dispose() {
    _threadsSub?.close();
    SocketService.instance.off('chat:thread:update', _onThreadUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadsAsync = ref.watch(threadsProvider);
    final threads = _threads;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          setState(() => _threads = null);
          ref.invalidate(threadsProvider);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        },
        child: threadsAsync.when(
          loading: () => const _ThreadsLoading(),
          error: (e, __) => _ThreadsError(
            error: e,
            onRetry: () {
              setState(() => _threads = null);
              ref.invalidate(threadsProvider);
            },
          ),
          data: (value) {
            final list = threads ?? value;
            return list.isEmpty
                ? _ThreadsEmpty(
                    onDiscover: () => context.go('/search'),
                    onRetry: () {
                      setState(() => _threads = null);
                      ref.invalidate(threadsProvider);
                    },
                  )
                : _ThreadsList(threads: list);
          },
        ),
      ),
    );
  }
}

class _ThreadsList extends StatelessWidget {
  final List<ThreadModel> threads;
  const _ThreadsList({required this.threads});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: threads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final t = threads[i];
        final when = t.lastMessageAt != null ? timeago.format(t.lastMessageAt!) : '';
        final title = (t.title ?? '').trim().isNotEmpty
            ? t.title!.trim()
            : 'Conversation';
        final subtitleLine = (t.contextTitle ?? '').trim().isNotEmpty
            ? 'Enquiry • ${t.contextTitle!.trim()}'
            : ((t.subtitle ?? '').trim());
        final avatarUrl = UrlUtils.normalizeMediaUrl(t.avatarUrl ?? '').trim();
        final unread = t.unreadCount;
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push(
              '/chat/${Uri.encodeComponent(t.id.trim())}',
              extra: ChatHeader(
                title: title,
                subtitle: subtitleLine.isEmpty ? null : subtitleLine,
                avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
                contextTag: (t.contextTitle ?? '').trim().isNotEmpty
                    ? 'Enquiry'
                    : null,
                contextTitle: t.contextTitle,
                contextImageUrl: t.contextImageUrl,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(8),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person_rounded,
                            color: AppColors.primary,
                          )
                        : CachedNetworkImage(
                            imageUrl: avatarUrl,
                            fit: BoxFit.cover,
                            fadeInDuration:
                                const Duration(milliseconds: 120),
                            placeholder: (_, __) =>
                                const SizedBox.shrink(),
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitleLine.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitleLine,
                            style: TextStyle(
                              color: AppColors.textSecondary.withAlpha(235),
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          (t.lastMessage ?? 'Say hi').toString(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (when.isNotEmpty)
                        Text(
                          when,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThreadsLoading extends StatelessWidget {
  const _ThreadsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

class _ThreadsEmpty extends StatelessWidget {
  final VoidCallback onDiscover;
  final VoidCallback onRetry;
  const _ThreadsEmpty({required this.onDiscover, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withAlpha(22),
                AppColors.surface,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No chats yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'When you send an enquiry or start a conversation, it will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withAlpha(235),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      child: const Text('Refresh'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onDiscover,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      child: const Text('Discover'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadsError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ThreadsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  color: AppColors.textSecondary.withAlpha(210),
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Couldn’t load chats',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull down to refresh or tap Retry.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withAlpha(235),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
