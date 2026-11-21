// نسخة فاضية للويب (الويب يتحدث لحاله، التحديث من داخل التطبيق بس بأندرويد).

const updatesSupported = false;

class ApkDownload {
  void cancel() {}
  Future<String> start(String url, void Function(int got, int total) onProgress) =>
      throw UnsupportedError('web');
}

Future<bool> verifySha256(String path, String expected) async => true;

/// يرجع null إذا تمام، أو رسالة خطأ
Future<String?> installApk(String path) async => 'مو مدعوم هنا';
