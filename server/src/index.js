// سيرفر غرف لمّة — السيرفر هو اللي يدير اللعبة ويحسم النتيجة.
//
// GET  /new              → { code }  يسوّي غرفة جديدة بكود من 4 حروف
// GET  /quick?game=ID    → { code }  لعب سريع ويا ناس ثانين: يلگي غرفة عامة تنتظر، أو يسوّي وحدة
// GET  /ws/<CODE>        → WebSocket للغرفة
//
// قواعد الألعاب مكتوبة بـ Dart (lib/logic/) ومبنية لـ JavaScript بـ logic.js،
// فالسيرفر والتطبيق يشغّلون نفس القواعد بالضبط.
// نسخة Dart من هذا الملف بـ lib/net/lan_room.dart (للعب على نفس الشبكة). أي تغيير هنا ينعمل هناك.
//
// - كل لاعب ياخذ مقعد (0..3) ويتذكره بالـ token، فإذا انقطع ورجع يرجع لنفس مكانه.
// - إذا طلع أي واحد (حتى صاحب الغرفة) اللعبة تكمل للباقين.
//   بلعبة لاعبين: إذا طلع أو غاب 45 ثانية، الثاني يفوز وبعدها الكل يرجع للغرفة.
// - صاحب الغرفة يختار اللعبة ويبدي، ويگدر يطرد أو يسلّم الغرفة. إذا انقطع يبقى صاحبها 20 ثانية.
// - "مرة ثانية" يزيد رقم الجولة حتى اللي رجع للغرفة تنفتح عنده اللعبة.
// - بطولة: صاحب الغرفة يختار كم لعبة، والفائز بكل وحدة ياخذ 3 نقاط (التعادل نقطة للكل).
// - الغرف العامة (لعب سريع): ماكو صاحب غرفة يتحكم، واللعب يبدي تلقائياً.
//
// رسائل العميل: join, cfg, start, tour, in, again, lobby, quit, leave, kick, host, emo, ping
// رسائل السيرفر: you, room, state, notice, emo, err, pong

import "./logic.js";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // بدون I و O حتى ما تلتبس
const MAX_PLAYERS = 4;
const IDLE_MS = 2 * 60 * 60 * 1000; // الغرفة تنمسح بعد ساعتين بدون نشاط
const FORFEIT_DEFAULT = 45 * 1000; // بمباراة: اللي غاب 45 ثانية = انسحب
const HOST_GRACE_DEFAULT = 20 * 1000; // صاحب الغرفة يبقى صاحبها 20 ثانية إذا انقطع
const LOBBY_DROP_DEFAULT = 3 * 60 * 1000; // بالغرفة: اللي انقطع 3 دقايق ينشال
const PUBLIC_DROP_MS = 30 * 1000; // بالغرف العامة أسرع
const END_DELAY_DEFAULT = 4000; // بعد ما تخلص المباراة لأن طلع لاعب
const AUTO_START_MS = 12 * 1000; // الغرف العامة: تبدي بعد 12 ثانية من وصول لاعبين
const SAVE_EVERY_MS = 2000;
const EMOJIS = 12; // عدد التفاعلات (القائمة بالتطبيق)

/// أكثر عدد لاعبين لكل لعبة
const GAME_MAX = { xo: 2, connect4: 2, tug: 2, hockey: 2, pigeon: 4, reaction: 4, quiz: 4 };

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", ...cors },
  });
}

function randomCode() {
  const b = new Uint8Array(4);
  crypto.getRandomValues(b);
  return [...b].map((x) => ALPHABET[x % ALPHABET.length]).join("");
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return new Response(null, { headers: cors });

    if (url.pathname === "/new") {
      for (let i = 0; i < 8; i++) {
        const code = randomCode();
        const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
        const r = await stub.fetch(`https://room/init?code=${code}`);
        if (r.ok) return json({ code });
      }
      return json({ error: "busy" }, 503);
    }

    if (url.pathname === "/quick") {
      const game = url.searchParams.get("game") ?? "";
      if (!GAME_MAX[game]) return json({ error: "game" }, 400);
      const mm = env.MATCH.get(env.MATCH.idFromName("mm"));
      const r = await mm.fetch(`https://mm/find?game=${game}`);
      return json(await r.json(), r.status);
    }

    // هل أكو غرفة بهالكود؟ (حتى التطبيق يعرف يدوّر بالشبكة المحلية إذا ماكو)
    const info = url.pathname.match(/^\/info\/([A-Za-z]{4})$/);
    if (info) {
      const stub = env.ROOMS.get(env.ROOMS.idFromName(info[1].toUpperCase()));
      const r = await stub.fetch("https://room/info");
      return json(await r.json());
    }

    const m = url.pathname.match(/^\/ws\/([A-Za-z]{4})$/);
    if (m) {
      if (req.headers.get("Upgrade") !== "websocket") return json({ error: "need websocket" }, 426);
      const code = m[1].toUpperCase();
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      return stub.fetch(req);
    }

    return json({ ok: true, name: "lamma-rooms" });
  },
};

