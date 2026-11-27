import 'dart:math' as math;

import 'connect4_logic.dart';
import 'domino_bot.dart';
import 'domino_logic.dart';
import 'game_model.dart';
import 'hockey_logic.dart';
import 'muhaibes_logic.dart';
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
const botGames = {'domino', 'xo'};

/// ألعاب بيها مستويات (سهل/متوسط/صعب) بدل عادي/مجنون
const levelGames = {'domino', 'xo'};

/// حركة الكمبيوتر بلعبة [m] للاعب [player] بمستوى [level] (0-2). null = ماكو شي يسويه هسة.
/// [peek] = بس نسأل "عنده شي يسويه؟" بدون ما يحسب الحركة (رخيص، كل إطار).
Map<String, dynamic>? botMove(GameModel m, int player, int level, math.Random r, {bool peek = false}) {
  if (m is DominoModel) {
    if (m.over) return null;
    if (m.phase == 'round') return m.nextOk[player] ? null : {'a': 'next'};
    return DominoBot.move(m, player, const [1, 3, 4][level.clamp(0, 2)], r);
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
      return Connect4Model(players: players, crazy: crazy, seed: seed);
    case 'tug':
      return TugModel(players: players, crazy: crazy, seed: seed);
    case 'pigeon':
      return PigeonModel(players: players, crazy: crazy, seed: seed);
    case 'hockey':
      return HockeyModel(players: players, crazy: crazy, seed: seed);
    case 'reaction':
      return ReactionModel(players: players, crazy: crazy, seed: seed);
    case 'quiz':
      return QuizModel(players: players, crazy: crazy, seed: seed);
    case 'muhaibes':
      return MuhaibesModel(players: players, crazy: crazy, seed: seed);
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
