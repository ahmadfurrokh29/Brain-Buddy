import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/receipt.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_buddy.dart';
import '../../widgets/common.dart';

/// Opens the Weekly Reel Receipt for the last 7 days, with a Share button.
Future<void> showWeeklyReceipt(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ReceiptSheet(),
  );
}

class _ReceiptSheet extends ConsumerStatefulWidget {
  const _ReceiptSheet();

  @override
  ConsumerState<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends ConsumerState<_ReceiptSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share(WeeklyReceipt r) async {
    setState(() => _sharing = true);
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brain_buddy_week.png')..writeAsBytesSync(png!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: 'My week in reels: ${r.watched} reels, ${r.distanceLabel} of scrolling. Counted with Brain Buddy 🧠',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not share: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = ref.watch(daysProvider(14));
    final budget = ref.watch(configProvider).value?.budget ?? 30;
    return SafeArea(
      child: days.when(
        loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
        data: (list) {
          final r = WeeklyReceipt.from(list, budget);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RepaintBoundary(key: _cardKey, child: ReceiptCard(r: r)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _sharing || r.isEmpty ? null : () => _share(r),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share my receipt'),
              ),
            ]),
          );
        },
      ),
    );
  }
}

/// The receipt itself: always light "paper", so it looks the same when shared from dark mode.
class ReceiptCard extends StatelessWidget {
  final WeeklyReceipt r;
  const ReceiptCard({super.key, required this.r});

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.robotoMono(color: BB.ink, fontSize: 14);
    final big = GoogleFonts.fredoka(color: BB.ink, fontSize: 34, fontWeight: FontWeight.w600);
    final range = r.week.isEmpty
        ? ''
        : '${DateFormat('d MMM').format(r.week.first.date)} – ${DateFormat('d MMM yyyy').format(r.week.last.date)}';
    final change = r.changePercent;

    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: mono)),
            Text(value, style: mono.copyWith(fontWeight: FontWeight.w700, color: color ?? BB.ink)),
          ]),
        );

    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF7),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(children: [
        BrainBuddy(mood: r.mood, size: 86, glow: false),
        const SizedBox(height: 6),
        Text('WEEKLY REEL RECEIPT', style: mono.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
        Text(range, style: mono.copyWith(color: BB.grey, fontSize: 12)),
        const _Dashes(),
        Text('${r.watched}', style: big),
        Text('reels watched', style: mono.copyWith(color: BB.grey)),
        const SizedBox(height: 8),
        Text(r.distanceLabel, style: big.copyWith(fontSize: 26, color: BB.mintDark)),
        Text('scrolled with my thumb', style: mono.copyWith(color: BB.grey)),
        const _Dashes(),
        line('Time in reels', formatMinutes(r.minutes)),
        line('Skimmed', '${r.skimmed}'),
        if (r.topApp != null) line('Top app', '${r.topApp} (${r.topAppReels})'),
        if (r.bestDay != null) line('Best day', '${DateFormat('EEE').format(r.bestDay!.date)} (${r.bestDay!.watched})'),
        if (change != null)
          line('vs last week', '${change > 0 ? '+' : ''}$change%', color: change <= 0 ? BB.mintDark : BB.coral),
        line('Brain buddy', r.mood.label),
        const _Dashes(),
        Text(change != null && change < 0 ? 'Fewer reels than last week. Nice! 🎉' : 'Every reel you skip is time back. 🌿',
            style: mono.copyWith(fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('brain buddy', style: mono.copyWith(color: BB.grey, fontSize: 11, letterSpacing: 3)),
      ]),
    );
  }
}

class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text('- ' * 24, maxLines: 1, overflow: TextOverflow.clip, style: GoogleFonts.robotoMono(color: BB.grey, fontSize: 12)),
    );
  }
}
