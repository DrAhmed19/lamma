// مشاركة النتيجة كصورة: نرسمها بالكود (CustomPainter → PNG) ونفتح قائمة المشاركة.
// حجمين: مربعة للمحادثات (1080×1080) وطولية للستوري (1080×1920).
// بالويب إذا المتصفح ما يدعم مشاركة الملفات تنحفظ الصورة.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/draw.dart';
import '../core/profile.dart';
import '../games/registry.dart';
import '../net/room.dart';
import '../net/session.dart';
import 'icons.dart';
import 'invite.dart';
import 'kit.dart';
import 'save_image_stub.dart' if (dart.library.js_interop) 'save_image_web.dart';
import 'theme.dart';

class CardPlayer {
  const CardPlayer(this.name, this.avatar, this.color, this.score, {this.title});
  final String name, avatar;

  /// لقب اللاعب (بدل النقاط): لعبة "منو بينا؟"
  final String? title;
  final Color color;
  final int score;
}

/// كل شي ينرسم بالصورة
class ShareCardData {
  const ShareCardData({
    required this.game,
    required this.players,
    required this.winner,
    this.headline,
    this.stat,
    this.tour = false,
    this.titles = false,
  });

  /// صورة الألقاب: البطل بالأعلى هو اللي يشارك ([winner])، وكل لاعب بلقبه
  final bool titles;

  /// اسم اللعبة (أو "البطولة")
  final String game;

  /// باللعبة: بترتيب اللاعبين. بالبطولة: بالترتيب (الأول فوق).
  final List<CardPlayer> players;

  /// رقم الفائز بـ [players]، -1 = تعادل
  final int winner;
  final String? headline, stat;
  final bool tour;
}

// ------------------------------------------------------------ النصوص

/// لقب حسب النتيجة
String headlineFor(int winner, List<int> scores) {
  if (winner < 0 || winner >= scores.length) return 'تعادل نار!';
  final top = scores[winner];
  var second = 0;
  for (var i = 0; i < scores.length; i++) {
    if (i != winner) second = math.max(second, scores[i]);
  }
  final gap = top - second;
  if (gap <= 1) return 'على الحافة!';
  if ((second == 0 && top >= 2) || gap >= math.max(3, top * 0.6)) return 'سحق!';
  return 'فوز مستحق!';
}

String _times(int n) {
  if (n == 2) return 'مرتين متتاليتين';
  if (n <= 10) return '$n مرات متتالية';
  return '$n مرة متتالية';
}

/// إحصائية مضحكة من الملف الشخصي (جهاز اللي يشارك)، مكتوبة بالأسماء
String? funnyStat(Session? s, String gameId, String title, int winner) {
  final p = Profile.I;
  final played = p.stats[gameId]?.played ?? 0;
  if (s is! OnlineSession) {
    return played >= 2 ? 'المباراة رقم $played بـ$title على هذا الجهاز' : null;
  }
  final me = s.me;
  if (me < 0) return null;
  final myName = s.nameOf(me);
  if (s.model.isWinner(me)) {
    // أطول سلسلة فوز على واحد من اللي لعبوا هسه
    String? rival;
    var best = 1;
    for (var i = 0; i < s.model.players; i++) {
      if (s.model.isWinner(i)) continue; // أنا وزملائي بالفريق
      final r = p.rivals[s.nameOf(i)];
      if (r != null && r.streak > best) {
        best = r.streak;
        rival = s.nameOf(i);
      }
    }
    if (rival != null) return 'فاز $myName على $rival ${_times(best)}';
    final ws = p.winStreak[gameId] ?? 0;
    if (ws >= 2) return 'فاز $myName ${_times(ws)} بـ$title';
    final won = p.stats[gameId]?.won ?? 0;
    return won >= 2 ? 'هذا الفوز رقم $won لـ$myName بـ$title' : 'أول فوز لـ$myName بـ$title!';
  }
  if (winner >= 0 && !s.model.teams) {
    final w = s.nameOf(winner);
    final r = p.rivals[w];
    if (r != null && r.streak <= -2) return 'فاز $w على $myName ${_times(-r.streak)}';
    if (r != null && r.lost >= 2) return 'فاز $w على $myName ${r.lost} مرات من أصل ${r.won + r.lost}';
  }
  return played >= 2 ? 'المباراة رقم $played لـ$myName بـ$title' : null;
}

