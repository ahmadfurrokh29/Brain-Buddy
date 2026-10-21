import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// A time window when reels are blocked, e.g. Bedtime 23:00–07:00. Times are minutes after midnight;
/// days are 1 (Monday) to 7 (Sunday). A window can run past midnight.
class Schedule {
  final String id;
  final String name;
  final int start;
  final int end;
  final List<int> days;
  final bool enabled;

  const Schedule({required this.id, required this.name, required this.start, required this.end, required this.days, this.enabled = true});

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Schedule',
        start: _int(j['start']),
        end: _int(j['end']),
        days: ((j['days'] as List?) ?? const []).map(_int).toList(),
        enabled: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'start': start, 'end': end, 'days': days, 'enabled': enabled};

  Schedule copyWith({String? name, int? start, int? end, List<int>? days, bool? enabled}) => Schedule(
        id: id,
        name: name ?? this.name,
        start: start ?? this.start,
        end: end ?? this.end,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
      );
}

/// User settings, owned by the native side so the counter can use them in the background.
class AppConfig {
  final Set<String> tracked;
  final int budget;
  final int dwellSec;
  final bool showSkimmed;
  final bool ignoreAds;
  final int dayStartHour;
  final bool floatingCounter;
  final bool intentPause;
  final int intentWaitSec;
  final bool warn50;
  final bool warn80;
  final bool warn100;
  final int pausedUntil;
  final int extraToday;

  /// "gentle", "firm" or "hard".
  final String lockMode;

  /// How long a Hard lock lasts: "1h", "3h" or "tomorrow".
  final String hardDuration;
  final int emergencyPerWeek;
  final int emergencyLeft;
  final int hardLockedUntil;
  final List<Schedule> schedules;

  // Earn your reels: steps and focus sessions add reels to today's budget.
  final bool earnEnabled;
  final int stepsPerReward;
  final int focusMinutes;
  final int maxEarnPerDay;
  final int earnedToday;
  final int stepsToday;
  final int focusUntil;
  final int rewardReels;

  /// Optional daily limits for single apps, by package name.
  final Map<String, int> appBudgets;

  /// The schedule blocking reels right now, if any.
  final String? activeScheduleId;
  final int activeScheduleUntil;

  const AppConfig({
    required this.earnEnabled,
    required this.stepsPerReward,
    required this.focusMinutes,
    required this.maxEarnPerDay,
    required this.earnedToday,
    required this.stepsToday,
    required this.focusUntil,
    required this.rewardReels,
    required this.schedules,
    required this.appBudgets,
    required this.activeScheduleId,
    required this.activeScheduleUntil,
    required this.lockMode,
    required this.hardDuration,
    required this.emergencyPerWeek,
    required this.emergencyLeft,
    required this.hardLockedUntil,
    required this.tracked,
    required this.budget,
    required this.dwellSec,
    required this.showSkimmed,
    required this.ignoreAds,
    required this.dayStartHour,
    required this.floatingCounter,
    required this.intentPause,
    required this.intentWaitSec,
    required this.warn50,
    required this.warn80,
    required this.warn100,
    required this.pausedUntil,
    required this.extraToday,
  });

