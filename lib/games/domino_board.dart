import 'dart:math' as math;
import 'dart:ui';

import '../logic/domino_logic.dart';

/// تخطيط طاولة الدومينو بوحدات العالم (عرض القطعة = 1، طولها = 2).
///
/// - أول قطعة بالنص. الدبل ينحط بالعرض (عمودي على اتجاه السلسلة).
/// - كل طرف يمشي مستقيم لحد حافة الطاولة وبعدين يلف (مثل الأفعى) ويرجع بالعكس.
/// - الخمسات ويا سبينر: كل طرف ياخذ ربع الطاولة (مروحة): اليمين ينزل يمين، اليسار يصعد يسار،
///   فوق يلف يمين، وجوه يلف يسار، حتى ما يركبون على بعض.
/// - بدون سبينر: اليمين ياخذ النص الجوه واليسار النص الفوق.
/// - إذا السلسلة ما كفّتها الطاولة، الوحدة تصغر ([fitBoard]) والطاولة تتمركز.
class BoardTile {
  BoardTile(this.rect, this.a, this.b, this.t, this.arm);

  /// المستطيل بوحدات العالم
  final Rect rect;

  /// الرقم اللي بأول نص (يسار أو فوق) والثاني
  final int a, b;
  final int t;
  final String arm;
}

class BoardLayout {
  BoardLayout(this.tiles, this.ghosts, this.bounds, [this.dirs = const {}]);
  final List<BoardTile> tiles;

  /// وين تنحط القطعة الجاية بكل طرف مفتوح (للحلقات واللمس)، بوحدات العالم
  final Map<String, Rect> ghosts;

  /// اتجاه كل طرف (للبرا): حتى نعرف أي نص من القطعة الجاية قريب
  final Map<String, Offset> dirs;
  final Rect bounds;

  /// القطعة t لو انحطت بطرف arm: (الرقم اللي بأول نص (يسار/فوق)، والثاني)
  (int, int) faceAt(String arm, int t, int end) {
    final a = DominoModel.tileA[t], b = DominoModel.tileB[t];
    final near = a == end ? a : b, far = a == end ? b : a;
    final d = dirs[arm] ?? const Offset(1, 0);
    return d.dx + d.dy > 0 ? (near, far) : (far, near);
  }
}

/// الكاميرا: كم بكسل لكل وحدة، ووين نص العالم بالشاشة
class BoardCam {
  const BoardCam(this.u, this.center);
  final double u;
  final Offset center;

  Offset toScreen(Offset w, Size size) => Offset(size.width / 2 + (w.dx - center.dx) * u, size.height / 2 + (w.dy - center.dy) * u);
  Rect rectToScreen(Rect r, Size size) => Rect.fromPoints(toScreen(r.topLeft, size), toScreen(r.bottomRight, size));
  Offset toWorld(Offset s, Size size) => Offset((s.dx - size.width / 2) / u + center.dx, (s.dy - size.height / 2) / u + center.dy);

  static BoardCam lerp(BoardCam a, BoardCam b, double k) => BoardCam(a.u + (b.u - a.u) * k, Offset.lerp(a.center, b.center, k)!);
}

/// مقطع من طرف: اتجاه، وحد (null = قطعة وحدة بس، للّفّة)
class _Leg {
  const _Leg(this.dx, this.dy, this.limit);
  final int dx, dy;
  final double? limit;
}

