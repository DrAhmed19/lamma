import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/perf.dart';
import '../core/profile.dart';
import '../logic/game_model.dart';
import '../logic/models.dart';

/// عنوان سيرفر الغرف. ينحط بالبناء (--dart-define=SERVER=...).
/// إذا فاضي، الأونلاين ما يشتغل.
const _kServerDefine = String.fromEnvironment('SERVER', defaultValue: '');

/// الويب اللي ينفتح من تلفون صاحب غرفة محلية (?lan=1): السيرفر هو نفس العنوان
final String? lanOrigin = kIsWeb && Uri.base.queryParameters['lan'] == '1' ? Uri.base.origin : null;
String get kServer => lanOrigin ?? _kServerDefine;
bool get onlineAvailable => kServer.isNotEmpty;

/// رابط نسخة الويب (حتى الدعوة من التطبيق تفتح للآيفون هم)
const kWebUrl = String.fromEnvironment('WEB', defaultValue: 'https://lamma-dk0.pages.dev');

/// اسم اللاعب (يتذكره طول ما التطبيق مفتوح)
String playerName = '';

class NetPlayer {
  const NetPlayer(this.seat, this.name, this.on, [this.avatar = '']);
  final int seat;
  final String name;
  final bool on;
  final String avatar;
}

/// بطولة: ألعاب ورا بعض، والنقاط لكل مقعد
class NetTour {
  NetTour(this.games, this.idx, this.pts, this.done);
  final List<String> games;
  final int idx;
  final Map<int, int> pts;
  final bool done;

  /// الترتيب: أكثر نقاط أول
  List<MapEntry<int, int>> get ranking => pts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// تفاعل سريع من لاعب (رقم من [kReactions])
class NetEmo {
  const NetEmo(this.seat, this.i);
  final int seat, i;
}

/// التفاعلات السريعة (نفس الترتيب بالسيرفر: يرسل رقمها بس)
const kReactions = ['👏', '😂', '😮', '😡', '❤️', '🔥', '👍', '😢', 'أحسنت!', 'هيا!', 'مرة أخرى؟', 'حظًا موفقًا'];

/// حالة لعبة جديدة جت من السيرفر
class NetState {
  NetState(this.model, this.events, this.at);
  final GameModel model;
  final List<Map<String, dynamic>> events;

  /// وقت الوصول (ثواني) حتى ننعّم الحركة بين حالتين
  final double at;
}

/// تنبيه من الغرفة: دخل، طلع، انطرد، صار صاحب الغرفة...
class NetNotice {
  const NetNotice(this.kind, this.seat, this.name);
  final String kind;
  final int seat;
  final String name;
}

enum RoomStatus { connecting, online, reconnecting, closed }

final _clock = Stopwatch()..start();
/// آخر سبب مشكلة اتصال (يظهر صغير بشاشة "جارٍ الاتصال" حتى نعرف شنو السبب بالآيفون)
String netDebug = '';

double get netNow => _clock.elapsedMicroseconds / 1e6;

/// الاتصال بغرفة. السيرفر هو اللي يدير اللعبة؛ هنا بس نعرض ونرسل الحركات.
/// يرجع يتصل تلقائياً إذا انقطع، وبنفس المقعد.
class RoomConn extends ChangeNotifier {
  RoomConn._(this.code, this.name, this.server);

  final String code;
  final String name;

  /// عنوان السيرفر لهالغرفة (الإنترنت، أو تلفون صاحب الغرفة بنفس الشبكة)
  final String server;
  bool get isLan => server != _kServerDefine || lanOrigin != null;
  // رقم الجهاز ثابت (محفوظ)، حتى إذا رجع لنفس الغرفة (بالرابط أو بعد ما سكّر التطبيق)
  // يرجع لنفس مكانه وإدارته، مو يدخل كلاعب ثاني بنفس الاسم
  final String _token = Profile.I.deviceId;

