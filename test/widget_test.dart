import 'package:brain_buddy/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mood', () {
    test('follows the share of the daily budget', () {
      expect(Mood.of(0, 30), Mood.fresh);
      expect(Mood.of(7, 30), Mood.fresh);
      expect(Mood.of(8, 30), Mood.okay);
      expect(Mood.of(15, 30), Mood.tired);
      expect(Mood.of(24, 30), Mood.fried);
      expect(Mood.of(30, 30), Mood.fried);
      expect(Mood.of(31, 30), Mood.melted);
    });

    test('a zero budget means melted', () {
      expect(Mood.of(0, 0), Mood.melted);
    });
  });
}
