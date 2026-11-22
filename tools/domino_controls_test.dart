// تحكم الدومينو: flutter test tools/domino_controls_test.dart
// ضغطة تختار وضغطة على الطاولة تلعب، الضغطة المزدوجة، الحجر اللي ما ينفع ما ينلعب،
// السحب والإفلات على المكان الصح يلعب، وبمكان غلط يرجع لليد.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/core/profile.dart';
import 'package:lamma/core/sfx.dart';
import 'package:lamma/games/domino.dart';
import 'package:lamma/logic/domino_bot.dart';
import 'package:lamma/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget home) => MaterialApp(
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: home,
    );

/// يفتح لعبة لاعبين على نفس الجهاز ويضغط "أنا جاهز"
Future<void> open(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app(const DominoGame(players: 2)));
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(find.text('أنا جاهز'));
  await t.pump(const Duration(milliseconds: 300));
}

Finder tile(int t) => find.byKey(ValueKey('hand-$t'));

/// نص الطاولة (المكان الأول بالنص)
Offset boardCenter(WidgetTester t) => t.getCenter(find.byKey(const ValueKey('board')));

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'name': 'تجربة', 'avatar': '🐼'});
    Sfx.enabled = false;
    Sfx.testMute = true; // حتى لو اللمسات العشوائية شغّلت زر الصوت
    await Profile.I.load();
  });

  testWidgets('ضغطة تختار، وضغطة على المكان تلعب', (t) async {
    await open(t);
    final m = debugDominoModel!();
    final must = m.mustStart;
    // حجر ما ينفع: ما ينلعب
    final bad = m.hands[m.turn].firstWhere((x) => x != must);
    await t.tap(tile(bad));
    await t.pump(const Duration(milliseconds: 100));
    await t.tapAt(boardCenter(t));
    await settle(t);
    expect(m.chainLen, 0, reason: 'invalid tile must not play');
    // الحجر الصح: اختيار ثم ضغطة على النص
    await t.tap(tile(must));
    await t.pump(const Duration(milliseconds: 500));
    expect(m.chainLen, 0, reason: 'one tap only selects');
    await t.tapAt(boardCenter(t));
    await settle(t);
    expect(m.chainLen, 1);
    expect(m.chainTile(0), must);
  });

  testWidgets('ضغطة مزدوجة تلعب الحجر اللي إله مكان واحد', (t) async {
    await open(t);
    final m = debugDominoModel!();
    final must = m.mustStart;
    await t.tap(tile(must));
    await t.pump(const Duration(milliseconds: 120));
    await t.tap(tile(must));
    await settle(t);
    expect(m.chainLen, 1);
  });

  testWidgets('السحب للمكان الصح يلعب، وللغلط يرجع', (t) async {
    await open(t);
    final m = debugDominoModel!();
    final must = m.mustStart;
    // سحب لزاوية فوق (غلط): يرجع
    var g = await t.startGesture(t.getCenter(tile(must)));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(t.getCenter(tile(must)), const Offset(80, 120), i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t);
    expect(m.chainLen, 0, reason: 'drop in a wrong place returns');
    // سحب للنص: يلتصق وينلعب
    final from = t.getCenter(tile(must));
    g = await t.startGesture(from);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(from, boardCenter(t), i / 12)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t);
    expect(m.chainLen, 1, reason: 'drop on the spot plays');
  });

  // ضد الكمبيوتر: مباراة كاملة. الكمبيوتر يلعب وحده، و"الجولة التالية" تنضغط من النافذة
  for (final (level, bots) in [
    (0, [false, true]),
    (1, [false, true, true, true]),
  ]) {
    testWidgets('مباراة كاملة ضد الكمبيوتر: مستوى $level، ${bots.length} لاعبين', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(DominoGame(players: bots.length, level: level, bots: bots)));
      await t.pump(const Duration(milliseconds: 100));
      final m = debugDominoModel!();
      expect(find.text('أنا جاهز'), findsNothing, reason: 'one human: no pass-the-phone cover');
      final r = math.Random(5);
      var rounds = 0, sawThinking = false;
      for (var k = 0; k < 6000 && !m.over; k++) {
        await t.pump(const Duration(milliseconds: 200));
        if (find.textContaining('يفكّر').evaluate().isNotEmpty) sawThinking = true;
        if (m.phase == 'round') {
          final b = find.text('الجولة التالية').evaluate().isNotEmpty ? find.text('الجولة التالية') : find.text('النتيجة النهائية');
          if (b.evaluate().isNotEmpty) {
            await t.tap(b.first);
            rounds++;
          }
        } else if (m.turn == 0 && m.phase == 'play') {
          final mv = DominoBot.move(m, 0, 2, r);
          if (mv != null) m.input(0, mv);
        }
      }
      expect(m.over, isTrue, reason: 'match finishes');
      expect(rounds, greaterThan(0));
      expect(sawThinking, isTrue);
      expect(m.goal, const [50, 100, 200][level]);
      expect(m.fives, level >= 1);
      await t.pump(const Duration(seconds: 2));
    });
  }
}
