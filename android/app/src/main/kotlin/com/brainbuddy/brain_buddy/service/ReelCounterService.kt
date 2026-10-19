package com.brainbuddy.brain_buddy.service

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.brainbuddy.brain_buddy.core.Config
import com.brainbuddy.brain_buddy.core.CountBus
import com.brainbuddy.brain_buddy.core.Db
import com.brainbuddy.brain_buddy.core.TargetApps
import com.brainbuddy.brain_buddy.widget.BrainWidgetProvider

/**
 * Counts reels.
 *
 * How a reel is counted:
 *  - Android tells us something scrolled or changed in a tracked app.
 *  - We check the reels screen is open and read the fingerprint of the reel on screen.
 *  - A new fingerprint starts a timer. If the reel is still there after the watch time
 *    (default 3 s) it counts as WATCHED; if the user flicks past first it is SKIMMED.
 *  - Ads and reels already counted today are never counted.
 */
class ReelCounterService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())
    private lateinit var config: Config
    private lateinit var db: Db
    private lateinit var overlays: Overlays
    private lateinit var notifier: Notifier

    /** Package of the app whose reels screen is open, or null. */
    private var reelsPkg: String? = null

    private var curKey: String? = null
    private var curTexts: Set<String>? = null
    private var curStart = 0L
    private var curDone = false
    private var curIsAd = false

    private var pendingScroll = false
    private var lastFallbackPage = 0L
    private var fallbackCounter = 0
    private var evalScheduled = false

    private var day = ""
    private val counted = HashSet<String>()
    private var unsavedMs = 0L
    private val screen = Rect()

    private val evaluateRunnable = Runnable { evalScheduled = false; safe("evaluate") { evaluate() } }
    private val watchCheck = Runnable { safe("watchTimer") { onWatchTimer() } }
    private val tick = object : Runnable {
        override fun run() {
            safe("tick") { onTick() }
            main.postDelayed(this, 1000)
        }
    }

    /**
     * An uncaught error inside an accessibility service kills it, while Android still shows it as "on".
     * Every entry point goes through here so one bad screen or database hiccup can't stop counting.
     */
    private inline fun safe(where: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e(TAG, "Error in $where", t)
            lastError = "$where: ${t.javaClass.simpleName}: ${t.message}"
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        config = Config(this)
        db = Db.get(this)
        overlays = Overlays(this)
        notifier = Notifier(this, config)
        refreshDay()
        instance = this
        lastEventAt = System.currentTimeMillis()
        main.post(tick)
        CountBus.emit()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) = safe("event") { onEvent(event) }

    private fun onEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (TargetApps.find(pkg) == null) return
        lastEventAt = System.currentTimeMillis()
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) pendingScroll = true
        // Reels screens send many events per second (video progress); look at the screen at most every 250 ms.
        if (!evalScheduled) {
            evalScheduled = true
            main.postDelayed(evaluateRunnable, 250)
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        if (::overlays.isInitialized) overlays.hideAll()
        flushTime()
        instance = null
        CountBus.emit()
        super.onDestroy()
    }

    // ---------------------------------------------------------------- core loop

    private fun evaluate() {
        val root = rootInActiveWindow ?: return
        val pkg = root.packageName?.toString()
        val app = TargetApps.find(pkg)
        if (app == null || !config.isTracked(app.pkg) || config.isPaused()) {
            if (reelsPkg != null) leaveReels()
            return
        }
        refreshDay()
        root.getBoundsInScreen(screen)
        if (screen.isEmpty) resources.displayMetrics.let { screen.set(0, 0, it.widthPixels, it.heightPixels) }

        if (!ReelDetector.isReelsScreen(root, app, screen)) {
            if (reelsPkg != null) leaveReels()
            pendingScroll = false
            return
        }
        if (reelsPkg != app.pkg) enterReels(app.pkg)

        val snap = ReelDetector.snapshot(root, screen)
        val now = System.currentTimeMillis()
        if (snap.texts.isNotEmpty()) {
            val same = curTexts?.let { ReelDetector.similar(it, snap.texts) } ?: false
            if (same) {
                if (snap.isAd) curIsAd = true
            } else {
                startReel(ReelDetector.key(snap.texts), snap.texts, snap.isAd)
            }
        } else if (curKey == null || (pendingScroll && now - lastFallbackPage > 800)) {
            // The app shows no readable text: fall back to one reel per swipe.
            lastFallbackPage = now
            fallbackCounter++
            startReel("swipe-$now-$fallbackCounter", null, snap.isAd)
        }
        pendingScroll = false
    }

    private fun startReel(key: String, texts: Set<String>?, isAd: Boolean) {
        finishReel()
        curKey = key
        curTexts = texts
        curStart = System.currentTimeMillis()
        curDone = false
        curIsAd = isAd
        main.removeCallbacks(watchCheck)
        main.postDelayed(watchCheck, config.dwellSec * 1000L)
    }

    /** Called when the user moves on from a reel: if it never reached the watch time, it was skimmed. */
    private fun finishReel() {
        val key = curKey ?: return
        val pkg = reelsPkg ?: return
        val shown = System.currentTimeMillis() - curStart
        if (!curDone && !curIsAd && shown > 300 && key !in counted) {
            counted.add(key)
            db.insertEvent(day, pkg, key, "skimmed")
            CountBus.emit()
        }
        curKey = null
        curTexts = null
    }

    private fun onWatchTimer() {
        val key = curKey ?: return
        val pkg = reelsPkg ?: return
        if (curDone) return
        curDone = true
        if (curIsAd) {
            if (config.ignoreAds) { db.insertEvent(day, pkg, key, "ad"); return }
        }
        if (key in counted) {
            // Skimmed earlier and now watched properly: upgrade instead of counting twice.
            if (!db.upgradeSkimmed(day, key)) return
        } else {
            counted.add(key)
            db.insertEvent(day, pkg, key, "watched")
        }
        afterCount()
    }

    private fun afterCount() {
        val watched = db.watchedCount(day)
        val allowance = config.allowanceToday()
        if (config.floatingCounter) overlays.updateCounter(watched, allowance)
        notifier.onCount(watched, allowance)
        BrainWidgetProvider.refresh(this)
        CountBus.emit()
        if (watched >= allowance) showLock(watched, allowance)
    }

    // ---------------------------------------------------------------- entering / leaving reels

    private fun enterReels(pkg: String) {
        finishReel()
        reelsPkg = pkg
        val watched = db.watchedCount(day)
        val allowance = config.allowanceToday()
        if (config.floatingCounter) overlays.showCounter(watched, allowance)
        val now = System.currentTimeMillis()
        when {
            watched >= allowance -> showLock(watched, allowance)
            config.intentPause && now - config.lastIntentAt > INTENT_COOLDOWN_MS -> {
                config.lastIntentAt = now
                overlays.showIntent(
                    config.intentWaitSec,
                    onReason = { reason -> safe("intentReason") { db.insertIntent(day, pkg, reason); CountBus.emit() } },
                    onClose = { safe("intentClose") { db.insertIntent(day, pkg, "Closed"); goHome() } },
                )
            }
        }
    }

    private fun leaveReels() {
        finishReel()
        main.removeCallbacks(watchCheck)
        flushTime()
        reelsPkg = null
        overlays.hideAll()
    }

    private fun showLock(watched: Int, allowance: Int) {
        if (overlays.isLockShowing) return
        overlays.hideIntent()
        overlays.showLock(
            watched, allowance,
            onClose = { safe("lockClose") { goHome() } },
            onMore = { safe("lockMore") { addFiveMore() } },
        )
    }

    private fun addFiveMore() {
        config.addExtraToday(5)
        db.insertUnlock(day, "gentle_plus5")
        if (config.floatingCounter) overlays.updateCounter(db.watchedCount(day), config.allowanceToday())
        CountBus.emit()
    }

    private fun goHome() {
        leaveReels()
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    // ---------------------------------------------------------------- every second

    private fun onTick() {
        val pkg = reelsPkg ?: return
        val now = System.currentTimeMillis()
        val activePkg = rootInActiveWindow?.packageName?.toString()
        if (activePkg != null && activePkg != pkg) {
            if (!evalScheduled) { evalScheduled = true; main.post(evaluateRunnable) }
            return
        }
        if (activePkg == null && now - lastEventAt > 8000) {
            leaveReels()
            return
        }
        if (config.isPaused()) { leaveReels(); return }
        unsavedMs += 1000
        if (unsavedMs >= 5000) flushTime()
    }

    private fun flushTime() {
        val pkg = reelsPkg
        if (unsavedMs > 0 && pkg != null && ::db.isInitialized) db.addTime(day, pkg, unsavedMs)
        unsavedMs = 0
    }

    private fun refreshDay() {
        val today = config.today()
        if (today != day) {
            flushTime()
            day = today
            counted.clear()
            counted.addAll(db.countedKeys(day))
        }
    }

    /** Called by the app after "Delete all data" or a restore, so in-memory state matches the database. */
    fun reload() {
        day = ""
        refreshDay()
        BrainWidgetProvider.refresh(this)
    }

    companion object {
        private const val INTENT_COOLDOWN_MS = 10 * 60 * 1000L

        @Volatile var instance: ReelCounterService? = null
            private set
        @Volatile var lastEventAt = 0L
            private set
        /** Last error caught by [safe], shown in the Reliability Doctor to help fix counting bugs. */
        @Volatile var lastError: String? = null
            private set
        private const val TAG = "BrainBuddy"
    }
}
