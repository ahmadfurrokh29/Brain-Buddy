import 'models.dart';

enum TriggerKind { peakHour, peakDay, lateNight, earlyStart, reason, topApp }

/// One insight about when or why the user scrolls, e.g. "Your busiest hour: 11 PM".
class Trigger {
  final TriggerKind kind;
  final String title;
  final String body;
  const Trigger(this.kind, this.title, this.body);
}

/// Below this many reels the patterns are too thin to say anything useful.
const kMinReelsForTriggers = 15;

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String hourLabel(int h) => h == 0 ? '12 AM' : h == 12 ? '12 PM' : h < 12 ? '$h AM' : '${h - 12} PM';

String _clock(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final suffix = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $suffix';
}

/// Finds the user's weak moments from their own data. [appTotals] are watched reels per app name.
List<Trigger> findTriggers(Patterns p, {Map<String, int> appTotals = const {}}) {
  final total = p.total;
  if (total < kMinReelsForTriggers) return const [];
  final out = <Trigger>[];
  int pct(int n) => (n * 100 / total).round();

  // Busiest hour of the day.
  final byHour = List.generate(24, (h) => p.heat.fold(0, (s, day) => s + day[h]));
  var peakHour = 0;
  for (var h = 1; h < 24; h++) {
    if (byHour[h] > byHour[peakHour]) peakHour = h;
  }
  out.add(Trigger(TriggerKind.peakHour, 'Your busiest hour: ${hourLabel(peakHour)}',
      '${pct(byHour[peakHour])}% of your reels happen between ${hourLabel(peakHour)} and ${hourLabel((peakHour + 1) % 24)}.'));

  // Late night: 11 PM to 4 AM.
  final late = [23, 0, 1, 2, 3].fold(0, (s, h) => s + byHour[h]);
  if (pct(late) >= 20) {
    out.add(Trigger(TriggerKind.lateNight, 'Late-night scrolling',
        '${pct(late)}% of your reels are after 11 PM. A Bedtime schedule can protect your sleep.'));
  }

  // Heaviest weekday, only when it clearly stands out.
  final byDay = p.heat.map((row) => row.fold(0, (a, b) => a + b)).toList();
  var peakDay = 0;
  for (var d = 1; d < 7; d++) {
    if (byDay[d] > byDay[peakDay]) peakDay = d;
  }
  final avg = total / 7;
  if (byDay[peakDay] >= 5 && byDay[peakDay] >= avg * 1.3) {
    out.add(Trigger(TriggerKind.peakDay, '${_weekdays[peakDay]} is your heaviest day',
        'You watch about ${(byDay[peakDay] / avg * 100 - 100).round()}% more reels on ${_weekdays[peakDay]}s than on an average day.'));
  }

  // Early start: on most days the first reel comes before 9 AM.
  if (p.firstReel.length >= 3) {
    final sorted = [...p.firstReel]..sort();
    final median = sorted[sorted.length ~/ 2];
    if (median < 9 * 60) {
      out.add(Trigger(TriggerKind.earlyStart, 'You start early',
          'On most days your first reel is around ${_clock(median)}. Try keeping reels away until after breakfast.'));
    }
  }

  // Most common answer to "Why are you here?".
  final reasons = p.intents.entries.where((e) => e.key != 'Closed' && e.value >= 3).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (reasons.isNotEmpty) {
    out.add(Trigger(TriggerKind.reason, 'Your usual reason: "${reasons.first.key}"',
        'You picked it ${reasons.first.value} times when reels opened.'));
  }

  // One app takes most of the reels.
  if (appTotals.isNotEmpty) {
    final top = appTotals.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final share = top.value * 100 / appTotals.values.fold(0, (a, b) => a + b);
    if (share >= 50) {
      out.add(Trigger(TriggerKind.topApp, '${top.key} takes ${share.round()}% of your reels',
          'A per-app budget for ${top.key} can cut the most with the least effort.'));
    }
  }
  return out;
}
