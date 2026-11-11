// WebSocket hub (contracts §7): hello/welcome per role, typed routing, presence.
import { makeMsg, newId, parseMsg, ROLE_CHANNELS, WS_CLOSE_UNAUTHORIZED } from "@bebbikart/shared";

export function createHub({ settings, log = console.log }) {
  /** @type {ReturnType<import("./game.js").createGame>} */
  let game;
  const phones = new Map(); // deviceId -> Set<ws>
  const admins = new Set();
  let gameWs = null;
  let gameTrack = null; // the course the connected game has loaded (its hello), null = follows config
  const renders = new Map();

  function failRenders(message) {
    for (const pending of renders.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error(message));
    }
    renders.clear();
  }

  function send(ws, channel, type, payload) {
    let msg;
    try {
      msg = makeMsg(channel, type, payload);
    } catch (err) {
      log(`[ws] BUG: invalid ${type} on ${channel}: ${err.message}`);
      return;
    }
    ws.send(JSON.stringify(msg));
  }
  const sendError = (ws, channel, code, message, refId) =>
    send(ws, channel, "error", { code, message, ...(refId ? { refId } : {}) });

  const hub = {
    attach(g) {
      game = g;
    },
    gameOnline: () => gameWs !== null,
    gameTrack: () => gameTrack,
    deviceOnline: (deviceId) => (phones.get(deviceId)?.size ?? 0) > 0,
    toPhone(playerId, type, payload) {
      const deviceId = game?.players.get(playerId)?.deviceId;
      for (const ws of phones.get(deviceId) ?? []) send(ws, "serverToPhone", type, payload);
    },
    toPhones(type, payload) {
      for (const set of phones.values())
        for (const ws of set) send(ws, "serverToPhone", type, payload);
    },
    toAdmins(type, payload) {
      for (const ws of admins) send(ws, "serverToAdmin", type, payload);
    },
    toGame(type, payload) {
      if (gameWs) send(gameWs, "serverToGame", type, payload);
    },
    render(spec) {
      if (!gameWs)
        return Promise.reject(new Error("The game must be connected to render racer reviews"));
      const requestId = newId("message");
      const msg = makeMsg("serverToGame", "render.request", { requestId, spec });
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          renders.delete(requestId);
          reject(new Error("The game did not render the racer review within 60 seconds"));
        }, 60_000);
        renders.set(requestId, { resolve, reject, timer });
        gameWs.send(JSON.stringify(msg));
      });
    },

    /** Bun.serve `websocket` handlers. ws.data = { deviceId?, role? } set at upgrade. */
    websocket: {
      idleTimeout: 30, // Bun pings idle sockets and closes dead ones (15 s heartbeat-ish)
      sendPings: true,
      message(ws, raw) {
        const role = ws.data.role;
        if (!role) return hello(ws, raw);
        const channel = ROLE_CHANNELS[role].send;
        const parsed = parseMsg(channel, String(raw));
        const out = ROLE_CHANNELS[role].receive;
        if (!parsed.ok) {
          sendError(ws, out, "bad_message", parsed.error.message, parsed.error.refId);
          return;
        }
        const { type, payload, id } = parsed.msg;
        if (type === "hello") return;
        if (role === "game") {
          if (ws !== gameWs) return;
          if (type === "game.rendered") {
            const pending = renders.get(payload.requestId);
            if (!pending) return;
            renders.delete(payload.requestId);
            clearTimeout(pending.timer);
            if (payload.ok) pending.resolve({ front: payload.front, side: payload.side });
            else pending.reject(new Error(payload.error));
            return;
          }
          if (type.startsWith("game.config.") || type.startsWith("game.session.")) {
            try {
              game.managerCommand(type, payload);
            } catch (err) {
              log(`[ws] game ${type} refused: ${err.code ?? "bad_request"}: ${err.message}`);
              sendError(ws, out, err.code ?? "bad_request", err.message, id);
            }
            return;
          }
          game.onGameMessage(type, payload);
        } else if (role === "phone") {
          const p = game.playerForDevice(ws.data.deviceId);
          if (!p) return sendError(ws, out, "not_found", "Create your racer first", id);
          if (type === "phone.go") {
            try {
              game.launch(p.id);
            } catch (err) {
              sendError(ws, out, err.code ?? "bad_request", err.message, id);
            }
          } else if (type === "phone.steer") {
            game.steer(p.id, payload.runId, payload.x);
          } else if (type === "phone.queue.leave") {
            game.leaveLine(p.id);
          }
        }
      },
      close(ws) {
        const { role, deviceId } = ws.data;
        if (role === "phone") {
          const set = phones.get(deviceId);
          set?.delete(ws);
          if (set && set.size === 0) {
            phones.delete(deviceId);
            game.setDeviceOnline(deviceId, false);
          }
        } else if (role === "admin") {
          admins.delete(ws);
        } else if (role === "game" && ws === gameWs) {
          gameWs = null;
          failRenders("The game disconnected while rendering racer reviews");
          log("[ws] game disconnected");
          game.abortAllRuns("game_disconnected");
        }
      },
    },
  };

  function hello(ws, raw) {
    const parsed = parseMsg("phoneToServer", String(raw));
    if (!parsed.ok || parsed.msg.type !== "hello") {
      ws.close(WS_CLOSE_UNAUTHORIZED, "first message must be hello");
      return;
    }
    const h = parsed.msg.payload;
    if (h.role === "phone") {
      ws.data.role = "phone";
      const deviceId = ws.data.deviceId ?? "";
      if (!phones.has(deviceId)) phones.set(deviceId, new Set());
      phones.get(deviceId).add(ws);
      if (deviceId) game.setDeviceOnline(deviceId, true);
      const me = game.playerForDevice(deviceId);
      send(ws, "serverToPhone", "welcome", {
        session: game.session,
        config: game.config,
        ...(me ? { me: game.playerView(me.id) } : {}),
        weather: game.weather,
      });
      send(ws, "serverToPhone", "leaderboard.updated", game.leaderboard());
      send(ws, "serverToPhone", "paddock.updated", game.paddock());
      send(ws, "serverToPhone", "queue.updated", game.queueState());
    } else if (h.role === "game") {
      if (h.gameKey !== settings.gameKey) {
        ws.close(WS_CLOSE_UNAUTHORIZED, "bad game key");
        return;
      }
      ws.data.role = "game";
      if (gameWs) {
        log("[ws] a new game connected; replacing the old one");
        const old = gameWs;
        gameWs = null;
        failRenders("The game was replaced while rendering racer reviews");
        old.close(4000, "replaced by another game");
        game.abortAllRuns("game_replaced");
      }
      gameWs = ws;
      gameTrack = h.track ?? null;
      log(`[ws] game connected${gameTrack ? ` with the ${gameTrack} track loaded` : ""}`);
      send(ws, "serverToGame", "welcome", {
        session: game.session,
        config: game.config,
        roster: game.roster(),
        activeRuns: game.activeRunStarts(),
      });
      send(ws, "serverToGame", "queue.updated", game.queueState());
      game.gameChanged();
    } else if (h.role === "admin") {
      if (h.pin !== settings.adminPin) {
        ws.close(WS_CLOSE_UNAUTHORIZED, "bad pin");
        return;
      }
      ws.data.role = "admin";
      admins.add(ws);
      send(ws, "serverToAdmin", "welcome", {
        session: game.session,
        config: game.config,
        players: game.allPlayerViews(),
        weather: game.weather,
      });
      send(ws, "serverToAdmin", "queue.updated", game.queueState());
    }
  }

  return hub;
}
