// اختبار سيرفر الإنترنت محلياً: cd server && npx wrangler dev --port 8799
// dart run tools/server_test.dart http://127.0.0.1:8799 [ADMIN_KEY]
// (لاختبار صفحة الإدارة: ADMIN_KEY=... بـ server/.dev.vars ونفسه هنا)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> wait([int ms = 250]) => Future.delayed(Duration(milliseconds: ms));

/// ينتظر لحد ما الشرط يتحقق (أو يخلص الوقت)
Future<bool> until(bool Function() cond, [int ms = 5000]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    try {
      if (cond()) return true;
    } catch (_) {}
    await wait(50);
  }
  try {
    return cond();
  } catch (_) {
    return false;
  }
}

/// يفحص الشرط وينتظره لحد [ms] (الجهاز البطيء ما يخرّب الاختبار)
Future<void> check(bool Function() cond, String what, [int ms = 5000]) async {
  final ok = await until(cond, ms);
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
  await check(() => b.room?['started'] == true, 'guest sees match started');
  await until(() => b.room?['round'] != null);
  final r1 = b.room!['round'] as int;
  for (final mv in [[a, 0], [b, 3], [a, 1], [b, 4], [a, 2]]) {
    (mv[0] as Client).send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
    await until(() => ((mv[0] as Client).state?['board'] as List?)?[mv[1] as int] != -1);
  }
  a.send({'t': 'again'});
  await wait(500);
  await check(() => (b.room!['round'] as int) == r1 + 1, 'again bumps round on the internet server');

  // رجوع للغرفة + تفاعل + بطولة
  a.send({'t': 'lobby'});
  await wait(400);
  a.send({'t': 'emo', 'i': 1});
  await wait(300);
  await check(() => b.emos.contains(1), 'emoji relayed');
  a.send({'t': 'tour', 'games': ['xo', 'connect4']});
  await wait(500);
  await check(() => b.room?['tour'] != null && b.room?['game'] == 'xo', 'tour starts');
  for (final mv in [[a, 0], [b, 3], [a, 1], [b, 4], [a, 2]]) {
    (mv[0] as Client).send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
    await until(() => ((mv[0] as Client).state?['board'] as List?)?[mv[1] as int] != -1);
  }
  await wait(500);
  await check(() => b.room?['tour']?['pts']?['0'] == 3, 'tour winner gets 3 points');
  a.send({'t': 'again'});
  await wait(500);
  await check(() => b.room?['game'] == 'connect4', 'tour moves to next game');
  await a.ws.close();
  await b.ws.close();

  // هل الغرفة موجودة؟
  Future<Map> getJson(String path) async {
    final rq = await hc.getUrl(Uri.parse('$base$path'));
    return jsonDecode(await (await rq.close()).transform(utf8.decoder).join()) as Map;
  }

  final info1 = await getJson('/info/$code'), info2 = await getJson('/info/ZZZZ');
  await check(() => info1['exists'] == true, '/info finds the room');
  await check(() => info2['exists'] == false, '/info for unknown code');

  // لعب سريع: اثنين يطلبون نفس اللعبة → نفس الغرفة وتبدي لحالها
  final q1 = (await getJson('/quick?game=xo'))['code'] as String;
  final c = Client('stranger1');
  await c.connect(base, q1);
  await wait(400);
  // «العب الآن» بالرئيسية: عدد اللي ينتظرون بكل لعبة (بدون رموز أو أسماء)
  final wt = await getJson('/waiting');
  await check(() => ((wt['games'] as Map?)?['xo'] ?? 0) >= 1, '/waiting counts the waiting player (${wt['games']})');
  await check(() => !jsonEncode(wt).contains(q1), '/waiting does not leak room codes');
  final q2 = (await getJson('/quick?game=xo'))['code'] as String;
  await check(() => q1 == q2, 'quick match pairs into the same room ($q1, $q2)');
  final d = Client('stranger2');
  await d.connect(base, q2);
  await wait(6200); // عدّ تنازلي 5 ثواني قبل البداية
  await check(() => c.room?['public'] == true, 'quick room is public');
  await check(() => c.room?['started'] == true && c.state != null, 'quick room auto-starts when full', 9000);
  await c.ws.close();
  await d.ws.close();

  // المحيبس ما يطلع باللعب السريع
  final mq = await hc.getUrl(Uri.parse('$base/quick?game=muhaibes'));
  final mqs = (await mq.close()).statusCode;
  await check(() => mqs == 400, 'muhaibes not in quick match');

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
  await check(() => ps[1].room?['cap'] == 4, 'host sets room size');
  final extra = Client('m4');
  await extra.connect(base, code2);
  await wait(400);
  await check(() => extra.seat < 0, 'room size enforced');
  ps[0].send({'t': 'cfg', 'game': 'muhaibes', 'crazy': false});
  ps[0].send({'t': 'start'});
  await wait(800);
  await until(() => ps[0].room?['started'] == true && ps[0].state != null);
  final seats = [for (final s in ps[0].room!['seats'] as List) s as int];
  Client byPlayer(int p) => ps.firstWhere((x) => x.seat == seats[p]);
  await check(() => seats.length == 4 && ps[0].state != null, 'muhaibes starts with 4');
  final hider = ps[0].state!['hider'] as int, leader = ps[0].state!['leader'] as int;
  final f = hider * 2;
  byPlayer(hider).send({'t': 'in', 'd': {'a': 'hide', 'f': f}});
  await wait(800);
  await check(() => byPlayer((hider + 2) % 4).state?['ring'] == f, 'teammate sees the ring');
  await check(() => byPlayer(leader).state?['ring'] == -1 && byPlayer((leader + 2) % 4).state?['ring'] == -1, 'other team does NOT see the ring');
  byPlayer(leader).send({'t': 'in', 'd': {'a': 'bat', 'f': f}});
  await wait(800);
  await check(() {
    final ts = byPlayer(leader).state?['ts'] as List?;
    return ts != null && ts[leader % 2] == 3;
  }, 'correct bat scores 3 (${byPlayer(leader).state?['ts']} ph=${byPlayer(leader).state?['ph']} la=${byPlayer(leader).state?['la']})');
  for (final p in [...ps, extra]) {
    await p.ws.close();
  }

  // الكمبيوتر بالغرفة: صاحب الغرفة يضيفه، والمستوى ينحفظ، والسيرفر يلعبه
  final req3 = await hc.getUrl(Uri.parse('$base/new'));
  final code3 = (jsonDecode(await (await req3.close()).transform(utf8.decoder).join()) as Map)['code'] as String;
  final solo = Client('solo');
  await solo.connect(base, code3);
  await wait(400);
  solo.send({'t': 'cfg', 'game': 'domino', 'crazy': false, 'level': 2});
  solo.send({'t': 'bot'});
  await wait(500);
  await check(() {
    final pl = solo.room?['players'] as List? ?? const [];
    return solo.room?['level'] == 2 && pl.length == 2 && pl.any((x) => x['bot'] == true && x['on'] == true);
  }, 'server: bot added, level saved');
  solo.send({'t': 'start'});
  await wait(600);
  await check(() => solo.room?['started'] == true && solo.state?['goal'] == 200, 'server: match with bot at hard level');
  final bseats = [for (final x in solo.room!['seats'] as List) x as int];
  final meB = bseats.indexOf(solo.seat);
  if (solo.state!['turn'] == meB) {
    solo.send({'t': 'in', 'd': {'a': 'play', 't': solo.state!['must'], 's': 'r'}});
    await wait(400);
  }
  await check(() {
    final st = solo.state!;
    final n = ((st['chain'] as List).length + (st['up'] as List).length + (st['dn'] as List).length) ~/ 3;
    return n >= 1 && (st['turn'] == meB || (st['hands'] as List)[1 - meB].length < 7);
  }, 'server: bot plays by itself', 6000);
  await solo.ws.close();

  // الدومينو ويا الغرباء: لاعبين بس، وتبدي لمّن يكتملون، والقطع مخفية
  final dq1 = (await getJson('/quick?game=domino'))['code'] as String;
  final e1 = Client('dom1');
  await e1.connect(base, dq1);
  await wait(400);
  final dq2 = (await getJson('/quick?game=domino'))['code'] as String;
  final e2 = Client('dom2');
  await e2.connect(base, dq2);
  await wait(6200); // عدّ تنازلي 5 ثواني قبل البداية
  await check(() => dq1 == dq2 && e1.room?['started'] == true, 'domino quick match starts with 2', 9000);
  final dh = e1.state?['hands'] as List?;
  await until(() => e1.room?['seats'] != null);
  final me1 = (e1.room!['seats'] as List).indexOf(e1.seat);
  await check(() => dh != null && (dh[1 - me1] as List).every((t) => t == -1) && (dh[me1] as List).every((t) => (t as int) >= 0), 'domino hides opponent tiles');
  await check(() => (e1.state?['pile'] as List?)?.every((t) => t == -1) == true && (e1.state?['pile'] as List).length == 14, 'domino draw pile hidden (14)');
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
  await check(() => rude.seat < 0 && rude.errs.contains('name'), 'bad name rejected');
  await rude.ws.close();

  // جولة إبلاغ: الهدف يدخل غرفة عامة، و3 أشخاص مختلفين يبلّغون عنه
  final run = DateTime.now().millisecondsSinceEpoch;
  final target = Client('target$run');
  Future<void> reportRound(String game, List<String> names) async {
    final q = (await postJson('/quick', {'game': game, 'dev': '${target.name}-tok'}))['code'] as String;
    target.seat = -1; // المقعد من الجولة اللي فاتت ما ينفع
    await target.connect(base, q);
    await until(() => target.seat >= 0);
    final rs = <Client>[];
    for (final n in names) {
      final c = Client(n);
      final cq = (await postJson('/quick', {'game': game, 'dev': '$n-tok'}))['code'] as String;
      await c.connect(base, cq);
      rs.add(c);
      await until(() => c.seat >= 0);
    }
    // كلهم لازم يكونون بنفس الغرفة ويشوفون الهدف
    await until(() => rs.every((c) => (c.room?['players'] as List?)?.any((p) => p['seat'] == target.seat) == true));
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
  await check(() => w['warn'] != null && w['code'] != null, 'first strike = warning only');
  await reportRound('reaction', ['rd$run', 're$run', 'rf$run']);
  final bn = await postJson('/quick', {'game': 'xo', 'dev': '${target.name}-tok'});
  await check(() => bn['error'] == 'banned' && (bn['until'] as num) > DateTime.now().millisecondsSinceEpoch, 'second strike = banned from quick match');
  final ok = await getJson('/new');
  final friend = Client(target.name);
  await friend.connect(base, ok['code'] as String);
  await wait(400);
  await check(() => friend.seat >= 0, 'banned player can still play with friends');
  await friend.ws.close();

  // الحظر: اللي حاظر واحد ما ينجمع وياه
  final x1 = Client('x1$run'), x2 = Client('x2$run');
  final xq = (await postJson('/quick', {'game': 'pigeon', 'dev': '${x1.name}-tok'}))['code'] as String;
  await x1.connect(base, xq);
  await wait(500);
  await until(() => x1.room?['players'] != null);
  final x1pid = (x1.room!['players'] as List).firstWhere((p) => p['seat'] == x1.seat)['pid'] as String;
  final xq2 = (await postJson('/quick', {'game': 'pigeon', 'dev': '${x2.name}-tok', 'avoid': [x1pid]}))['code'] as String;
  await check(() => x1pid.length == 16 && xq2 != xq, 'blocked player is not matched together');
  await x1.ws.close();

  // ------------------------------------------------ لعب الغرباء: عدّ تنازلي، خروج، مرة ثانية بموافقة الطرفين
  Future<(Client, Client, String)> pair(String tag) async {
    final p1 = Client('p1$tag$run'), p2 = Client('p2$tag$run');
    final q1 = (await postJson('/quick', {'game': 'xo', 'dev': '${p1.name}-tok'}))['code'] as String;
    await p1.connect(base, q1);
    await wait(400);
    final q2 = (await postJson('/quick', {'game': 'xo', 'dev': '${p2.name}-tok'}))['code'] as String;
    await p2.connect(base, q2);
    await wait(700);
    return (p1, p2, q1);
  }

  Future<void> win(Client p1, Client p2) async {
    // اللاعب 0 (أول واحد دخل) يكمل الصف الأول
    for (final mv in [[p1, 0], [p2, 3], [p1, 1], [p2, 4], [p1, 2]]) {
      (mv[0] as Client).send({'t': 'in', 'd': {'m': 'put', 'i': mv[1]}});
      await until(() => ((mv[0] as Client).state?['board'] as List?)?[mv[1] as int] != -1);
    }
    await wait(400);
  }

  // 1) عدّ تنازلي 5 ثواني قبل البداية
  var (p1, p2, room1) = await pair('a');
  await check(() => p1.room?['started'] == false && (p1.room?['autoIn'] as num? ?? 0) > 0, 'public room waits with a countdown when full');
  await check(() => p1.room?['started'] == true && p2.room?['started'] == true, 'public match starts after the countdown', 9000);

  // 2) خروج بنص الجولة = خروج كامل، والخصم يفوز ويبقى يشوف النتيجة
  p2.send({'t': 'quit'});
  p2.send({'t': 'leave'});
  await wait(800);
  await check(() => p1.state?['fin'] == true && p1.state?['win'] == 0, 'leaving mid-match: opponent wins');
  await wait(4600);
  await check(() => p1.room?['started'] == true && (p1.room?['players'] as List).length == 1, 'winner stays on the result (no auto restart)');
  p1.send({'t': 'again'});
  await wait(500);
  await check(() => p1.room?['started'] == true && p1.state?['fin'] == true, 'again alone does nothing after opponent left');

  // 3) دخول خصم ثاني: اللي بقى يدوّر خصم جديد، والغرفة القديمة ما تنعرض لأحد
  p1.send({'t': 'leave'});
  await wait(400);
  final nq1 = (await postJson('/quick', {'game': 'xo', 'dev': '${p1.name}-tok'}))['code'] as String;
  final p3 = Client('p3$run');
  final p1b = Client(p1.name);
  await p1b.connect(base, nq1);
  await wait(400);
  final nq3 = (await postJson('/quick', {'game': 'xo', 'dev': '${p3.name}-tok'}))['code'] as String;
  await p3.connect(base, nq3);
  await wait(700);
  await check(() => nq1 != room1 && nq3 == nq1 && p3.seat >= 0, 'new opponent is matched into a fresh room');
  await p1b.ws.close();
  await p3.ws.close();

  // 4) خروج بعد النتيجة، ومرة ثانية تحتاج موافقة الطرفين
  final (c1, c2, _) = await pair('b');
  await until(() => c1.room?['started'] == true && c2.state != null, 9000);
  await win(c1, c2);
  await check(() => c1.state?['fin'] == true, 'public match finished normally');
  final r0 = c1.room!['round'] as int;
  c1.send({'t': 'again'});
  await wait(500);
  await check(() => (c2.room!['votes'] as List).contains(c1.seat), 'rematch vote is shown to the other player');
  await wait(600);
  await check(() => c1.room!['round'] == r0, 'rematch waits for the other player', 0);
  c2.send({'t': 'again'});
  await wait(600);
  await check(() => c1.room!['round'] == r0 + 1 && c1.state?['fin'] == false, 'rematch starts when both agree');
  await win(c1, c2);
  c2.send({'t': 'leave'});
  await wait(600);
  await check(() => c1.room?['started'] == true && (c1.room?['players'] as List).length == 1, 'leaving after the result keeps the winner on the result (started=${c1.room?['started']} players=${(c1.room?['players'] as List?)?.length} fin=${c1.state?['fin']})');
  await c1.ws.close();

  // صفحة الإدارة: مقفولة بدون السر
  final adm = await hc.getUrl(Uri.parse('$base/admin?key=wrong'));
  final admStatus = (await adm.close()).statusCode;
  await check(() => admStatus == 404, 'admin page needs the secret key');
  if (args.length > 1) {
    final good = await hc.getUrl(Uri.parse('$base/admin?key=${args[1]}'));
    final res = await good.close();
    final html = await res.transform(utf8.decoder).join();
    await check(() => res.statusCode == 200 && html.contains(target.name.substring(0, 14)), 'admin page lists the reported player');
  }
  exit(exitCode);
}
