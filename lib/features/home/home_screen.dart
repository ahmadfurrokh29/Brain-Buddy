import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_buddy.dart';
import '../../widgets/common.dart';
import '../limits/earn_reels.dart';
import '../onboarding/setup_apps_screen.dart' show AppBadge;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final config = ref.watch(configProvider);
    final status = ref.watch(statusProvider).value;
    final streak = ref.watch(streakProvider).value ?? 0;

    if (!today.hasValue || !config.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final d = today.value!;
    final c = config.value!;
    final allowance = c.allowanceToday;
    final mood = Mood.of(d.watched, allowance);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => refreshAll(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(children: [
                const BrainBuddy(mood: Mood.fresh, size: 36, glow: false),
                const SizedBox(width: 8),
                Expanded(child: Text('Brain Buddy', style: t.titleLarge)),
                _TrackingPill(status: status, config: c),
              ]),
              const SizedBox(height: 16),
              BBCard(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                child: Column(children: [
                  _BrainRing(watched: d.watched, allowance: allowance, mood: mood),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: d.watched),
                      duration: const Duration(milliseconds: 700),
                      builder: (context, v, _) => Text('$v', style: t.displayMedium?.copyWith(color: mood == Mood.melted ? BB.coral : null)),
                    ),
                    Text(' / $allowance', style: t.titleLarge?.copyWith(color: context.muted)),
                  ]),
                  Text('reels today', style: t.bodyMedium?.copyWith(color: context.muted)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: mood.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '${mood.label} buddy • ${_leftText(d.watched, allowance)}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color.lerp(mood.color, BB.ink, 0.45)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(mood.message, style: t.bodySmall?.copyWith(color: context.muted)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                StatTile(icon: Icons.timer_rounded, color: BB.mint, value: formatMinutes(d.minutes), label: 'in reels'),
                const SizedBox(width: 10),
                if (c.showSkimmed) ...[
                  StatTile(icon: Icons.fast_forward_rounded, color: const Color(0xFFFF9F59), value: '${d.skimmed}', label: 'skimmed'),
                  const SizedBox(width: 10),
                ],
                StatTile(icon: Icons.local_fire_department_rounded, color: BB.coral, value: '$streak', label: streak == 1 ? 'day streak' : 'day streak'),
              ]),
              if (c.earnEnabled) ...[const SizedBox(height: 12), EarnReelsCard(c: c)],
              SectionTitle('App activity', trailing: TextButton(onPressed: () => context.go('/insights'), child: const Text('Details'))),
              if (d.apps.isEmpty)
                BBCard(
                  child: Row(children: [
                    const Icon(Icons.spa_rounded, color: BB.mint),
                    const SizedBox(width: 12),
                    Expanded(child: Text('No reels yet today. Nice and calm! 🌿', style: t.bodyMedium)),
                  ]),
                )
              else
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: d.apps.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => _AppChip(stat: d.apps[i]),
                  ),
                ),
              const SizedBox(height: 16),
              _PauseButton(config: c),
            ],
          ),
        ),
      ),
    );
  }

  static String _leftText(int watched, int allowance) {
    final left = allowance - watched;
    if (left > 0) return '$left reels left';
    if (left == 0) return 'limit reached';
    return '${-left} over limit';
  }
}

class _TrackingPill extends StatelessWidget {
  final DeviceStatus? status;
  final AppConfig config;
  const _TrackingPill({required this.status, required this.config});

  @override
  Widget build(BuildContext context) {
    if (config.isPaused) {
      return const StatusPill(label: 'Paused', color: Color(0xFFE0A800), icon: Icons.pause_circle_rounded);
    }
    if (status == null) return const SizedBox.shrink();
    if (status!.healthy) {
      return const StatusPill(label: 'Tracking on', color: BB.mintDark, icon: Icons.circle);
    }
    return StatusPill(
      label: 'Tracking off — fix',
      color: BB.coral,
      icon: Icons.error_rounded,
      onTap: () => context.push('/doctor'),
    );
  }
}

/// The brain inside a progress ring that fills as reels are watched.
class _BrainRing extends StatelessWidget {
  final int watched;
  final int allowance;
  final Mood mood;
  const _BrainRing({required this.watched, required this.allowance, required this.mood});

  @override
  Widget build(BuildContext context) {
    final progress = allowance <= 0 ? 1.0 : watched / allowance;
    return SizedBox.square(
      dimension: 230,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(size: const Size.square(230), painter: _RingPainter(v)),
        ),
        BrainBuddy(mood: mood, size: 170, count: watched),
      ]),
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.06;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..color = BB.mint.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * p,
      false,
      Paint()
        ..shader = const SweepGradient(
          colors: [BB.mint, Color(0xFF8BD17C), BB.sun, Color(0xFFFF9F59), BB.coral],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

class _AppChip extends StatelessWidget {
  final AppStat stat;
  const _AppChip({required this.stat});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: BBCard(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          AppBadge(name: stat.name, pkg: stat.pkg, size: 36),
          const SizedBox(height: 6),
          Text('${stat.watched} reels', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(formatMinutes((stat.ms / 60000).round()), style: TextStyle(color: context.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _PauseButton extends ConsumerWidget {
  final AppConfig config;
  const _PauseButton({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (config.isPaused) {
      final until = DateTime.fromMillisecondsSinceEpoch(config.pausedUntil);
      return OutlinedButton.icon(
        onPressed: () => ref.read(configProvider.notifier).pause(0),
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text('Paused until ${TimeOfDay.fromDateTime(until).format(context)} — Resume'),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => showPauseSheet(context, ref),
      icon: const Icon(Icons.pause_rounded),
      label: const Text('Pause tracking'),
    );
  }
}

/// Pause choices, also used from Settings.
Future<void> showPauseSheet(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final options = {
    '15 minutes': 15,
    '1 hour': 60,
    'Until tomorrow': tomorrow.difference(now).inMinutes + 1,
  };
  final minutes = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Pause counting for a while — handy when a banking app asks you to turn off accessibility apps.',
              textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
        ),
        for (final e in options.entries)
          ListTile(leading: const Icon(Icons.pause_circle_outline_rounded), title: Text(e.key), onTap: () => Navigator.pop(context, e.value)),
      ]),
    ),
  );
  if (minutes != null) await ref.read(configProvider.notifier).pause(minutes);
}