// ================================================================ اللعب السريع

/// قائمة الغرف العامة اللي تنتظر لاعبين (وحدة لكل السيرفر)
export class Match {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(req) {
    const url = new URL(req.url);
    const now = Date.now();
    const list = (await this.ctx.storage.get("open")) ?? {};
    for (const [c, r] of Object.entries(list)) if (now - r.at > 120000) delete list[c];

    if (url.pathname === "/update") {
      const code = url.searchParams.get("code");
      if (url.searchParams.get("open") === "1") {
        list[code] = {
          game: url.searchParams.get("game"),
          n: Number(url.searchParams.get("n")),
          max: Number(url.searchParams.get("max")),
          at: now,
        };
      } else {
        delete list[code];
      }
      await this.ctx.storage.put("open", list);
      return new Response("ok");
    }

    if (url.pathname === "/find") {
      const game = url.searchParams.get("game");
      const max = GAME_MAX[game];
      if (!max) return json({ error: "game" }, 400);
      // الغرفة اللي بيها أكثر ناس أول (حتى تبدي أسرع)
      const cands = Object.entries(list)
        .filter(([, r]) => r.game === game && r.n < r.max)
        .sort((a, b) => b[1].n - a[1].n);
      if (cands.length) {
        const [code, r] = cands[0];
        r.n += 1; // حجز، حتى اللي يجون سوه يتوزعون صح
        r.at = now;
        await this.ctx.storage.put("open", list);
        return json({ code });
      }
      for (let i = 0; i < 8; i++) {
        const code = randomCode();
        const stub = this.env.ROOMS.get(this.env.ROOMS.idFromName(code));
        const r = await stub.fetch(`https://room/init?code=${code}&public=1&game=${game}`);
        if (r.ok) {
          list[code] = { game, n: 1, max, at: now };
          await this.ctx.storage.put("open", list);
          return json({ code });
        }
      }
      return json({ error: "busy" }, 503);
    }
    return new Response("?", { status: 404 });
  }
}

// ================================================================ الغرفة

