import 'dart:math' as math;

import 'game_model.dart';

/// قواعد الهوكي: لاعبين. الطاولة بوحدات: العرض 1 والطول [h] = 2.
/// اللاعب 0 تحت (y كبير) والـ1 فوق. اللاعب يدز مكان مضربه، والسيرفر يحرك القرص ويحسم.
///
/// [level]: 0 سهل (الطاولة العادية)، 1 متوسط (مصدّان بالنص يطلعون ويختفون)،
/// 2 صعب (المصدّات + القرص يسرّع مع كل ضربة).
class HockeyModel extends GameModel {
  HockeyModel({required super.players, required super.crazy, required super.seed, int level = 0}) : level = level.clamp(0, 2) {
    _resetPositions(-1);
  }

  HockeyModel.restore(super.j)
      : padX = _l(j['px']),
        padY = _l(j['py']),
        padVx = _l(j['pvx']),
        padVy = _l(j['pvy']),
        hasT = [for (final v in j['ht'] as List) v == true],
        tx = _l(j['tx']),
        ty = _l(j['ty']),
        puckX = (j['ux'] as num).toDouble(),
        puckY = (j['uy'] as num).toDouble(),
        puckVx = (j['uvx'] as num).toDouble(),
        puckVy = (j['uvy'] as num).toDouble(),
        goals = [for (final v in j['goals'] as List) v as int],
        lastScorer = j['ls'] as int,
        goalUntil = (j['gu'] as num).toDouble(),
        startAt = (j['start'] as num).toDouble(),
        win = j['win'] as int,
        finished = j['fin'] == true,
        level = (j['lv'] as int?) ?? 0,
        super.restore();

  static List<double> _l(dynamic v) => [for (final x in v as List) (x as num).toDouble()];

  static const target = 7;
  static const countdown = 2.6;
  static const h = 2.0;
  static const rp = 0.085; // نصف قطر المضرب
  static const rk = 0.052; // نصف قطر القرص
  static const gw = 0.19; // نص عرض المرمى
  static const maxSpeed = 3.6;

  @override
  String get id => 'hockey';
  @override
  int get tickHz => 30;
  @override
  int get localHz => 60;

  final int level;

  /// المصدّات (المتوسط والصعب): دائرتين بنص الطاولة، تظهر 5 ثواني وتختفي 3 بالتناوب
  static const bumpR = 0.075;
  static const bumpers = [(0.27, h / 2), (0.73, h / 2)];
  static const bumpCycle = 8.0, bumpOnFor = 5.0;
  bool get bumpOn => level >= 1 && !counting && ((time - startAt) % bumpCycle) < bumpOnFor;

  List<double> padX = [0.5, 0.5], padY = [0, 0], padVx = [0, 0], padVy = [0, 0];
  List<bool> hasT = [false, false];
  List<double> tx = [0, 0], ty = [0, 0];
  double puckX = 0.5, puckY = h / 2, puckVx = 0, puckVy = 0;
  List<int> goals = [0, 0];
  int lastScorer = -1;
  double goalUntil = 0;
  double startAt = countdown;
  int win = -1;
  bool finished = false;
  double _lastWall = -1;

  bool get counting => time < startAt;

  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => goals;

  void _resetPositions(int serveTo) {
    padX = [0.5, 0.5];
    padY = [h - h * 0.18, h * 0.18];
    padVx = [0, 0];
    padVy = [0, 0];
    hasT = [false, false];
    puckX = 0.5;
    puckY = h / 2 + (serveTo == 0 ? h * 0.1 : (serveTo == 1 ? -h * 0.1 : 0.0));
    puckVx = 0;
    puckVy = 0;
  }

  double cx(double x) => x.clamp(rp, 1 - rp).toDouble();
  double cy(int p, double y) =>
      (p == 0 ? y.clamp(h / 2 + rp * 0.6, h - rp) : y.clamp(rp, h / 2 - rp * 0.6)).toDouble();

  @override
  void input(int player, Map<String, dynamic> d) {
    if (player < 0 || player > 1 || finished) return;
    switch (d['m']) {
      case 'pad':
        final x = d['x'], y = d['y'];
        if (x is! num || y is! num || !x.isFinite || !y.isFinite) return;
        tx[player] = x.toDouble();
        ty[player] = y.toDouble();
        hasT[player] = true;
      case 'rel':
        hasT[player] = false;
    }
  }

  @override
  void step(double dt) {
    final steps = (dt * 120).round().clamp(1, 8);
    final sdt = dt / steps;
    for (var i = 0; i < steps; i++) {
      _movePads(sdt);
      if (finished || counting || time < goalUntil) continue;
      if (_movePuck(sdt)) return;
    }
  }

  void _movePads(double sdt) {
    for (var p = 0; p < 2; p++) {
      if (!hasT[p]) {
        final f = math.exp(-20 * sdt);
        padVx[p] *= f;
        padVy[p] *= f;
        continue;
      }
      final nx = cx(tx[p]), ny = cy(p, ty[p]);
      var dx = nx - padX[p], dy = ny - padY[p];
      final dist = math.sqrt(dx * dx + dy * dy);
      final maxStep = 14 * sdt;
      if (dist > maxStep) {
        dx = dx / dist * maxStep;
        dy = dy / dist * maxStep;
      }
      var vx = dx / sdt, vy = dy / sdt;
      final v = math.sqrt(vx * vx + vy * vy);
      if (v > 7) {
        vx = vx / v * 7;
        vy = vy / v * 7;
      }
      padVx[p] += (vx - padVx[p]) * 0.25;
      padVy[p] += (vy - padVy[p]) * 0.25;
      padX[p] += dx;
      padY[p] += dy;
    }
  }

