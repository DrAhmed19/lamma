// اختبار قواعد "منو بينا؟": dart run tools/whois_test.dart
import 'dart:convert';

import '../lib/logic/models.dart';
import '../lib/logic/whois_bank.dart';
import '../lib/logic/whois_logic.dart';

var _bad = 0;
void check(bool ok, String what) {
  if (!ok) _bad++;
  print('${ok ? 'ok  ' : 'FAIL'} $what');
}

void run(WhoisModel m, double secs) {
  for (var i = 0; i < secs * 4; i++) {
    m.advance(0.25);
  }
}

void main() {
  check(whoisBank.length >= 120, 'بنك الأسئلة ${whoisBank.length} (120 على الأقل)');

  final m = createModel('whois', players: 4, crazy: false, seed: 7) as WhoisModel;
  check(m.phase == 'count', 'يبدأ بالعد التنازلي');
  run(m, 3);
  check(m.phase == 'vote' && m.qi == 0, 'بدأ السؤال الأول');

  // تصويت: مو لنفسه، ولا للاعب مو موجود
  m.input(0, {'a': 'vote', 't': 0});
  check(m.votes[0] == -1, 'ما يصوّت لنفسه');
  m.input(0, {'a': 'vote', 't': 9});
  check(m.votes[0] == -1, 'ما يصوّت لرقم غلط');
  m.input(0, {'a': 'vote', 't': 2});
  m.input(1, {'a': 'vote', 't': 2});
  m.input(2, {'a': 'vote', 't': 1});
  check(m.phase == 'vote', 'ينتظر اللي ما صوّت');

  // الأصوات سرية
  final v1 = WhoisModel.restore(m.viewFor(1));
  check(v1.votes[1] == 2 && v1.votes[0] == -2 && v1.votes[3] == -1, 'كل واحد يشوف صوته بس');
  check(WhoisModel.restore(m.viewFor(-1)).votes.every((v) => v < 0), 'المتفرج ما يشوف شي');
  check(jsonEncode(m.viewFor(1)).contains('"rng":0'), 'rng مخفي');

  m.input(3, {'a': 'vote', 't': 2});
  check(m.phase == 'reveal' && m.tally[2] == 3 && m.top.length == 1 && m.top[0] == 2, 'الكشف: اللاعب 2 أخذ 3 أصوات');
  check(m.won[2].length == 2 && m.total[2] == 3, 'اللقب انسجل');
  // بالكشف الأصوات لسه سرية (إلا بوضع كشف الأصوات)
  check(WhoisModel.restore(m.viewFor(1)).votes[0] == -2, 'الأصوات سرية بالكشف');

  // تعادل: كل المتعادلين ياخذون اللقب
  run(m, 6);
  check(m.phase == 'vote' && m.qi == 1, 'السؤال الثاني');
  m.input(0, {'a': 'vote', 't': 1});
  m.input(1, {'a': 'vote', 't': 0});
  run(m, 16);
  check(m.phase == 'reveal' && m.top.length == 2, 'تعادل: اثنين ياخذون اللقب');

  // الوقت: بدون تصويت = ممتنعين
  run(m, 6);
  run(m, 16);
  check(m.phase == 'reveal' && m.top.isEmpty, 'ماكو أصوات = ماكو لقب');

  // طلوع لاعب: صوته ينحذف
  run(m, 6);
  m.input(0, {'a': 'vote', 't': 3});
  m.forfeit(3);
  check(m.votes[0] == -1 && m.out[3], 'اللي طلع انحذفت الأصوات عليه');
  check(m.phase == 'vote', 'تكمل بـ3 لاعبين');
  m.forfeit(2);
  check(m.over, 'أقل من 3 = تنتهي');

  // لعبة كاملة: 8 أسئلة
  final g = WhoisModel(players: 3, crazy: true, seed: 3);
  run(g, 3);
  for (var q = 0; q < WhoisModel.questions; q++) {
    check(g.phase == 'vote' && g.qi == q, 'سؤال ${q + 1}');
    g.input(0, {'a': 'vote', 't': 1});
    g.input(1, {'a': 'vote', 't': 2});
    g.input(2, {'a': 'vote', 't': 1});
    if (q == 0) check(WhoisModel.restore(g.viewFor(0)).votes[2] == 1, 'وضع كشف الأصوات يكشف بالكشف');
    run(g, 6);
  }
  check(g.over && g.winner == -1, 'خلصت بعد 8 أسئلة');
  check(g.total[1] == 16 && g.total[2] == 8, 'مجموع الأصوات');
  check(g.finalTitleOf(1) != 'خفيف الظل' && g.finalTitleOf(0) == 'خفيف الظل', 'اللقب النهائي');

  // الإحصائيات: كل الأسئلة 1 أخذ صوتين من 3 (مو إجماع)، و0 صوّت لـ1 كل مرة (كشف الأصوات شغال)
  final kinds = g.facts.map((f) => f.$1).toList();
  check(g.star == 1 && kinds.contains('star'), 'نجم اللمّة');
  check(kinds.contains('pair') && g.facts.any((f) => f.$1 == 'pair' && f.$4 == 8), 'إحصائية «صوّت لفلان» بكشف الأصوات');
  check(kinds.contains('zero') && g.facts.any((f) => f.$1 == 'zero' && f.$2 == 0), 'المظلوم: ما أخذ ولا صوت');
  check(kinds.contains('rebel') && g.facts.any((f) => f.$1 == 'rebel' && f.$2 == 1), 'المتمرّد');
  check(g.agree[0] == 8 && g.agree[2] == 8 && g.agree[1] == 0, 'الاتفاق ويا الأغلبية');
  // قبل النهاية الإحصائيات مخفية
  final h = WhoisModel(players: 3, crazy: false, seed: 1);
  run(h, 3);
  h.input(0, {'a': 'vote', 't': 1});
  h.input(1, {'a': 'vote', 't': 0});
  h.input(2, {'a': 'vote', 't': 1});
  final hv = WhoisModel.restore(h.viewFor(0));
  check(hv.agree.every((v) => v == 0) && h.agree[2] == 1, 'الإحصائيات مخفية لحد النهاية');
  check(h.pairs.every((v) => v == 0), 'بدون كشف الأصوات ما ينحفظ منو صوّت لمنو');
  // الإجماع
  final u = WhoisModel(players: 4, crazy: false, seed: 1);
  run(u, 3);
  u.input(0, {'a': 'vote', 't': 2});
  u.input(1, {'a': 'vote', 't': 2});
  u.input(2, {'a': 'vote', 't': 0});
  u.input(3, {'a': 'vote', 't': 0});
  check(u.unan.isEmpty, 'مو إجماع إذا واحد خالف');
  run(u, 6);
  u.input(0, {'a': 'vote', 't': 1});
  u.input(2, {'a': 'vote', 't': 1});
  u.input(3, {'a': 'vote', 't': 1});
  u.input(1, {'a': 'vote', 't': 0});
  check(u.unan.length == 2 && u.unan[1] == 1, 'إجماع: الكل (غيره) صوّتوا إله');

  // حفظ واستعادة
  final r = restoreModel(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>) as WhoisModel;
  check(r.over && r.total.join() == g.total.join() && r.finalTitleOf(1) == g.finalTitleOf(1), 'save/restore');

  // مرة ثانية
  g.again();
  check(!g.over && g.total.every((v) => v == 0) && g.phase == 'count', 'again');

  print(_bad == 0 ? '\nكلشي تمام' : '\n$_bad فشل');
  if (_bad > 0) throw Exception('failed');
}
