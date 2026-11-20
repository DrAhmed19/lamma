// سيرفر غرف لمّة — السيرفر هو اللي يدير اللعبة ويحسم النتيجة.
//
// GET  /new          → { code }  يسوّي غرفة جديدة بكود من 4 حروف
// GET  /ws/<CODE>    → WebSocket للغرفة
//
// قواعد الألعاب مكتوبة بـ Dart (lib/logic/) ومبنية لـ JavaScript بـ logic.js،
// فالسيرفر والتطبيق يشغّلون نفس القواعد بالضبط.
//
// - كل لاعب ياخذ مقعد (0..3) ويتذكره بالـ token، فإذا انقطع ورجع يرجع لنفس مكانه
//   وياخذ الحالة الحالية فوراً.
// - إذا طلع أي واحد (حتى صاحب الغرفة) اللعبة تكمل للباقين.
//   بلعبة لاعبين: إذا ما رجع خلال دقيقة، الثاني يفوز.
// - صاحب الغرفة بس يختار اللعبة ويبدي. إذا طلع، اللي بعده ياخذ مكانه.
//
// رسائل العميل: join, cfg, start, in, again, lobby, quit, leave, ping
// رسائل السيرفر: you, room, state, err, pong

import "./logic.js";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // بدون I و O حتى ما تلتبس
const MAX_PLAYERS = 4;
const IDLE_MS = 2 * 60 * 60 * 1000; // الغرفة تنمسح بعد ساعتين بدون نشاط
// لاعب انقطع وما رجع خلال دقيقة = انسحب (يتغير بـ FORFEIT_MS للاختبار)
const FORFEIT_DEFAULT = 60 * 1000;
const SAVE_EVERY_MS = 2000;

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

