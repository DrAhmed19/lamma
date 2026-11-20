import 'dart:math' as math;

import 'game_model.dart';

/// أنواع الطيور والقوى (أرقام حتى تنحفظ)
const kPigeon = 0, kGold = 1, kCrow = 2;
const kFire = 0, kTriple = 1, kFreeze = 2;

class PBird {
  PBird(this.id, this.kind, this.x, this.y, this.tx, this.ty, this.seed, {this.small = false});
  final int id, kind;
  final bool small;
  double x, y, vx = 0, vy = 0, tx, ty;
  final double seed;
  double flap = 0, heading = 0, retargetAt = 0, leaveAt = 1e18, glideUntil = 0, nextGlideAt = 0;
  bool leaving = false, passer = false, hit = false;
  double hitAt = 0, altAtHit = 0, spin = 0;

  List<dynamic> toJson() => [
        id, kind, small ? 1 : 0, x, y, vx, vy, tx, ty, seed, flap, heading, retargetAt, leaveAt,
        glideUntil, nextGlideAt, leaving ? 1 : 0, passer ? 1 : 0, hit ? 1 : 0, hitAt, altAtHit, spin,
      ];

  static double _d(dynamic v) => (v as num).toDouble();

  factory PBird.fromJson(List j) {
    final b = PBird(j[0] as int, j[1] as int, _d(j[3]), _d(j[4]), _d(j[7]), _d(j[8]), _d(j[9]), small: j[2] == 1);
    b.vx = _d(j[5]);
    b.vy = _d(j[6]);
    b.flap = _d(j[10]);
    b.heading = _d(j[11]);
    b.retargetAt = _d(j[12]);
    b.leaveAt = _d(j[13]);
    b.glideUntil = _d(j[14]);
    b.nextGlideAt = _d(j[15]);
    b.leaving = j[16] == 1;
    b.passer = j[17] == 1;
    b.hit = j[18] == 1;
    b.hitAt = _d(j[19]);
    b.altAtHit = _d(j[20]);
    b.spin = _d(j[21]);
    return b;
  }
}

class PStone {
  PStone(this.id, this.x, this.y, this.vx, this.vy, this.owner, this.range, this.group, {this.fire = false});
  final int id, owner, group;
  final bool fire;
  final double range;
  double x, y, vx, vy, dist = 0;
  bool dead = false;
  final List<int> hits = [];

  List<dynamic> toJson() => [id, x, y, vx, vy, owner, range, group, fire ? 1 : 0, dist, dead ? 1 : 0, hits];

  factory PStone.fromJson(List j) {
    double d(dynamic v) => (v as num).toDouble();
    final s = PStone(j[0] as int, d(j[1]), d(j[2]), d(j[3]), d(j[4]), j[5] as int, d(j[6]), j[7] as int, fire: j[8] == 1);
    s.dist = d(j[9]);
    s.dead = j[10] == 1;
    s.hits.addAll([for (final v in j[11] as List) v as int]);
    return s;
  }
}

class PCrate {
  PCrate(this.id, this.x, this.y, this.vx, this.vy, this.kind, this.born);
  final int id, kind;
  final double born;
  double x, y, vx, vy;
  bool dead = false;

  List<dynamic> toJson() => [id, x, y, vx, vy, kind, born];

  factory PCrate.fromJson(List j) {
    double d(dynamic v) => (v as num).toDouble();
    return PCrate(j[0] as int, d(j[1]), d(j[2]), d(j[3]), d(j[4]), j[5] as int, d(j[6]));
  }
}

