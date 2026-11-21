import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_stub.dart' if (dart.library.io) 'update_io.dart' as plat;
import 'version.dart';

/// مصدر التحديثات: الـ Release "apk-latest" بـ GitHub (CI يرفع إلو lamma.apk و update.json كل مرة).
const _base = String.fromEnvironment('UPDATES', defaultValue: 'https://github.com/DrAhmed19/lamma/releases/download/apk-latest');

class UpdateChange {
  const UpdateChange(this.sha, this.date, this.title);
  final String sha, title;
  final DateTime? date;
}

class UpdateInfo {
  const UpdateInfo({
    required this.sha,
    required this.version,
    required this.size,
    required this.sha256,
    required this.date,
    required this.changes,
  });
  final String sha, version, sha256;
  final int size;
  final DateTime? date;

  /// الأحدث أولاً
  final List<UpdateChange> changes;

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
        sha: (j['sha'] as String).toLowerCase(),
        version: j['version'] as String? ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        sha256: j['sha256'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '')?.toLocal(),
        changes: [
          for (final c in (j['changes'] as List? ?? const []))
            UpdateChange(
              (c['sha'] as String? ?? '').toLowerCase(),
              DateTime.tryParse(c['date'] as String? ?? '')?.toLocal(),
              c['title'] as String? ?? '',
            ),
        ],
      );
}

enum UpdateStatus { idle, checking, upToDate, available, downloading, ready, error }

/// يتحقق من نسخة جديدة وينزّلها ويثبتها (أندرويد). الواجهة تسمع للتغييرات.
class Updater extends ChangeNotifier {
  Updater._();
  static final Updater I = Updater._();

  bool get supported => plat.updatesSupported;

  UpdateStatus status = UpdateStatus.idle;
  UpdateInfo? info;
  String? error;

  /// أثناء التنزيل
  int got = 0, total = 0;
  double speed = 0; // بايت بالثانية
  String? _path;
  plat.ApkDownload? _dl;
  DateTime? _lastCheck;
  final _speedWatch = Stopwatch();
  int _speedBase = 0;
  double _speedAt = 0;

  /// نسخة التطبيق الحالية
  String get current => buildId;

  bool get hasUpdate => info != null && info!.sha != current.toLowerCase();

  /// التعديلات الجديدة بس (اللي بعد نسختي). إذا ما لگيت نسختي أرجع الكل.
  List<UpdateChange> get newChanges {
    final all = info?.changes ?? const <UpdateChange>[];
    final i = all.indexWhere((c) => c.sha == current.toLowerCase());
    return i < 0 ? all : all.sublist(0, i);
  }

  bool get busy => status == UpdateStatus.checking || status == UpdateStatus.downloading;

  void _set(UpdateStatus s, {String? err}) {
    status = s;
    error = err;
    notifyListeners();
  }

  /// فحص. بالتلقائي ما نعيد الفحص أكثر من مرة بالـ10 دقايق.
  Future<void> check({bool force = false}) async {
    if (!supported || busy) return;
    if (!force && _lastCheck != null && DateTime.now().difference(_lastCheck!) < const Duration(minutes: 10)) return;
    if (status == UpdateStatus.ready) return;
    _set(UpdateStatus.checking);
    try {
      final r = await http
          .get(Uri.parse('$_base/update.json?t=${DateTime.now().millisecondsSinceEpoch}'),
              headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
      info = UpdateInfo.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      _lastCheck = DateTime.now();
      _set(hasUpdate ? UpdateStatus.available : UpdateStatus.upToDate);
    } catch (e) {
      _set(UpdateStatus.error, err: 'ما گدرت أتحقق من التحديث. تأكد من النت وجرب مرة ثانية.');
    }
  }

  Future<void> download() async {
    final i = info;
    if (!supported || i == null || status == UpdateStatus.downloading) return;
    got = 0;
    total = i.size;
    speed = 0;
    _speedBase = 0;
    _speedAt = 0;
    _speedWatch
      ..reset()
      ..start();
    _set(UpdateStatus.downloading);
    final dl = _dl = plat.ApkDownload();
    try {
      final path = await dl.start('$_base/lamma.apk', (g, t) {
        got = g;
        if (t > 0) total = t;
        final now = _speedWatch.elapsedMilliseconds / 1000;
        if (now - _speedAt >= 0.6) {
          final inst = (g - _speedBase) / (now - _speedAt);
          speed = speed == 0 ? inst : speed * 0.6 + inst * 0.4;
          _speedBase = g;
          _speedAt = now;
        }
        notifyListeners();
      });
      if (!await plat.verifySha256(path, i.sha256)) {
        throw Exception('checksum');
      }
      _path = path;
      _set(UpdateStatus.ready);
      await install();
    } catch (e) {
      if (e.toString() == 'cancelled') {
        _set(UpdateStatus.available);
      } else if (e.toString().contains('checksum')) {
        _set(UpdateStatus.error, err: 'الملف النازل تالف. جرب تنزّله مرة ثانية.');
      } else {
        _set(UpdateStatus.error, err: 'انقطع التنزيل. تأكد من النت وجرب مرة ثانية.');
      }
    } finally {
      _dl = null;
    }
  }

  void cancel() => _dl?.cancel();

  /// يفتح شاشة التثبيت (إذا انرفض السماح، المستخدم يرجع يضغط مرة ثانية)
  Future<void> install() async {
    final p = _path;
    if (p == null) return;
    final err = await plat.installApk(p);
    if (err != null) _set(UpdateStatus.error, err: err);
  }

  /// رجوع من الخطأ لحالة معروفة
  void resetError() {
    if (status != UpdateStatus.error) return;
    _set(_path != null ? UpdateStatus.ready : (hasUpdate ? UpdateStatus.available : UpdateStatus.idle));
  }
}
