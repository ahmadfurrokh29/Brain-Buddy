import 'package:flutter/services.dart';

import 'models.dart';

/// Talks to the Kotlin counting engine (see android/.../NativeBridge.kt).
class NativeBridge {
  static const _method = MethodChannel('brain_buddy/native');
  static const _events = EventChannel('brain_buddy/events');

  /// Fires whenever a reel is counted or data changes.
  Stream<void> get changes => _events.receiveBroadcastStream().map((_) {});

  Future<AppConfig> getConfig() async => AppConfig.fromMap((await _method.invokeMethod<Map>('getConfig'))!);

  Future<AppConfig> setConfig(Map<String, Object?> values) async =>
      AppConfig.fromMap((await _method.invokeMethod<Map>('setConfig', values))!);

  /// Settings update without reading the result (used by the Squads code).
  Future<void> setConfigRaw(Map<String, Object?> values) => _method.invokeMethod('setConfig', values);

  /// Sends this week's counts to the user's Squads now.
  Future<void> syncSquads() => _method.invokeMethod('syncSquads');

  Future<List<TargetApp>> getTargets() async =>
      (await _method.invokeMethod<List>('getTargets'))!.map((e) => TargetApp.fromMap(e as Map)).toList();

  /// Launcher icons of installed reel apps (PNG bytes), keyed by package name.
  Future<Map<String, Uint8List>> getAppIcons() async {
    final raw = await _method.invokeMethod<Map>('getAppIcons') ?? const {};
    return raw.map((k, v) => MapEntry(k as String, v as Uint8List));
  }

  Future<DeviceStatus> getStatus() async => DeviceStatus.fromMap((await _method.invokeMethod<Map>('getStatus'))!);

  Future<DaySummary> getDay([String? day]) async =>
      DaySummary.fromMap((await _method.invokeMethod<Map>('getDay', {'day': day}))!);

  /// The last [count] days, oldest first, ending today.
  Future<List<DaySummary>> getDays(int count) async =>
      (await _method.invokeMethod<List>('getDays', {'count': count}))!.map((e) => DaySummary.fromMap(e as Map)).toList();

  /// Habits over the last [count] days.
  Future<Patterns> getPatterns(int count) async =>
      Patterns.fromMap((await _method.invokeMethod<Map>('getPatterns', {'count': count}))!);

  /// Pause counting for [minutes]. 0 resumes.
  Future<AppConfig> pause(int minutes) async =>
      AppConfig.fromMap((await _method.invokeMethod<Map>('pause', {'minutes': minutes}))!);

  /// Starts a focus session: reels are blocked until it ends, and finishing earns reels.
  Future<AppConfig> startFocus(int minutes) async =>
      AppConfig.fromMap((await _method.invokeMethod<Map>('startFocus', {'minutes': minutes}))!);

  /// Gives up the current focus session (no reward).
  Future<AppConfig> cancelFocus() async => AppConfig.fromMap((await _method.invokeMethod<Map>('cancelFocus'))!);

  Future<void> requestActivityRecognition() => _method.invokeMethod('requestActivityRecognition');

  Future<String> exportCsv() async => (await _method.invokeMethod<String>('exportCsv'))!;

  Future<String> exportBackup() async => (await _method.invokeMethod<String>('exportBackup'))!;
  Future<void> importBackup(String json) => _method.invokeMethod('importBackup', {'json': json});
  Future<void> deleteAllData() => _method.invokeMethod('deleteAllData');

  Future<void> openAccessibilitySettings() => _method.invokeMethod('openAccessibilitySettings');
  Future<void> openBatterySettings() => _method.invokeMethod('openBatterySettings');
  Future<void> openAutostartSettings() => _method.invokeMethod('openAutostartSettings');
  Future<void> openAppSettings() => _method.invokeMethod('openAppSettings');
  Future<void> openNotificationSettings() => _method.invokeMethod('openNotificationSettings');
  Future<void> requestNotifications() => _method.invokeMethod('requestNotifications');
}
