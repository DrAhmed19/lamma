import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/games/registry.dart';
import 'package:lamma/ui/art.dart';

// معاينة أيقونات الألعاب: flutter test tools/art_home_test.dart
void main() {
  testWidgets('game art preview', (t) async {
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(560, 420));
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(
        key: key,
        child: Container(color: const Color(0xFF151C36), padding: const EdgeInsets.all(10), child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in games) GameArt(g.id, fallback: g.icon, size: 96, radius: 20),
        ])),
      ),
    ));
    await t.runAsync(() async {
      for (final g in games) {
        await precacheImage(AssetImage('assets/games/${g.id}.webp'), t.element(find.byType(Wrap)));
      }
    });
    await t.pump();
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      File('/tmp/claude-0/scratch/gamearts.png').writeAsBytesSync((await img.toByteData(format: ImageByteFormat.png))!.buffer.asUint8List());
    });
  });
}
