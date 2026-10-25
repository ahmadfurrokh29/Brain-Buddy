import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/startup.dart';

Future<void> main() async {
  // Android's start-up screen stays up until the splash picture is ready to draw (see SplashScreen).
  WidgetsFlutterBinding.ensureInitialized().deferFirstFrame();
  final prefs = await SharedPreferences.getInstance();
  // Draw the splash straight away; Firebase starts behind it (see SplashScreen).
  startFirebase(prefs);

  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const BrainBuddyApp(),
  ));
}
