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
import 'account_section.dart';
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
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickApps(context, ref, c),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Watch time to count'),
            trailing: BBDropdown<int>(value: c.dwellSec.clamp(1, 5), options: const [1, 2, 3, 4, 5], label: (v) => '$v sec', onChanged: (v) => cfg.set({'dwellSec': v})),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fast_forward_rounded),
            value: c.showSkimmed,
            onChanged: (v) => cfg.set({'showSkimmed': v}),
            title: const Text('Show skimmed reels'),
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
            trailing: BBDropdown<int>(
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
            trailing: BBDropdown<ThemeMode>(
              value: themeMode,
              options: ThemeMode.values,
              label: (m) => switch (m) { ThemeMode.system => 'Same as phone', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark' },
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
            ),
          ),
        ]),
        const AccountSection(),
        const SectionTitle('Subscription'),
        _Group(children: [
          ListTile(
            leading: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE0A800)),
            title: const Text('Brain Bean Pro'),
            subtitle: Text(kBetaAllPro ? 'All Pro features are free during the beta' : 'Locks, schedules, insights and more'),
            // While everything is free in the beta there is nothing to buy, so the row only informs.
            trailing: kBetaAllPro ? null : const Icon(Icons.chevron_right_rounded),
            onTap: kBetaAllPro ? null : () => context.push('/pro'),
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
            leading: const Icon(Icons.table_view_rounded),
            title: const Text('Export to spreadsheet (CSV)'),
            subtitle: const Text('Every counted reel: day, time, app'),
            trailing: const ProTag(),
            onTap: () => _exportCsv(context, ref),
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
                secondary: AppBadge(name: a.name, pkg: a.pkg, size: 32),
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
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], title: 'Brain Bean backup'));
    } catch (e) {
      if (context.mounted) showSnack(context, 'Backup failed: $e');
    }
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(bridgeProvider).exportCsv();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brain_buddy_reels_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], title: 'Brain Bean reels'));
    } catch (e) {
      if (context.mounted) showSnack(context, 'Export failed: $e');
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
      if (context.mounted) showSnack(context, 'That file could not be restored. Is it a Brain Bean backup?');
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
    const heading = TextStyle(fontSize: 18, fontWeight: FontWeight.w800);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('On this phone', style: heading),
            const SizedBox(height: 8),
            const Text('• How many reels you watched or skimmed, in which app, and when'),
            const Text('• Minutes spent on reel screens'),
            const Text('• Your answers to "Why are you here?"'),
            const Text('• Your settings'),
            const SizedBox(height: 16),
            const Text('Shared only if you use it', style: heading),
            const SizedBox(height: 8),
            const Text('• Squads: your nickname, avatar and reel counts (this week and today) are shown to your squad. '
                'Never which reels, apps or times.'),
            const Text('• Cloud backup (off unless you turn it on): your daily totals and settings, saved to your '
                'Google account.'),
            const Text('• Nudges: a push address, so squad friends can send you a nudge.'),
            const Text('• Crash reports (you can turn them off): technical details when the app crashes.'),
            const SizedBox(height: 16),
            const Text('Never collected', style: heading),
            const SizedBox(height: 8),
            const Text('• Messages, passwords or anything you type'),
            const Text('• Screenshots or the content of reels'),
            const Text('• Anything from apps you did not pick'),
            const SizedBox(height: 16),
            Text('You can delete your online account and everything in it anytime: Settings → Delete online account.',
                style: TextStyle(color: context.muted)),
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
