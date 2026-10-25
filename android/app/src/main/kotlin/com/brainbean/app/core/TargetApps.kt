package com.brainbean.app.core

/**
 * A short-video app we can track.
 *
 * [markerIds] are view ids that only exist on the app's reels/shorts screen.
 * [headerHints] are titles shown at the top of the reels screen ("Reels", "Spotlight")
 * and are used when the app hides its view ids.
 * [wholeFeedIsReels] is for apps whose main full-screen feed is short video (TikTok).
 * [pageIds] are view ids of one reel's page; reel texts are read only inside the page filling the screen.
 * [listIds] are view ids of the scrolling list that holds the reels (one page per reel). Without them
 * the innermost full-screen list is used.
 * [showsText] apps always show a caption/author, so a reel without text is still loading (never a
 * reel of its own). Lite apps draw their own views and may show no text at all.
 *
 * View ids change when apps update, so detection is tuned here in one place.
 */
data class TargetApp(
    val pkg: String,
    val name: String,
    val markerIds: List<String> = emptyList(),
    val headerHints: List<String> = emptyList(),
    val wholeFeedIsReels: Boolean = false,
    val pageIds: List<String> = emptyList(),
    val listIds: List<String> = emptyList(),
    val showsText: Boolean = true,
)

object TargetApps {
    val all: List<TargetApp> = listOf(
        TargetApp(
            pkg = "com.instagram.android",
            name = "Instagram",
            markerIds = listOf("clips_viewer_view_pager", "clips_viewer_container", "clips_video_container"),
            headerHints = listOf("Reels"),
            // Each reel page has another full-screen list inside it, so name the real reels list.
            listIds = listOf("clips_viewer_view_pager"),
        ),
        TargetApp(pkg = "com.instagram.lite", name = "Instagram Lite", headerHints = listOf("Reels"), showsText = false),
        TargetApp(
            pkg = "com.google.android.youtube",
            name = "YouTube Shorts",
            markerIds = listOf("reel_recycler", "reel_player_page_container", "reel_watch_player", "reel_time_bar"),
            headerHints = listOf("Shorts"),
            // YouTube's Shorts list is not marked scrollable, so the current Short is found by id.
            pageIds = listOf("reel_player_page_container"),
        ),
        TargetApp(pkg = "com.zhiliaoapp.musically", name = "TikTok", wholeFeedIsReels = true),
        TargetApp(pkg = "com.ss.android.ugc.trill", name = "TikTok", wholeFeedIsReels = true),
        // Facebook hides its view ids; the Reels tab is found by its "Reels" title. Reel texts are read
        // from the innermost full-screen list (the outer one only switches between the bottom tabs).
        TargetApp(pkg = "com.facebook.katana", name = "Facebook", headerHints = listOf("Reels")),
        TargetApp(pkg = "com.facebook.lite", name = "Facebook Lite", headerHints = listOf("Reels"), showsText = false),
        // Spotlight uses Snapchat's own viewer instead of a scrolling list, so it is found by id.
        TargetApp(
            pkg = "com.snapchat.android",
            name = "Snapchat",
            markerIds = listOf("spotlight_container"),
            pageIds = listOf("opera_viewer"),
        ),
        // Reddit's short videos play in its full-screen video player ("fbp" = full-bleed player).
        TargetApp(
            pkg = "com.reddit.frontpage",
            name = "Reddit",
            markerIds = listOf("fbp_screen"),
            pageIds = listOf("content_video_view"),
        ),
    )

    private val byPkg = all.associateBy { it.pkg }

    fun find(pkg: String?): TargetApp? = pkg?.let { byPkg[it] }

    fun name(pkg: String): String = byPkg[pkg]?.name ?: pkg
}
