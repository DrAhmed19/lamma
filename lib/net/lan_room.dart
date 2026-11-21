// غرفة على نفس الشبكة (بدون إنترنت): نفس منطق سيرفر الإنترنت (server/src/index.js)
// بس تشتغل داخل تطبيق صاحب الغرفة. نفس الرسائل بالضبط، فالتطبيقات والويب يتصلون بيها
// مثل ما يتصلون بالسيرفر.
//
// Dart صافي (بدون dart:io) حتى الاتصالات تنربط من برّه (lan_io.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../logic/game_model.dart';
import '../logic/models.dart';

/// اتصال لاعب واحد
abstract class LanPeer {
  int seat = -1;
  void send(String data);
  void close(int code, String reason);
}

class _Player {
  _Player(this.name, this.token);
  String name;
  final String token;
}

class LanRoom {
  LanRoom(this.code) {
    _house = Timer.periodic(const Duration(milliseconds: 500), (_) => _alarm());
  }

  final String code;
  static const maxPlayers = 4;
  static const forfeitMs = 45 * 1000;
  static const hostGraceMs = 20 * 1000;
  static const lobbyDropMs = 3 * 60 * 1000;
  static const endDelayMs = 4000;

  int host = -1;
  String? game;
  bool crazy = false;
  bool started = false;
  int round = 0;
  List<int> seats = [];
  List<int> out = [];
  final offlineSince = <int, int>{};
  final gone = <int, int>{};
  final banned = <String>[];
  int endAt = 0;
  final players = <int, _Player>{};
  final peers = <LanPeer>[];

  GameModel? g;
  Timer? _tick, _house;
  final _rnd = math.Random();

  int get _now => DateTime.now().millisecondsSinceEpoch;
  int get playerCount => players.length;

  void dispose() {
    _house?.cancel();
    _stopLoop();
    for (final p in List.of(peers)) {
      try {
        p.close(1001, 'bye');
      } catch (_) {}
    }
    peers.clear();
  }

  // ------------------------------------------------------------ أدوات

  Set<int> _online() => {for (final p in peers) if (p.seat >= 0) p.seat};

  void _send(LanPeer p, Object m) {
    try {
      p.send(m is String ? m : jsonEncode(m));
    } catch (_) {}
  }

  void _broadcast(Object m) {
    final s = m is String ? m : jsonEncode(m);
    for (final p in List.of(peers)) {
      if (p.seat >= 0) _send(p, s);
    }
  }

  void _notice(String m, int seat) =>
      _broadcast({'t': 'notice', 'm': m, 'seat': seat, 'name': players[seat]?.name ?? 'لاعب'});

  Map<String, dynamic> _roomState() {
    final on = _online();
    final list = players.entries.map((e) => {'seat': e.key, 'name': e.value.name, 'on': on.contains(e.key)}).toList()
      ..sort((a, b) => (a['seat'] as int).compareTo(b['seat'] as int));
    return {
      't': 'room',
      'code': code,
      'host': host,
      'game': game,
      'crazy': crazy,
      'started': started,
      'round': round,
      'seats': seats,
      'out': out,
      'ending': endAt != 0,
      'players': list,
    };
  }

  void _sendRoom() => _broadcast(_roomState());

  /// صاحب الغرفة يبقى صاحبها إذا انقطع شوية. إذا طوّل أو طلع، أقدم واحد متصل ياخذ مكانه.
  bool _fixHost({bool force = false}) {
    final on = _online();
    final exists = players.containsKey(host);
    final away = gone[host];
    final keep = exists && !force && (on.contains(host) || (away != null && _now - away < hostGraceMs));
    if (keep) return false;
    final candidates = on.where((s) => players.containsKey(s) && s != host).toList()..sort();
    final next = candidates.isNotEmpty ? candidates.first : (exists && on.contains(host) ? host : -1);
    if (next == host) return false;
    if (next < 0 && exists) return false;
    host = next;
    if (next >= 0) _notice('host', next);
    return true;
  }

  int _playerOf(int seat) => seats.indexOf(seat);

  // ------------------------------------------------------------ اللعبة

  String _stateMsg([List<Map<String, dynamic>>? ev]) =>
      jsonEncode({'t': 'state', 's': g!.toJson(), 'ev': ev ?? g!.drainEvents()});

  void _flush() {
    if (g != null) _broadcast(_stateMsg());
  }

