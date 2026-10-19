import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_buddy.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      context.go(ref.read(onboardingDoneProvider) ? '/home' : '/welcome');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: BB.mint,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const BrainBuddy(mood: Mood.fresh, size: 140, glow: false),
          ).animate().scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack, duration: 500.ms),
          const SizedBox(height: 24),
          Text('Brain Buddy', style: t.displaySmall?.copyWith(color: Colors.white))
              .animate()
              .fadeIn(delay: 200.ms)
              .slideY(begin: 0.3),
          const SizedBox(height: 6),
          Text('Count less, live more', style: t.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)))
              .animate()
              .fadeIn(delay: 400.ms),
        ]),
      ),
    );
  }
}
