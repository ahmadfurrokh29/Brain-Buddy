import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Setup step 2 of 2. This is also Google Play's required "prominent disclosure":
/// it explains what the Accessibility permission is used for before the user turns it on.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> with WidgetsBindingObserver {
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

  Future<void> _confirmAccessibility() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _AccessibilityDisclosure(),
    );
    if (ok == true) await ref.read(bridgeProvider).openAccessibilitySettings();
  }

  void _finish() {
    ref.read(onboardingDoneProvider.notifier).complete();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = ref.watch(statusProvider).value;
    final bridge = ref.read(bridgeProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/setup/apps')),
        title: const Text('Step 2 of 2'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Let Brain Buddy count', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('Android needs your OK for a few things. We explain each one.', style: t.bodyMedium?.copyWith(color: context.muted)),
          const SizedBox(height: 16),
          _PermissionCard(
            icon: Icons.accessibility_new_rounded,
            title: 'Accessibility',
            tag: 'Required',
            body: 'Lets Brain Buddy notice when you scroll reels in the apps you picked. '
                'We never read messages, passwords or banking apps.',
            done: status?.accessibility ?? false,
            actionLabel: 'Turn on',
            onAction: _confirmAccessibility,
          ),
          _PermissionCard(
            icon: Icons.battery_charging_full_rounded,
            title: 'Battery',
            tag: 'Recommended',
            body: (status?.battery ?? false) && (status?.backgroundRestricted ?? false)
                ? 'Brain Buddy is restricted in the background. In App info → Battery, turn ON "Allow background activity".'
                : 'Some phones stop apps in the background. Tap Allow on the next pop-up so the counter keeps working.',
            done: status?.batteryOk ?? false,
            actionLabel: (status?.battery ?? false) ? 'Open app info' : 'Allow',
            onAction: (status?.battery ?? false) ? bridge.openAppSettings : bridge.openBatterySettings,
          ),
          _PermissionCard(
            icon: Icons.notifications_active_rounded,
            title: 'Notifications',
            tag: 'Recommended',
            body: 'Friendly warnings when you get close to your daily reel budget.',
            done: status?.notifications ?? false,
            actionLabel: 'Allow',
            onAction: () async {
              await bridge.requestNotifications();
              await Future.delayed(const Duration(milliseconds: 600));
              ref.invalidate(statusProvider);
            },
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_rounded, size: 16, color: context.muted),
            SizedBox(width: 6),
            Text('Everything stays on your phone.', style: TextStyle(color: context.muted)),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              onPressed: (status?.accessibility ?? false) ? _finish : null,
              child: const Text('All done — start Brain Buddy'),
            ),
            TextButton(onPressed: _finish, child: const Text('Skip for now')),
          ]),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String tag;
  final String body;
  final bool done;
  final String actionLabel;
  final VoidCallback onAction;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.tag,
    required this.body,
    required this.done,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BBCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: BB.mintLight, child: Icon(icon, color: BB.mintDark)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(tag, style: TextStyle(color: tag == 'Required' ? BB.coral : context.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (done) const Icon(Icons.check_circle_rounded, color: BB.mint, size: 28),
          ]),
          const SizedBox(height: 10),
          Text(body, style: TextStyle(color: context.muted)),
          if (!done) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Full explanation shown before sending the user to Android's Accessibility settings.
class _AccessibilityDisclosure extends StatelessWidget {
  const _AccessibilityDisclosure();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget point(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: t.bodyMedium)),
          ]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How Brain Buddy uses Accessibility', style: t.titleLarge),
          const SizedBox(height: 16),
          point(Icons.check_circle_rounded, BB.mint,
              'Brain Buddy uses the Accessibility Service to see when you scroll reels and shorts in the apps you chose, so it can count them.'),
          point(Icons.check_circle_rounded, BB.mint, 'It also uses it to show your counter, the reel limit screen and the "Why are you here?" pause on top of those apps.'),
          point(Icons.cancel_rounded, BB.coral, 'It does not read your messages, passwords, typing, or any other app such as banking.'),
          point(Icons.cancel_rounded, BB.coral, 'Nothing is uploaded. Your counts stay on this phone.'),
          const SizedBox(height: 8),
          Text('On the next screen tap "Brain Buddy reel counter" (it may be under "Installed apps" or "Downloaded apps") and switch it on.',
              style: t.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('I agree — open settings')),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Center(child: Text('Not now'))),
        ]),
      ),
    );
  }
}