/// بيانات صورة مباراة (من شاشة النتيجة)
ShareCardData resultCard({
  required Session? session,
  required int winner,
  required List<int> scores,
  required Color Function(int player) colorOf,
  List<String>? names,
}) {
  final gameId = session?.model.id ?? '';
  final title = gameById(gameId)?.title ?? 'لمّة';
  final room = session is OnlineSession ? session.room : null;
  return ShareCardData(
    game: title,
    winner: winner,
    headline: headlineFor(winner, scores),
    stat: funnyStat(session, gameId, title, winner),
    players: [
      for (var i = 0; i < scores.length; i++)
        CardPlayer(
          names != null && i < names.length ? names[i] : C.playerNames[i % C.playerNames.length],
          room != null && !(session?.model.teams ?? false) && i < room.seats.length ? room.avatarOfSeat(room.seats[i]) : '',
          colorOf(i),
          scores[i],
        ),
    ],
  );
}

/// بيانات صورة البطولة: ترتيب الكل و"بطل البطولة"
ShareCardData tourCard(RoomConn room, NetTour t) {
  final r = t.ranking;
  final tie = r.length > 1 && r[0].value == r[1].value;
  return ShareCardData(
    game: 'البطولة (${t.games.length} ألعاب)',
    tour: true,
    winner: tie ? -1 : 0,
    headline: tie ? 'تعادل على القمة!' : 'بطل البطولة',
    players: [
      for (final e in r)
        CardPlayer(room.nameOfSeat(e.key), room.avatarOfSeat(e.key), C.players[e.key % C.players.length], e.value),
    ],
  );
}

// ------------------------------------------------------------ الرسم

const kSquare = Size(1080, 1080);
const kStory = Size(1080, 1920);

class ShareCardPainter extends CustomPainter {
  ShareCardPainter(this.d);
  final ShareCardData d;

  Color get _accent => d.winner >= 0 && d.winner < d.players.length ? d.players[d.winner].color : C.accent;

