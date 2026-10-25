// Renders the Brain Bean mascot in every mood as transparent PNGs, for posters and store graphics.
// Run: flutter test tool/render_poster_brains_test.dart   (files land in build/poster/)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_buddy/core/models.dart';
import 'package:brain_buddy/widgets/brain_buddy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('render brains for the poster', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    for (final mood in Mood.values) {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(dimension: 256, child: BrainBuddy(mood: mood, size: 240, glow: false)),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 4); // 1024 x 1024
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/poster/brain_${mood.name}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
