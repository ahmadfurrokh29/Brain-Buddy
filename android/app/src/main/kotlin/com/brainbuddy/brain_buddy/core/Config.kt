package com.brainbuddy.brain_buddy.core

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
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

    // ---------------------------------------------------------------- schedules

    /**
     * Times when reels are blocked, e.g. Bedtime 23:00–07:00. Stored as JSON:
     * [{"id","name","start":minutes,"end":minutes,"days":[1..7 Mon..Sun],"enabled"}]
     */
    val schedulesJson get() = prefs.getString("schedules", "[]") ?: "[]"

    data class ActiveSchedule(val id: String, val name: String, val until: Long)

    /** The schedule blocking reels right now, unless the user spent an emergency unlock on it. */
    fun activeSchedule(now: Long = System.currentTimeMillis()): ActiveSchedule? {
        val list = try { JSONArray(schedulesJson) } catch (_: Exception) { return null }
        val c = Calendar.getInstance().apply { timeInMillis = now }
        val minute = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        val today = isoDay(c)
        val yesterday = if (today == 1) 7 else today - 1
        for (i in 0 until list.length()) {
            val s = list.getJSONObject(i)
            if (!s.optBoolean("enabled", true)) continue
            val start = s.getInt("start"); val end = s.getInt("end")
            val days = s.getJSONArray("days").let { d -> (0 until d.length()).map { d.getInt(it) }.toSet() }
            val active: Boolean
            val endsAt = Calendar.getInstance().apply {
                timeInMillis = now
                set(Calendar.HOUR_OF_DAY, end / 60); set(Calendar.MINUTE, end % 60)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            if (start < end) {
                active = today in days && minute in start until end
            } else { // overnight, e.g. 23:00–07:00
                active = (minute >= start && today in days) || (minute < end && yesterday in days)
                if (minute >= start) endsAt.add(Calendar.DAY_OF_YEAR, 1)
            }
            if (!active) continue
            val id = s.getString("id")
            if (prefs.getLong("snoozed_$id", 0L) >= endsAt.timeInMillis) continue
            return ActiveSchedule(id, s.optString("name", "Schedule"), endsAt.timeInMillis)
        }
        return null
    }

    /** Emergency unlock for a schedule: lets reels through until this run of the schedule ends. */
    fun snoozeSchedule(s: ActiveSchedule) = prefs.edit().putLong("snoozed_${s.id}", s.until).apply()

    private fun isoDay(c: Calendar) = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1 // Mon=1 … Sun=7

    /** While a schedule runs it must stay in the list, switched on, with the same times and days. */
    private fun keepsActiveSchedule(newJson: String): Boolean {
        val active = activeSchedule() ?: return true
        val old = JSONArray(schedulesJson)
        val before = (0 until old.length()).map { old.getJSONObject(it) }.firstOrNull { it.getString("id") == active.id } ?: return true
        val list = try { JSONArray(newJson) } catch (_: Exception) { return false }
        val after = (0 until list.length()).map { list.getJSONObject(it) }.firstOrNull { it.getString("id") == active.id } ?: return false
        return after.optBoolean("enabled", true) &&
            after.getInt("start") == before.getInt("start") &&
            after.getInt("end") == before.getInt("end") &&
            after.getJSONArray("days").toString() == before.getJSONArray("days").toString()
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
        "schedules" to schedulesJson,
        "activeSchedule" to (activeSchedule()?.let { mapOf("id" to it.id, "name" to it.name, "until" to it.until) } ?: emptyMap<String, Any>()),
    )

    /**
     * Applies a partial update coming from Flutter. Unknown keys are ignored.
     * During an active Hard lock, changes that would loosen it are refused here, not just hidden in the UI.
     */
    fun apply(values: Map<*, *>) {
        val locked = isHardLocked() || activeSchedule() != null
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
                "schedules" -> if (keepsActiveSchedule(v as String)) e.putString("schedules", v)
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
