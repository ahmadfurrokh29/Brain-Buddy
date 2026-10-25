// Renders the splash picture (brain in a white circle, "Brain Bean", tagline) used by BOTH Android's
// start-up screen and the Flutter splash, so the two look like one screen.
//
// The fonts are the ones the app downloads at run time. Copy them from a phone first:
//   adb exec-out run-as com.brainbuddy.app cat files/Fredoka_600_<hash>.ttf > build/splash_fonts/Fredoka-600.ttf
//   adb exec-out run-as com.brainbuddy.app cat files/Nunito_700_<hash>.ttf  > build/splash_fonts/Nunito-700.ttf
// Run: flutter test tool/render_splash_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:brain_buddy/core/models.dart';
import 'package:brain_buddy/widgets/brain_buddy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Size of the picture in dp. The brain's circle is centred in it, so it lands in the screen's centre.
const splashSize = Size(320, 400);

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  testWidgets('render splash picture', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(() async {
      await _loadFont('SplashFredoka', 'build/splash_fonts/Fredoka-600.ttf');
      await _loadFont('SplashNunito', 'build/splash_fonts/Nunito-700.ttf');
    });

    final key = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.fromSize(
            size: splashSize,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const BrainBuddy(mood: Mood.fresh, size: 140, glow: false),
              ),
              const Positioned(
                top: 312,
                child: Text(
                  'Brain Bean',
                  style: TextStyle(fontFamily: 'SplashFredoka', fontSize: 36, color: Colors.white, height: 1.2),
                ),
              ),
              Positioned(
                top: 360,
                child: Text(
                  'Scroll less, live more',
                  style: TextStyle(fontFamily: 'SplashNunito', fontSize: 16, color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 4); // 1280 x 1600 = 320 x 400 dp at xxxhdpi
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      for (final path in ['android/app/src/main/res/drawable-xxxhdpi/splash_logo.png', 'assets/splash/splash.png']) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(png);
      }
    });
  });
}
