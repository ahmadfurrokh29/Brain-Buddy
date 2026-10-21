import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../theme/app_theme.dart';

/// The Brain Buddy mascot, drawn in code.
///
/// It bobs gently, blinks, wobbles when [count] goes up and changes face with [mood].
/// Built so it can later be swapped for a Rive animation without touching the screens.
class BrainBuddy extends StatefulWidget {
  final Mood mood;
  final double size;
  final int count;
  final bool glow;

  const BrainBuddy({super.key, required this.mood, this.size = 180, this.count = 0, this.glow = true});

  @override
  State<BrainBuddy> createState() => _BrainBuddyState();
}

class _BrainBuddyState extends State<BrainBuddy> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didUpdateWidget(BrainBuddy old) {
    super.didUpdateWidget(old);
    if (widget.count != old.count) _bounce.forward(from: 0);
  }

  @override
  void dispose() {
    _idle.dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _poke() => _bounce.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: _poke,
      child: AnimatedBuilder(
        animation: Listenable.merge([_idle, _bounce]),
        builder: (context, _) {
          final t = reduceMotion ? 0.0 : _idle.value;
          // Bounce: quick squash and stretch that settles.
          final b = _bounce.value;
          final wobble = b == 0 ? 0.0 : math.sin(b * math.pi * 4) * (1 - b) * 0.08;
          return SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(
              painter: _BrainPainter(
                mood: widget.mood,
                bob: math.sin(t * 2 * math.pi) * 0.02,
                blink: _blinkAmount(t),
                wobble: wobble,
                glow: widget.glow,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Eyes close briefly once per idle loop.
  double _blinkAmount(double t) {
    const start = 0.62, len = 0.05;
    if (t < start || t > start + len) return 0;
    final p = (t - start) / len;
    return p < 0.5 ? p * 2 : (1 - p) * 2;
  }
}

class _BrainPainter extends CustomPainter {
  final Mood mood;
  final double bob;
  final double blink;
  final double wobble;
  final bool glow;

  _BrainPainter({required this.mood, required this.bob, required this.blink, required this.wobble, required this.glow});

  // Lobes as (x, y, radius) in a 0..1 box. Together they make the brain's bumpy outline.
  static const _lobes = [
    [0.30, 0.36, 0.18],
    [0.50, 0.29, 0.20],
    [0.70, 0.36, 0.18],
    [0.22, 0.53, 0.17],
    [0.78, 0.53, 0.17],
    [0.38, 0.63, 0.19],
    [0.62, 0.63, 0.19],
    [0.50, 0.50, 0.24],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (glow) {
      canvas.drawCircle(
        Offset(s / 2, s / 2),
        s * 0.47,
        Paint()..shader = RadialGradient(colors: [mood.color.withValues(alpha: 0.35), mood.color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s * 0.47)),
      );
    }

    final melted = mood == Mood.melted;
    canvas.save();
    // Bob up and down, squash a little when bouncing, sag when melted.
    canvas.translate(s / 2, s / 2 + bob * s + (melted ? s * 0.04 : 0));
    canvas.scale(1 + wobble, (1 - wobble) * (melted ? 0.9 : 1));
    canvas.translate(-s / 2, -s / 2);

    final body = _bodyPath(s);
    canvas.drawShadow(body, Colors.black26, 6, false);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [mood.brainTop, mood.brain],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    if (melted) _drips(canvas, s);
    canvas.drawPath(body, Paint()
      ..color = mood.brainOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018);

    _folds(canvas, s);
    _face(canvas, s);
    canvas.restore();
  }

  Path _bodyPath(double s) {
    Path? path;
    for (final l in _lobes) {
      final p = Path()..addOval(Rect.fromCircle(center: Offset(l[0] * s, l[1] * s), radius: l[2] * s));
      path = path == null ? p : Path.combine(PathOperation.union, path, p);
    }
    return path!;
  }

  void _drips(Canvas canvas, double s) {
    final paint = Paint()..color = mood.brain;
    for (final d in const [
      [0.34, 0.78, 0.05, 0.10],
      [0.55, 0.80, 0.04, 0.14],
      [0.68, 0.76, 0.035, 0.08],
    ]) {
      final x = d[0] * s, y = d[1] * s, w = d[2] * s, h = d[3] * s;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - w / 2, y - h * 0.3, w, h), Radius.circular(w / 2)), paint);
      canvas.drawCircle(Offset(x, y + h * 0.7 - w / 2), w * 0.62, paint);
    }
  }

  void _folds(Canvas canvas, double s) {
    final fold = Paint()
      ..color = mood.brainOutline.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.014;
    // Middle line between the two halves.
    canvas.drawLine(Offset(s * 0.5, s * 0.14), Offset(s * 0.5, s * 0.33), fold);
    // A few curly folds.
    void arc(double x, double y, double r, double start, double sweep) =>
        canvas.drawArc(Rect.fromCircle(center: Offset(x * s, y * s), radius: r * s), start, sweep, false, fold);
    arc(0.30, 0.30, 0.07, math.pi * 1.1, math.pi * 0.8);
    arc(0.70, 0.30, 0.07, math.pi * 1.1, math.pi * 0.8);
    arc(0.17, 0.52, 0.06, math.pi * 1.5, math.pi * 0.7);
    arc(0.83, 0.52, 0.06, math.pi * 0.8, math.pi * 0.7);
    arc(0.36, 0.76, 0.06, math.pi * 1.8, math.pi * 0.6);
    arc(0.64, 0.76, 0.06, math.pi * 0.6, math.pi * 0.6);
  }

  void _face(Canvas canvas, double s) {
    final ink = Paint()
      ..color = BB.ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.022;
    final fill = Paint()..color = BB.ink;
    final left = Offset(s * 0.40, s * 0.50), right = Offset(s * 0.60, s * 0.50);
    final eyeR = s * 0.045;

    // Cheeks.
    final blush = Paint()..color = const Color(0xFFFF6F91).withValues(alpha: mood == Mood.fresh ? 0.45 : 0.25);
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.31, s * 0.58), width: s * 0.09, height: s * 0.05), blush);
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.69, s * 0.58), width: s * 0.09, height: s * 0.05), blush);

    // Eyes.
    switch (mood) {
      case Mood.fresh:
      case Mood.okay:
        for (final c in [left, right]) {
          _openEye(canvas, c, eyeR, 1 - blink);
        }
      case Mood.tired:
        // Heavy half-closed lids.
        for (final c in [left, right]) {
          _openEye(canvas, c, eyeR, 0.45 * (1 - blink));
          canvas.drawLine(c.translate(-eyeR * 1.1, -eyeR * 0.1), c.translate(eyeR * 1.1, -eyeR * 0.1), ink);
        }
      case Mood.fried:
        // Dizzy spirals.
        for (final c in [left, right]) {
          canvas.drawArc(Rect.fromCircle(center: c, radius: eyeR), 0, math.pi * 1.6, false, ink..strokeWidth = s * 0.014);
          canvas.drawArc(Rect.fromCircle(center: c, radius: eyeR * 0.45), math.pi, math.pi * 1.5, false, ink);
        }
        ink.strokeWidth = s * 0.022;
      case Mood.melted:
        // Closed, sleepy.
        for (final c in [left, right]) {
          canvas.drawArc(Rect.fromCircle(center: c, radius: eyeR), 0.1, math.pi - 0.2, false, ink);
        }
    }

    // Mouth.
    final m = Offset(s * 0.50, s * 0.61);
    switch (mood) {
      case Mood.fresh:
        final p = Path()
          ..moveTo(m.dx - s * 0.07, m.dy - s * 0.01)
          ..quadraticBezierTo(m.dx, m.dy + s * 0.08, m.dx + s * 0.07, m.dy - s * 0.01)
          ..close();
        canvas.drawPath(p, fill);
        canvas.drawCircle(m.translate(0, s * 0.03), s * 0.022, Paint()..color = const Color(0xFFFF6F91));
      case Mood.okay:
        canvas.drawArc(Rect.fromCenter(center: m, width: s * 0.10, height: s * 0.06), 0.2, math.pi - 0.4, false, ink);
      case Mood.tired:
        canvas.drawOval(Rect.fromCenter(center: m.translate(0, s * 0.01), width: s * 0.05, height: s * 0.065), fill);
      case Mood.fried:
        final p = Path()..moveTo(m.dx - s * 0.06, m.dy);
        for (var i = 0; i < 4; i++) {
          p.relativeQuadraticBezierTo(s * 0.015, (i.isEven ? -1 : 1) * s * 0.025, s * 0.03, 0);
        }
        canvas.drawPath(p, ink);
      case Mood.melted:
        canvas.drawArc(Rect.fromCenter(center: m.translate(0, s * 0.03), width: s * 0.10, height: s * 0.06), math.pi + 0.2, math.pi - 0.4, false, ink);
        // Drool.
        canvas.drawOval(Rect.fromCenter(center: m.translate(s * 0.04, s * 0.06), width: s * 0.02, height: s * 0.04), Paint()..color = const Color(0xFF8ED8FF));
    }
  }

  void _openEye(Canvas canvas, Offset c, double r, double open) {
    final h = r * 2 * open.clamp(0.08, 1.0);
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: h), Paint()..color = BB.ink);
    if (open > 0.4) {
      canvas.drawCircle(c.translate(r * 0.35, -r * 0.35), r * 0.32, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_BrainPainter old) =>
      old.mood != mood || old.bob != bob || old.blink != blink || old.wobble != wobble || old.glow != glow;
}
