import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rounded white card used across the app.
class BBCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  const BBCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Small coloured pill like "Tracking on".
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  /// Smaller pill with a small dot, for tight headers.
  final bool compact;

  const StatusPill({super.key, required this.label, required this.color, required this.icon, this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: compact ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: compact ? 10 : 16, color: color),
            SizedBox(width: compact ? 5 : 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: compact ? 12 : 13)),
          ]),
        ),
      ),
    );
  }
}

/// Small stat tile: icon, big value, caption.
class StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: BBCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(children: [
          CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, size: 18, color: color)),
          const SizedBox(height: 8),
          Text(value, style: t.titleLarge),
          Text(label, style: t.bodySmall?.copyWith(color: context.muted), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        ?trailing,
      ]),
    );
  }
}

/// Page dots for the welcome slides and setup.
class Dots extends StatelessWidget {
  final int count;
  final int index;
  const Dots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(color: i == index ? BB.mint : BB.mint.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4)),
          ),
      ],
    );
  }
}

/// During the free beta every Pro feature is open to everyone. Later this asks RevenueCat.
const kBetaAllPro = true;

/// Small yellow "PRO" tag on Pro features. In the beta it reads "PRO · free in beta".
class ProTag extends StatelessWidget {
  const ProTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: BB.sun.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
      child: Text(
        kBetaAllPro ? 'PRO · free in beta' : 'PRO',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFB38600)),
      ),
    );
  }
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.info_rounded, color: BB.mintDark),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
}

/// The app's dropdown: plain value with a mint arrow; opens as a rounded white list with the chosen
/// option in light mint (Flutter paints the chosen row with the theme's focus colour).
class BBDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  const BBDropdown({super.key, required this.value, required this.options, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(focusColor: BB.mint.withValues(alpha: context.isDark ? 0.22 : 0.14)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: BB.mint),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(label(o)))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