export class Room {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.game = null; // اللعبة الشغالة (من logic.js)
    this.timer = null; // تكّات الألعاب السريعة
    this.lastSave = 0;
    this.overSeen = false;
    this.lastEmo = {};
    // الأوقات تتغير بالمتغيرات للاختبار
    this.forfeitMs = Number(env.FORFEIT_MS ?? FORFEIT_DEFAULT);
    this.hostGraceMs = Number(env.HOST_GRACE_MS ?? HOST_GRACE_DEFAULT);
    this.lobbyDropMs = Number(env.LOBBY_DROP_MS ?? LOBBY_DROP_DEFAULT);
    this.endDelayMs = Number(env.END_DELAY_MS ?? END_DELAY_DEFAULT);
    this.autoStartMs = Number(env.AUTO_START_MS ?? AUTO_START_MS);
  }

  // ------------------------------------------------------------ تخزين

  async meta() {
    const m = (await this.ctx.storage.get("meta")) ?? null;
    if (m) {
      m.gone ??= {};
      m.banned ??= [];
      m.offlineSince ??= {};
      m.out ??= [];
      m.seats ??= [];
      m.tour ??= null;
      m.autoAt ??= 0;
    }
    return m;
  }

  async saveMeta(meta, { touch = true } = {}) {
    if (touch) meta.touched = Date.now();
    await this.ctx.storage.put("meta", meta);
    await this.scheduleAlarm(meta);
  }

  dropMs(meta) {
    return meta.public ? PUBLIC_DROP_MS : this.lobbyDropMs;
  }

  /// أقرب شي لازم السيرفر يصحى بيه
  async scheduleAlarm(meta) {
    let at = (meta.touched ?? Date.now()) + IDLE_MS;
    for (const t of Object.values(meta.offlineSince)) at = Math.min(at, t + this.forfeitMs + 300);
    const hg = meta.gone[meta.host];
    if (hg !== undefined) at = Math.min(at, hg + this.hostGraceMs + 300);
    if (!meta.started) for (const t of Object.values(meta.gone)) at = Math.min(at, t + this.dropMs(meta) + 300);
    if (meta.endAt) at = Math.min(at, meta.endAt);
    if (meta.autoAt) at = Math.min(at, meta.autoAt);
    await this.ctx.storage.setAlarm(Math.max(at, Date.now() + 50));
  }

  async ensureGame(meta) {
    if (this.game || !meta.started) return this.game;
    const s = await this.ctx.storage.get("game");
    if (s) this.game = globalThis.lamma.restore(s);
    return this.game;
  }

  async saveGame() {
    if (!this.game) return;
    this.lastSave = Date.now();
    await this.ctx.storage.put("game", this.game.state());
  }

  // ------------------------------------------------------------ اتصالات

  async fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/init") {
      const old = await this.meta();
      if (old && Date.now() - old.touched < IDLE_MS) return new Response("taken", { status: 409 });
      await this.ctx.storage.deleteAll();
      this.stopLoop();
      this.game = null;
      const pub = url.searchParams.get("public") === "1";
      await this.saveMeta({
        code: url.searchParams.get("code"),
        host: -1,
        game: pub ? url.searchParams.get("game") : null,
        crazy: false,
        public: pub,
        started: false,
        round: 0,
        seats: [],
        out: [], // مقاعد طلعت من المباراة الحالية
        offlineSince: {}, // مشارك بمباراة انقطع: مقعد → وقت
        gone: {}, // أي لاعب انقطع: مقعد → وقت
        banned: [], // tokens مطرودين
        endAt: 0, // رجوع الكل للغرفة بعد ما تخلص المباراة لأن طلع لاعب
        autoAt: 0, // الغرف العامة: وقت البداية التلقائية
        tour: null, // البطولة
        players: {}, // مقعد → { name, token, avatar }
      });
      return new Response("ok");
    }

    if (url.pathname === "/info") {
      const meta = await this.meta();
      const alive = !!meta && Date.now() - meta.touched < IDLE_MS;
      return new Response(
        JSON.stringify(alive ? { exists: true, players: Object.keys(meta.players).length, game: meta.game } : { exists: false }),
        { headers: { "content-type": "application/json" } },
      );
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ seat: -1 });
    return new Response(null, { status: 101, webSocket: client });
  }

  sockets() {
    return this.ctx.getWebSockets().filter((ws) => (ws.deserializeAttachment()?.seat ?? -1) >= 0);
  }

  online() {
    return new Set(this.sockets().map((ws) => ws.deserializeAttachment().seat));
  }

  send(ws, data) {
    try {
      ws.send(typeof data === "string" ? data : JSON.stringify(data));
    } catch (_) {}
  }

  broadcast(data) {
    const s = typeof data === "string" ? data : JSON.stringify(data);
    for (const ws of this.sockets()) this.send(ws, s);
  }

  notice(m, meta, seat) {
    this.broadcast({ t: "notice", m, seat, name: meta.players[seat]?.name ?? "لاعب" });
  }

  roomState(meta) {
    const on = this.online();
    const players = Object.entries(meta.players).map(([seat, p]) => ({
      seat: Number(seat),
      name: p.name,
      avatar: p.avatar ?? "",
      on: on.has(Number(seat)),
    }));
    players.sort((a, b) => a.seat - b.seat);
    return {
      t: "room",
      code: meta.code,
      host: meta.host,
      game: meta.game,
      crazy: meta.crazy,
      public: !!meta.public,
      started: meta.started,
      round: meta.round,
      seats: meta.seats,
      out: meta.out,
      ending: !!meta.endAt,
      autoIn: meta.autoAt ? Math.max(0, meta.autoAt - Date.now()) : 0,
      tour: meta.tour,
      players,
    };
  }

  fixHost(meta, { force = false } = {}) {
    const now = Date.now();
    const on = this.online();
    const exists = meta.players[meta.host] !== undefined;
    const away = meta.gone[meta.host];
    const keep = exists && !force && (on.has(meta.host) || (away !== undefined && now - away < this.hostGraceMs));
    if (keep) return false;
    const candidates = [...on].filter((s) => meta.players[s] && s !== meta.host).sort((a, b) => a - b);
    const next = candidates.length ? candidates[0] : exists && on.has(meta.host) ? meta.host : -1;
    if (next === meta.host) return false;
    if (next < 0 && exists) return false;
    meta.host = next;
    if (next >= 0 && !meta.public) this.notice("host", meta, next);
    return true;
  }

  playerOf(meta, seat) {
    return meta.seats.indexOf(seat);
  }

  /// الغرف العامة: نبلّغ قائمة اللعب السريع شكد بيها ناس
  async report(meta) {
    if (!meta.public || !this.env.MATCH) return;
    const n = Object.keys(meta.players).length;
    const max = GAME_MAX[meta.game] ?? 2;
    const open = !meta.started && n < max ? "1" : "0";
    try {
      const mm = this.env.MATCH.get(this.env.MATCH.idFromName("mm"));
      await mm.fetch(`https://mm/update?code=${meta.code}&game=${meta.game}&n=${n}&max=${max}&open=${open}`);
    } catch (_) {}
  }

  /// الغرف العامة: إذا اكتملت تبدي فوراً، وإذا بيها اثنين أو أكثر تبدي بعد شوية
  autoStart(meta) {
    if (!meta.public || meta.started) {
      meta.autoAt = 0;
      return false;
    }
    const n = [...this.online()].filter((s) => meta.players[s]).length;
    const max = GAME_MAX[meta.game] ?? 2;
    if (n >= max) {
      meta.autoAt = Date.now();
      return true;
    }
    if (n >= 2) {
      if (!meta.autoAt) meta.autoAt = Date.now() + this.autoStartMs;
    } else {
      meta.autoAt = 0;
    }
    return meta.autoAt && Date.now() >= meta.autoAt;
  }

  // ------------------------------------------------------------ اللعبة

  stateMsg(events) {
    return `{"t":"state","s":${this.game.state()},"ev":${events ?? this.game.events()}}`;
  }

  async flush() {
    if (!this.game) return;
    this.broadcast(this.stateMsg());
    await this.saveGame();
  }

  startLoop() {
    if (this.timer || !this.game) return;
    const hz = this.game.tickHz();
    if (hz <= 0) return;
    const dt = 1 / hz;
    let last = Date.now();
    let acc = 0;
    this.timer = setInterval(() => {
      if (!this.game) return this.stopLoop();
      const now = Date.now();
      acc += Math.min(0.25, (now - last) / 1000);
      last = now;
      let steps = 0;
      while (acc >= dt && steps < 8) {
        this.game.step(dt);
        acc -= dt;
        steps++;
      }
      if (steps > 0) this.broadcast(this.stateMsg());
      if (now - this.lastSave > SAVE_EVERY_MS) this.saveGame();
      this.watchOver();
    }, 1000 / hz);
  }

  stopLoop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  async syncLoop(meta) {
    if (!meta.started || !(await this.ensureGame(meta))) return this.stopLoop();
    const on = this.online();
    const anyone = meta.seats.some((s) => on.has(s) && !meta.out.includes(s));
    if (anyone && !meta.endAt) this.startLoop();
    else this.stopLoop();
  }

  /// لمّن تخلص اللعبة (بالبطولة نحسب النقاط)
  watchOver() {
    const over = !!this.game && this.game.over();
    if (over && !this.overSeen) {
      this.overSeen = true;
      this.ctx.waitUntil(
        (async () => {
          const meta = await this.meta();
          if (meta && this.scoreTour(meta)) {
            await this.saveMeta(meta);
            this.broadcast(this.roomState(meta));
          }
        })(),
      );
    } else if (!over) {
      this.overSeen = false;
    }
  }

  /// نقاط البطولة لهالجولة (مرة وحدة)
  scoreTour(meta) {
    const t = meta.tour;
    if (!t || t.done || !this.game || !this.game.over() || t.scored === meta.round) return false;
    const w = this.game.winner();
    if (w >= 0 && meta.seats[w] !== undefined) {
      const s = meta.seats[w];
      t.pts[s] = (t.pts[s] ?? 0) + 3;
    } else {
      for (const s of meta.seats) if (!meta.out.includes(s)) t.pts[s] = (t.pts[s] ?? 0) + 1;
    }
    t.scored = meta.round;
    if (t.idx >= t.games.length - 1) t.done = true;
    return true;
  }

  /// يبدي مباراة جديدة بهالمقاعد
  newMatch(meta, seats) {
    meta.started = true;
    meta.round += 1;
    meta.seats = seats;
    meta.out = [];
    meta.offlineSince = {};
    meta.endAt = 0;
    meta.autoAt = 0;
    const seed = Math.floor(Math.random() * 2 ** 31);
    this.stopLoop();
    this.overSeen = false;
    this.game = globalThis.lamma.create(meta.game, seats.length, meta.crazy, seed);
  }

  async afterChange(meta) {
    await this.saveMeta(meta);
    this.broadcast(this.roomState(meta));
    await this.flush();
    await this.syncLoop(meta);
    await this.report(meta);
  }

  async playerGone(meta, seat, now) {
    const p = this.playerOf(meta, seat);
    if (!meta.started || p < 0 || meta.out.includes(seat)) return;
    const g = await this.ensureGame(meta);
    if (!g) return;
    if (now) {
      meta.out.push(seat);
      delete meta.offlineSince[seat];
      g.forfeit(p);
      this.scoreTour(meta);
    } else {
      meta.offlineSince[seat] = Date.now();
      g.connection(p, false);
    }
    await this.flush();
  }

  checkMatch(meta) {
    if (!meta.started || meta.endAt) return;
    const left = meta.seats.filter((s) => !meta.out.includes(s) && meta.players[s]);
    if (left.length < 2) {
      meta.endAt = Date.now() + this.endDelayMs;
      this.stopLoop();
    }
  }

  async endMatch(meta) {
    meta.started = false;
    meta.out = [];
    meta.offlineSince = {};
    meta.endAt = 0;
    this.stopLoop();
    this.game = null;
    await this.ctx.storage.delete("game");
    this.fixHost(meta);
    this.autoStart(meta);
    await this.saveMeta(meta);
    this.broadcast(this.roomState(meta));
    await this.report(meta);
  }

  async removePlayer(meta, seat, { kicked = false } = {}) {
    if (meta.players[seat] === undefined) return;
    if (meta.started && this.playerOf(meta, seat) >= 0) await this.playerGone(meta, seat, true);
    this.notice(kicked ? "kicked" : "left", meta, seat);
    if (kicked) {
      meta.banned.push(meta.players[seat].token);
      for (const ws of this.sockets()) {
        if (ws.deserializeAttachment().seat === seat) {
          this.send(ws, { t: "err", m: "kicked" });
          ws.serializeAttachment({ seat: -1 });
          try {
            ws.close(4003, "kicked");
          } catch (_) {}
        }
      }
    }
    delete meta.players[seat];
    delete meta.gone[seat];
    delete meta.offlineSince[seat];
    if (meta.host === seat) this.fixHost(meta, { force: true });
    this.checkMatch(meta);
  }

  // ------------------------------------------------------------ الرسائل

  async webSocketMessage(ws, raw) {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (_) {
      return;
    }
    if (msg.t === "ping") return this.send(ws, { t: "pong" });

    const meta = await this.meta();
    if (!meta) {
      this.send(ws, { t: "err", m: "notfound" });
      try {
        ws.close(4004, "notfound");
      } catch (_) {}
      return;
    }
    const me = ws.deserializeAttachment() ?? { seat: -1 };

    if (msg.t === "join") return this.onJoin(ws, meta, msg);
    if (me.seat < 0 || meta.players[me.seat] === undefined) return;

    const isHost = me.seat === meta.host && !meta.public;
    const p = this.playerOf(meta, me.seat);
    const playing = meta.started && p >= 0 && !meta.out.includes(me.seat);

    switch (msg.t) {
      case "cfg":
        if (!isHost || meta.started) return;
        meta.game = typeof msg.game === "string" ? msg.game.slice(0, 20) : null;
        meta.crazy = !!msg.crazy;
        meta.tour = null;
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        return;

      case "start": {
        if (!isHost || meta.started || !meta.game) return;
        if (!globalThis.lamma.supports(meta.game)) return this.send(ws, { t: "err", m: "unsupported" });
        const seats = [...this.online()].filter((s) => meta.players[s]).sort((a, b) => a - b);
        if (seats.length < 2) return this.send(ws, { t: "err", m: "few" });
        meta.tour = null;
        this.newMatch(meta, seats);
        await this.afterChange(meta);
        return;
      }

      case "tour": {
        // بطولة: قائمة ألعاب تنلعب ورا بعض
        if (!isHost || meta.started || !Array.isArray(msg.games)) return;
        const seats = [...this.online()].filter((s) => meta.players[s]).sort((a, b) => a - b);
        if (seats.length < 2) return this.send(ws, { t: "err", m: "few" });
        const games = msg.games
          .filter((g) => typeof g === "string" && GAME_MAX[g] >= seats.length && globalThis.lamma.supports(g))
          .slice(0, 6);
        if (games.length < 2) return this.send(ws, { t: "err", m: "tour" });
        meta.tour = { games, idx: 0, pts: {}, scored: -1, done: false };
        meta.game = games[0];
        meta.crazy = false;
        this.newMatch(meta, seats);
        await this.afterChange(meta);
        return;
      }

      case "in": {
        if (!playing || meta.endAt || typeof msg.d !== "object" || msg.d === null) return;
        const g = await this.ensureGame(meta);
        if (!g) return;
        g.input(p, JSON.stringify(msg.d));
        if (g.tickHz() <= 0) {
          await this.flush();
          this.watchOver();
        }
        return;
      }

      case "again": {
        if (!meta.started || meta.endAt || !playing) return;
        const g = await this.ensureGame(meta);
        if (!g || !g.over()) return;
        this.scoreTour(meta);
        const t = meta.tour;
        // بطولة خلصت: الكل يرجع للغرفة ويشوفون الترتيب
        if (t && t.done) {
          await this.endMatch(meta);
          return;
        }
        const on = this.online();
        const keep = meta.seats.filter((s) => meta.players[s] && (!meta.out.includes(s) || on.has(s)));
        const changed = keep.length !== meta.seats.length || meta.out.some((s) => keep.includes(s));
        if (t) {
          // اللعبة الجاية بالبطولة
          t.idx += 1;
          meta.game = t.games[t.idx];
          this.newMatch(meta, keep.length >= 2 ? keep : meta.seats);
        } else if (changed && keep.length >= 2) {
          this.newMatch(meta, keep);
        } else {
          g.again();
          meta.round += 1;
          this.overSeen = false;
        }
        await this.afterChange(meta);
        return;
      }

      case "lobby":
        if (!isHost || !meta.started) return;
        if (meta.tour && !meta.tour.done) meta.tour = null;
        await this.endMatch(meta);
        return;

      case "kick": {
        const seat = Number(msg.seat);
        if (!isHost || seat === me.seat || meta.players[seat] === undefined) return;
        await this.removePlayer(meta, seat, { kicked: true });
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        await this.syncLoop(meta);
        await this.report(meta);
        return;
      }

      case "host": {
        const seat = Number(msg.seat);
        if (!isHost || seat === me.seat || !this.online().has(seat) || meta.players[seat] === undefined) return;
        meta.host = seat;
        this.notice("host", meta, seat);
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        return;
      }

      case "emo": {
        // تفاعل سريع (رقم من قائمة ثابتة، مو نص حر)
        const i = Number(msg.i);
        if (!Number.isInteger(i) || i < 0 || i >= EMOJIS) return;
        const now = Date.now();
        if (now - (this.lastEmo[me.seat] ?? 0) < 600) return;
        this.lastEmo[me.seat] = now;
        this.broadcast({ t: "emo", seat: me.seat, i });
        return;
      }

      case "quit":
        if (!playing) return;
        await this.playerGone(meta, me.seat, true);
        this.notice("quit", meta, me.seat);
        this.checkMatch(meta);
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        await this.syncLoop(meta);
        return;

      case "leave":
        await this.removePlayer(meta, me.seat);
        ws.serializeAttachment({ seat: -1 });
        this.autoStart(meta);
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        try {
          ws.close(1000, "bye");
        } catch (_) {}
        await this.syncLoop(meta);
        await this.report(meta);
        return;
    }
  }

  async onJoin(ws, meta, msg) {
    const name = String(msg.name ?? "").trim().slice(0, 14) || "لاعب";
    const avatar = String(msg.avatar ?? "").slice(0, 8);
    const token = String(msg.token ?? "").slice(0, 40);
    if (token && meta.banned.includes(token)) return this.send(ws, { t: "err", m: "kicked" });
    let seat = -1;
    for (const [s, p] of Object.entries(meta.players)) {
      if (token && p.token === token) seat = Number(s);
    }
    if (seat >= 0) {
      for (const other of this.sockets()) {
        if (other !== ws && other.deserializeAttachment().seat === seat) {
          other.serializeAttachment({ seat: -1 });
          try {
            other.close(4000, "replaced");
          } catch (_) {}
        }
      }
      meta.players[seat].name = name;
      meta.players[seat].avatar = avatar;
    } else {
      const taken = new Set(Object.keys(meta.players).map(Number));
      const max = meta.public ? GAME_MAX[meta.game] ?? MAX_PLAYERS : MAX_PLAYERS;
      if (taken.size >= max) return this.send(ws, { t: "err", m: "full" });
      for (let s = 0; s < MAX_PLAYERS && seat < 0; s++) if (!taken.has(s)) seat = s;
      if (seat < 0) return this.send(ws, { t: "err", m: "full" });
      meta.players[seat] = { name, token, avatar };
      if (meta.host >= 0) this.notice("joined", meta, seat);
    }
    delete meta.gone[seat];
    ws.serializeAttachment({ seat });
    if (meta.host < 0 || meta.players[meta.host] === undefined) meta.host = seat;
    this.fixHost(meta);

    const p = this.playerOf(meta, seat);
    if (meta.started && p >= 0 && meta.offlineSince[seat] !== undefined) {
      delete meta.offlineSince[seat];
      const g = await this.ensureGame(meta);
      if (g) g.connection(p, true);
    }
    const go = this.autoStart(meta);
    this.send(ws, { t: "you", seat });
    if (go) {
      const seats = [...this.online()].filter((s) => meta.players[s]).sort((a, b) => a - b);
      this.newMatch(meta, seats);
      await this.afterChange(meta);
      return;
    }
    await this.saveMeta(meta);
    this.broadcast(this.roomState(meta));
    if (meta.started && (await this.ensureGame(meta))) this.send(ws, this.stateMsg("[]"));
    await this.syncLoop(meta);
    await this.report(meta);
  }

  async webSocketClose(ws) {
    const me = ws.deserializeAttachment() ?? { seat: -1 };
    ws.serializeAttachment({ seat: -1 });
    const meta = await this.meta();
    if (!meta || me.seat < 0 || meta.players[me.seat] === undefined) return;
    if (!this.online().has(me.seat)) {
      meta.gone[me.seat] = Date.now();
      await this.playerGone(meta, me.seat, false);
    }
    this.autoStart(meta);
    await this.saveMeta(meta);
    this.broadcast(this.roomState(meta));
    await this.syncLoop(meta);
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }

  async alarm() {
    const meta = await this.meta();
    if (!meta) return;
    const now = Date.now();
    for (const [seat, since] of Object.entries(meta.offlineSince)) {
      if (now - since >= this.forfeitMs) {
        await this.playerGone(meta, Number(seat), true);
        this.checkMatch(meta);
      }
    }
    if (meta.endAt && now >= meta.endAt) {
      await this.endMatch(meta);
    }
    this.fixHost(meta);
    if (!meta.started) {
      for (const [seat, since] of Object.entries(meta.gone)) {
        if (now - since >= this.dropMs(meta) && !this.online().has(Number(seat))) {
          delete meta.players[seat];
          delete meta.gone[seat];
        }
      }
      if (meta.players[meta.host] === undefined) this.fixHost(meta, { force: true });
      // الغرف العامة: وقت البداية التلقائية
      if (this.autoStart(meta)) {
        const seats = [...this.online()].filter((s) => meta.players[s]).sort((a, b) => a - b);
        if (seats.length >= 2) {
          this.newMatch(meta, seats);
          await this.afterChange(meta);
          return;
        }
      }
      await this.report(meta);
    }
    if (now - meta.touched >= IDLE_MS && this.sockets().length === 0) {
      this.stopLoop();
      await this.ctx.storage.deleteAll();
      if (meta.public) {
        meta.started = true; // تنشال من قائمة اللعب السريع
        await this.report(meta);
      }
      return;
    }
    await this.saveMeta(meta, { touch: false });
    this.broadcast(this.roomState(meta));
    await this.syncLoop(meta);
  }
}
