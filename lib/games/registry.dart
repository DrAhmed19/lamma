import 'package:flutter/material.dart';

import '../net/room.dart';
import '../ui/icons.dart';
import 'connect4.dart';
import 'hockey.dart';
import 'pigeon.dart';
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

  String get playersLabel =>
      minPlayers == maxPlayers ? '$minPlayers لاعبين' : '$minPlayers - $maxPlayers لاعبين';
}

final games = <GameInfo>[
  GameInfo(
    id: 'pigeon',
    title: 'الحمامة',
    tagline: 'نيشن واصطاد الحمامة',
    howTo: 'كل واحد عنده مصيادة بزاويته. اسحب لورا وعوف حتى ترمي الحجارة على الحمامة. أول واحد يوصل 10 إصابات يفوز.',
    crazyHowTo: 'دقيقة وحدة والأكثر نقاط يفوز! الذهبية بنقطتين، الغراب الأسود ينقّصك نقطة، وأسراب تمر بسرعة. التقط الصناديق بالحجارة: نار تخترق، ثلاثية، وتجميد للخصوم. ثلاث إصابات ورا بعض = كومبو!',
    minPlayers: 2,
    maxPlayers: 4,
    colors: const [Color(0xFF2EB8E6), Color(0xFF0B4566)],
    icon: PigeonIcon.new,
    build: (n, crazy) => PigeonGame(players: n, crazy: crazy),
  ),
  GameInfo(
    id: 'hockey',
    title: 'هوكي',
    tagline: 'دافع عن هدفك وسجّل',
    howTo: 'كل واحد يحرك مضربه بإصبعه بنصّه من الشاشة. ضرب القرص لهدف خصمك. أول واحد يوصل 7 أهداف يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFF1E6BFF), Color(0xFF0B2A6B)],
    icon: HockeyIcon.new,
    build: (n, _) => const HockeyGame(),
  ),
  GameInfo(
    id: 'reaction',
    title: 'أسرع إصبع',
    tagline: 'لا تضغط قبل الأخضر!',
    howTo: 'انتظر لما الدائرة بالنص تصير خضراء، وبعدها اضغط على منطقتك بأسرع ما يمكن. إذا ضغطت قبلها تنطرد من الجولة. انتبه للبرتقالي، هو خدعة! أول واحد يوصل 5 نقاط يفوز.',
    minPlayers: 2,
    maxPlayers: 4,
    colors: const [Color(0xFF16B46A), Color(0xFF0A4A33)],
    icon: ReactionIcon.new,
    build: (n, _) => ReactionGame(players: n),
  ),
  GameInfo(
    id: 'tug',
    title: 'شد الحبل',
    tagline: 'اضغط أسرع من خصمك',
    howTo: 'كل واحد يضغط على نصّه من الشاشة بأسرع ما يگدر. كل ضغطة تسحب الحبل صوبك. اللي يوصل الحبل لخطه يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFFFF5A5F), Color(0xFF7A1630)],
    icon: TugIcon.new,
    build: (n, _) => const TugGame(),
    online: (room) => TugGame(room: room),
  ),
  GameInfo(
    id: 'connect4',
    title: 'أربعة بالصف',
    tagline: 'رتّب أربعة قبل خصمك',
    howTo: 'بالدور، اختار عمود حتى تنزل قطعتك. أول واحد يصفّ أربع قطع بخط واحد (عمودي، أفقي أو مايل) يفوز.',
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
    tagline: 'الكلاسيكية الأصلية',
    howTo: 'بالدور، كل واحد يحط علامته. أول واحد يصفّ ثلاثة بخط واحد يفوز.',
    minPlayers: 2,
    maxPlayers: 2,
    colors: const [Color(0xFF8B6CFF), Color(0xFF34207A)],
    icon: XoIcon.new,
    build: (n, _) => const XoGame(),
    online: (room) => XoGame(room: room),
  ),
];
