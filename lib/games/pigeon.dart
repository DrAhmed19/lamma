import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// الحمامة: كل لاعب عنده مصيادة بزاويته، يسحب ويعوف حتى يرمي حجارة على الحمامة.
/// عادي: حمامة وحدة وأول واحد يوصل 10.
/// مجنون: دقيقة وحدة، ذهبية وغراب وأسراب وصناديق قوى وكومبو.
class PigeonGame extends StatefulWidget {
  const PigeonGame({super.key, required this.players, this.crazy = false});
  final int players;
  final bool crazy;

  @override
  State<PigeonGame> createState() => _PigeonState();
}

enum BirdKind { pigeon, gold, crow }

enum PowerKind { fire, triple, freeze }

class _Bird {
  _Bird(this.kind, this.pos, this.vel, this.target, this.seed, {this.small = false});
  final BirdKind kind;
  final bool small;
  Offset pos, vel, target;
  final double seed;
  double flap = 0;
  double heading = 0;
  double retargetAt = 0;
  double leaveAt = double.infinity;
  double glideUntil = 0;
  double nextGlideAt = 0;
  bool leaving = false;

  /// يعبر الشاشة بخط وما يلف (السرب)
  bool passer = false;
  bool hit = false;
  double hitAt = 0;
  double altAtHit = 0;
  double spin = 0;
}

class _Stone {
  _Stone(this.pos, this.vel, this.owner, this.range, this.group, {this.fire = false});
  Offset pos, vel;
  final int owner;
  final double range;
  final int group;
  final bool fire;
  double dist = 0;
  bool dead = false;
  bool hitSomething = false;
  final hits = <_Bird>{};
}

class _Crate {
  _Crate(this.pos, this.vel, this.kind, this.born);
  Offset pos, vel;
  final PowerKind kind;
  final double born;
  bool dead = false;
}

/// ريش وغبار وشرار
class _Bit {
  _Bit(this.pos, this.vel, this.color, this.life, this.size, this.rot, this.spin, {this.round = false});
  Offset pos, vel;
  final Color color;
  final double life, size, spin;
  final bool round;
  double rot;
  double age = 0;
}

/// كتابة تطلع فوق مكان الضربة (+1، كومبو!، تجميد!)
class _Pop {
  _Pop(this.pos, this.text, this.color, this.flip, this.born, {this.big = false});
  final Offset pos;
  final String text;
  final Color color;
  final bool flip;
  final double born;
  final bool big;
}

class _Seat {
  const _Seat(this.anchor, this.zone, this.flip);
  final Offset anchor;
  final Rect zone;
  final bool flip;
  Offset get facing => flip ? const Offset(0, 1) : const Offset(0, -1);
}

class _Cloud {
  _Cloud(this.pos, this.scale, this.speed, this.puffs);
  Offset pos;
  final double scale, speed;

  /// كل نفخة: x, y, نصف قطر (نسبة للحجم)
  final List<List<double>> puffs;
}

/// طيور بعيدة بالخلفية، بس للمنظر
class _Far {
  _Far(this.pos, this.speed, this.seed);
  Offset pos;
  final double speed, seed;
}

class _PigeonState extends LoopState<PigeonGame> {
  static const target = 10;
  static const roundTime = 60.0;
  static const reload = 0.42;
  final _rnd = math.Random();

  bool get crazy => widget.crazy;
  GamePhase phase = GamePhase.countdown;
  late List<int> score = List.filled(n, 0);
  late List<int> combo = List.filled(n, 0);
  late List<PowerKind?> power = List.filled(n, null);
  late List<int> powerShots = List.filled(n, 0);
  late List<double> readyAt = List.filled(n, 0);
  late List<double> shotAt = List.filled(n, -10);
  late List<double> scoredAt = List.filled(n, -10);
  late List<double> frozenUntil = List.filled(n, 0);
  late List<Offset?> aimStart = List.filled(n, null);
  late List<Offset> aimCur = List.filled(n, Offset.zero);
  final Map<int, int> owners = {};

  final birds = <_Bird>[];
  final stones = <_Stone>[];
  final crates = <_Crate>[];
  final bits = <_Bit>[];
  final pops = <_Pop>[];
  final clouds = <_Cloud>[];
  final far = <_Far>[];
  final groupHit = <int>{};
  bool firstPigeon = true;
  double playStart = 0, overAt = 0;
  double respawnAt = 0.3, nextCrowAt = 0, nextFlockAt = 0, nextCrateAt = 0;
  double nextFarAt = 3, nextCooAt = 2, shake = 0;
  int winner = -1;
  int round = 0;
  int shotSeq = 0;
  int lastTick = -1;
  Size size = Size.zero;
  double dpr = 1;

  /// السطوح والنخل ما تتغير، فنرسمها مرة وحدة كصورة ونعيد استعمالها كل إطار
  ui.Image? roofImg, palmImg;
  Size roofImgSize = Size.zero;
  List<_Seat>? _seatCache;
  Size _seatSize = Size.zero;

  @override
  void initState() {
    super.initState();
    Sfx.preload(const ['snap', 'stretch', 'hit', 'gold', 'crow', 'land', 'clack', 'power', 'freeze', 'combo', 'coo', 'flap', 'whoosh', 'tick', 'pop', 'win']);
    Music.play(crazy ? 'music_crazy' : 'music_calm', volume: crazy ? 0.42 : 0.32);
  }

  @override
  void dispose() {
    Music.stop();
    roofImg?.dispose();
    palmImg?.dispose();
    super.dispose();
  }

  @override
  Future<void> openPause() async {
    if (paused) return;
    Music.pause();
    await super.openPause();
    if (mounted && phase != GamePhase.over) Music.resume();
  }

  int get n => widget.players;
  int get total => score.fold(0, (a, b) => a + b);
  double get k => (math.min(size.width, size.height) / 400).clamp(0.8, 1.6).toDouble();
  double get maxPull => math.min(size.width, size.height) * 0.26;
  double get skyTop => size.height * 0.22;
  double get skyBottom => size.height * 0.78;

  double get elapsed {
    if (phase == GamePhase.countdown) return 0;
    final now = phase == GamePhase.over ? overAt : time;
    return math.min(roundTime, now - playStart);
  }

  /// من 0 (عصر) لـ 1 (غروب). بس بالمجنون، وتمشي ويا الوقت بنعومة.
  /// (بالعادي ثابتة، لأن ربطها بالنقاط يخلي الإضاءة تتغير فجأة ويا كل ضربة)
  double get progress => crazy ? clamp01(elapsed / roundTime) : 0;

  double padOf(Size s) => math.min(80.0, s.height * 0.1);

  List<_Seat> seats(Size s) {
    if (_seatCache != null && _seatSize == s) return _seatCache!;
    _seatSize = s;
    return _seatCache = _buildSeats(s);
  }

