package com.brainbean.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.brainbean.app.MainActivity
import com.brainbean.app.R
import com.brainbean.app.core.Config
import com.brainbean.app.core.Db
import com.brainbean.app.core.Mood

/** Home-screen widget: today's reel count and Brain Bean's mood. Reads the database directly. */
class BrainWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, build(context)) }
    }

    companion object {
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, BrainWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = build(context)
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun build(context: Context): RemoteViews {
            val config = Config(context)
            val watched = Db.get(context).watchedCount(config.today())
            val allowance = config.allowanceToday()
            val mood = Mood.of(watched, allowance)
            val open = PendingIntent.getActivity(
                context, 1, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return RemoteViews(context.packageName, R.layout.brain_widget).apply {
                setTextViewText(R.id.widget_emoji, "🧠" + mood.emoji)
                setTextViewText(R.id.widget_count, "$watched / $allowance")
                setTextViewText(R.id.widget_label, "reels today • ${mood.label}")
                setOnClickPendingIntent(R.id.widget_root, open)
            }
        }
    }
}
