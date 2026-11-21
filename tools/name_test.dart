// اختبار فلتر الأسماء: كلمات لازم تنمنع، وأسماء عادية لازم تمر. شغّله بعد أي تعديل على القائمة.
// dart run tools/name_test.dart
import 'package:lamma/logic/name_filter.dart';

void main() {
  const bad = ['شرموطة', 'ش ر م و ط ه', 'شـــرمــوطة', 'قحبة', 'گحبة', 'كس', 'منيوك', 'f.u.c.k', 'FUUUCK', 'b1tch', 'sh1t',
    'Sharmoota', 'ga7ba', 'kos', 'kosomak', 'ابن الكلب', 'ابن_الحرام', 'نيك', 'زب', 'k0s', 'n1gger', 'zebi', 'حمار', 'كواد',
    'شَرْمُوطَة', 'ass', 'Hitler', 'كسمك', 'ط ي ز'];
  const good = ['أحمد', 'علي', 'نيكول', 'خولة', 'صغير', 'زينب', 'زبيدة', 'Nicole', 'Assad', 'Classic', 'Khayri', 'شعيري',
    'Nazih', 'كوادر', 'محمد ٧', 'Ali99', 'Grapes', 'مصطفى', 'حسين', 'Dina', 'Sara', 'فاطمة', 'عباس', 'Kassem', 'خيري', 'Kosay',
    'Jassim', 'Hassan', 'Basel', 'Tariq', 'Analia', 'سكينة', 'مسكين', 'Peacock', 'Bob', 'Alex', 'Max', 'Nigel', 'Rex', 'Anika'];
  var fail = 0;
  for (final n in bad) {
    if (!isBadName(n)) { print('MISSED  $n'); fail++; }
  }
  for (final n in good) {
    if (isBadName(n)) { print('FALSE+  $n'); fail++; }
  }
  print('bad=${bad.length} good=${good.length} fail=$fail');
  if (fail > 0) throw StateError("name filter failed");
}