  List<_Seat> _buildSeats(Size s) {
    final w = s.width, h = s.height;
    final pad = padOf(s);
    if (n == 2) {
      return [
        _Seat(Offset(w / 2, h - pad), Rect.fromLTWH(0, h / 2, w, h / 2), false),
        _Seat(Offset(w / 2, pad), Rect.fromLTWH(0, 0, w, h / 2), true),
      ];
    }
    final q = [
      _Seat(Offset(w * 0.7, h - pad), Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2), false),
      _Seat(Offset(w * 0.3, pad), Rect.fromLTWH(0, 0, w / 2, h / 2), true),
      _Seat(Offset(w * 0.3, h - pad), Rect.fromLTWH(0, h / 2, w / 2, h / 2), false),
      _Seat(Offset(w * 0.7, pad), Rect.fromLTWH(w / 2, 0, w / 2, h / 2), true),
    ];
    return q.sublist(0, n);
  }

  /// الزاوية الفاضية لما يكونون 3 (بيها برج حمام)
  _Seat get emptySeat {
    final w = size.width, h = size.height;
    return _Seat(Offset(w * 0.7, padOf(size)), Rect.fromLTWH(w / 2, 0, w / 2, h / 2), true);
  }

  @override
  void restart() {
    setState(() {
      phase = GamePhase.countdown;
      score = List.filled(n, 0);
      combo = List.filled(n, 0);
      power = List.filled(n, null);
      powerShots = List.filled(n, 0);
      readyAt = List.filled(n, 0);
      shotAt = List.filled(n, -10);
      scoredAt = List.filled(n, -10);
      frozenUntil = List.filled(n, 0);
      aimStart = List.filled(n, null);
      owners.clear();
      birds.clear();
      stones.clear();
      crates.clear();
      bits.clear();
      pops.clear();
      groupHit.clear();
      firstPigeon = true;
      respawnAt = time + 0.3;
      shake = 0;
      winner = -1;
      lastTick = -1;
      round++;
    });
  }

  // ------------------------------------------------------------ الطيور

  Offset _randomTarget() {
    final w = size.width, m = 44 * k;
    return Offset(m + _rnd.nextDouble() * (w - 2 * m), skyTop + _rnd.nextDouble() * (skyBottom - skyTop));
  }

  double _speed(_Bird b) {
    final grow = crazy ? elapsed * 2.2 + total * 4 : total * 10.0;
    var base = math.min(130 + grow, 300) * k;
    if (b.small) base *= 1.75;
    switch (b.kind) {
      case BirdKind.gold:
        return base * 1.35;
      case BirdKind.crow:
        return base * 1.05;
      case BirdKind.pigeon:
        return base;
    }
  }

  /// الارتفاع من 0 (واطي) لـ 1 (عالي)
  double alt(_Bird b) {
    if (b.hit) return math.max(0, b.altAtHit - (time - b.hitAt) * 1.4);
    return 0.5 + 0.5 * math.sin(time * 0.8 + b.seed);
  }

  double birdScale(_Bird b) => 0.8 + 0.34 * alt(b);

  double hitRadius(_Bird b) => birdRadius(b.kind, k) * (b.small ? 0.7 : 1) * birdScale(b);

  double flapOf(_Bird b) {
    if (!b.hit && time < b.glideUntil) return 0.95;
    return 0.5 + 0.5 * math.sin(b.flap);
  }

  _Bird _spawn(BirdKind kind, {bool small = false, Offset? from, Offset? to}) {
    final left = _rnd.nextBool();
    final pos = from ?? Offset(left ? -40 * k : size.width + 40 * k, skyTop + _rnd.nextDouble() * (skyBottom - skyTop));
    final t = to ?? _randomTarget();
    final b = _Bird(kind, pos, Offset.zero, t, _rnd.nextDouble() * 10, small: small);
    b.vel = (t - pos) / (t - pos).distance * _speed(b);
    b.heading = math.atan2(b.vel.dy, b.vel.dx);
    b.retargetAt = time + 2 + _rnd.nextDouble() * 1.5;
    b.nextGlideAt = time + 1.5 + _rnd.nextDouble() * 2;
    birds.add(b);
    return b;
  }

  void _spawnFlock() {
    final fromLeft = _rnd.nextBool();
    final y = skyTop + (0.2 + _rnd.nextDouble() * 0.6) * (skyBottom - skyTop);
    final w = size.width;
    for (var i = 0; i < 4; i++) {
      final from = Offset(fromLeft ? -40 * k - i * 34 * k : w + 40 * k + i * 34 * k, y + (i.isEven ? -1 : 1) * i * 16 * k);
      final to = Offset(fromLeft ? w + 200 * k : -200 * k, from.dy + (_rnd.nextDouble() - 0.5) * 120 * k);
      final b = _spawn(BirdKind.pigeon, small: true, from: from, to: to);
      b.passer = true;
      b.leaving = true;
    }
  }

  void _spawnCrate() {
    final w = size.width;
    final pos = Offset(60 * k + _rnd.nextDouble() * (w - 120 * k), skyTop + _rnd.nextDouble() * (skyBottom - skyTop));
    final a = _rnd.nextDouble() * math.pi * 2;
    crates.add(_Crate(pos, Offset(math.cos(a), math.sin(a)) * 24 * k, PowerKind.values[_rnd.nextInt(3)], time));
  }

  void _initScene() {
    final w = size.width, h = size.height;
    for (var i = 0; i < 7; i++) {
      final puffs = <List<double>>[
        [0, 0, 1],
      ];
      final count = 3 + _rnd.nextInt(4);
      for (var j = 0; j < count; j++) {
        final a = _rnd.nextDouble() * math.pi * 2;
        final d = 0.6 + _rnd.nextDouble() * 0.6;
        puffs.add([math.cos(a) * d * 1.3, math.sin(a) * d * 0.55, 0.45 + _rnd.nextDouble() * 0.4]);
      }
      clouds.add(_Cloud(
        Offset(_rnd.nextDouble() * w, h * (0.08 + 0.84 * (i + _rnd.nextDouble() * 0.6) / 7)),
        0.6 + _rnd.nextDouble() * 0.8,
        (7 + _rnd.nextDouble() * 14) * k,
        puffs,
      ));
    }
  }

  // ------------------------------------------------------------ التحديث

  @override
  void update(double dt) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    if (clouds.isEmpty) _initScene();

    for (final c in clouds) {
      c.pos += Offset(c.speed * dt, 0);
      if (c.pos.dx > w + 130 * c.scale * k) c.pos = Offset(-130 * c.scale * k, c.pos.dy);
    }
    if (time >= nextFarAt) {
      final y = h * (0.15 + _rnd.nextDouble() * 0.7);
      for (var i = 0; i < 5; i++) {
        far.add(_Far(Offset(-20 * k - (i % 3) * 14 * k - i * 9 * k, y + (i - 2).abs() * 8 * k), 34 * k, _rnd.nextDouble() * 6));
      }
      nextFarAt = time + 14 + _rnd.nextDouble() * 12;
    }
    for (final f in far) {
      f.pos += Offset(f.speed * dt, -f.speed * 0.15 * dt);
    }
    far.removeWhere((f) => f.pos.dx > w + 30);
    shake = math.max(0, shake - dt * 28);

    if (phase != GamePhase.over) {
      final hasMain = birds.any((b) => b.kind != BirdKind.crow && !b.small);
      if (!hasMain && time >= respawnAt) {
        final gold = crazy && !firstPigeon && _rnd.nextDouble() < 0.2;
        firstPigeon = false;
        _spawn(gold ? BirdKind.gold : BirdKind.pigeon);
        Sfx.play('flap', volume: 0.55);
      }
      if (time >= nextCooAt) {
        if (birds.any((b) => !b.hit && b.kind != BirdKind.crow)) Sfx.play('coo', volume: 0.35);
        nextCooAt = time + 6 + _rnd.nextDouble() * 6;
      }
    }

    if (phase == GamePhase.play && crazy) {
      if (elapsed >= roundTime) {
        _endByTime();
        return;
      }
      final left = (roundTime - elapsed).ceil();
      if (left <= 10 && left != lastTick) {
        lastTick = left;
        Sfx.play('tick', volume: 0.7);
      }
      if (total >= 2 && time >= nextCrowAt && !birds.any((b) => b.kind == BirdKind.crow)) {
        final c = _spawn(BirdKind.crow);
        c.leaveAt = time + 5 + _rnd.nextDouble() * 2.5;
        nextCrowAt = time + 8 + _rnd.nextDouble() * 6;
      }
      if (time >= nextFlockAt) {
        _spawnFlock();
        Sfx.play('whoosh', volume: 0.7);
        nextFlockAt = time + 12 + _rnd.nextDouble() * 7;
      }
      if (time >= nextCrateAt) {
        if (crates.isEmpty) {
          _spawnCrate();
          Sfx.play('pop', volume: 0.7);
        }
        nextCrateAt = time + 9 + _rnd.nextDouble() * 5;
      }
    }

    _updateBirds(dt);
    _updateCrates(dt);
    if (phase == GamePhase.play) {
      _updateStones(dt);
      stones.removeWhere((s) => s.dead);
    } else {
      // بعد الفوز ما نخلّي حجار واگفة بالجو
      stones.clear();
    }

    for (final p in bits) {
      p.age += dt;
      p.pos += p.vel * dt;
      p.vel = p.vel * (1 - math.min(1.0, dt * 2.4));
      p.rot += p.spin * dt;
    }
    bits.removeWhere((p) => p.age > p.life);
    pops.removeWhere((p) => time - p.born > 1.2);
  }

  void _updateBirds(double dt) {
    final w = size.width;
    for (final b in birds) {
      if (b.hit) {
        b.flap += dt * 3;
        b.spin += dt * 9;
        b.pos += b.vel * dt;
        b.vel = b.vel * (1 - math.min(1.0, dt * 3));
        continue;
      }
      final gliding = time < b.glideUntil;
      if (!gliding && time >= b.nextGlideAt && !b.passer) {
        b.glideUntil = time + 0.6 + _rnd.nextDouble() * 0.7;
        b.nextGlideAt = b.glideUntil + 1.8 + _rnd.nextDouble() * 2.5;
      }
      final sp = _speed(b) * (gliding ? 0.85 : 1);
      if (!gliding) b.flap += dt * (12 + sp / (40 * k));

      if (b.kind == BirdKind.crow && !b.leaving && time >= b.leaveAt) {
        b.leaving = true;
        b.target = Offset(b.pos.dx < w / 2 ? -140 * k : w + 140 * k, b.pos.dy);
      }
      if (!b.leaving && ((b.target - b.pos).distance < 30 * k || time >= b.retargetAt)) {
        b.target = _randomTarget();
        b.retargetAt = time + 1.3 + _rnd.nextDouble() * 1.8;
      }
      final to = b.target - b.pos;
      final d = to.distance;
      final desired = d > 0 ? to / d * sp : b.vel;
      b.vel = Offset.lerp(b.vel, desired, clamp01(dt * (b.passer ? 4 : 2.2)))!;
      final v = b.vel.distance;
      final perp = v > 0 ? Offset(-b.vel.dy, b.vel.dx) / v : Offset.zero;
      final wob = b.passer ? 14 : 42;
      b.pos += b.vel * dt + perp * (math.sin(time * 5 + b.seed) * wob * k * dt);
      b.heading = math.atan2(b.vel.dy, b.vel.dx);
    }
    birds.removeWhere((b) =>
        (b.hit && time - b.hitAt > 0.8) ||
        (b.leaving && (b.pos.dx < -160 * k || b.pos.dx > w + 160 * k)));
  }

  void _updateCrates(double dt) {
    final w = size.width;
    for (final c in crates) {
      c.pos += c.vel * dt;
      if (c.pos.dx < 30 * k || c.pos.dx > w - 30 * k) c.vel = Offset(-c.vel.dx, c.vel.dy);
      if (c.pos.dy < skyTop || c.pos.dy > skyBottom) c.vel = Offset(c.vel.dx, -c.vel.dy);
      if (time - c.born > 7.5) c.dead = true;
    }
    crates.removeWhere((c) => c.dead);
  }

  void _updateStones(double dt) {
    final w = size.width, h = size.height;
    final sr = 6 * k;
    const steps = 3;
    for (final s in stones) {
      final sp = s.vel.distance;
      for (var i = 0; i < steps && !s.dead; i++) {
        s.pos += s.vel * (dt / steps);
        s.dist += sp * dt / steps;
        if (s.dist >= s.range) {
          _land(s);
          break;
        }
        for (final c in crates) {
          if (!c.dead && (s.pos - c.pos).distance < 18 * k + sr) {
            _takeCrate(c, s.owner);
            s.hitSomething = true;
            groupHit.add(s.group);
            // الحجارة العادية تنكسر بالصندوق، الناريّة تكمل
            if (!s.fire) s.dead = true;
          }
        }
        if (s.dead) break;
        for (final b in birds) {
          if (b.hit || s.hits.contains(b)) continue;
          if ((s.pos - b.pos).distance < hitRadius(b) + sr) {
            s.hits.add(b);
            s.hitSomething = true;
            groupHit.add(s.group);
            _hitBird(b, s);
            if (!s.fire) {
              s.dead = true;
              break;
            }
          }
        }
        if (phase != GamePhase.play) return;
      }
      if (!s.dead && (s.pos.dx < -40 || s.pos.dx > w + 40 || s.pos.dy < -40 || s.pos.dy > h + 40)) {
        s.dead = true;
      }
    }

    // بالمجنون الحجار تتصادم بالجو
    if (crazy) {
      for (var i = 0; i < stones.length; i++) {
        final a = stones[i];
        if (a.dead) continue;
        for (var j = i + 1; j < stones.length; j++) {
          final b = stones[j];
          if (b.dead || a.owner == b.owner) continue;
          if ((a.pos - b.pos).distance < sr * 2.4) {
            a.dead = b.dead = true;
            final m = (a.pos + b.pos) / 2;
            _burst(m, 10, const Color(0xFFFFF0B3), round: true, speed: 160);
            Sfx.play('clack');
            Fx.hit();
            break;
          }
        }
      }
    }

    // رمية ما صابت شي = الكومبو يرجع صفر
    for (final s in stones) {
      if (!s.dead) continue;
      final groupAlive = stones.any((o) => !o.dead && o.group == s.group);
      if (!groupAlive) {
        if (!groupHit.contains(s.group)) combo[s.owner] = 0;
        groupHit.remove(s.group);
      }
    }
  }

  void _land(_Stone s) {
    s.dead = true;
    _burst(s.pos, 6, const Color(0xFFD9C29A), round: true, speed: 70);
    Sfx.play('land', volume: 0.5);
  }

  void _burst(Offset at, int count, Color color, {bool round = false, double speed = 200}) {
    for (var i = 0; i < count; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = (speed * 0.3 + _rnd.nextDouble() * speed) * k;
      bits.add(_Bit(
        at,
        Offset(math.cos(a), math.sin(a)) * sp,
        color,
        round ? 0.4 + _rnd.nextDouble() * 0.3 : 0.8 + _rnd.nextDouble() * 0.8,
        (round ? 2.5 + _rnd.nextDouble() * 3 : 5 + _rnd.nextDouble() * 6) * k,
        _rnd.nextDouble() * math.pi,
        (_rnd.nextDouble() - 0.5) * 10,
        round: round,
      ));
    }
  }

  void _hitBird(_Bird b, _Stone s) {
    final p = s.owner;
    b.altAtHit = alt(b);
    b.hit = true;
    b.hitAt = time;
    b.vel = b.vel * 0.25 + s.vel * 0.1;
    final flip = seats(size)[p].flip;
    final pal = birdPalette(b.kind);

    if (b.kind == BirdKind.crow) {
      score[p] = math.max(0, score[p] - 1);
      combo[p] = 0;
      pops.add(_Pop(b.pos, '-1', const Color(0xFFFF4D6A), flip, time));
      shake = 7;
      Fx.mid();
      Sfx.play('crow');
    } else {
      final pts = b.kind == BirdKind.gold ? 2 : 1;
      score[p] += pts;
      scoredAt[p] = time;
      if (!b.small) respawnAt = time + 0.9;
      pops.add(_Pop(b.pos, '+$pts', b.kind == BirdKind.gold ? const Color(0xFFFFD34D) : Colors.white, flip, time));
      if (crazy) {
        combo[p]++;
        if (combo[p] % 3 == 0) {
          score[p]++;
          pops.add(_Pop(b.pos + Offset(0, (flip ? 1 : -1) * 34 * k), 'كومبو! +1', const Color(0xFFFF9F1C), flip, time + 0.08, big: true));
          Sfx.play('combo');
        }
      }
      shake = b.kind == BirdKind.gold ? 10 : 6;
      if (b.kind == BirdKind.gold) {
        Fx.big();
        Sfx.play('gold');
      } else {
        Fx.hit();
        Sfx.play('hit');
      }
    }

    final count = b.kind == BirdKind.gold ? 22 : 15;
    for (var i = 0; i < count; i++) {
      final a = _rnd.nextDouble() * math.pi * 2;
      final sp = (60 + _rnd.nextDouble() * 200) * k;
      final col = i.isEven ? pal.wing : (i % 3 == 0 ? Colors.white : pal.body);
      bits.add(_Bit(b.pos, Offset(math.cos(a), math.sin(a)) * sp, col, 0.8 + _rnd.nextDouble() * 0.8,
          (5 + _rnd.nextDouble() * 6) * k, _rnd.nextDouble() * math.pi, (_rnd.nextDouble() - 0.5) * 10));
    }

    if (!crazy && score[p] >= target) _finish(p);
  }

  void _takeCrate(_Crate c, int p) {
    c.dead = true;
    final flip = seats(size)[p].flip;
    Fx.mid();
    _burst(c.pos, 12, const Color(0xFFC98B4E), speed: 180);
    switch (c.kind) {
      case PowerKind.fire:
        power[p] = PowerKind.fire;
        powerShots[p] = 3;
        pops.add(_Pop(c.pos, 'نار!', const Color(0xFFFF7A1A), flip, time, big: true));
        Sfx.play('power');
      case PowerKind.triple:
        power[p] = PowerKind.triple;
        powerShots[p] = 3;
        pops.add(_Pop(c.pos, 'ثلاثية!', const Color(0xFFFFD34D), flip, time, big: true));
        Sfx.play('power');
      case PowerKind.freeze:
        pops.add(_Pop(c.pos, 'تجميد!', const Color(0xFF8FE3FF), flip, time, big: true));
        Sfx.play('freeze');
        final ss = seats(size);
        for (var i = 0; i < n; i++) {
          if (i == p) continue;
          frozenUntil[i] = time + 3;
          readyAt[i] = math.max(readyAt[i], time + 3);
          aimStart[i] = null;
          owners.removeWhere((_, v) => v == i);
          _burst(ss[i].anchor, 12, const Color(0xFFCFF4FF), round: true, speed: 120);
        }
    }
  }

  void _finish(int w) {
    winner = w;
    overAt = time;
    for (var i = 0; i < n; i++) {
      aimStart[i] = null;
    }
    owners.clear();
    Fx.big();
    Music.stop();
    Sfx.play('win');
    setState(() => phase = GamePhase.over);
  }

  void _endByTime() {
    final best = score.reduce(math.max);
    final tops = [for (var i = 0; i < n; i++) if (score[i] == best) i];
    _finish(tops.length == 1 ? tops.first : -1);
  }

  // ------------------------------------------------------------ اللمس

  Offset pull(int p) {
    final st = aimStart[p];
    if (st == null) return Offset.zero;
    var d = aimCur[p] - st;
    final m = maxPull;
    if (d.distance > m) d = d / d.distance * m;
    return d;
  }

  bool frozen(int p) => time < frozenUntil[p];

  void _down(PointerDownEvent e) {
    if (phase != GamePhase.play || paused) return;
    final ss = seats(size);
    for (var i = 0; i < ss.length; i++) {
      if (aimStart[i] == null && !frozen(i) && ss[i].zone.contains(e.localPosition)) {
        owners[e.pointer] = i;
        aimStart[i] = e.localPosition;
        aimCur[i] = e.localPosition;
        Fx.tap();
        if (time >= readyAt[i]) Sfx.play('stretch', volume: 0.6);
        return;
      }
    }
  }

  void _move(PointerMoveEvent e) {
    final p = owners[e.pointer];
    if (p != null) aimCur[p] = e.localPosition;
  }

  void _up(int pointer, {bool cancel = false}) {
    final p = owners.remove(pointer);
    if (p == null) return;
    final pl = pull(p);
    aimStart[p] = null;
    if (cancel || phase != GamePhase.play || paused || time < readyAt[p] || frozen(p)) return;
    final len = pl.distance;
    if (len < 14) return;
    final dir = -pl / len;
    final seat = seats(size)[p];
    if (dir.dx * seat.facing.dx + dir.dy * seat.facing.dy < 0.15) return;
    // السرعة والمدى نسبة لطول الشاشة: السحبة الضعيفة توصل نص الشاشة،
    // والقوية تعبرها. وكل الرميات تاخذ تقريباً نفس الوقت بالجو (~0.8 ثانية).
    final pw = len / maxPull;
    final speed = size.height * (0.6 + 0.9 * pw);
    final range = size.height * (0.5 + 0.75 * pw);
    final group = shotSeq++;
    final kind = power[p];
    final angles = kind == PowerKind.triple ? const [-0.2, 0.0, 0.2] : const [0.0];
    for (final a in angles) {
      final d = Offset(dir.dx * math.cos(a) - dir.dy * math.sin(a), dir.dx * math.sin(a) + dir.dy * math.cos(a));
      stones.add(_Stone(seat.anchor + d * (24 * k), d * speed, p, range, group, fire: kind == PowerKind.fire));
    }
    if (kind != null) {
      powerShots[p]--;
      if (powerShots[p] <= 0) power[p] = null;
    }
    readyAt[p] = time + reload;
    shotAt[p] = time;
    Fx.hit();
    Sfx.play('snap', volume: 0.8);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        size = box.biggest;
        dpr = MediaQuery.devicePixelRatioOf(context);
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: (e) => _up(e.pointer),
                onPointerCancel: (e) => _up(e.pointer, cancel: true),
                child: CustomPaint(painter: _PigeonPainter(this)),
              ),
            ),
            if (phase == GamePhase.countdown)
              Positioned.fill(
                child: Countdown(
                  key: ValueKey(round),
                  paused: paused,
                  dual: true,
                  onDone: () => setState(() {
                    phase = GamePhase.play;
                    playStart = time;
                    nextCrowAt = time + 7;
                    nextFlockAt = time + 10;
                    nextCrateAt = time + 5;
                  }),
                ),
              ),
            if (phase == GamePhase.over)
              Positioned.fill(
                child: ResultOverlay(
                  winner: winner,
                  scores: score,
                  dual: true,
                  subtitle: crazy ? 'خلص الوقت!' : null,
                  onAgain: () {
                    Music.play(crazy ? 'music_crazy' : 'music_calm', volume: crazy ? 0.42 : 0.32);
                    restart();
                  },
                ),
              ),
          ],
        );
      }),
    );
  }
}

