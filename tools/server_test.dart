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

  // المحيبس ما يطلع باللعب السريع
  final mq = await hc.getUrl(Uri.parse('$base/quick?game=muhaibes'));
  check((await mq.close()).statusCode == 400, 'muhaibes not in quick match');

  // المحيبس: غرفة بـ 4، والسيرفر يخفي المحبس عن الفريق الثاني
  final req2 = await hc.getUrl(Uri.parse('$base/new'));
  final code2 = (jsonDecode(await (await req2.close()).transform(utf8.decoder).join()) as Map)['code'] as String;
  final ps = [Client('m0'), Client('m1'), Client('m2'), Client('m3')];
  for (final p in ps) {
    await p.connect(base, code2);
    await wait(200);
  }
  ps[0].send({'t': 'cap', 'n': 4});
  await wait(300);
  check(ps[1].room?['cap'] == 4, 'host sets room size');
  final extra = Client('m4');
  await extra.connect(base, code2);
  await wait(400);
  check(extra.seat < 0, 'room size enforced');
  ps[0].send({'t': 'cfg', 'game': 'muhaibes', 'crazy': false});
  ps[0].send({'t': 'start'});
  await wait(800);
  final seats = [for (final s in ps[0].room!['seats'] as List) s as int];
  Client byPlayer(int p) => ps.firstWhere((x) => x.seat == seats[p]);
  check(seats.length == 4 && ps[0].state != null, 'muhaibes starts with 4');
  final hider = ps[0].state!['hider'] as int, leader = ps[0].state!['leader'] as int;
  final f = hider * 2;
  byPlayer(hider).send({'t': 'in', 'd': {'a': 'hide', 'f': f}});
  await wait(800);
  check(byPlayer((hider + 2) % 4).state?['ring'] == f, 'teammate sees the ring');
  check(byPlayer(leader).state?['ring'] == -1 && byPlayer((leader + 2) % 4).state?['ring'] == -1, 'other team does NOT see the ring');
  byPlayer(leader).send({'t': 'in', 'd': {'a': 'bat', 'f': f}});
  await wait(800);
  final ts = byPlayer(leader).state?['ts'] as List?;
  check(ts != null && ts[leader % 2] == 3, 'correct bat scores 3');
  for (final p in [...ps, extra]) {
    await p.ws.close();
  }
  exit(exitCode);
}
