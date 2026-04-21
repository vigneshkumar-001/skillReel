class CrashlyticsLogSettings {
  /// Set this to `true` to send API error context (sanitized) to Firebase
  /// Crashlytics. Set `false` to disable API error logging to Crashlytics.
  ///
  /// Note: this only affects API error logging. Crashes/non-fatals can still be
  /// reported by Crashlytics if enabled.
  static bool apiLoggingEnabled = true;
}