  factory AppConfig.fromMap(Map<Object?, Object?> m) => AppConfig(
        earnEnabled: m['earnEnabled'] as bool? ?? false,
        stepsPerReward: _int(m['stepsPerReward']),
        focusMinutes: _int(m['focusMinutes']),
        maxEarnPerDay: _int(m['maxEarnPerDay']),
        earnedToday: _int(m['earnedToday']),
        stepsToday: _int(m['stepsToday']),
        focusUntil: _int(m['focusUntil']),
        rewardReels: _int(m['rewardReels']),
        schedules: ((jsonDecode(m['schedules'] as String? ?? '[]') as List).cast<Map<String, dynamic>>()).map(Schedule.fromJson).toList(),
        appBudgets: (jsonDecode(m['appBudgets'] as String? ?? '{}') as Map).map((k, v) => MapEntry(k as String, _int(v))),
        activeScheduleId: (m['activeSchedule'] as Map?)?['id'] as String?,
        activeScheduleUntil: _int((m['activeSchedule'] as Map?)?['until']),
        lockMode: m['lockMode'] as String? ?? 'gentle',
        hardDuration: m['hardDuration'] as String? ?? 'tomorrow',
        emergencyPerWeek: _int(m['emergencyPerWeek']),
        emergencyLeft: _int(m['emergencyLeft']),
        hardLockedUntil: _int(m['hardLockedUntil']),
        tracked: ((m['tracked'] as List?) ?? const []).map((e) => e.toString()).toSet(),
        budget: _int(m['budget']),
        dwellSec: _int(m['dwellSec']),
        showSkimmed: m['showSkimmed'] as bool? ?? true,
        ignoreAds: m['ignoreAds'] as bool? ?? true,
        dayStartHour: _int(m['dayStartHour']),
        floatingCounter: m['floatingCounter'] as bool? ?? true,
        intentPause: m['intentPause'] as bool? ?? false,
        intentWaitSec: _int(m['intentWaitSec']),
        warn50: m['warn50'] as bool? ?? false,
        warn80: m['warn80'] as bool? ?? true,
        warn100: m['warn100'] as bool? ?? true,
        pausedUntil: _int(m['pausedUntil']),
        extraToday: _int(m['extraToday']),
      );

  int get allowanceToday => budget + extraToday + earnedToday;
  bool get isFocusing => DateTime.now().millisecondsSinceEpoch < focusUntil;
  bool get isPaused => DateTime.now().millisecondsSinceEpoch < pausedUntil;

  /// A Hard lock is running: reels are blocked and rules can't be loosened until it ends.
  bool get isHardLocked => DateTime.now().millisecondsSinceEpoch < hardLockedUntil;

  /// Reels are blocked right now by a Hard lock or a schedule; rules can only get stricter.
  bool get isLocked => isHardLocked || activeScheduleId != null;
}

class AppStat {
  final String pkg;
  final String name;
  final int watched;
  final int skimmed;
  final int ms;

  const AppStat({required this.pkg, required this.name, required this.watched, required this.skimmed, required this.ms});

  factory AppStat.fromMap(Map<Object?, Object?> m) => AppStat(
        pkg: m['pkg'] as String,
        name: m['name'] as String,
        watched: _int(m['watched']),
        skimmed: _int(m['skimmed']),
        ms: _int(m['ms']),
      );
}

/// Everything counted on one day.
class DaySummary {
  final String day;
  final int watched;
  final int skimmed;
  final int ads;
  final int ms;
  final int unlocks;
  final List<AppStat> apps;
  final List<int> hours;
  final Map<String, int> intents;

  const DaySummary({
    required this.day,
    required this.watched,
    required this.skimmed,
    required this.ads,
    required this.ms,
    required this.unlocks,
    required this.apps,
    required this.hours,
    required this.intents,
  });

  factory DaySummary.fromMap(Map<Object?, Object?> m) => DaySummary(
        day: m['day'] as String,
        watched: _int(m['watched']),
        skimmed: _int(m['skimmed']),
        ads: _int(m['ads']),
        ms: _int(m['ms']),
        unlocks: _int(m['unlocks']),
        apps: ((m['apps'] as List?) ?? const []).map((e) => AppStat.fromMap(e as Map)).toList(),
        hours: ((m['hours'] as List?) ?? List.filled(24, 0)).map(_int).toList(),
        intents: ((m['intents'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), _int(v))),
      );

  int get minutes => (ms / 60000).round();
  DateTime get date => DateTime.parse(day);
}

/// Health of the counter on this phone (used by Permissions and the Reliability Doctor).
class DeviceStatus {
  final bool accessibility;
  final bool serviceRunning;
  final bool battery;
  final bool backgroundRestricted;
  final bool notifications;
  final int lastEventAt;
  final String lastError;
  final String manufacturer;
  final String model;
  final int sdk;
  final bool paused;

