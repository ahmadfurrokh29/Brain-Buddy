import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'native_bridge.dart';

final bridgeProvider = Provider<NativeBridge>((ref) => NativeBridge());

/// Settings key for anonymous crash reports (Firebase Crashlytics).
const kCrashReportsKey = 'crashReports';

/// Set in main() before the app starts.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefs not ready'));

/// Ticks whenever the native counter reports a change, so screens refresh live.
final changesProvider = StreamProvider<void>((ref) => ref.watch(bridgeProvider).changes);

class ConfigNotifier extends AsyncNotifier<AppConfig> {
  @override
  Future<AppConfig> build() => ref.watch(bridgeProvider).getConfig();

  Future<void> set(Map<String, Object?> values) async {
    state = AsyncData(await ref.read(bridgeProvider).setConfig(values));
  }

  Future<void> setSchedules(List<Schedule> schedules) =>
      set({'schedules': jsonEncode(schedules.map((s) => s.toJson()).toList())});

  Future<void> setAppBudgets(Map<String, int> budgets) => set({'appBudgets': jsonEncode(budgets)});

  Future<void> startFocus(int minutes) async {
    state = AsyncData(await ref.read(bridgeProvider).startFocus(minutes));
  }

  Future<void> cancelFocus() async {
    state = AsyncData(await ref.read(bridgeProvider).cancelFocus());
  }

  Future<void> pause(int minutes) async {
    state = AsyncData(await ref.read(bridgeProvider).pause(minutes));
  }

  Future<void> reload() async {
    state = AsyncData(await ref.read(bridgeProvider).getConfig());
  }
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, AppConfig>(ConfigNotifier.new);

final todayProvider = FutureProvider<DaySummary>((ref) {
  ref.watch(changesProvider);
  return ref.watch(bridgeProvider).getDay();
});

/// Last N days, oldest first.
final daysProvider = FutureProvider.family<List<DaySummary>, int>((ref, count) {
  ref.watch(changesProvider);
  return ref.watch(bridgeProvider).getDays(count);
});

final patternsProvider = FutureProvider.family<Patterns, int>((ref, count) {
  ref.watch(changesProvider);
  return ref.watch(bridgeProvider).getPatterns(count);
});

final statusProvider =FutureProvider<DeviceStatus>((ref) {
  ref.watch(changesProvider);
  return ref.watch(bridgeProvider).getStatus();
});

final appIconsProvider = FutureProvider<Map<String, Uint8List>>((ref) => ref.watch(bridgeProvider).getAppIcons());

final targetsProvider =FutureProvider<List<TargetApp>>((ref) => ref.watch(bridgeProvider).getTargets());

/// Days in a row (ending today) at or under the daily budget.
final streakProvider = FutureProvider<int>((ref) async {
  final days = await ref.watch(daysProvider(60).future);
  final config = await ref.watch(configProvider.future);
  if (days.isEmpty) return 0;
  // Days before the first counted reel were before Brain Bean was installed: they don't count.
  var firstData = days.indexWhere((d) => d.watched > 0 || d.skimmed > 0 || d.ms > 0);
  if (firstData < 0) firstData = days.length - 1;
  var streak = 0;
  for (var i = days.length - 1; i >= firstData; i--) {
    if (days[i].watched > config.budget) break;
    streak++;
  }
  return streak;
});

/// Refreshes everything that may have changed while the user was in Android settings.
void refreshAll(WidgetRef ref) {
  ref.invalidate(statusProvider);
  ref.invalidate(todayProvider);
  ref.invalidate(daysProvider);
  ref.invalidate(configProvider);
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'themeMode';

  @override
  ThemeMode build() {
    final saved = ref.watch(prefsProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.light);
  }

  void set(ThemeMode mode) {
    ref.read(prefsProvider).setString(_key, mode.name);
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class OnboardingNotifier extends Notifier<bool> {
  static const _key = 'onboardingDone';

  @override
  bool build() => ref.watch(prefsProvider).getBool(_key) ?? false;

  void complete() {
    ref.read(prefsProvider).setBool(_key, true);
    state = true;
  }

  void reset() {
    ref.read(prefsProvider).remove(_key);
    state = false;
  }
}

final onboardingDoneProvider = NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);
