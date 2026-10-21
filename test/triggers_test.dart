import 'package:brain_buddy/core/models.dart';
import 'package:brain_buddy/core/triggers.dart';
import 'package:flutter_test/flutter_test.dart';

Patterns _patterns({Map<(int, int), int> cells = const {}, List<int> firstReel = const [], Map<String, int> intents = const {}}) {
  final heat = List.generate(7, (_) => List.filled(24, 0));
  cells.forEach((k, v) => heat[k.$1][k.$2] = v);
  return Patterns(heat: heat, firstReel: firstReel, intents: intents, firmReasons: const []);
}

void main() {
  test('too little data gives no triggers', () {
    expect(findTriggers(_patterns(cells: {(0, 10): 5})), isEmpty);
  });

  test('finds busiest hour, late night and heaviest day', () {
    final p = _patterns(cells: {(6, 23): 30, (6, 0): 10, (1, 14): 5, (2, 9): 5});
    final kinds = findTriggers(p).map((t) => t.kind).toSet();
    expect(kinds, containsAll([TriggerKind.peakHour, TriggerKind.lateNight, TriggerKind.peakDay]));
    final peak = findTriggers(p).firstWhere((t) => t.kind == TriggerKind.peakHour);
    expect(peak.title, contains('11 PM'));
    final day = findTriggers(p).firstWhere((t) => t.kind == TriggerKind.peakDay);
    expect(day.title, startsWith('Sunday'));
  });

  test('daytime scrolling is not flagged as late night', () {
    final p = _patterns(cells: {(0, 14): 10, (1, 15): 10, (2, 16): 10});
    expect(findTriggers(p).map((t) => t.kind), isNot(contains(TriggerKind.lateNight)));
  });

  test('early start uses the median first reel', () {
    final p = _patterns(cells: {(0, 8): 20}, firstReel: [8 * 60 + 10, 7 * 60 + 50, 8 * 60 + 30, 13 * 60]);
    final t = findTriggers(p).firstWhere((t) => t.kind == TriggerKind.earlyStart);
    expect(t.body, contains('8:30 AM'));
  });

  test('reason ignores "Closed" and rare answers', () {
    final p = _patterns(cells: {(0, 20): 20}, intents: {'Closed': 9, "I'm bored": 4, 'I want to relax': 2});
    final t = findTriggers(p).firstWhere((t) => t.kind == TriggerKind.reason);
    expect(t.title, contains("I'm bored"));
  });

  test('top app only when it takes at least half', () {
    final p = _patterns(cells: {(0, 20): 20});
    expect(findTriggers(p, appTotals: {'Instagram': 30, 'YouTube Shorts': 10}).map((t) => t.kind), contains(TriggerKind.topApp));
    expect(findTriggers(p, appTotals: {'Instagram': 10, 'YouTube Shorts': 10, 'Facebook': 10}).map((t) => t.kind),
        isNot(contains(TriggerKind.topApp)));
  });
}
