package com.brainbuddy.brain_buddy.core

/** Brain buddy's mood from how much of today's budget is used. Same thresholds as the Flutter side. */
enum class Mood(val emoji: String, val label: String) {
    FRESH("😄", "Fresh"),
    OKAY("🙂", "Okay"),
    TIRED("😪", "Tired"),
    FRIED("😵‍💫", "Fried"),
    MELTED("🫠", "Melted");

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
