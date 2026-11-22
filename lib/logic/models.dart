import 'connect4_logic.dart';
import 'domino_logic.dart';
import 'game_model.dart';
import 'hockey_logic.dart';
import 'muhaibes_logic.dart';
import 'pigeon_logic.dart';
import 'quiz_logic.dart';
import 'reaction_logic.dart';
import 'tug_logic.dart';
import 'whois_logic.dart';
import 'xo_logic.dart';

/// كل الألعاب اللي قواعدها صارت على الأساس المشترك (تشتغل أونلاين)
const onlineGames = {'xo', 'connect4', 'tug', 'pigeon', 'hockey', 'reaction', 'quiz', 'muhaibes', 'domino', 'whois'};

GameModel createModel(String id, {required int players, required bool crazy, required int seed}) {
  switch (id) {
    case 'xo':
      return XoModel(players: players, crazy: crazy, seed: seed);
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
      return DominoModel(players: players, crazy: crazy, seed: seed);
    case 'whois':
      return WhoisModel(players: players, crazy: crazy, seed: seed);
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
  }
  throw ArgumentError('unknown game ${j['id']}');
}