  TextPainter _tp(String text, TextStyle style, double maxW) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
  }

  /// نص بالوسط أفقياً، [y] = أعلاه
  double _center(Canvas c, String text, TextStyle style, double cx, double y, double maxW) {
    final tp = _tp(text, style, maxW);
    tp.paint(c, Offset(cx - tp.width / 2, y));
    return tp.height;
  }

  void _avatar(Canvas c, Offset at, double r, CardPlayer p) {
    c.drawCircle(at, r * 1.5,
        Paint()..shader = RadialGradient(colors: [alpha(p.color, 0.45), alpha(p.color, 0)]).createShader(Rect.fromCircle(center: at, radius: r * 1.5)));
    if (p.avatar.isEmpty) {
      paintDisc(c, at, r, p.color);
      return;
    }
    c.drawCircle(at, r, Paint()..color = alpha(p.color, 0.25));
    c.drawCircle(at, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = p.color);
    final tp = _tp(p.avatar, TextStyle(fontSize: r * 1.1, height: 1), r * 3);
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas c, Size size) {
    final w = size.width, h = size.height;
    final story = h > w * 1.3;
    final k = story ? 1.12 : 1.0;
    final cx = w / 2;

    // الخلفية: تدرج + بقع ملونة (بدون تمويه)
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B1650), C.bg])
            .createShader(Offset.zero & size),
    );
    void blob(Offset o, double r, Color col) => c.drawCircle(
        o, r, Paint()..shader = RadialGradient(colors: [alpha(col, 0.35), alpha(col, 0)]).createShader(Rect.fromCircle(center: o, radius: r)));
    blob(Offset(w * 0.15, h * 0.12), w * 0.5, C.accent);
    blob(Offset(w * 0.9, h * 0.45), w * 0.55, _accent);
    blob(Offset(w * 0.2, h * 0.95), w * 0.5, C.players[1]);

    // ارتفاعات الأجزاء حتى نوزّعها بالطول
    final many = d.players.length > 4;
    final rowH = (many ? 74.0 : 86.0) * k;
    final rows = many ? (d.players.length / 2).ceil() : d.players.length;
    // تاج + صورة + اسم + شارة اللقب
    final heroH = (d.winner >= 0 ? 400.0 : 320.0) * k;
    final parts = <double>[130 * k, heroH, rows * rowH, if (d.stat != null) 70 * k, 110 * k];
    final used = parts.fold(0.0, (a, b) => a + b);
    final gap = math.max(16.0, (h - 80 - used) / (parts.length + 1));
    var y = 40 + gap;

    // 1) الشعار واسم اللعبة
    {
      final word = _tp('لمّة', display(78 * k, color: Colors.white), 400);
      final logo = 84 * k;
      final total = logo + 16 + word.width;
      final x0 = cx - total / 2;
      word.paint(c, Offset(x0, y - 8 * k));
      LogoMarkPainter().paint(c..save()..translate(x0 + word.width + 16, y), Size(logo, logo));
      c.restore();
      _center(c, d.game, body(36 * k, weight: FontWeight.w800, color: C.muted), cx, y + logo + 4, w - 120);
      y += parts[0] + gap;
    }

    // 2) الفائز: تاج + صورة + اسم + لقب
    {
      var yy = y;
      if (d.winner >= 0 && d.winner < d.players.length) {
        final p = d.players[d.winner];
        final cw = 120 * k, ch = 92 * k;
        c.save();
        c.translate(cx - cw / 2, yy);
        CrownPainter(p.color).paint(c, Size(cw, ch));
        c.restore();
        yy += ch - 6 * k;
        final r = (story ? 78 : 70) * k;
        _avatar(c, Offset(cx, yy + r), r, p);
        yy += r * 2 + 10 * k;
        yy += _center(c, d.tour || d.titles ? p.name : 'فاز ${p.name}!', display(70 * k, color: p.color), cx, yy, w - 100);
      } else {
        yy += 20 * k;
        final r = 70 * k;
        // تعادل: أول اثنين متداخلين (بدون إيموجي حتى يطلع حتى بدون خط الإيموجي)
        final a = d.players.isNotEmpty ? d.players[0] : const CardPlayer('', '', C.accent, 0);
        final b = d.players.length > 1 ? d.players[1] : a;
        _avatar(c, Offset(cx + r * 0.62, yy + r), r * 0.9, b);
        _avatar(c, Offset(cx - r * 0.62, yy + r), r * 0.9, a);
        yy += r * 2 + 14 * k;
        yy += _center(c, 'تعادل!', display(70 * k, color: Colors.white), cx, yy, w - 100);
      }
      // اللقب كشارة
      if (d.headline != null) {
        final tp = _tp(d.headline!, body(32 * k, weight: FontWeight.w900, color: Colors.white), w - 200);
        final pw = tp.width + 56 * k, ph = tp.height + 14 * k;
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, yy + ph / 2 + 4), width: pw, height: ph), Radius.circular(ph / 2));
        c.drawRRect(r, Paint()..color = alpha(_accent, 0.3));
        c.drawRRect(r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _accent);
        tp.paint(c, Offset(cx - tp.width / 2, r.center.dy - tp.height / 2));
      }
      y += heroH + gap;
    }

    // 3) اللاعبين بألوانهم ونقاطهم
    {
      final cols = many ? 2 : 1;
      final rw = many ? (w - 140) / 2 : math.min(780.0 * k, w - 120);
      for (var i = 0; i < d.players.length; i++) {
        final p = d.players[i];
        final col = i % cols, row = i ~/ cols;
        // من اليمين لليسار
        final left = many ? (col == 0 ? cx + 10 : cx - 10 - rw) : cx - rw / 2;
        final rect = Rect.fromLTWH(left, y + row * rowH, rw, rowH - 14 * k);
        final win = i == d.winner;
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(22 * k));
        c.drawRRect(rr, Paint()..color = alpha(p.color, win ? 0.3 : 0.13));
        c.drawRRect(rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = win ? 4 : 2
          ..color = alpha(p.color, win ? 0.95 : 0.45));
        final ar = rect.height * 0.32;
        var right = rect.right - 22 * k;
        if (d.tour) {
          final n = _tp('${i + 1}', display(38 * k, color: alpha(Colors.white, 0.8)), 80);
          n.paint(c, Offset(right - n.width, rect.center.dy - n.height / 2));
          right -= n.width + 16 * k;
        }
        _avatar(c, Offset(right - ar, rect.center.dy), ar, p);
        right -= ar * 2 + 16 * k;
        final score = _tp(p.title ?? (d.tour ? '${p.score} نقطة' : '${p.score}'), display((p.title != null ? 32 : 40) * k, color: p.color), p.title != null ? 330 : 260);
        score.paint(c, Offset(rect.left + 24 * k, rect.center.dy - score.height / 2));
        final nameW = right - (rect.left + 24 * k + score.width + 16);
        final name = TextPainter(
          text: TextSpan(text: p.name, style: body(32 * k, weight: FontWeight.w800, color: Colors.white)),
          textDirection: TextDirection.rtl,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(40, nameW));
        name.paint(c, Offset(right - name.width, rect.center.dy - name.height / 2));
      }
      y += parts[2] + gap;
    }

    // 4) الإحصائية المضحكة
    if (d.stat != null) {
      _center(c, '«${d.stat}»', body(31 * k, weight: FontWeight.w700, color: const Color(0xFFFFD27A)), cx, y, w - 110);
      y += parts[3] + gap;
    }

    // 5) رابط التطبيق
    {
      final link = Uri.tryParse(kWebUrl)?.host ?? 'lamma';
      _center(c, 'تعال العب وياي بلمّة 🎮', body(30 * k, weight: FontWeight.w700, color: alpha(Colors.white, 0.85)), cx, y, w - 100);
      _center(c, link, body(32 * k, weight: FontWeight.w800, color: const Color(0xFFC9B8FF)), cx, y + 48 * k, w - 100);
    }
  }

  @override
  bool shouldRepaint(ShareCardPainter old) => old.d != d;
}

