// صور للطاولة (للمراجعة بالعين): flutter test tools/domino_snap_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/games/domino.dart';
import 'package:lamma/games/domino_board.dart';
import 'package:lamma/logic/domino_bot.dart';
import 'package:lamma/logic/domino_logic.dart';

const out = String.fromEnvironment('OUT', defaultValue: 'build/snaps');

DominoModel play(bool fives, int seed, int moves) {
  final m = DominoModel(players: 2, crazy: false, seed: seed, fives: fives, goal: 200);
  final r = math.Random(seed);
  var n = 0;
  for (var k = 0; k < 5000 && n < moves && m.phase == 'play'; k++) {
    final mv = DominoBot.move(m, m.turn, 2, r);
    if (mv != null) {
      m.input(m.turn, mv);
      if (mv['a'] == 'play') n++;
    }
    m.advance(0.25);
  }
  return m;
}

void main() {
  testWidgets('snaps', (tester) async {
    await tester.runAsync(() async {
      Directory(out).createSync(recursive: true);
      for (final (name, fives, seed, size) in [
        ('fives_phone', true, 11, const Size(330, 380)),
        ('fives_phone2', true, 23, const Size(330, 380)),
        ('classic_phone', false, 5, const Size(330, 380)),
        ('fives_wide', true, 11, const Size(900, 420)),
      ]) {
        final m = play(fives, seed, 40);
        final (l, cam) = fitBoard(m, size, 34);
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E4D3A));
        for (final t in l.tiles) {
          paintTile(c, cam.rectToScreen(t.rect, size).deflate(cam.u * 0.04), t.a, t.b);
        }
        for (final g in l.ghosts.values) {
          c.drawRect(cam.rectToScreen(g, size), Paint()..style = PaintingStyle.stroke..color = Colors.yellow..strokeWidth = 2);
        }
        final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });
}
