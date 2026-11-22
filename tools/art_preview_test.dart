import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/ui/art.dart';

// يرسم كل الشخصيات بصورة وحدة للمراجعة: flutter test tools/art_preview_test.dart
void main() {
  testWidgets('mascots preview', (t) async {
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(1000, 520));
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFF151C36),
          child: Wrap(spacing: 20, runSpacing: 20, children: [
            for (final e in kMascots.keys) Avatar(e, size: 220),
            for (final e in kMascots.keys) Avatar(e, size: 40),
          ]),
        ),
      ),
    ));
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ImageByteFormat.png);
      File('/tmp/claude-0/scratch/mascots.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