/// يرسم الصورة PNG
Future<Uint8List> renderCard(ShareCardData d, Size size) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Offset.zero & size);
  ShareCardPainter(d).paint(canvas, size);
  final img = await rec.endRecording().toImage(size.width.round(), size.height.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// يشارك الصورة. بالويب إذا المتصفح ما يدعم مشاركة الملفات: يحفظها.
Future<void> shareCard(BuildContext context, ShareCardData d, Size size) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void toast(String t) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      content: Text(t, style: body(15, weight: FontWeight.w700, color: Colors.white)),
    ));
  final Uint8List bytes;
  try {
    bytes = await renderCard(d, size);
  } catch (_) {
    toast('تعذّر تجهيز الصورة.');
    return;
  }
  const name = 'lamma.png';
  var shared = false;
  try {
    final r = await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: name)],
      fileNameOverrides: const [name],
      text: appInviteText,
    ));
    shared = r.status != ShareResultStatus.unavailable;
  } catch (_) {}
  if (shared) return;
  if (await saveImage(bytes, name)) {
    toast('تم حفظ الصورة');
  } else {
    toast('تعذّرت المشاركة.');
  }
}

/// نافذة الاختيار: مربعة للمحادثات أو طولية للستوري، ويا معاينة
Future<void> showShareSheet(BuildContext context, ShareCardData d) async {
  final size = await showModalBottomSheet<Size>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(30), border: Border.all(color: C.line)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('شارك النتيجة', style: display(28)),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _option(ctx, d, kSquare, 'مربعة', 'للمحادثات')),
                  const SizedBox(width: 12),
                  Expanded(child: _option(ctx, d, kStory, 'طولية', 'للستوري')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (size != null && context.mounted) await shareCard(context, d, size);
}

Widget _option(BuildContext ctx, ShareCardData d, Size size, String title, String sub) {
  return Pressable(
    onTap: () => Navigator.pop(ctx, size),
    child: Column(
      children: [
        SizedBox(
          height: 220,
          child: AspectRatio(
            aspectRatio: size.width / size.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FittedBox(
                child: SizedBox.fromSize(size: size, child: CustomPaint(painter: ShareCardPainter(d))),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: body(16, weight: FontWeight.w800)),
        Text(sub, style: body(13, color: C.muted)),
      ],
    ),
  );
}

/// زر صغير "شارك النتيجة"
class ShareResultButton extends StatelessWidget {
  const ShareResultButton({super.key, required this.data});
  final ShareCardData Function() data;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showShareSheet(context, data()),
      icon: const Icon(Icons.ios_share_rounded, color: L.ink),
      label: Text('شارك النتيجة', style: body(16, weight: FontWeight.w800, color: L.ink)),
    );
  }
}
