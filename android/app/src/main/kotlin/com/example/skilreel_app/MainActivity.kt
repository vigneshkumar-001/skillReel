package com.feni.skilreel_app

import android.os.Handler
import android.os.Looper
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "skilreel/ffmpeg"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        if (call.method != "execute") {
          result.notImplemented()
          return@setMethodCallHandler
        }

        val args = call.arguments as? Map<*, *>
        val command = (args?.get("command") as? String)?.trim().orEmpty()
        if (command.isEmpty()) {
          result.error("bad_args", "Missing 'command'", null)
          return@setMethodCallHandler
        }

        val mainHandler = Handler(Looper.getMainLooper())

        FFmpegKit.executeAsync(command) { session ->
          try {
            val rc = session.returnCode
            val code = rc?.value ?: -1
            val output = session.allLogsAsString ?: ""

            mainHandler.post {
              result.success(
                mapOf(
                  "returnCode" to code,
                  "output" to output
                )
              )
            }
          } catch (e: Exception) {
            mainHandler.post {
              result.error("ffmpeg_error", e.message, null)
            }
          }
        }
      }
  }
}
