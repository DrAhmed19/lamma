import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/updater.dart';
import 'kit.dart';
import 'theme.dart';

const _violet = Color(0xFF6A4DFF);

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// "قبل ساعتين"
String ago(DateTime? d) {
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 60) return 'الآن';
  final m = s ~/ 60;
  if (m < 60) return m == 1 ? 'قبل دقيقة' : (m == 2 ? 'قبل دقيقتين' : (m <= 10 ? 'قبل $m دقائق' : 'قبل $m دقيقة'));
  final h = m ~/ 60;
  if (h < 24) return h == 1 ? 'قبل ساعة' : (h == 2 ? 'قبل ساعتين' : (h <= 10 ? 'قبل $h ساعات' : 'قبل $h ساعة'));
  final dd = h ~/ 24;
  if (dd < 30) return dd == 1 ? 'قبل يوم' : (dd == 2 ? 'قبل يومين' : (dd <= 10 ? 'قبل $dd أيام' : 'قبل $dd يوم'));
  return '${d.year}/${d.month}/${d.day}';
}

Future<void> showUpdateSheet(BuildContext context) {
  final u = Updater.I;
  // نفتح الشاشة ونفحص إذا ما عندنا معلومات أو آخر مرة كانت خطأ
  if (u.status == UpdateStatus.idle || u.status == UpdateStatus.error && !u.hasUpdate) u.check(force: true);
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _UpdateSheet(),
  );
}

