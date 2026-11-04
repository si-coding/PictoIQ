package com.pictoiq.app

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Free and total space on the phone, for the home screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pictoiq/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "deviceStorage") {
                    val stat = StatFs(Environment.getDataDirectory().path)
                    result.success(
                        mapOf("free" to stat.availableBytes, "total" to stat.totalBytes)
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
