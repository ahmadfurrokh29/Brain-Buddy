import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/triggers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// "Your patterns": busy-hours heat map plus trigger insights for the last [days] days.
class PatternsSection extends ConsumerWidget {
  final int days;
  final Map<String, int> appTotals;
  const PatternsSection({super.key, required this.days, required this.appTotals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(patternsProvider(days));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Your patterns', trailing: ProTag()),
      patterns.when(
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text('$e'),
        data: (p) {
          if (p.total < kMinReelsForTriggers) {
            return BBCard(
              child: Text('Keep using Brain Bean for a few days and your weak moments will show up here.',
                  style: TextStyle(color: context.muted)),
            );
          }
          final triggers = findTriggers(p, appTotals: appTotals);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BBCard(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Busy hours', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _HeatMap(heat: p.heat),
              ]),
            ),
            const SizedBox(height: 10),
            for (final t in triggers) ...[_TriggerCard(t: t), const SizedBox(height: 10)],
          ]);
        },
      ),
    ]);
  }
}

class _HeatMap extends StatelessWidget {
  final List<List<int>> heat;
  const _HeatMap({required this.heat});

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final max = heat.expand((r) => r).fold(0, (a, b) => a > b ? a : b);
    final empty = context.isDark ? BB.nightRaised : const Color(0xFFEDF1F5);
    return LayoutBuilder(builder: (context, box) {
      const labelW = 16.0, gap = 2.0;
      final cell = (box.maxWidth - labelW - gap * 23) / 24;
      return Column(children: [
        for (var d = 0; d < 7; d++)
          Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(children: [
              SizedBox(width: labelW, child: Text(_days[d], style: TextStyle(fontSize: 10, color: context.muted))),
              for (var h = 0; h < 24; h++) ...[
                Container(
                  width: cell,
                  height: cell,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: heat[d][h] == 0 || max == 0 ? empty : Color.lerp(BB.mint.withValues(alpha: 0.25), BB.coral, heat[d][h] / max),
                  ),
                ),
                if (h < 23) const SizedBox(width: gap),
              ],
            ]),
          ),
        const SizedBox(height: 4),
        Row(children: [
          const SizedBox(width: labelW),
          for (final h in const [0, 6, 12, 18])
            Expanded(child: Text(hourLabel(h), style: TextStyle(fontSize: 10, color: context.muted))),
        ]),
      ]);
    });
  }
}

class _TriggerCard extends StatelessWidget {
  final Trigger t;
  const _TriggerCard({required this.t});

  static const _icons = {
    TriggerKind.peakHour: Icons.schedule_rounded,
    TriggerKind.peakDay: Icons.calendar_today_rounded,
    TriggerKind.lateNight: Icons.bedtime_rounded,
    TriggerKind.earlyStart: Icons.wb_sunny_rounded,
    TriggerKind.reason: Icons.psychology_alt_rounded,
    TriggerKind.topApp: Icons.apps_rounded,
  };

  @override
  Widget build(BuildContext context) {
    // Triggers with an obvious fix link straight to it.
    final action = switch (t.kind) {
      TriggerKind.lateNight => 'Add a Bedtime schedule',
      TriggerKind.topApp => 'Set a per-app budget',
      _ => null,
    };
    return BBCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(backgroundColor: BB.coral.withValues(alpha: 0.15), child: Icon(_icons[t.kind], color: BB.coral)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(t.body, style: TextStyle(color: context.muted)),
            if (action != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => context.go('/limits'),
                  child: Text(action),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
