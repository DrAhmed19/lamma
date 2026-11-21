import 'package:flutter/material.dart';

import '../net/room.dart';
import '../ui/icons.dart';
import 'connect4.dart';
import 'hockey.dart';
import 'pigeon.dart';
import 'quiz.dart';
import 'reaction.dart';
import 'tug.dart';
import 'xo.dart';

class GameInfo {
  const GameInfo({
    required this.id,
    required this.title,
    required this.tagline,
    required this.howTo,
    required this.minPlayers,
    required this.maxPlayers,
    required this.colors,
    required this.icon,
    required this.build,
    this.crazyHowTo,
    this.online,
  });

  final String id;
  final String title;
  final String tagline;
  final String howTo;
  final int minPlayers;
  final int maxPlayers;
  final List<Color> colors;
  final CustomPainter Function() icon;

  /// crazy = الوضع المجنون (بس للألعاب اللي عندها crazyHowTo)
  final Widget Function(int players, bool crazy) build;

  /// شرح الوضع المجنون. إذا null اللعبة بس بوضع عادي.
  final String? crazyHowTo;

  /// اللعب أونلاين (كل واحد بتلفونه). إذا null اللعبة بعدها ما تدعم الأونلاين.
  final Widget Function(RoomConn room)? online;

  String get playersLabel => minPlayers == maxPlayers ? 'لاعبان' : 'من $minPlayers إلى $maxPlayers لاعبين';
}

GameInfo? gameById(String? id) => games.where((g) => g.id == id).firstOrNull;

final games = <GameInfo>[
  GameInfo(
    id: 'pigeon',
    title: 'الحمامة',
    tagline: 'صوّب واصطد الحمامة',
    howTo: 'لكل لاعب مقلاع في زاويته. اسحب إلى الخلف ثم اترك لترمي الحجارة على الحمامة. أول من يصل إلى 10 إصابات يفوز.',
    crazyHowTo:
        'دقيقة واحدة، والأكثر نقاطًا يفوز! الحمامة الذهبية بنقطتين، والغراب الأسود يُنقص نقطة، وأسراب تمر بسرعة. أصب الصناديق لتحصل على قوة: نار تخترق، أو ثلاث حجارة، أو تجميد للخصوم. ثلاث إصابات متتالية تمنحك نقطة إضافية.',
    minPlayers: 2,
    maxPlayers: 4,
    colors: const [Color(0xFF2EB8E6), Color(0xFF0B4566)],
    icon: PigeonIcon.new,
    build: (n, crazy) => PigeonGame(players: n, crazy: crazy),
    online: (room) => PigeonGame(players: room.seats.length, crazy: room.crazy, room: room),
  ),
  GameInfo(
    id: 'quiz',
    title: 'سؤال وجواب',
    tagline: 'من يعرف أكثر؟',
    howTo: 'عشرة أسئلة في المعلومات العامة. اختر الإجابة الصحيحة قبل انتهاء الوقت. كل إجابة صحيحة بنقطة، وأسرع إجابة صحيحة تحصل على نقطة إضافية.',
    minPlayers: 2,
    maxPlayers: 4,
    colors: const [Color(0xFF8B5CF6), Color(0xFF3B1C8C)],
    icon: QuizIcon.new,
    build: (n, _) => QuizGame(players: n),
    online: (room) => QuizGame(players: room.seats.length, room: room),
  ),
  GameInfo(
    id: 'hockey',
    title: 'الهوكي',
    tagline: 'دافع عن مرماك وسجّل',
    howTo: 'حرّك مضربك بإصبعك في نصفك من الشاشة، واضرب القرص نحو مرمى خصمك. أول من يسجّل 7 أهداف يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFF1E6BFF), Color(0xFF0B2A6B)],
    icon: HockeyIcon.new,
    build: (n, _) => const HockeyGame(),
    online: (room) => HockeyGame(room: room),
  ),
  GameInfo(
    id: 'reaction',
    title: 'أسرع إصبع',
    tagline: 'لا تضغط قبل اللون الأخضر!',
    howTo: 'انتظر حتى تصبح الدائرة في المنتصف خضراء، ثم اضغط بأسرع ما يمكن. إذا ضغطت قبلها تخرج من الجولة. احذر من اللون البرتقالي فهو خدعة! أول من يصل إلى 5 نقاط يفوز.',
    minPlayers: 2,
    maxPlayers: 4,
    colors: const [Color(0xFF16B46A), Color(0xFF0A4A33)],
    icon: ReactionIcon.new,
    build: (n, _) => ReactionGame(players: n),
    online: (room) => ReactionGame(players: room.seats.length, room: room),
  ),
  GameInfo(
    id: 'tug',
    title: 'شدّ الحبل',
    tagline: 'اضغط أسرع من خصمك',
    howTo: 'اضغط على الشاشة بأسرع ما تستطيع. كل ضغطة تسحب الحبل نحوك، ومن يوصل الحبل إلى خطّه يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFFFF5A5F), Color(0xFF7A1630)],
    icon: TugIcon.new,
    build: (n, _) => const TugGame(),
    online: (room) => TugGame(room: room),
  ),
  GameInfo(
    id: 'connect4',
    title: 'أربعة في صف',
    tagline: 'رتّب أربعًا قبل خصمك',
    howTo: 'بالتناوب، اختر عمودًا لتُسقط قطعتك فيه. أول من يصفّ أربع قطع في خط واحد (عمودي أو أفقي أو مائل) يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFFFFB627), Color(0xFF7A4A06)],
    icon: Connect4Icon.new,
    build: (n, _) => const Connect4Game(),
    online: (room) => Connect4Game(room: room),
  ),
  GameInfo(
    id: 'xo',
    title: 'إكس أو',
    tagline: 'اللعبة الكلاسيكية',
    howTo: 'بالتناوب، يضع كل لاعب علامته. أول من يصفّ ثلاث علامات في خط واحد يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFF8B6CFF), Color(0xFF34207A)],
    icon: XoIcon.new,
    build: (n, _) => const XoGame(),
    online: (room) => XoGame(room: room),
  ),
];
