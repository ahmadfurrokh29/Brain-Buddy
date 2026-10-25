package com.brainbean.app.service

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.brainbean.app.core.Mood
import com.brainbean.app.service.Overlays.Companion.GREY
import com.brainbean.app.service.Overlays.Companion.INK
import com.brainbean.app.service.Overlays.Companion.MINT
import com.brainbean.app.service.Overlays.Companion.MINT_LIGHT

/**
 * Firm lock: "Why do you want more reels?". A normal app screen rather than a pop-up over the reel app,
 * so the keyboard, Back and the navigation buttons behave like everywhere else.
 */
class ReasonActivity : Activity() {
    /** Unlock, Close app or Back already answered the counter. */
    private var answered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = MINT_LIGHT
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE,
        )

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(24), dp(28), dp(24))
        }
        column.addView(BrainView(this).apply { mood = Mood.MELTED }, LinearLayout.LayoutParams(dp(88), dp(88)))
        column.addView(text("Why do you want more reels?", 24f, bold = true).withTop(12))
        column.addView(text("Type at least $MIN_REASON characters. Be honest with yourself.", 15f, color = GREY).withTop(6))

        val reason = EditText(this).apply {
            hint = "I want more reels because…"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(INK)
            setHintTextColor(GREY)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            maxLines = 4
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(Color.WHITE); setStroke(dp(1), MINT) }
        }
        column.addView(reason, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(18) })

        val unlock = button("Unlock 5 reels", primary = false) {
            val typed = reason.text.toString().trim()
            if (typed.length >= MIN_REASON) answer { ReelCounterService.instance?.reasonGiven(typed) }
        }.apply { alpha = 0.4f }
        reason.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(e: Editable?) { unlock.alpha = if ((e?.trim()?.length ?: 0) >= MIN_REASON) 1f else 0.4f }
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
        })
        column.addView(unlock.withTop(14))
        column.addView(button("Close app", primary = true) { answer { ReelCounterService.instance?.reasonClose() } }.withTop(10))

        // Scrolls when the keyboard leaves too little room, so the brain is never cut off.
        setContentView(ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(MINT_LIGHT)
            addView(column)
        })
        reason.requestFocus()
    }

    @Deprecated("Back is handled for all Android versions this app supports")
    override fun onBackPressed() {
        answer { ReelCounterService.instance?.reasonDismissed() }
    }

    override fun onStop() {
        super.onStop()
        // Left with Home or Recents: the reel app locks again when it comes back.
        if (!answered) answer { ReelCounterService.instance?.reasonDismissed() }
    }

    private fun answer(tell: () -> Unit) {
        if (answered) return
        answered = true
        tell()
        finish()
    }

    private fun text(s: String, sp: Float, bold: Boolean = false, color: Int = INK) = TextView(this).apply {
        text = s
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun button(label: String, primary: Boolean, onClick: () -> Unit) = TextView(this).apply {
        text = label
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        minWidth = dp(240)
        setPadding(dp(24), dp(14), dp(24), dp(14))
        setTextColor(if (primary) Color.WHITE else INK)
        background = GradientDrawable().apply { cornerRadius = dp(28).toFloat(); setColor(if (primary) MINT else Color.WHITE) }
        setOnClickListener { onClick() }
    }

    private fun <T : View> T.withTop(dpTop: Int): T = apply {
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(dpTop) }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    companion object {
        private const val MIN_REASON = 10
    }
}