/// شريط بالشاشة الرئيسية يظهر لمّن تكون أكو نسخة جديدة
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Updater.I,
      builder: (context, _) {
        final u = Updater.I;
        final show = u.supported && u.hasUpdate && u.status != UpdateStatus.checking;
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Pressable(
                    onTap: () => showUpdateSheet(context),
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) {
                        final glow = 0.5 + 0.5 * math.sin(_c.value * math.pi * 2);
                        return Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(colors: [_violet, Color(0xFF8B6CFF), Color(0xFFB06CFF)]),
                            boxShadow: [BoxShadow(color: alpha(_violet, 0.25 + 0.25 * glow), blurRadius: 12 + 10 * glow)],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: alpha(Colors.white, 0.18), shape: BoxShape.circle),
                                child: Transform.translate(
                                  offset: Offset(0, 2 * glow - 1),
                                  child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 26),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('يتوفر إصدار جديد!', style: body(17, weight: FontWeight.w800)),
                                    Text(
                                      u.newChanges.isEmpty
                                          ? 'اضغط لتحديث التطبيق'
                                          : '${u.newChanges.length} ${u.newChanges.length <= 10 ? 'تحسينات' : 'تحسين'} جديدة · ${fmtBytes(u.info!.size)}',
                                      style: body(13.5, color: alpha(Colors.white, 0.85)),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                child: Text('تحديث', style: body(15, weight: FontWeight.w800, color: _violet)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet();

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  bool _showAll = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
        child: Container(
          margin: EdgeInsets.fromLTRB(10, 10, 10, 10 + MediaQuery.paddingOf(context).bottom),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: C.line),
          ),
          child: ListenableBuilder(
            listenable: Updater.I,
            builder: (context, _) {
              final u = Updater.I;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _header(u),
                    const SizedBox(height: 16),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: KeyedSubtree(key: ValueKey(u.status), child: _content(context, u)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ الرأس

  Widget _header(Updater u) {
    final (String title, String sub) = switch (u.status) {
      UpdateStatus.checking => ('جارٍ التحقق...', 'نبحث عن إصدار جديد'),
      UpdateStatus.upToDate => ('كل شيء محدَّث', 'لديك أحدث إصدار'),
      UpdateStatus.available => ('إصدار جديد!', 'جاهز للتحديث'),
      UpdateStatus.downloading => ('جارٍ تنزيل التحديث', 'لا تغلق التطبيق'),
      UpdateStatus.ready => ('التحديث جاهز', 'بقي التثبيت فقط'),
      UpdateStatus.error => ('حدثت مشكلة', 'حاول مرة أخرى'),
      UpdateStatus.idle => ('التحديثات', ''),
    };
    final ok = u.status == UpdateStatus.upToDate;
    final bad = u.status == UpdateStatus.error;
    final col = bad ? const Color(0xFFFF4D6A) : (ok ? C.go : _violet);
    return Row(
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => CustomPaint(
              painter: _PulsePainter(_pulse.value, col, spin: u.status == UpdateStatus.checking || u.status == UpdateStatus.downloading),
              child: Center(
                child: Icon(
                  ok
                      ? Icons.check_rounded
                      : bad
                          ? Icons.error_outline_rounded
                          : u.status == UpdateStatus.ready
                              ? Icons.inventory_2_rounded
                              : Icons.system_update_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: display(32)),
              if (sub.isNotEmpty) Text(sub, style: body(15, color: C.muted)),
            ],
          ),
        ),
        Pressable(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: alpha(Colors.white, 0.07), shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 20, color: C.muted),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ المحتوى

  Widget _content(BuildContext context, Updater u) {
    switch (u.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(child: SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: alpha(Colors.white, 0.7)))),
        );
      case UpdateStatus.upToDate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _versionCard(u, same: true),
            const SizedBox(height: 14),
            BigButton(label: 'التحقق مرة أخرى', icon: Icons.refresh_rounded, filled: false, onTap: () => u.check(force: true)),
          ],
        );
      case UpdateStatus.available:
        return _available(context, u);
      case UpdateStatus.downloading:
        return _downloading(u);
      case UpdateStatus.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note(Icons.shield_outlined, 'إذا ظهر تنبيه "السماح بالتثبيت من هذا المصدر"، ففعّله ثم ارجع إلى التطبيق واضغط تثبيت.', C.go),
            const SizedBox(height: 14),
            BigButton(label: 'ثبّت الآن', icon: Icons.install_mobile_rounded, color: C.go, onTap: u.install),
          ],
        );
      case UpdateStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note(Icons.wifi_off_rounded, u.error ?? 'حدث خطأ', const Color(0xFFFF4D6A)),
            const SizedBox(height: 14),
            BigButton(
              label: 'حاول مرة أخرى',
              icon: Icons.refresh_rounded,
              onTap: () {
                final had = u.hasUpdate;
                u.resetError();
                if (u.status == UpdateStatus.ready) {
                  u.install();
                } else if (had) {
                  u.download();
                } else {
                  u.check(force: true);
                }
              },
            ),
          ],
        );
    }
  }

  Widget _note(IconData icon, String text, Color col) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: alpha(col, 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: alpha(col, 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: col, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: body(14.5, color: alpha(Colors.white, 0.9)))),
          ],
        ),
      );

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: alpha(Colors.white, 0.08), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: body(13, weight: FontWeight.w700, color: alpha(Colors.white, 0.85)), textDirection: TextDirection.ltr),
      );

  Widget _versionCard(Updater u, {bool same = false}) {
    final i = u.info;
    Widget col(String label, String ver, String build, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: alpha(c, 0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: alpha(c, 0.4))),
            child: Column(
              children: [
                Text(label, style: body(12.5, color: C.muted, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(ver.isEmpty ? '—' : ver, style: display(22)),
                const SizedBox(height: 2),
                _chip(build),
              ],
            ),
          ),
        );
    if (same) {
      return Row(children: [col('إصدارك', i?.version ?? '', u.current, C.go)]);
    }
    return Row(
      children: [
        col('إصدارك', i == null ? '' : '', u.current, C.muted),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_back_rounded, color: alpha(Colors.white, 0.5)),
        ),
        col('الجديد', i?.version ?? '', i?.sha ?? '', _violet),
      ],
    );
  }

  Widget _available(BuildContext context, Updater u) {
    final i = u.info!;
    final changes = u.newChanges;
    final shown = _showAll ? changes : changes.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _versionCard(u),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat(Icons.save_alt_rounded, fmtBytes(i.size)),
            if (i.date != null) _stat(Icons.schedule_rounded, ago(i.date)),
            _stat(Icons.auto_awesome_rounded, changes.isEmpty ? 'تحسينات عامة' : '${changes.length} تعديل'),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(color: alpha(Colors.white, 0.04), borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ما الجديد', style: body(15, weight: FontWeight.w800, color: C.muted)),
              const SizedBox(height: 10),
              if (changes.isEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('تحسينات وإصلاحات عامة.', style: body(15)))
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var n = 0; n < shown.length; n++) _timelineRow(shown[n], first: n == 0, last: n == shown.length - 1),
                      ],
                    ),
                  ),
                ),
              if (!_showAll && changes.length > 5)
                Pressable(
                  onTap: () => setState(() => _showAll = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: Text('عرض الكل (${changes.length})', style: body(14, weight: FontWeight.w800, color: C.accent))),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BigButton(label: 'حدّث الآن', icon: Icons.download_rounded, color: _violet, onTap: u.download),
        const SizedBox(height: 6),
        Pressable(
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(child: Text('لاحقاً', style: body(15, color: C.muted, weight: FontWeight.w700))),
          ),
        ),
      ],
    );
  }

  Widget _stat(IconData icon, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: alpha(Colors.white, 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: C.muted),
            const SizedBox(width: 6),
            Text(t, style: body(13.5, weight: FontWeight.w700)),
          ],
        ),
      );

  Widget _timelineRow(UpdateChange c, {required bool first, required bool last}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: first ? C.accent : alpha(Colors.white, 0.3),
                    boxShadow: first ? [BoxShadow(color: alpha(C.accent, 0.6), blurRadius: 8)] : null,
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: alpha(Colors.white, 0.1))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: body(14.5, weight: first ? FontWeight.w700 : FontWeight.w500, color: alpha(Colors.white, first ? 0.95 : 0.78))),
                  if (c.date != null) Text(ago(c.date), style: body(12, color: C.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloading(Updater u) {
    final f = u.total > 0 ? (u.got / u.total).clamp(0.0, 1.0) : 0.0;
    final left = u.speed > 0 && u.total > 0 ? ((u.total - u.got) / u.speed).ceil() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Center(
          child: SizedBox(
            width: 170,
            height: 170,
            child: CustomPaint(
              painter: _RingPainter(f),
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: f),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, v, _) => Text('${(v * 100).floor()}%', style: display(44)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat(Icons.download_rounded, '${fmtBytes(u.got)} / ${fmtBytes(u.total)}'),
            if (u.speed > 0) _stat(Icons.speed_rounded, '${fmtBytes(u.speed)}/ث'),
            if (left != null) _stat(Icons.timer_outlined, left < 60 ? '$left ثانية' : '${(left / 60).ceil()} دقيقة'),
          ],
        ),
        const SizedBox(height: 16),
        BigButton(label: 'إلغاء', filled: false, onTap: u.cancel),
      ],
    );
  }
}

/// دايرة نابضة خلف أيقونة الرأس
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color, {this.spin = false});
  final double t;
  final Color color;
  final bool spin;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.34;
    for (var i = 0; i < 2; i++) {
      final k = (t + i / 2) % 1.0;
      canvas.drawCircle(
        c,
        r + (size.width * 0.16) * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = alpha(color, 0.45 * (1 - k)),
      );
    }
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [lighten(color, 0.15), darken(color, 0.2)]).createShader(rect),
    );
    if (spin) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + 4),
        t * math.pi * 2,
        math.pi * 0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = alpha(Colors.white, 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.t != t || old.color != color || old.spin != spin;
}

/// حلقة تقدم التنزيل
class _RingPainter extends CustomPainter {
  _RingPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 14..color = alpha(Colors.white, 0.08));
    if (f <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: const [_violet, Color(0xFFB06CFF), Color(0xFF6A4DFF)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    // رأس متوهج
    final a = -math.pi / 2 + math.pi * 2 * f;
    canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.f != f;
}
