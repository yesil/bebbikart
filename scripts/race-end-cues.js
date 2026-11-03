// Renders the big screen's race-end cues (apps/game/assets/audio/sfx/end_*.ogg): short brass
// fanfares composed for BebbiKart, written here as notes, rendered with FluidSynth and the
// MuseScore General soundfont (MIT), then levelled with ffmpeg.
//
//   SOUNDFONT=/path/to/MuseScore_General.sf2 bun run audio:cues [--out=DIR] [--only=a,b]
//
// Needs `fluidsynth` (2.x) and an `ffmpeg` built with libvorbis on the PATH, and the soundfont.
// Debian/Ubuntu: `apt install fluidsynth ffmpeg musescore-general-soundfont-lossless` (the
// soundfont lands in /usr/share/sounds/sf2/MuseScore_General_Full.sf2). macOS: `brew install
// fluid-synth`, MuseScore_General.sf2 from https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/
// and an ffmpeg with libvorbis (Homebrew's ffmpeg 9 has none). Anything missing stops the
// script with an error; nothing is skipped.
//
// Every cue is in F major. The village music sits in D minor and the countryside in F major,
// which share their notes, so a cue never clashes with the music it dips under.
// Times are in seconds. The audio director (apps/game/audio/audio_director.gd) picks the cue
// for a lap's verdict, dips the music for the cue's length and places the crowd and the horn.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const OUT_DEFAULT = resolve(
  import.meta.dir ?? import.meta.dirname,
  "../apps/game/assets/audio/sfx",
);

// ---------------------------------------------------------------- instruments

// channel -> [GM program, pan (0..127), reverb send (0..127), volume (0..127)]
const CH = {
  trumpet: [0, 56, 64, 52, 112],
  brass: [1, 61, 78, 52, 96],
  horns: [2, 60, 48, 56, 100],
  trombone: [3, 57, 56, 50, 100],
  tuba: [4, 58, 64, 44, 96],
  timpani: [5, 47, 64, 56, 110],
  glock: [6, 9, 88, 72, 86],
  strings: [7, 48, 40, 64, 84],
  xylo: [8, 13, 84, 56, 92],
  drums: [9, 0, 64, 52, 108],
  bells: [10, 14, 74, 70, 84],
  vibes: [11, 11, 54, 66, 100],
  pizz: [12, 45, 60, 52, 104],
};

// GM drum keys
const KICK = 36;
const SNARE = 38;
const CRASH = 49;
const CRASH2 = 57;
const SPLASH = 55;
const TRIANGLE = 81;
const TAMBOURINE = 54;

