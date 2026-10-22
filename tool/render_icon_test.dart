// Renders the Brain Buddy mascot to PNG files for the launcher icon.
// Run: flutter test tool/render_icon_test.dart   (then: dart run flutter_launcher_icons)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_buddy/core/models.dart';
import 'package:brain_buddy/theme/app_theme.dart';
import 'package:brain_buddy/widgets/brain_buddy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _render(WidgetTester tester, Widget child, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: RepaintBoundary(key: key, child: SizedBox.square(dimension: 256, child: child))),
  ));
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4); // 1024 x 1024
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render launcher icon', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;

    // Full icon (older launchers): brain on a mint square.
    await _render(
      tester,
      const ColoredBox(
        color: BB.mintLight,
        child: Padding(padding: EdgeInsets.all(28), child: BrainBuddy(mood: Mood.fresh, size: 200, glow: false)),
      ),
      'assets/icon/icon.png',
    );

    // Adaptive icon foreground: brain inside the 66% safe zone, transparent around it.
    await _render(
      tester,
      const Padding(padding: EdgeInsets.all(58), child: BrainBuddy(mood: Mood.fresh, size: 140, glow: false)),
      'assets/icon/foreground.png',
    );
  });
}
