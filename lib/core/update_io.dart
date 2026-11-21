// تنزيل وتثبيت الـ APK (أندرويد). يشتغل بس إذا dart:io موجود.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

final bool updatesSupported = defaultTargetPlatform == TargetPlatform.android;

class ApkDownload {
  http.Client? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  /// ينزّل الملف ويرجع مساره. يرمي استثناء إذا فشل أو انلغى.
  Future<String> start(String url, void Function(int got, int total) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lamma-update.apk');
    if (await file.exists()) await file.delete();
    final client = _client = http.Client();
    IOSink? sink;
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw HttpException('server ${res.statusCode}');
      final total = res.contentLength ?? 0;
      sink = file.openWrite();
      var got = 0;
      var lastTick = DateTime.now();
      await for (final chunk in res.stream) {
        if (_cancelled) throw const _Cancelled();
        sink.add(chunk);
        got += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastTick).inMilliseconds > 80) {
          lastTick = now;
          onProgress(got, total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress(got, total > 0 ? total : got);
      return file.path;
    } catch (e) {
      try {
        await sink?.close();
        if (await file.exists()) await file.delete();
      } catch (_) {}
      if (_cancelled) throw const _Cancelled();
      rethrow;
    } finally {
      client.close();
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => 'cancelled';
}

Future<bool> verifySha256(String path, String expected) async {
  if (expected.isEmpty) return true;
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString().toLowerCase() == expected.toLowerCase();
}

/// يفتح شاشة التثبيت. يرجع null إذا تمام، أو رسالة خطأ.
Future<String?> installApk(String path) async {
  final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  switch (r.type) {
    case ResultType.done:
      return null;
    case ResultType.permissionDenied:
      return 'لازم تسمح للتطبيق بالتثبيت. فعّل "السماح من هذا المصدر" وارجع اضغط تثبيت.';
    default:
      return r.message;
  }
}
