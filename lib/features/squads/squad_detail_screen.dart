import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/nudges.dart';
import '../../core/providers.dart';
import '../../core/squads.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// One squad: weekly leaderboard (fewest reels wins), last week's winner, invite code.
class SquadDetailScreen extends ConsumerStatefulWidget {
  final String squadId;
  const SquadDetailScreen({super.key, required this.squadId});

  @override
  ConsumerState<SquadDetailScreen> createState() => _SquadDetailScreenState();
}

class _SquadDetailScreenState extends ConsumerState<SquadDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Push our latest counts as soon as the leaderboard opens.
    ref.read(bridgeProvider).syncSquads();
  }

  @override
  Widget build(BuildContext context) {
    final squad = ref.watch(squadProvider(widget.squadId));
    final members = ref.watch(squadMembersProvider(widget.squadId));
    final uid = ref.watch(authUserProvider).value?.uid;
    final s = squad.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.name ?? 'Squad'),
        actions: [
          if (s != null)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'leave' ? _leave(s) : _rename(s),
              itemBuilder: (_) => [
                if (s.ownerUid == uid) const PopupMenuItem(value: 'rename', child: Text('Rename squad')),
                const PopupMenuItem(value: 'leave', child: Text('Leave squad', style: TextStyle(color: BB.coral))),
              ],
            ),
        ],
      ),
      body: s == null
          ? Center(child: squad.isLoading ? const CircularProgressIndicator() : const Text('This squad no longer exists.'))
          : members.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) => _Board(squad: s, members: list, myUid: uid),
            ),
    );
  }

  Future<void> _leave(Squad s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave ${s.name}?'),
        content: const Text('You can join again later with the invite code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave', style: TextStyle(color: BB.coral))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(squadsRepoProvider).leave(s);
    if (mounted) context.pop();
  }

  Future<void> _rename(Squad s) async {
    final c = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename squad'),
        content: TextField(controller: c, autofocus: true, maxLength: 30),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await ref.read(squadsRepoProvider).rename(s, name);
  }
}

class _Board extends ConsumerWidget {
  final Squad squad;
  final List<SquadMember> members;
  final String? myUid;
  const _Board({required this.squad, required this.members, required this.myUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final week = weekKeyOf(now);
    final lastWeek = weekKeyOf(now.subtract(const Duration(days: 7)));
    final ranked = rankForWeek(members, week);
    final winner = lastWeekWinner(members, lastWeek);

    return RefreshIndicator(
      onRefresh: () => ref.read(bridgeProvider).syncSquads(),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        if (winner != null)
          BBCard(
            color: BB.sun.withValues(alpha: 0.2),
            child: Row(children: [
              const Text('🏆', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Last week\'s winner: ${winner.avatar} ${winner.name} with ${winner.prevWeekWatched} reels',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        SectionTitle('This week', trailing: Text('Fewest reels wins', style: t.bodySmall?.copyWith(color: context.muted))),
        BBCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (var i = 0; i < ranked.length; i++)
              _MemberRow(
                rank: i + 1,
                m: ranked[i],
                synced: ranked[i].weekKey == week,
                isMe: ranked[i].uid == myUid,
                canRemove: squad.ownerUid == myUid && ranked[i].uid != myUid,
                onRemove: () => ref.read(squadsRepoProvider).removeMember(squad, ranked[i].uid),
                onNudge: ranked[i].uid == myUid || !nudgesAvailable ? null : () => _nudge(context, squad.id, ranked[i]),
              ),
          ]),
        ),
        const SectionTitle('Invite friends'),
        BBCard(
          child: Column(children: [
            Text('Squad code', style: TextStyle(color: context.muted)),
            const SizedBox(height: 4),
            SelectableText(squad.code, style: t.displaySmall?.copyWith(letterSpacing: 4, color: BB.mintDark)),
            const SizedBox(height: 4),
            Text('${squad.memberUids.length} of $kMaxSquadSize places used', style: t.bodySmall?.copyWith(color: context.muted)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: squad.code));
                    showSnack(context, 'Code copied');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(
                    text: 'Join my Brain Buddy squad "${squad.name}" and let\'s scroll less together! '
                        'Open Brain Buddy → Squads → Join with code: ${squad.code}',
                  )),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Friends with a nudge on its way, so a double tap doesn't send two.
final _sending = <String>{};

Future<void> _nudge(BuildContext context, String squadId, SquadMember m) async {
  if (!_sending.add(m.uid)) return;
  // Answer the tap straight away; the push itself takes a second or two.
  showSnack(context, 'Sending a nudge to ${m.name}…');
  final (NudgeResult, int) out;
  try {
    out = await sendNudge(squadId, m.uid);
  } finally {
    _sending.remove(m.uid);
  }
  final (result, minutes) = out;
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  showSnack(context, switch (result) {
    NudgeResult.sent => 'Nudge sent to ${m.name} 👋',
    NudgeResult.tooSoon => 'You can nudge ${m.name} 3 times an hour. Try again in $minutes min.',
    NudgeResult.friendHasNoNotifications => '${m.name} has notifications turned off.',
    NudgeResult.failed => 'Could not send the nudge. Check your internet.',
  });
}

class _MemberRow extends StatelessWidget {
  final int rank;
  final SquadMember m;
  final bool synced;
  final bool isMe;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback? onNudge;
  const _MemberRow({
    this.onNudge,
    required this.rank,
    required this.m,
    required this.synced,
    required this.isMe,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final updated = m.updatedAt;
    final ago = updated == null ? 'not synced yet' : _ago(DateTime.now().difference(updated));
    return ListTile(
      onLongPress: canRemove ? () => _confirmRemove(context) : null,
      leading: SizedBox(
        width: 64,
        child: Row(children: [
          SizedBox(
            width: 24,
            child: Text(rank == 1 && synced ? '👑' : '$rank', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Text(m.avatar, style: const TextStyle(fontSize: 26)),
        ]),
      ),
      title: Text('${m.name}${isMe ? ' (you)' : ''}', style: TextStyle(fontWeight: isMe ? FontWeight.w900 : FontWeight.w700)),
      subtitle: Text(synced ? 'Today ${m.todayWatched} · $ago' : 'No reels counted this week yet'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(synced ? '${m.weekWatched}' : '–', style: Theme.of(context).textTheme.titleLarge),
        if (onNudge != null)
          IconButton(tooltip: 'Nudge ${m.name}', onPressed: onNudge, icon: const Text('👋', style: TextStyle(fontSize: 20))),
      ]),
    );
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: BB.coral))),
        ],
      ),
    );
    if (ok == true) onRemove();
  }
}
