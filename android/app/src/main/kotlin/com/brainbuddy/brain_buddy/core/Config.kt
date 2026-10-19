package com.brainbuddy.brain_buddy.core

import android.content.Context
import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** User settings. Stored natively so the counting service can read them even when the app UI is closed. */
class Config(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("bb_config", Context.MODE_PRIVATE)

    var tracked: Set<String>
        get() = prefs.getStringSet(KEY_TRACKED, null) ?: TargetApps.all.map { it.pkg }.toSet()
        set(v) = prefs.edit().putStringSet(KEY_TRACKED, v).apply()

    val budget get() = prefs.getInt("budget", 30)
    val dwellSec get() = prefs.getInt("dwellSec", 3)
    val showSkimmed get() = prefs.getBoolean("showSkimmed", true)
    val ignoreAds get() = prefs.getBoolean("ignoreAds", true)
    val dayStartHour get() = prefs.getInt("dayStartHour", 0)
    val floatingCounter get() = prefs.getBoolean("floatingCounter", true)
    val intentPause get() = prefs.getBoolean("intentPause", false)
    val intentWaitSec get() = prefs.getInt("intentWaitSec", 3)
    val warn50 get() = prefs.getBoolean("warn50", false)
    val warn80 get() = prefs.getBoolean("warn80", true)
    val warn100 get() = prefs.getBoolean("warn100", true)
    val pausedUntil get() = prefs.getLong("pausedUntil", 0L)

    var lastIntentAt: Long
        get() = prefs.getLong("lastIntentAt", 0L)
        set(v) = prefs.edit().putLong("lastIntentAt", v).apply()

    fun isTracked(pkg: String) = pkg in tracked
    fun isPaused(now: Long = System.currentTimeMillis()) = now < pausedUntil

    fun today(now: Long = System.currentTimeMillis()) = dayKey(now, dayStartHour)

    /** Extra reels the user allowed themselves today with "5 more reels". */
    fun extraToday(): Int = prefs.getInt("extra_" + today(), 0)
    fun addExtraToday(n: Int) = prefs.edit().putInt("extra_" + today(), extraToday() + n).apply()
    fun allowanceToday() = budget + extraToday()

    /** Returns true only the first time a warning level is reached on a given day. */
    fun markWarned(level: Int): Boolean {
        val key = "warned${level}_" + today()
        if (prefs.getBoolean(key, false)) return false
        prefs.edit().putBoolean(key, true).apply()
        return true
    }

    fun toMap(): Map<String, Any> = mapOf(
        KEY_TRACKED to tracked.toList(),
        "budget" to budget,
        "dwellSec" to dwellSec,
        "showSkimmed" to showSkimmed,
        "ignoreAds" to ignoreAds,
        "dayStartHour" to dayStartHour,
        "floatingCounter" to floatingCounter,
        "intentPause" to intentPause,
        "intentWaitSec" to intentWaitSec,
        "warn50" to warn50,
        "warn80" to warn80,
        "warn100" to warn100,
        "pausedUntil" to pausedUntil,
        "extraToday" to extraToday(),
        "today" to today(),
    )

    /** Applies a partial update coming from Flutter. Unknown keys are ignored. */
    fun apply(values: Map<*, *>) {
        val e = prefs.edit()
        for ((k, v) in values) {
            when (k) {
                KEY_TRACKED -> e.putStringSet(KEY_TRACKED, (v as List<*>).map { it.toString() }.toSet())
                "budget", "dwellSec", "dayStartHour", "intentWaitSec" -> e.putInt(k as String, (v as Number).toInt())
                "showSkimmed", "ignoreAds", "floatingCounter", "intentPause", "warn50", "warn80", "warn100" ->
                    e.putBoolean(k as String, v as Boolean)
                "pausedUntil" -> e.putLong("pausedUntil", (v as Number).toLong())
            }
        }
        e.apply()
    }

    fun clear() = prefs.edit().clear().apply()

    companion object {
        private const val KEY_TRACKED = "tracked"

        /** The "day" a moment belongs to. A day can start later than midnight for night owls. */
        fun dayKey(ts: Long, dayStartHour: Int): String {
            val c = Calendar.getInstance().apply {
                timeInMillis = ts
                add(Calendar.HOUR_OF_DAY, -dayStartHour)
            }
            return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(c.time)
        }
    }
}
