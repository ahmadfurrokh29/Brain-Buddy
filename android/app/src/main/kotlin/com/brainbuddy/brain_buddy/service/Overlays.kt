package com.brainbuddy.brain_buddy.service

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
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.brainbuddy.brain_buddy.core.Mood

/**
 * Pop-ups drawn over the reel apps. They use the accessibility overlay window type,
 * so no extra "draw over other apps" permission is needed.
 */
class Overlays(private val ctx: Context) {
    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    private var counter: LinearLayout? = null
    private var counterBrain: BrainView? = null
    private var counterText: TextView? = null
    private var counterParams: WindowManager.LayoutParams? = null
    private var lastWatched = -1
    private val positions = ctx.getSharedPreferences("bb_overlay", Context.MODE_PRIVATE)
    private var lock: View? = null
    private var intent: View? = null
    private var breathing: ValueAnimator? = null

    val isLockShowing get() = lock != null
    val isIntentShowing get() = intent != null

    // ---------------------------------------------------------------- floating counter

    /** Bubble with the animated brain and today's count. The user can drag it anywhere; the spot is remembered. */
    fun showCounter(watched: Int, budget: Int) {
        if (counter == null) {
            val brain = BrainView(ctx).apply { deep = true }
            val text = TextView(ctx).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(INK)
            }
            val bubble = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(4), dp(3), dp(12), dp(3))
                elevation = dp(4).toFloat()
                addView(brain, LinearLayout.LayoutParams(dp(38), dp(38)))
                addView(text, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { leftMargin = dp(2) })
            }
            val metrics = ctx.resources.displayMetrics
            val lp = baseParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.START
                x = positions.getInt("x", metrics.widthPixels - dp(132))
                y = positions.getInt("y", dp(96))
            }
            enableDragging(bubble, lp)
            if (!add(bubble, lp)) return
            counter = bubble
            counterBrain = brain
            counterText = text
            counterParams = lp
            lastWatched = -1
        }
        updateCounter(watched, budget)
    }

    fun updateCounter(watched: Int, budget: Int) {
        val bubble = counter ?: return
        val mood = Mood.of(watched, budget)
        counterBrain?.mood = mood
        counterText?.text = "$watched/$budget"
        // A light, slightly see-through shade of the brain's colour, so the stronger-coloured brain stands
        // out against it, with a border in the brain's darker outline colour.
        bubble.background = GradientDrawable().apply {
            cornerRadius = dp(28).toFloat()
            setColor(towardWhite(mood.top, 0.75f, alpha = 235))
            setStroke(dp(2), mood.outline)
        }
        if (lastWatched in 0 until watched) counterBrain?.poke()
        lastWatched = watched
    }

    fun hideCounter() {
        counter?.let { remove(it) }
        counter = null
        counterBrain = null
        counterText = null
        counterParams = null
    }

    /** Mixes [color] with white by [amount] (0 = unchanged, 1 = white). */
    private fun towardWhite(color: Int, amount: Float, alpha: Int): Int {
        fun mix(c: Int) = (c + (255 - c) * amount).toInt()
        return Color.argb(alpha, mix(Color.red(color)), mix(Color.green(color)), mix(Color.blue(color)))
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
        actions.addView(button("5 more reels", primary = false) { hideLock(); onMore() }.withTop(8))
        if (!add(root, baseParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))) return
        lock = root
        // One full breath before the buttons appear.
        revealLater(actions, 8000)
    }

    /** Firm lock: wait [waitSec] seconds, then type why you want more reels to unlock 5. */
    fun showFirmLock(watched: Int, budget: Int, waitSec: Int, appName: String? = null, onClose: () -> Unit, onUnlock: (String) -> Unit) {
        if (lock != null) return
        val (root, actions) = lockScreen(Mood.MELTED, "Reel limit reached", limitMessage(watched, budget, appName), breathing = true)
        val countdown = text("", 15f, color = GREY)
        val reason = EditText(ctx).apply {
            hint = "Why do you want more reels?"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(INK)
            setHintTextColor(GREY)
            minWidth = dp(260)
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(Color.WHITE); setStroke(dp(1), MINT) }
            visibility = View.GONE
        }
        val unlock = button("Unlock 5 reels", primary = false) {
            val typed = reason.text.toString().trim()
            if (typed.length >= MIN_REASON) { hideLock(); onUnlock(typed) }
        }.apply { alpha = 0.4f; visibility = View.GONE }
        reason.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(e: Editable?) { unlock.alpha = if ((e?.trim()?.length ?: 0) >= MIN_REASON) 1f else 0.4f }
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
        })
        actions.addView(countdown)
        actions.addView(reason.withTop(8))
        actions.addView(unlock.withTop(10))
        actions.addView(button("Close app", primary = true) { hideLock(); onClose() }.withTop(10))
        actions.visibility = View.VISIBLE

        // Focusable so the keyboard can type the reason.
        val lp = baseParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT).apply {
            flags = flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN
        }
        if (!add(root, lp)) return
        lock = root

        var left = waitSec
        val ticker = object : Runnable {
            override fun run() {
                if (lock !== root) return
                if (left > 0) {
                    countdown.text = "You can ask for more reels in $left s"
                    left--
                    main.postDelayed(this, 1000)
                } else {
                    countdown.text = "Type at least $MIN_REASON characters to unlock 5 more reels."
                    reason.visibility = View.VISIBLE
                    unlock.visibility = View.VISIBLE
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
            emergency = button("Emergency unlock ($emergencyLeft left this week)", primary = false) {
                if (!armed) {
                    armed = true
                    emergency.text = "Tap again to use it. This can't be undone."
                    emergency.setTextColor(CORAL)
                } else {
                    hideLock(); onEmergency()
                }
            }
            actions.addView(emergency.withTop(10))
        }
        actions.visibility = View.VISIBLE
        if (!add(root, baseParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))) return
        lock = root
    }

    fun hideLock() {
        breathing?.cancel()
        breathing = null
        lock?.let { remove(it) }
        lock = null
    }

    /** Shared layout for all lock screens: brain, title, message, optional breathing circle, actions area. */
    private fun lockScreen(mood: Mood, title: String, message: String, breathing: Boolean): Pair<LinearLayout, LinearLayout> {
        val root = column(MINT_LIGHT)
        root.addView(BrainView(ctx).apply { this.mood = mood }, LinearLayout.LayoutParams(dp(120), dp(120)))
        root.addView(text(title, 26f, bold = true).withTop(12))
        root.addView(text(message, 16f, color = GREY).withTop(8))
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
        } else {
            root.addView(View(ctx), LinearLayout.LayoutParams(1, dp(36)))
        }
        val actions = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.INVISIBLE
        }
        root.addView(actions)
        return root to actions
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

        if (!add(root, baseParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))) return
        intent = root
        main.postDelayed({ buttons.visibility = View.VISIBLE; buttons.alpha = 0f; buttons.animate().alpha(1f).start() }, waitSec * 1000L)
    }

    fun hideIntent() {
        intent?.let { remove(it) }
        intent = null
    }

    fun hideAll() { hideCounter(); hideLock(); hideIntent() }

    // ---------------------------------------------------------------- helpers

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
        private const val MIN_REASON = 10
    }
}
