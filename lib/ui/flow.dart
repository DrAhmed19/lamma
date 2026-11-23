// الطرق البسيطة للعب ويا الآخرين. المستخدم ما يحتاج يعرف إنترنت لو شبكة محلية:
//  - "مع أصدقائي": نسوّي غرفة بالإنترنت، وإذا ماكو إنترنت (بأندرويد) نسوّيها على نفس الواي فاي.
//  - "انضمام": يكتب الرمز بس، ونحن ندوّر عليه بالإنترنت وبالشبكة المحلية.
//  - "مع لاعبين آخرين": لعب سريع بالإنترنت.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/profile.dart';
import '../games/registry.dart';
import '../net/lan.dart';
import '../net/room.dart';
import 'kit.dart';
import 'online.dart';
import 'profile_ui.dart';
import 'theme.dart';

/// نافذة انتظار صغيرة أثناء عملية
Future<T?> withBusy<T>(BuildContext context, String text, Future<T> Function() job) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 14),
              Material(color: Colors.transparent, child: Text(text, style: body(16, weight: FontWeight.w800, color: L.ink))),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await job();
  } finally {
    nav.pop();
  }
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      backgroundColor: error ? const Color(0xFFE5484D) : L.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      content: Text(text, style: body(15, weight: FontWeight.w700, color: Colors.white)),
    ));
}

/// نافذة رسالة بسيطة بزر "حسنًا"
Future<void> showNotice(BuildContext context, {required IconData icon, required String title, required String text}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 48, color: const Color(0xFFFFB627)),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: display(26, color: L.ink)),
              const SizedBox(height: 6),
              Text(text, textAlign: TextAlign.center, style: body(15, weight: FontWeight.w700, color: L.ink)),
              const SizedBox(height: 18),
              ChunkyButton(label: 'حسنًا', onTap: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    ),
  );
}

void _openLobby(BuildContext context, RoomConn room, {GameInfo? game, LanHost? lan}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => LobbyScreen(room: room, preferGame: game, lanHost: lan)));
}

/// "مع أصدقائي": غرفة جديدة (إنترنت، وإذا ماكو فالشبكة المحلية)
Future<void> createFriendsRoom(BuildContext context, {GameInfo? game}) async {
  if (!await ensureProfile(context) || !context.mounted) return;
  String? code;
  String? server;
  LanHost? lan;
  String? onlineErr;
  await withBusy(context, 'جارٍ تجهيز الغرفة...', () async {
    if (onlineAvailable) {
      try {
        code = await RoomConn.createRoom();
        return;
      } catch (e) {
        onlineErr = e.toString().split('\n').first;
      }
    }
    // ماكو إنترنت: غرفة على نفس الشبكة (أندرويد)
    if (lanHostSupported) {
      try {
        final h = await LanHost.start();
        if (h.ips.isEmpty) {
          await h.stop();
          return;
        }
        lan = h;
        code = h.code;
        server = h.selfServer;
      } catch (_) {}
    }
  });
  if (!context.mounted) return;
  if (code == null) {
    showMessage(
      context,
      lanHostSupported
          ? 'تعذّر إنشاء الغرفة. اتصل بالإنترنت أو بشبكة Wi‑Fi ثم حاول مرة أخرى.'
          : 'تعذّر إنشاء الغرفة. تحقّق من اتصالك بالإنترنت ثم حاول مرة أخرى.',
      error: true,
    );
    return;
  }
  _openLobby(context, RoomConn.join(code!, Profile.I.name, server: server), game: game, lan: lan);
  // ما گدرنا نوصل السيرفر فسوّينا غرفة محلية: نبيّن السبب حتى نعرف شنو صار
  if (lan != null && onlineErr != null && context.mounted) {
    showMessage(context, 'تعذّر الوصول إلى سيرفر الإنترنت، فأُنشئت غرفة على شبكة Wi‑Fi نفسها.\n($onlineErr)');
  }
}

