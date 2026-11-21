import 'package:flutter/material.dart';

import '../core/profile.dart';
import '../games/registry.dart';
import 'background.dart';
import 'kit.dart';
import 'online.dart';
import 'theme.dart';

/// قبل اللعب ويا الآخرين نحتاج اسم (مرة وحدة بس، وينحفظ)
/// [invited]: جاي من رابط دعوة، فبعد الاسم يدخل الغرفة مباشرة
Future<bool> ensureProfile(BuildContext context, {bool invited = false}) async {
  if (Profile.I.hasName) return true;
  return await editProfile(context, first: true, invited: invited);
}

/// نافذة الاسم والصورة الرمزية
Future<bool> editProfile(BuildContext context, {bool first = false, bool invited = false}) async {
  final name = TextEditingController(text: Profile.I.name);
  var avatar = Profile.I.avatar;
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
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(30), border: Border.all(color: C.line)),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Text(avatar, style: const TextStyle(fontSize: 64))),
                    const SizedBox(height: 4),
                    Text(first ? 'أهلًا بك! ما اسمك؟' : 'ملفك الشخصي', textAlign: TextAlign.center, style: display(28)),
                    if (first)
                      Text(
                        invited ? 'اكتب اسمك واختر صورتك، ثم ندخلك إلى الغرفة مباشرة' : 'سيظهر اسمك لأصدقائك عند اللعب معهم',
                        textAlign: TextAlign.center,
                        style: body(14, color: C.muted),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: name,
                      autofocus: first,
                      maxLength: 14,
                      textAlign: TextAlign.center,
                      style: body(22, weight: FontWeight.w800),
                      decoration: InputDecoration(
                        hintText: 'اكتب اسمك',
                        counterText: '',
                        hintStyle: body(20, color: alpha(C.muted, 0.5)),
                        filled: true,
                        fillColor: alpha(Colors.white, 0.06),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: C.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: C.line)),
                        focusedBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: alpha(C.accent, 0.8))),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('اختر صورتك', style: body(14, weight: FontWeight.w700, color: C.muted)),
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
                                color: a == avatar ? alpha(C.accent, 0.3) : alpha(Colors.white, 0.05),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: a == avatar ? C.accent : C.line, width: a == avatar ? 2 : 1),
                              ),
                              child: Text(a, style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    BigButton(
                      label: invited ? 'دخول الغرفة' : (first ? 'متابعة' : 'حفظ'),
                      icon: Icons.check_rounded,
                      onTap: () {
                        if (name.text.trim().isEmpty) return;
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
          const Positioned.fill(child: LammaBackground()),
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
                          icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        Text('ملفي', style: display(34)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(child: Text(p.avatar, style: const TextStyle(fontSize: 72))),
                    Center(child: Text(p.hasName ? p.name : 'بدون اسم', style: display(32))),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => editProfile(context),
                        icon: const Icon(Icons.edit_rounded, size: 18, color: C.muted),
                        label: Text('تعديل الاسم والصورة', style: body(14, weight: FontWeight.w700, color: C.muted)),
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
                    Text('الألقاب', style: body(16, weight: FontWeight.w800, color: C.muted)),
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
                                color: alpha(earned.contains(t.name) ? C.accent : Colors.white, earned.contains(t.name) ? 0.18 : 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: earned.contains(t.name) ? alpha(C.accent, 0.7) : C.line),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(earned.contains(t.name) ? t.icon : '🔒', style: const TextStyle(fontSize: 26)),
                                  Text(t.name, style: body(15, weight: FontWeight.w800)),
                                  Text(t.how, style: body(12, color: C.muted)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('الألعاب', style: body(16, weight: FontWeight.w800, color: C.muted)),
                    const SizedBox(height: 8),
                    for (final g in games)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: alpha(Colors.white, 0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: g.colors)),
                              child: CustomPaint(painter: g.icon()),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(g.title, style: body(16, weight: FontWeight.w800))),
                            Text('${p.stats[g.id]?.played ?? 0} مباراة', style: body(13, color: C.muted)),
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
          decoration: BoxDecoration(color: alpha(Colors.white, 0.05), borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              Text(value, style: display(26)),
              Text(label, textAlign: TextAlign.center, style: body(11.5, color: C.muted)),
            ],
          ),
        ),
      );
}
