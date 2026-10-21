import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../onboarding/setup_apps_screen.dart' show AppBadge;

/// "Per-app budgets" section of the Limits screen, e.g. Instagram 20, YouTube 10.
class AppBudgetsSection extends ConsumerWidget {
  final AppConfig c;
  const AppBudgetsSection({super.key, required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(targetsProvider).value ?? const <TargetApp>[];
    final apps = targets.where((a) => a.installed && a.pkgs.any(c.tracked.contains)).toList();
    final cfg = ref.read(configProvider.notifier);

    int? budgetOf(TargetApp a) => a.pkgs.map((p) => c.appBudgets[p]).whereType<int>().firstOrNull;

    void setBudget(TargetApp a, int? value) {
      final next = {...c.appBudgets}..removeWhere((k, _) => a.pkgs.contains(k));
      if (value != null) next[a.pkg] = value;
      cfg.setAppBudgets(next);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Per-app budgets', trailing: ProTag()),
      Text('Give an app its own limit. When it runs out, only that app\'s reels are locked.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.muted)),
      const SizedBox(height: 10),
      BBCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (final a in apps)
            _AppBudgetRow(
              app: a,
              budget: budgetOf(a),
              // During a lock budgets can only go down; the native side refuses loosening too.
              locked: c.isLocked,
              onChanged: (v) => setBudget(a, v),
            ),
          if (apps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No tracked apps installed.', style: TextStyle(color: context.muted)),
            ),
        ]),
      ),
    ]);
  }
}

class _AppBudgetRow extends StatelessWidget {
  final TargetApp app;
  final int? budget;
  final bool locked;
  final ValueChanged<int?> onChanged;
  const _AppBudgetRow({required this.app, required this.budget, required this.locked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final b = budget;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        AppBadge(name: app.name, pkg: app.pkg, size: 34),
        const SizedBox(width: 12),
        Expanded(child: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w700))),
        if (b != null) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: b > 5 ? () => onChanged(b - 5) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(width: 36, child: Text('$b', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: !locked && b < 500 ? () => onChanged(b + 5) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
        Switch(
          value: b != null,
          onChanged: (on) {
            if (on) {
              onChanged(20);
            } else if (!locked) {
              onChanged(null);
            }
          },
        ),
      ]),
    );
  }
}