// ================================================================ الرسم

double birdRadius(BirdKind kind, double k) => (kind == BirdKind.crow ? 25 : 23) * k;

class BirdPalette {
  const BirdPalette(this.wing, this.wingDark, this.body, this.head, this.tail, this.neck, this.eye);
  final Color wing, wingDark, body, head, tail, eye;
  final List<Color> neck;
}

BirdPalette birdPalette(BirdKind kind) {
  switch (kind) {
    case BirdKind.gold:
      return const BirdPalette(Color(0xFFFFDB6E), Color(0xFFC9860F), Color(0xFFFFCC4A), Color(0xFFE5A52B),
          Color(0xFFE9AE35), [Color(0xFFFFF3B5), Color(0xFFFFA928), Color(0xFFFFF3B5)], Color(0xFFFF6A2B));
    case BirdKind.crow:
      return const BirdPalette(Color(0xFF2C313C), Color(0xFF101319), Color(0xFF262A33), Color(0xFF1A1D24),
          Color(0xFF1D2129), [Color(0xFF3D4D70), Color(0xFF5D3D70), Color(0xFF3D4D70)], Color(0xFFFF3B3B));
    case BirdKind.pigeon:
      return const BirdPalette(Color(0xFFC9D2DC), Color(0xFF55606D), Color(0xFFB2BCC8), Color(0xFF7D8896),
          Color(0xFF8F9AA7), [Color(0xFF3FC493), Color(0xFF9160CF), Color(0xFF3FC493)], Color(0xFFFF8A2B));
  }
}

