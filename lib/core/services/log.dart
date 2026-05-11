import 'package:logger/logger.dart' as lg;

/// Simple app-wide logger with `log.i()`, `log.d()` style calls.
///
/// Note: colors depend on the console supporting ANSI escape codes
/// (VS Code/Android Studio sometimes disable them). If you still don't see
/// color, run from a terminal (`flutter run`) instead of the IDE debug console.
class AppLog {
  final String _name;
  final lg.Logger _logger;

  AppLog([String name = 'App'])
      : _name = name,
        _logger = lg.Logger(
          printer: lg.PrettyPrinter(
            methodCount: 0,
            errorMethodCount: 8,
            lineLength: 120,
            colors: true,
            printEmojis: false,
            // Hide the leading time line like "16:50:14.309 (+0:...)" so logs
            // look closer to typical Flutter debug output, and keep the
            // callsite/stack frames as the primary navigation targets.
            dateTimeFormat: lg.DateTimeFormat.none,
          ),
        );

  AppLog tag(String name) => AppLog(name);

  void d(Object? message, [Object? error, StackTrace? stackTrace]) {
    _logger.d('[$_name] $message', error: error, stackTrace: stackTrace);
  }

  void i(Object? message, [Object? error, StackTrace? stackTrace]) {
    _logger.i('[$_name] $message', error: error, stackTrace: stackTrace);
  }

  void w(Object? message, [Object? error, StackTrace? stackTrace]) {
    _logger.w('[$_name] $message', error: error, stackTrace: stackTrace);
  }

  void e(Object? message, [Object? error, StackTrace? stackTrace]) {
    _logger.e('[$_name] $message', error: error, stackTrace: stackTrace);
  }
}

final log = AppLog();
