import 'package:flutter/material.dart';

import '../net/room.dart';
import '../ui/icons.dart';
import 'connect4.dart';
import 'domino.dart';
import 'hockey.dart';
import 'muhaibes.dart';
import 'pigeon.dart';
import 'quiz.dart';
import 'reaction.dart';
import 'tug.dart';
import 'spy.dart';
import 'whois.dart';
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
    this.local = true,
    this.quick = true,
    this.counts,
    this.modeLabels,
    this.levels,
    this.play,
    this.teamsAt = const [],
  });

  /// نظام المستويات: شرح سطر لكل مستوى (سهل، متوسط، صعب). إذا موجود، "على هذا الجهاز"
  /// يفتح شاشة البداية (المستوى + منو يلعب ويا الكمبيوتر) بدل عادي/مجنون.
  final List<String>? levels;

  /// تشغيل على هذا الجهاز بمستوى وتشكيلة (bots[i] = المقعد i كمبيوتر)
  final Widget Function(int level, List<bool> bots)? play;

  /// أعداد اللاعبين اللي تصير بيها فرق (الدومينو: 4)
  final List<int> teamsAt;

  /// أعداد اللاعبين المسموحة إذا مو كل الأعداد بين الأقل والأكثر (الدومينو: 2 أو 4)
  final List<int>? counts;

  /// أسماء الوضعين بدل "عادي/مجنون" (الدومينو: 50 / 100 نقطة)
  final List<String>? modeLabels;

  List<int> get allowedCounts => counts ?? [for (var k = minPlayers; k <= maxPlayers; k++) k];
  bool fits(int n) => allowedCounts.contains(n);

  /// تنلعب "على هذا الجهاز"؟ (المحيبس لا: بيها أسرار بين الفريقين)
  final bool local;

  /// تظهر بـ"لمّة جديدة" (اللعب ويا الغرباء)؟ الألعاب الاجتماعية لا.
  final bool quick;

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

  String get playersLabel => minPlayers == maxPlayers
      ? 'لاعبان'
      : counts != null
          ? '${counts!.join(' أو ')} لاعبين'
          : 'من $minPlayers إلى $maxPlayers لاعبين';
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
    levels: const [
      'حمام فقط بسرعة هادئة. أول من يصل 10 نقاط يفوز.',
      'حمامة ذهبية بنقطتين، وغراب يخصم نقطة، وصناديق قوى، والوقت دقيقة واحدة.',
      'كل ما سبق، والطيور أسرع بكثير. والكمبيوتر بأقوى حالاته.',
    ],
    play: (level, bots) => PigeonGame(players: bots.length, level: level, bots: bots),
    online: (room) => PigeonGame(players: room.seats.length, crazy: room.level >= 1, room: room),
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
    levels: const [
      'عشرة أسئلة، والكمبيوتر هادئ ويغلط كثيرًا.',
      'عشرة أسئلة بنقاط السرعة. الكمبيوتر يعرف أغلب الأجوبة.',
      'الجواب الخاطئ ينقص نقطة! والكمبيوتر سريع ودقيق.',
    ],
    play: (level, bots) => QuizGame(players: bots.length, level: level, bots: bots),
    online: (room) => QuizGame(players: room.seats.length, room: room),
  ),
  GameInfo(
    id: 'domino',
    title: 'الدومينو',
    tagline: 'صفّ القطع وخلّصها أولًا',
    howTo: 'كل لاعب معه 7 قطع. ضع قطعة يطابق أحد رقميها طرف السلسلة. من ينهي قطعه أولًا يأخذ مجموع نقاط قطع خصومه، '
        'وإذا أُغلقت اللعبة يأخذ صاحب المجموع الأقل. بلاعبَين: اسحب إذا لم تجد قطعة مناسبة. بأربعة لاعبين: فريقان، كل شريكين متقابلان. '
        'اختر المستوى قبل اللعب: السهل هو الدومينو العائلي، والمتوسط والصعب «الخمسات».',
    crazyHowTo: 'نفس القواعد، لكن الفوز عند 100 نقطة.',
    modeLabels: const ['50 نقطة', '100 نقطة'],
    minPlayers: 2,
    maxPlayers: 4,
    counts: const [2, 4],
    colors: const [Color(0xFF1F8A63), Color(0xFF0B3A2A)],
    icon: DominoIcon.new,
    build: (n, long) => DominoGame(players: n, long: long),
    levels: const [
      'الدومينو العائلي: السلسلة بجهتين، والنقاط آخر الجولة، والفوز عند 50. الأحجار الصالحة تضوي.',
      'الخمسات: أول دبل يتفرّع لأربع جهات، وكل ما صار مجموع الأطراف 5 أو 10 أو 15... تاخذه نقاط فورًا. الفوز عند 100.',
      'الخمسات حتى 200، بدون إضاءة للأحجار الصالحة، والدور 15 ثانية بس. والكمبيوتر بأقوى حالاته.',
    ],
    play: (level, bots) => DominoGame(players: bots.length, level: level, bots: bots),
    teamsAt: const [4],
    online: (room) => DominoGame(players: room.seats.length, long: room.crazy, room: room),
  ),
  GameInfo(
    id: 'muhaibes',
    title: 'المحيبس',
    tagline: 'وين المحبس؟',
    howTo: 'فريقان. الفريق الذي معه المحبس يخبّئه في إحدى القبضات، وقائد الفريق الآخر يبحث عنه: '
        '«طالعة» تفتح قبضة فارغة، و«بات» تعني أن المحبس هنا. إذا أصاب في «بات» أخذ فريقه نقاطًا '
        'بعدد القبضات المغلقة الباقية وانتقل المحبس إليهم، وإذا أخطأ أخذ الفريق الآخر النقاط. أول فريق يصل إلى 15 يفوز. '
        'كل لاعب على هاتفه.',
    minPlayers: 4,
    maxPlayers: 8,
    colors: const [Color(0xFFC2185B), Color(0xFF4A1030)],
    icon: MuhaibesIcon.new,
    build: (_, __) => const SizedBox.shrink(), // ما تنلعب على نفس الجهاز
    levels: const [
      'وقت أطول للتخبئة والتخمين، مناسب للعائلة.',
      'الوقت العادي: 20 ثانية للتخبئة و15 لكل حركة.',
      'وقت قصير جدًا: 12 ثانية للتخبئة و9 لكل حركة. فكّر بسرعة!',
    ],
    online: (room) => MuhaibesGame(room: room),
    local: false,
    quick: false,
  ),
  GameInfo(
    id: 'whois',
    title: 'منو بينا؟',
    tagline: 'من الأنسب لهذا اللقب؟',
    howTo: 'في كل جولة سؤال مضحك، والكل يصوّت سرًّا على لاعب يراه الأنسب (لا يمكنك التصويت لنفسك). '
        'بعد الكشف ينال الأكثر أصواتًا لقب الجولة، وبعد ثمانية أسئلة يحصل كل لاعب على لقبه النهائي. '
        'بدون نقاط، للضحك فقط. كل لاعب على هاتفه.',
    crazyHowTo: 'نفس اللعبة، لكن يُكشف في كل جولة من صوّت لمن.',
    modeLabels: const ['أصوات سرية', 'كشف الأصوات'],
    minPlayers: 3,
    maxPlayers: 8,
    colors: const [Color(0xFF2E8BFF), Color(0xFF14295E)],
    icon: WhoisIcon.new,
    build: (_, __) => const SizedBox.shrink(), // ما تنلعب على نفس الجهاز
    online: (room) => WhoisGame(room: room),
    local: false,
    quick: false,
  ),
  GameInfo(
    id: 'spy',
    title: 'الجاسوس',
    tagline: 'من بينكم لا يعرف المكان؟',
    howTo: 'الجميع يعرف المكان إلا الجاسوس. اجلسوا معًا واسألوا بعضكم بصوتكم أسئلة عن المكان دون ذكره: '
        'من عليه الدور يسأل أي لاعب، ثم يسأل ذلك اللاعب غيره. يمكن لأي لاعب طلب التصويت. '
        'إذا كشفتم الجاسوس فله حزرة واحدة للمكان. ينال الجاسوس نقطتين إن نجا أو حزر، والباقون نقطة إن كشفوه. كل لاعب على هاتفه.',
    crazyHowTo: 'جاسوسان بدل جاسوس واحد (عند 6 لاعبين فأكثر).',
    modeLabels: const ['جاسوس واحد', 'جاسوسان'],
    minPlayers: 3,
    maxPlayers: 8,
    colors: const [Color(0xFFC0392B), Color(0xFF3A0F0A)],
    icon: SpyIcon.new,
    build: (_, __) => const SizedBox.shrink(), // ما تنلعب على نفس الجهاز
    online: (room) => SpyGame(room: room),
    local: false,
    quick: false,
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
    levels: const [
      'الطاولة العادية: سجّل 7 أهداف قبل خصمك.',
      'تظهر مصدّات برتقالية بنص الطاولة وتختفي بالتناوب، والقرص يرتد عنها.',
      'المصدّات، والقرص يزداد سرعة مع كل ضربة. والكمبيوتر بأقوى حالاته.',
    ],
    play: (level, bots) => HockeyGame(level: level, bots: bots),
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
    levels: const [
      'اضغط لمّا تصير الدائرة خضراء. بدون خدع، والكمبيوتر بطيء.',
      'أحيانًا تظهر دائرة برتقالية خدعة، والضغط عليها يخرجك من الجولة.',
      'الخدع كثيرة، والكمبيوتر سريع جدًا.',
    ],
    play: (level, bots) => ReactionGame(players: bots.length, level: level, bots: bots),
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
    levels: const [
      'اضغط بأسرع ما تقدر. كل ضغطة تسحب الحبل نحوك.',
      'تظهر لحظات «توقف!» بين الحين والآخر: من يضغط فيها يرجع الحبل إلى الخلف!',
      '«توقف!» تأتي أكثر وأسرع، والكمبيوتر يضغط بسرعة كبيرة.',
    ],
    play: (level, bots) => TugGame(level: level, bots: bots),
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
    levels: const [
      'أربعة بالصف العادية: اصفّ أربع قطع في خط واحد.',
      'قنبلة واحدة لكل لاعب: تنزل وتنفجر وتمسح القطع اللي حولها، وتتغير اللوحة كلها!',
      '«اسحب من تحت»: بدل الإسقاط تگدر تسحب قطعتك من أسفل أي عمود، فتنزل الباقي. حتى الخصم ممكن يفوز بحركتك.',
    ],
    play: (level, bots) => Connect4Game(level: level, bots: bots),
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
    levels: const [
      'إكس أو العادية: صفّ ثلاث علامات في خط واحد.',
      'ثلاث قطع فقط لكل لاعب: عندما تضع الرابعة تختفي أقدم قطعة لك (تنبض قبل أن تختفي). لا تعادل!',
      'إكس أو الكبيرة: 9 لوحات صغيرة. المربع الذي تلعب فيه يحدد اللوحة التي يلعب فيها خصمك. اربح ثلاث لوحات في خط.',
    ],
    play: (level, bots) => XoGame(level: level, bots: bots),
    online: (room) => XoGame(room: room),
  ),
];
