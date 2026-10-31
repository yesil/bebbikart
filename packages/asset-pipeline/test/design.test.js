import { describe, expect, test } from "bun:test";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { clampRacerSpec, RacerSpecSchema } from "@bebbikart/shared";
import { applyPatch, parseReply, runDesignJob } from "../src/design.js";
import { createMockClient, MOCK_DESIGNS, SAMPLE_RUNS } from "../src/mock.js";
import {
  buildDesignMessages,
  buildReviewMessages,
  designSystemPrompt,
  EXAMPLES,
  reviewSystemPrompt,
} from "../src/prompt.js";

const SAMPLES = join(import.meta.dir, "..", "samples");

describe("prompt", () => {
  test("worked examples are valid RacerSpecs", () => {
    expect(EXAMPLES.length).toBeGreaterThanOrEqual(1);
    for (const { reply } of EXAMPLES) {
      const r = RacerSpecSchema.safeParse(reply.spec);
      if (!r.success) console.error(r.error.issues);
      expect(r.success).toBe(true);
      expect(reply.spec.sound).toBeDefined();
    }
  });

  test("prompts list the kit, the checks and the reply shapes", () => {
    const design = designSystemPrompt();
    for (const word of [
      "animal4",
      "googly",
      "head_top",
      "ride_bottom",
      "drawingSticker",
      "crayon",
      "hooves",
      "meow",
      "featureMap",
    ]) {
      expect(design).toContain(word);
    }
    for (const word of [
      "not_a_drawing",
      "real_person",
      "importance",
      "schwarze Räder",
      "LOYALTY",
    ]) {
      expect(design).toContain(word);
    }
    for (const word of ["patch", "remove", "LOYALTY"]) {
      expect(reviewSystemPrompt()).toContain(word);
    }
  });

  test("messages carry both images and retry errors", () => {
    const design = JSON.stringify(
      buildDesignMessages({
        characterDataUrl: "data:a",
        vehicleDataUrl: "data:b",
        previousErrors: ["bad eyes"],
      }),
    );
    expect(design).toContain("data:a");
    expect(design).toContain("data:b");
    expect(design).toContain("bad eyes");
    const review = JSON.stringify(
      buildReviewMessages({
        characterDataUrl: "data:a",
        vehicleDataUrl: "data:b",
        design: { spec: { title: "Cat" } },
        renders: { front: "data:front", side: "data:side" },
      }),
    );
    expect(review).toContain("data:front");
    expect(review).toContain("Cat");
  });
});

describe("mock designs", () => {
  for (const [id, d] of Object.entries(MOCK_DESIGNS)) {
    test(`${id} is valid${id === "pair05" ? " after repair" : " as written"}`, () => {
      if (id === "pair05") {
        const r = clampRacerSpec(d.spec);
        expect(r.ok).toBe(true);
        expect(r.fixes.length).toBeGreaterThan(0);
        expect(r.spec.character.face.eyes).toBe("one_eye");
        expect(r.spec.ride.legs.style).toBe("claws");
      } else {
        const r = RacerSpecSchema.safeParse(d.spec);
        if (!r.success) console.error(id, r.error.issues);
        expect(r.success).toBe(true);
      }
    });
  }
});

describe("parseReply", () => {
  test("handles fences, empty and broken replies", () => {
    expect(parseReply('```json\n{"spec":null}\n```').ok).toBe(true);
    expect(parseReply("   ").ok).toBe(false);
    expect(parseReply("{nope").ok).toBe(false);
  });
});

