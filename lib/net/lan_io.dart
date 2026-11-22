// اللعب على نفس الشبكة بدون إنترنت (أندرويد/حاسبة): تلفون صاحب الغرفة يصير هو السيرفر.
//  - التطبيقات تتصل بيه مباشرة (تلگاه بالبحث بالشبكة أو بالعنوان).
//  - الآيفون والمتصفحات يفتحون عنوانه بالمتصفح: هو يقدّم إلهم نسخة الويب من داخله
//    (assets/lan/web.zip، تنبني بالـ CI) وبعدها يتصلون بيه.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lan_room.dart';

const lanPort = 8787;
final bool lanHostSupported = !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS);

class LanFound {
  const LanFound(this.server, this.code, this.hostName, this.players, this.started);
  final String server, code, hostName;
  final int players;
  final bool started;
}

class _WsPeer extends LanPeer {
  _WsPeer(this.ws);
  final WebSocket ws;
  @override
  void send(String data) => ws.add(data);
  @override
  void close(int code, String reason) => ws.close(code, reason);
}

class LanHost {
  LanHost._(this._http, this.room, this.ips);

  final HttpServer _http;
  final LanRoom room;

  /// عناوين التلفون بالشبكة (واي فاي أو هوتسبوت)
  final List<String> ips;
  Map<String, ArchiveFile>? _web;
  bool _webLoaded = false;

  static LanHost? current;

  int get port => _http.port;
  String get code => room.code;

  /// السيرفر بالنسبة لتطبيق صاحب الغرفة نفسه
  String get selfServer => 'http://127.0.0.1:$port';

  /// العنوان اللي يفتحه الباقين (QR)
  String? get joinUrl => ips.isEmpty ? null : urlFor(ips.first);
  String urlFor(String ip) => 'http://$ip:$port/?room=$code&lan=1';

