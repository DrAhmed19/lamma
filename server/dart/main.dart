// جسر بين قواعد الألعاب (Dart) والسيرفر (JavaScript).
// ينبني بـ: dart compile js -O2 -o server/src/logic.js server/dart/main.dart
// ويحط على globalThis دالة lamma يستعملها server/src/index.js
import 'dart:convert';
import 'dart:math' as math;
import 'dart:js_interop';

import 'package:lamma/logic/game_model.dart';
import 'package:lamma/logic/models.dart';
import 'package:lamma/logic/name_filter.dart';

@JS('globalThis')
external JSObject get _global;

extension on JSObject {
  external set lamma(JSObject v);
}

@JSExport()
class JsGame {
  JsGame(this.m);
  final GameModel m;

  int tickHz() => m.tickHz;
  int winner() => m.winner;
  bool over() => m.over;
  void input(int player, String json) => m.input(player, jsonDecode(json) as Map<String, dynamic>);
  void step(double dt) => m.advance(dt);
  void again() => m.again();
  void connection(int player, bool on) => m.connection(player, on);
  void forfeit(int player) => m.forfeit(player);
  String state() => jsonEncode(m.toJson());
  bool secret() => m.secret;
  String stateFor(int player) => jsonEncode(m.viewFor(player));
  String winners() => jsonEncode(m.winners);
  String events() => jsonEncode(m.drainEvents());

  /// حركة الكمبيوتر (JSON، أو "" إذا ماكو شي يسويه هسة)
  String bot(int player, int level) {
    final mv = botMove(m, player, level, _rng);
    return mv == null ? '' : jsonEncode(mv);
  }

  static final _rng = math.Random();
}

@JSExport()
class JsLogic {
  JSObject create(String id, int players, bool crazy, int seed, int level) =>
      createJSInteropWrapper(JsGame(createModel(id, players: players, crazy: crazy, seed: seed, level: level)));
  JSObject restore(String json) =>
      createJSInteropWrapper(JsGame(restoreModel(jsonDecode(json) as Map<String, dynamic>)));
  bool supports(String id) => onlineGames.contains(id);

  /// اللعبة يلعبها الكمبيوتر؟ وبيها مستويات؟
  bool bots(String id) => botGames.contains(id);
  bool levels(String id) => levelGames.contains(id);

  /// فلتر الأسماء (نفس اللي بالتطبيق)
  bool badName(String name) => isBadName(name);
}

void main() {
  _global.lamma = createJSInteropWrapper(JsLogic());
}
