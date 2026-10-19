import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Checks everything the counter needs and explains how to fix each problem
/// on the user's phone brand (fixes BrainPal's "keeps turning off" complaint).
class DoctorScreen extends ConsumerStatefulWidget {
  const DoctorScreen({super.key});

  @override
  ConsumerState<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends ConsumerState<DoctorScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(statusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(statusProvider);
    final bridge = ref.read(bridgeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reliability Doctor')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          final brand = _Brand.of(s.manufacturer);
          final lastEvent = s.lastEventAt == 0 ? null : DateTime.fromMillisecondsSinceEpoch(s.lastEventAt);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(statusProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                BBCard(
                  color: s.healthy ? BB.mintLight : BB.coralLight,
                  child: Row(children: [
                    Icon(s.healthy ? Icons.verified_rounded : Icons.warning_rounded, color: s.healthy ? BB.mintDark : BB.coral, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.healthy ? 'All good!' : 'Counting needs a fix',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: BB.ink)),
                        Text('Phone: ${brand.name} ${s.model}', style: const TextStyle(color: BB.grey)),
                      ]),
                    ),
                  ]),
                ),
                const SectionTitle('Checklist'),
                BBCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _Check(
                      ok: s.accessibility,
                      title: 'Accessibility switched on',
                      body: 'Needed to count reels.',
                      onFix: bridge.openAccessibilitySettings,
                    ),
                    _Check(
                      ok: !s.killed,
                      title: 'Counter running',
                      body: s.killed
                          ? 'Android stopped the counter. Turn Brain Buddy off and on again in Accessibility settings.'
                          : 'The counter is alive.',
                      onFix: bridge.openAccessibilitySettings,
                    ),
                    _Check(
                      ok: s.battery,
                      title: 'Battery unrestricted',
                      body: 'Stops the phone from closing the counter to save battery.',
                      onFix: bridge.openBatterySettings,
                    ),
                    if (brand.hasAutostart)
                      _Check(
                        ok: null,
                        title: 'Autostart allowed',
                        body: '${brand.name} phones need Autostart turned on for Brain Buddy. We can\'t check this one for you.',
                        onFix: bridge.openAutostartSettings,
                      ),
                    _Check(
                      ok: s.notifications,
                      title: 'Notifications on',
                      body: 'For budget warnings.',
                      onFix: bridge.openNotificationSettings,
                    ),
                    _Check(
                      ok: lastEvent == null ? null : true,
                      title: 'Last reel activity seen',
                      body: lastEvent == null
                          ? 'Nothing seen yet since the counter started. Try the test below.'
                          : 'At ${TimeOfDay.fromDateTime(lastEvent).format(context)} on ${lastEvent.day}/${lastEvent.month}.',
                    ),
                  ]),
                ),
                const SectionTitle('Tips for your phone'),
                BBCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final tip in brand.tips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.arrow_right_rounded, color: BB.mint),
                          Expanded(child: Text(tip)),
                        ]),
                      ),
                  ]),
                ),
                const SectionTitle('Run a test'),
                BBCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('1. Open YouTube Shorts or Instagram Reels.\n2. Watch one reel for 5 seconds, then swipe to the next.\n3. Come back here and pull down to refresh.'),
                    const SizedBox(height: 8),
                    Text('If "Last reel activity" shows the time you just scrolled, counting works. 🎉', style: TextStyle(color: BB.grey.withValues(alpha: 0.9))),
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Check extends StatelessWidget {
  /// true = good, false = needs fixing, null = can't tell.
  final bool? ok;
  final String title;
  final String body;
  final VoidCallback? onFix;

  const _Check({required this.ok, required this.title, required this.body, this.onFix});

  @override
  Widget build(BuildContext context) {
    final icon = switch (ok) {
      true => const Icon(Icons.check_circle_rounded, color: BB.mint),
      false => const Icon(Icons.cancel_rounded, color: BB.coral),
      null => const Icon(Icons.help_rounded, color: Color(0xFFE0A800)),
    };
    return ListTile(
      leading: icon,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(body),
      trailing: ok == true || onFix == null ? null : TextButton(onPressed: onFix, child: const Text('Fix')),
    );
  }
}

/// Phone-brand specific advice (from dontkillmyapp.com).
class _Brand {
  final String name;
  final bool hasAutostart;
  final List<String> tips;

  const _Brand(this.name, this.hasAutostart, this.tips);

  static _Brand of(String manufacturer) {
    const common = 'Settings → Apps → Brain Buddy → Battery → "Unrestricted".';
    switch (manufacturer) {
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return const _Brand('Xiaomi', true, [
          'Security app → Permissions → Autostart → turn on Brain Buddy.',
          'Settings → Apps → Brain Buddy → Battery saver → "No restrictions".',
          'Open Recent apps, pull Brain Buddy down a little and tap the lock icon.',
        ]);
      case 'oppo':
      case 'realme':
      case 'oneplus':
        return _Brand(manufacturer[0].toUpperCase() + manufacturer.substring(1), true, const [
          'Settings → Apps → Brain Buddy → Battery usage → allow "Background activity" and "Auto launch".',
          'Open Recent apps and lock Brain Buddy so it is never cleared.',
          'If the counter still stops, turn Brain Buddy off and on in Accessibility.',
        ]);
      case 'vivo':
      case 'iqoo':
        return const _Brand('Vivo', true, [
          'i Manager → App manager → Autostart manager → allow Brain Buddy.',
          'Settings → Battery → Background power consumption → allow Brain Buddy.',
        ]);
      case 'huawei':
      case 'honor':
        return const _Brand('Huawei', true, [
          'Settings → Battery → App launch → Brain Buddy → "Manage manually" and allow all three options.',
        ]);
      case 'samsung':
        return const _Brand('Samsung', false, [
          common,
          'Settings → Battery → Background usage limits → make sure Brain Buddy is not in "Sleeping apps".',
        ]);
      default:
        return const _Brand('Your', false, [common, 'If the counter stops, turn Brain Buddy off and on in Accessibility settings.']);
    }
  }
}
