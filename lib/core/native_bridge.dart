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

  /// Pause counting for [minutes]. 0 resumes.
  Future<AppConfig> pause(int minutes) async =>
      AppConfig.fromMap((await _method.invokeMethod<Map>('pause', {'minutes': minutes}))!);

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
