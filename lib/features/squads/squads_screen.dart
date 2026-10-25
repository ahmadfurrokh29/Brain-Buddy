import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/squads.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_buddy.dart';
import '../../widgets/common.dart';

/// Squads tab: sign in, set a nickname, then create or join squads.
class SquadsScreen extends ConsumerWidget {
  const SquadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Squads')),
      body: user.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (u) {
          if (u == null) return const _SignIn();
          final profile = ref.watch(profileProvider);
          return profile.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (p) => p == null ? const ProfileForm() : _SquadList(me: p),
          );
        },
      ),
    );
  }
}

class _SignIn extends ConsumerStatefulWidget {
  const _SignIn();

  @override
  ConsumerState<_SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<_SignIn> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('BrainBuddy sign-in failed: $e');
      if (mounted) showSnack(context, signInErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final repo = ref.read(squadsRepoProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
      const Center(child: BrainBuddy(mood: Mood.fresh, size: 150)),
      const SizedBox(height: 12),
      Text('Scroll less, together', style: t.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Make a squad with 2–8 friends. Each week, whoever watches the fewest reels wins.',
          style: t.bodyLarge?.copyWith(color: context.muted), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() async {
                  await repo.signInWithGoogle();
                  if (!mounted) return;
                  await offerCloudRestore(this.context, ref);
                }),
        icon: const Icon(Icons.account_circle_rounded),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: _busy ? null : () => _run(repo.signInAsGuest),
        child: const Text('Continue as guest'),
      ),
      const SizedBox(height: 20),
      BBCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_rounded, color: BB.mint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only your nickname, avatar and reel counts are shared with your squads. Never which reels, apps or times. '
              'Guest accounts can\'t be moved to a new phone; Google accounts can.',
              style: TextStyle(color: context.muted),
            ),
          ),
        ]),
      ),
      if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
    ]);
  }
}

/// On a new phone, right after Google sign-in: bring back history and settings from the cloud backup.
Future<void> offerCloudRestore(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(squadsRepoProvider);
  if (!await repo.shouldOfferRestore() || !context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Restore your history?'),
      content: const Text('Your Google account has a Brain Bean backup: your daily reel history and settings. '
          'Bring it to this phone?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true) return;
  final days = await repo.restoreFromCloud();
  refreshAll(ref);
  if (context.mounted) showSnack(context, 'Restored $days days of history ✅');
}

/// Nickname + avatar. Shown after the first sign-in, and from Settings to edit.
class ProfileForm extends ConsumerStatefulWidget {
  final Profile? initial;
  final VoidCallback? onSaved;
  const ProfileForm({super.key, this.initial, this.onSaved});

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late String _avatar = widget.initial?.avatar ?? kAvatars.first;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(squadsRepoProvider).saveProfile(Profile(_name.text.trim(), _avatar));
      ref.invalidate(profileProvider);
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final valid = _name.text.trim().isNotEmpty && _name.text.trim().length <= 24;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), shrinkWrap: true, children: [
      Text('Pick a nickname', style: t.headlineSmall),
      const SizedBox(height: 4),
      Text('This is how friends see you. No real name needed.', style: TextStyle(color: context.muted)),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        maxLength: 24,
        decoration: const InputDecoration(labelText: 'Nickname', border: OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in kAvatars)
          ChoiceChip(
            label: Text(a, style: const TextStyle(fontSize: 22)),
            selected: _avatar == a,
            showCheckmark: false,
            onSelected: (_) => setState(() => _avatar = a),
          ),
      ]),
      const SizedBox(height: 20),
      FilledButton(onPressed: valid && !_busy ? _save : null, child: const Text('Save')),
      // Changed your mind about how to sign in? Go back before anything is saved.
      if (widget.initial == null)
        TextButton(
          onPressed: _busy ? null : _useDifferentSignIn,
          child: const Text('Use a different sign-in'),
        ),
    ]);
  }

  Future<void> _useDifferentSignIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(squadsRepoProvider).cancelSignIn();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not go back: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SquadList extends ConsumerWidget {
  final Profile me;
  const _SquadList({required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final squads = ref.watch(mySquadsProvider);
    return squads.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load squads: $e'))),
      data: (list) => ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Text(me.avatar, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          Expanded(child: Text('Hi ${me.name}!', style: Theme.of(context).textTheme.titleLarge)),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          BBCard(
            child: Text('You\'re not in a squad yet. Create one and share the code, or join a friend\'s.',
                style: TextStyle(color: context.muted)),
          ),
        for (final s in list) ...[_SquadCard(squad: s), const SizedBox(height: 10)],
        const SizedBox(height: 6),
        // Full-width and stacked, so the labels fit even with large text/display size settings.
        FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create squad'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: () => _join(context, ref),
          icon: const Icon(Icons.vpn_key_rounded),
          label: const Text('Join with code'),
        ),
      ]),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _ask(context, 'Name your squad', 'e.g. The Detox Club', maxLength: 30);
    if (name == null || !context.mounted) return;
    try {
      final s = await ref.read(squadsRepoProvider).create(name, me);
      if (context.mounted) context.push('/squads/${s.id}');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final code = await _ask(context, 'Enter invite code', 'e.g. K7M2QX', maxLength: 8, caps: true);
    if (code == null || !context.mounted) return;
    try {
      final s = await ref.read(squadsRepoProvider).join(code, me);
      if (context.mounted) context.push('/squads/${s.id}');
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }
}

Future<String?> _ask(BuildContext context, String title, String hint, {int maxLength = 30, bool caps = false}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: maxLength,
        textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final v = c.text.trim();
            if (v.isNotEmpty) Navigator.pop(context, v);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _SquadCard extends ConsumerWidget {
  final Squad squad;
  const _SquadCard({required this.squad});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).value?.uid;
    final members = ref.watch(squadMembersProvider(squad.id)).value ?? const <SquadMember>[];
    final ranked = rankForWeek(members, weekKeyOf(DateTime.now()));
    final myRank = ranked.indexWhere((m) => m.uid == uid) + 1;
    return BBCard(
      onTap: () => context.push('/squads/${squad.id}'),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: BB.mintLight,
          child: Text(ranked.isEmpty ? '👥' : ranked.first.avatar, style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(squad.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${squad.memberUids.length} ${squad.memberUids.length == 1 ? 'member' : 'members'}'
                '${myRank > 0 && ranked.length > 1 ? ' · you\'re #$myRank this week' : ''}',
                style: TextStyle(color: context.muted)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded),
      ]),
    );
  }
}