/// جناح طير من فوق: s = -1 يسار، +1 يمين. الطرف فيه ريش مدرّج.
Path _wingPath(double r, double s, double span) {
  final len = r * (0.55 + 1.45 * span);
  final y0 = s * r * 0.24;
  final p = Path()..moveTo(r * 0.36, y0);
  // الحافة الأمامية
  p.cubicTo(r * 0.62, y0 + s * len * 0.35, r * 0.32, y0 + s * len * 0.85, r * 0.0, y0 + s * len);
  // الطرف المدوّر
  p.quadraticBezierTo(-r * 0.16, y0 + s * len * 1.08, -r * 0.34, y0 + s * len * 0.98);
  // ريش الحافة الخلفية (تموّجات)
  const feathers = 6;
  final a = Offset(-r * 0.34, y0 + s * len * 0.98);
  final b = Offset(-r * 0.74, y0 + s * len * 0.08);
  for (var i = 1; i <= feathers; i++) {
    final t0 = (i - 1) / feathers, t1 = i / feathers;
    final p0 = Offset.lerp(a, b, t0)!, p1 = Offset.lerp(a, b, t1)!;
    final mid = Offset.lerp(p0, p1, 0.5)!;
    final bulge = r * (0.2 - 0.1 * t0);
    p.quadraticBezierTo(mid.dx - bulge, mid.dy + s * bulge * 0.4, p1.dx, p1.dy);
  }
  p.close();
  return p;
}

/// يرسم طير من فوق، متجه لليمين (+x)، بمركز (0,0).
/// flap من 0 لـ 1 = فتحة الجناح. flash = وميض أبيض لمّن ينضرب.
void paintBird(Canvas canvas, double r, double flap, BirdKind kind, {double opacity = 1, double flash = 0}) {
  if (flash > 0) {
    canvas.saveLayer(Rect.fromCircle(center: Offset.zero, radius: r * 3), Paint());
  }
  final pal = birdPalette(kind);
  Color a(Color c) => alpha(c, c.a * opacity);
  final span = 0.4 + 0.6 * flap;

  if (kind == BirdKind.gold) {
    canvas.drawCircle(
      Offset.zero,
      r * 2.4,
      Paint()
        ..shader = RadialGradient(colors: [
          alpha(const Color(0xFFFFE27A), 0.55 * opacity),
          alpha(const Color(0xFFFFE27A), 0),
        ]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 2.4)),
    );
  }

  // الذيل: مروحة مدوّرة بشريط غامق
  final tail = Path()
    ..moveTo(-r * 0.5, -r * 0.2)
    ..lineTo(-r * 1.3, -r * 0.44)
    ..quadraticBezierTo(-r * 1.62, 0, -r * 1.3, r * 0.44)
    ..lineTo(-r * 0.5, r * 0.2)
    ..close();
  canvas.drawPath(tail, Paint()..color = a(pal.tail));
  canvas.save();
  canvas.clipPath(tail);
  canvas.drawRect(Rect.fromLTRB(-r * 1.7, -r, -r * 1.3, r), Paint()..color = a(pal.wingDark));
  canvas.restore();
  final tailLine = Paint()
    ..color = a(alpha(pal.wingDark, 0.35))
    ..strokeWidth = r * 0.04;
  for (final t in [-0.24, 0.0, 0.24]) {
    canvas.drawLine(Offset(-r * 0.6, t * r * 0.6), Offset(-r * 1.4, t * r * 1.5), tailLine);
  }

  // الجنحان
  for (final s in [-1.0, 1.0]) {
    final wing = _wingPath(r, s, span);
    final bounds = wing.getBounds();
    canvas.drawPath(
      wing,
      Paint()
        ..shader = LinearGradient(
          begin: s < 0 ? Alignment.bottomCenter : Alignment.topCenter,
          end: s < 0 ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [a(lighten(pal.wing, 0.14)), a(pal.wing), a(darken(pal.wing, 0.06))],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.clipPath(wing);
    final len = r * (0.55 + 1.45 * span);
    final y0 = s * r * 0.24;
    // الريش الطويل الغامق بالطرف
    final edge = y0 + s * len * 0.62;
    canvas.drawRect(
      Rect.fromLTRB(-r * 2, s < 0 ? edge - len : edge, r * 2, s < 0 ? edge : edge + len),
      Paint()..color = a(pal.wingDark),
    );
    // خطوط الريش
    final fl = Paint()
      ..color = a(alpha(lighten(pal.wingDark, 0.25), 0.8))
      ..strokeWidth = r * 0.035;
    for (var i = 0; i < 5; i++) {
      final x = r * (0.15 - i * 0.12);
      canvas.drawLine(Offset(x, edge), Offset(x - r * 0.12, y0 + s * len * 1.1), fl);
    }
    // خطّين غامقات (مثل الحمام البلدي)
    final bar = Paint()
      ..color = a(alpha(pal.wingDark, 0.9))
      ..strokeWidth = r * 0.11
      ..strokeCap = StrokeCap.round;
    for (final t in [0.28, 0.44]) {
      final yy = y0 + s * len * t;
      canvas.drawLine(Offset(-r * 0.05, yy), Offset(-r * 0.55, yy + s * r * 0.08), bar);
    }
    canvas.restore();
  }

  // الجسم
  final bodyRect = Rect.fromCenter(center: Offset(-r * 0.05, 0), width: r * 1.7, height: r * 0.95);
  canvas.drawOval(
    bodyRect,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.2, -0.3),
        radius: 0.9,
        colors: [a(lighten(pal.body, 0.2)), a(pal.body), a(darken(pal.body, 0.2))],
        stops: const [0, 0.6, 1],
      ).createShader(bodyRect),
  );

  // الرگبة اللمّاعة
  final neckRect = Rect.fromCenter(center: Offset(r * 0.55, 0), width: r * 0.68, height: r * 0.74);
  canvas.drawOval(
    neckRect,
    Paint()..shader = SweepGradient(colors: [for (final c in pal.neck) a(c)]).createShader(neckRect),
  );

  // الراس
  final hc = Offset(r * 0.92, 0);
  canvas.drawCircle(hc, r * 0.36, Paint()..color = a(pal.head));
  canvas.drawCircle(hc.translate(-r * 0.06, -r * 0.1), r * 0.14, Paint()..color = a(alpha(Colors.white, 0.2)));
  final beak = Path()
    ..moveTo(r * 1.2, -r * 0.09)
    ..lineTo(r * 1.5, 0)
    ..lineTo(r * 1.2, r * 0.09)
    ..close();
  canvas.drawPath(beak, Paint()..color = a(kind == BirdKind.crow ? const Color(0xFF6B7180) : const Color(0xFF3B3540)));
  canvas.drawCircle(Offset(r * 1.2, 0), r * 0.07, Paint()..color = a(const Color(0xFFF2EEE8)));
  for (final s in [-1.0, 1.0]) {
    final e = Offset(r * 1.0, s * r * 0.23);
    canvas.drawCircle(e, r * 0.1, Paint()..color = a(pal.eye));
    canvas.drawCircle(e, r * 0.05, Paint()..color = a(Colors.black));
    canvas.drawCircle(e.translate(-r * 0.02, -r * 0.02), r * 0.02, Paint()..color = a(Colors.white));
  }

  if (flash > 0) {
    canvas.drawRect(
      Rect.fromCircle(center: Offset.zero, radius: r * 3),
      Paint()
        ..color = alpha(Colors.white, flash)
        ..blendMode = BlendMode.srcATop,
    );
    canvas.restore();
  }
}

