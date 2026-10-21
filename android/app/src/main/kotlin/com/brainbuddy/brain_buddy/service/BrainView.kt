package com.brainbuddy.brain_buddy.service

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import android.view.animation.LinearInterpolator
import com.brainbuddy.brain_buddy.core.Mood
import kotlin.math.PI
import kotlin.math.sin

/**
 * The Brain Buddy mascot for the floating counter. A native copy of lib/widgets/brain_buddy.dart
 * (same lobes, folds, faces and colours) because overlays over other apps can't run Flutter.
 */
class BrainView(context: Context) : View(context) {

    var mood: Mood = Mood.FRESH
        set(value) {
            if (field != value) { field = value; invalidate() }
        }

    /** Draw the brain in deeper shades, so it stands out on a light background (the floating counter). */
    var deep = false

    private var phase = 0f
    private var bounce = 0f

    private val idle = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 4000
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { phase = it.animatedValue as Float; invalidate() }
    }
    private val bounceAnim = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 600
        addUpdateListener { bounce = it.animatedValue as Float; invalidate() }
    }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
    private val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = INK }
    private val oval = RectF()

    /** Wobble once, like when a reel is counted. */
    fun poke() = bounceAnim.start()

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        idle.start()
    }

    override fun onDetachedFromWindow() {
        idle.cancel()
        bounceAnim.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        val s = minOf(width, height).toFloat()
        if (s <= 0) return
        val bob = sin(phase * 2 * PI).toFloat() * 0.02f
        val wobble = if (bounce == 0f || bounce == 1f) 0f else sin(bounce * PI * 4).toFloat() * (1 - bounce) * 0.08f
        val melted = mood == Mood.MELTED

        canvas.save()
        canvas.translate(s / 2, s / 2 + bob * s + if (melted) s * 0.04f else 0f)
        canvas.scale(1 + wobble, (1 - wobble) * if (melted) 0.9f else 1f)
        canvas.translate(-s / 2, -s / 2)

        val body = bodyPath(s)
        val top = if (deep) mood.body else mood.top
        val bottom = if (deep) blend(mood.body, mood.outline, 0.45f) else mood.body
        fill.shader = LinearGradient(0f, 0f, 0f, s, top, bottom, Shader.TileMode.CLAMP)
        canvas.drawPath(body, fill)
        fill.shader = null
        if (melted) drips(canvas, s)
        stroke.color = mood.outline
        stroke.strokeWidth = s * 0.03f
        canvas.drawPath(body, stroke)

        folds(canvas, s)
        face(canvas, s)
        canvas.restore()
    }

    private fun bodyPath(s: Float): Path {
        val path = Path()
        for (l in LOBES) {
            val p = Path().apply { addCircle(l[0] * s, l[1] * s, l[2] * s, Path.Direction.CW) }
            path.op(p, Path.Op.UNION)
        }
        return path
    }

    private fun drips(canvas: Canvas, s: Float) {
        fill.color = mood.body
        for (d in DRIPS) {
            val x = d[0] * s; val y = d[1] * s; val w = d[2] * s; val h = d[3] * s
            oval.set(x - w / 2, y - h * 0.3f, x + w / 2, y + h * 0.7f)
            canvas.drawRoundRect(oval, w / 2, w / 2, fill)
            canvas.drawCircle(x, y + h * 0.7f - w / 2, w * 0.62f, fill)
        }
    }

    private fun folds(canvas: Canvas, s: Float) {
        stroke.color = withAlpha(mood.outline, 0.55f)
        stroke.strokeWidth = s * 0.022f
        canvas.drawLine(s * 0.5f, s * 0.14f, s * 0.5f, s * 0.33f, stroke)
        arc(canvas, s, 0.30f, 0.30f, 0.07f, 198f, 144f)
        arc(canvas, s, 0.70f, 0.30f, 0.07f, 198f, 144f)
        arc(canvas, s, 0.17f, 0.52f, 0.06f, 270f, 126f)
        arc(canvas, s, 0.83f, 0.52f, 0.06f, 144f, 126f)
    }

    private fun arc(canvas: Canvas, s: Float, x: Float, y: Float, r: Float, start: Float, sweep: Float) {
        oval.set((x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s)
        canvas.drawArc(oval, start, sweep, false, stroke)
    }

    private fun face(canvas: Canvas, s: Float) {
        val lx = s * 0.40f; val rx = s * 0.60f; val ey = s * 0.50f
        val eyeR = s * 0.05f
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = INK; style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeWidth = s * 0.03f
        }

        // Cheeks.
        fill.color = withAlpha(Color.parseColor("#FF6F91"), if (mood == Mood.FRESH) 0.45f else 0.25f)
        oval.set(s * 0.265f, s * 0.555f, s * 0.355f, s * 0.605f); canvas.drawOval(oval, fill)
        oval.set(s * 0.645f, s * 0.555f, s * 0.735f, s * 0.605f); canvas.drawOval(oval, fill)

        val blink = blinkAmount()
        for (x in floatArrayOf(lx, rx)) {
            when (mood) {
                Mood.FRESH, Mood.OKAY -> openEye(canvas, x, ey, eyeR, 1 - blink)
                Mood.TIRED -> {
                    openEye(canvas, x, ey, eyeR, 0.45f * (1 - blink))
                    canvas.drawLine(x - eyeR * 1.1f, ey - eyeR * 0.1f, x + eyeR * 1.1f, ey - eyeR * 0.1f, line)
                }
                Mood.FRIED -> {
                    line.strokeWidth = s * 0.02f
                    oval.set(x - eyeR, ey - eyeR, x + eyeR, ey + eyeR); canvas.drawArc(oval, 0f, 288f, false, line)
                    val r2 = eyeR * 0.45f
                    oval.set(x - r2, ey - r2, x + r2, ey + r2); canvas.drawArc(oval, 180f, 270f, false, line)
                    line.strokeWidth = s * 0.03f
                }
                Mood.MELTED -> {
                    oval.set(x - eyeR, ey - eyeR, x + eyeR, ey + eyeR); canvas.drawArc(oval, 6f, 168f, false, line)
                }
            }
        }

        val mx = s * 0.5f; val my = s * 0.61f
        when (mood) {
            Mood.FRESH -> {
                val p = Path().apply {
                    moveTo(mx - s * 0.07f, my - s * 0.01f)
                    quadTo(mx, my + s * 0.08f, mx + s * 0.07f, my - s * 0.01f)
                    close()
                }
                canvas.drawPath(p, ink)
            }
            Mood.OKAY -> { oval.set(mx - s * 0.05f, my - s * 0.03f, mx + s * 0.05f, my + s * 0.03f); canvas.drawArc(oval, 11f, 158f, false, line) }
            Mood.TIRED -> { oval.set(mx - s * 0.025f, my - s * 0.022f, mx + s * 0.025f, my + s * 0.043f); canvas.drawOval(oval, ink) }
            Mood.FRIED -> {
                val p = Path().apply { moveTo(mx - s * 0.06f, my) }
                for (i in 0 until 4) p.rQuadTo(s * 0.015f, (if (i % 2 == 0) -1 else 1) * s * 0.025f, s * 0.03f, 0f)
                canvas.drawPath(p, line)
            }
            Mood.MELTED -> { oval.set(mx - s * 0.05f, my, mx + s * 0.05f, my + s * 0.06f); canvas.drawArc(oval, 191f, 158f, false, line) }
        }
    }

    private fun openEye(canvas: Canvas, x: Float, y: Float, r: Float, open: Float) {
        val h = r * 2 * open.coerceIn(0.08f, 1f)
        oval.set(x - r, y - h / 2, x + r, y + h / 2)
        canvas.drawOval(oval, ink)
        if (open > 0.4f) {
            fill.color = Color.WHITE
            canvas.drawCircle(x + r * 0.35f, y - r * 0.35f, r * 0.32f, fill)
        }
    }

    private fun blinkAmount(): Float {
        val start = 0.62f; val len = 0.05f
        if (phase < start || phase > start + len) return 0f
        val p = (phase - start) / len
        return if (p < 0.5f) p * 2 else (1 - p) * 2
    }

    private fun blend(a: Int, b: Int, t: Float) = Color.rgb(
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt(),
    )

    private fun withAlpha(color: Int, alpha: Float) =
        Color.argb((alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    companion object {
        private val INK = Color.parseColor("#1B2430")
        private val LOBES = arrayOf(
            floatArrayOf(0.30f, 0.36f, 0.18f), floatArrayOf(0.50f, 0.29f, 0.20f), floatArrayOf(0.70f, 0.36f, 0.18f),
            floatArrayOf(0.22f, 0.53f, 0.17f), floatArrayOf(0.78f, 0.53f, 0.17f), floatArrayOf(0.38f, 0.63f, 0.19f),
            floatArrayOf(0.62f, 0.63f, 0.19f), floatArrayOf(0.50f, 0.50f, 0.24f),
        )
        private val DRIPS = arrayOf(
            floatArrayOf(0.34f, 0.78f, 0.05f, 0.10f), floatArrayOf(0.55f, 0.80f, 0.04f, 0.14f), floatArrayOf(0.68f, 0.76f, 0.035f, 0.08f),
        )
    }
}
