import 'package:brain_buddy/core/models.dart';
import 'package:brain_buddy/core/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

DaySummary _day(String day, int watched, {int skimmed = 0, int ms = 0, Map<String, int> apps = const {}}) => DaySummary(
      day: day,
      watched: watched,
      skimmed: skimmed,
      ads: 0,
      ms: ms,
      unlocks: 0,
      apps: [for (final e in apps.entries) AppStat(pkg: e.key, name: e.key, watched: e.value, skimmed: 0, ms: 0)],
      hours: List.filled(24, 0),
      intents: const {},
    );

void main() {
  test('sums the last 7 days and compares with the 7 before', () {
    final days = [
      for (var i = 1; i <= 7; i++) _day('2026-10-0$i', 20),
      for (var i = 8; i <= 14; i++) _day('2026-10-${i.toString().padLeft(2, '0')}', 10, skimmed: 5, ms: 600000, apps: {'Instagram': 7, 'YouTube Shorts': 3}),
    ];
    final r = WeeklyReceipt.from(days, 30);
    expect(r.watched, 70);
    expect(r.skimmed, 35);
    expect(r.minutes, 70);
    expect(r.previousWatched, 140);
    expect(r.changePercent, -50);
    expect(r.topApp, 'Instagram');
    expect(r.topAppReels, 49);
    expect(r.mood, Mood.okay); // 10 a day of 30
  });

  test('distance is one screen per swipe', () {
    final r = WeeklyReceipt.from([_day('2026-10-14', 1000, skimmed: 500)], 30);
    expect(r.distanceLabel, '210 m');
    final big = WeeklyReceipt.from([_day('2026-10-14', 10000)], 30);
    expect(big.distanceLabel, '1.4 km');
  });

  test('best day ignores days without use, and no comparison without a previous week', () {
    final r = WeeklyReceipt.from([_day('2026-10-13', 0), _day('2026-10-14', 12), _day('2026-10-15', 4)], 30);
    expect(r.bestDay?.day, '2026-10-15');
    expect(r.changePercent, isNull);
  });
}
