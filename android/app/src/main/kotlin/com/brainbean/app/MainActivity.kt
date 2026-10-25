package com.brainbean.app

import android.os.Bundle
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        createdAt = SystemClock.elapsedRealtime()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        com.brainbean.app.service.Notifier.ensureNudgeChannel(this)
    }

    companion object {
        /** When the screen was opened; the splash counts its 1.2 s from here. */
        @Volatile var createdAt = 0L
    }
}
