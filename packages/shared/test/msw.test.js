import { afterAll, beforeAll, expect, test } from "bun:test";
import { setupServer } from "msw/node";
import { DEFAULT_BUILD, PlayerViewSchema, QueueStateSchema } from "../src/index.js";
import { mockHandlers } from "../testing/msw-handlers.js";

const server = setupServer(...mockHandlers({ delayMs: 0, baseUrl: "http://localhost" }));
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterAll(() => server.close());

const base = "http://localhost";
const api = (path, init) => fetch(base + path, init);
const json = (method, body, headers = {}) => ({
  method,
  headers: { "content-type": "application/json", ...headers },
  body: JSON.stringify(body),
});

test("state, build and launch", async () => {
  const state = await (await api("/api/state")).json();
  expect(PlayerViewSchema.safeParse(state.me).success).toBe(true);

  const bad = await api(
    "/api/players/me/build",
    json("PUT", { ...DEFAULT_BUILD, stars: { ...DEFAULT_BUILD.stars, speed: 9 } }),
  );
  expect(bad.status).toBe(400);
  expect((await bad.json()).error.code).toBe("invalid_build");

  expect((await api("/api/players/me/build", json("PUT", DEFAULT_BUILD))).status).toBe(200);

  const go = await api("/api/players/me/runs", { method: "POST" });
  expect(go.status).toBe(202);
  expect(QueueStateSchema.safeParse(await go.json()).success).toBe(true);
  const again = await api("/api/players/me/runs", { method: "POST" });
  expect((await again.json()).error.code).toBe("run_in_progress");

  // Leave the race: back in the garage, and Go works again.
  const left = await api("/api/players/me/race", { method: "DELETE" });
  expect(QueueStateSchema.safeParse(await left.json()).success).toBe(true);
  const none = await api("/api/players/me/race", { method: "DELETE" });
  expect((await none.json()).error.code).toBe("not_found");
  expect((await api("/api/players/me/runs", { method: "POST" })).status).toBe(202);
});

test("admin routes need the PIN", async () => {
  expect((await api("/api/admin/players")).status).toBe(401);
  const res = await api("/api/admin/players", { headers: { "x-admin-pin": "1234" } });
  expect((await res.json()).length).toBe(5);
});
