import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_buddy.dart';
import '../../widgets/common.dart';

/// Brain Buddy Pro. Built now, charging later: while [kBetaAllPro] is on, everything is free and no
/// purchase can be made. Follows the fair-pay rules: full price in big text, close button always visible,
/// no fake timers, cancel anytime.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

enum _Plan { monthly, yearly, lifetime }

class _PaywallScreenState extends State<PaywallScreen> {
  _Plan _plan = _Plan.yearly;

  // Placeholder prices for Pakistan. Real prices come from Google Play (local currency) when billing is added.
  static const _prices = {
    _Plan.monthly: ('Monthly', 'Rs 250', 'per month', null),
    _Plan.yearly: ('Yearly', 'Rs 1,500', 'per year · Rs 125/month', 'Best value · 7 days free'),
    _Plan.lifetime: ('Lifetime', 'Rs 3,500', 'one payment', null),
  };

  static const _features = [
    (Icons.lock_rounded, 'Firm & Hard locks', 'Locks that really hold'),
    (Icons.schedule_rounded, 'Schedules', 'Bedtime, study and work hours'),
    (Icons.apps_rounded, 'Per-app budgets', 'A limit for each app'),
    (Icons.directions_walk_rounded, 'Earn your reels', 'Steps and focus add reels'),
    (Icons.insights_rounded, 'Trigger insights', 'Heat map and weak moments'),
    (Icons.table_view_rounded, 'Export your data', 'Your history as a spreadsheet'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final selected = _prices[_plan]!;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Close', onPressed: () => context.pop())],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          const Center(child: BrainBuddy(mood: Mood.fresh, size: 120)),
          const SizedBox(height: 8),
          Text('Brain Buddy Pro', style: t.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Stronger tools to scroll less.', style: t.bodyLarge?.copyWith(color: context.muted), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (kBetaAllPro)
            BBCard(
              color: BB.mint.withValues(alpha: 0.15),
              child: const Row(children: [
                Icon(Icons.celebration_rounded, color: BB.mint),
                SizedBox(width: 10),
                Expanded(
                  child: Text('All Pro features are free during the beta. Thank you for testing Brain Buddy!',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          BBCard(
            child: Column(children: [
              for (final f in _features)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: BB.mintLight, child: Icon(f.$1, color: BB.mintDark)),
                  title: Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(f.$3),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          for (final p in _Plan.values) ...[
            _PlanCard(
              title: _prices[p]!.$1,
              price: _prices[p]!.$2,
              note: _prices[p]!.$3,
              badge: _prices[p]!.$4,
              selected: _plan == p,
              onTap: () => setState(() => _plan = p),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          FilledButton(
            // No purchases during the beta; billing (RevenueCat + Google Play) is added at launch.
            onPressed: kBetaAllPro ? null : () {},
            child: Text(kBetaAllPro ? 'Free during beta' : (_plan == _Plan.yearly ? 'Start 7-day free trial' : 'Continue')),
          ),
          const SizedBox(height: 8),
          Text(
            _plan == _Plan.yearly
                ? '7 days free, then ${selected.$2} per year. Cancel anytime in Google Play.'
                : _plan == _Plan.monthly
                    ? '${selected.$2} per month. Cancel anytime in Google Play.'
                    : '${selected.$2} once. Yours forever.',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: context.muted),
          ),
          TextButton(onPressed: kBetaAllPro ? null : () {}, child: const Text('Restore purchase')),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String note;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.title, required this.price, required this.note, this.badge, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? BB.mint : Colors.transparent, width: 2),
      ),
      child: BBCard(
        onTap: onTap,
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? BB.mint : context.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: BB.sun.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
                      child: Text(badge!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB38600))),
                    ),
                  ),
                ],
              ]),
              Text(note, style: TextStyle(color: context.muted, fontSize: 13)),
            ]),
          ),
          // The full price, in big text.
          Text(price, style: Theme.of(context).textTheme.titleLarge),
        ]),
      ),
    );
  }
}
