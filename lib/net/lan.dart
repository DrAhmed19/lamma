// اللعب على نفس الشبكة: بالتطبيق (dart:io) سيرفر حقيقي، بالويب نسخة فاضية.
export 'lan_stub.dart' if (dart.library.io) 'lan_io.dart';
