import 'models.dart';

/// One phone screen per reel swipe, about 14 cm on a typical phone.
const kMetersPerReel = 0.14;

/// The numbers on the Weekly Reel Receipt, from the last 7 days and the 7 days before.
class WeeklyReceipt {
  final List<DaySummary> week;
  final int watched;
  final int skimmed;
  final int minutes;
  final int previousWatched;
  final String? topApp;
  final int topAppReels;
  final DaySummary? bestDay;
  final int budget;

  const WeeklyReceipt({
    required this.week,
    required this.watched,
    required this.skimmed,
    required this.minutes,
    required this.previousWatched,
    required this.topApp,
    required this.topAppReels,
    required this.bestDay,
    required this.budget,
  });

  /// [days] = the last 14 days, oldest first (as from getDays(14)).
  factory WeeklyReceipt.from(List<DaySummary> days, int budget) {
    final week = days.length > 7 ? days.sublist(days.length - 7) : days;
    final before = days.length > 7 ? days.sublist(0, days.length - 7) : const <DaySummary>[];
    final apps = <String, int>{};
    for (final d in week) {
      for (final a in d.apps) {
        apps[a.name] = (apps[a.name] ?? 0) + a.watched;
      }
    }
    final top = apps.entries.where((e) => e.value > 0).fold<MapEntry<String, int>?>(
          null,
          (best, e) => best == null || e.value > best.value ? e : best,
        );
    // Best day: fewest reels among days the app was in use.
    final used = week.where((d) => d.watched > 0 || d.ms > 0).toList()..sort((a, b) => a.watched.compareTo(b.watched));
    return WeeklyReceipt(
      week: week,
      watched: week.fold(0, (s, d) => s + d.watched),
      skimmed: week.fold(0, (s, d) => s + d.skimmed),
      minutes: week.fold(0, (s, d) => s + d.minutes),
      previousWatched: before.fold(0, (s, d) => s + d.watched),
      topApp: top?.key,
      topAppReels: top?.value ?? 0,
      bestDay: used.isEmpty ? null : used.first,
      budget: budget,
    );
  }

  /// Every reel and skim is one swipe of the screen.
  double get kilometers => (watched + skimmed) * kMetersPerReel / 1000;

  String get distanceLabel {
    final m = (watched + skimmed) * kMetersPerReel;
    return m < 1000 ? '${m.round()} m' : '${kilometers.toStringAsFixed(1)} km';
  }

  /// Change versus the 7 days before, in percent (negative = fewer reels). Null when there's nothing to compare.
  int? get changePercent => previousWatched == 0 ? null : ((watched - previousWatched) * 100 / previousWatched).round();

  /// The brain's mood for the week, from the daily average against the budget.
  Mood get mood => Mood.of((watched / 7).round(), budget);

  bool get isEmpty => watched == 0 && skimmed == 0 && minutes == 0;
}
