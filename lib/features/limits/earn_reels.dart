import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// "Earn your reels" card: step progress toward the next reward, and focus sessions.
/// Shown on Home (when switched on) and on the Limits screen.
class EarnReelsCard extends ConsumerStatefulWidget {
  final AppConfig c;

  /// On the Limits screen the card also has the on/off switch and settings.
  final bool showSettings;
  const EarnReelsCard({super.key, required this.c, this.showSettings = false});

  @override
  ConsumerState<EarnReelsCard> createState() => _EarnReelsCardState();
}

class _EarnReelsCardState extends ConsumerState<EarnReelsCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh the focus countdown every second while a session runs.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.c.focusUntil > 0 && mounted) {
        setState(() {});
        if (!widget.c.isFocusing) ref.read(configProvider.notifier).reload();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    if (on) await ref.read(bridgeProvider).requestActivityRecognition();
    await ref.read(configProvider.notifier).set({'earnEnabled': on});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final t = Theme.of(context).textTheme;
    final cfg = ref.read(configProvider.notifier);
    final stepsInto = c.stepsPerReward == 0 ? 0 : c.stepsToday % c.stepsPerReward;
    final capped = c.earnedToday >= c.maxEarnPerDay;
    final steps = NumberFormat.decimalPattern();

    return BBCard(
      color: BB.sun.withValues(alpha: context.isDark ? 0.12 : 0.18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.directions_walk_rounded, color: Color(0xFFE0A800)),
          const SizedBox(width: 8),
          Expanded(child: Text('Earn your reels', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (widget.showSettings) Switch(value: c.earnEnabled, onChanged: _toggle) else const ProTag(),
        ]),
        if (widget.showSettings && !c.earnEnabled)
          Text('Walk ${steps.format(c.stepsPerReward)} steps or finish a ${c.focusMinutes}-minute focus to add ${c.rewardReels} reels '
              '(up to ${c.maxEarnPerDay} a day).', style: TextStyle(color: context.muted)),
        if (c.earnEnabled) ...[
          const SizedBox(height: 8),
          Text(
            capped
                ? 'You earned the daily maximum of ${c.maxEarnPerDay} reels. Nice!'
                : '${steps.format(stepsInto)} / ${steps.format(c.stepsPerReward)} steps → +${c.rewardReels} reels',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: capped ? 1 : stepsInto / c.stepsPerReward,
              minHeight: 8,
              color: const Color(0xFFE0A800),
              backgroundColor: BB.sun.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 6),
          Text('Earned today: +${c.earnedToday} reels · ${steps.format(c.stepsToday)} steps',
              style: t.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(height: 10),
          if (c.isFocusing)
            Row(children: [
              const Icon(Icons.self_improvement_rounded, color: BB.mint),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Focus: ${_left(c.focusUntil)} left · reels are blocked',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: () => _confirmGiveUp(context), child: const Text('Give up')),
            ])
          else
            OutlinedButton.icon(
              onPressed: capped ? null : () => cfg.startFocus(c.focusMinutes),
              icon: const Icon(Icons.timer_outlined),
              label: Text('Start ${c.focusMinutes}-min focus (+${c.rewardReels} reels)'),
            ),
        ],
        if (widget.showSettings && c.earnEnabled) ...[
          const Divider(height: 24),
          _Setting(
            label: 'Steps per reward',
            value: c.stepsPerReward,
            options: const [500, 1000, 2000, 3000],
            format: (v) => '${steps.format(v)} steps',
            onChanged: (v) => cfg.set({'stepsPerReward': v}),
          ),
          _Setting(
            label: 'Focus session',
            value: c.focusMinutes,
            options: const [15, 25, 45, 60],
            format: (v) => '$v min',
            onChanged: (v) => cfg.set({'focusMinutes': v}),
          ),
          _Setting(
            label: 'Most reels earned per day',
            value: c.maxEarnPerDay,
            options: const [10, 20, 30, 50, 100],
            format: (v) => '$v reels',
            onChanged: (v) => cfg.set({'maxEarnPerDay': v}),
          ),
        ],
      ]),
    );
  }

  String _left(int until) {
    final left = Duration(milliseconds: (until - DateTime.now().millisecondsSinceEpoch).clamp(0, 1 << 31));
    final m = left.inMinutes, s = left.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmGiveUp(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give up this focus?'),
        content: const Text('You won\'t earn reels for this session.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Give up', style: TextStyle(color: BB.coral))),
        ],
      ),
    );
    if (ok == true) await ref.read(configProvider.notifier).cancelFocus();
  }
}

class _Setting extends StatelessWidget {
  final String label;
  final int value;
  final List<int> options;
  final String Function(int) format;
  final ValueChanged<int> onChanged;
  const _Setting({required this.label, required this.value, required this.options, required this.format, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = {...options, value}.toList()..sort();
    return Row(children: [
      Expanded(child: Text(label)),
      BBDropdown<int>(value: value, options: items, label: format, onChanged: onChanged),
    ]);
  }
}
