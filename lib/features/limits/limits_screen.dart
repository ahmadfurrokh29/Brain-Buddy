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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        BBCard(
          child: Column(children: [
            Text('DAILY REEL BUDGET', style: t.labelLarge?.copyWith(color: BB.grey, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _RoundButton(icon: Icons.remove_rounded, onTap: c.budget > 10 ? () => cfg.set({'budget': c.budget - 5}) : null),
              SizedBox(
                width: 140,
                child: Column(children: [
                  Text('${c.budget}', style: t.displayMedium),
                  Text('reels a day', style: t.bodyMedium?.copyWith(color: BB.grey)),
                ]),
              ),
              _RoundButton(icon: Icons.add_rounded, onTap: c.budget < 200 ? () => cfg.set({'budget': c.budget + 5}) : null),
            ]),
            if (c.extraToday > 0) ...[
              const SizedBox(height: 8),
              Text('+${c.extraToday} extra unlocked today', style: t.bodySmall?.copyWith(color: BB.coral, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
        const SectionTitle('Lock style'),
        _LockCard(
          title: 'Gentle',
          body: 'A calm breathing break when you reach your budget. Then you can close the app or allow 5 more reels.',
          icon: Icons.spa_rounded,
          selected: true,
        ),
        const _LockCard(
          title: 'Firm',
          body: 'Wait 60 seconds and type why you want more reels.',
          icon: Icons.hourglass_bottom_rounded,
          selected: false,
          comingSoon: true,
        ),
        const _LockCard(
          title: 'Hard',
          body: 'Reels stay locked until tomorrow. No way around it.',
          icon: Icons.lock_rounded,
          selected: false,
          comingSoon: true,
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
  final bool comingSoon;

  const _LockCard({required this.title, required this.body, required this.icon, required this.selected, this.comingSoon = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: comingSoon ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? BB.mint : Colors.transparent, width: 2),
          ),
          child: BBCard(
            child: Row(children: [
              CircleAvatar(backgroundColor: BB.mintLight, child: Icon(icon, color: BB.mintDark)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (comingSoon) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: BB.sunLight, borderRadius: BorderRadius.circular(8)),
                        child: const Text('Coming soon', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB38600))),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(color: BB.grey)),
                ]),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: BB.mint),
            ]),
          ),
        ),
      ),
    );
  }
}
