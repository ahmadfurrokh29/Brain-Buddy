package com.brainbean.app.core

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** User settings. Stored natively so the counting service can read them even when the app UI is closed. */
class Config(context: Context) {
    private val app = context.applicationContext
    private val prefs: SharedPreferences = app.getSharedPreferences("bb_config", Context.MODE_PRIVATE)

    /** Apps to count. Until the user picks, only the supported apps that are installed on this phone. */
    var tracked: Set<String>
        get() = prefs.getStringSet(KEY_TRACKED, null) ?: installedTargets
        set(v) = prefs.edit().putStringSet(KEY_TRACKED, v).apply()

    // Worked out once: this is read on every screen change in the reel apps.
    private val installedTargets by lazy { TargetApps.all.map { it.pkg }.filter(::isInstalled).toSet() }

    /**
     * Switches on supported apps installed since the last check (e.g. Reddit installed later). Apps that were
     * already installed keep the user's choice, so an app they switched off stays off.
     * Returns true if the list of tracked apps changed.
     */
    fun trackNewlyInstalledApps(): Boolean {
        val installedNow = TargetApps.all.map { it.pkg }.filter(::isInstalled).toSet()
        val seen = prefs.getStringSet(KEY_SEEN_INSTALLED, null)
        prefs.edit().putStringSet(KEY_SEEN_INSTALLED, installedNow).apply()
        if (seen == null) return false // first check: nothing to compare with yet
        val fresh = installedNow - seen
        if (fresh.isEmpty()) return false
        tracked = (prefs.getStringSet(KEY_TRACKED, null) ?: seen) + fresh
        return true
    }

    private fun isInstalled(pkg: String) = try {
        app.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: Exception) {
        false
    }

    val budget get() = prefs.getInt("budget", 30)
    val dwellSec get() = prefs.getInt("dwellSec", 1)
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

    /**
     * When the current Firm-lock wait ends. Saved, so leaving the app or turning the screen off doesn't
     * restart the 60 seconds. Cleared after an unlock.
     */
    var firmReadyAt: Long
        get() = prefs.getLong("firmReadyAt", 0L)
        set(v) = prefs.edit().putLong("firmReadyAt", v).apply()

    /** Seconds left in the Firm-lock wait, starting it if none is running. */
    fun firmWaitLeft(waitSec: Int, now: Long = System.currentTimeMillis()): Int {
        if (firmReadyAt == 0L) firmReadyAt = now + waitSec * 1000L
        return ((firmReadyAt - now + 999) / 1000).toInt().coerceAtLeast(0)
    }

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

    // ---------------------------------------------------------------- per-app budgets

    /** Optional limits for single apps, e.g. {"com.instagram.android": 20}. Stored as JSON. */
    val appBudgetsJson get() = prefs.getString("appBudgets", "{}") ?: "{}"

    fun appBudget(pkg: String): Int? {
        val o = try { JSONObject(appBudgetsJson) } catch (_: Exception) { return null }
        // TikTok has two package names; a budget set for either applies to both.
        val name = TargetApps.name(pkg)
        val key = o.keys().asSequence().firstOrNull { it == pkg || TargetApps.name(it) == name } ?: return null
        return o.optInt(key).takeIf { it > 0 }
    }

    fun appExtraToday(pkg: String): Int = prefs.getInt("extra_${pkg}_" + today(), 0)
    fun addAppExtraToday(pkg: String, n: Int) = prefs.edit().putInt("extra_${pkg}_" + today(), appExtraToday(pkg) + n).apply()

    fun appHardLockedUntil(pkg: String) = prefs.getLong("hardLockedUntil_$pkg", 0L)
    fun setAppHardLockedUntil(pkg: String, until: Long) = prefs.edit().putLong("hardLockedUntil_$pkg", until).apply()

    /** A Hard lock for one app, ending like a normal Hard lock. */
    fun startAppHardLock(pkg: String, now: Long = System.currentTimeMillis()): Long {
        val until = when (hardDuration) {
            "1h" -> now + 60 * 60_000L
            "3h" -> now + 3 * 60 * 60_000L
            else -> nextDayStart(now)
        }
        setAppHardLockedUntil(pkg, until)
        return until
    }

