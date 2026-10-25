package com.brainbean.app.service

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.brainbean.app.core.Mood

/**
 * Pop-ups drawn over the reel apps. They use the accessibility overlay window type,
 * so no extra "draw over other apps" permission is needed.
 */
class Overlays(private val ctx: Context) {
    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    private var counter: LinearLayout? = null
    private var counterBrain: BrainView? = null
    private var counterNumber: FrameLayout? = null
    private var counterParams: WindowManager.LayoutParams? = null
    private var lastWatched = -1
    private val closeMouth = Runnable { counterBrain?.closeMouth() }
    private val positions = ctx.getSharedPreferences("bb_overlay", Context.MODE_PRIVATE)
    private var lock: View? = null
    private var intent: View? = null
    private var breathing: ValueAnimator? = null

    val isLockShowing get() = lock != null
    val isIntentShowing get() = intent != null

    // ---------------------------------------------------------------- floating counter

    /**
     * The brain on its own with today's count under it. It opens its mouth when a new reel comes up and
     * gulps when the reel counts. The user can drag it anywhere; the spot is remembered.
     */
    fun showCounter(watched: Int, budget: Int) {
        if (counter == null) {
            val brain = BrainView(ctx).apply { shadow = true }
            // The number flies up into the brain's mouth, outside its own box, so nothing may clip it.
            val number = FrameLayout(ctx).apply { clipChildren = false; clipToPadding = false }
            val column = LinearLayout(ctx).apply {
                clipChildren = false
                clipToPadding = false
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(4), dp(2), dp(4), dp(2))
                addView(brain, LinearLayout.LayoutParams(dp(44), dp(44)))
                addView(number, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(20)))
            }
            val metrics = ctx.resources.displayMetrics
            val lp = baseParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.START
                x = positions.getInt("x", metrics.widthPixels - dp(76))
                y = positions.getInt("y", dp(96))
            }
            enableDragging(column, lp)
            if (!add(column, lp)) return
            counter = column
            counterBrain = brain
            counterNumber = number
            counterParams = lp
            lastWatched = -1
        }
        updateCounter(watched, budget)
    }

    fun updateCounter(watched: Int, budget: Int) {
        counter ?: return
        counterBrain?.mood = Mood.of(watched, budget)
        val counted = lastWatched in 0 until watched
        if (counted) main.removeCallbacks(closeMouth)
        setNumber("$watched/$budget", eat = counted)
        lastWatched = watched
    }

    /**
     * A new reel came up: the brain opens its mouth. If the reel isn't counted within [waitMs]
     * (skipped too fast, or an ad), the mouth closes again without a gulp.
     */
    fun counterSawSwipe(waitMs: Long) {
        val brain = counterBrain ?: return
        brain.openMouth()
        main.removeCallbacks(closeMouth)
        main.postDelayed(closeMouth, waitMs)
    }

    /**
     * Shows the count under the brain. [eat]: the brain eats the old number. It flies up into the open mouth,
     * shrinking like something moving far away; the mouth shuts as it arrives, then the new number pops in.
     */
    private fun setNumber(text: String, eat: Boolean) {
        val box = counterNumber ?: return
        val brain = counterBrain
        // Already showing (or eating its way to) this number: a repeat refresh must not cut the animation short.
        if ((box.getChildAt(box.childCount - 1) as? TextView)?.text == text) return
        // A new count arriving mid-animation: finish the previous one at once.
        while (box.childCount > 1) box.getChildAt(0).let { it.animate().cancel(); box.removeView(it) }
        val old = box.getChildAt(0) as? TextView
        val label = TextView(ctx).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            // Dark outline-like shadow keeps the white number readable on any video.
            setShadowLayer(dp(3).toFloat(), 0f, dp(1).toFloat(), Color.argb(200, 0, 0, 0))
        }
        box.addView(label, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        if (old == null || !eat || brain == null) {
            old?.let { box.removeView(it) }
            brain?.takeIf { eat }?.gulp()
            return
        }
        brain.openMouth() // in case the swipe wasn't seen
        // From the number's centre up to the mouth (61% down the brain).
        val numberCentre = box.top + box.height / 2f
        val mouth = brain.top + brain.height * 0.61f
        old.animate()
            .translationY(mouth - numberCentre)
            .scaleX(0.08f).scaleY(0.08f)
            .alpha(0.2f)
            .setDuration(EAT_MS)
            .setInterpolator(AccelerateInterpolator(1.4f))
            .withEndAction {
                box.removeView(old)
                brain.gulp()
            }
            .start()
        // The new number grows from tiny to full size, the opposite of the old one being eaten.
        label.alpha = 0f
        label.scaleX = 0.1f
        label.scaleY = 0.1f
        label.animate().alpha(1f).scaleX(1f).scaleY(1f)
            .setStartDelay(EAT_MS - 60).setDuration(GROW_MS)
            .setInterpolator(DecelerateInterpolator(1.4f))
            .start()
    }

    fun hideCounter() {
        main.removeCallbacks(closeMouth)
        counter?.let { remove(it) }
        counter = null
        counterBrain = null
        counterNumber = null
        counterParams = null
    }

    private fun enableDragging(view: View, lp: WindowManager.LayoutParams) {
        var startX = 0; var startY = 0
        var downX = 0f; var downY = 0f
        var moved = false
        view.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x; startY = lp.y
                    downX = e.rawX; downY = e.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX; val dy = e.rawY - downY
                    if (!moved && dx * dx + dy * dy > dp(6) * dp(6)) moved = true
                    if (moved) {
                        val metrics = ctx.resources.displayMetrics
                        lp.x = (startX + dx).toInt().coerceIn(0, (metrics.widthPixels - v.width).coerceAtLeast(0))
                        lp.y = (startY + dy).toInt().coerceIn(0, (metrics.heightPixels - v.height).coerceAtLeast(0))
                        try { wm.updateViewLayout(v, lp) } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (moved) positions.edit().putInt("x", lp.x).putInt("y", lp.y).apply()
                    else counterBrain?.poke() // a tap makes the brain wobble
                    true
                }
                else -> false
            }
        }
    }

    // ---------------------------------------------------------------- lock screen (Gentle)

    /** Gentle lock: a breathing break, then "Close app" or "5 more reels". */
    fun showGentleLock(watched: Int, budget: Int, appName: String? = null, onClose: () -> Unit, onMore: () -> Unit) {
        if (lock != null) return
        val (root, actions) = lockScreen(Mood.MELTED, "Time for a brain break", limitMessage(watched, budget, appName), breathing = true)
        actions.addView(button("Close app", primary = true) { hideLock(); onClose() })
        actions.addView(button("5 more reels", primary = false) { gentleReadyAt = 0; hideLock(); onMore() }.withTop(8))
        if (!add(root, lockParams())) return
        lock = root
        quietMedia()
        // One full breath before the buttons appear. Leaving and coming back doesn't start the breath over.
        val now = System.currentTimeMillis()
        if (gentleReadyAt == 0L || now - gentleReadyAt > GENTLE_FORGET_MS) gentleReadyAt = now + GENTLE_BREATH_MS
        val wait = gentleReadyAt - now
        if (wait <= 0) actions.visibility = View.VISIBLE else revealLater(actions, wait)
    }

    /** When the current Gentle lock's buttons appear (0 = no Gentle lock started). */
    private var gentleReadyAt = 0L

    /**
     * Firm lock: wait [waitSec] seconds, then "Write a reason for 5 more" opens Brain Bean's reason screen
     * ([onAskReason]). Typing happens there, in a normal app screen, because Samsung phones draw the navigation
     * buttons invisible when a pop-up like this one has the keyboard.
     */
    fun showFirmLock(watched: Int, budget: Int, waitSec: Int, appName: String? = null, onClose: () -> Unit, onAskReason: () -> Unit) {
        if (lock != null) return
        val parts = lockScreen(Mood.MELTED, "Reel limit reached", limitMessage(watched, budget, appName), breathing = true)
        val (root, actions) = parts
        val countdown = text("", 15f, color = GREY)
        val ask = button("Write a reason for 5 more", primary = false) { hideLock(); onAskReason() }
            .apply { visibility = View.GONE }
        actions.addView(countdown.withTop(12))
        actions.addView(ask.withTop(10))
        actions.addView(button("Close app", primary = true) { hideLock(); onClose() }.withTop(10))
        actions.visibility = View.VISIBLE
        if (!add(root, lockParams())) return
        lock = root
        quietMedia()

        var left = waitSec
        val ticker = object : Runnable {
            override fun run() {
                if (lock !== root) return
                if (left > 0) {
                    countdown.text = "You can ask for more reels in $left s"
                    left--
                    main.postDelayed(this, 1000)
                } else {
                    // The breathing circle is only for the wait; afterwards the buttons need the room.
                    parts.breath?.visibility = View.GONE
                    countdown.text = "Still want more? Tell yourself why."
                    ask.visibility = View.VISIBLE
                }
            }
        }
        main.post(ticker)
    }

    /** Hard lock: reels stay locked. Only "Close app", plus an emergency unlock if any are left this week. */
    fun showHardLock(title: String, message: String, emergencyLeft: Int, onClose: () -> Unit, onEmergency: (() -> Unit)?) {
        if (lock != null) return
        val (root, actions) = lockScreen(Mood.MELTED, title, message, breathing = false)
        actions.addView(button("Close app", primary = true) { hideLock(); onClose() })
        if (onEmergency != null && emergencyLeft > 0) {
            var armed = false
            lateinit var emergency: TextView
            emergency = button("Emergency unlock ($emergencyLeft left)", primary = false) {
                if (!armed) {
                    armed = true
                    emergency.text = "Tap again to confirm"
                    emergency.setTextColor(CORAL)
                } else {
                    hideLock(); onEmergency()
                }
            }
            actions.addView(emergency.withTop(10))
        }
        actions.visibility = View.VISIBLE
        if (!add(root, lockParams())) return
        lock = root
        quietMedia()
    }

    fun hideLock() {
        breathing?.cancel()
        breathing = null
        lock?.let { remove(it) }
        lock = null
        releaseMedia()
    }

    // ---------------------------------------------------------------- quieting the reel behind a lock

    private val audio = ctx.getSystemService(AudioManager::class.java)
    private var focusRequest: AudioFocusRequest? = null

    /**
     * Takes audio focus and sends "pause", so Instagram/YouTube stop playing the reel behind the lock
     * instead of looping it.
     */
    private fun quietMedia() {
        if (focusRequest != null) return
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setOnAudioFocusChangeListener { }
            .build()
        try {
            audio.requestAudioFocus(request)
            focusRequest = request
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE))
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE))
        } catch (_: Exception) {}
    }

    private fun releaseMedia() {
        focusRequest?.let { try { audio.abandonAudioFocusRequest(it) } catch (_: Exception) {} }
        focusRequest = null
    }

    /** Shared layout for all lock screens: brain, title, message, optional breathing circle, actions area. */
    private data class LockParts(val root: LinearLayout, val actions: LinearLayout, val brain: View, val message: View, val breath: View?)

    private fun lockScreen(mood: Mood, title: String, message: String, breathing: Boolean): LockParts {
        val root = column(MINT_LIGHT)
        val brain = BrainView(ctx).apply { this.mood = mood }
        root.addView(brain, LinearLayout.LayoutParams(dp(120), dp(120)))
        root.addView(text(title, 26f, bold = true).withTop(12))
        val messageView = text(message, 16f, color = GREY).withTop(8)
        root.addView(messageView)
        var breath: View? = null
        if (breathing) {
            val circleBox = FrameLayout(ctx)
            val circle = View(ctx).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(MINT) }
                alpha = 0.85f
            }
            circleBox.addView(circle, FrameLayout.LayoutParams(dp(130), dp(130), Gravity.CENTER))
            val label = text("Breathe in…", 17f, bold = true, color = Color.WHITE)
            circleBox.addView(label, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
            root.addView(circleBox, LinearLayout.LayoutParams(dp(170), dp(170)).apply { topMargin = dp(20); bottomMargin = dp(20) })
            startBreathing(circle, label)
            breath = circleBox
        } else {
            root.addView(View(ctx), LinearLayout.LayoutParams(1, dp(36)))
        }
        val actions = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.INVISIBLE
        }
        root.addView(actions)
        return LockParts(root, actions, brain, messageView, breath)
    }

    private fun startBreathing(circle: View, label: TextView) {
        var inhale = true
        breathing = ObjectAnimator.ofPropertyValuesHolder(
            circle,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 0.65f, 1f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 0.65f, 1f),
        ).apply {
            duration = 4000
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationRepeat(animation: Animator) {
                    inhale = !inhale
                    label.text = if (inhale) "Breathe in…" else "Breathe out…"
                }
            })
            start()
        }
    }

    private fun limitMessage(watched: Int, budget: Int, appName: String?) =
        if (appName == null) "You've watched $watched reels today. Your goal was $budget."
        else "You've watched $watched reels on $appName today. Your $appName limit was $budget."

    private fun revealLater(view: View, delayMs: Long) {
        main.postDelayed({ view.visibility = View.VISIBLE; view.alpha = 0f; view.animate().alpha(1f).start() }, delayMs)
    }

    // ---------------------------------------------------------------- intent pause

    fun showIntent(waitSec: Int, onReason: (String) -> Unit, onClose: () -> Unit) {
        if (intent != null) return
        val root = column(MINT_LIGHT)
        root.addView(text("🧠🤔", 64f, bold = false))
        root.addView(text("Why are you here?", 26f, bold = true).withTop(12))
        root.addView(text("Take a second. Opening reels on autopilot is how hours disappear.", 16f, color = GREY).withTop(8))

        val buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.INVISIBLE
        }
        for (reason in listOf("I'm bored", "I want to relax", "Looking for something")) {
            buttons.addView(button(reason, primary = false) { hideIntent(); onReason(reason) }.withTop(10))
        }
        buttons.addView(button("Close app", primary = true) { hideIntent(); onClose() }.withTop(18))
        root.addView(buttons, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(28) })

        if (!add(root, lockParams())) return
        intent = root
        main.postDelayed({ buttons.visibility = View.VISIBLE; buttons.alpha = 0f; buttons.animate().alpha(1f).start() }, waitSec * 1000L)
    }

    fun hideIntent() {
        intent?.let { remove(it) }
        intent = null
    }

    fun hideAll() { hideCounter(); hideLock(); hideIntent() }

    // ---------------------------------------------------------------- helpers

    /** Full-screen pop-up that stops above the navigation bar, so Back and Home always stay usable. */
    private fun lockParams() = WindowManager.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    )

    private fun baseParams(w: Int, h: Int) = WindowManager.LayoutParams(
        w, h,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT,
    )

    private fun add(v: View, lp: WindowManager.LayoutParams): Boolean =
        try { wm.addView(v, lp); true } catch (e: Exception) { false }

    private fun remove(v: View) {
        try { wm.removeView(v) } catch (_: Exception) {}
    }

    private fun column(bg: Int) = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setBackgroundColor(bg)
        setPadding(dp(28), dp(48), dp(28), dp(48))
        isClickable = true // swallow touches so the reel underneath can't be scrolled
        // After a key press (Back, Home) Android otherwise greys out the whole screen as a "focus" highlight.
        defaultFocusHighlightEnabled = false
    }

    private fun text(s: String, sp: Float, bold: Boolean = false, color: Int = INK) = TextView(ctx).apply {
        text = s
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun button(label: String, primary: Boolean, onClick: () -> Unit) = TextView(ctx).apply {
        text = label
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        minWidth = dp(240)
        setPadding(dp(24), dp(14), dp(24), dp(14))
        if (primary) {
            setTextColor(Color.WHITE)
            background = pill(MINT)
        } else {
            setTextColor(INK)
            background = pill(Color.WHITE)
        }
        defaultFocusHighlightEnabled = false
        setOnClickListener { onClick() }
    }

    private fun pill(color: Int) = GradientDrawable().apply {
        cornerRadius = dp(28).toFloat()
        setColor(color)
    }

    private fun <T : View> T.withTop(dpTop: Int): T = apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(dpTop) }
    }

    private fun dp(v: Int) = (v * ctx.resources.displayMetrics.density).toInt()

    companion object {
        val MINT = Color.parseColor("#2EC4A6")
        val MINT_LIGHT = Color.parseColor("#E3F8F3")
        val CORAL = Color.parseColor("#FF6B6B")
        val INK = Color.parseColor("#1B2430")
        val GREY = Color.parseColor("#5B6573")
        private const val GENTLE_BREATH_MS = 8000L
        /** How long the brain takes to eat the old number. */
        private const val EAT_MS = 500L
        /** How long the new number takes to grow in. */
        private const val GROW_MS = 350L
        private const val GENTLE_FORGET_MS = 30 * 60 * 1000L
    }
}
