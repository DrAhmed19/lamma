import 'connect4_logic.dart';
import 'game_model.dart';
import 'tug_logic.dart';
import 'xo_logic.dart';

/// كل الألعاب اللي قواعدها صارت على الأساس المشترك (تشتغل أونلاين)
const onlineGames = {'xo', 'connect4', 'tug'};

GameModel createModel(String id, {required int players, required bool crazy, required int seed}) {
  switch (id) {
    case 'xo':
      return XoModel(players: players, crazy: crazy, seed: seed);
    case 'connect4':
      return Connect4Model(players: players, crazy: crazy, seed: seed);
    case 'tug':
      return TugModel(players: players, crazy: crazy, seed: seed);
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
  }
  throw ArgumentError('unknown game ${j['id']}');
}