class _PigeonPainter extends CustomPainter {
  _PigeonPainter(this.s) : super(repaint: s.frame);
  final _PigeonState s;

  static const _wood = Color(0xFF94602E);
  static const _woodLight = Color(0xFFC98E52);
  static const _woodDark = Color(0xFF4A2C12);
  static const _cream = Color(0xFFFFEFD2);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final k = s.k;

    canvas.save();
    if (s.shake > 0) {
      final t = s.time * 95;
      canvas.translate(math.sin(t) * s.shake * 0.6, math.cos(t * 1.3) * s.shake * 0.6);
    }

    _ensureImages(size, k);
    final imgPaint = Paint()..filterQuality = FilterQuality.medium;

    _sky(canvas, size);
    for (final f in s.far) {
      _farBird(canvas, f, k);
    }
    _palmImage(canvas, Offset(-8 * k, h * 0.36), 1.0, 0.3, k, imgPaint);
    _palmImage(canvas, Offset(w + 8 * k, h * 0.64), 0.92, 2.1, k, imgPaint);
    for (final c in s.clouds) {
      _cloud(canvas, c, k);
    }

    final seats = s.seats(size);
    final roofImg = s.roofImg!;
    canvas.drawImageRect(
      roofImg,
      Rect.fromLTWH(0, 0, roofImg.width.toDouble(), roofImg.height.toDouble()),
      Offset.zero & size,
      imgPaint,
    );
    for (var i = 0; i < seats.length; i++) {
      final side = _plaqueSide(size, seats[i]);
      _local(canvas, seats[i], () => _plaque(canvas, Offset(side * (s.n == 2 ? 100 : 80) * k, -46 * k), i, k));
    }

    for (final c in s.crates) {
      _crate(canvas, c, k);
    }
    for (final b in s.birds) {
      _birdShadow(canvas, b, k);
    }
    for (final b in s.birds) {
      _bird(canvas, b, k);
    }
    _bits(canvas);
    for (final st in s.stones) {
      _stone(canvas, st, k);
    }

    for (var i = 0; i < seats.length; i++) {
      _aimGuide(canvas, i, seats[i], k);
      _slingshot(canvas, i, seats[i], k);
    }
    if (s.crazy) _timer(canvas, size, k);

    for (final p in s.pops) {
      if (s.time < p.born) continue;
      final t = ((s.time - p.born) / 1.2).clamp(0.0, 1.0);
      final rise = (p.flip ? 1 : -1) * 54 * k * easeOutCubic(t);
      final sc = t < 0.15 ? easeOutBack(t / 0.15) : 1.0;
      // الشفافية بدرجات حتى النص المجهّز ينعاد استعماله
      final op = ((1 - t * t) * 12).round() / 12;
      if (op <= 0) continue;
      canvas.save();
      canvas.translate(p.pos.dx, p.pos.dy + rise);
      canvas.scale(sc);
      paintText(
        canvas,
        p.text,
        Offset.zero,
        size: ((p.big ? 30 : 34) * k).roundToDouble(),
        color: alpha(p.color, op),
        flip: p.flip,
        shadows: [Shadow(color: alpha(const Color(0xFF0B2236), 0.75 * op), offset: const Offset(0, 2))],
      );
      canvas.restore();
    }