/// "مع لاعبين آخرين": لعب سريع بالإنترنت
Future<void> quickMatch(BuildContext context, GameInfo game) async {
  if (!await ensureProfile(context) || !context.mounted) return;
  if (!onlineAvailable || lanOrigin != null) {
    showMessage(context, 'اللعب مع لاعبين آخرين يحتاج إلى اتصال بالإنترنت.', error: true);
    return;
  }
  QuickResult? res;
  await withBusy(context, 'جارٍ البحث عن لاعبين...', () async {
    try {
      res = await RoomConn.quickRoom(game.id);
    } catch (_) {}
  });
  if (!context.mounted) return;
  final r = res;
  if (r == null) {
    showMessage(context, 'تعذّر الاتصال. تحقّق من اتصالك بالإنترنت ثم حاول مرة أخرى.', error: true);
    return;
  }
  // ممنوع من الإبلاغات
  if (r.ban != null) {
    await showNotice(context, icon: Icons.block_rounded, title: 'لا يمكنك اللعب مع لاعبين آخرين الآن', text: r.ban!.message);
    return;
  }
  // تنبيه أول مرة (قبل المنع)
  if (r.warn != null) {
    await showNotice(context, icon: Icons.warning_amber_rounded, title: 'تنبيه', text: r.warn!);
    if (!context.mounted) return;
  }
  _openLobby(context, RoomConn.join(r.code!, Profile.I.name), game: game);
}

/// يدخل غرفة بالرمز: يدوّر بالإنترنت أول، وبعدين بالشبكة المحلية
Future<void> joinByCode(BuildContext context, String raw) async {
  final code = raw.trim().toUpperCase();
  if (code.length != 4) {
    showMessage(context, 'الرمز مكوّن من 4 أحرف.', error: true);
    return;
  }
  String? server;
  var found = false;
  await withBusy(context, 'جارٍ البحث عن الغرفة...', () async {
    if (lanOrigin != null) {
      server = lanOrigin;
      found = true;
      return;
    }
    final online = await RoomConn.roomExists(code);
    if (online == true) {
      found = true;
      return;
    }
    if (lanHostSupported) {
      final rooms = await scanLan();
      for (final r in rooms) {
        if (r.code == code) {
          server = r.server;
          found = true;
          return;
        }
      }
    }
    // ما گدرنا نتحقق (السيرفر ما يرد): نجرّب ندخل على أي حال
    if (online == null && onlineAvailable && !lanHostSupported) found = true;
  });
  if (!context.mounted) return;
  if (!found) {
    showMessage(context, 'لم نجد غرفة بهذا الرمز. تأكّد من الرمز، أو أن تكونوا على شبكة Wi‑Fi نفسها.', error: true);
    return;
  }
  _openLobby(context, RoomConn.join(code, Profile.I.name, server: server));
}

/// رابط دعوة (/j/CODE أو ?room=CODE): يدخل الغرفة مباشرة بدون ما يكتب الرمز.
/// أول مرة يطلب الاسم والصورة بخطوة وحدة. [gone]: دالة الرابط بالويب لگت الغرفة منتهية.
Future<void> openInvite(BuildContext context, String raw, {bool gone = false}) async {
  final code = raw.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{4}$').hasMatch(code)) return;
  if (!await ensureProfile(context, invited: true) || !context.mounted) return;
  // ويب مفتوح من تلفون صاحب غرفة محلية
  if (lanOrigin != null) {
    _openLobby(context, RoomConn.join(code, Profile.I.name, server: lanOrigin));
    return;
  }
  bool? exists = gone ? false : null;
  if (!gone && onlineAvailable) {
    await withBusy(context, 'جارٍ الدخول إلى الغرفة...', () async {
      exists = await RoomConn.roomExists(code);
    });
  }
  if (!context.mounted) return;
  if (exists == false) {
    await showRoomGone(context);
    return;
  }
  // موجودة، أو ما گدرنا نتأكد: ندخل والغرفة تطلع الخطأ إذا ماكو
  _openLobby(context, RoomConn.join(code, Profile.I.name));
}

