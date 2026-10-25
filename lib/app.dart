import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/nudges.dart';
import 'core/providers.dart';
import 'core/squads.dart';
import 'core/startup.dart';
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
import 'features/squads/squad_detail_screen.dart';
import 'features/squads/squads_screen.dart';
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
    GoRoute(path: '/squads/:id', builder: (_, state) => SquadDetailScreen(squadId: state.pathParameters['id']!)),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => MainShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/limits', builder: (_, _) => const LimitsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/squads', builder: (_, _) => const SquadsScreen())]),
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
    // Firebase finishes starting behind the splash screen; these need it.
    firebaseReady.then((_) {
      if (mounted) _listenToFirebase();
    });
  }

  void _listenToFirebase() {
    // After signing in (on this or a new phone), tell the background counter which squads to sync.
    ref.listenManual(authUserProvider, (prev, next) {
      if (next.value != null && prev?.value?.uid != next.value!.uid) {
        ref.read(squadsRepoProvider).refreshSync().catchError((_) {});
        registerPushToken().catchError((Object e) => debugPrint('BrainBuddy push: could not register: $e'));
      }
    }, fireImmediately: true);
    // A nudge while Brain Bean is open: Android only shows pushes automatically in the background.
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      _messenger.currentState?.showSnackBar(SnackBar(content: Text('${n.title ?? ''}\n${n.body ?? ''}')));
    });
  }

  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Brain Bean',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
      scaffoldMessengerKey: _messenger,
    );
  }
}
