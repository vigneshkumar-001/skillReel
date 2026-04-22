import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/app_colors.dart';
import 'notification_permission_provider.dart';

class NotificationPermissionBanner extends ConsumerStatefulWidget {
  const NotificationPermissionBanner({super.key});

  @override
  ConsumerState<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends ConsumerState<NotificationPermissionBanner>
    with WidgetsBindingObserver {
  bool _checkingAfterSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_checkingAfterSettings) return;
    _checkingAfterSettings = false;
    ref.invalidate(notificationPermissionStatusProvider);
  }

  bool _shouldShow(PermissionStatus status) {
    if (ref.watch(notificationPermissionPromptDismissedProvider)) return false;
    if (status.isGranted) return false;
    if (status.isLimited) return false;
    // denied / permanentlyDenied / restricted => show prompt.
    return true;
  }

  Future<void> _enable(PermissionStatus status) async {
    HapticFeedback.selectionClick();

    if (status.isDenied) {
      await Permission.notification.request();
      ref.invalidate(notificationPermissionStatusProvider);
      return;
    }

    _checkingAfterSettings = true;
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(notificationPermissionStatusProvider);
    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        if (!_shouldShow(status)) return const SizedBox.shrink();

        final top = MediaQuery.paddingOf(context).top + 10;
        return Positioned(
          left: 12,
          right: 12,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: AppColors.surface.withAlpha(245),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border.withAlpha(180)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 22,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.primary.withAlpha(12),
                      border:
                          Border.all(color: AppColors.primary.withAlpha(22)),
                    ),
                    child: const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enable notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Turn on notifications to get updates instantly.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => _enable(status),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    child: const Text('Enable'),
                  ),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(notificationPermissionPromptDismissedProvider
                              .notifier)
                          .state = true;
                    },
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
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
