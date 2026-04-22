import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/notification_service.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  bool _handledInitial = false;
  late final GoRouter _router = createAppRouter();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitial) return;
    _handledInitial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.handlePendingRouteIfAny();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep router accessible to non-UI services (FCM/local notifications),
    // and avoid recreating it during hot reload.
    setAppRouter(_router);
    return MaterialApp.router(
      title: 'SkilReel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}
