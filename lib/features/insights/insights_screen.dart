import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../onboarding/setup_apps_screen.dart' show AppBadge;
import 'patterns_section.dart';

enum _Range { day, week, month }

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  _Range _range = _Range.week;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final config = ref.watch(configProvider).value;
    final days = ref.watch(daysProvider(_range == _Range.month ? 30 : 7));

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: days.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final budget = config?.budget ?? 30;
          final shown = _range == _Range.day ? [list.last] : list;
          final total = shown.fold(0, (s, d) => s + d.watched);
          final minutes = shown.fold(0, (s, d) => s + d.minutes);
          final skimmed = shown.fold(0, (s, d) => s + d.skimmed);
          final unlocks = shown.fold(0, (s, d) => s + d.unlocks);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              SegmentedButton<_Range>(
                segments: const [
                  ButtonSegment(value: _Range.day, label: Text('Day')),
                  ButtonSegment(value: _Range.week, label: Text('Week')),
                  ButtonSegment(value: _Range.month, label: Text('Month')),
                ],
                selected: {_range},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 16),
              Row(children: [
                StatTile(icon: Icons.movie_filter_rounded, color: BB.mint, value: '$total', label: _range == _Range.day ? 'reels today' : 'reels'),
                const SizedBox(width: 10),
                StatTile(
                  icon: Icons.av_timer_rounded,
                  color: const Color(0xFF8BD17C),
                  value: _range == _Range.day ? formatMinutes(minutes) : '${(total / shown.length).round()}',
                  label: _range == _Range.day ? 'in reels' : 'daily average',
                ),
                const SizedBox(width: 10),
                StatTile(icon: Icons.lock_open_rounded, color: BB.coral, value: '$unlocks', label: 'extra unlocks'),
              ]),
              SectionTitle(_range == _Range.day ? 'Reels by hour' : 'Reels per day'),
              BBCard(
                padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
                child: SizedBox(
                  height: 200,
                  child: _range == _Range.day ? _HourChart(day: list.last) : _DaysChart(days: list, budget: budget),
                ),
              ),
              if (_range != _Range.day) ...[
                const SectionTitle('Time in reels'),
                BBCard(
                  child: Row(children: [
                    const Icon(Icons.timer_rounded, color: BB.mint, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: formatMinutes(minutes), style: t.titleLarge),
                        TextSpan(text: '  in ${shown.length} days • $skimmed skimmed', style: t.bodyMedium?.copyWith(color: context.muted)),
                      ])),
                    ),
                  ]),
                ),
              ],
              const SectionTitle('Apps'),
              _AppsBreakdown(days: shown),
              if (_range != _Range.day)
                PatternsSection(days: shown.length, appTotals: _watchedByApp(shown)),
              if (_range == _Range.day && list.last.intents.isNotEmpty) ...[
                const SectionTitle('Why you opened reels'),
                BBCard(
                  child: Column(children: [
                    for (final e in list.last.intents.entries)
                      ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(e.key), trailing: Text('${e.value}×')),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Watched reels per app name over [days].
Map<String, int> _watchedByApp(List<DaySummary> days) {
  final totals = <String, int>{};
  for (final d in days) {
    for (final a in d.apps) {
      totals[a.name] = (totals[a.name] ?? 0) + a.watched;
    }
  }
  return totals;
}

class _DaysChart extends StatelessWidget {
  final List<DaySummary> days;
  final int budget;
  const _DaysChart({required this.days, required this.budget});

  @override
  Widget build(BuildContext context) {
    final maxY = [budget, ...days.map((d) => d.watched)].reduce((a, b) => a > b ? a : b) * 1.2;
    final labelEvery = days.length > 10 ? 5 : 1;
    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 10 : maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${DateFormat('EEE d MMM').format(days[group.x].date)}\n${rod.toY.round()} reels',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: budget.toDouble(),
            color: BB.coral.withValues(alpha: 0.7),
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(show: true, alignment: Alignment.topRight, style: const TextStyle(color: BB.coral, fontSize: 11, fontWeight: FontWeight.w700), labelResolver: (_) => 'Budget'),
          ),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length || (days.length - 1 - i) % labelEvery != 0) return const SizedBox.shrink();
                final fmt = days.length > 10 ? 'd' : 'E';
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat(fmt).format(days[i].date), style: TextStyle(fontSize: 11, color: context.muted)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: days[i].watched.toDouble(),
                width: days.length > 10 ? 6 : 18,
                color: days[i].watched > budget ? BB.coral : BB.mint,
                borderRadius: BorderRadius.circular(6),
              ),
            ]),
        ],
      ),
    );
  }
}

class _HourChart extends StatelessWidget {
  final DaySummary day;
  const _HourChart({required this.day});

  @override
  Widget build(BuildContext context) {
    final maxY = day.hours.fold(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 5 : maxY * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final h = value.toInt();
                if (h % 6 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(h == 0 ? '12am' : h == 12 ? '12pm' : h < 12 ? '${h}am' : '${h - 12}pm', style: TextStyle(fontSize: 11, color: context.muted)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var h = 0; h < 24; h++)
            BarChartGroupData(x: h, barRods: [
              BarChartRodData(toY: day.hours[h].toDouble(), width: 7, color: BB.mint, borderRadius: BorderRadius.circular(4)),
            ]),
        ],
      ),
    );
  }
}

class _AppsBreakdown extends StatelessWidget {
  final List<DaySummary> days;
  const _AppsBreakdown({required this.days});

  @override
  Widget build(BuildContext context) {
    final byApp = <String, (int, int)>{};
    final pkgOf = <String, String>{};
    for (final d in days) {
      for (final a in d.apps) {
        final prev = byApp[a.name] ?? (0, 0);
        byApp[a.name] = (prev.$1 + a.watched, prev.$2 + a.ms);
        pkgOf[a.name] = a.pkg;
      }
    }
    if (byApp.isEmpty) {
      return BBCard(child: Text('Nothing counted yet. Scroll some reels and they will show up here.', style: TextStyle(color: context.muted)));
    }
    final total = byApp.values.fold(0, (s, v) => s + v.$1);
    final sorted = byApp.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    return BBCard(
      child: Column(children: [
        for (final e in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              AppBadge(name: e.key, pkg: pkgOf[e.key], size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('${e.value.$1} reels • ${formatMinutes((e.value.$2 / 60000).round())}', style: TextStyle(color: context.muted, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : e.value.$1 / total,
                      minHeight: 6,
                      color: BB.mint,
                      backgroundColor: BB.mint.withValues(alpha: 0.12),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
