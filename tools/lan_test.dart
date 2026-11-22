// اختبار سريع لغرفة نفس الشبكة: سيرفر محلي + لاعبين وهميين.
// dart run tools/lan_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lamma/net/lan_room.dart';

class _Peer extends LanPeer {
  _Peer(this.ws);
  final WebSocket ws;
  @override
  void send(String d) => ws.add(d);
  @override
  void close(int c, String r) => ws.close(c, r);
}

class Client {
  Client(this.name);
  final String name;
  late WebSocket ws;
  final msgs = <Map<String, dynamic>>[];
  Map<String, dynamic>? room, state;
  int seat = -1;

  Future<void> connect(int port) async {
    ws = await WebSocket.connect('ws://127.0.0.1:$port/ws/ABCD');
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      msgs.add(m);
      if (m['t'] == 'room') room = m;
      if (m['t'] == 'state') state = m['s'] as Map<String, dynamic>;
      if (m['t'] == 'you') seat = m['seat'] as int;
    });
    send({'t': 'join', 'name': name, 'token': '$name-tok', 'avatar': '🦁'});
  }

  void send(Map<String, dynamic> m) => ws.add(jsonEncode(m));
}

Future<void> wait([int ms = 150]) => Future.delayed(Duration(milliseconds: ms));

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) exitCode = 1;
}

