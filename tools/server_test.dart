// اختبار سيرفر الإنترنت محلياً: cd server && npx wrangler dev --port 8799
// dart run tools/server_test.dart http://127.0.0.1:8799
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> wait([int ms = 250]) => Future.delayed(Duration(milliseconds: ms));

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) exitCode = 1;
}

class Client {
  Client(this.name);
  final String name;
  late WebSocket ws;
  Map<String, dynamic>? room, state;
  int seat = -1;
  final emos = <int>[];

  Future<void> connect(String base, String code) async {
    ws = await WebSocket.connect('${base.replaceFirst('http', 'ws')}/ws/$code');
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      if (m['t'] == 'room') room = m;
      if (m['t'] == 'state') state = m['s'] as Map<String, dynamic>;
      if (m['t'] == 'you') seat = m['seat'] as int;
      if (m['t'] == 'emo') emos.add(m['i'] as int);
    });
    send({'t': 'join', 'name': name, 'token': '$name-tok'});
  }

  void send(Map<String, dynamic> m) => ws.add(jsonEncode(m));
}

Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'http://127.0.0.1:8799' : args.first;
  final hc = HttpClient();
  final req = await hc.getUrl(Uri.parse('$base/new'));
  final code = (jsonDecode(await (await req.close()).transform(utf8.decoder).join()) as Map)['code'] as String;
  final a = Client('host'), b = Client('guest');
  await a.connect(base, code);
  await wait();
  await b.connect(base, code);
  await wait();
  a.send({'t': 'cfg', 'game': 'xo', 'crazy': false});
  a.send({'t': 'start'});
  await wait(500);
  check(b.room?['started'] == true, 'guest sees match started');
  final r1 = b.room!['round'] as int;
  for (final mv in [[a, 0], [b, 3], [a, 1], [b, 4], [a, 2]]) {
    (mv[0] as Client).send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
    await wait(150);
  }
  a.send({'t': 'again'});
  await wait(500);
  check((b.room!['round'] as int) == r1 + 1, 'again bumps round on the internet server');

  // رجوع للغرفة + تفاعل + بطولة
  a.send({'t': 'lobby'});
  await wait(400);
  a.send({'t': 'emo', 'i': 1});
  await wait(300);
  check(b.emos.contains(1), 'emoji relayed');
  a.send({'t': 'tour', 'games': ['xo', 'connect4']});
  await wait(500);
  check(b.room?['tour'] != null && b.room?['game'] == 'xo', 'tour starts');
  for (final mv in [[a, 0], [b, 3], [a, 1], [b, 4], [a, 2]]) {
    (mv[0] as Client).send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
    await wait(150);
  }
  await wait(500);
  check(b.room?['tour']?['pts']?['0'] == 3, 'tour winner gets 3 points');
  a.send({'t': 'again'});
  await wait(500);
  check(b.room?['game'] == 'connect4', 'tour moves to next game');
  await a.ws.close();
  await b.ws.close();

  // هل الغرفة موجودة؟
  Future<Map> getJson(String path) async {
    final rq = await hc.getUrl(Uri.parse('$base$path'));
    return jsonDecode(await (await rq.close()).transform(utf8.decoder).join()) as Map;
  }

  check((await getJson('/info/$code'))['exists'] == true, '/info finds the room');
  check((await getJson('/info/ZZZZ'))['exists'] == false, '/info for unknown code');

  // لعب سريع: اثنين يطلبون نفس اللعبة → نفس الغرفة وتبدي لحالها
  final q1 = (await getJson('/quick?game=xo'))['code'] as String;
  final c = Client('stranger1');
  await c.connect(base, q1);
  await wait(400);
  final q2 = (await getJson('/quick?game=xo'))['code'] as String;
  check(q1 == q2, 'quick match pairs into the same room ($q1, $q2)');
  final d = Client('stranger2');
  await d.connect(base, q2);
  await wait(800);
  check(c.room?['public'] == true, 'quick room is public');
  check(c.room?['started'] == true && c.state != null, 'quick room auto-starts when full');
  await c.ws.close();
  await d.ws.close();
  exit(exitCode);
}
