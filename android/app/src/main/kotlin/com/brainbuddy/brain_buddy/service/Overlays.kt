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

    fun showLock(watched: Int, budget: Int, onClose: () -> Unit, onMore: () -> Unit) {
        if (lock != null) return
        val root = column(MINT_LIGHT)

        root.addView(text("🧠😴", 64f, bold = false))
        root.addView(text("Time for a brain break", 26f, bold = true).withTop(12))
        root.addView(text("You've watched $watched reels today. Your goal was $budget.", 16f, color = GREY).withTop(8))

        val circleBox = FrameLayout(ctx)
        val circle = View(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(MINT) }
            alpha = 0.85f
        }
        circleBox.addView(circle, FrameLayout.LayoutParams(dp(150), dp(150), Gravity.CENTER))
        val breathLabel = text("Breathe in…", 18f, bold = true, color = Color.WHITE)
        circleBox.addView(breathLabel, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        root.addView(circleBox, LinearLayout.LayoutParams(dp(200), dp(200)).apply { topMargin = dp(28); bottomMargin = dp(28) })

        val buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.INVISIBLE
        }
        buttons.addView(button("Close app", primary = true) { hideLock(); onClose() })
        buttons.addView(button("5 more reels", primary = false) { hideLock(); onMore() }.withTop(8))
        root.addView(buttons)

        if (!add(root, baseParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))) return
        lock = root

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
                    breathLabel.text = if (inhale) "Breathe in…" else "Breathe out…"
                }
            })
            start()
        }
        // One full breath before the buttons appear.
        main.postDelayed({ buttons.visibility = View.VISIBLE; buttons.alpha = 0f; buttons.animate().alpha(1f).start() }, 8000)
    }

    fun hideLock() {
        breathing?.cancel()
        breathing = null
        lock?.let { remove(it) }
        lock = null
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
    }
}
