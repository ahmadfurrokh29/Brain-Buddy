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

    // ---------------------------------------------------------------- lock styles

    /** What happens at the budget: "gentle" (breathing break), "firm" (wait + reason) or "hard" (locked). */
    val lockMode get() = prefs.getString("lockMode", "gentle") ?: "gentle"
    /** How long a Hard lock lasts: "1h", "3h" or "tomorrow". */
    val hardDuration get() = prefs.getString("hardDuration", "tomorrow") ?: "tomorrow"
    val emergencyPerWeek get() = prefs.getInt("emergencyPerWeek", 1)

    var hardLockedUntil: Long
        get() = prefs.getLong("hardLockedUntil", 0L)
        set(v) = prefs.edit().putLong("hardLockedUntil", v).apply()

    fun isHardLocked(now: Long = System.currentTimeMillis()) = now < hardLockedUntil

    /** Starts a Hard lock now and returns when it ends. */
    fun startHardLock(now: Long = System.currentTimeMillis()): Long {
        val until = when (hardDuration) {
            "1h" -> now + 60 * 60_000L
            "3h" -> now + 3 * 60 * 60_000L
            else -> nextDayStart(now)
        }
        hardLockedUntil = until
        return until
    }

    /** When the current "day" ends (respects a later day start for night owls). */
    fun nextDayStart(now: Long = System.currentTimeMillis()): Long {
        val c = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, dayStartHour)
            set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (c.timeInMillis <= now) c.add(Calendar.DAY_OF_YEAR, 1)
        return c.timeInMillis
    }

    private fun weekKey(now: Long = System.currentTimeMillis()): String {
        val c = Calendar.getInstance().apply { timeInMillis = now }
        return "${c.get(Calendar.YEAR)}-w${c.get(Calendar.WEEK_OF_YEAR)}"
    }

    fun emergencyLeft(): Int = (emergencyPerWeek - prefs.getInt("emergencyUsed_" + weekKey(), 0)).coerceAtLeast(0)
    fun useEmergency() {
        val key = "emergencyUsed_" + weekKey()
        prefs.edit().putInt(key, prefs.getInt(key, 0) + 1).apply()
    }

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
        "lockMode" to lockMode,
        "hardDuration" to hardDuration,
        "emergencyPerWeek" to emergencyPerWeek,
        "emergencyLeft" to emergencyLeft(),
        "hardLockedUntil" to hardLockedUntil,
    )

    /**
     * Applies a partial update coming from Flutter. Unknown keys are ignored.
     * During an active Hard lock, changes that would loosen it are refused here, not just hidden in the UI.
     */
    fun apply(values: Map<*, *>) {
        val locked = isHardLocked()
        val e = prefs.edit()
        for ((k, v) in values) {
            if (locked) {
                when (k) {
                    "budget" -> if ((v as Number).toInt() > budget) continue
                    "lockMode" -> if (v != "hard") continue
                    "hardDuration", "pausedUntil" -> continue
                    "emergencyPerWeek" -> if ((v as Number).toInt() > emergencyPerWeek) continue
                }
            }
            when (k) {
                KEY_TRACKED -> e.putStringSet(KEY_TRACKED, (v as List<*>).map { it.toString() }.toSet())
                "budget", "dwellSec", "dayStartHour", "intentWaitSec", "emergencyPerWeek" -> e.putInt(k as String, (v as Number).toInt())
                "lockMode", "hardDuration" -> e.putString(k as String, v as String)
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
