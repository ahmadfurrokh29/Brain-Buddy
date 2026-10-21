import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_buddy.dart';
import '../../widgets/common.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 2) {
      context.go('/setup/apps');
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => context.go('/setup/apps'), child: const Text('Skip')),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: const [_SlideCounter(), _SlideMoods(), _SlidePrivate()],
            ),
          ),
          Dots(count: 3, index: _page),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: FilledButton(onPressed: _next, child: Text(_page == 2 ? 'Get started' : 'Next')),
          ),
        ]),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  final Widget art;
  final String title;
  final String body;
  const _Slide({required this.art, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        art,
        const SizedBox(height: 36),
        Text(title, style: t.headlineMedium, textAlign: TextAlign.center).animate().fadeIn().slideY(begin: 0.2),
        const SizedBox(height: 12),
        Text(body, style: t.bodyLarge?.copyWith(color: context.muted), textAlign: TextAlign.center).animate().fadeIn(delay: 150.ms),
      ]),
    );
  }
}

class _SlideCounter extends StatelessWidget {
  const _SlideCounter();

  @override
  Widget build(BuildContext context) {
    return _Slide(
      art: BBCard(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text('REELS TODAY', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.muted, letterSpacing: 1.2)),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: 142),
            duration: const Duration(milliseconds: 1600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text('$v', style: Theme.of(context).textTheme.displayLarge?.copyWith(color: BB.coral)),
          ),
        ]),
      ),
      title: 'You scroll more than you think',
      body: 'Most people scroll far more reels than they guess. Brain Buddy shows you the real number, live.',
    );
  }
}

class _SlideMoods extends StatelessWidget {
  const _SlideMoods();

  @override
  Widget build(BuildContext context) {
    return _Slide(
      art: Column(children: [
        const BrainBuddy(mood: Mood.fresh, size: 150),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final m in Mood.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(children: [
                BrainBuddy(mood: m, size: 56, glow: false),
                Text(m.label, style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
        ]),
      ]),
      title: 'Watch your brain buddy react',
      body: 'Your buddy is fresh in the morning and gets tired the more you scroll. On good days it heals.',
    );
  }
}

class _SlidePrivate extends StatelessWidget {
  const _SlidePrivate();

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: BBCard(
            child: Row(children: [
              CircleAvatar(backgroundColor: BB.mintLight, child: Icon(icon, color: BB.mintDark)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(body, style: TextStyle(color: context.muted)),
                ]),
              ),
            ]),
          ),
        );
    return _Slide(
      art: Column(children: [
        row(Icons.phone_android_rounded, 'Stays on your phone', 'Your scroll data is never uploaded.'),
        row(Icons.person_off_rounded, 'No login, no survey', 'Open the app and start right away.'),
        row(Icons.favorite_rounded, 'Free core features', 'Counting and daily limits are free forever.'),
      ]),
      title: 'Free, private, no login',
      body: 'Your habits belong to you alone.',
    );
  }
}
