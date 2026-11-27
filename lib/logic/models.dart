import 'dart:math' as math;

import 'connect4_bot.dart';
import 'connect4_logic.dart';
import 'domino_bot.dart';
import 'domino_logic.dart';
import 'game_model.dart';
import 'hockey_bot.dart';
import 'hockey_logic.dart';
import 'muhaibes_bot.dart';
import 'muhaibes_logic.dart';
import 'pigeon_bot.dart';
import 'pigeon_logic.dart';
import 'quiz_logic.dart';
import 'reaction_logic.dart';
import 'spy_logic.dart';
import 'tug_logic.dart';
import 'whois_logic.dart';
import 'xo_bot.dart';
import 'xo_logic.dart';

/// كل الألعاب اللي قواعدها صارت على الأساس المشترك (تشتغل أونلاين)
const onlineGames = {'xo', 'connect4', 'tug', 'pigeon', 'hockey', 'reaction', 'quiz', 'muhaibes', 'domino', 'whois', 'spy'};

/// ألعاب يلعبها الكمبيوتر (بالغرف وعلى الجهاز)
const botGames = {'domino', 'xo', 'connect4', 'quiz', 'reaction', 'tug', 'hockey', 'pigeon', 'muhaibes'};

/// ألعاب بيها مستويات (سهل/متوسط/صعب) بدل عادي/مجنون
const levelGames = {'domino', 'xo', 'connect4', 'quiz', 'reaction', 'tug', 'hockey', 'pigeon', 'muhaibes'};

/// حركة الكمبيوتر بلعبة [m] للاعب [player] بمستوى [level] (0-2). null = ماكو شي يسويه هسة.
/// [peek] = بس نسأل "عنده شي يسويه؟" بدون ما يحسب الحركة (رخيص، كل إطار).
Map<String, dynamic>? botMove(GameModel m, int player, int level, math.Random r, {bool peek = false}) {
  if (m is DominoModel) {
    if (m.over) return null;
    if (m.phase == 'round') return m.nextOk[player] ? null : {'a': 'next'};
    return DominoBot.move(m, player, const [1, 3, 4][level.clamp(0, 2)], r);
  }
  if (m is QuizModel) {
    if (!m.started || m.reveal || m.over || m.answers[player] >= 0 || m.out[player]) return null;
    // وقت جوابه ثابت لكل سؤال (الأقوى أسرع)، وبعدها يجاوب صح باحتمال حسب المستوى
    final lv = level.clamp(0, 2);
    final wait = const [6.0, 4.0, 2.5][lv] + ((m.qi * 37 + player * 11) % 30) / 10;
    if (m.time - m.askedAt < wait) return null;
    if (peek) return const {};
    final right = r.nextDouble() < const [0.4, 0.65, 0.85][lv];
    final c = m.current.$3;
    var a = c;
    if (!right) a = (c + 1 + r.nextInt(3)) % 4;
    return {'m': 'ans', 'a': a};
  }
  if (m is ReactionModel) {
    if (!m.started || m.over || m.out[player] || m.fouled[player]) return null;
    final lv = level.clamp(0, 2);
    final key = (m.nextAt * 1000).round() + player * 13 + m.score[0] * 7;
    if (m.rs == ReactionModel.go) {
      final due = const [0.62, 0.42, 0.27][lv] + (key % 20) / 100;
      if (m.time - m.goAt < due) return null;
    } else if (m.rs == ReactionModel.decoy) {
      // الضعيف يقع بالخدعة أحياناً
      final falls = (key % 100) < const [35, 10, 0][lv];
      if (!falls || m.time < m.decoyEnd - 0.3) return null;
    } else {
      return null;
    }
    return const {'m': 'tap', 'w': 0};
  }
  if (m is MuhaibesModel) return MuhaibesBot.move(m, player, level, r);
  if (m is PigeonModel) return PigeonBot.move(m, player, level, r, peek: peek);
  if (m is HockeyModel) {
    if (peek) return !m.over && !m.counting ? const {'w': 0} : null;
    return HockeyBot.move(m, player, level, r);
  }
  if (m is TugModel) {
    if (m.over || m.counting) return null;
    final rate = const [3.5, 5.5, 8.0][level.clamp(0, 2)];
    final want = (rate * (m.time - m.startAt) * (0.9 + 0.2 * ((m.time * 3).floor() % 2))).floor();
    if (m.stopping) return null;
    if (m.taps[player] >= want) return null;
    return const {'m': 'tap', 'w': 0};
  }
  if (m is Connect4Model) {
    if (peek) return !m.over && m.turn == player ? const {} : null;
    return Connect4Bot.move(m, player, r);
  }
  if (m is XoModel) {
    if (peek) return !m.over && m.turn == player ? const {} : null;
    return XoBot.move(m, player, r);
  }
  return null;
}

GameModel createModel(String id, {required int players, required bool crazy, required int seed, int level = -1}) {
  switch (id) {
    case 'xo':
      return XoModel(players: players, crazy: crazy, seed: seed, level: level < 0 ? 0 : level);
    case 'connect4':
      return Connect4Model(players: players, crazy: crazy, seed: seed, level: level < 0 ? 0 : level);
    case 'tug':
      return TugModel(players: players, crazy: crazy, seed: seed, level: level < 0 ? 0 : level);
    case 'pigeon':
      return PigeonModel(players: players, crazy: level >= 0 ? level >= 1 : crazy, seed: seed, level: level);
    case 'hockey':
      return HockeyModel(players: players, crazy: crazy, seed: seed, level: level < 0 ? 0 : level);
    case 'reaction':
      return ReactionModel(players: players, crazy: crazy, seed: seed, level: level < 0 ? 1 : level);
    case 'quiz':
      return QuizModel(players: players, crazy: crazy, seed: seed, level: level < 0 ? 1 : level);
    case 'muhaibes':
      return MuhaibesModel(players: players, crazy: crazy, seed: seed, level: level < 0 ? 1 : level);
    case 'domino':
      return DominoModel(players: players, crazy: crazy, seed: seed, level: level);
    case 'whois':
      return WhoisModel(players: players, crazy: crazy, seed: seed);
    case 'spy':
      return SpyModel(players: players, crazy: crazy, seed: seed);
  }
  throw ArgumentError('unknown game $id');
}

GameModel restoreModel(Map<String, dynamic> j) {
  switch (j['id']) {
    case 'xo':
      return XoModel.restore(j);
    case 'connect4':
      return Connect4Model.restore(j);
    case 'tug':
      return TugModel.restore(j);
    case 'pigeon':
      return PigeonModel.restore(j);
    case 'hockey':
      return HockeyModel.restore(j);
    case 'reaction':
      return ReactionModel.restore(j);
    case 'quiz':
      return QuizModel.restore(j);
    case 'muhaibes':
      return MuhaibesModel.restore(j);
    case 'domino':
      return DominoModel.restore(j);
    case 'whois':
      return WhoisModel.restore(j);
    case 'spy':
      return SpyModel.restore(j);
  }
  throw ArgumentError('unknown game ${j['id']}');
}
