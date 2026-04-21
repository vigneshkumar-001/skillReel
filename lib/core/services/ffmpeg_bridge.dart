import 'package:flutter/services.dart';

class FfmpegBridge {
  static const MethodChannel _channel = MethodChannel('skilreel/ffmpeg');

  static Future<void> execute(
    String command, {
    required String onFailTitle,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map>('execute', {
        'command': command,
      });

      if (res == null) {
        throw StateError('FFmpeg failed: empty result');
      }

      final returnCode = res['returnCode'];
      final output = (res['output'] ?? '').toString();
      final rc = returnCode is int ? returnCode : int.tryParse('$returnCode');

      if (rc == null) {
        throw StateError('FFmpeg failed: invalid returnCode');
      }
      if (rc != 0) {
        throw PlatformException(
          code: 'ffmpeg_failed',
          message: onFailTitle,
          details: output.isEmpty ? 'Return code: $rc' : output,
        );
      }
    } on MissingPluginException {
      throw PlatformException(
        code: 'ffmpeg_not_supported',
        message: onFailTitle,
        details: 'FFmpeg is not available on this platform build.',
      );
    }
  }
}