  static Future<LanHost> start() async {
    await current?.stop();
    HttpServer http;
    try {
      http = await HttpServer.bind(InternetAddress.anyIPv4, lanPort, shared: true);
    } catch (_) {
      http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final r = math.Random.secure();
    final code = List.generate(4, (_) => letters[r.nextInt(letters.length)]).join();
    final host = LanHost._(http, LanRoom(code), await localIps());
    http.listen(host._handle, onError: (_) {});
    current = host;
    return host;
  }

  Future<void> stop() async {
    if (identical(current, this)) current = null;
    room.dispose();
    await _http.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    final path = req.uri.path;
    try {
      if (path.startsWith('/ws/') && WebSocketTransformer.isUpgradeRequest(req)) {
        final want = path.substring(4).toUpperCase();
        final ws = await WebSocketTransformer.upgrade(req);
        ws.pingInterval = const Duration(seconds: 10);
        final peer = _WsPeer(ws);
        if (want != room.code) {
          peer.send(jsonEncode({'t': 'err', 'm': 'notfound'}));
          await ws.close(4004, 'notfound');
          return;
        }
        room.connect(peer);
        ws.listen(
          (d) {
            if (d is String) room.message(peer, d);
          },
          onDone: () => room.closed(peer),
          onError: (_) => room.closed(peer),
          cancelOnError: true,
        );
        return;
      }
      if (path == '/info') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'app': 'lamma',
          'code': room.code,
          'players': room.playerCount,
          'host': room.players[room.host]?.name ?? '',
          'started': room.started,
        }));
        await res.close();
        return;
      }
      if (path == '/new') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'code': room.code}));
        await res.close();
        return;
      }
      await _static(req, path);
    } catch (_) {
      try {
        res.statusCode = 500;
        await res.close();
      } catch (_) {}
    }
  }

  /// يقدّم نسخة الويب للي يفتح العنوان بالمتصفح
  Future<void> _static(HttpRequest req, String path) async {
    final res = req.response;
    if (!_webLoaded) {
      _webLoaded = true;
      try {
        final data = await rootBundle.load('assets/lan/web.zip');
        final zip = ZipDecoder().decodeBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        _web = {for (final f in zip.files) if (f.isFile) f.name: f};
      } catch (_) {
        _web = null;
      }
    }
    var name = path == '/' || path.isEmpty ? 'index.html' : path.substring(1);
    final web = _web;
    if (web == null) {
      res.headers.contentType = ContentType.html;
      res.write('<html dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
          '<body style="font-family:sans-serif;background:#090C18;color:#fff;padding:24px">'
          '<h2>لمّة</h2><p>نسخة الويب غير متوفرة في هذا التطبيق. ثبّت تطبيق لمّة على أندرويد وانضم إلى الغرفة <b>${room.code}</b>.</p></body></html>');
      await res.close();
      return;
    }
    var f = web[name];
    // الأصوات والخطوط ما ننسخها بالـ zip (تكبّر التطبيق): نقدّمها من ملفات التطبيق نفسه
    if (f == null && name.startsWith('assets/assets/') && !name.contains('..')) {
      try {
        final data = await rootBundle.load(Uri.decodeComponent(name.substring('assets/'.length)));
        res.headers.set('Content-Type', _mime(name));
        res.headers.set('Cache-Control', 'max-age=3600');
        res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        await res.close();
        return;
      } catch (_) {}
    }
    if (f == null && !name.contains('.')) f = web['index.html'];
    if (f == null) {
      res.statusCode = 404;
      await res.close();
      return;
    }
    res.headers.set('Content-Type', _mime(name));
    res.headers.set('Cache-Control', name == 'index.html' ? 'no-cache' : 'max-age=3600');
    res.add(f.content);
    await res.close();
  }

  static String _mime(String n) {
    final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1).toLowerCase() : '';
    return switch (ext) {
      'html' => 'text/html; charset=utf-8',
      'js' || 'mjs' => 'text/javascript; charset=utf-8',
      'json' => 'application/json',
      'wasm' => 'application/wasm',
      'css' => 'text/css',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'svg' => 'image/svg+xml',
      'ico' => 'image/x-icon',
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      'woff2' => 'font/woff2',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      _ => 'application/octet-stream',
    };
  }
}

bool _private(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.contains(null)) return false;
  return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && p[1]! >= 16 && p[1]! <= 31);
}

/// عناوين هالجهاز بالشبكات المحلية
Future<List<String>> localIps() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final ips = <String>[];
    for (final i in list) {
      for (final a in i.addresses) {
        if (_private(a.address)) ips.add(a.address);
      }
    }
    // الواي فاي أول (wlan)، بعده الهوتسبوت
    ips.sort((a, b) => (a.startsWith('192.168.') ? 0 : 1) - (b.startsWith('192.168.') ? 0 : 1));
    return ips;
  } catch (_) {
    return const [];
  }
}

/// يدوّر على غرف لمّة بنفس الشبكة (يجرّب كل عنوان بالشبكة على منفذ لمّة)
Future<List<LanFound>> scanLan() async {
  final mine = await localIps();
  final prefixes = {for (final ip in mine) ip.substring(0, ip.lastIndexOf('.'))};
  final found = <LanFound>[];
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 900);
  Future<void> probe(String ip) async {
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:$lanPort/info')).timeout(const Duration(milliseconds: 1500));
      final res = await req.close().timeout(const Duration(milliseconds: 1500));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(milliseconds: 1500));
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['app'] != 'lamma') return;
      found.add(LanFound('http://$ip:$lanPort', j['code'] as String, j['host'] as String? ?? '', (j['players'] as num?)?.toInt() ?? 0,
          j['started'] == true));
    } catch (_) {}
  }

  final jobs = <Future<void>>[];
  for (final pre in prefixes) {
    for (var i = 1; i < 255; i++) {
      jobs.add(probe('$pre.$i'));
    }
  }
  await Future.wait(jobs);
  client.close(force: true);
  return found;
}
