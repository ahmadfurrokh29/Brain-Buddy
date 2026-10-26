package com.brainbean.app.core

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * All counting data, stored only on the phone.
 *
 * events     – one row per reel: watched / skimmed / ad
 * time_spent – milliseconds spent on reel screens per app per day
 * unlocks    – each "5 more reels" after the limit
 * intents    – answers to "Why are you here?"
 */
class Db private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "brain_buddy.db", null, 3) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT NOT NULL, ts INTEGER NOT NULL, pkg TEXT NOT NULL, k TEXT NOT NULL, kind TEXT NOT NULL)")
        db.execSQL("CREATE INDEX events_day ON events(day)")
        db.execSQL("CREATE TABLE time_spent(day TEXT NOT NULL, pkg TEXT NOT NULL, ms INTEGER NOT NULL, PRIMARY KEY(day, pkg))")
        db.execSQL("CREATE TABLE unlocks(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT NOT NULL, ts INTEGER NOT NULL, kind TEXT NOT NULL, reason TEXT)")
        db.execSQL("CREATE TABLE intents(id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT NOT NULL, ts INTEGER NOT NULL, pkg TEXT NOT NULL, reason TEXT NOT NULL)")
        createImportedDays(db)
    }

    /** Day summaries restored from cloud backup, for days with no reels recorded on this phone. */
    private fun createImportedDays(db: SQLiteDatabase) =
        db.execSQL("CREATE TABLE IF NOT EXISTS imported_days(day TEXT PRIMARY KEY, json TEXT NOT NULL)")

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // v2: Firm lock stores the reason the user typed.
        if (oldVersion < 2) db.execSQL("ALTER TABLE unlocks ADD COLUMN reason TEXT")
        // v3: cloud backup restores day summaries.
        if (oldVersion < 3) createImportedDays(db)
    }

    fun insertEvent(day: String, pkg: String, key: String, kind: String) {
        writableDatabase.insert("events", null, ContentValues().apply {
            put("day", day); put("ts", System.currentTimeMillis()); put("pkg", pkg); put("k", key); put("kind", kind)
        })
    }

    /** A reel first skimmed and later watched properly becomes a watched reel. */
    fun upgradeSkimmed(day: String, key: String): Boolean {
        val cv = ContentValues().apply { put("kind", "watched") }
        return writableDatabase.update("events", cv, "day = ? AND k = ? AND kind = 'skimmed'", arrayOf(day, key)) > 0
    }

    fun addTime(day: String, pkg: String, ms: Long) {
        // Plain UPDATE-then-INSERT: "ON CONFLICT DO UPDATE" needs SQLite 3.24, which Android 9 and older don't have.
        val w = writableDatabase
        w.beginTransaction()
        try {
            w.execSQL("UPDATE time_spent SET ms = ms + ? WHERE day = ? AND pkg = ?", arrayOf<Any>(ms, day, pkg))
            w.execSQL("INSERT OR IGNORE INTO time_spent(day, pkg, ms) VALUES(?, ?, ?)", arrayOf<Any>(day, pkg, ms))
            w.setTransactionSuccessful()
        } finally {
            w.endTransaction()
        }
    }

    fun insertUnlock(day: String, kind: String, reason: String? = null) {
        writableDatabase.insert("unlocks", null, ContentValues().apply {
            put("day", day); put("ts", System.currentTimeMillis()); put("kind", kind); put("reason", reason)
        })
    }

    fun insertIntent(day: String, pkg: String, reason: String) {
        writableDatabase.insert("intents", null, ContentValues().apply {
            put("day", day); put("ts", System.currentTimeMillis()); put("pkg", pkg); put("reason", reason)
        })
    }

    /** Reels watched on [day]: on this phone, plus any restored from cloud backup for that day. */
    fun watchedCount(day: String): Int {
        val local = readableDatabase.rawQuery("SELECT COUNT(*) FROM events WHERE day = ? AND kind = 'watched'", arrayOf(day)).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        return local + (importedSummary(day)?.get("watched") as? Int ?: 0)
    }

    /** Watched reels over several days (e.g. this week, for Squads). */
    fun watchedCount(days: List<String>): Int {
        if (days.isEmpty()) return 0
        val marks = days.joinToString(",") { "?" }
        val local = readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM events WHERE kind = 'watched' AND day IN ($marks)", days.toTypedArray(),
        ).use { if (it.moveToFirst()) it.getInt(0) else 0 }
        return local + days.sumOf { importedSummary(it)?.get("watched") as? Int ?: 0 }
    }

    /** Reels watched today in one app (both TikTok package names count as one app). */
    fun watchedCount(day: String, pkgs: Collection<String>): Int {
        if (pkgs.isEmpty()) return 0
        val marks = pkgs.joinToString(",") { "?" }
        return readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM events WHERE day = ? AND kind = 'watched' AND pkg IN ($marks)",
            arrayOf(day, *pkgs.toTypedArray()),
        ).use { if (it.moveToFirst()) it.getInt(0) else 0 }
    }

    /** Keys of reels already counted today, so the same reel never counts twice. */
    fun countedKeys(day: String): Set<String> {
        val out = HashSet<String>()
        readableDatabase.rawQuery("SELECT k FROM events WHERE day = ?", arrayOf(day)).use {
            while (it.moveToNext()) out.add(it.getString(0))
        }
        return out
    }

    fun daySummary(day: String): Map<String, Any> {
        val apps = LinkedHashMap<String, MutableMap<String, Any>>()
        fun app(pkg: String) = apps.getOrPut(pkg) {
            mutableMapOf("pkg" to pkg, "name" to TargetApps.name(pkg), "watched" to 0, "skimmed" to 0, "ms" to 0L)
        }
        var watched = 0; var skimmed = 0; var ads = 0; var ms = 0L
        val hours = IntArray(24)
        val cal = Calendar.getInstance()
        val r = readableDatabase
        r.rawQuery("SELECT pkg, kind, ts FROM events WHERE day = ?", arrayOf(day)).use {
            while (it.moveToNext()) {
                val pkg = it.getString(0)
                when (it.getString(1)) {
                    "watched" -> {
                        watched++
                        app(pkg)["watched"] = (app(pkg)["watched"] as Int) + 1
                        cal.timeInMillis = it.getLong(2)
                        hours[cal.get(Calendar.HOUR_OF_DAY)]++
                    }
                    "skimmed" -> { skimmed++; app(pkg)["skimmed"] = (app(pkg)["skimmed"] as Int) + 1 }
                    "ad" -> ads++
                }
            }
        }
        r.rawQuery("SELECT pkg, ms FROM time_spent WHERE day = ?", arrayOf(day)).use {
            while (it.moveToNext()) {
                val t = it.getLong(1)
                ms += t
                app(it.getString(0))["ms"] = t
            }
        }
        val unlocks = r.rawQuery("SELECT COUNT(*) FROM unlocks WHERE day = ?", arrayOf(day)).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
        val intents = HashMap<String, Int>()
        r.rawQuery("SELECT reason, COUNT(*) FROM intents WHERE day = ? GROUP BY reason", arrayOf(day)).use {
            while (it.moveToNext()) intents[it.getString(0)] = it.getInt(1)
        }
        // Restored from cloud backup for this day (another phone, or before a reinstall): added on top of what
        // this phone counted since. Restores only fill days this phone had no data for, so nothing counts twice.
        importedSummary(day)?.let { imp ->
            watched += imp["watched"] as? Int ?: 0
            skimmed += imp["skimmed"] as? Int ?: 0
            ads += imp["ads"] as? Int ?: 0
            ms += (imp["ms"] as? Number)?.toLong() ?: 0L
            (imp["hours"] as? List<*>)?.forEachIndexed { h, n -> if (h < 24) hours[h] += (n as? Number)?.toInt() ?: 0 }
            (imp["apps"] as? List<*>)?.forEach { a ->
                val m = a as? Map<*, *> ?: return@forEach
                val pkg = m["pkg"] as? String ?: return@forEach
                val app = app(pkg)
                app["watched"] = (app["watched"] as Int) + ((m["watched"] as? Int) ?: 0)
                app["skimmed"] = (app["skimmed"] as Int) + ((m["skimmed"] as? Int) ?: 0)
                app["ms"] = (app["ms"] as Long) + ((m["ms"] as? Number)?.toLong() ?: 0L)
            }
        }
        return mapOf(
            "day" to day, "watched" to watched, "skimmed" to skimmed, "ads" to ads, "ms" to ms,
            "unlocks" to unlocks, "apps" to apps.values.toList(), "hours" to hours.toList(), "intents" to intents,
        )
    }

    // ---------------------------------------------------------------- cloud backup

    /** Days with reels counted on this phone itself (restored days not included). */
    fun localDayCount(): Int =
        readableDatabase.rawQuery("SELECT COUNT(*) FROM (SELECT DISTINCT day FROM events UNION SELECT DISTINCT day FROM time_spent)", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }

    /** Every day that has anything recorded, here or restored. */
    fun daysWithData(): List<String> {
        val out = sortedSetOf<String>()
        readableDatabase.rawQuery("SELECT DISTINCT day FROM events UNION SELECT DISTINCT day FROM time_spent UNION SELECT day FROM imported_days", null).use {
            while (it.moveToNext()) out.add(it.getString(0))
        }
        return out.toList()
    }

    fun importedSummary(day: String): Map<String, Any>? =
        readableDatabase.rawQuery("SELECT json FROM imported_days WHERE day = ?", arrayOf(day)).use {
            if (it.moveToFirst()) jsonToMap(JSONObject(it.getString(0))) else null
        }

    /** Saves day summaries from cloud backup (a JSON array of daySummary maps). Returns how many. */
    fun importSummaries(json: String): Int {
        val list = JSONArray(json)
        // Days this phone already counted keep this phone's numbers: the backup may be this phone's own
        // (restoring after it already uploaded), so adding it would count those reels twice.
        val local = HashSet<String>()
        readableDatabase.rawQuery("SELECT DISTINCT day FROM events UNION SELECT DISTINCT day FROM time_spent", null).use {
            while (it.moveToNext()) local.add(it.getString(0))
        }
        var count = 0
        val w = writableDatabase
        w.beginTransaction()
        try {
            for (i in 0 until list.length()) {
                val o = list.getJSONObject(i)
                val day = o.getString("day")
                if (day in local) continue
                w.execSQL("INSERT OR REPLACE INTO imported_days(day, json) VALUES(?, ?)", arrayOf<Any>(day, o.toString()))
                count++
            }
            w.setTransactionSuccessful()
        } finally {
            w.endTransaction()
        }
        return count
    }

    private fun jsonToMap(o: JSONObject): Map<String, Any> {
        val out = LinkedHashMap<String, Any>()
        for (k in o.keys()) out[k] = jsonValue(o.get(k)) ?: continue
        return out
    }

    private fun jsonValue(v: Any?): Any? = when (v) {
        is JSONObject -> jsonToMap(v)
        is JSONArray -> (0 until v.length()).mapNotNull { jsonValue(v.get(it)) }
        JSONObject.NULL -> null
        is Long -> if (v in Int.MIN_VALUE..Int.MAX_VALUE) v.toInt() else v
        else -> v
    }

    /**
     * Habits over [days] (keys "yyyy-MM-dd"), for trigger insights:
     * heat = 7×24 watched reels by weekday (Mon first) and hour, first reel time of each day,
     * reasons from "Why are you here?", and reasons typed into Firm locks.
     */
    fun patterns(days: List<String>): Map<String, Any> {
        if (days.isEmpty()) return emptyMap()
        val heat = IntArray(7 * 24)
        val firstReel = HashMap<String, Int>() // day -> minutes after midnight
        val cal = Calendar.getInstance()
        val marks = days.joinToString(",") { "?" }
        val r = readableDatabase
        r.rawQuery("SELECT day, ts FROM events WHERE kind = 'watched' AND day IN ($marks) ORDER BY ts", days.toTypedArray()).use {
            while (it.moveToNext()) {
                cal.timeInMillis = it.getLong(1)
                val weekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 // Mon=0 … Sun=6
                val hour = cal.get(Calendar.HOUR_OF_DAY)
                heat[weekday * 24 + hour]++
                firstReel.putIfAbsent(it.getString(0), hour * 60 + cal.get(Calendar.MINUTE))
            }
        }
        for (d in days) { // restored days add their hours on top, like daySummary
            val hours = importedSummary(d)?.get("hours") as? List<*> ?: continue
            cal.time = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).parse(d)!!
            val weekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7
            hours.forEachIndexed { h, n -> if (h < 24) heat[weekday * 24 + h] += (n as? Number)?.toInt() ?: 0 }
        }
        val intents = HashMap<String, Int>()
        r.rawQuery("SELECT reason, COUNT(*) FROM intents WHERE day IN ($marks) GROUP BY reason", days.toTypedArray()).use {
            while (it.moveToNext()) intents[it.getString(0)] = it.getInt(1)
        }
        val firmReasons = ArrayList<String>()
        r.rawQuery("SELECT reason FROM unlocks WHERE kind IN ('firm','app_firm') AND reason IS NOT NULL AND day IN ($marks) ORDER BY ts DESC LIMIT 20", days.toTypedArray()).use {
            while (it.moveToNext()) firmReasons.add(it.getString(0))
        }
        return mapOf("heat" to heat.toList(), "firstReel" to firstReel.values.toList(), "intents" to intents, "firmReasons" to firmReasons)
    }

    /** Every counted reel as a spreadsheet: day, time, app, watched/skimmed/ad. Opens in Excel or Google Sheets. */
    fun exportCsv(): String {
        val out = StringBuilder("day,time,app,result\n")
        val cal = Calendar.getInstance()
        readableDatabase.rawQuery("SELECT day, ts, pkg, kind FROM events ORDER BY ts", null).use {
            while (it.moveToNext()) {
                cal.timeInMillis = it.getLong(1)
                val time = "%02d:%02d".format(cal.get(Calendar.HOUR_OF_DAY), cal.get(Calendar.MINUTE))
                out.append(it.getString(0)).append(',').append(time).append(',')
                    .append(TargetApps.name(it.getString(2))).append(',').append(it.getString(3)).append('\n')
            }
        }
        return out.toString()
    }

    fun exportJson(config: Map<String, Any>): String {
        val root = JSONObject()
        root.put("format", "brain_buddy_backup")
        root.put("version", 1)
        root.put("createdAt", System.currentTimeMillis())
        root.put("config", JSONObject(config))
        for (table in TABLES) {
            val rows = JSONArray()
            readableDatabase.rawQuery("SELECT * FROM $table", null).use { c ->
                while (c.moveToNext()) {
                    val row = JSONObject()
                    for (i in 0 until c.columnCount) {
                        if (c.getColumnName(i) == "id") continue
                        when (c.getType(i)) {
                            android.database.Cursor.FIELD_TYPE_INTEGER -> row.put(c.getColumnName(i), c.getLong(i))
                            else -> row.put(c.getColumnName(i), c.getString(i))
                        }
                    }
                    rows.put(row)
                }
            }
            root.put(table, rows)
        }
        return root.toString()
    }

    /** Replaces all data with a backup. Returns the backup's config so it can be restored too. */
    fun importJson(json: String): Map<String, Any?> {
        val root = JSONObject(json)
        require(root.optString("format") == "brain_buddy_backup") { "Not a Brain Bean backup file" }
        val w = writableDatabase
        w.beginTransaction()
        try {
            for (table in TABLES) {
                w.delete(table, null, null)
                val rows = root.optJSONArray(table) ?: continue
                for (i in 0 until rows.length()) {
                    val row = rows.getJSONObject(i)
                    val cv = ContentValues()
                    for (key in row.keys()) {
                        when (val v = row.get(key)) {
                            is Number -> cv.put(key, v.toLong())
                            else -> cv.put(key, v.toString())
                        }
                    }
                    w.insert(table, null, cv)
                }
            }
            w.setTransactionSuccessful()
        } finally {
            w.endTransaction()
        }
        val cfg = root.optJSONObject("config") ?: return emptyMap()
        val out = HashMap<String, Any?>()
        for (key in cfg.keys()) {
            val v = cfg.get(key)
            out[key] = if (v is JSONArray) (0 until v.length()).map { v.getString(it) } else v
        }
        return out
    }

    fun clearAll() {
        val w = writableDatabase
        for (table in TABLES) w.delete(table, null, null)
    }

    companion object {
        private val TABLES = listOf("events", "time_spent", "unlocks", "intents", "imported_days")

        @Volatile private var instance: Db? = null
        fun get(context: Context): Db = instance ?: synchronized(this) {
            instance ?: Db(context).also { instance = it }
        }
    }
}
