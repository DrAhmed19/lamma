import 'package:flutter/material.dart';

import '../core/profile.dart';
import '../games/registry.dart';
import '../logic/name_filter.dart';
import 'background.dart';
import 'kit.dart';
import 'online.dart';
import 'art.dart';
import 'theme.dart';

/// قبل اللعب ويا الآخرين نحتاج اسم (مرة وحدة بس، وينحفظ)
/// [invited]: جاي من رابط دعوة، فبعد الاسم يدخل الغرفة مباشرة
Future<bool> ensureProfile(BuildContext context, {bool invited = false}) async {
  final bad = isBadName(Profile.I.name);
  if (Profile.I.hasName && !bad) return true;
  return await editProfile(context, first: !Profile.I.hasName, invited: invited, problem: bad ? badNameMessage : null);
}

/// نافذة الاسم والصورة الرمزية
/// [problem]: سبب نطلب تغيير الاسم (مثلاً الاسم المحفوظ صار ممنوع)
Future<bool> editProfile(BuildContext context, {bool first = false, bool invited = false, String? problem}) async {
  final name = TextEditingController(text: Profile.I.name);
  var avatar = Profile.I.avatar;
  String? nameError = problem;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Avatar(avatar, size: 84)),
                    const SizedBox(height: 4),
                    Text(first ? 'أهلًا بك! ما اسمك؟' : 'ملفك الشخصي', textAlign: TextAlign.center, style: display(28, color: L.ink)),
                    if (first)
                      Text(
                        invited ? 'اكتب اسمك واختر صورتك، ثم ندخلك إلى الغرفة مباشرة' : 'سيظهر اسمك لأصدقائك عند اللعب معهم',
                        textAlign: TextAlign.center,
                        style: body(14, color: L.muted),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      autofocus: first,
                      maxLength: 14,
                      textAlign: TextAlign.center,
                      style: body(22, weight: FontWeight.w800, color: L.ink),
                      onChanged: (_) {
                        if (nameError != null) set(() => nameError = null);
                      },
                      decoration: InputDecoration(
                        hintText: 'اكتب اسمك',
                        errorText: nameError,
                        errorMaxLines: 2,
                        errorStyle: body(13, weight: FontWeight.w700, color: const Color(0xFFFF6B81)),
                        counterText: '',
                        hintStyle: body(20, color: alpha(L.muted, 0.5)),
                        filled: true,
                        fillColor: L.sky,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: L.sky2, width: 2)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: L.sky2, width: 2)),
                        focusedBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF2E9BF0), width: 2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('اختر صورتك', style: body(14, weight: FontWeight.w700, color: L.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in kAvatars)
                          Pressable(
                            onTap: () => set(() => avatar = a),
                            child: Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: a == avatar ? alpha(const Color(0xFF2E9BF0), 0.18) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: a == avatar ? const Color(0xFF2E9BF0) : L.sky2, width: 2),
                              ),
                              child: Avatar(a, size: 36),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ChunkyButton(
                      label: invited ? 'دخول الغرفة' : (first ? 'متابعة' : 'حفظ'),
                      icon: Icons.check_rounded,
                      onTap: () {
                        if (name.text.trim().isEmpty) return;
                        // فلتر الأسماء (نفس فحص السيرفر)
                        if (isBadName(name.text)) {
                          set(() => nameError = badNameMessage);
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (ok == true) {
    Profile.I.setIdentity(name.text, avatar);
    return true;
  }
  return false;
}

/// صفحة الملف الشخصي: الإحصائيات والألقاب
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LightBackground()),
          SafeArea(
            child: ListenableBuilder(
              listenable: Profile.I,
              builder: (context, _) {
                final p = Profile.I;
                final earned = p.titles.map((t) => t.name).toSet();
                return ListView(
                  padding: EdgeInsets.fromLTRB(sidePad(context), 8, sidePad(context), 28),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_forward_rounded, color: L.ink),
                        ),
                        const SizedBox(width: 4),
                        Text('ملفي', style: display(34, color: L.ink)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(child: Idle(lift: 5, period: 2.6, child: Avatar(p.avatar, size: 92))),
                    Center(child: Text(p.hasName ? p.name : 'بدون اسم', style: display(32, color: L.ink))),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => editProfile(context),
                        icon: const Icon(Icons.edit_rounded, size: 18, color: L.muted),
                        label: Text('تعديل الاسم والصورة', style: body(14, weight: FontWeight.w700, color: L.muted)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _stat('🎮', '${p.totalPlayed}', 'مباراة'),
                        const SizedBox(width: 8),
                        _stat('🏆', '${p.totalWon}', 'فوز عبر الهواتف'),
                        const SizedBox(width: 8),
                        _stat('⚡', p.bestReaction > 0 ? '${p.bestReaction}' : '—', 'أسرع استجابة (ملّي ثانية)'),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('الألقاب', style: body(16, weight: FontWeight.w800, color: L.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in Profile.allTitles)
                          Opacity(
                            opacity: earned.contains(t.name) ? 1 : 0.4,
                            child: Container(
                              width: 160,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: earned.contains(t.name) ? alpha(const Color(0xFFFFB928), 0.18) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: earned.contains(t.name) ? const Color(0xFFFFB928) : L.sky2, width: 2),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(earned.contains(t.name) ? t.icon : '🔒', style: const TextStyle(fontSize: 26)),
                                  Text(t.name, style: body(15, weight: FontWeight.w800, color: L.ink)),
                                  Text(t.how, style: body(12, color: L.muted)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (p.blocked.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('المحظورون', style: body(16, weight: FontWeight.w800, color: L.muted)),
                      Text('لن تُجمع معهم عند اللعب مع لاعبين آخرين.', style: body(13, color: L.muted)),
                      const SizedBox(height: 8),
                      for (final e in p.blocked.entries)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: L.sky2, width: 2),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.block_rounded, color: L.muted, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(e.value.isEmpty ? 'لاعب' : e.value, style: body(15, weight: FontWeight.w700, color: L.ink))),
                              TextButton(
                                onPressed: () => p.unblock(e.key),
                                child: Text('إلغاء الحظر', style: body(13, weight: FontWeight.w800, color: const Color(0xFFC9B8FF))),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 22),
                    Text('الألعاب', style: body(16, weight: FontWeight.w800, color: L.muted)),
                    const SizedBox(height: 8),
                    for (final g in games)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: L.sky2, width: 2)),
                        child: Row(
                          children: [
                            GameArt(g.id, fallback: g.icon, size: 40, radius: 12),
                            const SizedBox(width: 12),
                            Expanded(child: Text(g.title, style: body(16, weight: FontWeight.w800, color: L.ink))),
                            Text('${p.stats[g.id]?.played ?? 0} مباراة', style: body(13, color: L.muted)),
                            const SizedBox(width: 10),
                            Text('${p.stats[g.id]?.won ?? 0} فوز', style: body(13, weight: FontWeight.w800, color: C.go)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String icon, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: L.sky2, width: 2)),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              Text(value, style: display(26, color: L.ink)),
              Text(label, textAlign: TextAlign.center, style: body(11.5, color: L.muted)),
            ],
          ),
        ),
      );
}