/// قواعد الحمامة: 2-4 لاعبين. العالم بوحدات ([worldW] × [worldH])، والسيرفر يحرك الطيور
/// والحجارة ويحسم الإصابات. اللاعب يدز بس "shot" (اتجاه وقوة السحبة).
/// اللاعبين 0,2 تحت و1,3 فوق (حسب الترتيب بالشاشة الواحدة).
class PigeonModel extends GameModel {
  PigeonModel({
    required super.players,
    required super.crazy,
    required super.seed,
    this.worldW = 400,
    this.worldH = 800,
  })  : score = List.filled(players, 0),
        combo = List.filled(players, 0),
        power = List.filled(players, -1),
        powerShots = List.filled(players, 0),
        readyAt = List.filled(players, 0),
        shotAt = List.filled(players, -10),
        scoredAt = List.filled(players, -10),
        frozenUntil = List.filled(players, 0),
        out = List.filled(players, false) {
    respawnAt = 0.3;
  }

  PigeonModel.restore(super.j)
      : worldW = (j['ww'] as num).toDouble(),
        worldH = (j['wh'] as num).toDouble(),
        score = _ints(j['score']),
        combo = _ints(j['combo']),
        power = _ints(j['power']),
        powerShots = _ints(j['pshots']),
        readyAt = _dbls(j['ready']),
        shotAt = _dbls(j['shot']),
        scoredAt = _dbls(j['scored']),
        frozenUntil = _dbls(j['frozen']),
        out = [for (final v in j['out'] as List) v == true],
        birds = [for (final b in j['birds'] as List) PBird.fromJson(b as List)],
        stones = [for (final s in j['stones'] as List) PStone.fromJson(s as List)],
        crates = [for (final c in j['crates'] as List) PCrate.fromJson(c as List)],
        groupHit = {for (final v in j['gh'] as List) v as int},
        nextId = j['nid'] as int,
        shotSeq = j['seq'] as int,
        firstPigeon = j['first'] == true,
        started = j['started'] == true,
        startAt = (j['start'] as num).toDouble(),
        playStart = (j['ps'] as num).toDouble(),
        overAt = (j['oa'] as num).toDouble(),
        respawnAt = (j['resp'] as num).toDouble(),
        nextCrowAt = (j['crow'] as num).toDouble(),
        nextFlockAt = (j['flock'] as num).toDouble(),
        nextCrateAt = (j['crate'] as num).toDouble(),
        nextCooAt = (j['coo'] as num).toDouble(),
        lastTick = j['lt'] as int,
        win = j['win'] as int,
        finished = j['fin'] == true,
        super.restore();

  static List<int> _ints(dynamic v) => [for (final x in v as List) x as int];
  static List<double> _dbls(dynamic v) => [for (final x in v as List) (x as num).toDouble()];

  static const target = 10;
  static const roundTime = 60.0;
  static const reload = 0.42;
  static const countdown = 2.6;

  final double worldW, worldH;

  @override
  String get id => 'pigeon';
  @override
  int get tickHz => 30;
  @override
  int get localHz => 60;

  List<int> score, combo, power, powerShots;
  List<double> readyAt, shotAt, scoredAt, frozenUntil;
  List<bool> out;
  List<PBird> birds = [];
  List<PStone> stones = [];
  List<PCrate> crates = [];
  Set<int> groupHit = {};
  int nextId = 1, shotSeq = 0, lastTick = -1;
  bool firstPigeon = true, started = false, finished = false;
  double startAt = countdown, playStart = 0, overAt = 0;
  double respawnAt = 0.3, nextCrowAt = 0, nextFlockAt = 0, nextCrateAt = 0, nextCooAt = 2;
  int win = -1;

  bool get counting => !started;
  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => score;

  int get total => score.fold(0, (a, b) => a + b);
  double get skyTop => worldH * 0.22;
  double get skyBottom => worldH * 0.78;

  double get elapsed {
    if (!started) return 0;
    final now = finished ? overAt : time;
    return math.min(roundTime, now - playStart);
  }

  // ------------------------------------------------------------ المقاعد

  double get pad => math.min(80.0, worldH * 0.1);
  bool isTop(int p) => p.isOdd;

  /// مكان المصيادة
  (double, double) anchor(int p) {
    if (players == 2) return (worldW / 2, p == 0 ? worldH - pad : pad);
    switch (p) {
      case 0:
        return (worldW * 0.7, worldH - pad);
      case 1:
        return (worldW * 0.3, pad);
      case 2:
        return (worldW * 0.3, worldH - pad);
      default:
        return (worldW * 0.7, pad);
    }
  }