    canvas.restore();
  }

  /// يرسم السطوح والنخلة مرة وحدة كصور (يرجع يرسمها بس إذا تغيّر حجم الشاشة)
  void _ensureImages(Size size, double k) {
    if (s.roofImg != null && s.roofImgSize == size) return;
    s.roofImg?.dispose();
    s.palmImg?.dispose();
    s.roofImgSize = size;
    final dpr = s.dpr;

    var rec = ui.PictureRecorder();
    var c = Canvas(rec)..scale(dpr);
    final seats = s.seats(size);
    for (var i = 0; i < seats.length; i++) {
      _roof(c, size, seats[i], i, k);
    }
    if (s.n == 3) _roof(c, size, s.emptySeat, -1, k);
    var pic = rec.endRecording();
    s.roofImg = pic.toImageSync((size.width * dpr).ceil(), (size.height * dpr).ceil());
    pic.dispose();

    final pr = 50 * k, box = pr * 2.2;
    rec = ui.PictureRecorder();
    c = Canvas(rec)..scale(dpr);
    _palm(c, Offset(box / 2, box / 2), pr);
    pic = rec.endRecording();
    s.palmImg = pic.toImageSync((box * dpr).ceil(), (box * dpr).ceil());
    pic.dispose();
  }

  void _palmImage(Canvas canvas, Offset c, double scale, double rot, double k, Paint p) {
    final img = s.palmImg!;
    final box = 50 * k * 2.2 * scale;
    canvas.drawCircle(c.translate(10 * k, 14 * k), 46 * k * scale, Paint()..color = alpha(const Color(0xFF1B4A6B), 0.1));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: box, height: box),
      p,
    );
    canvas.restore();
  }

  // ------------------------------------------------------------ الجو

  void _sky(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = s.progress * 0.85;
    Color mix(int day, int dusk) => Color.lerp(Color(day), Color(dusk), t)!;
    final r = (Offset.zero & size).inflate(30);
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [mix(0xFFE4F7FF, 0xFFFFE9C9), mix(0xFFA6DCF6, 0xFFF6B98E), mix(0xFF5FB2E2, 0xFF8E70B9)],
          stops: const [0, 0.55, 1],
        ).createShader(r),
    );
    final sun = Offset(w * 0.78, h * 0.4);
    final sr = math.max(w, h) * 0.42;
    final glow = mix(0xFFFFF3BF, 0xFFFFC27A);
    canvas.drawCircle(
      sun,
      sr,
      Paint()
        ..shader = RadialGradient(colors: [alpha(glow, 0.55 + 0.2 * t), alpha(glow, 0)])
            .createShader(Rect.fromCircle(center: sun, radius: sr)),
    );
  }

  void _farBird(Canvas canvas, _Far f, double k) {
    final fl = math.sin(s.time * 9 + f.seed);
    final wv = 5 * k, hv = 2.5 * k * fl;
    final p = Path()
      ..moveTo(f.pos.dx - wv, f.pos.dy - hv)
      ..quadraticBezierTo(f.pos.dx - wv * 0.4, f.pos.dy - hv - 2 * k, f.pos.dx, f.pos.dy)
      ..quadraticBezierTo(f.pos.dx + wv * 0.4, f.pos.dy - hv - 2 * k, f.pos.dx + wv, f.pos.dy - hv);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * k
        ..strokeCap = StrokeCap.round
        ..color = alpha(const Color(0xFF2D4A63), 0.35),
    );
  }

  /// راس نخلة طالع من حافة الشاشة
  void _palm(Canvas canvas, Offset c, double r) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    const fronds = 9;
    for (var i = 0; i < fronds; i++) {
      final a = i * math.pi * 2 / fronds;
      canvas.save();
      canvas.rotate(a);
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(r * 0.5, -r * 0.2, r, r * 0.06)
        ..quadraticBezierTo(r * 0.5, r * 0.16, 0, 0)
        ..close();
      canvas.drawPath(
        leaf,
        Paint()
          ..shader = LinearGradient(colors: [const Color(0xFF3E8F3A), i.isEven ? const Color(0xFF6CC04A) : const Color(0xFF58AE3F)])
              .createShader(Rect.fromLTWH(0, -r * 0.2, r, r * 0.4)),
      );
      final vein = Paint()
        ..color = alpha(const Color(0xFF2E6B2A), 0.6)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset.zero, Offset(r * 0.95, r * 0.05), vein);
      for (var j = 1; j < 6; j++) {
        final x = r * j / 6;
        canvas.drawLine(Offset(x, r * 0.02), Offset(x + r * 0.06, -r * 0.09), vein);
        canvas.drawLine(Offset(x, r * 0.04), Offset(x + r * 0.06, r * 0.13), vein);
      }
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, r * 0.14, Paint()..color = const Color(0xFF8A5A2B));
    for (var i = 0; i < 5; i++) {
      final a = i * 1.3;
      canvas.drawCircle(Offset(math.cos(a), math.sin(a)) * r * 0.13, r * 0.06, Paint()..color = const Color(0xFFE09A2D));
    }
    canvas.restore();
  }

  void _cloud(Canvas canvas, _Cloud c, double k) {
    final base = 30 * c.scale * k;
    Path shape(Offset o, double grow) {
      final p = Path();
      for (final f in c.puffs) {
        p.addOval(Rect.fromCircle(center: c.pos + o + Offset(f[0] * base, f[1] * base), radius: f[2] * base * grow));
      }
      return p;
    }

    canvas.drawPath(shape(Offset(12 * k, 18 * k), 1), Paint()..color = alpha(const Color(0xFF2A6C97), 0.09));
    canvas.drawPath(shape(Offset.zero, 1), Paint()..color = alpha(Colors.white, 0.88));
    canvas.drawPath(shape(Offset(-base * 0.12, -base * 0.16), 0.78), Paint()..color = alpha(Colors.white, 0.6));
  }

  // ------------------------------------------------------------ السطوح

  /// يرسم داخل إحداثيات اللاعب: (0,0) = المصيادة، والسما صوب -y
  void _local(Canvas canvas, _Seat seat, void Function() draw) {
    canvas.save();
    canvas.translate(seat.anchor.dx, seat.anchor.dy);
    if (seat.flip) canvas.rotate(math.pi);
    draw();
    canvas.restore();
  }

  /// جهة مربع النقاط: لو 2 جنب المصيادة، لو أكثر صوب حافة الشاشة
  double _plaqueSide(Size size, _Seat seat) {
    final outward = s.n == 2 ? 1.0 : (seat.anchor.dx > size.width / 2 ? 1.0 : -1.0);
    return seat.flip ? -outward : outward;
  }

  void _roof(Canvas canvas, Size size, _Seat seat, int player, double k) {
    final a = seat.anchor;
    final edge = seat.flip ? a.dy : size.height - a.dy;
    final left = seat.flip ? a.dx - seat.zone.right : seat.zone.left - a.dx;
    final right = seat.flip ? a.dx - seat.zone.left : seat.zone.right - a.dx;
    final col = player >= 0 ? C.players[player] : null;
    final side = _plaqueSide(size, seat);

    _local(canvas, seat, () {
      final top = -40 * k;
      final gap = s.n == 2 ? 0.0 : 3.0;
      final floor = Rect.fromLTRB(left + gap, top, right - gap, edge + 30);
      canvas.drawRect(
        floor,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF1DDB4), Color(0xFFDDBB88)],
          ).createShader(floor),
      );
      // كاشي خفيف
      final tile = Paint()
        ..color = alpha(const Color(0xFF9C7444), 0.09)
        ..strokeWidth = 1;
      final step = 36 * k;
      for (var y = top + step; y < floor.bottom; y += step) {
        canvas.drawLine(Offset(floor.left, y), Offset(floor.right, y), tile);
      }
      for (var x = step / 2; x < floor.right; x += step) {
        canvas.drawLine(Offset(x, top), Offset(x, floor.bottom), tile);
      }
      for (var x = -step / 2; x > floor.left; x -= step) {
        canvas.drawLine(Offset(x, top), Offset(x, floor.bottom), tile);
      }

      // حايط الطابوگ
      final wallH = 12 * k;
      final wall = Rect.fromLTRB(floor.left, top - wallH, floor.right, top);
      canvas.drawRect(
        wall.shift(Offset(0, -5 * k)).inflate(2),
        Paint()
          ..color = alpha(Colors.black, 0.1)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * k),
      );
      canvas.drawRect(wall, Paint()..color = const Color(0xFFC88A57));
      final mortar = Paint()
        ..color = alpha(const Color(0xFF7A4A26), 0.5)
        ..strokeWidth = 1.1;
      canvas.drawLine(Offset(wall.left, wall.center.dy), Offset(wall.right, wall.center.dy), mortar);
      final bw = 22 * k;
      var row = 0;
      for (final yy in [wall.top, wall.center.dy]) {
        final off = row.isEven ? 0.0 : bw / 2;
        for (var x = wall.left + off; x < wall.right; x += bw) {
          canvas.drawLine(Offset(x, yy), Offset(x, yy + wallH / 2), mortar);
        }
        row++;
      }
      canvas.drawRect(Rect.fromLTRB(wall.left, wall.top - 3 * k, wall.right, wall.top + 1), Paint()..color = const Color(0xFFE2B27F));
      if (col != null) {
        canvas.drawRect(Rect.fromLTRB(wall.left, wall.top - 3 * k, wall.right, wall.top), Paint()..color = alpha(col, 0.8));
      }

      if (col == null) {
        _coop(canvas, Offset(0, 16 * k), k);
        return;
      }

      _rug(canvas, col, k);
      _tank(canvas, Offset(-side * (s.n == 2 ? 100 : 64) * k, 22 * k), k);
    });
  }

  void _rug(Canvas canvas, Color col, double k) {
    final rug = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, 12 * k), width: 92 * k, height: 56 * k),
      Radius.circular(7 * k),
    );
    canvas.drawRRect(rug.shift(Offset(0, 3 * k)), Paint()..color = alpha(Colors.black, 0.12));
    canvas.drawRRect(rug, Paint()..color = darken(col, 0.18));
    canvas.drawRRect(
      rug.deflate(5 * k),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * k
        ..color = alpha(_cream, 0.85),
    );
    final c = rug.center;
    final dm = Path()
      ..moveTo(c.dx, c.dy - 14 * k)
      ..lineTo(c.dx + 24 * k, c.dy)
      ..lineTo(c.dx, c.dy + 14 * k)
      ..lineTo(c.dx - 24 * k, c.dy)
      ..close();
    canvas.drawPath(dm, Paint()..color = alpha(_cream, 0.28));
    canvas.drawPath(
      dm,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * k
        ..color = alpha(_cream, 0.8),
    );
    final fringe = Paint()
      ..color = alpha(_cream, 0.8)
      ..strokeWidth = 1.3 * k;
    for (var x = rug.left + 5 * k; x < rug.right - 3 * k; x += 6 * k) {
      canvas.drawLine(Offset(x, rug.top), Offset(x, rug.top - 4 * k), fringe);
      canvas.drawLine(Offset(x, rug.bottom), Offset(x, rug.bottom + 4 * k), fringe);
    }
  }

  /// تانكي الماي من فوق
  void _tank(Canvas canvas, Offset c, double k) {
    final r = 14 * k;
    canvas.drawCircle(c.translate(4 * k, 5 * k), r, Paint()..color = alpha(Colors.black, 0.14));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [const Color(0xFFF4F7FA), const Color(0xFFB9C6D2)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * k
        ..color = alpha(const Color(0xFF7C8B99), 0.7),
    );
    canvas.drawCircle(c, r * 0.22, Paint()..color = const Color(0xFF7C8B99));
  }

  /// برج حمام (للزاوية الفاضية)
  void _coop(Canvas canvas, Offset c, double k) {
    final r = Rect.fromCenter(center: c, width: 70 * k, height: 50 * k);
    canvas.drawRect(r.shift(Offset(4 * k, 5 * k)), Paint()..color = alpha(Colors.black, 0.14));
    canvas.drawRect(r, Paint()..color = const Color(0xFF9A6A3A));
    // سقف بشكل جملون
    canvas.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.center.dy), Paint()..color = const Color(0xFFB27B44));
    canvas.drawLine(
      Offset(r.left, r.center.dy),
      Offset(r.right, r.center.dy),
      Paint()
        ..color = const Color(0xFF5E3B1B)
        ..strokeWidth = 2 * k,
    );
    final plank = Paint()
      ..color = alpha(const Color(0xFF5E3B1B), 0.5)
      ..strokeWidth = 1;
    for (var x = r.left + 10 * k; x < r.right; x += 10 * k) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), plank);
    }
    // حمامتين گاعدات على السطح
    for (final p in [Offset(r.left + 18 * k, r.top + 6 * k), Offset(r.right - 16 * k, r.bottom - 8 * k)]) {
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(p.dx < c.dx ? 0.4 : 2.6);
      paintBird(canvas, 8 * k, 0, BirdKind.pigeon);
      canvas.restore();
    }
  }

  /// لوحة النقاط على حايط الطابوگ
  void _plaque(Canvas canvas, Offset c, int i, double k) {
    final col = C.players[i];
    final since = s.time - s.scoredAt[i];
    final bump = since < 0.35 ? 1 + 0.22 * math.sin(since / 0.35 * math.pi) : 1.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(bump);
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 54 * k, height: 34 * k),
      Radius.circular(9 * k),
    );
    canvas.drawRRect(box.shift(Offset(0, 3 * k)), Paint()..color = alpha(Colors.black, 0.2));
    canvas.drawRRect(box, Paint()..color = _cream);
    canvas.drawRRect(
      box.deflate(1.5 * k),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * k
        ..color = col,
    );
    for (final dx in [-1.0, 1.0]) {
      canvas.drawCircle(Offset(dx * 20 * k, -10 * k), 1.8 * k, Paint()..color = alpha(darken(col, 0.4), 0.8));
    }
    paintText(canvas, '${s.score[i]}', Offset(0, s.crazy ? 0 : -3 * k), size: 22 * k, color: darken(col, 0.35));
    if (!s.crazy) {
      // نقاط التقدّم للعشرة
      for (var d = 0; d < _PigeonState.target; d++) {
        final x = (d - (_PigeonState.target - 1) / 2) * 4.2 * k;
        canvas.drawCircle(
          Offset(x, 10 * k),
          1.4 * k,
          Paint()..color = d < s.score[i] ? col : alpha(darken(col, 0.3), 0.25),
        );
      }
    }
    canvas.restore();
  }

  // ------------------------------------------------------------ الطيور

  void _birdShadow(Canvas canvas, _Bird b, double k) {
    final r = birdRadius(b.kind, k) * (b.small ? 0.7 : 1);
    final al = s.alt(b);
    var op = 1.0;
    if (b.hit) op = 1 - clamp01((s.time - b.hitAt) / 0.8);
    final off = (6 + 22 * al) * k;
    canvas.save();
    canvas.translate(b.pos.dx + off * 0.6, b.pos.dy + off);
    canvas.rotate(b.heading + b.spin);
    canvas.scale(0.85 + 0.1 * al);
    final span = 0.4 + 0.6 * s.flapOf(b);
    final p = Paint()..color = alpha(const Color(0xFF1B4A6B), (0.2 - 0.09 * al) * op);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2.6, height: r * 0.9), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(-r * 0.2, 0), width: r * 0.9, height: r * (0.8 + 3.1 * span)), p);
    canvas.restore();
  }

  void _bird(Canvas canvas, _Bird b, double k) {
    final r = birdRadius(b.kind, k) * (b.small ? 0.7 : 1);
    var op = 1.0, sc = s.birdScale(b), flash = 0.0;
    if (b.hit) {
      final t = clamp01((s.time - b.hitAt) / 0.8);
      op = 1 - t * t;
      sc *= 1 - 0.4 * t;
      flash = clamp01(1 - (s.time - b.hitAt) / 0.14) * 0.85;
    }
    canvas.save();
    canvas.translate(b.pos.dx, b.pos.dy);
    canvas.rotate(b.heading + b.spin);
    canvas.scale(sc);
    paintBird(canvas, r, s.flapOf(b), b.kind, opacity: op, flash: flash);
    canvas.restore();

    if (b.kind == BirdKind.gold && !b.hit) {
      for (var i = 0; i < 3; i++) {
        final a = s.time * 2.4 + i * math.pi * 2 / 3;
        final p = b.pos + Offset(math.cos(a), math.sin(a)) * r * 1.8 * sc;
        _sparkle(canvas, p, 4 * k * (0.6 + 0.4 * math.sin(s.time * 8 + i)), const Color(0xFFFFFBE0));
      }
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r * 2)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _bits(Canvas canvas) {
    for (final p in s.bits) {
      final t = p.age / p.life;
      final op = (1 - t).clamp(0.0, 1.0);
      if (p.round) {
        canvas.drawCircle(p.pos, p.size * (1 - 0.4 * t), Paint()..color = alpha(p.color, op));
        continue;
      }
      canvas.save();
      canvas.translate(p.pos.dx, p.pos.dy);
      canvas.rotate(p.rot);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: p.size * 1.8, height: p.size * 0.7),
        Paint()..color = alpha(p.color, op),
      );
      canvas.drawLine(
        Offset(-p.size * 0.9, 0),
        Offset(p.size * 0.9, 0),
        Paint()
          ..color = alpha(darken(p.color, 0.25), op)
          ..strokeWidth = math.max(1, p.size * 0.12),
      );
      canvas.restore();
    }
  }

  // ------------------------------------------------------------ الصناديق

  void _crate(Canvas canvas, _Crate c, double k) {
    final age = s.time - c.born;
    if (age > 6 && (age * 8).floor().isEven) return; // يرمش قبل لا يختفي
    final bob = 1 + 0.06 * math.sin(s.time * 4 + c.born);
    final pop = age < 0.3 ? easeOutBack(age / 0.3) : 1.0;
    final r = 17 * k * bob * pop;
    final glow = switch (c.kind) {
      PowerKind.fire => const Color(0xFFFF7A1A),
      PowerKind.triple => const Color(0xFFFFD34D),
      PowerKind.freeze => const Color(0xFF8FE3FF),
    };
    canvas.drawCircle(
      c.pos,
      r * 2,
      Paint()
        ..shader = RadialGradient(colors: [alpha(glow, 0.55), alpha(glow, 0)])
            .createShader(Rect.fromCircle(center: c.pos, radius: r * 2)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCircle(center: c.pos.translate(6 * k, 10 * k), radius: r), Radius.circular(4 * k)),
      Paint()..color = alpha(const Color(0xFF1B4A6B), 0.2),
    );
    canvas.save();
    canvas.translate(c.pos.dx, c.pos.dy);
    canvas.rotate(math.sin(s.time * 1.5 + c.born) * 0.15);
    final box = RRect.fromRectAndRadius(Rect.fromCircle(center: Offset.zero, radius: r), Radius.circular(4 * k));
    canvas.drawRRect(box, Paint()..color = const Color(0xFFB57A3E));
    final plank = Paint()
      ..color = const Color(0xFF7A4E22)
      ..strokeWidth = 2 * k;
    canvas.drawLine(Offset(-r, -r * 0.33), Offset(r, -r * 0.33), plank);
    canvas.drawLine(Offset(-r, r * 0.33), Offset(r, r * 0.33), plank);
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * k
        ..color = const Color(0xFF6A421C),
    );
    canvas.drawCircle(Offset.zero, r * 0.62, Paint()..color = _cream);
    _powerGlyph(canvas, c.kind, r * 0.5);
    canvas.restore();
  }

  void _powerGlyph(Canvas canvas, PowerKind kind, double r) {
    switch (kind) {
      case PowerKind.fire:
        final f = Path()
          ..moveTo(0, -r)
          ..quadraticBezierTo(r * 0.9, -r * 0.1, r * 0.55, r * 0.6)
          ..quadraticBezierTo(0, r * 1.05, -r * 0.55, r * 0.6)
          ..quadraticBezierTo(-r * 0.9, -r * 0.1, 0, -r)
          ..close();
        canvas.drawPath(f, Paint()..color = const Color(0xFFFF6A1A));
        canvas.drawCircle(Offset(0, r * 0.3), r * 0.32, Paint()..color = const Color(0xFFFFD34D));
      case PowerKind.triple:
        for (final dx in [-0.62, 0.0, 0.62]) {
          canvas.drawCircle(Offset(dx * r, dx == 0 ? -r * 0.2 : r * 0.25), r * 0.3, Paint()..color = const Color(0xFF6E665A));
        }
      case PowerKind.freeze:
        final p = Paint()
          ..color = const Color(0xFF3BB7E8)
          ..strokeWidth = r * 0.18
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi / 3;
          final d = Offset(math.cos(a), math.sin(a)) * r;
          canvas.drawLine(-d, d, p);
        }
    }
  }

  // ------------------------------------------------------------ الحجار

  void _stone(Canvas canvas, _Stone st, double k) {
    final h01 = math.sin(math.pi * clamp01(st.dist / st.range));
    final r = 6 * k * (1 + 0.35 * h01);
    final v = st.vel.distance;
    final trail = st.fire ? const Color(0xFFFF8A1F) : Colors.white;
    if (v > 0) {
      final dir = st.vel / v;
      final len = (st.fire ? 50 : 34) * k;
      canvas.drawLine(
        st.pos - dir * len,
        st.pos,
        Paint()
          ..shader = LinearGradient(colors: [alpha(trail, 0), alpha(trail, st.fire ? 0.9 : 0.65)])
              .createShader(Rect.fromPoints(st.pos - dir * len, st.pos))
          ..strokeWidth = r * (st.fire ? 1.8 : 1.2)
          ..strokeCap = StrokeCap.round,
      );
    }
    final off = (4 + 16 * h01) * k;
    canvas.drawCircle(st.pos.translate(off * 0.6, off), 6 * k, Paint()..color = alpha(const Color(0xFF1B4A6B), 0.24 - 0.1 * h01));
    if (st.fire) {
      canvas.drawCircle(
        st.pos,
        r * 2.2,
        Paint()
          ..shader = RadialGradient(colors: [alpha(const Color(0xFFFF7A1A), 0.6), alpha(const Color(0xFFFF7A1A), 0)])
              .createShader(Rect.fromCircle(center: st.pos, radius: r * 2.2)),
      );
    }
    _pebble(canvas, st.pos, r, C.players[st.owner], hot: st.fire);
  }

  void _pebble(Canvas canvas, Offset c, double r, Color tint, {bool hot = false}) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: hot
              ? [const Color(0xFFFFF0B3), const Color(0xFFFF8A1F), const Color(0xFFB8360B)]
              : [const Color(0xFFE7E1D6), const Color(0xFF9C9488), const Color(0xFF5E574D)],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.28
        ..color = alpha(tint, 0.85),
    );
  }

  // ------------------------------------------------------------ المصيادة

  void _aimGuide(Canvas canvas, int i, _Seat seat, double k) {
    final pl = s.pull(i);
    final len = pl.distance;
    if (s.aimStart[i] == null || len < 14) return;
    final dir = -pl / len;
    final ok = dir.dx * seat.facing.dx + dir.dy * seat.facing.dy >= 0.15;
    final power = len / s.maxPull;
    final col = C.players[i];
    final angles = s.power[i] == PowerKind.triple ? const [-0.2, 0.0, 0.2] : const [0.0];
    final count = 7 + (power * 7).round();
    final gap = 22 * k;
    for (final a in angles) {
      final d = Offset(dir.dx * math.cos(a) - dir.dy * math.sin(a), dir.dx * math.sin(a) + dir.dy * math.cos(a));
      for (var j = 1; j <= count; j++) {
        final p = seat.anchor + d * (24 * k + j * gap);
        final f = 1 - j / (count + 1);
        canvas.drawCircle(
          p,
          (2.2 + 2.2 * f) * k,
          Paint()..color = ok ? alpha(Colors.white, 0.85 * f) : alpha(const Color(0xFFFF4D6A), 0.6 * f),
        );
      }
    }
    canvas.drawArc(
      Rect.fromCircle(center: seat.anchor, radius: 50 * k),
      -math.pi / 2,
      math.pi * 2 * power,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * k
        ..strokeCap = StrokeCap.round
        ..color = alpha(col, 0.9),
    );
  }

  void _slingshot(Canvas canvas, int i, _Seat seat, double k) {
    final col = C.players[i];
    var pl = s.pull(i);
    final power = pl.distance / s.maxPull;
    if (seat.flip) pl = -pl;
    final ready = s.time >= s.readyAt[i] && !s.frozen(i);
    final since = s.time - s.shotAt[i];
    final iced = s.frozen(i);

    _local(canvas, seat, () {
      final lt = Offset(-21 * k, -36 * k), rt = Offset(21 * k, -36 * k);
      final rest = Offset(0, -31 * k);
      var pouch = rest + pl;
      if (pl == Offset.zero && since < 0.35) {
        final t = since / 0.35;
        pouch = Offset(0, -31 * k - 16 * k * math.sin(t * math.pi * 2.5) * (1 - t));
      }

      // ظل
      canvas.drawOval(
        Rect.fromCenter(center: Offset(6 * k, 32 * k), width: 40 * k, height: 13 * k),
        Paint()..color = alpha(Colors.black, 0.18),
      );

      final bandCol = Color.lerp(darken(col, 0.3), lighten(col, 0.3), power)!;
      final band = Paint()
        ..color = bandCol
        ..strokeWidth = (6.5 - 3 * power) * k
        ..strokeCap = StrokeCap.round;

      // المطاطة الخلفية
      if (!iced) canvas.drawLine(lt, pouch, band);

      // الخشبة: مسكة وفرعين
      final fork = Path()
        ..moveTo(0, 30 * k)
        ..lineTo(0, 0)
        ..moveTo(0, 2 * k)
        ..quadraticBezierTo(-4 * k, -14 * k, lt.dx, lt.dy)
        ..moveTo(0, 2 * k)
        ..quadraticBezierTo(4 * k, -14 * k, rt.dx, rt.dy);
      canvas.drawPath(
        fork,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _woodDark
          ..strokeWidth = 16 * k
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        fork,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _wood
          ..strokeWidth = 11 * k
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(-2.5 * k, 27 * k),
        Offset(-2.5 * k, 3 * k),
        Paint()
          ..color = alpha(_woodLight, 0.9)
          ..strokeWidth = 3 * k
          ..strokeCap = StrokeCap.round,
      );
      // عُقد الخشب
      for (final kn in [Offset(1.5 * k, -1 * k), Offset(-12 * k, -22 * k), Offset(13 * k, -26 * k)]) {
        canvas.drawOval(Rect.fromCenter(center: kn, width: 5 * k, height: 3.4 * k), Paint()..color = alpha(_woodDark, 0.7));
      }
      // لفّة بلون اللاعب على المسكة
      for (var y = 12.0; y <= 24; y += 4) {
        canvas.drawLine(
          Offset(-6 * k, y * k),
          Offset(6 * k, (y - 2) * k),
          Paint()
            ..color = col
            ..strokeWidth = 3.2 * k
            ..strokeCap = StrokeCap.round,
        );
      }

      if (!iced) {
        // جيب الجلد
        final pd = pouch - rest;
        final ang = pd.distance > 1 ? math.atan2(pd.dy, pd.dx) + math.pi / 2 : 0.0;
        canvas.save();
        canvas.translate(pouch.dx, pouch.dy);
        canvas.rotate(ang);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 22 * k, height: 12 * k), Radius.circular(5 * k)),
          Paint()..color = const Color(0xFF5A3A22),
        );
        canvas.restore();
        if (ready) _pebble(canvas, pouch, 6.5 * k, col, hot: s.power[i] == PowerKind.fire);

        // المطاطة الأمامية
        canvas.drawLine(rt, pouch, band);
      }
      for (final t in [lt, rt]) {
        canvas.drawCircle(t, 4.5 * k, Paint()..color = darken(col, 0.35));
      }

      // تعبئة الحجارة
      if (!s.frozen(i) && s.time < s.readyAt[i]) {
        final f = 1 - (s.readyAt[i] - s.time) / _PigeonState.reload;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(0, 2 * k), radius: 44 * k),
          -math.pi / 2,
          math.pi * 2 * clamp01(f),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * k
            ..strokeCap = StrokeCap.round
            ..color = alpha(Colors.white, 0.6),
        );
      }

      // تجميد
      if (iced) {
        final left = s.frozenUntil[i] - s.time;
        canvas.drawCircle(Offset(0, -4 * k), 42 * k, Paint()..color = alpha(const Color(0xFFBFEFFF), 0.45));
        canvas.drawCircle(
          Offset(0, -4 * k),
          42 * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * k
            ..color = alpha(Colors.white, 0.9),
        );
        canvas.save();
        canvas.translate(0, -4 * k);
        canvas.rotate(s.time * 0.5);
        _powerGlyph(canvas, PowerKind.freeze, 16 * k);
        canvas.restore();
        paintText(canvas, left.ceil().toString(), Offset(0, 22 * k), size: 18 * k, color: const Color(0xFF1D6E93));
      }

      // شارة القوة
      final pw = s.power[i];
      if (pw != null) {
        final c = Offset(0, -62 * k);
        canvas.drawCircle(c, 14 * k, Paint()..color = alpha(Colors.white, 0.92));
        canvas.drawCircle(
          c,
          14 * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * k
            ..color = col,
        );
        _powerGlyph(canvas, pw, 8 * k);
        paintText(canvas, '×${s.powerShots[i]}', c.translate(22 * k, 2 * k), size: 14 * k, color: Colors.white,
            shadows: [Shadow(color: alpha(Colors.black, 0.5), blurRadius: 4)]);
      }

      // كومبو
      if (s.crazy && s.combo[i] > 0 && s.combo[i] % 3 != 0) {
        for (var d = 0; d < 3; d++) {
          canvas.drawCircle(
            Offset((d - 1) * 9 * k, 44 * k),
            3 * k,
            Paint()..color = d < s.combo[i] % 3 ? const Color(0xFFFF9F1C) : alpha(Colors.black, 0.18),
          );
        }
      }
    });
  }

  // ------------------------------------------------------------ الوقت (المجنون)

  void _timer(Canvas canvas, Size size, double k) {
    final w = size.width, h = size.height;
    final left = _PigeonState.roundTime - s.elapsed;
    final f = clamp01(left / _PigeonState.roundTime);
    final bar = Rect.fromLTWH(w - 10 * k, h * 0.3, 5 * k, h * 0.4);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, Radius.circular(3 * k)), Paint()..color = alpha(Colors.black, 0.15));
    final fill = Rect.fromLTRB(bar.left, bar.bottom - bar.height * f, bar.right, bar.bottom);
    final hot = left <= 10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, Radius.circular(3 * k)),
      Paint()..color = hot ? const Color(0xFFFF4D6A) : Colors.white,
    );
    if (hot && s.phase == GamePhase.play) {
      final sec = left.ceil();
      final frac = left - left.floor();
      final sc = 1 + 0.25 * frac;
      for (final flip in [false, true]) {
        canvas.save();
        canvas.translate(w / 2, h / 2 + (flip ? -44 : 44) * k);
        canvas.scale(sc);
        paintText(
          canvas,
          '$sec',
          Offset.zero,
          size: (60 * k).roundToDouble(),
          color: alpha(Colors.white, 0.55),
          flip: flip,
          shadows: [Shadow(color: alpha(const Color(0xFF0B2236), 0.45), offset: const Offset(0, 3))],
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// أيقونة الحمامة بالقائمة
class PigeonIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final c = s.center(Offset.zero);
    canvas.drawCircle(c, w * 0.44, Paint()..color = alpha(const Color(0xFFBFE9FF), 0.22));
    canvas.drawCircle(
      c,
      w * 0.44,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..color = alpha(const Color(0xFFBFE9FF), 0.6),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.58, h * 0.66), width: w * 0.5, height: h * 0.14),
      Paint()
        ..color = alpha(const Color(0xFF0B2236), 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
    );
    canvas.save();
    canvas.translate(w * 0.5, h * 0.48);
    canvas.rotate(-math.pi / 2 - 0.3);
    paintBird(canvas, w * 0.15, 1, BirdKind.pigeon);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
