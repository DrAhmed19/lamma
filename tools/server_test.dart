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

  Future<void> connect(String base, String code) async {
    ws = await WebSocket.connect('${base.replaceFirst('http', 'ws')}/ws/$code');
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      if (m['t'] == 'room') room = m;
      if (m['t'] == 'state') state = m['s'] as Map<String, dynamic>;
      if (m['t'] == 'you') seat = m['seat'] as int;
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
  await a.ws.close();
  await b.ws.close();
  exit(exitCode);
}
