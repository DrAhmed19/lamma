// جسر بين قواعد الألعاب (Dart) والسيرفر (JavaScript).
// ينبني بـ: dart compile js -O2 -o server/src/logic.js server/dart/main.dart
// ويحط على globalThis دالة lamma يستعملها server/src/index.js
import 'dart:convert';
import 'dart:js_interop';

import 'package:lamma/logic/game_model.dart';
import 'package:lamma/logic/models.dart';

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
  bool over() => m.over;
  void input(int player, String json) => m.input(player, jsonDecode(json) as Map<String, dynamic>);
  void step(double dt) => m.advance(dt);
  void again() => m.again();
  void connection(int player, bool on) => m.connection(player, on);
  void forfeit(int player) => m.forfeit(player);
  String state() => jsonEncode(m.toJson());
  String events() => jsonEncode(m.drainEvents());
}

@JSExport()
class JsLogic {
  JSObject create(String id, int players, bool crazy, int seed) =>
      createJSInteropWrapper(JsGame(createModel(id, players: players, crazy: crazy, seed: seed)));
  JSObject restore(String json) =>
      createJSInteropWrapper(JsGame(restoreModel(jsonDecode(json) as Map<String, dynamic>)));
  bool supports(String id) => onlineGames.contains(id);
}

void main() {
  _global.lamma = createJSInteropWrapper(JsLogic());
}