/// التخطيط بحدود نص عرض ونص ارتفاع معينة (بوحدات العالم)
BoardLayout layoutBoard(DominoModel m, double hw, double hh) {
  final tiles = <BoardTile>[];
  final ghosts = <String, Rect>{};
  final dirs = <String, Offset>{};
  if (m.chainLen == 0) {
    return BoardLayout(tiles, {'r': Rect.fromCenter(center: Offset.zero, width: 2, height: 1)}, Rect.fromCenter(center: Offset.zero, width: 2, height: 1));
  }
  final t0 = m.chainTile(m.anchor);
  final dbl0 = DominoModel.isDouble(t0);
  final pin = m.spinner;
  // أول قطعة: الدبل بالعرض (عمودي)، غيره أفقي
  final r0 = dbl0 ? Rect.fromCenter(center: Offset.zero, width: 1, height: 2) : Rect.fromCenter(center: Offset.zero, width: 2, height: 1);
  tiles.add(BoardTile(r0, m.chainL(m.anchor), m.chainR(m.anchor), t0, 'c'));

  const c = 1.1; // مسافة عن الخط النص (الدبل بالعرض بفرع فوق/جوه عرضه 2) حتى ما تركب الأطراف على بعض
  List<_Leg> legsFor(String arm) {
    // الأفعى: مقطع طويل، لفّة قطعة وحدة، مقطع بالعكس...
    List<_Leg> snake(int dx, int dy, double far, double back, int sx, int sy) => [
          for (var i = 0; i < 40; i++) ...[
            _Leg(dx, dy, far),
            _Leg(sx, sy, null),
            _Leg(-dx, -dy, back),
            _Leg(sx, sy, null),
          ],
        ];
    switch (arm) {
      case 'r':
        return snake(1, 0, hw, pin ? c : -hw, 0, 1);
      case 'l':
        return snake(-1, 0, -hw, pin ? -c : hw, 0, -1);
      case 'u':
        return [const _Leg(0, -1, null), _Leg(0, -1, -hh), ...snake(1, 0, hw, c, 0, 1)];
      default:
        return [const _Leg(0, 1, null), _Leg(0, 1, hh), ...snake(-1, 0, -hw, -c, 0, -1)];
    }
  }

  void walk(String arm, List<(int t, int near, int far)> list, Offset start, double halfAcross) {
    final legs = legsFor(arm);
    var p = start; // نهاية آخر قطعة (على خطها النص)
    var li = 0;
    var dx = legs[0].dx, dy = legs[0].dy;
    var lastAcross = halfAcross;
    var placedInLeg = 0;
    var emptyLegs = 0;

    // ينقل المؤشر لمقطع جديد (لفّة 90 درجة من آخر مربع)
    void bend(_Leg g) {
      final back = Offset(-dx * 0.5, -dy * 0.5);
      p = p + back + Offset(g.dx * lastAcross, g.dy * lastAcross);
      dx = g.dx;
      dy = g.dy;
      placedInLeg = 0;
    }

    // نحسب مكان القطعة الجاية (طول على الاتجاه، وعرض)
    Rect place(double along, double across) {
      final centre = p + Offset(dx * along / 2, dy * along / 2);
      final w = dx != 0 ? along : across, h = dx != 0 ? across : along;
      return Rect.fromCenter(center: centre, width: w, height: h);
    }

    bool fits(double along, double? limit) {
      if (limit == null) return placedInLeg == 0;
      final end = dx != 0 ? p.dx + dx * along : p.dy + dy * along;
      return (dx + dy) > 0 ? end <= limit : end >= limit;
    }

    // أول مقطع: من حافة القطعة الأولى بنفس الاتجاه (مو لفّة)
    var first = true;
    for (var k = 0; k <= list.length; k++) {
      final ghost = k == list.length;
      final (t, near, far) = ghost ? (-1, -1, -1) : list[k];
      final dbl = !ghost && near == far;
      while (true) {
        final g = legs[li];
        final single = g.limit == null;
        final along = dbl && !single ? 1.0 : 2.0;
        if (fits(along, g.limit) || emptyLegs >= 2) {
          emptyLegs = 0;
          break;
        }
        if (placedInLeg == 0 && !single) emptyLegs++;
        li = math.min(li + 1, legs.length - 1);
        if (first && legs[li].dx == dx && legs[li].dy == dy) {
          // نفس الاتجاه (فوق/جوه بعد القطعة الأولى): بدون لفّة
          placedInLeg = 0;
        } else {
          bend(legs[li]);
        }
        first = false;
      }
      final single = legs[li].limit == null;
      final along = dbl && !single ? 1.0 : 2.0;
      final across = dbl && !single ? 2.0 : 1.0;
      final r = place(along, across);
      if (ghost) {
        ghosts[arm] = place(2, 1);
        dirs[arm] = Offset(dx.toDouble(), dy.toDouble());
        break;
      }
      // الرقم القريب بجهة القطعة اللي قبلها
      final forward = dx + dy > 0;
      tiles.add(BoardTile(r, forward ? near : far, forward ? far : near, t, arm));
      p = p + Offset(dx * along, dy * along);
      lastAcross = across / 2;
      placedInLeg++;
      first = false;
    }
  }

  final right = <(int, int, int)>[
    for (var i = m.anchor + 1; i < m.chainLen; i++) (m.chainTile(i), m.chainL(i), m.chainR(i)),
  ];
  final left = <(int, int, int)>[
    for (var i = m.anchor - 1; i >= 0; i--) (m.chainTile(i), m.chainR(i), m.chainL(i)),
  ];
  List<(int, int, int)> arm3(List<int> l) => [for (var i = 0; i + 2 < l.length; i += 3) (l[i], l[i + 1], l[i + 2])];

  final halfW = r0.width / 2, halfH = r0.height / 2;
  walk('r', right, Offset(halfW, 0), halfH);
  walk('l', left, Offset(-halfW, 0), halfH);
  if (pin && (m.crossOpen || m.up.isNotEmpty || m.dn.isNotEmpty)) {
    walk('u', arm3(m.up), Offset(0, -halfH), halfW);
    walk('d', arm3(m.dn), Offset(0, halfH), halfW);
  }
  // الأطراف المسكّرة ما إلها حلقة
  final open = m.arms.toSet();
  ghosts.removeWhere((k, _) => !open.contains(k));
  var b = tiles.first.rect;
  for (final t in tiles) {
    b = b.expandToInclude(t.rect);
  }
  for (final g in ghosts.values) {
    b = b.expandToInclude(g);
  }
  return BoardLayout(tiles, ghosts, b, dirs);
}

/// يختار حجم الوحدة حتى السلسلة كلها تكفّي الطاولة، ويرجّع التخطيط والكاميرا.
/// [uMax] أكبر وحدة مسموحة (حتى القطع ما تصير عملاقة بالكمبيوتر).
(BoardLayout, BoardCam) fitBoard(DominoModel m, Size size, double uMax) {
  var u = math.min(uMax, math.min(size.width / 9, size.height / 7));
  BoardLayout l = layoutBoard(m, 4, 3);
  for (var tries = 0; tries < 40; tries++) {
    final hw = size.width / (2 * u) - 0.4, hh = size.height / (2 * u) - 0.4;
    l = layoutBoard(m, math.max(2.5, hw), math.max(2, hh));
    final fits = l.bounds.width * u <= size.width - 4 && l.bounds.height * u <= size.height - 4;
    if (fits && !hasOverlap(l)) break;
    u *= 0.92;
  }
  return (l, BoardCam(u, l.bounds.center));
}

/// قطعتين راكبات على بعض؟ (أو مكان الحلقة راكب على قطعة)
bool hasOverlap(BoardLayout l) {
  final rs = [for (final t in l.tiles) t.rect.deflate(0.05), for (final g in l.ghosts.values) g.deflate(0.05)];
  for (var i = 0; i < rs.length; i++) {
    for (var j = i + 1; j < rs.length; j++) {
      if (rs[i].overlaps(rs[j])) return true;
    }
  }
  return false;
}
