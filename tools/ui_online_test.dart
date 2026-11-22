// اختبار شاشات الأونلاين: flutter test tools/ui_online_test.dart
// غرفة محلية حقيقية (LanHost) + لاعبين وهميين يلعبون عشوائياً، وأنا (الواجهة) صاحب الغرفة.
// كل لعبة بأحجام شاشات مختلفة: أي خطأ أو عنصر طالع برا الشاشة = فشل.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/core/profile.dart';
import 'package:lamma/core/sfx.dart';
import 'package:lamma/net/lan.dart';
import 'package:lamma/net/room.dart';
import 'package:lamma/ui/online.dart';
import 'package:lamma/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sizes = {
  'تلفون صغير': Size(320, 568),
  'تلفون': Size(390, 844),
  'كمبيوتر': Size(1366, 768),
};

/// (اللعبة، عدد اللاعبين، الوضع الثاني)
const cases = [
  ('whois', 3, false),
  ('whois', 8, true),
  ('muhaibes', 4, false),
  ('muhaibes', 8, false),
  ('domino', 2, false),
  ('domino', 4, true),
  ('pigeon', 2, false),
  ('pigeon', 4, true),
  ('hockey', 2, false),
  ('quiz', 4, false),
  ('reaction', 3, false),
  ('tug', 2, false),
  ('xo', 2, false),
  ('connect4', 2, false),
];

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

class Bot {
  Bot(this.name);
  final String name;
  late WebSocket ws;
  Map<String, dynamic>? room, state;
  int seat = -1;

  Future<void> connect(int port, String code) async {
    ws = await WebSocket.connect('ws://127.0.0.1:$port/ws/$code');
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      if (m['t'] == 'room') room = m;
      if (m['t'] == 'state') state = m['s'] as Map<String, dynamic>;
      if (m['t'] == 'you') seat = m['seat'] as int;
    }, onError: (_) {});
    send({'t': 'join', 'name': name, 'token': '$name-tok', 'avatar': '🐱'});
  }

  void send(Map<String, dynamic> m) {
    try {
      ws.add(jsonEncode(m));
    } catch (_) {}
  }

  int get me => room == null ? -1 : (room!['seats'] as List).indexOf(seat);

  /// حركة عشوائية (مثل اللاعب الحقيقي)
  void play(String id, math.Random r) {
    final s = state;
    final p = me;
    if (s == null || p < 0) return;
    final n = s['players'] as int;
    Map<String, dynamic> d;
    switch (id) {
      case 'xo':
        d = {'m': 'put', 'i': r.nextInt(9)};
      case 'connect4':
        d = {'m': 'drop', 'c': r.nextInt(7)};
      case 'tug':
      case 'reaction':
        d = {'m': 'tap'};
      case 'hockey':
        d = {'m': 'pad', 'x': r.nextDouble(), 'y': r.nextDouble()};
      case 'pigeon':
        d = {'m': 'shot', 'dx': r.nextDouble() * 2 - 1, 'dy': r.nextDouble() * 2 - 1, 'pw': r.nextDouble()};
      case 'quiz':
        d = {'m': 'ans', 'a': r.nextInt(4)};
      case 'muhaibes':
        d = {'a': ['hide', 'aim', 'open', 'bat', 'shake'][r.nextInt(5)], 'f': r.nextInt(n * 2)};
      case 'domino':
        final hand = (s['hands'] as List)[p] as List;
        d = hand.isEmpty || r.nextInt(4) == 0 ? {'a': 'draw'} : {'a': 'play', 't': hand[r.nextInt(hand.length)], 's': r.nextBool() ? 'l' : 'r'};
      case 'whois':
        d = {'a': 'vote', 't': r.nextInt(n)};
      default:
        return;
    }
    send({'t': 'in', 'd': d});
  }
}

Future<void> real(WidgetTester t, int ms) => t.runAsync(() => Future.delayed(Duration(milliseconds: ms)));

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'name': 'أنا', 'avatar': '🐼'});
    Sfx.enabled = false;
    await loadFont('Vazirmatn', ['assets/fonts/Vazirmatn-Regular.ttf', 'assets/fonts/Vazirmatn-Bold.ttf', 'assets/fonts/Vazirmatn-ExtraBold.ttf', 'assets/fonts/Vazirmatn-Black.ttf']);
    await loadFont('Lalezar', ['assets/fonts/Lalezar-Regular.ttf']);
    await Profile.I.load();
  });

  for (final e in sizes.entries) {
    for (final (id, n, crazy) in cases) {
      testWidgets('$id $n لاعبين${crazy ? ' (الوضع الثاني)' : ''} - ${e.key}', (t) async {
        // flutter test يمنع الشبكة افتراضياً؛ هنا نحتاج اتصال حقيقي بالغرفة المحلية
        HttpOverrides.global = null;
        t.view.physicalSize = e.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final r = math.Random(n * 13 + id.length);

        final host = (await t.runAsync(LanHost.start))!;
        // الاتصال لازم ينبني بالوقت الحقيقي (مو الوقت الوهمي مال الاختبار)
        final room = (await t.runAsync(() async => RoomConn.join(host.code, Profile.I.name, server: host.selfServer)))!;
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: LobbyScreen(room: room, lanHost: host),
        ));
        await real(t, 300);
        await t.pump(const Duration(milliseconds: 300));

        final bots = [for (var i = 0; i < n - 1; i++) Bot('لاعب${i + 1}')];
        await t.runAsync(() async {
          for (final b in bots) {
            await b.connect(host.port, host.code);
            await Future.delayed(const Duration(milliseconds: 60));
          }
        });
        await real(t, 300);
        await t.pump(const Duration(milliseconds: 500));
        expect(room.players.length, n, reason: 'كل اللاعبين دخلوا الغرفة');

        room.setGame(id, crazy);
        await real(t, 150);
        room.start();
        await real(t, 300);
        await t.pump(const Duration(seconds: 1));

        // نلعب: الوهميين يتحركون، وأنا ألمس الشاشة عشوائياً
        for (var step = 0; step < 220; step++) {
          for (final b in bots) {
            if (r.nextInt(3) == 0) b.play(id, r);
          }
          if (r.nextInt(2) == 0) {
            final at = Offset(r.nextDouble() * e.value.width, r.nextDouble() * e.value.height);
            if (r.nextInt(3) == 0) {
              final g = await t.startGesture(at);
              await t.pump(const Duration(milliseconds: 30));
              await g.moveBy(Offset((r.nextDouble() - 0.5) * 120, r.nextDouble() * 150));
              await t.pump(const Duration(milliseconds: 30));
              await g.up();
            } else {
              await t.tapAt(at);
            }
          }
          await real(t, 40);
          await t.pump(const Duration(milliseconds: 150));
        }

        for (final b in bots) {
          await t.runAsync(() async => b.ws.close());
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        await real(t, 400);
        await t.runAsync(host.stop);
      });
    }
  }
}
