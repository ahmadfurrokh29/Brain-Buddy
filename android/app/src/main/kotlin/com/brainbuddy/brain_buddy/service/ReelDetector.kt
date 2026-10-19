package com.brainbuddy.brain_buddy.service

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import com.brainbuddy.brain_buddy.core.TargetApp

/**
 * Reads the screen of a tracked app and answers two questions:
 *  1. Is the user on the reels/shorts screen right now?
 *  2. Which reel is showing? (a "fingerprint" built from its caption, author and audio text)
 *
 * The fingerprint is what makes counting honest: the same reel seen again,
 * scrolling back up, or pulling down notifications keeps the same fingerprint
 * and is not counted twice.
 */
object ReelDetector {

    data class Snapshot(val texts: Set<String>, val isAd: Boolean)

    private const val MAX_NODES = 400

    /** Buttons and labels that appear on every reel and say nothing about which reel it is. */
    private val UI_WORDS = setOf(
        "follow", "following", "like", "liked", "comment", "comments", "share", "send", "save", "saved",
        "remix", "subscribe", "subscribed", "more", "reels", "shorts", "spotlight", "audio", "original audio",
        "home", "search", "profile", "inbox", "friends", "for you", "explore", "create", "camera", "back",
        "mute", "unmute", "play", "pause", "dislike", "options", "menu", "close", "watch", "video", "see more",
        "see translation", "add comment…", "add a comment…", "suggested for you",
    )

    private val AD_LABELS = setOf("sponsored", "ad", "promoted", "sponsored ·", "ad ·")

    fun isReelsScreen(root: AccessibilityNodeInfo, app: TargetApp, screen: Rect): Boolean {
        for (id in app.markerIds) {
            val found = root.findAccessibilityNodeInfosByViewId("${app.pkg}:id/$id")
            if (found.any { it.isVisibleToUser }) return true
        }
        val pager = findFullScreenScroller(root, screen) ?: return false
        if (app.wholeFeedIsReels) return true
        if (app.headerHints.isNotEmpty()) return hasHeader(root, app.headerHints, screen)
        // Apps without hints count only a true full-screen pager, never a normal feed list.
        return pager.contains("ViewPager")
    }

    fun snapshot(root: AccessibilityNodeInfo, screen: Rect): Snapshot {
        val texts = HashSet<String>()
        var isAd = false
        val r = Rect()
        walk(root) { node ->
            if (!node.isVisibleToUser) return@walk
            node.getBoundsInScreen(r)
            if (!Rect.intersects(r, screen)) return@walk
            for (raw in listOfNotNull(node.text?.toString(), node.contentDescription?.toString())) {
                val s = raw.trim()
                val lower = s.lowercase()
                if (lower in AD_LABELS || lower.startsWith("sponsored")) isAd = true
                if (s.length < 3 || s.length > 300) continue
                if (lower in UI_WORDS) continue
                if (s.any { it.isDigit() }) continue // like counts, view counts and timers change while watching
                texts.add(s)
            }
        }
        // The longest texts are the caption, the author and the audio name.
        val top = texts.sortedByDescending { it.length }.take(8).toSet()
        return Snapshot(top, isAd)
    }

    /** Stable id for a reel, used to remember it for the rest of the day. */
    fun key(texts: Set<String>): String =
        texts.sortedByDescending { it.length }.take(4).sorted().joinToString("|").hashCode().toString(16)

    /** Same reel if at least half of its texts are still on screen (captions can expand, buttons can change). */
    fun similar(a: Set<String>, b: Set<String>): Boolean {
        if (a.isEmpty() || b.isEmpty()) return false
        val shared = a.count { it in b }
        return shared * 2 >= minOf(a.size, b.size)
    }

    private fun findFullScreenScroller(root: AccessibilityNodeInfo, screen: Rect): String? {
        val r = Rect()
        var result: String? = null
        walk(root) { node ->
            if (result != null || !node.isScrollable || !node.isVisibleToUser) return@walk
            val cls = node.className?.toString() ?: return@walk
            if (!cls.contains("ViewPager") && !cls.contains("RecyclerView")) return@walk
            node.getBoundsInScreen(r)
            if (r.height() >= screen.height() * 0.8 && r.width() >= screen.width() * 0.9) result = cls
        }
        return result
    }

    private fun hasHeader(root: AccessibilityNodeInfo, hints: List<String>, screen: Rect): Boolean {
        val r = Rect()
        val topLimit = screen.top + screen.height() / 4
        val lowerHints = hints.map { it.lowercase() }
        var found = false
        walk(root) { node ->
            if (found || !node.isVisibleToUser) return@walk
            val t = (node.text ?: node.contentDescription)?.toString()?.trim()?.lowercase() ?: return@walk
            if (t !in lowerHints) return@walk
            node.getBoundsInScreen(r)
            if (r.top < topLimit) found = true
        }
        return found
    }

    private inline fun walk(root: AccessibilityNodeInfo, visit: (AccessibilityNodeInfo) -> Unit) {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var seen = 0
        while (queue.isNotEmpty() && seen < MAX_NODES) {
            val node = queue.removeFirst()
            seen++
            visit(node)
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
    }
}
