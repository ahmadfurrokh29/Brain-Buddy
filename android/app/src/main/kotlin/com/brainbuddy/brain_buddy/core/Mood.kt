package com.brainbuddy.brain_buddy.core

import android.graphics.Color

/**
 * Brain buddy's mood from how much of today's budget is used. Same thresholds and brain colours as
 * the Flutter side (lib/core/models.dart): the brain itself changes colour as it gets more tired.
 */
enum class Mood(val emoji: String, val label: String, body: String, top: String, outline: String) {
    FRESH("😄", "Fresh", "#FF9EC0", "#FFC4D9", "#E0608F"),
    OKAY("🙂", "Okay", "#FFB09A", "#FFD0C2", "#E07A5F"),
    TIRED("😪", "Tired", "#F2C580", "#F9DDB0", "#C9963F"),
    FRIED("😵‍💫", "Fried", "#F58F5B", "#FFB892", "#C9612F"),
    MELTED("🫠", "Melted", "#A99ACB", "#C9BEE3", "#7A6AA6");

    /** Main brain colour, its lighter top, and the darker outline. */
    val body = Color.parseColor(body)
    val top = Color.parseColor(top)
    val outline = Color.parseColor(outline)

    companion object {
        fun of(watched: Int, budget: Int): Mood {
            if (budget <= 0) return MELTED
            val r = watched.toDouble() / budget
            return when {
                r < 0.25 -> FRESH
                r < 0.5 -> OKAY
                r < 0.8 -> TIRED
                r <= 1.0 -> FRIED
                else -> MELTED
            }
        }
    }
}