Future<void> main() async {
  final room = LanRoom('ABCD');
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  http.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    final p = _Peer(ws);
    room.connect(p);
    ws.listen((d) => room.message(p, d as String), onDone: () => room.closed(p));
  });

  final a = Client('host'), b = Client('guest');
  await a.connect(http.port);
  await wait();
  await b.connect(http.port);
  await wait();
  check(a.seat == 0 && b.seat == 1, 'seats 0 and 1');
  check(a.room?['host'] == 0, 'first player is host');

  a.send({'t': 'cfg', 'game': 'xo', 'crazy': false});
  a.send({'t': 'start'});
  await wait();
  check(b.room?['started'] == true && b.state != null, 'match started for guest');
  final r1 = b.room!['round'] as int;

  // xo: اللاعب 0 يفوز بالصف الأول
  for (final mv in [[a, 0], [b, 3], [a, 1], [b, 4], [a, 2]]) {
    final c = mv[0] as Client;
    c.send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
    await wait(60);
  }
  check(b.state?['win'] != null || b.state?['winner'] != null || b.msgs.any((m) => m['t'] == 'state'), 'states flowing');
  // الضيف رجع للغرفة، وصاحب الغرفة ضغط "مرة ثانية"
  a.send({'t': 'again'});
  await wait();
  final r2 = b.room!['round'] as int;
  check(r2 == r1 + 1, 'again bumps round ($r1 -> $r2) so the guest re-opens the game');

  // الضيف انقطع ورجع بنفس المقعد
  await b.ws.close();
  await wait();
  check(a.room?['players'].any((p) => p['seat'] == 1 && p['on'] == false) == true, 'guest shown offline');
  final b2 = Client('guest');
  await b2.connect(http.port);
  await wait();
  check(b2.seat == 1, 'guest reconnects to same seat');
  check(b2.state != null, 'guest gets current state on reconnect');

  // ping
  b2.send({'t': 'ping'});
  await wait();
  check(b2.msgs.any((m) => m['t'] == 'pong'), 'pong');

  // صاحب الغرفة يرجّع الكل للغرفة
  a.send({'t': 'lobby'});
  await wait();
  check(b2.room?['started'] == false, 'lobby ends match');

  // صورة رمزية + تفاعل
  check(b2.room?['players'].any((p) => p['avatar'] == '🦁') == true, 'avatar shared');
  a.send({'t': 'emo', 'i': 3});
  await wait();
  check(b2.msgs.any((m) => m['t'] == 'emo' && m['i'] == 3 && m['seat'] == 0), 'emoji relayed');
  a.send({'t': 'emo', 'i': 99});
  await wait();
  check(!b2.msgs.any((m) => m['t'] == 'emo' && m['i'] == 99), 'bad emoji rejected');

  // بطولة: إكس أو ثم أربعة بالصف
  a.send({'t': 'tour', 'games': ['xo', 'connect4']});
  await wait();
  check(b2.room?['tour'] != null && b2.room?['game'] == 'xo', 'tour starts with first game');
  for (final mv in [[a, 0], [b2, 3], [a, 1], [b2, 4], [a, 2]]) {
    (mv[0] as Client).send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
    await wait(60);
  }
  await wait();
  check(b2.room?['tour']['pts']['0'] == 3, 'winner of game 1 gets 3 points');
  a.send({'t': 'again'});
  await wait();
  check(b2.room?['game'] == 'connect4' && b2.room?['tour']['idx'] == 1, 'again moves tour to next game');
  a.send({'t': 'lobby'});
  await wait();

  // عدد اللاعبين يحدده صاحب الغرفة
  a.send({'t': 'cap', 'n': 3});
  await wait();
  check(b2.room?['cap'] == 3, 'host sets room size');
  final c = Client('third'), d = Client('fourth');
  await c.connect(http.port);
  await wait();
  await d.connect(http.port);
  await wait();
  check(c.seat == 2 && d.msgs.any((m) => m['t'] == 'err' && m['m'] == 'full'), 'room size enforced');

  // المحيبس: 4 لاعبين أقل شي
  a.send({'t': 'cfg', 'game': 'muhaibes', 'crazy': false});
  a.send({'t': 'start'});
  await wait();
  check(a.room?['started'] == false, 'muhaibes needs 4 players');
  a.send({'t': 'cap', 'n': 8});
  await wait();
  final d2 = Client('fourth');
  await d2.connect(http.port);
  await wait();
  check(d2.seat == 3, 'fourth player joins after size raised');
  a.send({'t': 'start'});
  await wait(400);
  final all = [a, b2, c, d2];
  final seats = [for (final s in a.room!['seats'] as List) s as int];
  Client byPlayer(int p) => all.firstWhere((x) => x.seat == seats[p]);
  check(a.room?['started'] == true && seats.length == 4, 'muhaibes starts with 4');
  final st = a.state!;
  final holding = st['ht'] as int, hider = st['hider'] as int, leader = st['leader'] as int;
  check(hider % 2 == holding && leader % 2 != holding, 'hider and leader on the right teams');
  final f = hider * 2 + 1;
  byPlayer(hider).send({'t': 'in', 'd': {'a': 'hide', 'f': f}});
  await wait(500);
  final mate = byPlayer((hider + 2) % 4), foe = byPlayer(leader);
  check(mate.state?['ring'] == f && byPlayer(hider).state?['ring'] == f, 'hiding team sees the ring');
  check(foe.state?['ring'] == -1 && byPlayer((leader + 2) % 4).state?['ring'] == -1, 'other team does NOT see the ring');
  check(foe.state?['ph'] == 'guess', 'guess phase');
  foe.send({'t': 'in', 'd': {'a': 'bat', 'f': f}});
  await wait(500);
  final ts = foe.state?['ts'] as List?;
  check(ts != null && ts[1 - holding] == 3 && foe.state?['ring'] == f, 'correct bat scores 3 and reveals the ring');

  // منو بينا؟: 3 لاعبين أقل شي، والأصوات سرية
  a.send({'t': 'lobby'});
  await wait();
  a.send({'t': 'cfg', 'game': 'whois', 'crazy': false});
  a.send({'t': 'start'});
  await wait(3500);
  check(a.room?['started'] == true, 'whois starts with 4');
  final wp = [for (final s in a.room!['seats'] as List) all.firstWhere((x) => x.seat == s as int)];
  check(wp[0].state?['ph'] == 'vote', 'whois reaches voting');
  wp[0].send({'t': 'in', 'd': {'a': 'vote', 't': 1}});
  wp[1].send({'t': 'in', 'd': {'a': 'vote', 't': 0}});
  await wait(600);
  final wv0 = wp[0].state?['votes'] as List, wv2 = wp[2].state?['votes'] as List;
  check(wv0[0] == 1 && wv0[1] == -2, 'whois: I see my vote only');
  check(wv2[0] == -2 && wv2[1] == -2 && wv2[2] == -1, 'whois: others hidden from voters');
  wp[2].send({'t': 'in', 'd': {'a': 'vote', 't': 1}});
  wp[3].send({'t': 'in', 'd': {'a': 'vote', 't': 1}});
  await wait(600);
  check(wp[0].state?['ph'] == 'reveal' && (wp[0].state?['tally'] as List)[1] == 3, 'whois reveal tallies 3 votes');

  // الجاسوس: الجاسوس ما يشوف المكان، والباقي ما يشوفون الجاسوس
  a.send({'t': 'lobby'});
  await wait();
  a.send({'t': 'cfg', 'game': 'spy', 'crazy': false});
  a.send({'t': 'start'});
  await wait(8200);
  final sp = [for (final s in a.room!['seats'] as List) all.firstWhere((x) => x.seat == s as int)];
  check(sp[0].state?['ph'] == 'play', 'spy reaches play');
  final spyViews = [for (final x in sp) x.state!];
  final spyN = spyViews.where((v) => (v['spies'] as List).isNotEmpty).length;
  check(spyN == 1, 'spy: exactly one player sees a spy (himself)');
  check(spyViews.where((v) => (v['spies'] as List).isNotEmpty).every((v) => v['place'] == -1), 'spy: the spy does not see the place');
  check(spyViews.where((v) => (v['spies'] as List).isEmpty).every((v) => (v['place'] as int) >= 0), 'spy: others see the place');
  final turnP = sp[0].state!['turn'] as int, nxt = (turnP + 1) % sp.length;
  sp[turnP].send({'t': 'in', 'd': {'a': 'ask', 't': nxt}});
  await wait(500);
  check(sp[0].state?['turn'] == nxt && sp[0].state?['prev'] == turnP, 'spy: asking passes the turn');

  // الدومينو بأربعة: كل واحد يشوف قطعه بس
  a.send({'t': 'lobby'});
  await wait();
  a.send({'t': 'cfg', 'game': 'domino', 'crazy': true});
  a.send({'t': 'start'});
  await wait(400);
  check(a.room?['game'] == 'domino' && a.room?['started'] == true, 'domino starts with 4');
  final dseats = [for (final s in a.room!['seats'] as List) s as int];
  final pa = dseats.indexOf(a.seat);
  final hands = a.state!['hands'] as List;
  check((hands[pa] as List).every((t) => (t as int) >= 0) && (hands[pa] as List).length == 7, 'own 7 tiles visible');
  check([for (var p = 0; p < 4; p++) if (p != pa) hands[p]].every((h) => (h as List).every((t) => t == -1)), 'opponent tiles hidden');
  // اللي دوره يلعب القطعة الإجبارية
  final turn = a.state!['turn'] as int, must = a.state!['must'] as int;
  final tc = [a, b2, c, d2].firstWhere((x) => x.seat == dseats[turn]);
  tc.send({'t': 'in', 'd': {'a': 'play', 't': must, 's': 'r'}});
  await wait(500);
  check((a.state!['chain'] as List).isNotEmpty && a.state!['turn'] == (turn + 1) % 4, 'opening double played, next turn');

  // الكمبيوتر بالغرفة: صاحب الغرفة يضيفه، والمستوى ينحفظ، والكمبيوتر يلعب وحده
  final room2 = LanRoom('BOTS');
  final http2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  http2.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    final p = _Peer(ws);
    room2.connect(p);
    ws.listen((d) => room2.message(p, d as String), onDone: () => room2.closed(p));
  });
  final solo = Client('solo');
  await solo.connect(http2.port);
  await wait();
  solo.send({'t': 'bot'}); // قبل اختيار لعبة يلعبها الكمبيوتر: ما يصير
  await wait();
  check((solo.room!["players"] as List).length == 1, 'no bot before choosing a bot game');
  solo.send({'t': 'cfg', 'game': 'domino', 'crazy': false, 'level': 2});
  solo.send({'t': 'bot'});
  await wait();
  final bp = solo.room!["players"] as List;
  check(solo.room?["level"] == 2 && bp.length == 2 && bp.any((x) => x["bot"] == true && x["on"] == true), 'bot added, level saved');
  solo.send({'t': 'start'});
  await wait(300);
  check(solo.room?["started"] == true && solo.state?["goal"] == 200 && solo.state?["lv"] == 2, 'match with bot starts at hard level');
  final bseats = [for (final x in solo.room!["seats"] as List) x as int];
  final me2 = bseats.indexOf(solo.seat);
  if (solo.state!["turn"] == me2) {
    solo.send({'t': 'in', 'd': {'a': 'play', 't': solo.state!["must"], 's': 'r'}});
    await wait(300);
  }
  await wait(2600);
  final tilesOnBoard = ((solo.state!["chain"] as List).length + (solo.state!["up"] as List).length + (solo.state!["dn"] as List).length) ~/ 3;
  check(tilesOnBoard >= 1 && (solo.state!["turn"] == me2 || (solo.state!["hands"] as List)[1 - me2].length < 7), 'bot plays by itself');
  // صاحب الغرفة يشيل الكمبيوتر بالغرفة (بدون منع)
  solo.send({'t': 'lobby'});
  await wait();
  final botSeat = ((solo.room!["players"] as List).firstWhere((x) => x["bot"] == true))["seat"];
  solo.send({'t': 'kick', 'seat': botSeat});
  await wait();
  check((solo.room!["players"] as List).length == 1, 'bot removed');
  room2.dispose();
  await http2.close(force: true);

  // اسم ممنوع ما يدخل
  final rude = Client('شرموطة');
  await rude.connect(http.port);
  await wait(300);
  check(rude.seat < 0 && rude.msgs.any((m) => m['t'] == 'err' && m['m'] == 'name'), 'bad name rejected');

  room.dispose();
  await http.close(force: true);
  exit(exitCode);
}
