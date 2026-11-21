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

  room.dispose();
  await http.close(force: true);
  exit(exitCode);
}