  /// منطقة اللمس: (يسار، فوق، عرض، طول)
  (double, double, double, double) zone(int p) {
    final w = worldW, h = worldH;
    if (players == 2) return (0, p == 0 ? h / 2 : 0, w, h / 2);
    switch (p) {
      case 0:
        return (w / 2, h / 2, w / 2, h / 2);
      case 1:
        return (0, 0, w / 2, h / 2);
      case 2:
        return (0, h / 2, w / 2, h / 2);
      default:
        return (w / 2, 0, w / 2, h / 2);
    }
  }

  // ------------------------------------------------------------ الطيور

  (double, double) _randomTarget() {
    const m = 44.0;
    return (m + rng.next() * (worldW - 2 * m), skyTop + rng.next() * (skyBottom - skyTop));
  }

  double speedOf(PBird b) {
    final grow = crazy ? elapsed * 2.2 + total * 4 : total * 10.0;
    var base = math.min(130 + grow, 300.0);
    if (b.small) base *= 1.75;
    return switch (b.kind) {
      kGold => base * 1.35,
      kCrow => base * 1.05,
      _ => base,
    };
  }

  /// الارتفاع من 0 (واطي) لـ 1 (عالي)
  double alt(PBird b) {
    if (b.hit) return math.max(0.0, b.altAtHit - (time - b.hitAt) * 1.4);
    return 0.5 + 0.5 * math.sin(time * 0.8 + b.seed);
  }

  double birdScale(PBird b) => 0.8 + 0.34 * alt(b);
  static double birdRadius(int kind) => kind == kCrow ? 25.0 : 23.0;
  double hitRadius(PBird b) => birdRadius(b.kind) * (b.small ? 0.7 : 1) * birdScale(b);

  double flapOf(PBird b) {
    if (!b.hit && time < b.glideUntil) return 0.95;
    return 0.5 + 0.5 * math.sin(b.flap);
  }

  PBird _spawn(int kind, {bool small = false, (double, double)? from, (double, double)? to}) {
    final left = rng.nextBool();
    final f = from ?? (left ? -40.0 : worldW + 40, skyTop + rng.next() * (skyBottom - skyTop));
    final t = to ?? _randomTarget();
    final b = PBird(nextId++, kind, f.$1, f.$2, t.$1, t.$2, rng.next() * 10, small: small);
    final dx = t.$1 - f.$1, dy = t.$2 - f.$2;
    final d = math.sqrt(dx * dx + dy * dy);
    final sp = speedOf(b);
    b.vx = d > 0 ? dx / d * sp : sp;
    b.vy = d > 0 ? dy / d * sp : 0;
    b.heading = math.atan2(b.vy, b.vx);
    b.retargetAt = time + 2 + rng.next() * 1.5;
    b.nextGlideAt = time + 1.5 + rng.next() * 2;
    birds.add(b);
    return b;
  }

  void _spawnFlock() {
    final fromLeft = rng.nextBool();
    final y = skyTop + (0.2 + rng.next() * 0.6) * (skyBottom - skyTop);
    for (var i = 0; i < 4; i++) {
      final fx = fromLeft ? -40.0 - i * 34 : worldW + 40 + i * 34;
      final fy = y + (i.isEven ? -1 : 1) * i * 16;
      final tx = fromLeft ? worldW + 200 : -200.0;
      final ty = fy + (rng.next() - 0.5) * 120;
      final b = _spawn(kPigeon, small: true, from: (fx, fy), to: (tx, ty));
      b.passer = true;
      b.leaving = true;
    }
  }

  void _spawnCrate() {
    final x = 60 + rng.next() * (worldW - 120);
    final y = skyTop + rng.next() * (skyBottom - skyTop);
    final a = rng.next() * math.pi * 2;
    crates.add(PCrate(nextId++, x, y, math.cos(a) * 24, math.sin(a) * 24, rng.nextInt(3), time));
  }