  /// رمز الغرفة اللي الجهاز داخلها هسة (null = ماكو)
  static String? activeCode;

  RoomStatus status = RoomStatus.connecting;
  String? error;
  int mySeat = -1;
  int host = -1;
  List<NetPlayer> players = const [];
  String? game;
  bool crazy = false;
  bool started = false;

  /// غرفة عامة (لعب سريع ويا ناس ثانين): ماكو صاحب غرفة يتحكم، واللعب يبدي لحاله
  bool isPublic = false;

  /// الغرف العامة: متى تبدي (بساعة هذا الجهاز)
  DateTime? autoAt;

  NetTour? tour;

  final _emos = StreamController<NetEmo>.broadcast();
  Stream<NetEmo> get emos => _emos.stream;
  int round = 0;

  /// مقاعد المشاركين بالمباراة الحالية بالترتيب (اللاعب i = seats[i])
  List<int> seats = const [];

  /// مقاعد طلعت من المباراة الحالية
  List<int> out = const [];

  /// المباراة خلصت لأن طلع لاعب، وهسه نرجع للغرفة
  bool ending = false;

  final _notices = StreamController<NetNotice>.broadcast();
  Stream<NetNotice> get notices => _notices.stream;

  /// آخر حالة للعبة من السيرفر
  NetState? state;
  final _states = StreamController<NetState>.broadcast();
  Stream<NetState> get states => _states.stream;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _ping, _retry, _watch;
  int _attempt = 0;
  bool _left = false;

  /// آخر مرة وصلنا شي من السيرفر (حتى نكشف الاتصال الميت)
  DateTime _lastRx = DateTime.now();

  /// رسائل مهمة انرسلت والاتصال مقطوع: تنرسل أول ما نرجع
  final List<Map<String, dynamic>> _pending = [];

  bool get isHost => mySeat >= 0 && mySeat == host;

  /// رقمي باللعبة (-1 = مو مشارك بهالمباراة)
  int get me => seats.indexOf(mySeat);
  bool get playing => started && me >= 0 && !out.contains(mySeat);

  String nameOfSeat(int seat) {
    for (final p in players) {
      if (p.seat == seat) return p.name;
    }
    return 'لاعب';
  }

  bool seatOn(int seat) => players.any((p) => p.seat == seat && p.on);
  String nameOf(int player) => player >= 0 && player < seats.length ? nameOfSeat(seats[player]) : 'لاعب';
  bool isOn(int player) =>
      player >= 0 && player < seats.length && seatOn(seats[player]) && !out.contains(seats[player]);

  /// يسوّي غرفة جديدة ويرجع كودها
  /// هل أكو غرفة بهالكود على سيرفر الإنترنت؟ null = ما گدرنا نوصل للسيرفر
  static Future<bool?> roomExists(String code) async {
    if (kServer.isEmpty) return null;
    try {
      final r = await http.get(Uri.parse('$kServer/info/${code.toUpperCase()}')).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      return (jsonDecode(r.body) as Map)['exists'] == true;
    } catch (_) {
      return null;
    }
  }

  /// لعب سريع: السيرفر يلگي غرفة عامة تنتظر بهاللعبة أو يسوّي وحدة
  static Future<String> quickRoom(String game) async {
    final r = await http.get(Uri.parse('$kServer/quick?game=$game')).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    return (jsonDecode(r.body) as Map)['code'] as String;
  }

  static Future<String> createRoom({String? server}) async {
    final r = await http.get(Uri.parse('${server ?? kServer}/new')).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    return (jsonDecode(r.body) as Map)['code'] as String;
  }

  static RoomConn join(String code, String name, {String? server}) {
    final c = RoomConn._(code.toUpperCase(), name, server ?? kServer);
    activeCode = c.code;
    c._connect();
    return c;
  }