const PITCH = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
/** "Bb4" -> MIDI note number (C4 = 60). */
function n(name) {
  const m = /^([A-G])(b|#)?(-?\d)$/.exec(name);
  if (!m) throw new Error(`bad note name ${name}`);
  return 12 * (Number(m[3]) + 1) + PITCH[m[1]] + (m[2] === "b" ? -1 : m[2] === "#" ? 1 : 0);
}

// ---------------------------------------------------------------- score helpers

class Score {
  constructor(name, length) {
    this.name = name;
    this.length = length; // seconds of MIDI, the reverb tail included
    this.events = []; // [ms, order, bytes]
  }
  note(ch, at, dur, notes, vel = 100) {
    const c = CH[ch][0];
    for (const nm of [notes].flat()) {
      const k = typeof nm === "number" ? nm : n(nm);
      this.events.push([Math.round(at * 1000), 1, [0x90 | c, k, vel]]);
      this.events.push([Math.round((at + dur) * 1000), 0, [0x80 | c, k, 0]]);
    }
    return this;
  }
  /**
   * A line of steps, each starting where the last ended (plus gap): "C5:0.13:108 F5:0.13", a
   * step being note:seconds[:velocity].
   */
  line(ch, at, steps, vel = 100, gap = 0.01) {
    let t = at;
    for (const step of steps.trim().split(/\s+/)) {
      const [nm, d, v] = step.split(":");
      this.note(ch, t, Number(d), nm, v ? Number(v) : vel);
      t += Number(d) + gap;
    }
    return this;
  }
  drum(at, key, vel = 100) {
    return this.note("drums", at, 0.2, key, vel);
  }
  /** A timpani (or other) roll: repeated strokes from vel0 to vel1. */
  roll(ch, from, to, note, vel0, vel1, every = 0.045) {
    const count = Math.max(1, Math.round((to - from) / every));
    for (let i = 0; i < count; i++) {
      const v = Math.round(vel0 + ((vel1 - vel0) * i) / Math.max(1, count - 1));
      this.note(ch, from + i * every, every * 0.9, note, v);
    }
    return this;
  }
  cc(ch, at, num, value) {
    this.events.push([Math.round(at * 1000), 0, [0xb0 | CH[ch][0], num, value]]);
    return this;
  }
  /** Expression (CC11) ramp, for a held chord that swells or fades. */
  swell(ch, from, to, v0, v1, steps = 16) {
    for (let i = 0; i <= steps; i++) {
      this.cc(ch, from + ((to - from) * i) / steps, 11, Math.round(v0 + ((v1 - v0) * i) / steps));
    }
    return this;
  }
  /** The same expression ramp on several channels (a section swelling or dying away). */
  swells(chs, from, to, v0, v1) {
    for (const ch of chs) this.swell(ch, from, to, v0, v1);
    return this;
  }
  /** Pitch bend in semitones (the default bend range is +-2). */
  bend(ch, at, semis) {
    const v = Math.max(0, Math.min(16383, Math.round(8192 + semis * 4096)));
    this.events.push([Math.round(at * 1000), 0, [0xe0 | CH[ch][0], v & 0x7f, v >> 7]]);
    return this;
  }
  midi() {
    const head = [];
    for (const [c, prog, pan, rev, vol] of Object.values(CH)) {
      if (c !== 9) head.push([0, -2, [0xc0 | c, prog]]);
      head.push([0, -1, [0xb0 | c, 10, pan]]);
      head.push([0, -1, [0xb0 | c, 91, rev]]);
      head.push([0, -1, [0xb0 | c, 93, 0]]); // no chorus
      head.push([0, -1, [0xb0 | c, 7, vol]]);
      head.push([0, -1, [0xb0 | c, 11, 127]]);
    }
    const all = [...head, ...this.events].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    const bytes = [];
    const vlq = (x) => {
      const out = [x & 0x7f];
      for (x >>= 7; x > 0; x >>= 7) out.unshift((x & 0x7f) | 0x80);
      return out;
    };
    // 480 ticks per quarter at 480000 us per quarter: one tick is one millisecond.
    bytes.push(0x00, 0xff, 0x51, 0x03, 0x07, 0x53, 0x00);
    let last = 0;
    for (const [ms, , ev] of all) {
      bytes.push(...vlq(ms - last), ...ev);
      last = ms;
    }
    const end = Math.round(this.length * 1000);
    if (end < last)
      throw new Error(`${this.name}: length ${this.length} s cuts notes off (${last} ms)`);
    bytes.push(...vlq(end - last), 0xff, 0x2f, 0x00);
    const u32 = (x) => [(x >>> 24) & 255, (x >>> 16) & 255, (x >>> 8) & 255, x & 255];
    return Buffer.from([
      ...Buffer.from("MThd"),
      ...u32(6),
      0,
      0,
      0,
      1,
      0x01,
      0xe0,
      ...Buffer.from("MTrk"),
      ...u32(bytes.length),
      ...bytes,
    ]);
  }
}

// ---------------------------------------------------------------- the cues

const F = ["F3", "A3", "C4", "F4"];

/** A lap finished, no record: bright and short, rising to a held high C. */
function finish() {
  const s = new Score("end_finish", 2.6);
  s.line("trumpet", 0.0, "C5:0.13:108 F5:0.13 A5:0.13 G5:0.11 A5:0.11");
  s.note("trumpet", 0.72, 1.05, "C6", 112);
  s.line("xylo", 0.0, "C6:0.13 F6:0.13 A6:0.13 G6:0.11 A6:0.11", 92);
  s.note("brass", 0.0, 0.13, ["F4", "A4", "C5"], 104);
  s.note("brass", 0.45, 0.11, ["E4", "G4", "C5"], 92);
  s.note("brass", 0.72, 1.05, ["F4", "A4", "C5"], 104);
  s.note("trombone", 0.0, 0.13, "F3", 100).note("trombone", 0.45, 0.11, "C3", 92);
  s.note("trombone", 0.72, 1.05, ["F2", "F3"], 104);
  s.note("strings", 0.72, 1.1, F, 76).swell("strings", 0.72, 1.85, 127, 70);
  s.note("timpani", 0.0, 0.3, "F2", 96).note("timpani", 0.72, 0.6, "F2", 112);
  s.drum(0.0, KICK, 100).drum(0.0, SPLASH, 88);
  s.drum(0.72, KICK, 112).drum(0.72, CRASH, 100);
  s.line("glock", 0.72, "F6:0.07 A6:0.07 C7:0.07 F7:0.6", 84, 0);
  s.swells(["trumpet", "brass", "trombone"], 1.42, 1.77, 127, 72);
  return s;
}

/** A personal best (short of the crown): climbing steps F-Bb-C, then a ringing F chord. */
function best() {
  const s = new Score("end_best", 3.0);
  const steps = ["F4", "A4", "Bb4", "D5", "C5", "E5"];
  const at = [0.0, 0.12, 0.26, 0.38, 0.52, 0.64];
  steps.forEach((nm, i) => {
    s.note("trumpet", at[i], 0.11, nm, 104 + i * 2);
    s.note("glock", at[i], 0.12, n(nm) + 24, 70);
  });
  s.line("horns", 0.0, "C4:0.11 F4:0.11", 92, 0.01);
  s.line("horns", 0.26, "F4:0.11 Bb4:0.11", 94, 0.01);
  s.line("horns", 0.52, "G4:0.11 C5:0.11", 96, 0.01);
  s.note("trumpet", 0.8, 1.2, "F5", 116);
  s.note("horns", 0.8, 1.2, "A4", 104);
  s.note("brass", 0.0, 0.22, ["F3", "A3", "C4"], 100);
  s.note("brass", 0.26, 0.22, ["F3", "Bb3", "D4"], 100);
  s.note("brass", 0.52, 0.22, ["E3", "G3", "C4"], 102);
  s.note("brass", 0.8, 1.2, ["F3", "A3", "C4", "F4"], 108);
  s.note("trombone", 0.0, 0.22, "F2", 96).note("trombone", 0.26, 0.22, "Bb2", 98);
  s.note("trombone", 0.52, 0.22, "C3", 100).note("trombone", 0.8, 1.2, ["F2", "F3"], 108);
  s.note("tuba", 0.26, 0.22, "Bb1", 90).note("tuba", 0.52, 0.22, "C2", 92);
  s.note("tuba", 0.8, 1.2, "F1", 100);
  s.note("strings", 0.8, 1.3, [...F, "A4"], 80).swell("strings", 0.8, 2.1, 127, 64);
  s.note("timpani", 0.0, 0.3, "F2", 92).note("timpani", 0.52, 0.3, "C2", 96);
  s.note("timpani", 0.8, 0.6, "F2", 118);
  s.drum(0.0, KICK, 96).drum(0.0, CRASH2, 84);
  for (const t of [0.0, 0.26, 0.52]) s.drum(t, TAMBOURINE, 74);
  s.drum(0.8, KICK, 112).drum(0.8, CRASH, 108).drum(0.8, TRIANGLE, 92);
  s.note("bells", 0.8, 1.6, "F5", 96);
  s.line("glock", 0.8, "F6:0.06 A6:0.06 C7:0.06 F7:0.06 A7:0.7", 86, 0);
  s.swells(["trumpet", "horns", "brass", "trombone", "tuba"], 1.62, 2.0, 127, 70);
  return s;
}

/**
 * The crown's motif, shared by the new record and the podium: a hit on F, a quick climb to a
 * held top C, then down Bb-A-G-E to the F.
 */
function crownOpening(s, vel = 118) {
  s.note("trumpet", 0.0, 0.24, "F5", vel);
  s.line("trumpet", 0.3, "C5:0.09 F5:0.09 A5:0.09", vel - 8);
  s.note("trumpet", 0.6, 0.76, "C6", vel - 2);
  s.line("trumpet", 1.4, "Bb5:0.18 A5:0.18 G5:0.18 E5:0.18", vel - 6, 0.02);
  s.note("horns", 0.0, 0.24, "C4", vel - 14);
  s.line("horns", 0.3, "A3:0.09 C4:0.09 F4:0.09", vel - 20);
  s.note("horns", 0.6, 0.76, "A4", vel - 12);
  s.line("horns", 1.4, "F4:0.18 F4:0.18 E4:0.18 C4:0.18", vel - 16, 0.02);
  s.note("brass", 0.0, 0.28, ["F3", "C4", "F4", "A4"], vel);
  s.note("brass", 0.6, 0.76, ["C3", "F3", "A3", "C4"], vel - 14);
  s.note("brass", 1.4, 0.18, ["Bb2", "D3", "F3", "Bb3"], vel - 10);
  s.note("brass", 1.6, 0.18, ["A2", "D3", "F3", "A3"], vel - 10);
  s.note("brass", 1.8, 0.38, ["C3", "E3", "G3", "Bb3"], vel - 8);
  s.note("trombone", 0.0, 0.28, "F2", vel - 6).note("trombone", 0.6, 0.76, "C3", vel - 18);
  s.line("trombone", 1.4, "Bb2:0.18 A2:0.18 C3:0.38", vel - 12, 0.02);
  s.note("tuba", 0.0, 0.28, "F1", vel - 10).note("tuba", 0.6, 0.76, "C2", vel - 22);
  s.line("tuba", 1.4, "Bb1:0.18 A1:0.18 C2:0.38", vel - 16, 0.02);
  s.note("strings", 0.6, 0.78, ["C4", "F4", "A4", "C5"], 84).swell("strings", 0.6, 1.38, 80, 118);
  s.note("strings", 1.4, 0.18, ["Bb3", "D4", "F4", "Bb4"], 84);
  s.note("strings", 1.6, 0.18, ["A3", "D4", "F4", "A4"], 84);
  s.note("strings", 1.8, 0.38, ["G3", "C4", "E4", "Bb4"], 88);
  s.note("timpani", 0.0, 0.4, "F2", 124);
  s.roll("timpani", 0.62, 1.36, "F2", 40, 92);
  s.note("timpani", 1.8, 0.2, "C2", 100).note("timpani", 2.0, 0.2, "C2", 92);
  s.drum(0.0, KICK, 122).drum(0.0, CRASH, 120).drum(0.0, CRASH2, 108);
  for (const [t, v] of [
    [1.82, 70],
    [1.92, 78],
    [2.02, 88],
    [2.12, 100],
  ])
    s.drum(t, SNARE, v);
  s.note("glock", 0.0, 0.3, "F6", 92).note("glock", 0.6, 0.6, "C7", 86);
  return s;
}

/** The big F chord a fanfare lands on at `at`, held `hold` s, with a roll into a short button. */
function crownLanding(s, at, hold, vel = 120) {
  const end = at + hold;
  s.note("trumpet", at, hold, "F5", vel);
  s.note("horns", at, hold, ["A3", "C4"], vel - 14);
  s.note("brass", at, hold, ["F3", "A3", "C4", "F4"], vel - 4);
  s.note("trombone", at, hold, ["F2", "F3"], vel - 6);
  s.note("tuba", at, hold, "F1", vel - 10);
  s.note("strings", at, hold + 0.05, ["F3", "A3", "C4", "F4", "A4", "C5"], 92);
  s.swell("strings", at, end, 96, 124);
  // Held a touch softer after the hit, then swelling into the button.
  s.swells(["trumpet", "horns", "brass", "trombone", "tuba"], at + 0.12, end - 0.02, 98, 127);
  s.note("timpani", at, 0.3, "F2", 127);
  s.roll("timpani", at + 0.25, end - 0.05, "F2", 44, 112);
  s.drum(at, KICK, 127).drum(at, CRASH, 124).drum(at, CRASH2, 112).drum(at, TRIANGLE, 96);
  s.note("bells", at, 1.6, "F5", 104);
  s.line("glock", at, "F6:0.06 A6:0.06 C7:0.06 F7:0.5", 96, 0);
  s.line("glock", at + 0.62, "A6:0.06 C7:0.06 F7:0.5", 76, 0);
  // The button.
  s.note("trumpet", end, 0.3, ["F5"], 124).note("horns", end, 0.3, ["A4", "C5"], 112);
  s.note("brass", end, 0.3, ["F3", "A3", "C4", "F4", "A4"], 124);
  s.note("trombone", end, 0.3, ["F2", "F3"], 118).note("tuba", end, 0.3, "F1", 112);
  s.note("strings", end, 0.32, ["F3", "C4", "F4", "A4", "F5"], 100);
  s.note("timpani", end, 0.5, ["C2", "F2"], 127);
  s.drum(end, KICK, 127).drum(end, CRASH, 120).drum(end, CRASH2, 116);
  s.note("bells", end, 1.4, ["F5", "C6"], 100);
  s.note("glock", end, 0.8, ["C7", "F7"], 100);
  return end + 0.3;
}

/** A new record or a new champion: the crown's motif, landing on a held F and a button. */
function record() {
  const s = new Score("end_record", 5.6);
  crownOpening(s);
  crownLanding(s, 2.2, 1.55);
  return s;
}

/** The session's podium: the crown's motif twice, the second time up to D and home. */
function podium() {
  const s = new Score("end_podium", 7.9);
  crownOpening(s);
  // Lands on F for a moment, climbs again, this time to a held D over B-flat.
  s.note("trumpet", 2.2, 0.4, "F5", 118).note("horns", 2.2, 0.4, ["A3", "C4"], 100);
  s.note("brass", 2.2, 0.4, ["F3", "A3", "C4", "F4"], 112);
  s.note("trombone", 2.2, 0.4, "F2", 110).note("tuba", 2.2, 0.4, "F1", 106);
  s.note("strings", 2.2, 0.42, ["F3", "A3", "C4", "F4"], 88);
  s.note("timpani", 2.2, 0.3, "F2", 120);
  s.drum(2.2, KICK, 120).drum(2.2, CRASH, 112);
  s.line("trumpet", 2.65, "C5:0.09 F5:0.09 A5:0.09", 110);
  s.line("horns", 2.65, "A3:0.09 C4:0.09 F4:0.09", 98);
  s.note("trumpet", 2.95, 0.76, "D6", 120).note("horns", 2.95, 0.76, ["F4", "Bb4"], 106);
  s.note("brass", 2.95, 0.76, ["Bb2", "F3", "Bb3", "D4"], 110);
  s.note("trombone", 2.95, 0.76, "Bb2", 106).note("tuba", 2.95, 0.76, "Bb1", 102);
  s.note("strings", 2.95, 0.78, ["Bb3", "D4", "F4", "Bb4", "D5"], 90);
  s.swell("strings", 2.95, 3.72, 84, 120);
  s.roll("timpani", 2.97, 3.72, "F2", 44, 96);
  s.drum(2.95, CRASH2, 104).note("glock", 2.95, 0.6, ["D7"], 88);
  // Down to the C7 and home.
  s.line("trumpet", 3.75, "C6:0.18 A5:0.18 G5:0.33", 116, 0.02);
  s.line("horns", 3.75, "A4:0.18 F4:0.18 E4:0.33", 102, 0.02);
  s.note("brass", 3.75, 0.38, ["C3", "F3", "A3", "C4"], 108);
  s.note("brass", 4.15, 0.33, ["C3", "E3", "G3", "Bb3"], 112);
  s.note("trombone", 3.75, 0.38, "C3", 104).note("trombone", 4.15, 0.33, "C3", 108);
  s.note("tuba", 3.75, 0.38, "C2", 100).note("tuba", 4.15, 0.33, "C2", 104);
  s.note("strings", 3.75, 0.38, ["C4", "F4", "A4", "C5"], 90);
  s.note("strings", 4.15, 0.33, ["G3", "C4", "E4", "Bb4"], 94);
  s.roll("timpani", 4.15, 4.47, "C2", 60, 110);
  for (const [t, v] of [
    [4.17, 74],
    [4.25, 82],
    [4.33, 92],
    [4.41, 104],
  ])
    s.drum(t, SNARE, v);
  crownLanding(s, 4.5, 1.8);
  return s;
}

/** A best lap mid-run (runs of more than one lap): a quick bright chime. */
function bestLap() {
  const s = new Score("end_best_lap", 1.4);
  s.line("vibes", 0.0, "C6:0.08 F6:0.08 A6:0.75", 100, 0);
  s.line("glock", 0.0, "C7:0.08 F7:0.08 A7:0.6", 74, 0);
  s.drum(0.16, TRIANGLE, 76);
  return s;
}

/** A failed lap (OOPS!): a soft trombone slides down four steps, wobbles, a pizzicato shrugs. */
function oops() {
  const s = new Score("end_oops", 2.3);
  s.line("trombone", 0.0, "C4:0.27 B3:0.27 Bb3:0.27", 92, 0.03);
  s.note("trombone", 0.9, 0.78, "A3", 96);
  s.note("tuba", 0.0, 0.27, "F2", 70).note("tuba", 0.9, 0.78, "F1", 74);
  // The last note wobbles (a slow vibrato) and sags at the end.
  s.bend("trombone", 0.0, 0);
  for (let i = 0; i <= 30; i++) {
    const t = 1.02 + i * 0.018;
    s.bend("trombone", t, 0.28 * Math.sin(i * 0.68));
  }
  for (let i = 0; i <= 8; i++) s.bend("trombone", 1.56 + i * 0.015, -0.12 * i);
  s.bend("trombone", 1.75, 0);
  s.note("pizz", 1.78, 0.2, ["F2", "F3"], 100);
  s.note("pizz", 1.78, 0.2, ["C4"], 70);
  return s;
}

const CUES = { finish, best, record, podium, best_lap: bestLap, oops };
// Loudness each file is levelled to (integrated LUFS, true peak -1 dBTP). The director's LEVEL
// table sets how loud each plays against the music.
const LUFS = { finish: -14, best: -13.5, record: -13, podium: -13, best_lap: -16, oops: -16 };

// ---------------------------------------------------------------- render

function run(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8" });
  if (r.error) throw new Error(`${cmd} could not run (${r.error.message}); is it installed?`);
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")} failed:\n${r.stderr}`);
  return r.stderr + r.stdout;
}

function render(key, outDir, soundfont, tmp) {
  const score = CUES[key]();
  const mid = join(tmp, `${score.name}.mid`);
  const raw = join(tmp, `${score.name}.raw.wav`);
  const out = join(outDir, `${score.name}.ogg`);
  writeFileSync(mid, score.midi());
  run("fluidsynth", [
    "-ni",
    "-q",
    "-r",
    "44100",
    "-g",
    "0.45",
    "-o",
    "synth.reverb.active=1",
    "-o",
    "synth.reverb.room-size=0.62",
    "-o",
    "synth.reverb.damp=0.35",
    "-o",
    "synth.reverb.width=0.9",
    "-o",
    "synth.reverb.level=0.55",
    "-o",
    "synth.chorus.active=0",
    "-F",
    raw,
    soundfont,
    mid,
  ]);
  // Two-pass loudness: measure, then level linearly; a gentle limiter keeps the peaks under -1 dBTP.
  const pre = "highpass=f=32,atrim=start=0";
  const target = LUFS[key];
  const m = run("ffmpeg", [
    "-hide_banner",
    "-i",
    raw,
    "-af",
    `${pre},loudnorm=I=${target}:TP=-1.5:LRA=20:print_format=json`,
    "-f",
    "null",
    "-",
  ]);
  const j = JSON.parse(m.slice(m.lastIndexOf("{"), m.lastIndexOf("}") + 1));
  const fadeAt = (score.length - 0.35).toFixed(3);
  const ln = `loudnorm=I=${target}:TP=-1.5:LRA=20:linear=true:measured_I=${j.input_i}:measured_TP=${j.input_tp}:measured_LRA=${j.input_lra}:measured_thresh=${j.input_thresh}:offset=${j.target_offset}`;
  run("ffmpeg", [
    "-hide_banner",
    "-y",
    "-i",
    raw,
    "-af",
    `${pre},${ln},alimiter=limit=0.79:attack=1:release=40:level=false,atrim=end=${score.length},afade=t=out:st=${fadeAt}:d=0.35,aresample=44100`,
    "-c:a",
    "libvorbis",
    "-q:a",
    "6",
    out,
  ]);
  const check = run("ffmpeg", [
    "-hide_banner",
    "-i",
    out,
    "-af",
    "ebur128=peak=true",
    "-f",
    "null",
    "-",
  ]);
  const lufs = /I:\s+(-?[\d.]+) LUFS/.exec(check.slice(check.lastIndexOf("Summary")))?.[1];
  const peak = /Peak:\s+(-?[\d.]+) dBFS/.exec(check.slice(check.lastIndexOf("Summary")))?.[1];
  console.log(`${out}: ${score.length.toFixed(2)} s, ${lufs} LUFS, true peak ${peak} dBFS`);
}

function main() {
  const args = Object.fromEntries(
    process.argv.slice(2).map((a) => {
      const [k, v] = a.replace(/^--/, "").split("=");
      return [k, v ?? "1"];
    }),
  );
  const soundfont = process.env.SOUNDFONT;
  if (!soundfont)
    throw new Error("set SOUNDFONT to MuseScore_General.sf2 (see the top of this file)");
  if (!existsSync(soundfont)) throw new Error(`SOUNDFONT ${soundfont} does not exist`);
  const outDir = resolve(args.out ?? OUT_DEFAULT);
  mkdirSync(outDir, { recursive: true });
  const keys = args.only ? args.only.split(",") : Object.keys(CUES);
  for (const k of keys)
    if (!CUES[k]) throw new Error(`unknown cue ${k} (known: ${Object.keys(CUES)})`);
  const tmp = mkdtempSync(join(tmpdir(), "bk-cues-"));
  try {
    for (const k of keys) render(k, outDir, soundfont, tmp);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

main();
