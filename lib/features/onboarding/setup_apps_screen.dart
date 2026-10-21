import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Setup step 1 of 2: which apps to track and the daily reel budget.
class SetupAppsScreen extends ConsumerStatefulWidget {
  const SetupAppsScreen({super.key});

  @override
  ConsumerState<SetupAppsScreen> createState() => _SetupAppsScreenState();
}

class _SetupAppsScreenState extends ConsumerState<SetupAppsScreen> {
  Set<String>? _selected; // app names
  double _budget = 30;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final targets = ref.watch(targetsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/welcome')),
        title: const Text('Step 1 of 2'),
      ),
      body: targets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not read your apps: $e')),
        data: (apps) {
          _selected ??= apps.where((a) => a.installed).map((a) => a.name).toSet();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Which apps do you scroll?', style: t.headlineSmall),
              const SizedBox(height: 4),
              Text('Brain Buddy only looks at the apps you pick.', style: t.bodyMedium?.copyWith(color: context.muted)),
              const SizedBox(height: 16),
              BBCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final a in apps) ...[
                    _AppTile(
                      app: a,
                      selected: _selected!.contains(a.name),
                      onChanged: (v) => setState(() => v ? _selected!.add(a.name) : _selected!.remove(a.name)),
                    ),
                    if (a != apps.last) const Divider(indent: 64),
                  ],
                ]),
              ),
              const SectionTitle('Daily reel budget'),
              BBCard(
                child: Column(children: [
                  Text('${_budget.round()} reels', style: t.displaySmall?.copyWith(color: BB.mintDark)),
                  Slider(
                    value: _budget,
                    min: 10,
                    max: 500,
                    divisions: 98,
                    activeColor: BB.mint,
                    label: '${_budget.round()}',
                    onChanged: (v) => setState(() => _budget = v),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: BB.sunLight, borderRadius: BorderRadius.circular(12)),
                    child: const Row(children: [
                      Icon(Icons.lightbulb_rounded, color: Color(0xFFE0A800), size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text('Most people start with 30–50 and lower it later.')),
                    ]),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: targets.hasValue && (_selected?.isNotEmpty ?? false) ? () => _continue(targets.value!) : null,
            child: const Text('Continue'),
          ),
        ),
      ),
    );
  }

  Future<void> _continue(List<TargetApp> apps) async {
    final pkgs = apps.where((a) => _selected!.contains(a.name)).expand((a) => a.pkgs).toList();
    await ref.read(configProvider.notifier).set({'tracked': pkgs, 'budget': _budget.round()});
    if (mounted) context.go('/setup/permissions');
  }
}

class _AppTile extends StatelessWidget {
  final TargetApp app;
  final bool selected;
  final ValueChanged<bool> onChanged;
  const _AppTile({required this.app, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: selected,
      onChanged: onChanged,
      secondary: AppBadge(name: app.name, pkg: app.pkg),
      title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(app.installed ? 'Installed' : 'Not installed', style: TextStyle(color: context.muted)),
    );
  }
}

/// The app's real icon from the phone, or a coloured square with its initial when it isn't installed.
class AppBadge extends ConsumerWidget {
  final String name;
  final String? pkg;
  final double size;
  const AppBadge({super.key, required this.name, this.pkg, this.size = 40});

  static const _colors = {
    'Instagram': Color(0xFFE1306C),
    'Instagram Lite': Color(0xFFC13584),
    'YouTube Shorts': Color(0xFFFF0000),
    'TikTok': Color(0xFF111111),
    'Facebook': Color(0xFF1877F2),
    'Facebook Lite': Color(0xFF4267B2),
    'Snapchat': Color(0xFFFFC800),
    'Reddit': Color(0xFFFF4500),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = pkg == null ? null : ref.watch(appIconsProvider).value?[pkg];
    if (icon != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.memory(icon, width: size, height: size, gaplessPlayback: true),
      );
    }
    final color = _colors[name] ?? BB.mint;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(
        name.characters.first,
        style: TextStyle(color: name == 'Snapchat' ? BB.ink : Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.45),
      ),
    );
  }
}
