import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/squads.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../squads/squads_screen.dart' show ProfileForm;

/// Settings → Squads & account: nickname, sign out, delete the online account, crash reports.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final profile = ref.watch(profileProvider).value;
    final prefs = ref.watch(prefsProvider);
    final crashReports = prefs.getBool(kCrashReportsKey) ?? true;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Squads & account'),
      BBCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          if (user == null)
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: const Text('Not signed in'),
              subtitle: const Text('Sign in from the Squads tab to compete with friends.'),
              trailing: const Icon(Icons.chevron_right_rounded),
            )
          else ...[
            ListTile(
              leading: Text(profile?.avatar ?? '🙂', style: const TextStyle(fontSize: 26)),
              title: Text(profile?.name ?? 'Set a nickname'),
              subtitle: Text(user.isAnonymous ? 'Guest account' : (user.email ?? 'Google account')),
              trailing: const Icon(Icons.edit_rounded),
              onTap: () => _editProfile(profile),
            ),
            if (user.isAnonymous) ...[
              ListTile(
                leading: const Icon(Icons.upgrade_rounded, color: BB.mint),
                title: const Text('Upgrade to Google account'),
                subtitle: const Text('Keeps your squads and nickname, and lets you use them on a new phone.'),
                onTap: _upgrade,
              ),
              // A guest account can never be signed back into, so signing out deletes it instead of
              // leaving an empty account and a stale squad member behind.
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: BB.coral),
                title: const Text('Sign out & delete guest account', style: TextStyle(color: BB.coral, fontWeight: FontWeight.w700)),
                subtitle: const Text('Leaves your squads. Counts on this phone stay.'),
                onTap: _deleteAccount,
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                onTap: _signOut,
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_rounded, color: BB.coral),
                title: const Text('Delete online account', style: TextStyle(color: BB.coral, fontWeight: FontWeight.w700)),
                subtitle: const Text('Leaves every squad and deletes your nickname. Counts on this phone stay.'),
                onTap: _deleteAccount,
              ),
            ],
          ],
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            value: crashReports,
            title: const Text('Send crash reports'),
            subtitle: const Text('Anonymous reports help fix bugs. Never includes your reels.'),
            onChanged: (v) async {
              await prefs.setBool(kCrashReportsKey, v);
              await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(v);
              setState(() {});
            },
          ),
        ]),
      ),
    ]);
  }

  Future<void> _editProfile(Profile? current) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
        child: ProfileForm(initial: current, onSaved: () => Navigator.pop(sheet)),
      ),
    );
  }

  Future<void> _upgrade() async {
    try {
      await ref.read(squadsRepoProvider).upgradeGuestToGoogle();
      ref.invalidate(authUserProvider);
      if (mounted) showSnack(context, 'Your account is now a Google account ✅');
    } catch (e) {
      if (mounted) showSnack(context, e.toString().split('\n').first);
    }
  }

  Future<void> _signOut() async {
    final ok = await _confirm('Sign out?', 'Your squads stay saved; sign in again with Google to see them.', 'Sign out');
    if (!ok) return;
    await ref.read(squadsRepoProvider).signOut();
  }

  Future<void> _deleteAccount() async {
    final guest = ref.read(authUserProvider).value?.isAnonymous ?? false;
    final ok = await _confirm(
      guest ? 'Sign out of the guest account?' : 'Delete online account?',
      guest
          ? 'A guest account can\'t be signed back into, so it will be deleted and you\'ll leave your squads. '
              'Tip: "Upgrade to Google account" keeps everything. Counts on this phone stay.'
          : 'You\'ll leave every squad and your nickname is deleted. This can\'t be undone. Your counts on this phone are not affected.',
      guest ? 'Sign out & delete' : 'Delete',
    );
    if (!ok) return;
    try {
      await ref.read(squadsRepoProvider).deleteAccount();
      if (mounted) showSnack(context, 'Online account deleted');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      showSnack(
        context,
        e.code == 'requires-recent-login'
            ? 'For safety, sign out, sign in again, then delete.'
            : 'Could not delete: ${e.message}',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Could not delete: $e');
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
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
}
