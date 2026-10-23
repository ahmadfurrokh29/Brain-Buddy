package com.brainbuddy.app.service

import android.accessibilityservice.AccessibilityService
import android.content.pm.ApplicationInfo
import android.graphics.Rect
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.text.format.DateFormat
import java.util.Date
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.brainbuddy.app.core.Config
import com.brainbuddy.app.core.CountBus
import com.brainbuddy.app.core.Db
import com.brainbuddy.app.core.CloudBackup
import com.brainbuddy.app.core.SquadSync
import com.brainbuddy.app.core.TargetApps
import com.brainbuddy.app.widget.BrainWidgetProvider

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
    private var curTexts: List<String>? = null
    private var curStart = 0L
    private var curDone = false
    private var curIsAd = false

    /** A swipe happened since the current reel started. Reels only change with a swipe (or auto-advance). */
    private var pendingScroll = false
    private var lastScrollAt = 0L
    private var lastFallbackPage = 0L

    /**
     * Per app: on how many different reels each text appeared. Texts seen on 3+ reels are buttons
     * and labels ("Dislike this video", the app's tabs…), not reel content, so they are ignored.
     */
    private val chrome = HashMap<String, HashMap<String, Int>>()
    /** Apps that show readable reel text. For these we never fall back to "one reel per swipe". */
    private val appsWithText = HashSet<String>()

    /** Reel number on screen as reported by the app's pager, and the number of the current reel. -1 = unknown. */
    private var pagerIndex = -1
    private var curIndex = -1
    /** Which list reported the number. Facebook's outer tab switcher reports its own numbers too. */
    private var pagerSource: String? = null
    private var curIndexSource: String? = null
    private var emptySince = 0L
    private var ticksInReels = 0
    private val debug by lazy { (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0 }
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
        updateStepListener()
        scheduleFocusEnd()
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
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED && isReelSwipe(event)) {
            pendingScroll = true
            lastScrollAt = lastEventAt
            // Pagers (Instagram, Facebook) report which reel number is on screen. YouTube reports -1.
            if (event.fromIndex >= 0 && event.fromIndex == event.toIndex) {
                pagerIndex = event.fromIndex
                pagerSource = event.className?.toString()
            }
        }
        // Reels screens send many events per second (video progress); look at the screen at most every 250 ms.
        scheduleEvaluate(250)
    }

    /**
     * Only a big view scrolling is a reel swipe. Small views scroll all the time on reels
     * (Instagram's sliding song title), and treating those as swipes delayed counting.
     */
    private fun isReelSwipe(event: AccessibilityEvent): Boolean {
        val source = event.source ?: return false
        val r = Rect()
        source.getBoundsInScreen(r)
        return r.height() >= resources.displayMetrics.heightPixels * 0.4
    }

    private fun scheduleEvaluate(delayMs: Long) {
        if (evalScheduled) return
        evalScheduled = true
        main.postDelayed(evaluateRunnable, delayMs)
    }

    private fun log(msg: String) {
        if (debug) Log.d(TAG, msg)
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        stepListener?.let { getSystemService(SensorManager::class.java)?.unregisterListener(it) }
        stepListener = null
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
        // Our own Firm-lock pop-up takes focus for typing; that isn't leaving the reels app.
        if (pkg == packageName) return
        val app = TargetApps.find(pkg)
        if (app == null || !config.isTracked(app.pkg) || config.isPaused()) {
            if (reelsPkg != null) leaveReels()
            return
        }
        refreshDay()
        root.getBoundsInScreen(screen)
        if (screen.isEmpty) resources.displayMetrics.let { screen.set(0, 0, it.widthPixels, it.heightPixels) }

        if (!ReelDetector.isReelsScreen(root, app, screen)) {
            if (reelsPkg != null) log("not a reels screen any more")
            if (reelsPkg != null) leaveReels()
            pendingScroll = false
            return
        }
        if (reelsPkg != app.pkg) enterReels(app.pkg)

        // Mid-swipe the screen shows two half reels. Wait until the swipe has settled.
        val now = System.currentTimeMillis()
        val sinceScroll = now - lastScrollAt
        if (sinceScroll < SETTLE_MS) {
            scheduleEvaluate(SETTLE_MS - sinceScroll + 20)
            return
        }

        val snap = ReelDetector.snapshot(root, app, screen)
        val texts = withoutChrome(app.pkg, snap.texts).take(8)
        if (texts.isNotEmpty()) emptySince = 0L
        if (texts.isNotEmpty()) {
            val cur = curTexts
            if (cur != null) {
                val overlap = ReelDetector.overlap(cur, texts)
                // Same reel if at least half its texts are still there (a caption expanding or
                // "Use this sound" popping up keeps the rest). Mostly different texts are a new reel,
                // even without a swipe event: YouTube, Snapchat and Reddit don't always send one.
                val sameReel = overlap >= 0.5
                if (sameReel) {
                    if (snap.isAd) curIsAd = true
                    if (pendingScroll && now - lastScrollAt < SWIPE_RECHECK_MS) {
                        // Swiped, but the app still shows the old reel's texts (YouTube swaps them in late
                        // and sends no event when it does). Keep looking until the new reel shows up.
                        scheduleEvaluate(250)
                        return
                    }
                    if (pendingScroll) log("swipe but same reel (overlap=$overlap) now=${texts.take(3)}")
                    pendingScroll = false
                    return
                }
            }
            appsWithText.add(app.pkg)
            learnChrome(app.pkg, snap.texts)
            startReel(ReelDetector.key(texts), texts, snap.isAd)
        } else if ((app.showsText && curKey == null) ||
            (waitingForText(now) && (app.showsText || app.pkg in appsWithText || curKey == null))
        ) {
            // Just opened the app: the first reel always gets its caption, never a guessed count.
            // The reel is still loading its caption. Look again shortly instead of guessing.
            if (pendingScroll && now - emptySince < 300) log("waiting for texts, raw=${snap.texts.take(4)}")
            scheduleEvaluate(300)
            return
        } else if (curKey == null || (pendingScroll && now - lastFallbackPage > 800)) {
            // The app shows no readable text: fall back to one reel per swipe.
            lastFallbackPage = now
            fallbackCounter++
            startReel("swipe-$now-$fallbackCounter", null, snap.isAd)
        }
        pendingScroll = false
    }

    /**
     * Gives a reel time to show its caption before falling back to "one reel per swipe":
     * a short wait after a swipe (the user is clearly on a new reel), longer when entering an app.
     */
    private fun waitingForText(now: Long): Boolean {
        if (emptySince == 0L) emptySince = now
        val limit = if (pendingScroll) SWIPE_TEXT_WAIT_MS else TEXT_WAIT_MS
        return now - emptySince < limit
    }

    private fun withoutChrome(pkg: String, texts: List<String>): List<String> {
        val seen = chrome[pkg] ?: return texts
        return texts.filter { (seen[it] ?: 0) < CHROME_MIN_REELS }
    }

    private fun learnChrome(pkg: String, texts: List<String>) {
        val seen = chrome.getOrPut(pkg) { HashMap() }
        if (seen.size > 3000) seen.clear()
        for (t in texts) seen[t] = (seen[t] ?: 0) + 1
    }

    private fun startReel(key: String, texts: List<String>?, isAd: Boolean) {
        log("new reel $key ad=$isAd swipe=$pendingScroll index=$pagerIndex texts=${texts?.take(3)}")
        finishReel()
        recordFlownPastReels()
        val now = System.currentTimeMillis()
        // The reel appeared when the swipe ended, not when its caption finished loading
        // (YouTube fades its texts in ~1.5 s later). The watch time runs from the swipe.
        val shownSince = if (pendingScroll && now - lastScrollAt < MAX_TEXT_DELAY_MS) lastScrollAt else now
        curKey = key
        curTexts = texts
        curStart = shownSince
        curDone = false
        curIsAd = isAd
        main.removeCallbacks(watchCheck)
        main.postDelayed(watchCheck, (config.dwellSec * 1000L - (now - shownSince)).coerceAtLeast(0))
    }

    /**
     * A very fast flick can pass reels before their caption is ever read. When the app reports reel
     * numbers (e.g. 41 → 45), the reels in between (42, 43, 44) were seen for a split second: skimmed.
     */
    private fun recordFlownPastReels() {
        val pkg = reelsPkg ?: return
        val from = curIndex
        val sameList = curIndexSource == pagerSource
        curIndex = pagerIndex
        curIndexSource = pagerSource
        if (from < 0 || pagerIndex < 0 || !sameList) return
        val missed = pagerIndex - from - 1
        if (missed <= 0) return
        // Cap it: a jump of dozens means the app reloaded its list, not that the user flew past them.
        if (missed > MAX_FLOWN_PAST) return
        for (i in from + 1 until pagerIndex) {
            val key = "pass-$pkg-$i-${System.currentTimeMillis()}"
            counted.add(key)
            db.insertEvent(day, pkg, key, "skimmed")
        }
        log("flown past $missed reels ($from → $pagerIndex), saved as skimmed")
        CountBus.emit()
    }

    /** Called when the user moves on from a reel: if it never reached the watch time, it was skimmed. */
    private fun finishReel() {
        val key = curKey ?: return
        val pkg = reelsPkg ?: return
        val shown = System.currentTimeMillis() - curStart
        // With "Ignore ads" off, ads are treated like any other reel, so a quickly skipped ad is skimmed too.
        val ignoredAd = curIsAd && config.ignoreAds
        if (!curDone && !ignoredAd && shown > 300 && key !in counted) {
            log("skimmed $key after ${shown}ms")
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
            if (config.ignoreAds) { log("ad ignored $key"); db.insertEvent(day, pkg, key, "ad"); return }
        }
        if (key in counted) {
            // Skimmed earlier and now watched properly: upgrade instead of counting twice.
            if (!db.upgradeSkimmed(day, key)) { log("already counted $key"); return }
            log("upgraded skim to watched $key")
        } else {
            counted.add(key)
            db.insertEvent(day, pkg, key, "watched")
            log("WATCHED $key")
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
        SquadSync.sync(this)
        CloudBackup.backup(this)
        enforceLimits()
    }

    // ---------------------------------------------------------------- entering / leaving reels

    private fun enterReels(pkg: String) {
        log("enter reels $pkg")
        finishReel()
        reelsPkg = pkg
        curTexts = null
        pendingScroll = false
        pagerIndex = -1
        curIndex = -1
        pagerSource = null
        curIndexSource = null
        val watched = db.watchedCount(day)
        val allowance = config.allowanceToday()
        if (config.floatingCounter) overlays.showCounter(watched, allowance)
        val now = System.currentTimeMillis()
        when {
            enforceLimits() -> {}
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
        log("leave reels $reelsPkg")
        finishReel()
        main.removeCallbacks(watchCheck)
        flushTime()
        reelsPkg = null
        overlays.hideAll()
    }

    // ---------------------------------------------------------------- limits and locks

    /**
     * Shows the right lock screen if reels aren't allowed right now (only the reels screen is covered;
     * messages, stories and the rest of the app still work). Returns true when a lock is showing.
     */
    private fun enforceLimits(): Boolean {
        if (overlays.isLockShowing) return true
        val now = System.currentTimeMillis()
        config.settleFocus(now)
        if (config.isFocusing(now)) {
            showFocusLock()
            return true
        }
        config.activeSchedule(now)?.let { s ->
            showScheduleLock(s)
            return true
        }
        endExpiredHardLock(now)
        // A budget Hard lock only makes sense while the budget is used up. Reels earned by walking or
        // focusing (or any extra) can raise the limit after the lock started: then the lock lifts.
        if (config.isHardLocked(now) && db.watchedCount(day) < config.allowanceToday()) {
            config.hardLockedUntil = 0
            db.insertUnlock(day, "hard_lifted_by_earned")
        }
        if (config.isHardLocked(now)) {
            showHardLock()
            return true
        }
        val watched = db.watchedCount(day)
        val allowance = config.allowanceToday()
        if (watched < allowance) return enforceAppLimit(now)
        overlays.hideIntent()
        when (config.lockMode) {
            "firm" -> overlays.showFirmLock(
                watched, allowance, config.firmWaitLeft(FIRM_WAIT_SEC),
                onClose = { safe("lockClose") { goHome() } },
                onUnlock = { reason -> safe("firmUnlock") { config.firmReadyAt = 0; allowMore(5, "firm", reason) } },
            )
            "hard" -> {
                config.startHardLock(now)
                db.insertUnlock(day, "hard_start")
                showHardLock()
            }
            else -> overlays.showGentleLock(
                watched, allowance,
                onClose = { safe("lockClose") { goHome() } },
                onMore = { safe("gentleMore") { allowMore(5, "gentle_plus5") } },
            )
        }
        return true
    }

    /** The app's own budget (e.g. Instagram 20), using the same lock style but only for that app. */
    private fun enforceAppLimit(now: Long): Boolean {
        val pkg = reelsPkg ?: return false
        val name = TargetApps.name(pkg)
        val until = config.appHardLockedUntil(pkg)
        if (until in 1..now) {
            config.setAppHardLockedUntil(pkg, 0)
            if (config.today(until - 1) == config.today(now)) config.addAppExtraToday(pkg, 5)
        }
        if (now < config.appHardLockedUntil(pkg)) {
            showAppHardLock(pkg, name)
            return true
        }
        val limit = config.appBudget(pkg) ?: return false
        val samePkgs = TargetApps.all.filter { it.name == name }.map { it.pkg }
        val appWatched = db.watchedCount(day, samePkgs)
        val appAllowance = limit + config.appExtraToday(pkg)
        if (appWatched < appAllowance) return false
        overlays.hideIntent()
        when (config.lockMode) {
            "firm" -> overlays.showFirmLock(
                appWatched, appAllowance, config.firmWaitLeft(FIRM_WAIT_SEC), appName = name,
                onClose = { safe("lockClose") { goHome() } },
                onUnlock = { reason -> safe("appFirm") { config.firmReadyAt = 0; allowMoreInApp(pkg, 5, "app_firm", reason) } },
            )
            "hard" -> {
                config.startAppHardLock(pkg, now)
                db.insertUnlock(day, "app_hard_start", name)
                showAppHardLock(pkg, name)
            }
            else -> overlays.showGentleLock(
                appWatched, appAllowance, appName = name,
                onClose = { safe("lockClose") { goHome() } },
                onMore = { safe("appGentle") { allowMoreInApp(pkg, 5, "app_gentle_plus5") } },
            )
        }
        return true
    }

    private fun showAppHardLock(pkg: String, name: String) {
        val until = config.appHardLockedUntil(pkg)
        val time = DateFormat.getTimeFormat(this).format(Date(until))
        val whenText = if (config.today(until - 1) == config.today()) "until $time" else "until $time tomorrow"
        overlays.showHardLock(
            "$name reels are locked",
            "You reached your $name limit. Its reels stay locked $whenText. Other apps, messages and stories still work.",
            config.emergencyLeft(),
            onClose = { safe("lockClose") { goHome() } },
            onEmergency = {
                safe("appEmergency") {
                    config.useEmergency()
                    config.setAppHardLockedUntil(pkg, 0)
                    allowMoreInApp(pkg, EMERGENCY_REELS, "app_emergency")
                }
            },
        )
    }

    private fun allowMoreInApp(pkg: String, reels: Int, kind: String, reason: String? = null) {
        config.addAppExtraToday(pkg, reels)
        db.insertUnlock(day, kind, reason ?: TargetApps.name(pkg))
        CountBus.emit()
    }

    private fun showHardLock() {
        val until = config.hardLockedUntil
        val time = DateFormat.getTimeFormat(this).format(Date(until))
        val whenText = if (config.today(until - 1) == config.today()) "until $time" else "until $time tomorrow"
        overlays.showHardLock(
            "Reels are locked",
            "You reached your reel limit. Reels stay locked $whenText. Messages and stories still work.",
            config.emergencyLeft(),
            onClose = { safe("lockClose") { goHome() } },
            onEmergency = {
                safe("emergency") {
                    config.useEmergency()
                    config.hardLockedUntil = 0
                    allowMore(EMERGENCY_REELS, "emergency")
                }
            },
        )
    }

    private fun showFocusLock() {
        overlays.hideIntent()
        val time = DateFormat.getTimeFormat(this).format(Date(config.focusUntil))
        overlays.showHardLock(
            "Focus time",
            "You're in a focus session until $time. Finish it to earn ${Config.REWARD_REELS} reels.",
            emergencyLeft = 0,
            onClose = { safe("lockClose") { goHome() } },
            onEmergency = null,
        )
    }

    private val focusEnd = Runnable {
        safe("focusEnd") {
            val earned = config.settleFocus()
            if (earned > 0) notifier.earned(earned, "focusing")
            if (overlays.isLockShowing && !config.isFocusing()) recheckLock()
            CountBus.emit()
        }
    }

    /** Wakes up when a focus session ends to give its reward, even if no reel app is open. */
    private fun scheduleFocusEnd() {
        main.removeCallbacks(focusEnd)
        val left = config.focusUntil - System.currentTimeMillis()
        if (config.focusUntil > 0) main.postDelayed(focusEnd, left.coerceAtLeast(0) + 500)
    }

    // ---------------------------------------------------------------- steps

    private var stepListener: SensorEventListener? = null

    /** Listens to the phone's step counter while "Earn your reels" is on. Uses almost no battery. */
    private fun updateStepListener() {
        val sensors = getSystemService(SensorManager::class.java) ?: return
        val wanted = config.earnEnabled
        if (wanted && stepListener == null) {
            val sensor = sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) ?: return
            val listener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    safe("steps") {
                        val earned = config.onStepCounter(event.values[0])
                        if (earned > 0) {
                            notifier.earned(earned, "walking")
                            if (reelsPkg != null && config.floatingCounter) overlays.updateCounter(db.watchedCount(day), config.allowanceToday())
                            BrainWidgetProvider.refresh(this@ReelCounterService)
                            if (overlays.isLockShowing) recheckLock()
                        }
                        CountBus.emit()
                    }
                }
                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            sensors.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            stepListener = listener
        } else if (!wanted && stepListener != null) {
            sensors.unregisterListener(stepListener)
            stepListener = null
        }
    }

    private fun showScheduleLock(s: Config.ActiveSchedule) {
        overlays.hideIntent()
        val time = DateFormat.getTimeFormat(this).format(Date(s.until))
        overlays.showHardLock(
            "${s.name}: reels are off",
            "Your ${s.name.lowercase()} schedule blocks reels until $time. Messages and stories still work.",
            config.emergencyLeft(),
            onClose = { safe("lockClose") { goHome() } },
            onEmergency = {
                safe("scheduleEmergency") {
                    config.useEmergency()
                    config.snoozeSchedule(s)
                    db.insertUnlock(day, "schedule_emergency", s.name)
                    CountBus.emit()
                }
            },
        )
    }

    /** Earned reels may have lifted the limit: take the lock down and show it again only if still needed. */
    private fun recheckLock() {
        overlays.hideLock()
        if (reelsPkg != null) enforceLimits()
    }

    /** A 1 h / 3 h Hard lock that ended during the same day gives 5 more reels, then locks again at the new limit. */
    private fun endExpiredHardLock(now: Long) {
        val until = config.hardLockedUntil
        if (until == 0L || now < until) return
        config.hardLockedUntil = 0
        if (config.today(until - 1) == config.today(now)) allowMore(5, "hard_timeout")
    }

    private fun allowMore(reels: Int, kind: String, reason: String? = null) {
        config.addExtraToday(reels)
        db.insertUnlock(day, kind, reason)
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
        if (activePkg == packageName) return // our Firm-lock pop-up has focus
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
        // A schedule can start, or a Hard lock end, while the user is already watching reels.
        if (++ticksInReels % 30 == 0) enforceLimits()
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
            // A new day: the finished day's final numbers go to the backup.
            if (day.isNotEmpty()) {
                CloudBackup.backup(this, force = true)
                if (java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_WEEK) == java.util.Calendar.MONDAY) notifier.receiptReady()
            }
            day = today
            counted.clear()
            counted.addAll(db.countedKeys(day))
        }
    }

    /** Called by the app after "Delete all data" or a restore, so in-memory state matches the database. */
    fun reload() {
        day = ""
        refreshDay()
        updateStepListener()
        scheduleFocusEnd()
        BrainWidgetProvider.refresh(this)
    }

    companion object {
        private const val INTENT_COOLDOWN_MS = 10 * 60 * 1000L
        private const val FIRM_WAIT_SEC = 60
        private const val EMERGENCY_REELS = 10
        /** Time after the last scroll event before the screen is read (a swipe animation is ~300 ms). */
        private const val SETTLE_MS = 400L
        private const val TEXT_WAIT_MS = 3000L
        private const val SWIPE_TEXT_WAIT_MS = 1500L
        private const val MAX_FLOWN_PAST = 10
        /** After a swipe, how long to keep looking for the new reel before deciding the swipe bounced back. */
        private const val SWIPE_RECHECK_MS = 2500L
        /** Longest gap between a swipe and its reel's caption appearing that still counts from the swipe. */
        private const val MAX_TEXT_DELAY_MS = 4000L
        /** A text seen on this many different reels is treated as a button/label, not reel content. */
        private const val CHROME_MIN_REELS = 3

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
