// اختبار الشاشات: flutter test tools/ui_test.dart
// الرئيسية وكل لعبة (على نفس الجهاز) بأحجام شاشات مختلفة (تلفون صغير، تلفون، تابلت، كمبيوتر)،
// ويا لمسات وسحبات عشوائية. أي خطأ (استثناء أو عنصر طالع برا الشاشة) = فشل.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/core/profile.dart';
import 'package:lamma/core/sfx.dart';
import 'package:lamma/games/registry.dart';
import 'package:lamma/main.dart';
import 'package:lamma/ui/setup.dart';
import 'package:lamma/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sizes = {
  'تلفون صغير': Size(320, 568),
  'تلفون': Size(390, 844),
  'تلفون عريض': Size(412, 732),
  'تابلت': Size(820, 1180),
  'كمبيوتر': Size(1366, 768),
};

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

/// لمسات وسحبات عشوائية بمدة [secs] ثانية (وقت اللعبة)
Future<void> poke(WidgetTester t, Size s, math.Random r, double secs) async {
  final steps = (secs * 10).round();
  for (var i = 0; i < steps; i++) {
    final at = Offset(r.nextDouble() * s.width, r.nextDouble() * s.height);
    if (r.nextInt(3) == 0) {
      final g = await t.startGesture(at);
      await t.pump(const Duration(milliseconds: 40));
      await g.moveBy(Offset((r.nextDouble() - 0.5) * 160, (r.nextDouble() - 0.5) * 220));
      await t.pump(const Duration(milliseconds: 40));
      await g.up();
    } else {
      await t.tapAt(at);
    }
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'name': 'تجربة', 'avatar': '🐼'});
    Sfx.enabled = false;
    Sfx.testMute = true; // حتى لو اللمسات العشوائية شغّلت زر الصوت
    await loadFont('Vazirmatn', ['assets/fonts/Vazirmatn-Regular.ttf', 'assets/fonts/Vazirmatn-Bold.ttf', 'assets/fonts/Vazirmatn-ExtraBold.ttf', 'assets/fonts/Vazirmatn-Black.ttf']);
    await loadFont('Lalezar', ['assets/fonts/Lalezar-Regular.ttf']);
    await Profile.I.load();
  });

  for (final e in sizes.entries) {
    testWidgets('الرئيسية - ${e.key}', (t) async {
      t.view.physicalSize = e.value;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const LammaApp());
      await t.pump(const Duration(seconds: 1));
      // أقسام الرئيسية: نفتح كل وحدة ونرجع
      for (final label in ['الانضمام إلى صديق', 'ادعُ صديق للمّة', 'ملفي']) {
        final f = find.textContaining(label);
        if (f.evaluate().isEmpty) continue;
        await t.tap(f.first, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 800));
        await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
        await t.pump(const Duration(milliseconds: 800));
      }
      // نفتح بطاقة كل لعبة ونسكّرها
      for (final g in games) {
        final f = find.text(g.title);
        if (f.evaluate().isEmpty) continue;
        await t.ensureVisible(f.first);
        await t.pump();
        await t.tap(f.first, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 600));
        await t.tapAt(const Offset(5, 5));
        await t.pump(const Duration(milliseconds: 600));
      }
    });

    for (final g in games.where((g) => g.local)) {
      for (final n in g.allowedCounts) {
        for (final crazy in g.crazyHowTo != null ? [false, true] : [false]) {
          testWidgets('${g.title} $n لاعبين${crazy ? ' (الوضع الثاني)' : ''} - ${e.key}', (t) async {
            t.view.physicalSize = e.value;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            await t.pumpWidget(app(g.build(n, crazy)));
            await t.pump(const Duration(seconds: 4)); // العد التنازلي
            await poke(t, e.value, math.Random(n * 31 + e.key.length), 25);
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 1));
          });
        }
      }
    }

    // ألعاب المستويات: شاشة البداية، وكل مستوى ويا تشكيلات فيها كمبيوتر
    for (final g in games.where((g) => g.play != null)) {
      testWidgets('${g.title} شاشة البداية - ${e.key}', (t) async {
        t.view.physicalSize = e.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(app(SetupScreen(game: g)));
        await t.pump(const Duration(milliseconds: 600));
        for (final label in ['+ كمبيوتر', '+ شخص', 'صعب', 'سهل']) {
          final f = find.text(label);
          if (f.evaluate().isNotEmpty) await t.tap(f.first, warnIfMissed: false);
          await t.pump(const Duration(milliseconds: 400));
        }
        await poke(t, e.value, math.Random(7), 3);
      });
      for (var level = 0; level < 3; level++) {
        for (final bots in [
          [false, true],
          [false, true, false, true],
          [true, false, true, true],
        ]) {
          if (!g.fits(bots.length)) continue;
          testWidgets('${g.title} مستوى $level ${bots.map((b) => b ? 'ك' : 'ش').join()} - ${e.key}', (t) async {
            t.view.physicalSize = e.value;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            await t.pumpWidget(app(g.play!(level, bots)));
            await t.pump(const Duration(seconds: 2));
            await poke(t, e.value, math.Random(level * 13 + bots.length), 20);
            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 1));
          });
        }
      }
    }
  }
}
