package com.tenminutestudio.whereismybusdriver.AOS

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 배터리 최적화 예외 — 위치 전송이 Doze·절전에 걸려 일정 시간 뒤 멈추는 것을 막는다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "driver_app/battery").setMethodCallHandler { call, result ->
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            when (call.method) {
                "isIgnoring" -> result.success(pm.isIgnoringBatteryOptimizations(packageName))
                "request" -> {
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
