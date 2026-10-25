package com.brainbuddy.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import com.brainbuddy.app.core.CloudBackup
import com.brainbuddy.app.core.Config
import com.brainbuddy.app.core.CountBus
import com.brainbuddy.app.core.Db
import com.brainbuddy.app.core.SquadSync
import com.brainbuddy.app.core.TargetApps
import com.brainbuddy.app.service.ReelCounterService
import com.brainbuddy.app.widget.BrainWidgetProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** The bridge between the Flutter screens and the native counting engine. */
class NativeBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val config = Config(activity)
    private val db = Db.get(activity)

    init {
        MethodChannel(messenger, "brain_buddy/native").setMethodCallHandler { call, result ->
            try {
                result.success(handle(call))
            } catch (e: Exception) {
                result.error("native_error", e.message, null)
            }
        }
        EventChannel(messenger, "brain_buddy/events").setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: (() -> Unit)? = null
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                val l = { sink.success(System.currentTimeMillis()) }
                listener = l
                CountBus.listen(l)
            }
            override fun onCancel(arguments: Any?) {
                listener?.let { CountBus.remove(it) }
                listener = null
            }
        })
    }

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "getConfig" -> {
            config.settleFocus()
            // Same rule as the counter: earned reels that lift the limit also lift a budget Hard lock.
            if (config.isHardLocked() && db.watchedCount(config.today()) < config.allowanceToday()) config.hardLockedUntil = 0
            config.toMap()
        }
        "startFocus" -> {
            config.startFocus(call.argument<Int>("minutes") ?: config.focusMinutes)
            afterDataChange()
            config.toMap()
        }
        "cancelFocus" -> {
            config.cancelFocus()
            afterDataChange()
            config.toMap()
        }
        "requestActivityRecognition" -> {
            if (Build.VERSION.SDK_INT >= 29) {
                ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), 8)
            }
            true
        }
        "setConfig" -> {
            config.apply(call.arguments as Map<*, *>)
            afterDataChange()
            config.toMap()
        }
        "getTargets" -> TargetApps.all.distinctBy { it.name }.map { app ->
            // TikTok has two package names; report whichever is installed.
            val pkgs = TargetApps.all.filter { it.name == app.name }.map { it.pkg }
            val installed = pkgs.firstOrNull { isInstalled(it) }
            mapOf("pkg" to (installed ?: app.pkg), "pkgs" to pkgs, "name" to app.name, "installed" to (installed != null))
        }
        "getAppIcons" -> appIcons()
        "backupNow" -> {
            CloudBackup.backup(activity, force = true)
            true
        }
        "importSummaries" -> {
            val count = db.importSummaries(call.argument<String>("json")!!)
            afterDataChange()
            count
        }
        "restoreSettings" -> {
            config.apply(call.arguments as Map<*, *>)
            afterDataChange()
            config.toMap()
        }
        "localDays" -> db.daysWithData().size
        "syncSquads" -> {
            SquadSync.sync(activity, force = true)
            true
        }
        "getStatus" -> status()
        "getDay" -> db.daySummary(call.argument<String>("day") ?: config.today())
        "getDays" -> {
            val count = call.argument<Int>("count") ?: 7
            val oneDay = 24L * 60 * 60 * 1000
            val now = System.currentTimeMillis()
            (count - 1 downTo 0).map { db.daySummary(Config.dayKey(now - it * oneDay, config.dayStartHour)) }
        }
        "getPatterns" -> {
            val count = call.argument<Int>("count") ?: 30
            val oneDay = 24L * 60 * 60 * 1000
            val now = System.currentTimeMillis()
            db.patterns((0 until count).map { Config.dayKey(now - it * oneDay, config.dayStartHour) })
        }
        "pause" -> {
            val minutes = call.argument<Int>("minutes") ?: 0
            config.apply(mapOf("pausedUntil" to if (minutes <= 0) 0L else System.currentTimeMillis() + minutes * 60_000L))
            CountBus.emit()
            config.toMap()
        }
        "exportBackup" -> db.exportJson(config.toMap())
        "exportCsv" -> db.exportCsv()
        "importBackup" -> {
            val restoredConfig = db.importJson(call.argument<String>("json")!!)
            config.apply(restoredConfig)
            afterDataChange()
            true
        }
        "deleteAllData" -> {
            db.clearAll()
            config.clear()
            afterDataChange()
            true
        }
        "openAccessibilitySettings" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        "openBatterySettings" -> requestBatteryExemption()
        "openAppSettings" -> openAppSettings()
        "openNotificationSettings" -> open(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName),
        )
        "requestNotifications" -> {
            if (Build.VERSION.SDK_INT >= 33) {
                ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
            }
            true
        }
        "openAutostartSettings" -> openAutostart()
        else -> throw IllegalArgumentException("Unknown method ${call.method}")
    }

    private fun afterDataChange() {
        ReelCounterService.instance?.reload()
        BrainWidgetProvider.refresh(activity)
        CountBus.emit()
    }

    private fun status(): Map<String, Any> {
        val pm = activity.getSystemService(PowerManager::class.java)
        return mapOf(
            "accessibility" to isAccessibilityEnabled(),
            "serviceRunning" to (ReelCounterService.instance != null),
            "battery" to pm.isIgnoringBatteryOptimizations(activity.packageName),
            "backgroundRestricted" to isBackgroundRestricted(),
            "lastError" to (ReelCounterService.lastError ?: ""),
            "notifications" to NotificationManagerCompat.from(activity).areNotificationsEnabled(),
            "lastEventAt" to ReelCounterService.lastEventAt,
            "manufacturer" to Build.MANUFACTURER.lowercase(),
            "model" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
            "paused" to config.isPaused(),
            "pausedUntil" to config.pausedUntil,
        )
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(activity.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val cn = ComponentName(activity, ReelCounterService::class.java)
        return enabled.split(':').any {
            it.equals(cn.flattenToString(), true) || it.equals(cn.flattenToShortString(), true)
        }
    }

    /**
     * Shows Android's own "Allow Brain Buddy to always run in the background?" dialog.
     * The settings list we used before hides apps that are still optimised, so users couldn't find Brain Buddy.
     */
    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption(): Boolean {
        val pm = activity.getSystemService(PowerManager::class.java)
        if (pm.isIgnoringBatteryOptimizations(activity.packageName)) return openAppSettings()
        return open(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${activity.packageName}")),
        )
    }

    /** "Restrict background activity" (Samsung: "Put app to sleep") stops the counter even if battery optimisation is off. */
    private fun isBackgroundRestricted(): Boolean =
        Build.VERSION.SDK_INT >= 28 && activity.getSystemService(ActivityManager::class.java).isBackgroundRestricted

    /**
     * The real launcher icons of installed reel apps, as PNG bytes. Taken from the phone, so Brain Buddy
     * doesn't ship other companies' logos and the icons always match the installed version.
     */
    private fun appIcons(): Map<String, ByteArray> {
        val out = HashMap<String, ByteArray>()
        val size = (48 * activity.resources.displayMetrics.density).toInt()
        for (app in TargetApps.all) {
            val drawable = try {
                activity.packageManager.getApplicationIcon(app.pkg)
            } catch (_: PackageManager.NameNotFoundException) {
                continue
            }
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val bytes = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
            out[app.pkg] = bytes.toByteArray()
        }
        return out
    }

    private fun isInstalled(pkg: String): Boolean = try {
        activity.packageManager.getPackageInfo(pkg, 0); true
    } catch (_: PackageManager.NameNotFoundException) { false }

    private fun open(intent: Intent): Boolean = try {
        activity.startActivity(intent); true
    } catch (_: ActivityNotFoundException) { openAppSettings() }

    private fun openAppSettings(): Boolean {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null)),
        )
        return true
    }

    /** Phone makers that stop background apps hide "Autostart" in their own settings screens. */
    private fun openAutostart(): Boolean {
        val candidates = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        )
        for (cn in candidates) {
            try {
                activity.startActivity(Intent().setComponent(cn))
                return true
            } catch (_: Exception) {}
        }
        return openAppSettings()
    }
}