export class Room {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.game = null; // اللعبة الشغالة (من logic.js)
    this.timer = null; // تكّات الألعاب السريعة
    this.lastSave = 0;
    this.forfeitMs = Number(env.FORFEIT_MS ?? FORFEIT_DEFAULT);
  }

  // ------------------------------------------------------------ تخزين

  async meta() {
    return (await this.ctx.storage.get("meta")) ?? null;
  }

  async saveMeta(meta) {
    meta.touched = Date.now();
    await this.ctx.storage.put("meta", meta);
    await this.scheduleAlarm(meta);
  }

  async scheduleAlarm(meta) {
    let at = Date.now() + IDLE_MS;
    for (const t of Object.values(meta.offlineSince ?? {})) at = Math.min(at, t + this.forfeitMs + 500);
    await this.ctx.storage.setAlarm(at);
  }

  /// يرجّع اللعبة من التخزين إذا السيرفر نام وصحى
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
      await this.saveMeta({
        code: url.searchParams.get("code"),
        host: -1,
        game: null,
        crazy: false,
        started: false,
        round: 0,
        seats: [],
        out: [], // مقاعد طلعت من الجولة الحالية
        offlineSince: {}, // مقعد → وقت الانقطاع
        players: {}, // مقعد → { name, token }
      });
      return new Response("ok");
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

  roomState(meta) {
    const on = this.online();
    const players = Object.entries(meta.players).map(([seat, p]) => ({
      seat: Number(seat),
      name: p.name,
      on: on.has(Number(seat)),
    }));
    players.sort((a, b) => a.seat - b.seat);
    return {
      t: "room",
      code: meta.code,
      host: meta.host,
      game: meta.game,
      crazy: meta.crazy,
      started: meta.started,
      round: meta.round,
      seats: meta.seats,
      out: meta.out,
      players,
    };
  }

  /// إذا صاحب الغرفة طلع، الأقدم بالمتصلين يصير هو صاحبها
  fixHost(meta) {
    const on = [...this.online()].sort((a, b) => a - b);
    if (!on.includes(meta.host)) meta.host = on.length ? on[0] : -1;
  }

  /// رقم اللاعب باللعبة (حسب ترتيب المشاركين)
  playerOf(meta, seat) {
    return meta.seats.indexOf(seat);
  }

  // ------------------------------------------------------------ اللعبة

  stateMsg(events) {
    return `{"t":"state","s":${this.game.state()},"ev":${events ?? this.game.events()}}`;
  }

  /// يدز الحالة الجديدة للكل ويحفظها
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
    // المؤقت ممكن يتأخر، فنحسب الوقت الحقيقي ونمشي تكّات ثابتة بقدره
    // (حتى ساعة اللعبة تمشي ويا الساعة الحقيقية بالضبط)
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
    }, 1000 / hz);
  }

  stopLoop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  /// التكّات تمشي بس إذا أكو واحد مشارك متصل
  async syncLoop(meta) {
    if (!meta.started || !(await this.ensureGame(meta))) return this.stopLoop();
    const on = this.online();
    const anyone = meta.seats.some((s) => on.has(s) && !meta.out.includes(s));
    if (anyone) this.startLoop();
    else this.stopLoop();
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
    } else {
      meta.offlineSince[seat] = Date.now();
      g.connection(p, false);
    }
    await this.flush();
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
      // كود غلط أو غرفة انتهت
      this.send(ws, { t: "err", m: "notfound" });
      try {
        ws.close(4004, "notfound");
      } catch (_) {}
      return;
    }
    const me = ws.deserializeAttachment() ?? { seat: -1 };

    if (msg.t === "join") return this.onJoin(ws, meta, msg);
    if (me.seat < 0) return; // لازم join أول شي

    const isHost = me.seat === meta.host;
    const p = this.playerOf(meta, me.seat);
    const playing = meta.started && p >= 0 && !meta.out.includes(me.seat);

    switch (msg.t) {
      case "cfg":
        if (!isHost || meta.started) return;
        meta.game = typeof msg.game === "string" ? msg.game.slice(0, 20) : null;
        meta.crazy = !!msg.crazy;
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        return;

      case "start": {
        if (!isHost || meta.started || !meta.game) return;
        if (!globalThis.lamma.supports(meta.game)) return this.send(ws, { t: "err", m: "unsupported" });
        const seats = [...this.online()].sort((a, b) => a - b);
        meta.started = true;
        meta.round += 1;
        meta.seats = seats;
        meta.out = [];
        meta.offlineSince = {};
        const seed = Math.floor(Math.random() * 2 ** 31);
        this.stopLoop();
        this.game = globalThis.lamma.create(meta.game, seats.length, meta.crazy, seed);
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        await this.flush();
        await this.syncLoop(meta);
        return;
      }

      case "in": {
        if (!playing || typeof msg.d !== "object" || msg.d === null) return;
        const g = await this.ensureGame(meta);
        if (!g) return;
        g.input(p, JSON.stringify(msg.d));
        // الألعاب بالدور تتحدث فوراً، السريعة تطلع بالتكّة الجاية
        if (g.tickHz() <= 0) await this.flush();
        return;
      }

      case "again": {
        if (!meta.started) return;
        const g = await this.ensureGame(meta);
        if (!g || !g.over()) return;
        g.again();
        await this.flush();
        return;
      }

      case "lobby":
        // صاحب الغرفة يرجّع الكل للغرفة (بس بعد ما تخلص المباراة)
        if (!isHost || !meta.started) return;
        if (this.game && !this.game.over()) return;
        await this.endMatch(meta);
        return;

      case "quit":
        // طلع من اللعبة (رجع لشاشة الغرفة): ينسحب، والباقين يكملون
        if (!playing) return;
        await this.playerGone(meta, me.seat, true);
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        await this.afterLeave(meta);
        return;

      case "leave":
        if (playing) await this.playerGone(meta, me.seat, true);
        delete meta.players[me.seat];
        ws.serializeAttachment({ seat: -1 });
        this.fixHost(meta);
        await this.saveMeta(meta);
        this.broadcast(this.roomState(meta));
        try {
          ws.close(1000, "bye");
        } catch (_) {}
        await this.afterLeave(meta);
        return;
    }
  }

  /// إذا ما بقى أحد يلعب، نرجع للغرفة
  async afterLeave(meta) {
    if (!meta.started) return;
    const on = this.online();
    const left = meta.seats.filter((s) => on.has(s) && !meta.out.includes(s));
    if (left.length === 0) await this.endMatch(meta);
    else await this.syncLoop(meta);
  }

  async endMatch(meta) {
    meta.started = false;
    meta.out = [];
    meta.offlineSince = {};
    this.stopLoop();
    this.game = null;
    await this.ctx.storage.delete("game");
    await this.saveMeta(meta);
    this.broadcast(this.roomState(meta));
  }

  async onJoin(ws, meta, msg) {
    const name = String(msg.name ?? "").trim().slice(0, 14) || "لاعب";
    const token = String(msg.token ?? "").slice(0, 40);
    let seat = -1;
    for (const [s, p] of Object.entries(meta.players)) {
      if (token && p.token === token) seat = Number(s);
    }
    if (seat >= 0) {
      // رجع: نسد أي اتصال قديم إله
      for (const other of this.sockets()) {
        if (other !== ws && other.deserializeAttachment().seat === seat) {
          other.serializeAttachment({ seat: -1 });
          try {
            other.close(4000, "replaced");
          } catch (_) {}
        }
      }
      meta.players[seat].name = name;
    } else {
      const taken = new Set(Object.keys(meta.players).map(Number));
      const on = this.online();
      for (let s = 0; s < MAX_PLAYERS && seat < 0; s++) if (!taken.has(s)) seat = s;
      // مقعد واحد طلع ومو راجع (بس إذا مو بنص مباراة)
      for (let s = 0; s < MAX_PLAYERS && seat < 0; s++) {
        if (!on.has(s) && !meta.seats.includes(s)) seat = s;
      }
      if (seat < 0) return this.send(ws, { t: "err", m: "full" });
      meta.players[seat] = { name, token };
    }
    ws.serializeAttachment({ seat });
    this.fixHost(meta);
    if (meta.host < 0) meta.host = seat;

    // رجع بنص مباراة: يكمل وياهم
    const p = this.playerOf(meta, seat);
    if (meta.started && p >= 0 && meta.offlineSince[seat] !== undefined) {
      delete meta.offlineSince[seat];
      const g = await this.ensureGame(meta);
      if (g) g.connection(p, true);
    }
    await this.saveMeta(meta);
    this.send(ws, { t: "you", seat });
    this.broadcast(this.roomState(meta));
    if (meta.started && (await this.ensureGame(meta))) this.send(ws, this.stateMsg("[]"));
    await this.syncLoop(meta);
  }

  async webSocketClose(ws) {
    const me = ws.deserializeAttachment() ?? { seat: -1 };
    ws.serializeAttachment({ seat: -1 });
    const meta = await this.meta();
    if (!meta || me.seat < 0) return;
    // نفس المقعد ممكن رجع باتصال ثاني
    if (!this.online().has(me.seat)) await this.playerGone(meta, me.seat, false);
    this.fixHost(meta);
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
    // اللي انقطع أكثر من دقيقة = انسحب، والباقين يكملون
    for (const [seat, since] of Object.entries(meta.offlineSince ?? {})) {
      if (now - since >= this.forfeitMs) await this.playerGone(meta, Number(seat), true);
    }
    if (now - meta.touched >= IDLE_MS && this.sockets().length === 0) {
      this.stopLoop();
      await this.ctx.storage.deleteAll();
      return;
    }
    await this.saveMeta(meta);
    if (meta.started) this.broadcast(this.roomState(meta));
  }
}
