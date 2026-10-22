import 'package:brain_buddy/core/squads.dart';
import 'package:flutter_test/flutter_test.dart';

SquadMember _m(String uid, {String week = '2026-10-19', int reels = 0, String prevWeek = '', int prev = 0}) => SquadMember(
      uid: uid,
      name: uid,
      avatar: '🦊',
      weekKey: week,
      weekWatched: reels,
      todayWatched: 0,
      prevWeekKey: prevWeek,
      prevWeekWatched: prev,
      updatedAt: null,
    );

void main() {
  test('week key is the Monday of the week', () {
    expect(weekKeyOf(DateTime(2026, 10, 22)), '2026-10-19'); // Thursday
    expect(weekKeyOf(DateTime(2026, 10, 19)), '2026-10-19'); // Monday
    expect(weekKeyOf(DateTime(2026, 10, 25)), '2026-10-19'); // Sunday
    expect(weekKeyOf(DateTime(2026, 11, 2)), '2026-11-02');
  });

  test('fewest reels ranks first; members without this week\'s counts go last', () {
    final ranked = rankForWeek([
      _m('a', reels: 40),
      _m('b', reels: 12),
      _m('stale', week: '2026-10-12', reels: 1),
      _m('c', reels: 25),
    ], '2026-10-19');
    expect(ranked.map((m) => m.uid), ['b', 'c', 'a', 'stale']);
  });

  test('last week\'s winner only counts members who reported that week', () {
    final w = lastWeekWinner([
      _m('a', prevWeek: '2026-10-12', prev: 50),
      _m('b', prevWeek: '2026-10-12', prev: 20),
      _m('old', prevWeek: '2026-10-05', prev: 3),
    ], '2026-10-12');
    expect(w?.uid, 'b');
    expect(lastWeekWinner([_m('x')], '2026-10-12'), isNull);
  });
}
