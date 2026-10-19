import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../home/home_screen.dart' show showPauseSheet;
import '../onboarding/setup_apps_screen.dart' show AppBadge;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: config.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (c) => _SettingsBody(c: c),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final AppConfig c;
  const _SettingsBody({required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.read(configProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        const SectionTitle('Tracking'),
        _Group(children: [
          ListTile(
            leading: const Icon(Icons.apps_rounded),
            title: const Text('Apps to track'),
            subtitle: Text(_trackedNames(ref, c)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickApps(context, ref, c),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Watch time to count'),
            subtitle: const Text('A reel counts only if you stay on it this long'),
            trailing: _Choice<int>(value: c.dwellSec, options: const [1, 2, 3, 5, 7, 10], label: (v) => '$v sec', onChanged: (v) => cfg.set({'dwellSec': v})),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fast_forward_rounded),
            value: c.showSkimmed,
            onChanged: (v) => cfg.set({'showSkimmed': v}),
            title: const Text('Show skimmed reels'),
            subtitle: const Text('Quick flicks shown as a separate number'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.campaign_outlined),
            value: c.ignoreAds,
            onChanged: (v) => cfg.set({'ignoreAds': v}),
            title: const Text('Ignore ads'),
            subtitle: const Text('Sponsored reels are not counted'),
          ),
          ListTile(
            leading: const Icon(Icons.wb_twilight_rounded),
            title: const Text('New day starts at'),
            subtitle: const Text('Night owl? Start your day later'),
            trailing: _Choice<int>(
              value: c.dayStartHour,
              options: const [0, 2, 4, 6],
              label: (v) => v == 0 ? '12 am' : '$v am',
              onChanged: (v) => cfg.set({'dayStartHour': v}),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.pause_circle_outline_rounded),
            title: Text(c.isPaused ? 'Tracking paused — tap to resume' : 'Pause tracking'),
            onTap: () => c.isPaused ? cfg.pause(0) : showPauseSheet(context, ref),
          ),
        ]),
        const SectionTitle('Pop-ups'),
        _Group(children: [
          SwitchListTile(
            secondary: const Icon(Icons.bubble_chart_outlined),
            value: c.floatingCounter,
            onChanged: (v) => cfg.set({'floatingCounter': v}),
            title: const Text('Floating counter'),
            subtitle: const Text('Small bubble with your count while watching reels'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.psychology_alt_outlined),
            value: c.intentPause,
            onChanged: (v) => cfg.set({'intentPause': v}),
            title: const Text('"Why are you here?" pause'),
          ),
        ]),
        const SectionTitle('Look & feel'),
        _Group(children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            trailing: _Choice<ThemeMode>(
              value: themeMode,
              options: ThemeMode.values,
              label: (m) => switch (m) { ThemeMode.system => 'Same as phone', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark' },
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
            ),
          ),
        ]),
        const SectionTitle('Privacy & data'),
        _Group(children: [
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('What we collect'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showPrivacy(context),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_done_outlined),
            title: Text('Auto backup'),
            subtitle: Text('Android saves your data to your own Google Drive and brings it back on a new phone with the same Google account.'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Back up to file'),
            onTap: () => _backup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Restore from file'),
            onTap: () => _restore(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: BB.coral),
            title: const Text('Delete all data', style: TextStyle(color: BB.coral, fontWeight: FontWeight.w700)),
            onTap: () => _deleteAll(context, ref),
          ),
        ]),
        const SectionTitle('Help & about'),
        _Group(children: [
          ListTile(
            leading: const Icon(Icons.healing_rounded),
            title: const Text('Reliability Doctor'),
            subtitle: const Text('Check that counting works on this phone'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/doctor'),
          ),
          const ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('Version'), trailing: Text('1.0.0 (beta)')),
        ]),
      ],
    );
  }

  String _trackedNames(WidgetRef ref, AppConfig c) {
    final targets = ref.watch(targetsProvider).value ?? const [];
    final names = targets.where((a) => a.pkgs.any(c.tracked.contains)).map((a) => a.name).toList();
    return names.isEmpty ? 'None' : names.join(', ');
  }

  Future<void> _pickApps(BuildContext context, WidgetRef ref, AppConfig c) async {
    final targets = await ref.read(targetsProvider.future);
    final selected = targets.where((a) => a.pkgs.any(c.tracked.contains)).map((a) => a.name).toSet();
    if (!context.mounted) return;
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final a in targets)
              SwitchListTile(
                secondary: AppBadge(name: a.name, size: 32),
                title: Text(a.name),
                subtitle: Text(a.installed ? 'Installed' : 'Not installed'),
                value: selected.contains(a.name),
                onChanged: (v) => setState(() => v ? selected.add(a.name) : selected.remove(a.name)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Save')),
            ),
          ]),
        ),
      ),
    );
    if (result == null) return;
    final pkgs = targets.where((a) => result.contains(a.name)).expand((a) => a.pkgs).toList();
    await ref.read(configProvider.notifier).set({'tracked': pkgs});
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      final json = await ref.read(bridgeProvider).exportBackup();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brain_buddy_backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json');
      await file.writeAsString(json);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], title: 'Brain Buddy backup'));
    } catch (e) {
      if (context.mounted) showSnack(context, 'Backup failed: $e');
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context, 'Restore from file?', 'This replaces all data on this phone with the backup.', 'Restore');
    if (!ok) return;
    try {
      final picked = await FilePicker.pickFile();
      if (picked?.path == null) return;
      await ref.read(bridgeProvider).importBackup(await File(picked!.path!).readAsString());
      refreshAll(ref);
      if (context.mounted) showSnack(context, 'Backup restored ✅');
    } catch (e) {
      if (context.mounted) showSnack(context, 'That file could not be restored. Is it a Brain Buddy backup?');
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context, 'Delete all data?', 'All counts and settings on this phone will be erased. This cannot be undone.', 'Delete');
    if (!ok) return;
    await ref.read(bridgeProvider).deleteAllData();
    refreshAll(ref);
    if (context.mounted) showSnack(context, 'All data deleted');
  }

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action, style: const TextStyle(color: BB.coral))),
            ],
          ),
        ) ??
        false;
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What Brain Buddy keeps', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Text('• How many reels you watched or skimmed, in which app, and when'),
            Text('• Minutes spent on reel screens'),
            Text('• Your answers to "Why are you here?"'),
            Text('• Your settings'),
            SizedBox(height: 12),
            Text('What it never keeps', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Text('• Messages, passwords or anything you type'),
            Text('• Screenshots or the content of reels'),
            Text('• Anything from apps you did not pick'),
            SizedBox(height: 12),
            Text('All of it stays on this phone. Nothing is uploaded.', style: TextStyle(color: BB.grey)),
          ]),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => BBCard(padding: EdgeInsets.zero, child: Column(children: children));
}

class _Choice<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  const _Choice({required this.value, required this.options, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(label(o)))).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