  const DeviceStatus({
    required this.accessibility,
    required this.serviceRunning,
    required this.battery,
    required this.backgroundRestricted,
    required this.notifications,
    required this.lastEventAt,
    required this.lastError,
    required this.manufacturer,
    required this.model,
    required this.sdk,
    required this.paused,
  });

  factory DeviceStatus.fromMap(Map<Object?, Object?> m) => DeviceStatus(
        accessibility: m['accessibility'] as bool? ?? false,
        serviceRunning: m['serviceRunning'] as bool? ?? false,
        battery: m['battery'] as bool? ?? false,
        backgroundRestricted: m['backgroundRestricted'] as bool? ?? false,
        notifications: m['notifications'] as bool? ?? false,
        lastEventAt: _int(m['lastEventAt']),
        lastError: m['lastError'] as String? ?? '',
        manufacturer: m['manufacturer'] as String? ?? '',
        model: m['model'] as String? ?? '',
        sdk: _int(m['sdk']),
        paused: m['paused'] as bool? ?? false,
      );

  /// Accessibility is switched on but Android has stopped the counter.
  bool get killed => accessibility && !serviceRunning;
  bool get healthy => accessibility && serviceRunning && !backgroundRestricted;

  /// Battery is fully OK only when optimisation is off and background activity isn't restricted.
  bool get batteryOk => battery && !backgroundRestricted;
}

class TargetApp {
  final String pkg;
  final List<String> pkgs;
  final String name;
  final bool installed;

  const TargetApp({required this.pkg, required this.pkgs, required this.name, required this.installed});

  factory TargetApp.fromMap(Map<Object?, Object?> m) => TargetApp(
        pkg: m['pkg'] as String,
        pkgs: ((m['pkgs'] as List?) ?? const []).map((e) => e.toString()).toList(),
        name: m['name'] as String,
        installed: m['installed'] as bool? ?? false,
      );
}

/// Brain Buddy's mood. Same thresholds and brain colours as the native side (Mood.kt).
///
/// [color] is the mood's accent (glow, pill). [brain], [brainTop] and [brainOutline] colour the brain
/// itself: healthy pink when fresh, fading through salmon, dull yellow and burnt orange to a drained
/// grey-purple when melted.
enum Mood {
  fresh('Fresh', 'Feeling sharp and happy!', BB.mint, Color(0xFFFF9EC0), Color(0xFFFFC4D9), Color(0xFFE0608F)),
  okay('Okay', 'Doing fine. Keep it chill.', Color(0xFF8BD17C), Color(0xFFFFB09A), Color(0xFFFFD0C2), Color(0xFFE07A5F)),
  tired('Tired', 'Getting a bit sleepy…', BB.sun, Color(0xFFF2C580), Color(0xFFF9DDB0), Color(0xFFC9963F)),
  fried('Fried', 'Dizzy! Time to slow down.', Color(0xFFFF9F59), Color(0xFFF58F5B), Color(0xFFFFB892), Color(0xFFC9612F)),
  melted('Melted', 'Brain is melting. Break time!', BB.coral, Color(0xFFA99ACB), Color(0xFFC9BEE3), Color(0xFF7A6AA6));

  final String label;
  final String message;
  final Color color;
  final Color brain;
  final Color brainTop;
  final Color brainOutline;
  const Mood(this.label, this.message, this.color, this.brain, this.brainTop, this.brainOutline);

  static Mood of(int watched, int budget) {
    if (budget <= 0) return Mood.melted;
    final r = watched / budget;
    if (r < 0.25) return Mood.fresh;
    if (r < 0.5) return Mood.okay;
    if (r < 0.8) return Mood.tired;
    if (r <= 1.0) return Mood.fried;
    return Mood.melted;
  }
}
