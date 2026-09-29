package com.example.do_robotics

import android.content.Context
import android.net.wifi.WifiManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI plus two small platform hooks used from
 * lib/services/platform_service.dart:
 *  - keepScreenOn: while a program runs. Android stops camera frames and
 *    blocks the microphone for apps that are not in the foreground, so a
 *    screen timeout would leave the robot acting on stale sensor data.
 *  - multicast lock: Android filters incoming multicast unless an app holds
 *    one, which silently breaks mDNS (robot.local) on many phones.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        if (call.arguments as? Boolean == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "acquireMulticastLock" -> {
                        val lock = multicastLock
                            ?: (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                                .createMulticastLock("do_robotics_mdns")
                                .apply { setReferenceCounted(false) }
                        multicastLock = lock
                        if (!lock.isHeld) lock.acquire()
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        multicastLock?.let { if (it.isHeld) it.release() }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "do_robotics/platform"
    }
}
