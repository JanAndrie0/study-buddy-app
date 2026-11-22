// Renders the legacy launcher PNGs (Android 7.x, which has no adaptive icons)
// from the same code as the in-app logo, so every icon matches Figma.
//
// Run from the project root:  flutter test tool/render_launcher_icons.dart
// (Not part of the normal test run or CI: those only run test/.)

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:study_buddy/widgets/logo.dart';

void main() {
  testWidgets('render legacy launcher icons', (tester) async {
    const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    for (final MapEntry(key: density, value: px) in sizes.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr, // the logo has a screen-reader label
        child: Center(child: RepaintBoundary(key: key, child: StudyBuddyLogo(size: px.toDouble()))),
      ));
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
        file.writeAsBytesSync(png!.buffer.asUint8List());
        expect(image.width, px);
      });
    }
  });
}
