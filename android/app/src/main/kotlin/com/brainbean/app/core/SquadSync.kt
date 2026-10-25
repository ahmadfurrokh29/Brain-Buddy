package com.brainbuddy.app.core

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Sends this week's reel count to every Squad the user is in. Runs from the background counter,
 * so friends see fresh numbers even if the user never opens Brain Buddy (BrainPal's "friend shows 0").
 * Only counts are shared: never which reels, apps or times.
 */
object SquadSync {
    private const val MIN_GAP_MS = 60_000L
    private var lastSync = 0L

    /** Squads the user joined, saved by the app after sign-in. */
    fun squadIds(config: Config): List<String> = config.squadIds

    fun sync(context: Context, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastSync < MIN_GAP_MS) return
        val config = Config(context)
        val ids = squadIds(config)
        val user = try { FirebaseAuth.getInstance().currentUser } catch (_: Exception) { null } ?: return
        if (ids.isEmpty()) return
        lastSync = now

        val db = Db.get(context)
        val today = config.today(now)
        val thisWeek = weekDays(today)
        val lastWeek = fullWeekFrom(shift(thisWeek.first(), -7))
        val data = hashMapOf<String, Any>(
            "weekKey" to thisWeek.first(),
            "weekWatched" to db.watchedCount(thisWeek),
            "todayWatched" to db.watchedCount(today),
            "prevWeekKey" to lastWeek.first(),
            "prevWeekWatched" to db.watchedCount(lastWeek),
            "updatedAt" to FieldValue.serverTimestamp(),
        )
        val firestore = FirebaseFirestore.getInstance()
        for (id in ids) {
            firestore.collection("squads").document(id).collection("members").document(user.uid)
                .set(data, SetOptions.merge())
                .addOnFailureListener { Log.w("BrainBuddy", "Squad sync failed for $id: ${it.message}") }
        }
    }

    /** Monday … [today] of the week containing [today] (day keys "yyyy-MM-dd"). */
    fun weekDays(today: String): List<String> {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val c = Calendar.getInstance().apply { time = fmt.parse(today)!! }
        val back = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 // days since Monday
        c.add(Calendar.DAY_OF_YEAR, -back)
        return (0..back).map { fmt.format(c.time).also { _ -> c.add(Calendar.DAY_OF_YEAR, 1) } }
    }

    /** The 7 days starting at [monday]. */
    private fun fullWeekFrom(monday: String): List<String> = (0 until 7).map { shift(monday, it) }

    private fun shift(day: String, days: Int): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val c = Calendar.getInstance().apply { time = fmt.parse(day)!!; add(Calendar.DAY_OF_YEAR, days) }
        return fmt.format(c.time)
    }
}
