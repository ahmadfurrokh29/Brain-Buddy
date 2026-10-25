import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/startup.dart';
import '../../theme/app_theme.dart';

/// The splash: exactly the picture Android shows while Brain Bean starts, so both look like one screen.
/// Opens the app 1.2 s after the user's tap, or as soon as start-up is done if that took longer.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _total = 1200;
  static const _picture = AssetImage('assets/splash/splash.png');
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Show the first frame only once the picture is decoded; otherwise it flashes plain mint.
    precacheImage(_picture, context).whenComplete(WidgetsBinding.instance.allowFirstFrame);
    _open();
  }

  Future<void> _open() async {
    final since = await ref.read(bridgeProvider).sinceLaunch().catchError((_) => 0);
    await Future.wait([
      firebaseReady,
      Future<void>.delayed(Duration(milliseconds: max(0, _total - since))),
    ]);
    if (!mounted) return;
    context.go(ref.read(onboardingDoneProvider) ? '/home' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: BB.mint,
      // 320 x 400 dp, centred, like Android's start-up screen (tool/render_splash_test.dart).
      body: Center(child: Image(image: _picture, width: 320, height: 400)),
    );
  }
}
