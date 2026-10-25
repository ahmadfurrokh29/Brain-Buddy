package com.brainbean.app.service

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo
import com.brainbean.app.core.TargetApp

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

    /** [texts] are the reel's own texts, longest first. */
    data class Snapshot(val texts: List<String>, val isAd: Boolean)

    /** YouTube nests reel texts ~25 levels deep, so the walk must be generous. */
    private const val MAX_NODES = 1500

    /** Buttons and labels that appear on every reel and say nothing about which reel it is. */
    private val UI_WORDS = setOf(
        "follow", "following", "like", "liked", "comment", "comments", "share", "send", "save", "saved",
        "remix", "subscribe", "subscribed", "more", "reels", "shorts", "spotlight", "audio", "original audio",
        "home", "search", "profile", "inbox", "friends", "for you", "explore", "create", "camera", "back",
        "mute", "unmute", "play", "pause", "dislike", "options", "menu", "close", "watch", "video", "see more",
        "see translation", "add comment…", "add a comment…", "suggested for you", "subscriptions", "you",
        "library", "more options", "navigate up", "go back", "action menu", "sound", "add", "notifications",
        "play video", "pause video", "captions", "settings", "report", "not interested", "use this sound",
        "more actions", "new content available", "youtube premium", "privacy setting public",
        "reels tab details", "tap to show video controls", "video, overlays visible", "video buttons are active",
        "track position", "upvote", "downvote", "unmute", "add friends", "story sent", "spotlight",
        "seekbar", "view likes", "full screen", "full-screen", "rotate camera",
    )

    /** Bottom-tab labels such as "Home, tab 1 of 6". */
    private val TAB_LABEL = Regex(""",?\s*tab \d+ of \d+$""")

    /** Button descriptions that start the same on every reel ("Like this video along with …"). */
    private val UI_PREFIXES = listOf(
        "like this", "dislike this", "share this", "remix this", "view comments", "subscribe to", "comments.",
        "see more videos using this sound", "go to channel", "double tap", "tap to", "swipe",
        "subscriptions", "navigate to your reels profile", "enter full-screen", "are you interested in this",
        "opera_content_index", "like button",
        // TikTok: the bookmark button and a search suggestion that changes between visits.
        "add or remove this video", "search ·",
    )

    private val AD_LABELS = setOf("sponsored", "ad", "promoted", "sponsored ·", "ad ·")

    fun isReelsScreen(root: AccessibilityNodeInfo, app: TargetApp, screen: Rect): Boolean {
        for (id in app.markerIds) {
            val found = findById(root, app, id)
            if (found.any { it.isVisibleToUser }) return true
        }
        val pager = findFullScreenScroller(root, screen) ?: return false
        if (app.wholeFeedIsReels) return true
        if (app.headerHints.isNotEmpty()) return hasHeader(root, app.headerHints, screen)
        // Apps without hints count only a true full-screen pager, never a normal feed list.
        return pager.className?.toString()?.contains("ViewPager") == true
    }

    /**
     * Texts of the reel that fills the screen. Neighbouring reels that peek in during a swipe,
     * and app chrome outside the current page, are left out.
     */
    fun snapshot(root: AccessibilityNodeInfo, app: TargetApp, screen: Rect): Snapshot {
        val scope = pageById(root, app, screen) ?: currentPage(root, app, screen) ?: root
        val texts = LinkedHashSet<String>()
        var isAd = false
        val r = Rect()
        walk(scope) { node ->
            if (!node.isVisibleToUser) return@walk
            node.getBoundsInScreen(r)
            if (!mostlyOnScreen(r, screen)) return@walk
            for (raw in listOfNotNull(node.text?.toString(), node.contentDescription?.toString())) {
                val s = raw.trim()
                val lower = s.lowercase()
                if (lower in AD_LABELS || lower.startsWith("sponsored")) isAd = true
                if (s.length < 3 || s.length > 300) continue
                if (lower in UI_WORDS || UI_PREFIXES.any { lower.startsWith(it) }) continue
                if (TAB_LABEL.containsMatchIn(lower)) continue
                if (isCounterOrTimer(lower)) continue // like counts, view counts and timers change while watching
                // Hashtags like "#shorts" or "#viral" are shared by many different reels.
                if (s.startsWith("#") && s.none { it == ' ' }) continue
                texts.add(s)
            }
        }
        return Snapshot(texts.sortedByDescending { it.length }, isAd)
    }

    private val COUNT_WORDS = Regex("""\d[\d.,]*\+?\s*(k|m|b|thousand|million|billion|views?|likes?|comments?|replies|others?|shares?|votes?|reactions?|posts?|followers?|videos?)\b""")
    private val TIMER = Regex("""\d+:\d{2}|\d+\s*(seconds?|minutes?|hours?|days?|weeks?)\b|\b\d+\s*[smhdw]\b""")
    /**
     * Spelled-out counters: Instagram's "Reshare number is 31066", "Save number is 9230", "Reposted 1788 times",
     * and Facebook's position "New for you • 4 of 8".
     */
    private val SPELLED_COUNT = Regex("""number is \d|\d[\d.,]*\s*times\b|\b\d+ of \d+\b""")

    /**
     * "1.4m", "14k", "13,275 comments", "0:12", "3 days ago" change while a reel plays, so they can't
     * identify it. Names that merely contain a digit ("@Skinnyfromthe9") are kept.
     */
    private fun isCounterOrTimer(lower: String): Boolean {
        val digits = lower.count { it.isDigit() }
        if (digits == 0) return false
        if (COUNT_WORDS.containsMatchIn(lower) || TIMER.containsMatchIn(lower) || SPELLED_COUNT.containsMatchIn(lower)) return true
        val meaningful = lower.count { !it.isWhitespace() }
        return digits * 10 >= meaningful * 4 // mostly digits, e.g. "1,204" or "12.5"
    }

    /**
     * Stable id for a reel, used to remember it for the rest of the day. Built from the reel's longest texts,
     * leaving out the music line (Instagram "Artist · Song", TikTok "Sound: …" / "Contains: …"): it scrolls
     * across the screen and is only readable on some visits, so including it made the same reel look new
     * when scrolling back to it.
     */
    fun key(texts: Collection<String>): String {
        val stable = texts.filterNot { isMusicLine(it) }.ifEmpty { texts }
        return stable.sortedByDescending { it.length }.take(4).sorted().joinToString("|").hashCode().toString(16)
    }

    private fun isMusicLine(s: String): Boolean {
        val lower = s.lowercase()
        return s.contains(" · ") || lower.startsWith("sound:") || lower.startsWith("contains:") ||
            lower.startsWith("original sound")
    }

    /** The reel's main text: its longest text that isn't the music line (usually the caption). */
    fun mainText(texts: Collection<String>): String? =
        texts.filterNot { isMusicLine(it) }.maxByOrNull { it.length }

    /**
     * Whether two text lists are the same reel seen twice: the same main text (caption), and most of the
     * rest shared, measured against the longer list. A few labels that come and go still match; two
     * different videos from the same creator (same name, profile and follow button) differ in the caption.
     */
    fun sameReel(a: Collection<String>, b: Collection<String>): Boolean {
        if (a.isEmpty() || b.isEmpty() || mainText(a) != mainText(b)) return false
        val setA = a.toHashSet()
        val setB = b.toHashSet()
        // Seen once before it finished loading (only the caption, say): all of it is in the full version.
        if (setA.size < setB.size && setB.containsAll(setA)) return true
        if (setB.size < setA.size && setA.containsAll(setB)) return true
        return setA.count { it in setB }.toDouble() / maxOf(setA.size, setB.size) >= 0.6
    }

    /** How much two reels' texts overlap, from 0 (nothing shared) to 1 (identical). */
    fun overlap(a: Collection<String>, b: Collection<String>): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        val setB = b.toHashSet()
        val shared = a.count { it in setB }
        return shared.toDouble() / minOf(a.size, setB.size)
    }

    /**
     * Classic Android views have ids like "com.app:id/name" and Android can look them up directly.
     * Jetpack Compose screens (Reddit) expose plain tags like "name" that the direct lookup can't find,
     * so for those the screen is walked and ids compared.
     */
    private fun findById(root: AccessibilityNodeInfo, app: TargetApp, id: String): List<AccessibilityNodeInfo> {
        val direct = root.findAccessibilityNodeInfosByViewId("${app.pkg}:id/$id")
        if (direct.isNotEmpty()) return direct
        val found = ArrayList<AccessibilityNodeInfo>()
        walk(root) { node ->
            val name = node.viewIdResourceName ?: return@walk
            if (name == id || name.endsWith("/$id")) found.add(node)
        }
        return found
    }

    /** The app's own reel page (found by view id) covering most of the screen. */
    private fun pageById(root: AccessibilityNodeInfo, app: TargetApp, screen: Rect): AccessibilityNodeInfo? {
        if (app.pageIds.isEmpty()) return null
        val r = Rect()
        val screenArea = screen.width().toLong() * screen.height()
        var best: AccessibilityNodeInfo? = null
        var bestArea = 0L
        for (id in app.pageIds) {
            for (node in findById(root, app, id)) {
                node.getBoundsInScreen(r)
                if (!r.intersect(screen)) continue
                val area = r.width().toLong() * r.height()
                if (area > bestArea) { bestArea = area; best = node }
            }
        }
        return if (bestArea * 2 >= screenArea) best else null
    }

    /** The pager page covering most of the screen, or null if the screen has no full-screen pager. */
    private fun currentPage(root: AccessibilityNodeInfo, app: TargetApp, screen: Rect): AccessibilityNodeInfo? {
        val named = app.listIds.firstNotNullOfOrNull { id -> findById(root, app, id).firstOrNull { it.isVisibleToUser } }
        val pager = named ?: findFullScreenScroller(root, screen) ?: return null
        val r = Rect()
        val screenArea = screen.width().toLong() * screen.height()
        var best: AccessibilityNodeInfo? = null
        var bestArea = 0L
        for (i in 0 until pager.childCount) {
            val child = pager.getChild(i) ?: continue
            child.getBoundsInScreen(r)
            if (!r.intersect(screen)) continue
            val area = r.width().toLong() * r.height()
            if (area > bestArea) { bestArea = area; best = child }
        }
        return if (bestArea * 2 >= screenArea) best else null
    }

    /** At least 60% of the node is on screen (mid-swipe neighbours are mostly off screen). */
    private fun mostlyOnScreen(r: Rect, screen: Rect): Boolean {
        val area = r.width().toLong() * r.height()
        if (area <= 0) return false
        val visible = Rect(r)
        if (!visible.intersect(screen)) return false
        return visible.width().toLong() * visible.height() * 10 >= area * 6
    }

    /**
     * The innermost full-screen scrolling list. Apps nest lists: Facebook's outer pager only switches
     * bottom tabs, and the reels list sits inside it. The walk goes level by level, so the last match is
     * the deepest one.
     */
    private fun findFullScreenScroller(root: AccessibilityNodeInfo, screen: Rect): AccessibilityNodeInfo? {
        val r = Rect()
        var result: AccessibilityNodeInfo? = null
        walk(root) { node ->
            if (!node.isScrollable || !node.isVisibleToUser) return@walk
            val cls = node.className?.toString() ?: return@walk
            if (!cls.contains("ViewPager") && !cls.contains("RecyclerView")) return@walk
            node.getBoundsInScreen(r)
            if (r.height() >= screen.height() * 0.8 && r.width() >= screen.width() * 0.9) result = node
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