/// الغرفة منتهية: رسالة + زر يسوّي غرفة جديدة
Future<void> showRoomGone(BuildContext context) async {
  final make = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: Text('⌛', style: TextStyle(fontSize: 54))),
              const SizedBox(height: 6),
              Text('انتهت هاي الغرفة', textAlign: TextAlign.center, style: display(30, color: L.ink)),
              const SizedBox(height: 4),
              Text('اطلب من صديقك رابطًا جديدًا، أو أنشئ غرفتك وادعُه إليها.', textAlign: TextAlign.center, style: body(15, weight: FontWeight.w800, color: L.muted)),
              const SizedBox(height: 18),
              ChunkyButton(label: 'سوّي غرفة جديدة', icon: Icons.add_rounded, onTap: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    ),
  );
  if (make == true && context.mounted) await createFriendsRoom(context);
}

/// نافذة الانضمام: مربع واحد للرمز وزر واحد
Future<void> showJoinSheet(BuildContext context, {String? code}) async {
  if (!await ensureProfile(context) || !context.mounted) return;
  final c = TextEditingController(text: code ?? '');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الانضمام إلى غرفة', textAlign: TextAlign.center, style: display(30, color: L.ink)),
                const SizedBox(height: 6),
                Text('اكتب الرمز الذي أرسله إليك صديقك', textAlign: TextAlign.center, style: body(15, weight: FontWeight.w800, color: L.muted)),
                const SizedBox(height: 18),
                // أربع خانات (مثل النموذج): حقل كتابة مخفي فوقها ياخذ الحروف
                SizedBox(
                  height: 70,
                  child: Stack(children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: IgnorePointer(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: c,
                          builder: (context, v, _) => Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < 4; i++)
                                Container(
                                  width: 58,
                                  height: 66,
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: L.sky,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: i == v.text.length ? const Color(0xFF2E9BF0) : L.sky2, width: 2),
                                  ),
                                  child: Text(i < v.text.length ? v.text[i] : '', style: display(36, color: L.ink)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: c,
                          autofocus: code == null,
                          maxLength: 4,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')), UpperCaseFormatter()],
                          onSubmitted: (_) => Navigator.pop(ctx, true),
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text('أو امسح رمز QR من هاتف صاحب الغرفة بكاميرا هاتفك', textAlign: TextAlign.center, style: body(13, weight: FontWeight.w800, color: L.muted)),
                const SizedBox(height: 16),
                ChunkyButton(label: 'انضمام', icon: Icons.login_rounded, onTap: () => Navigator.pop(ctx, true)),
                if (lanHostSupported) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.wifi_find_rounded, color: L.muted),
                    label: Text('البحث عن غرف قريبة بدون رمز', style: body(14, weight: FontWeight.w800, color: L.muted)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (ok == true) {
    await joinByCode(context, c.text);
  } else if (ok == false) {
    await showNearbyRooms(context);
  }
}

/// غرف قريبة على نفس الشبكة (أندرويد)
Future<void> showNearbyRooms(BuildContext context) async {
  List<LanFound> rooms = const [];
  await withBusy(context, 'جارٍ البحث في شبكة Wi‑Fi...', () async {
    rooms = await scanLan();
  });
  if (!context.mounted) return;
  if (rooms.isEmpty) {
    showMessage(context, 'لا توجد غرف قريبة. تأكّد أنكم على شبكة Wi‑Fi نفسها.', error: true);
    return;
  }
  final pick = await showModalBottomSheet<LanFound>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('غرف قريبة', textAlign: TextAlign.center, style: display(28, color: L.ink)),
          const SizedBox(height: 12),
          for (final r in rooms)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChunkyButton(
                label: r.hostName.isEmpty ? 'غرفة ${r.code}' : 'غرفة ${r.hostName}',
                icon: Icons.wifi_tethering_rounded,
                filled: false,
                onTap: () => Navigator.pop(ctx, r),
              ),
            ),
        ],
      ),
    ),
  );
  if (pick != null && context.mounted) {
    _openLobby(context, RoomConn.join(pick.code, Profile.I.name, server: pick.server));
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) => n.copyWith(text: n.text.toUpperCase());
}
