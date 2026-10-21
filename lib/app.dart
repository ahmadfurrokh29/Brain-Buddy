import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'features/doctor/doctor_screen.dart';
import 'features/home/home_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/limits/limits_screen.dart';
import 'features/onboarding/permissions_screen.dart';
import 'features/onboarding/setup_apps_screen.dart';
import 'features/onboarding/splash_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/pro/paywall_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/main_shell.dart';
import 'theme/app_theme.dart';

final _router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: '/setup/apps', builder: (_, _) => const SetupAppsScreen()),
    GoRoute(path: '/setup/permissions', builder: (_, _) => const PermissionsScreen()),
    GoRoute(path: '/doctor', builder: (_, _) => const DoctorScreen()),
    GoRoute(path: '/pro', builder: (_, _) => const PaywallScreen()),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => MainShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/limits', builder: (_, _) => const LimitsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
      ],
    ),
  ],
);

class BrainBuddyApp extends ConsumerStatefulWidget {
  const BrainBuddyApp({super.key});

  @override
  ConsumerState<BrainBuddyApp> createState() => _BrainBuddyAppState();
}

class _BrainBuddyAppState extends ConsumerState<BrainBuddyApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back from Android settings or a reel app: refresh counts and permission status.
    _lifecycle = AppLifecycleListener(onResume: () => refreshAll(ref));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Brain Buddy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
    );
  }
}
