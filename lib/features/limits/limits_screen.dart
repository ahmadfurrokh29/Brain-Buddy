import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class LimitsScreen extends ConsumerWidget {
  const LimitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Limits & Locks')),
      body: config.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (c) => _LimitsBody(c: c),
      ),
    );
  }
}

class _LimitsBody extends ConsumerWidget {
  final AppConfig c;
  const _LimitsBody({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cfg = ref.read(configProvider.notifier);
    final locked = c.isHardLocked;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        if (locked) ...[
          _HardLockBanner(until: DateTime.fromMillisecondsSinceEpoch(c.hardLockedUntil)),
          const SizedBox(height: 12),
        ],
        BBCard(
          child: Column(children: [
            Text('DAILY REEL BUDGET', style: t.labelLarge?.copyWith(color: context.muted, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Steps of 5 for small budgets, 10 for bigger ones, so reaching 500 doesn't take 100 taps.
              _RoundButton(icon: Icons.remove_rounded, onTap: c.budget > 10 ? () => cfg.set({'budget': c.budget - (c.budget > 100 ? 10 : 5)}) : null),
              SizedBox(
                width: 140,
                child: Column(children: [
                  Text('${c.budget}', style: t.displayMedium),
                  Text('reels a day', style: t.bodyMedium?.copyWith(color: context.muted)),
                ]),
              ),
              // A running Hard lock can't be loosened, so the budget can only go down.
              _RoundButton(
                icon: Icons.add_rounded,
                onTap: c.budget < 500 && !locked ? () => cfg.set({'budget': (c.budget + (c.budget >= 100 ? 10 : 5)).clamp(10, 500)}) : null,
              ),
            ]),
            if (c.extraToday > 0) ...[
              const SizedBox(height: 8),
              Text('+${c.extraToday} extra unlocked today', style: t.bodySmall?.copyWith(color: BB.coral, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
        const SectionTitle('Lock style'),
        Text('What happens when you reach your budget. Only the reels part is locked: messages, stories and posts still work.',
            style: t.bodySmall?.copyWith(color: context.muted)),
        const SizedBox(height: 10),
        _LockCard(
          title: 'Gentle',
          body: 'A calm breathing break. Then close the app or allow 5 more reels.',
          icon: Icons.spa_rounded,
          selected: c.lockMode == 'gentle',
          enabled: !locked,
          onTap: () => cfg.set({'lockMode': 'gentle'}),
        ),
        _LockCard(
          title: 'Firm',
          body: 'Wait 60 seconds, then type why you want more reels to unlock 5.',
          icon: Icons.hourglass_bottom_rounded,
          selected: c.lockMode == 'firm',
          pro: true,
          enabled: !locked,
          onTap: () => cfg.set({'lockMode': 'firm'}),
        ),
        _LockCard(
          title: 'Hard',
          body: 'Reels stay locked for the time you choose. Only emergency unlocks can open them.',
          icon: Icons.lock_rounded,
          selected: c.lockMode == 'hard',
          pro: true,
          onTap: () => cfg.set({'lockMode': 'hard'}),
          child: c.lockMode == 'hard' ? _HardOptions(c: c, locked: locked) : null,
        ),
        const SectionTitle('Before you scroll'),
        BBCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              value: c.intentPause,
              onChanged: (v) => cfg.set({'intentPause': v}),
              title: const Text('"Why are you here?" pause', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('A short pause asks your reason before reels open (at most every 10 min).'),
            ),
            if (c.intentPause)
              ListTile(
                title: const Text('Wait before buttons appear'),
                trailing: DropdownButton<int>(
                  value: c.intentWaitSec,
                  underline: const SizedBox.shrink(),
                  items: const [3, 5, 10].map((s) => DropdownMenuItem(value: s, child: Text('$s sec'))).toList(),
                  onChanged: (v) => cfg.set({'intentWaitSec': v}),
                ),
              ),
          ]),
        ),
        const SectionTitle('Warnings'),
        BBCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(value: c.warn50, onChanged: (v) => cfg.set({'warn50': v}), title: const Text('At 50% of budget')),
            SwitchListTile(value: c.warn80, onChanged: (v) => cfg.set({'warn80': v}), title: const Text('At 80% of budget')),
            SwitchListTile(value: c.warn100, onChanged: (v) => cfg.set({'warn100': v}), title: const Text('When budget is reached')),
          ]),
        ),
      ],
    );
  }
}

class _HardLockBanner extends StatelessWidget {
  final DateTime until;
  const _HardLockBanner({required this.until});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sameDay = until.year == now.year && until.month == now.month && until.day == now.day;
    final time = TimeOfDay.fromDateTime(until).format(context);
    return BBCard(
      color: BB.coral.withValues(alpha: 0.15),
      child: Row(children: [
        const Icon(Icons.lock_rounded, color: BB.coral, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Hard lock is on until $time${sameDay ? '' : ' tomorrow'}. You can make your rules stricter, but not looser, until then.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

class _HardOptions extends ConsumerWidget {
  final AppConfig c;
  final bool locked;
  const _HardOptions({required this.c, required this.locked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.read(configProvider.notifier);
    return Column(children: [
      const Divider(height: 20),
      Row(children: [
        const Expanded(child: Text('Lock lasts', style: TextStyle(fontWeight: FontWeight.w700))),
        DropdownButton<String>(
          value: c.hardDuration,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: '1h', child: Text('1 hour')),
            DropdownMenuItem(value: '3h', child: Text('3 hours')),
            DropdownMenuItem(value: 'tomorrow', child: Text('Until tomorrow')),
          ],
          onChanged: locked ? null : (v) => cfg.set({'hardDuration': v}),
        ),
      ]),
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Emergency unlocks', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${c.emergencyLeft} left this week · each gives 10 reels', style: TextStyle(color: context.muted, fontSize: 12)),
          ]),
        ),
        DropdownButton<int>(
          value: c.emergencyPerWeek,
          underline: const SizedBox.shrink(),
          items: const [0, 1, 2].map((n) => DropdownMenuItem(value: n, child: Text('$n per week'))).toList(),
          // During a lock only fewer emergency unlocks are allowed (the native side enforces this too).
          onChanged: (v) {
            if (v == null || (locked && v > c.emergencyPerWeek)) return;
            cfg.set({'emergencyPerWeek': v});
          },
        ),
      ]),
    ]);
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      iconSize: 28,
      style: IconButton.styleFrom(backgroundColor: BB.mintLight, foregroundColor: BB.mintDark, fixedSize: const Size(52, 52)),
      icon: Icon(icon),
    );
  }
}

class _LockCard extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  final bool selected;
  final bool pro;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? child;

  const _LockCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.pro = false,
    this.enabled = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: enabled || selected ? 1 : 0.5,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? BB.mint : Colors.transparent, width: 2),
          ),
          child: BBCard(
            onTap: enabled && !selected ? onTap : null,
            child: Column(children: [
              Row(children: [
                CircleAvatar(backgroundColor: BB.mintLight, child: Icon(icon, color: BB.mintDark)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      if (pro) ...[const SizedBox(width: 8), const ProTag()],
                    ]),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(color: context.muted)),
                  ]),
                ),
                Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? BB.mint : context.muted),
              ]),
              ?child,
            ]),
          ),
        ),
      ),
    );
  }
}
