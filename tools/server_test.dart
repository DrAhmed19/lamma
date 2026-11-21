// اختبار سيرفر الإنترنت محلياً: cd server && npx wrangler dev --port 8799
// dart run tools/server_test.dart http://127.0.0.1:8799 [ADMIN_KEY]
// (لاختبار صفحة الإدارة: ADMIN_KEY=... بـ server/.dev.vars ونفسه هنا)
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
  final errs = <String>[];

  Future<void> connect(String base, String code) async {
    ws = await WebSocket.connect('${base.replaceFirst('http', 'ws')}/ws/$code');
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      if (m['t'] == 'room') room = m;
      if (m['t'] == 'state') state = m['s'] as Map<String, dynamic>;
      if (m['t'] == 'you') seat = m['seat'] as int;
      if (m['t'] == 'emo') emos.add(m['i'] as int);
      if (m['t'] == 'err') errs.add(m['m'] as String);
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

  // الدومينو ويا الغرباء: لاعبين بس، وتبدي لمّن يكتملون، والقطع مخفية
  final dq1 = (await getJson('/quick?game=domino'))['code'] as String;
  final e1 = Client('dom1');
  await e1.connect(base, dq1);
  await wait(400);
  final dq2 = (await getJson('/quick?game=domino'))['code'] as String;
  final e2 = Client('dom2');
  await e2.connect(base, dq2);
  await wait(900);
  check(dq1 == dq2 && e1.room?['started'] == true, 'domino quick match starts with 2');
  final dh = e1.state?['hands'] as List?;
  final me1 = (e1.room!['seats'] as List).indexOf(e1.seat);
  check(dh != null && (dh[1 - me1] as List).every((t) => t == -1) && (dh[me1] as List).every((t) => (t as int) >= 0), 'domino hides opponent tiles');
  check((e1.state?['pile'] as List?)?.every((t) => t == -1) == true && (e1.state?['pile'] as List).length == 14, 'domino draw pile hidden (14)');
  await e1.ws.close();
  await e2.ws.close();

  // ------------------------------------------------ الأسماء والإبلاغ والمنع
  Future<Map> postJson(String path, Map body) async {
    final rq = await hc.postUrl(Uri.parse('$base$path'));
    rq.headers.contentType = ContentType.json;
    rq.write(jsonEncode(body));
    return jsonDecode(await (await rq.close()).transform(utf8.decoder).join()) as Map;
  }

  final rude = Client('شرموطة');
  await rude.connect(base, code2);
  await wait(500);
  check(rude.seat < 0 && rude.errs.contains('name'), 'bad name rejected');
  await rude.ws.close();

  // جولة إبلاغ: الهدف يدخل غرفة عامة، و3 أشخاص مختلفين يبلّغون عنه
  final run = DateTime.now().millisecondsSinceEpoch;
  final target = Client('target$run');
  Future<void> reportRound(String game, List<String> names) async {
    final q = (await postJson('/quick', {'game': game, 'dev': '${target.name}-tok'}))['code'] as String;
    await target.connect(base, q);
    await wait(400);
    final rs = <Client>[];
    for (final n in names) {
      final c = Client(n);
      final cq = (await postJson('/quick', {'game': game, 'dev': '$n-tok'}))['code'] as String;
      await c.connect(base, cq);
      rs.add(c);
      await wait(300);
    }
    await wait(400);
    for (final c in rs) {
      c.send({'t': 'report', 'seat': target.seat, 'r': 'abuse'});
      await wait(250);
    }
    await wait(500);
    for (final c in [target, ...rs]) {
      await c.ws.close();
    }
  }

  await reportRound('quiz', ['ra$run', 'rb$run', 'rc$run']);
  final w = await postJson('/quick', {'game': 'xo', 'dev': '${target.name}-tok'});
  check(w['warn'] != null && w['code'] != null, 'first strike = warning only');
  await reportRound('reaction', ['rd$run', 're$run', 'rf$run']);
  final bn = await postJson('/quick', {'game': 'xo', 'dev': '${target.name}-tok'});
  check(bn['error'] == 'banned' && (bn['until'] as num) > DateTime.now().millisecondsSinceEpoch, 'second strike = banned from quick match');
  final ok = await getJson('/new');
  final friend = Client(target.name);
  await friend.connect(base, ok['code'] as String);
  await wait(400);
  check(friend.seat >= 0, 'banned player can still play with friends');
  await friend.ws.close();

  // الحظر: اللي حاظر واحد ما ينجمع وياه
  final x1 = Client('x1$run'), x2 = Client('x2$run');
  final xq = (await postJson('/quick', {'game': 'pigeon', 'dev': '${x1.name}-tok'}))['code'] as String;
  await x1.connect(base, xq);
  await wait(500);
  final x1pid = (x1.room!['players'] as List).firstWhere((p) => p['seat'] == x1.seat)['pid'] as String;
  final xq2 = (await postJson('/quick', {'game': 'pigeon', 'dev': '${x2.name}-tok', 'avoid': [x1pid]}))['code'] as String;
  check(x1pid.length == 16 && xq2 != xq, 'blocked player is not matched together');
  await x1.ws.close();

  // صفحة الإدارة: مقفولة بدون السر
  final adm = await hc.getUrl(Uri.parse('$base/admin?key=wrong'));
  check((await adm.close()).statusCode == 404, 'admin page needs the secret key');
  if (args.length > 1) {
    final good = await hc.getUrl(Uri.parse('$base/admin?key=${args[1]}'));
    final res = await good.close();
    final html = await res.transform(utf8.decoder).join();
    check(res.statusCode == 200 && html.contains(target.name.substring(0, 14)), 'admin page lists the reported player');
  }
  exit(exitCode);
}