describe("runDesignJob (mock)", () => {
  test("all sample runs end as expected and write viewer files", async () => {
    const out = await mkdtemp(join(tmpdir(), "bk-specs-"));
    try {
      const client = createMockClient();
      for (const [name, c, v] of SAMPLE_RUNS) {
        const statuses = [];
        const r = await runDesignJob(
          {
            jobId: name,
            playerId: "t",
            name,
            characterPath: join(SAMPLES, c),
            vehiclePath: join(SAMPLES, v),
            outDir: out,
          },
          (s) => statuses.push(s),
          { client },
        );
        expect(r.status).toBe(name.startsWith("reject-") ? "rejected" : "ready");
        if (r.status === "ready") {
          const onDisk = JSON.parse(await readFile(r.file, "utf8"));
          expect(RacerSpecSchema.safeParse(onDisk).success).toBe(true);
          expect(statuses).toEqual(["looking", "designing", "critiquing", "refining", "ready"]);
        }
      }
      const files = (await readdir(out)).filter((f) => f.endsWith(".spec.json"));
      expect(files.length).toBe(SAMPLE_RUNS.filter(([n]) => !n.startsWith("reject-")).length);
    } finally {
      await rm(out, { recursive: true, force: true });
    }
  });

  test("drawings the model can't design fail the job (no default racer)", async () => {
    const out = await mkdtemp(join(tmpdir(), "bk-specs-"));
    try {
      const client = createMockClient();
      const blank = join(SAMPLES, "tricky-blank-page.jpg");
      const r = await runDesignJob(
        {
          jobId: "x",
          playerId: "t",
          characterPath: blank,
          vehiclePath: blank,
          outDir: out,
          skipCheck: true,
        },
        undefined,
        { client },
      );
      expect(r.status).toBe("failed");
      expect(r.error).toContain("invalid 3 times");
    } finally {
      await rm(out, { recursive: true, force: true });
    }
  });

  test("a broken first reply is retried with the errors", async () => {
    const out = await mkdtemp(join(tmpdir(), "bk-specs-"));
    const seen = [];
    const mock = createMockClient();
    const client = {
      name: "fake",
      async complete(messages, opts, ctx) {
        if (ctx.stage !== "design") return mock.complete(messages, opts, ctx);
        seen.push(JSON.stringify(messages));
        return seen.length === 1 ? "" : mock.complete(messages, opts, ctx);
      },
    };
    try {
      const r = await runDesignJob(
        {
          jobId: "y",
          playerId: "t",
          characterPath: join(SAMPLES, "pair01-character-cat.jpg"),
          vehiclePath: join(SAMPLES, "pair01-vehicle-kart.jpg"),
          outDir: out,
        },
        undefined,
        { client },
      );
      expect(r.status).toBe("ready");
      expect(seen[1]).toContain("empty");
    } finally {
      await rm(out, { recursive: true, force: true });
    }
  });

  test("a failing call fails the job with the reason", async () => {
    const client = {
      name: "down",
      complete: async () => {
        throw new Error("HTTP 503");
      },
    };
    const r = await runDesignJob(
      {
        jobId: "z",
        playerId: "t",
        characterPath: join(SAMPLES, "pair01-character-cat.jpg"),
        vehiclePath: join(SAMPLES, "pair01-vehicle-kart.jpg"),
        outDir: tmpdir(),
      },
      undefined,
      { client },
    );
    expect(r.status).toBe("failed");
    expect(r.error).toContain("HTTP 503");
  });

  test("a design without sound, motion or tagline is sent back", async () => {
    const out = await mkdtemp(join(tmpdir(), "bk-specs-"));
    const mock = createMockClient();
    let designs = 0;
    const client = {
      name: "fake",
      async complete(messages, opts, ctx) {
        if (ctx.stage !== "design") return mock.complete(messages, opts, ctx);
        designs++;
        const reply = JSON.parse(await mock.complete(messages, opts, ctx));
        if (designs === 1) delete reply.spec.sound;
        else expect(JSON.stringify(messages)).toContain("spec.sound is missing");
        return JSON.stringify(reply);
      },
    };
    try {
      const r = await runDesignJob(
        {
          jobId: "s",
          playerId: "t",
          characterPath: join(SAMPLES, "pair01-character-cat.jpg"),
          vehiclePath: join(SAMPLES, "pair01-vehicle-kart.jpg"),
          outDir: out,
        },
        undefined,
        { client },
      );
      expect(r.status).toBe("ready");
      expect(r.spec.sound.horn).toBe("meow");
      expect(designs).toBe(2);
    } finally {
      await rm(out, { recursive: true, force: true });
    }
  });
});

describe("claude client", () => {
  test("turns pass messages into a system prompt and base64 image blocks", async () => {
    const { toClaudeMessages } = await import("../src/claude.js");
    const { system, turns } = toClaudeMessages(
      buildDesignMessages({
        characterDataUrl: "data:image/jpeg;base64,AAAA",
        vehicleDataUrl: "data:image/png;base64,BBBB",
      }),
    );
    expect(system).toContain("not_a_drawing");
    expect(turns).toHaveLength(1);
    const images = turns[0].content.filter((p) => p.type === "image");
    expect(images.map((i) => i.source.media_type)).toEqual(["image/jpeg", "image/png"]);
    expect(images[1].source.data).toBe("BBBB");
  });

  test("a missing ANTHROPIC_API_KEY fails loudly", async () => {
    const { createClaudeClient } = await import("../src/claude.js");
    const saved = process.env.ANTHROPIC_API_KEY;
    delete process.env.ANTHROPIC_API_KEY;
    try {
      expect(() => createClaudeClient()).toThrow("ANTHROPIC_API_KEY is not set");
    } finally {
      if (saved !== undefined) process.env.ANTHROPIC_API_KEY = saved;
    }
  });
});

describe("applyPatch", () => {
  const spec = structuredClone(MOCK_DESIGNS.pair01.spec);
  test("set, remove and add with indices from the original spec", () => {
    const n = spec.character.extras.length;
    const r = applyPatch(spec, [
      { op: "add", path: "ride.extras", value: { ...spec.ride.extras[0], color: 3 } },
      { op: "remove", path: "character.extras.0" },
      { op: "remove", path: "character.extras.2" },
      { op: "set", path: "character.extras.2.color", value: 4 },
      { op: "set", path: "ride.color", value: 0 },
    ]);
    expect(r.ok).toBe(true);
    expect(r.spec.ride.color).toBe(0);
    expect(r.spec.character.extras).toHaveLength(n - 2);
    expect(r.spec.ride.extras.at(-1).color).toBe(3);
    expect(spec.ride.color).toBe(1); // original untouched
  });
  test("bad paths and ops are reported, not guessed", () => {
    const r = applyPatch(spec, [
      { op: "set", path: "character.wings.size", value: 1 },
      { op: "remove", path: "ride.extras.99" },
      { op: "swap", path: "ride.color" },
    ]);
    expect(r.ok).toBe(false);
    expect(r.errors).toHaveLength(3);
  });
});
