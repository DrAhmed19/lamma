// بالويب: المتصفح ما يگدر يصير سيرفر ولا يدوّر بالشبكة.
// (الويب يدخل غرفة محلية بفتح عنوان تلفون صاحب الغرفة مباشرة.)
import 'lan_room.dart';

const lanPort = 8787;
const bool lanHostSupported = false;

class LanFound {
  const LanFound(this.server, this.code, this.hostName, this.players, this.started);
  final String server, code, hostName;
  final int players;
  final bool started;
}

class LanHost {
  static LanHost? current;
  LanRoom get room => throw UnsupportedError('web');
  List<String> get ips => const [];
  int get port => lanPort;
  String get code => '';
  String get selfServer => '';
  String? get joinUrl => null;
  String urlFor(String ip) => '';
  static Future<LanHost> start() => throw UnsupportedError('web');
  Future<void> stop() async {}
}

Future<List<String>> localIps() async => const [];
Future<List<LanFound>> scanLan() async => const [];
