// Renders a RacerSpec with the game's racer kit (Godot), so the critique pass can look at the racer
// that will actually appear, next to the child's drawings. Needs Godot and a display (not headless).
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const GAME_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "../../../apps/game");

export class RenderError extends Error {}

/**
 * @param {{ godot?: string, gameDir?: string, timeoutMs?: number }} [opts] godot defaults to
 *   BK_GODOT_BIN or "godot" on PATH.
 * @returns {{ name: string, render: (spec: object) => Promise<{ front: string, side: string }> }}
 *   data URLs of a 3/4 front view and a side view (PNG)
 */
export function createGodotRenderer(opts = {}) {
  const godot = opts.godot ?? process.env.BK_GODOT_BIN ?? "godot";
  const gameDir = opts.gameDir ?? GAME_DIR;
  const timeoutMs = opts.timeoutMs ?? 60_000;
  return {
    name: `godot:${godot}`,
    async render(spec) {
      const dir = await mkdtemp(join(tmpdir(), "bk-render-"));
      try {
        await writeFile(join(dir, "racer.spec.json"), JSON.stringify(spec));
        let proc;
        try {
          proc = Bun.spawn(
            [
              godot,
              "--path",
              gameDir,
              "--script",
              "res://racer_kit/tools/render_heroes.gd",
              "--",
              dir,
              join(dir, "png"),
              "--side",
            ],
            { stdout: "pipe", stderr: "pipe", timeout: timeoutMs },
          );
        } catch (err) {
          throw new RenderError(`can't start Godot (${godot}): ${err.message}. Set BK_GODOT_BIN.`);
        }
        const [code, out, errText] = await Promise.all([
          proc.exited,
          new Response(proc.stdout).text(),
          new Response(proc.stderr).text(),
        ]);
        if (code !== 0) {
          const why = `${errText}\n${out}`
            .split("\n")
            .filter((l) => /error/i.test(l))
            .slice(0, 3)
            .join(" | ");
          throw new RenderError(
            `Godot render failed (exit ${code}${proc.signalCode ? `, ${proc.signalCode}` : ""}): ${why || "no output"}`,
          );
        }
        const png = async (f) =>
          `data:image/png;base64,${(await readFile(join(dir, "png", f))).toString("base64")}`;
        return { front: await png("racer.png"), side: await png("racer.side.png") };
      } finally {
        await rm(dir, { recursive: true, force: true });
      }
    },
  };
}
