package com.brainbean.app.core

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions

/**
 * Backs up day summaries (counts, minutes, per-app numbers, busiest hours) and settings to the signed-in
 * Google account, so history comes back on a new phone. Individual reels are never uploaded.
 * Guest accounts are skipped: they can't be signed into on another phone.
 */
object CloudBackup {
    private const val MIN_GAP_MS = 30 * 60_000L
    /** A phone with this many days of its own history isn't fresh: its settings are the user's real ones. */
    private const val ESTABLISHED_DAYS = 3
    private var lastRun = 0L

    fun backup(context: Context, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastRun < MIN_GAP_MS) return
        val config = Config(context)
        if (!config.cloudBackup) return
        val user = try { FirebaseAuth.getInstance().currentUser } catch (_: Exception) { null } ?: return
        if (user.isAnonymous) return
        lastRun = now

        val db = Db.get(context)
        val today = config.today(now)
        // First time for this account: everything. Afterwards: from the last uploaded day (it may have grown) to today.
        val from = if (config.lastBackupUid == user.uid) config.lastBackupDay else ""
        val days = db.daysWithData().filter { from.isEmpty() || it >= from } + today
        val userDoc = FirebaseFirestore.getInstance().collection("users").document(user.uid)
        val settingsDoc = userDoc.collection("backup").document("settings")
        // Settings go up only once this phone's settings are the real ones: restored from the cloud, the
        // account has none saved yet, or this phone has its own history (it isn't a fresh phone).
        when {
            config.settingsSettledUid == user.uid || db.localDayCount() >= ESTABLISHED_DAYS -> {
                config.settingsSettledUid = user.uid
                upload(config, db, user.uid, userDoc, days, today, withSettings = true)
            }
            else -> settingsDoc.get()
                .addOnSuccessListener { snap ->
                    if (!snap.exists()) config.settingsSettledUid = user.uid
                    upload(config, db, user.uid, userDoc, days, today, withSettings = !snap.exists())
                }
                .addOnFailureListener { Log.w("BrainBuddy", "Cloud backup: could not check settings: ${it.message}") }
        }
    }

    private fun upload(
        config: Config,
        db: Db,
        uid: String,
        userDoc: com.google.firebase.firestore.DocumentReference,
        days: List<String>,
        today: String,
        withSettings: Boolean,
    ) {
        val batch = FirebaseFirestore.getInstance().batch()
        var writes = 0
        for (day in days.distinct()) {
            val summary = db.daySummary(day)
            if ((summary["watched"] as Int) == 0 && (summary["skimmed"] as Int) == 0 && (summary["ms"] as Number).toLong() == 0L) continue
            batch.set(userDoc.collection("days").document(day), summary + ("updatedAt" to FieldValue.serverTimestamp()))
            if (++writes >= 400) break // stay under Firestore's 500-writes-per-batch limit; the rest goes next time
        }
        if (withSettings) {
            batch.set(userDoc.collection("backup").document("settings"), mapOf("config" to config.toMap(), "updatedAt" to FieldValue.serverTimestamp()), SetOptions.merge())
        }
        Log.i("BrainBuddy", "Cloud backup: $writes days, settings ${if (withSettings) "included" else "kept as they are in the cloud"}")
        batch.commit()
            .addOnSuccessListener {
                if (writes < 400) {
                    config.lastBackupDay = today
                    config.lastBackupUid = uid
                }
            }
            .addOnFailureListener { Log.w("BrainBuddy", "Cloud backup failed: ${it.message}") }
    }
}
