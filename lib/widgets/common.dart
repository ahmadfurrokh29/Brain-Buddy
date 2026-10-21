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

  const StatusPill({super.key, required this.label, required this.color, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
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

String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
