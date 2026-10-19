package com.brainbuddy.brain_buddy.core

/**
 * A short-video app we can track.
 *
 * [markerIds] are view ids that only exist on the app's reels/shorts screen.
 * [headerHints] are titles shown at the top of the reels screen ("Reels", "Spotlight")
 * and are used when the app hides its view ids.
 * [wholeFeedIsReels] is for apps whose main full-screen feed is short video (TikTok).
 * [pageIds] are view ids of one reel's page; reel texts are read only inside the page filling the screen.
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
    val showsText: Boolean = true,
)

object TargetApps {
    val all: List<TargetApp> = listOf(
        TargetApp(
            pkg = "com.instagram.android",
            name = "Instagram",
            markerIds = listOf("clips_viewer_view_pager", "clips_viewer_container", "clips_video_container"),
            headerHints = listOf("Reels"),
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
        TargetApp(pkg = "com.facebook.katana", name = "Facebook", headerHints = listOf("Reels")),
        TargetApp(pkg = "com.facebook.lite", name = "Facebook Lite", headerHints = listOf("Reels"), showsText = false),
        TargetApp(pkg = "com.snapchat.android", name = "Snapchat", headerHints = listOf("Spotlight")),
        TargetApp(pkg = "com.reddit.frontpage", name = "Reddit"),
    )

    private val byPkg = all.associateBy { it.pkg }

    fun find(pkg: String?): TargetApp? = pkg?.let { byPkg[it] }

    fun name(pkg: String): String = byPkg[pkg]?.name ?: pkg
}