  // ------------------------------------------------------------ التحديث

  @override
  void step(double dt) {
    if (!started && time >= startAt) {
      started = true;
      playStart = time;
      nextCrowAt = time + 7;
      nextFlockAt = time + 10;
      nextCrateAt = time + 5;
    }

    if (!finished) {
      final hasMain = birds.any((b) => b.kind != kCrow && !b.small);
      if (!hasMain && time >= respawnAt) {
        final gold = crazy && !firstPigeon && rng.next() < 0.2;
        firstPigeon = false;
        _spawn(gold ? kGold : kPigeon);
        emit('spawn');
      }
      if (time >= nextCooAt) {
        if (birds.any((b) => !b.hit && b.kind != kCrow)) emit('coo');
        nextCooAt = time + 6 + rng.next() * 6;
      }
    }

    if (started && !finished && crazy) {
      if (elapsed >= roundTime) {
        _endByTime();
        return;
      }
      final left = (roundTime - elapsed).ceil();
      if (left <= 10 && left != lastTick) {
        lastTick = left;
        emit('tick');
      }
      if (total >= 2 && time >= nextCrowAt && !birds.any((b) => b.kind == kCrow)) {
        final c = _spawn(kCrow);
        c.leaveAt = time + 5 + rng.next() * 2.5;
        nextCrowAt = time + 8 + rng.next() * 6;
      }
      if (time >= nextFlockAt) {
        _spawnFlock();
        emit('flock');
        nextFlockAt = time + 12 + rng.next() * 7;
      }
      if (time >= nextCrateAt) {
        if (crates.isEmpty) {
          _spawnCrate();
          emit('crate');
        }
        nextCrateAt = time + 9 + rng.next() * 5;
      }
    }

    _updateBirds(dt);
    _updateCrates(dt);
    if (started && !finished) {
      _updateStones(dt);
      stones.removeWhere((s) => s.dead);
    } else {
      stones.clear();
    }
  }

  void _updateBirds(double dt) {
    final w = worldW;
    for (final b in birds) {
      if (b.hit) {
        b.flap += dt * 3;
        b.spin += dt * 9;
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        final f = 1 - math.min(1.0, dt * 3);
        b.vx *= f;
        b.vy *= f;
        continue;
      }
      final gliding = time < b.glideUntil;
      if (!gliding && time >= b.nextGlideAt && !b.passer) {
        b.glideUntil = time + 0.6 + rng.next() * 0.7;
        b.nextGlideAt = b.glideUntil + 1.8 + rng.next() * 2.5;
      }
      final sp = speedOf(b) * (gliding ? 0.85 : 1);
      if (!gliding) b.flap += dt * (12 + sp / 40);

      if (b.kind == kCrow && !b.leaving && time >= b.leaveAt) {
        b.leaving = true;
        b.tx = b.x < w / 2 ? -140 : w + 140;
        b.ty = b.y;
      }
      final dd = math.sqrt((b.tx - b.x) * (b.tx - b.x) + (b.ty - b.y) * (b.ty - b.y));
      if (!b.leaving && (dd < 30 || time >= b.retargetAt)) {
        final t = _randomTarget();
        b.tx = t.$1;
        b.ty = t.$2;
        b.retargetAt = time + 1.3 + rng.next() * 1.8;
      }
      final dx = b.tx - b.x, dy = b.ty - b.y;
      final d = math.sqrt(dx * dx + dy * dy);
      final dvx = d > 0 ? dx / d * sp : b.vx, dvy = d > 0 ? dy / d * sp : b.vy;
      final k = (dt * (b.passer ? 4 : 2.2)).clamp(0.0, 1.0);
      b.vx += (dvx - b.vx) * k;
      b.vy += (dvy - b.vy) * k;
      final v = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final px = v > 0 ? -b.vy / v : 0.0, py = v > 0 ? b.vx / v : 0.0;
      final wob = (b.passer ? 14 : 42) * math.sin(time * 5 + b.seed) * dt;
      b.x += b.vx * dt + px * wob;
      b.y += b.vy * dt + py * wob;
      b.heading = math.atan2(b.vy, b.vx);
    }
    birds.removeWhere((b) => (b.hit && time - b.hitAt > 0.8) || (b.leaving && (b.x < -160 || b.x > w + 160)));
  }