  void _startLoop() {
    if (_tick != null || g == null) return;
    final hz = g!.tickHz;
    if (hz <= 0) return;
    final dt = 1 / hz;
    final watch = Stopwatch()..start();
    var last = 0;
    var acc = 0.0;
    _tick = Timer.periodic(Duration(microseconds: (1e6 / hz).round()), (_) {
      final game = g;
      if (game == null) return _stopLoop();
      final now = watch.elapsedMilliseconds;
      acc += math.min(0.25, (now - last) / 1000);
      last = now;
      var steps = 0;
      while (acc >= dt && steps < 8) {
        game.advance(dt);
        acc -= dt;
        steps++;
      }
      if (steps > 0) _broadcast(_stateMsg());
    });
  }

  void _stopLoop() {
    _tick?.cancel();
    _tick = null;
  }

  /// التكّات تمشي بس إذا أكو واحد مشارك متصل
  void _syncLoop() {
    if (!started || g == null) return _stopLoop();
    final on = _online();
    final anyone = seats.any((s) => on.contains(s) && !out.contains(s));
    if (anyone && endAt == 0) {
      _startLoop();
    } else {
      _stopLoop();
    }
  }

  void _playerGone(int seat, bool forever) {
    final p = _playerOf(seat);
    if (!started || p < 0 || out.contains(seat) || g == null) return;
    if (forever) {
      out.add(seat);
      offlineSince.remove(seat);
      g!.forfeit(p);
    } else {
      offlineSince[seat] = _now;
      g!.connection(p, false);
    }
    _flush();
  }

  void _checkMatch() {
    if (!started || endAt != 0) return;
    final left = seats.where((s) => !out.contains(s) && players.containsKey(s));
    if (left.length < 2) {
      endAt = _now + endDelayMs;
      _stopLoop();
    }
  }

  void _endMatch() {
    started = false;
    out = [];
    offlineSince.clear();
    endAt = 0;
    _stopLoop();
    g = null;
    _fixHost();
    _sendRoom();
  }

  void _removePlayer(int seat, {bool kicked = false}) {
    final pl = players[seat];
    if (pl == null) return;
    if (started && _playerOf(seat) >= 0) _playerGone(seat, true);
    _notice(kicked ? 'kicked' : 'left', seat);
    if (kicked) {
      banned.add(pl.token);
      for (final p in List.of(peers)) {
        if (p.seat == seat) {
          _send(p, {'t': 'err', 'm': 'kicked'});
          p.seat = -1;
          try {
            p.close(4003, 'kicked');
          } catch (_) {}
        }
      }
    }
    players.remove(seat);
    gone.remove(seat);
    offlineSince.remove(seat);
    if (host == seat) _fixHost(force: true);
    _checkMatch();
  }

  // ------------------------------------------------------------ الاتصالات

  void connect(LanPeer p) => peers.add(p);

  void message(LanPeer peer, String raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (msg['t'] == 'ping') return _send(peer, {'t': 'pong'});
    if (msg['t'] == 'join') return _onJoin(peer, msg);
    final seat = peer.seat;
    if (seat < 0 || !players.containsKey(seat)) return;

    final isHost = seat == host;
    final p = _playerOf(seat);
    final playing = started && p >= 0 && !out.contains(seat);

    switch (msg['t']) {
      case 'cfg':
        if (!isHost || started) return;
        final gm = msg['game'];
        game = gm is String ? (gm.length > 20 ? gm.substring(0, 20) : gm) : null;
        crazy = msg['crazy'] == true;
        _sendRoom();

      case 'start':
        if (!isHost || started || game == null) return;
        if (!onlineGames.contains(game)) return _send(peer, {'t': 'err', 'm': 'unsupported'});
        final s = _online().where(players.containsKey).toList()..sort();
        if (s.length < 2) return _send(peer, {'t': 'err', 'm': 'few'});
        started = true;
        round += 1;
        seats = s;
        out = [];
        offlineSince.clear();
        endAt = 0;
        _stopLoop();
        g = createModel(game!, players: s.length, crazy: crazy, seed: _rnd.nextInt(1 << 31));
        _sendRoom();
        _flush();
        _syncLoop();

      case 'in':
        final d = msg['d'];
        if (!playing || endAt != 0 || d is! Map || g == null) return;
        g!.input(p, Map<String, dynamic>.from(d));
        if (g!.tickHz <= 0) _flush();

      case 'again':
        if (!started || endAt != 0 || !playing || g == null || !g!.over) return;
        final on = _online();
        final keep = seats.where((s) => players.containsKey(s) && (!out.contains(s) || on.contains(s))).toList();
        final changed = keep.length != seats.length || out.any(keep.contains);
        if (changed && keep.length >= 2) {
          seats = keep;
          out = [];
          offlineSince.clear();
          g = createModel(game!, players: keep.length, crazy: crazy, seed: _rnd.nextInt(1 << 31));
        } else {
          g!.again();
        }
        round += 1;
        _sendRoom();
        _flush();
        _syncLoop();

      case 'lobby':
        if (!isHost || !started) return;
        _endMatch();

      case 'kick':
        final s = (msg['seat'] as num?)?.toInt() ?? -1;
        if (!isHost || s == seat || !players.containsKey(s)) return;
        _removePlayer(s, kicked: true);
        _sendRoom();
        _syncLoop();

      case 'host':
        final s = (msg['seat'] as num?)?.toInt() ?? -1;
        if (!isHost || s == seat || !_online().contains(s) || !players.containsKey(s)) return;
        host = s;
        _notice('host', s);
        _sendRoom();

      case 'quit':
        if (!playing) return;
        _playerGone(seat, true);
        _notice('quit', seat);
        _checkMatch();
        _sendRoom();
        _syncLoop();

      case 'leave':
        _removePlayer(seat);
        peer.seat = -1;
        _sendRoom();
        try {
          peer.close(1000, 'bye');
        } catch (_) {}
        _syncLoop();
    }
  }

