import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// صور رمزية بسيطة يختار منها اللاعب
const kAvatars = ['😀', '😎', '🦁', '🐱', '🐼', '🦊', '🐸', '🐵', '🦄', '🐯', '🐙', '🐢', '⚽', '🚀', '🌟', '👑'];

/// إحصائية لعبة وحدة
class GameStat {
  GameStat({this.played = 0, this.won = 0});
  int played, won;

  Map<String, dynamic> toJson() => {'p': played, 'w': won};
  factory GameStat.fromJson(Map<String, dynamic> j) => GameStat(played: j['p'] as int? ?? 0, won: j['w'] as int? ?? 0);
}

/// سجلّي ضد خصم واحد (بالاسم، أونلاين بس)
class Rival {
  Rival({this.won = 0, this.lost = 0, this.streak = 0});

  /// كم مرة فزت عليه / فاز عليّ
  int won, lost;

  /// ورا بعض: موجب = فزت عليه هالعدد، سالب = فاز عليّ
  int streak;

  Map<String, dynamic> toJson() => {'w': won, 'l': lost, 's': streak};
  factory Rival.fromJson(Map<String, dynamic> j) =>
      Rival(won: j['w'] as int? ?? 0, lost: j['l'] as int? ?? 0, streak: j['s'] as int? ?? 0);
}

/// لقب يحصل عليه اللاعب
class PlayerTitle {
  const PlayerTitle(this.icon, this.name, this.how);
  final String icon, name, how;
}

/// ملف اللاعب: الاسم والصورة والإحصائيات. ينحفظ على الجهاز.
class Profile extends ChangeNotifier {
  Profile._();
  static final Profile I = Profile._();

  SharedPreferences? _p;
  String name = '';
  String avatar = kAvatars.first;

  /// رقم عشوائي ثابت للجهاز (يتعرّف بيه بالغرف)
  String deviceId = _newId();

  static String _newId() {
    final r = math.Random.secure();
    return List.generate(20, (_) => r.nextInt(36).toRadixString(36)).join();
  }
  final stats = <String, GameStat>{};

  /// سجلّي ضد كل خصم (للإحصائية المضحكة بصورة النتيجة)
  final rivals = <String, Rival>{};

  /// كم مرة فزت ورا بعض بكل لعبة (أونلاين)
  final winStreak = <String, int>{};

  /// اللي حاظرهم (رقم عام → اسم): ما ينجمع وياهم باللعب ويا الغرباء
  final blocked = <String, String>{};

  void block(String pid, String name) {
    if (pid.isEmpty) return;
    blocked[pid] = name;
    notifyListeners();
    _save();
  }

  void unblock(String pid) {
    blocked.remove(pid);
    notifyListeners();
    _save();
  }

  /// أفضل زمن استجابة بلعبة أسرع إصبع (ملّي ثانية)، 0 = ما أكو
  int bestReaction = 0;
  int tournamentsWon = 0;
  int onlineGames = 0;