  void _connect() {
    if (_left) return;
    _retry?.cancel();
    final ws = server.replaceFirst(RegExp('^http'), 'ws');
    try {
      final ch = WebSocketChannel.connect(Uri.parse('$ws/ws/$code'));
      _ch = ch;
      _sub = ch.stream.listen(
        (d) {
          if (identical(ch, _ch)) _onData(d);
        },
        onDone: () {
          netDebug = 'closed ${ch.closeCode ?? ''} ${ch.closeReason ?? ''}'.trim();
          // نفس الجهاز دخل من مكان ثاني وأخذ المقعد: هذا الاتصال القديم يسكت وما يرجع يحاول
          if (ch.closeCode == 4000 && identical(ch, _ch)) {
            _close();
            notifyListeners();
            return;
          }
          _onDrop(ch);
        },
        onError: (e) {
          netDebug = 'error: ${e.toString().split('\n').first}';
          _onDrop(ch);
        },
      );
      ch.ready.timeout(const Duration(seconds: 8)).then((_) {
        if (!identical(ch, _ch)) return;
        _attempt = 0;
        _lastRx = DateTime.now();
        _send({'t': 'join', 'name': name, 'token': _token, 'avatar': Profile.I.avatar});
      }).catchError((e) {
        netDebug = 'ws: ${e.toString().split('\n').first}';
        _onDrop(ch);
      });
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 8), (_) => _send({'t': 'ping'}));
      // اتصال ميت (النت تبدّل، التلفون نام...): إذا ماكو شي وصل 20 ثانية نرجع نتصل
      _watch?.cancel();
      _watch = Timer.periodic(const Duration(seconds: 4), (_) {
        if (identical(ch, _ch) && DateTime.now().difference(_lastRx) > const Duration(seconds: 20)) _onDrop(ch);
      });
    } catch (e) {
      netDebug = 'connect: ${e.toString().split('\n').first}';
      _onDrop(null);
    }
  }

  void _onDrop(WebSocketChannel? from) {
    if (from != null && !identical(from, _ch)) return; // اتصال قديم
    final old = _ch;
    _sub?.cancel();
    _sub = null;
    _ch = null;
    _ping?.cancel();
    _watch?.cancel();
    try {
      old?.sink.close();
    } catch (_) {}
    if (_left || status == RoomStatus.closed) return;
    status = RoomStatus.reconnecting;
    notifyListeners();
    _retry?.cancel();
    // نرجع نحاول بسرعة أول مرات (حتى اللي انقطع ثواني يلحق)
    final wait = [200, 600, 1200, 2500, 4000][math.min(_attempt, 4)];
    _attempt++;
    _retry = Timer(Duration(milliseconds: wait), _connect);
  }

  /// التطبيق رجع للواجهة (من الواتساب مثلاً): إذا الاتصال مشكوك بيه نرجع نتصل فوراً
  void wake() {
    if (_left || status == RoomStatus.closed) return;
    final stale = DateTime.now().difference(_lastRx) > const Duration(seconds: 6);
    if (_ch == null || status != RoomStatus.online || stale) {
      _attempt = 0;
      if (_ch != null) {
        _onDrop(_ch);
      } else {
        _connect();
      }
    } else {
      _send({'t': 'ping'});
    }
  }

  void _onData(dynamic raw) {
    final Map<String, dynamic> m;
    _lastRx = DateTime.now();
    netMsgs++;
    if (raw is String) netBytes += raw.length;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'you':
        mySeat = m['seat'] as int;
        status = RoomStatus.online;
        error = null;
        // اللي انرسل والاتصال مقطوع
        final q = List.of(_pending);
        _pending.clear();
        for (final x in q) {
          _send(x);
        }
      case 'room':
        isPublic = m['public'] == true;
        final ai = (m['autoIn'] as num?)?.toInt() ?? 0;
        autoAt = ai > 0 ? DateTime.now().add(Duration(milliseconds: ai)) : null;
        final t = m['tour'];
        tour = t is Map
            ? NetTour(
                [for (final g in t['games'] as List) g as String],
                (t['idx'] as num).toInt(),
                {for (final e in (t['pts'] as Map).entries) int.parse('${e.key}'): (e.value as num).toInt()},
                t['done'] == true,
              )
            : null;
        host = m['host'] as int;
        game = m['game'] as String?;
        crazy = m['crazy'] == true;
        final wasStarted = started;
        started = m['started'] == true;
        round = m['round'] as int;
        seats = [for (final s in m['seats'] as List) s as int];
        out = [for (final s in m['out'] as List) s as int];
        ending = m['ending'] == true;
        players = [
          for (final p in m['players'] as List)
            NetPlayer(p['seat'] as int, p['name'] as String, p['on'] == true, p['avatar'] as String? ?? ''),
        ];
        if (!started && wasStarted) state = null;
      case 'state':
        try {
          final model = restoreModel(Map<String, dynamic>.from(m['s'] as Map));
          final ev = [for (final e in m['ev'] as List) Map<String, dynamic>.from(e as Map)];
          final st = NetState(model, ev, netNow);
          state = st;
          _states.add(st);
          netDebug = '';
        } catch (e) {
          netDebug = 'state: ${e.toString().split('\n').first}';
        }
        return; // الحالة تتحدث كثير، ما نعيد بناء الواجهات كل مرة
      case 'emo':
        _emos.add(NetEmo((m['seat'] as num).toInt(), (m['i'] as num).toInt()));
        return;
      case 'notice':
        _notices.add(NetNotice(m['m'] as String, (m['seat'] as num?)?.toInt() ?? -1, m['name'] as String? ?? 'لاعب'));
        return;
      case 'err':
        error = m['m'] as String?;
        if (error == 'notfound' || error == 'full' || error == 'kicked') {
          status = RoomStatus.closed;
          _left = true;
          _ch?.sink.close();
        }
    }
    notifyListeners();
  }

  static const _important = {'cfg', 'start', 'again', 'lobby', 'kick', 'host', 'quit', 'leave'};

  void _send(Map<String, dynamic> m) {
    final ch = _ch;
    final ready = ch != null && (status == RoomStatus.online || m['t'] == 'join' || m['t'] == 'ping');
    if (!ready) {
      if (_important.contains(m['t']) && !_pending.any((x) => x['t'] == m['t'])) _pending.add(m);
      return;
    }
    try {
      ch.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  /// حركة باللعبة (السيرفر يقرر إذا مقبولة)
  void input(Map<String, dynamic> d) => _send({'t': 'in', 'd': d});
  void again() => _send({'t': 'again'});
  void setGame(String id, bool crazy) => _send({'t': 'cfg', 'game': id, 'crazy': crazy});
  void start() => _send({'t': 'start'});
  void toLobby() => _send({'t': 'lobby'});

  /// صاحب الغرفة: يطرد لاعب، أو يسلّمه الغرفة
  void kick(int seat) => _send({'t': 'kick', 'seat': seat});

  /// بطولة بهالألعاب (صاحب الغرفة)
  void startTour(List<String> games) => _send({'t': 'tour', 'games': games});

  /// تفاعل سريع
  void emo(int i) => _send({'t': 'emo', 'i': i});

  /// المقعد → الصورة الرمزية
  String avatarOfSeat(int seat) {
    for (final p in players) {
      if (p.seat == seat) return p.avatar;
    }
    return '';
  }
  void makeHost(int seat) => _send({'t': 'host', 'seat': seat});

  bool get hostOn => seatOn(host);

  /// طلع من المباراة (الباقين يكملون)
  void quit() => _send({'t': 'quit'});

  void leave() {
    _left = true;
    _send({'t': 'leave'});
    _close();
  }

  void _close() {
    status = RoomStatus.closed;
    _retry?.cancel();
    _ping?.cancel();
    _watch?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
  }

  @override
  void dispose() {
    if (activeCode == code) activeCode = null;
    _left = true;
    _close();
    _states.close();
    _emos.close();
    _notices.close();
    super.dispose();
  }

}