    /** Raising or removing an app's budget is loosening, so it's refused during a lock. */
    private fun loosensAppBudgets(newJson: String): Boolean {
        val old = try { JSONObject(appBudgetsJson) } catch (_: Exception) { JSONObject() }
        val new = try { JSONObject(newJson) } catch (_: Exception) { return true }
        for (key in old.keys()) {
            val before = old.optInt(key)
            val after = new.optInt(key, 0)
            if (before > 0 && (after == 0 || after > before)) return true
        }
        return false
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

    /** Back up day summaries and settings to the signed-in Google account. */
    val cloudBackup get() = prefs.getBoolean("cloudBackup", false)

    /** Last day already uploaded; days after it (and it, since it may have grown) are uploaded next time. */
    var lastBackupDay: String
        get() = prefs.getString("lastBackupDay", "") ?: ""
        set(v) = prefs.edit().putString("lastBackupDay", v).apply()

    /** The account [lastBackupDay] belongs to. Another account on this phone starts again from the first day. */
    var lastBackupUid: String
        get() = prefs.getString("lastBackupUid", "") ?: ""
        set(v) = prefs.edit().putString("lastBackupUid", v).apply()

    /** Squads the signed-in user belongs to; the counter syncs counts to each. */
    val squadIds: List<String> get() = prefs.getStringSet("squadIds", emptySet())!!.toList()

    fun isTracked(pkg: String) = pkg in tracked
    fun isPaused(now: Long = System.currentTimeMillis()) = now < pausedUntil

    fun today(now: Long = System.currentTimeMillis()) = dayKey(now, dayStartHour)

    /** Extra reels the user allowed themselves today with "5 more reels". */
    fun extraToday(): Int = prefs.getInt("extra_" + today(), 0)
    fun addExtraToday(n: Int) = prefs.edit().putInt("extra_" + today(), extraToday() + n).apply()
    fun allowanceToday() = budget + extraToday() + earnedToday()

    // ---------------------------------------------------------------- earn your reels

    val earnEnabled get() = prefs.getBoolean("earnEnabled", false)
    val stepsPerReward get() = prefs.getInt("stepsPerReward", 1000)
    val focusMinutes get() = prefs.getInt("focusMinutes", 25)
    val maxEarnPerDay get() = prefs.getInt("maxEarnPerDay", 30)

    fun earnedToday(): Int = prefs.getInt("earned_" + today(), 0)
    fun stepsToday(): Int = prefs.getInt("steps_" + today(), 0)

    /** Adds earned reels, capped at [maxEarnPerDay]. Returns how many were actually added. */
    private fun earn(reels: Int): Int {
        val add = reels.coerceAtMost(maxEarnPerDay - earnedToday()).coerceAtLeast(0)
        if (add > 0) prefs.edit().putInt("earned_" + today(), earnedToday() + add).apply()
        return add
    }

    /**
     * Feeds the phone's step counter (total steps since the phone started). Returns reels earned now.
     * The counter resets when the phone restarts, so only the increase since the last reading is used.
     */
    fun onStepCounter(total: Float): Int {
        val last = prefs.getFloat("lastStepCounter", -1f)
        prefs.edit().putFloat("lastStepCounter", total).apply()
        if (last < 0 || !earnEnabled) return 0
        val delta = if (total >= last) (total - last).toInt() else total.toInt()
        if (delta <= 0) return 0
        val steps = stepsToday() + delta
        prefs.edit().putInt("steps_" + today(), steps).apply()
        val given = prefs.getInt("stepRewards_" + today(), 0)
        val due = steps / stepsPerReward
        if (due <= given) return 0
        prefs.edit().putInt("stepRewards_" + today(), due).apply()
        return earn((due - given) * REWARD_REELS)
    }

    var focusUntil: Long
        get() = prefs.getLong("focusUntil", 0L)
        set(v) = prefs.edit().putLong("focusUntil", v).apply()

    fun isFocusing(now: Long = System.currentTimeMillis()) = now < focusUntil

    fun startFocus(minutes: Int = focusMinutes) { focusUntil = System.currentTimeMillis() + minutes * 60_000L }

    /** Giving up early earns nothing. */
    fun cancelFocus() { focusUntil = 0 }

    /** If a focus session has finished, grants its reward once. Returns reels earned. */
    fun settleFocus(now: Long = System.currentTimeMillis()): Int {
        val until = focusUntil
        if (until == 0L || now < until) return 0
        focusUntil = 0
        return if (earnEnabled) earn(REWARD_REELS) else 0
    }

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
        "cloudBackup" to cloudBackup,
        "earnEnabled" to earnEnabled,
        "stepsPerReward" to stepsPerReward,
        "focusMinutes" to focusMinutes,
        "maxEarnPerDay" to maxEarnPerDay,
        "earnedToday" to earnedToday(),
        "stepsToday" to stepsToday(),
        "focusUntil" to focusUntil,
        "rewardReels" to REWARD_REELS,
        "schedules" to schedulesJson,
        "appBudgets" to appBudgetsJson,
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
                    "appBudgets" -> if (loosensAppBudgets(v as String)) continue
                }
            }
            when (k) {
                KEY_TRACKED -> e.putStringSet(KEY_TRACKED, (v as List<*>).map { it.toString() }.toSet())
                "budget", "dwellSec", "dayStartHour", "intentWaitSec", "emergencyPerWeek",
                "stepsPerReward", "focusMinutes", "maxEarnPerDay" -> e.putInt(k as String, (v as Number).toInt())
                "earnEnabled" -> e.putBoolean("earnEnabled", v as Boolean)
                "cloudBackup" -> e.putBoolean("cloudBackup", v as Boolean)
                "lockMode", "hardDuration" -> e.putString(k as String, v as String)
                "schedules" -> if (keepsActiveSchedule(v as String)) e.putString("schedules", v)
                "appBudgets" -> e.putString("appBudgets", v as String)
                "squadIds" -> e.putStringSet("squadIds", (v as List<*>).map { it.toString() }.toSet())
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
        /** Supported apps that were installed at the last check, to spot newly installed ones. */
        private const val KEY_SEEN_INSTALLED = "seenInstalled"
        /** Reels earned per 1,000 steps (or per [stepsPerReward]) and per finished focus session. */
        const val REWARD_REELS = 10

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
