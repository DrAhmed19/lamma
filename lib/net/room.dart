import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../logic/game_model.dart';
import '../logic/models.dart';

/// عنوان سيرفر الغرف. ينحط بالبناء (--dart-define=SERVER=...).
/// إذا فاضي، الأونلاين ما يشتغل.
const kServer = String.fromEnvironment('SERVER', defaultValue: '');
bool get onlineAvailable => kServer.isNotEmpty;

/// اسم اللاعب (يتذكره طول ما التطبيق مفتوح)
String playerName = '';

class NetPlayer {
  const NetPlayer(this.seat, this.name, this.on);
  final int seat;
  final String name;
  final bool on;
}

/// حالة لعبة جديدة جت من السيرفر
class NetState {
  NetState(this.model, this.events, this.at);
  final GameModel model;
  final List<Map<String, dynamic>> events;

  /// وقت الوصول (ثواني) حتى ننعّم الحركة بين حالتين
  final double at;
}

enum RoomStatus { connecting, online, reconnecting, closed }

final _clock = Stopwatch()..start();
double get netNow => _clock.elapsedMicroseconds / 1e6;

/// الاتصال بغرفة. السيرفر هو اللي يدير اللعبة؛ هنا بس نعرض ونرسل الحركات.
/// يرجع يتصل تلقائياً إذا انقطع، وبنفس المقعد.
class RoomConn extends ChangeNotifier {
  RoomConn._(this.code, this.name);

  final String code;
  final String name;
  final String _token = _randomToken();

  RoomStatus status = RoomStatus.connecting;
  String? error;
  int mySeat = -1;
  int host = -1;
  List<NetPlayer> players = const [];
  String? game;
  bool crazy = false;
  bool started = false;
  int round = 0;

  /// مقاعد المشاركين بالمباراة الحالية بالترتيب (اللاعب i = seats[i])
  List<int> seats = const [];

  /// مقاعد طلعت من المباراة الحالية
  List<int> out = const [];

  /// آخر حالة للعبة من السيرفر
  NetState? state;
  final _states = StreamController<NetState>.broadcast();
  Stream<NetState> get states => _states.stream;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _ping, _retry;
  int _attempt = 0;
  bool _left = false;

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
  static Future<String> createRoom() async {
    final r = await http.get(Uri.parse('$kServer/new')).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    return (jsonDecode(r.body) as Map)['code'] as String;
  }

  static RoomConn join(String code, String name) {
    final c = RoomConn._(code.toUpperCase(), name);
    c._connect();
    return c;
  }

  void _connect() {
    if (_left) return;
    final ws = kServer.replaceFirst(RegExp('^http'), 'ws');
    try {
      final ch = WebSocketChannel.connect(Uri.parse('$ws/ws/$code'));
      _ch = ch;
      _sub = ch.stream.listen(_onData, onDone: _onDrop, onError: (_) => _onDrop());
      ch.ready.then((_) {
        _attempt = 0;
        _send({'t': 'join', 'name': name, 'token': _token});
      }).catchError((_) => _onDrop());
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 15), (_) => _send({'t': 'ping'}));
    } catch (_) {
      _onDrop();
    }
  }

  void _onDrop() {
    _sub?.cancel();
    _sub = null;
    _ch = null;
    _ping?.cancel();
    if (_left || status == RoomStatus.closed) return;
    status = RoomStatus.reconnecting;
    notifyListeners();
    _retry?.cancel();
    // نرجع نحاول بسرعة أول مرات (حتى اللي انقطع ثواني يلحق)
    final wait = [300, 800, 1500, 3000, 5000][math.min(_attempt, 4)];
    _attempt++;
    _retry = Timer(Duration(milliseconds: wait), _connect);
  }

  void _onData(dynamic raw) {
    final Map<String, dynamic> m;
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
      case 'room':
        host = m['host'] as int;
        game = m['game'] as String?;
        crazy = m['crazy'] == true;
        final wasStarted = started;
        started = m['started'] == true;
        round = m['round'] as int;
        seats = [for (final s in m['seats'] as List) s as int];
        out = [for (final s in m['out'] as List) s as int];
        players = [
          for (final p in m['players'] as List) NetPlayer(p['seat'] as int, p['name'] as String, p['on'] == true),
        ];
        if (!started && wasStarted) state = null;
      case 'state':
        try {
          final model = restoreModel(Map<String, dynamic>.from(m['s'] as Map));
          final ev = [for (final e in m['ev'] as List) Map<String, dynamic>.from(e as Map)];
          final st = NetState(model, ev, netNow);
          state = st;
          _states.add(st);
        } catch (_) {}
        return; // الحالة تتحدث كثير، ما نعيد بناء الواجهات كل مرة
      case 'err':
        error = m['m'] as String?;
        if (error == 'notfound' || error == 'full') {
          status = RoomStatus.closed;
          _left = true;
          _ch?.sink.close();
        }
    }
    notifyListeners();
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ch?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  /// حركة باللعبة (السيرفر يقرر إذا مقبولة)
  void input(Map<String, dynamic> d) => _send({'t': 'in', 'd': d});
  void again() => _send({'t': 'again'});
  void setGame(String id, bool crazy) => _send({'t': 'cfg', 'game': id, 'crazy': crazy});
  void start() => _send({'t': 'start'});
  void toLobby() => _send({'t': 'lobby'});

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
    _sub?.cancel();
    _ch?.sink.close();
  }

  @override
  void dispose() {
    _left = true;
    _close();
    _states.close();
    super.dispose();
  }

  static String _randomToken() {
    final r = math.Random.secure();
    return List.generate(20, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}