  void _updateCrates(double dt) {
    for (final c in crates) {
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      if (c.x < 30 || c.x > worldW - 30) c.vx = -c.vx;
      if (c.y < skyTop || c.y > skyBottom) c.vy = -c.vy;
      if (time - c.born > 7.5) c.dead = true;
    }
    crates.removeWhere((c) => c.dead);
  }

  void _updateStones(double dt) {
    const sr = 6.0;
    const steps = 3;
    for (final s in stones) {
      final sp = math.sqrt(s.vx * s.vx + s.vy * s.vy);
      for (var i = 0; i < steps && !s.dead; i++) {
        s.x += s.vx * (dt / steps);
        s.y += s.vy * (dt / steps);
        s.dist += sp * dt / steps;
        if (s.dist >= s.range) {
          s.dead = true;
          emit('land', {'x': s.x, 'y': s.y});
          break;
        }
        for (final c in crates) {
          if (!c.dead && _dist(s.x, s.y, c.x, c.y) < 18 + sr) {
            _takeCrate(c, s.owner);
            groupHit.add(s.group);
            if (!s.fire) s.dead = true;
          }
        }
        if (s.dead) break;
        for (final b in birds) {
          if (b.hit || s.hits.contains(b.id)) continue;
          if (_dist(s.x, s.y, b.x, b.y) < hitRadius(b) + sr) {
            s.hits.add(b.id);
            groupHit.add(s.group);
            _hitBird(b, s);
            if (finished) return;
            if (!s.fire) {
              s.dead = true;
              break;
            }
          }
        }
        if (finished) return;
      }
      if (!s.dead && (s.x < -40 || s.x > worldW + 40 || s.y < -40 || s.y > worldH + 40)) s.dead = true;
    }

    // بالمجنون الحجار تتصادم بالجو
    if (crazy) {
      for (var i = 0; i < stones.length; i++) {
        final a = stones[i];
        if (a.dead) continue;
        for (var j = i + 1; j < stones.length; j++) {
          final b = stones[j];
          if (b.dead || a.owner == b.owner) continue;
          if (_dist(a.x, a.y, b.x, b.y) < sr * 2.4) {
            a.dead = b.dead = true;
            emit('clack', {'x': (a.x + b.x) / 2, 'y': (a.y + b.y) / 2});
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

  static double _dist(double ax, double ay, double bx, double by) {
    final dx = ax - bx, dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _hitBird(PBird b, PStone s) {
    final p = s.owner;
    b.altAtHit = alt(b);
    b.hit = true;
    b.hitAt = time;
    b.vx = b.vx * 0.25 + s.vx * 0.1;
    b.vy = b.vy * 0.25 + s.vy * 0.1;
    var pts = 0;
    var bonus = false;
    if (b.kind == kCrow) {
      score[p] = math.max(0, score[p] - 1);
      combo[p] = 0;
      pts = -1;
    } else {
      pts = b.kind == kGold ? 2 : 1;
      score[p] += pts;
      scoredAt[p] = time;
      if (!b.small) respawnAt = time + 0.9;
      if (crazy) {
        combo[p]++;
        if (combo[p] % 3 == 0) {
          score[p]++;
          bonus = true;
        }
      }
    }
    emit('hit', {'p': p, 'k': b.kind, 'x': b.x, 'y': b.y, 'pts': pts, 'bonus': bonus});
    if (!crazy && score[p] >= target) _finish(p);
  }

  void _takeCrate(PCrate c, int p) {
    c.dead = true;
    switch (c.kind) {
      case kFire:
      case kTriple:
        power[p] = c.kind;
        powerShots[p] = 3;
      case kFreeze:
        for (var i = 0; i < players; i++) {
          if (i == p) continue;
          frozenUntil[i] = time + 3;
          readyAt[i] = math.max(readyAt[i], time + 3);
        }
    }
    emit('crate_taken', {'p': p, 'k': c.kind, 'x': c.x, 'y': c.y});
  }

  void _finish(int w) {
    win = w;
    overAt = time;
    finished = true;
    emit('win', {'p': w});
  }

  void _endByTime() {
    final best = score.reduce(math.max);
    final tops = [for (var i = 0; i < players; i++) if (score[i] == best) i];
    _finish(tops.length == 1 ? tops.first : -1);
  }

  // ------------------------------------------------------------ الحركات

  bool frozen(int p) => time < frozenUntil[p];

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'shot' || !started || finished || player < 0 || player >= players) return;
    if (out[player] || time < readyAt[player] || frozen(player)) return;
    final dx = d['dx'], dy = d['dy'], pwr = d['pw'];
    if (dx is! num || dy is! num || pwr is! num) return;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6 || !len.isFinite) return;
    final ux = dx / len, uy = dy / len;
    final fy = isTop(player) ? 1.0 : -1.0;
    if (uy * fy < 0.05) return;
    final pw = pwr.toDouble().clamp(0.0, 1.0);
    final speed = worldH * (0.6 + 0.9 * pw);
    final range = worldH * (0.5 + 0.75 * pw);
    final group = shotSeq++;
    final kind = power[player];
    final angles = kind == kTriple ? const [-0.2, 0.0, 0.2] : const [0.0];
    final a0 = anchor(player);
    for (final a in angles) {
      final vx = ux * math.cos(a) - uy * math.sin(a);
      final vy = ux * math.sin(a) + uy * math.cos(a);
      stones.add(PStone(nextId++, a0.$1 + vx * 24, a0.$2 + vy * 24, vx * speed, vy * speed, player, range, group,
          fire: kind == kFire));
    }
    if (kind >= 0) {
      powerShots[player]--;
      if (powerShots[player] <= 0) power[player] = -1;
    }
    readyAt[player] = time + reload;
    shotAt[player] = time;
    emit('shot', {'p': player});
  }

  @override
  void forfeit(int player) {
    if (finished || player < 0 || player >= players || out[player]) return;
    out[player] = true;
    final alive = [for (var i = 0; i < players; i++) if (!out[i]) i];
    if (alive.length == 1) _finish(alive.first);
  }

  @override
  void again() {
    score = List.filled(players, 0);
    combo = List.filled(players, 0);
    power = List.filled(players, -1);
    powerShots = List.filled(players, 0);
    readyAt = List.filled(players, 0);
    shotAt = List.filled(players, -10);
    scoredAt = List.filled(players, -10);
    frozenUntil = List.filled(players, 0);
    birds = [];
    stones = [];
    crates = [];
    groupHit = {};
    firstPigeon = true;
    started = false;
    finished = false;
    win = -1;
    lastTick = -1;
    startAt = time + countdown;
    respawnAt = time + 0.3;
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'ww': worldW,
        'wh': worldH,
        'score': score,
        'combo': combo,
        'power': power,
        'pshots': powerShots,
        'ready': readyAt,
        'shot': shotAt,
        'scored': scoredAt,
        'frozen': frozenUntil,
        'out': out,
        'birds': [for (final b in birds) b.toJson()],
        'stones': [for (final s in stones) s.toJson()],
        'crates': [for (final c in crates) c.toJson()],
        'gh': groupHit.toList(),
        'nid': nextId,
        'seq': shotSeq,
        'first': firstPigeon,
        'started': started,
        'start': startAt,
        'ps': playStart,
        'oa': overAt,
        'resp': respawnAt,
        'crow': nextCrowAt,
        'flock': nextFlockAt,
        'crate': nextCrateAt,
        'coo': nextCooAt,
        'lt': lastTick,
        'win': win,
        'fin': finished,
      };
}