  void _wall() {
    final sp = math.sqrt(puckVx * puckVx + puckVy * puckVy);
    if (time - _lastWall > 0.08 && sp > 0.6) {
      emit('wall');
      _lastWall = time;
    }
  }

  /// يرجع true إذا صار هدف (نوقف التكّة)
  bool _movePuck(double sdt) {
    puckX += puckVx * sdt;
    puckY += puckVy * sdt;
    var x = puckX, y = puckY, vx = puckVx, vy = puckVy;
    final inGoal = (x - 0.5).abs() < gw - rk * 0.3;
    if (x < rk) {
      x = rk;
      vx = vx.abs() * 0.9;
      _wall();
    } else if (x > 1 - rk) {
      x = 1 - rk;
      vx = -vx.abs() * 0.9;
      _wall();
    }
    if (y < rk) {
      if (inGoal) {
        if (y < -rk) {
          _goal(0);
          return true;
        }
      } else {
        y = rk;
        vy = vy.abs() * 0.9;
        _wall();
      }
    } else if (y > h - rk) {
      if (inGoal) {
        if (y > h + rk) {
          _goal(1);
          return true;
        }
      } else {
        y = h - rk;
        vy = -vy.abs() * 0.9;
        _wall();
      }
    }
    puckX = x;
    puckY = y;
    puckVx = vx;
    puckVy = vy;

    if (bumpOn) {
      for (final bp in bumpers) {
        final dx = puckX - bp.$1, dy = puckY - bp.$2;
        final dist = math.sqrt(dx * dx + dy * dy);
        const minD = bumpR + rk;
        if (dist < minD && dist > 0.0001) {
          final nx = dx / dist, ny = dy / dist;
          puckX = bp.$1 + nx * minD;
          puckY = bp.$2 + ny * minD;
          final vn = puckVx * nx + puckVy * ny;
          if (vn < 0) {
            puckVx -= nx * 1.9 * vn;
            puckVy -= ny * 1.9 * vn;
            _wall();
          }
        }
      }
    }
    for (var p = 0; p < 2; p++) {
      final dx = puckX - padX[p], dy = puckY - padY[p];
      final dist = math.sqrt(dx * dx + dy * dy);
      const minD = rp + rk;
      if (dist < minD && dist > 0.0001) {
        final nx = dx / dist, ny = dy / dist;
        puckX = padX[p] + nx * minD;
        puckY = padY[p] + ny * minD;
        final rx = puckVx - padVx[p], ry = puckVy - padVy[p];
        final vn = rx * nx + ry * ny;
        if (vn < 0) {
          puckVx -= nx * 1.85 * vn;
          puckVy -= ny * 1.85 * vn;
          if (level == 2) {
            // الصعب: القرص يسرّع مع كل ضربة
            puckVx *= 1.07;
            puckVy *= 1.07;
          }
          final impact = -vn;
          if (impact > 0.4) emit('hit', {'i': double.parse(impact.toStringAsFixed(2))});
        }
      }
    }
    final sp = math.sqrt(puckVx * puckVx + puckVy * puckVy);
    final cap = level == 2 ? maxSpeed * 1.2 : maxSpeed;
    if (sp > cap) {
      puckVx = puckVx / sp * cap;
      puckVy = puckVy / sp * cap;
    }
    final damp = math.exp(-0.28 * sdt);
    puckVx *= damp;
    puckVy *= damp;
    return false;
  }

  void _goal(int scorer) {
    goals[scorer]++;
    lastScorer = scorer;
    emit('goal', {'p': scorer});
    if (goals[scorer] >= target) {
      win = scorer;
      finished = true;
      emit('win', {'p': scorer});
      return;
    }
    goalUntil = time + 1.1;
    final conceder = 1 - scorer;
    puckX = 0.5;
    puckY = h / 2 + (conceder == 0 ? h * 0.1 : -h * 0.1);
    puckVx = 0;
    puckVy = 0;
  }

  @override
  void forfeit(int player) {
    if (finished || player < 0 || player > 1) return;
    win = 1 - player;
    finished = true;
    emit('win', {'p': win, 'forfeit': true});
  }

  @override
  void again() {
    goals = [0, 0];
    win = -1;
    finished = false;
    lastScorer = -1;
    goalUntil = 0;
    _resetPositions(-1);
    startAt = time + countdown;
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'px': padX,
        'py': padY,
        'pvx': padVx,
        'pvy': padVy,
        'ht': hasT,
        'tx': tx,
        'ty': ty,
        'ux': puckX,
        'uy': puckY,
        'uvx': puckVx,
        'uvy': puckVy,
        'goals': goals,
        'ls': lastScorer,
        'gu': goalUntil,
        'start': startAt,
        'win': win,
        'fin': finished,
        'lv': level,
      };
}
