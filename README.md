# Brain Buddy 🧠

Count the reels you scroll. Scroll less. Live more.

Brain Buddy counts every reel and short you watch on Instagram, YouTube Shorts, TikTok, Facebook, Snapchat and Reddit, shows the number live, and helps you stop with a friendly brain mascot that gets tired as you scroll.

## Features (Phase 1)

- **Honest counting:** a reel counts only after you watch it for 3 seconds (adjustable). Quick flicks are shown separately as *skimmed*. Ads and reels you see again are not counted.
- **Brain Buddy mascot** with 5 moods: Fresh, Okay, Tired, Fried, Melted.
- **Daily reel budget** with a **Gentle lock**: a breathing break when you reach your limit.
- **"Why are you here?" pause** before reels open.
- **Floating counter** on top of the reel apps.
- **Budget warnings** at 50%, 80% and 100%.
- **Insights:** reels by hour, per day, per app, and time spent.
- **Home-screen widget.**
- **Reliability Doctor:** checks the counter is running and gives fix steps for your phone brand.
- **Private:** no login and no uploads. Data is protected by Android Auto Backup and by backup/restore files.

## How it works

| Part | Where |
|---|---|
| Screens (Flutter) | `lib/` |
| Reel counting engine (Kotlin `AccessibilityService`) | `android/app/src/main/kotlin/.../service/` |
| Reel screen detection, tuned per app | `service/ReelDetector.kt`, `core/TargetApps.kt` |
| Local database | `core/Db.kt` (SQLite) |
| Flutter ↔ Kotlin bridge | `NativeBridge.kt` and `lib/core/native_bridge.dart` |
| Home-screen widget | `widget/BrainWidgetProvider.kt` |

## Run

```bash
flutter pub get
flutter run
```

Then, on the phone, open **Settings → Accessibility → Brain Buddy reel counter** and switch it on. The app walks you through this.

Requires Android 8.0+.
