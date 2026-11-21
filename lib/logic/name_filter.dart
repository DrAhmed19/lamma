// فلتر الأسماء: كلمات ممنوعة (عربي بلهجاته + إنكليزي + عربيزي).
// Dart صافي: نفس الكود يشتغل بالتطبيق، وبسيرفر الإنترنت (logic.js)، وبالغرفة المحلية.
//
// قبل الفحص نطبّع الاسم حتى التمويه ما يفيد:
//  - نشيل التشكيل والتطويل والفراغات والنقاط والرموز والحروف المخفية.
//  - نوحّد الحروف المتشابهة (أ إ آ ا، ة ه، ى ي، گ ك، چ ج ...).
//  - الأرقام: بالإنكليزي (0=o، 1=i، 3=e، 4=a، 5=s، 7=t، @=a، $=s)، وبالعربيزي (2=a، 3=a، 5=kh، 6=t، 7=h، 9=q).
//  - الحرف المكرر يصير واحد (fuuuck = fuck).
// انتبه: الكلمات نفسها تنطبّع، فكلمة بيها حرف مكرر تصير أقصر (boob = bob) وممكن تمنع أسماء عادية.
// القائمة تنفحص بطريقتين: كلمات مميّزة تنمنع إذا جت داخل أي جزء من الاسم،
// وكلمات قصيرة تنمنع بس إذا كانت كلمة كاملة (حتى ما ينمنع "نيكول" أو "خولة" أو "صغير").

/// تنمنع إذا جت بأي مكان بالاسم
const _contains = [
  // عربي
  'شرموط', 'شرامي', 'قحبه', 'كحبه', 'قحاب', 'كحاب', 'منيوك', 'منيوج', 'منايك', 'منيك', 'انيكك', 'انيچك', 'نيكني',
  'تنيك', 'ينيك', 'نيكها', 'كسمك', 'كسامك', 'كسام', 'كسخت', 'كساخت', 'كسها', 'كسختك', 'كسك', 'طيز', 'طيزك',
  'لوطي', 'لواط', 'عاهر', 'ديوث', 'دياثه', 'فاجره', 'مومس', 'سكس', 'بزاز', 'قواد', 'ابنالكواد', 'ابنالكلب',
  'ابنالحرام', 'ابنالقحبه', 'ابنالشرموطه', 'يلعن', 'نغل', 'جلق', 'زبري', 'زبك', 'زبه', 'ازباب',
  'خرابك', 'تفوعليك', 'مخنث', 'شاذجنسي',
  // إنكليزي
  'fuck', 'fuk', 'fck', 'shit', 'bitch', 'btch', 'cunt', 'dick', 'pussy', 'whore', 'slut', 'porn', 'sex', 'nigger', 'nigga',
  'faggot', 'penis', 'vagina', 'asshole', 'bastard', 'motherf', 'retard', 'hitler', 'horny', 'blowjob', 'dildo',
  'milf',
  // عربيزي
  'sharmot', 'sharmut', 'qahba', 'gahba', 'kahba', 'manyok', 'manyuk', 'kosom', 'kosomak', 'kusom', 'kusomak', 'kosak',
  'kuskhat', 'koskhat', 'ibnalkalb', 'ibnelkalb', 'ibnalharam', 'ibnelharam', 'teezak', 'tizak', 'manyak',
];

/// تنمنع بس إذا كانت كلمة كاملة (أو الاسم كله)
const _words = [
  // عربي
  'نيك', 'كس', 'زب', 'زبي', 'عير', 'عيري', 'عيرك', 'خول', 'زاني', 'زانيه', 'شاذ', 'خرا', 'خره', 'كواد', 'مطي', 'زمال', 'فرخ',
  'حيوان', 'حمار', 'كلب', 'جحش', 'حقير', 'واطي', 'نجس', 'قذر', 'زباله', 'تافه',
  // إنكليزي
  'ass', 'cum', 'tit', 'tits', 'cock', 'kys', 'nude', 'nudes', 'pig', 'nazi', 'rape', 'fag', 'anal',
  // عربيزي
  'kos', 'kus', 'nik', 'neek', 'zeb', 'zib', 'zebi', 'zebak', 'ayri', 'ayrak', 'yilan', 'yel3n', 'teez', 'tiz', 'khara', 'kalb', 'hmar', 'hemar', 'matti', 'zmal',
];

const _arabicUnify = {
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ة': 'ه', 'ى': 'ي', 'ئ': 'ي', 'ؤ': 'و', 'ء': '',
  'گ': 'ك', 'ڭ': 'ك', 'ک': 'ك', 'چ': 'ج', 'پ': 'ب', 'ڤ': 'ف', 'ژ': 'ز', 'ی': 'ي', 'ھ': 'ه',
};

const _leet = {'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '@': 'a', r'$': 's', '!': 'i'};
const _arabizi = {'2': 'a', '3': 'a', '5': 'kh', '6': 't', '7': 'h', '8': 'gh', '9': 'q'};

bool _isArabicLetter(int c) => c >= 0x0621 && c <= 0x064A;
bool _isLatin(int c) => c >= 0x61 && c <= 0x7A;

/// تطبيع أولي: حروف صغيرة، بدون تشكيل أو تطويل أو حروف مخفية، وحروف موحّدة
String _base(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    // التشكيل (064B-065F و 0670)، التطويل (0640)، والحروف المخفية (200B-200F، 202A-202E، 2060-2064، FEFF)
    if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || r == 0x0640) continue;
    if ((r >= 0x200B && r <= 0x200F) || (r >= 0x202A && r <= 0x202E) || (r >= 0x2060 && r <= 0x2064) || r == 0xFEFF) continue;
    final ch = String.fromCharCode(r);
    b.write(_arabicUnify[ch] ?? ch);
  }
  return b.toString();
}

/// يبدّل الأرقام والرموز بحروف، ويخلي الحروف بس، والمكرر يصير واحد
String _compact(String s, Map<String, String> digits) {
  final b = StringBuffer();
  var last = -1;
  for (final r in s.runes) {
    var ch = String.fromCharCode(r);
    ch = digits[ch] ?? ch;
    for (final c in ch.runes) {
      if (!_isArabicLetter(c) && !_isLatin(c)) continue;
      if (c == last) continue;
      b.writeCharCode(c);
      last = c;
    }
  }
  return b.toString();
}

/// الكلمات (مفصولة بأي شي مو حرف أو رقم)
List<String> _tokens(String s, Map<String, String> digits) => s
    .split(RegExp(r'[^0-9a-zء-ي@$!]+'))
    .map((t) => _compact(t, digits))
    .where((t) => t.isNotEmpty)
    .toList();

final _containsN = {for (final w in _contains) _compact(_base(w), const {})}..remove('');
final _wordsN = {for (final w in _words) _compact(_base(w), const {})}..remove('');

/// الاسم بيه كلمة ممنوعة؟
bool isBadName(String name) {
  final s = _base(name);
  for (final digits in [_leet, _arabizi]) {
    final all = _compact(s, digits);
    if (all.isEmpty) continue;
    for (final w in _containsN) {
      if (all.contains(w)) return true;
    }
    if (_wordsN.contains(all)) return true;
    for (final t in _tokens(s, digits)) {
      if (_wordsN.contains(t)) return true;
    }
  }
  return false;
}

/// رسالة الرفض بالواجهة
const badNameMessage = 'هذا الاسم غير مناسب، اختر اسماً آخر';