  bool get hasName => name.trim().isNotEmpty;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      name = _p!.getString('name') ?? '';
      final id = _p!.getString('deviceId');
      if (id != null && id.length >= 10) {
        deviceId = id;
      } else {
        await _p!.setString('deviceId', deviceId);
      }
      avatar = _p!.getString('avatar') ?? kAvatars[math.Random().nextInt(kAvatars.length)];
      bestReaction = _p!.getInt('bestReaction') ?? 0;
      tournamentsWon = _p!.getInt('tours') ?? 0;
      onlineGames = _p!.getInt('onlineGames') ?? 0;
      final s = _p!.getString('stats');
      if (s != null) {
        (jsonDecode(s) as Map<String, dynamic>).forEach((k, v) => stats[k] = GameStat.fromJson(v as Map<String, dynamic>));
      }
      final r = _p!.getString('rivals');
      if (r != null) {
        (jsonDecode(r) as Map<String, dynamic>).forEach((k, v) => rivals[k] = Rival.fromJson(v as Map<String, dynamic>));
      }
      final bl = _p!.getString('blocked');
      if (bl != null) {
        (jsonDecode(bl) as Map<String, dynamic>).forEach((k, v) => blocked[k] = '$v');
      }
      final ws = _p!.getString('winStreak');
      if (ws != null) {
        (jsonDecode(ws) as Map<String, dynamic>).forEach((k, v) => winStreak[k] = v as int);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = _p ??= await SharedPreferences.getInstance();
      await p.setString('name', name);
      await p.setString('avatar', avatar);
      await p.setInt('bestReaction', bestReaction);
      await p.setInt('tours', tournamentsWon);
      await p.setInt('onlineGames', onlineGames);
      await p.setString('stats', jsonEncode({for (final e in stats.entries) e.key: e.value.toJson()}));
      await p.setString('rivals', jsonEncode({for (final e in rivals.entries) e.key: e.value.toJson()}));
      await p.setString('winStreak', jsonEncode(winStreak));
      await p.setString('blocked', jsonEncode(blocked));
    } catch (_) {}
  }

  void setIdentity(String n, String a) {
    final t = n.trim();
    name = t.length > 14 ? t.substring(0, 14) : t;
    avatar = a;
    notifyListeners();
    _save();
  }

  /// نهاية مباراة. won = null على نفس الجهاز (ما نعرف منو انت).
  /// أونلاين: [beat] = الخصوم اللي فزت عليهم، [lostTo] = اللي فاز عليّ، [drew] = تعادلت وياهم.
  void recordGame(
    String game, {
    bool? won,
    bool online = false,
    List<String> beat = const [],
    String? lostTo,
    List<String> drew = const [],
  }) {
    final s = stats.putIfAbsent(game, GameStat.new);
    s.played++;
    if (won == true) s.won++;
    if (online) {
      onlineGames++;
      winStreak[game] = won == true ? (winStreak[game] ?? 0) + 1 : 0;
      for (final n in beat) {
        final r = rivals.putIfAbsent(n, Rival.new);
        r.won++;
        r.streak = r.streak > 0 ? r.streak + 1 : 1;
      }
      if (lostTo != null) {
        final r = rivals.putIfAbsent(lostTo, Rival.new);
        r.lost++;
        r.streak = r.streak < 0 ? r.streak - 1 : -1;
      }
      for (final n in drew) {
        rivals[n]?.streak = 0;
      }
      // ما نخلي القائمة تكبر بلا حد
      if (rivals.length > 60) {
        final weakest = rivals.entries.reduce((a, b) => a.value.won + a.value.lost <= b.value.won + b.value.lost ? a : b).key;
        rivals.remove(weakest);
      }
    }
    notifyListeners();
    _save();
  }

  void recordReaction(int ms) {
    if (ms <= 0) return;
    if (bestReaction == 0 || ms < bestReaction) {
      bestReaction = ms;
      notifyListeners();
      _save();
    }
  }

  void recordTournamentWin() {
    tournamentsWon++;
    notifyListeners();
    _save();
  }

  int get totalPlayed => stats.values.fold(0, (a, s) => a + s.played);
  int get totalWon => stats.values.fold(0, (a, s) => a + s.won);

  /// الألقاب اللي حصل عليها (تنحسب من الإحصائيات)
  List<PlayerTitle> get titles {
    final t = <PlayerTitle>[];
    final p = totalPlayed, w = totalWon;
    if (p >= 1) t.add(const PlayerTitle('🎮', 'لاعب جديد', 'العب أول مباراة'));
    if (p >= 20) t.add(const PlayerTitle('🔥', 'لاعب نشيط', 'العب 20 مباراة'));
    if (p >= 100) t.add(const PlayerTitle('🏅', 'محترف', 'العب 100 مباراة'));
    if (w >= 10) t.add(const PlayerTitle('🏆', 'بطل', 'فُز 10 مرات عبر الإنترنت'));
    if (w >= 50) t.add(const PlayerTitle('👑', 'أسطورة', 'فُز 50 مرة عبر الإنترنت'));
    if (bestReaction > 0 && bestReaction < 300) t.add(const PlayerTitle('⚡', 'البرق', 'استجابة أسرع من 300 ملّي ثانية'));
    if (tournamentsWon >= 1) t.add(const PlayerTitle('🥇', 'بطل البطولة', 'فُز ببطولة'));
    if (onlineGames >= 10) t.add(const PlayerTitle('🌍', 'اجتماعي', 'العب 10 مباريات عبر الهواتف'));
    return t;
  }

  /// كل الألقاب الممكنة (حتى نعرض اللي بعدها مقفلة)
  static const allTitles = [
    PlayerTitle('🎮', 'لاعب جديد', 'العب أول مباراة'),
    PlayerTitle('🔥', 'لاعب نشيط', 'العب 20 مباراة'),
    PlayerTitle('🏅', 'محترف', 'العب 100 مباراة'),
    PlayerTitle('🏆', 'بطل', 'فُز 10 مرات عبر الإنترنت'),
    PlayerTitle('👑', 'أسطورة', 'فُز 50 مرة عبر الإنترنت'),
    PlayerTitle('⚡', 'البرق', 'استجابة أسرع من 300 ملّي ثانية'),
    PlayerTitle('🥇', 'بطل البطولة', 'فُز ببطولة'),
    PlayerTitle('🌍', 'اجتماعي', 'العب 10 مباريات عبر الهواتف'),
  ];
}