  void _onJoin(LanPeer peer, Map<String, dynamic> msg) {
    var name = '${msg['name'] ?? ''}'.trim();
    if (name.length > 14) name = name.substring(0, 14);
    if (name.isEmpty) name = 'لاعب';
    var token = '${msg['token'] ?? ''}';
    if (token.length > 40) token = token.substring(0, 40);
    if (token.isNotEmpty && banned.contains(token)) return _send(peer, {'t': 'err', 'm': 'kicked'});
    var seat = -1;
    players.forEach((s, p) {
      if (token.isNotEmpty && p.token == token) seat = s;
    });
    if (seat >= 0) {
      // رجع: نسد أي اتصال قديم إله
      for (final other in List.of(peers)) {
        if (!identical(other, peer) && other.seat == seat) {
          other.seat = -1;
          try {
            other.close(4000, 'replaced');
          } catch (_) {}
        }
      }
      players[seat]!.name = name;
    } else {
      for (var s = 0; s < maxPlayers && seat < 0; s++) {
        if (!players.containsKey(s)) seat = s;
      }
      if (seat < 0) return _send(peer, {'t': 'err', 'm': 'full'});
      players[seat] = _Player(name, token);
      if (host >= 0) _notice('joined', seat);
    }
    gone.remove(seat);
    peer.seat = seat;
    if (host < 0 || !players.containsKey(host)) host = seat;
    _fixHost();

    final p = _playerOf(seat);
    if (started && p >= 0 && offlineSince.containsKey(seat)) {
      offlineSince.remove(seat);
      g?.connection(p, true);
    }
    _send(peer, {'t': 'you', 'seat': seat});
    _sendRoom();
    if (started && g != null) _send(peer, _stateMsg(const []));
    _syncLoop();
  }

  void closed(LanPeer peer) {
    final seat = peer.seat;
    peer.seat = -1;
    peers.remove(peer);
    if (seat < 0 || !players.containsKey(seat)) return;
    if (!_online().contains(seat)) {
      gone[seat] = _now;
      _playerGone(seat, false);
    }
    _sendRoom();
    _syncLoop();
  }

  // ------------------------------------------------------------ المواعيد

  void _alarm() {
    final now = _now;
    var changed = false;
    for (final e in offlineSince.entries.toList()) {
      if (now - e.value >= forfeitMs) {
        _playerGone(e.key, true);
        _checkMatch();
        changed = true;
      }
    }
    if (endAt != 0 && now >= endAt) {
      _endMatch();
      changed = true;
    }
    if (_fixHost()) changed = true;
    if (!started) {
      final on = _online();
      for (final e in gone.entries.toList()) {
        if (now - e.value >= lobbyDropMs && !on.contains(e.key)) {
          players.remove(e.key);
          gone.remove(e.key);
          changed = true;
        }
      }
      if (!players.containsKey(host) && _fixHost(force: true)) changed = true;
    }
    if (changed) {
      _sendRoom();
      _syncLoop();
    }
  }
}
