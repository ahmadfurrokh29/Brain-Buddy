package com.brainbuddy.brain_buddy.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.brainbuddy.brain_buddy.MainActivity
import com.brainbuddy.brain_buddy.R
import com.brainbuddy.brain_buddy.core.Config

/** Budget warnings (50% / 80% / 100%). Each level fires at most once a day. */
class Notifier(private val ctx: Context, private val config: Config) {

    init {
        val channel = NotificationChannel(CHANNEL, "Reel budget warnings", NotificationManager.IMPORTANCE_DEFAULT)
        channel.description = "Tells you when you are close to your daily reel budget"
        ctx.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun onCount(watched: Int, allowance: Int) {
        if (allowance <= 0) return
        val r = watched.toDouble() / allowance
        when {
            r >= 1.0 && config.warn100 && config.markWarned(100) ->
                show("Brain break time 🫠", "You reached your $allowance reels for today.")
            r >= 0.8 && r < 1.0 && config.warn80 && config.markWarned(80) ->
                show("Brain Buddy is getting tired 😪", "$watched of $allowance reels watched today.")
            r >= 0.5 && r < 0.8 && config.warn50 && config.markWarned(50) ->
                show("Halfway there 🙂", "$watched of $allowance reels watched today.")
        }
    }

    /** "You earned 10 reels by walking 🚶" */
    fun earned(reels: Int, how: String) = show("You earned $reels reels 🎉", "Nice $how! They're added to today's budget.")

    private fun show(title: String, body: String) {
        val nm = NotificationManagerCompat.from(ctx)
        if (!nm.areNotificationsEnabled()) return
        val open = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_brain)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try { nm.notify(title.hashCode(), n) } catch (_: SecurityException) {}
    }

    companion object { private const val CHANNEL = "budget" }
}
