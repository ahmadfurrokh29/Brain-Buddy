import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'providers.dart';

/// Completes once Firebase (sign-in, Squads, backup, crash reports) is ready. It starts while the splash
/// screen is already showing; the splash waits for it before opening the app.
late final Future<void> firebaseReady;

void startFirebase(SharedPreferences prefs) {
  firebaseReady = _start(prefs);
}

Future<void> _start(SharedPreferences prefs) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Crash reports help fix bugs during the beta. Users can switch them off in Settings.
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(prefs.getBool(kCrashReportsKey) ?? true);
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
