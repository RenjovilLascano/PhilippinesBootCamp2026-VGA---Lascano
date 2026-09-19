// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// gen_vectors.js: golden test vectors for the chip, made with the golden
// model reference/game_logic/chip.js.
//
//   node tools/gen_vectors.js        -> writes test/vectors.json
//
// The chip updates the game once per "step" (once per video frame, or once
// per scanline in test mode). This script walks chip.js through exactly the
// same schedule:
//
//   step k:  acc += 3155 (16 bits); on overflow a new eighth begins -> tick()
//            phase(acc >> 12)                     -> late misses
//            press(lane, phase) if a button was pressed during step k
//
// A START at step k instead resets the game (acc = 0, eighth 0) with a seed
// built from the beam position, the way project.v does:
//   seed = {vpos[5:0], hpos[9:1], 1},  vpos = k mod 525 (one step per line)
//
// For every scenario the file stores the button events and, each time the
// visible state changes, the debug bytes the chip must show from then on.
// test/test.py replays the events on the Verilog and compares every step.

'use strict';
const fs = require('fs');
const path = require('path');
const { Chip, PH, WIN } = require('../reference/game_logic/chip.js');

const INC = 3155;          // tempo increment per step (see src/tempo.v)
const LINES = 525;         // lines per frame: vpos = step mod 525 in test mode

// Result codes of src/judge.v
const RES = { none: 0, perfect: 1, great: 2, good: 3, miss: 4, wrong: 5 };

const bcd = (v, digits) => {
  let out = 0;
  for (let i = 0; i < digits; i++) { out |= (v % 10) << (4 * i); v = Math.floor(v / 10); }
  return out;
};
const log2 = (len) => [1, 2, 4, 8].indexOf(len);

// Small deterministic random generator so the vectors never change by accident.
function makeRandom(seed) {
  let s = seed >>> 0;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
}

// Simulates the chip step by step. `player` decides what to press.
class Run {
  constructor(name) {
    this.name = name;
    this.step = 0;
    this.acc = 0; this.pos = 0;
    this.playing = false;
    this.chip = new Chip(0xACE1);
    this.attractFrame = 0;
    this.result = RES.none;
    this.events = [];      // [step, 'start', h9] or [step, 'press', lanes]
    this.expect = [];      // [step, b0, b1, b2, b3, b4, b5, b6, b7, b8] on change
    this.seeds = [];
    this.last = '';
  }

  // Debug bytes as defined at the bottom of src/project.v. Byte 0 without the
  // `follow` bit and byte 1 without `pos`, and byte 3 without `phase`: the
  // test checks pos and phase with its own copy of the tempo.
  state() {
    const c = this.chip;
    if (!this.playing) {
      // attract mode: dancers follow the music, the note is the reset value
      return [this.attractFrame, 0, (8 << 3) | 0, 0, 0, 0, 0, 0, 0];
    }
    const n = c.note;
    return [
      (c.err ? 0x80 : 0) | 0x40 | c.frame,
      this.result,
      ((n.start % 32) << 3) | n.lane,
      log2(n.len),
      bcd(c.score % 10000, 4) & 0xff,
      bcd(c.score % 10000, 4) >> 8,
      bcd(Math.min(c.combo, 99), 2),
      bcd(Math.min(c.best, 99), 2),
      bcd(Math.min(c.misses, 99), 2),
    ];
  }

  record() {
    const s = this.state();
    const key = s.join(',');
    if (key !== this.last) { this.expect.push([this.step, ...s]); this.last = key; }
  }

  // Result code for the newest judgement of chip.js.
  noteResult() {
    const ev = this.chip.last;
    if (ev.type === 'miss') return RES.miss;
    if (ev.type === 'wrong') return RES.wrong;
    const a = Math.abs(ev.off);
    return a <= 1 ? RES.perfect : a <= 2 ? RES.great : RES.good;
  }

  // One step. `h9` starts a new game with that seed part; `lanes` lists the
  // lane buttons pressed during this step (the lowest one wins, like judge.v).
  doStep({ h9 = null, lanes = [] } = {}) {
    const c = this.chip;
    if (h9 !== null) {
      // test.py presses START at hpos 2*h9-1 inside the line and reads the
      // state at hpos 20, so h9 must stay between 16 and 390.
      if (h9 < 16 || h9 > 390) throw new Error(`h9 ${h9} out of range`);
      const seed = (((this.step % LINES) & 63) << 10) | (h9 << 1) | 1;
      this.events.push([this.step, 'start', h9]);
      this.seeds.push(seed);
      c.reset(seed);
      this.playing = true;
      this.acc = 0; this.pos = 0;
      this.result = RES.none;
      c.tick(); c.phase(0);
    } else {
      this.acc += INC;
      const wrap = this.acc >= 65536;
      this.acc &= 0xffff;
      if (wrap) this.pos = (this.pos + 1) % 32;
      const ph = this.acc >> 12;
      if (!this.playing) {
        if (wrap) this.attractFrame = this.pos;
      } else {
        if (wrap) c.tick();
        const before = c.events.length;
        c.phase(ph);
        if (c.events.length > before) this.result = RES.miss;
      }
      if (lanes.length) {
        this.events.push([this.step, 'press', lanes]);
        if (this.playing) {
          const r = c.press(Math.min(...lanes), ph);
          if (r) this.result = this.noteResult();
        }
      }
    }
    this.record();
    this.step++;
  }

  // Absolute time of the current step in sixteenths of an eighth.
  get t() { return this.chip.abs * PH + (this.acc >> 12); }

  // Runs `n` steps, asking `player(run, t_after_this_step)` for lanes.
  play(n, player) {
    for (let i = 0; i < n; i++) {
      // Work out the time this step will have, so the player can aim.
      let acc = this.acc + INC, abs = this.chip.abs;
      if (acc >= 65536) { acc &= 0xffff; abs++; }
      const tNext = abs * PH + (acc >> 12);
      this.doStep({ lanes: player ? player(this, tNext) : [] });
    }
  }

  toJSON() {
    return { name: this.name, steps: this.step, seeds: this.seeds, events: this.events, expect: this.expect };
  }
}

// A player that presses every note `off` sixteenths from its start (off may
// change per note), using `laneOf(note)` as the lane.
function aimPlayer(offOf, laneOf = (n) => n.lane) {
  const done = new Set();
  return (run, t) => {
    const n = run.chip.note;
    if (!run.playing || done.has(n.start)) return [];
    const off = offOf(n);
    if (t < n.start * PH + off) return [];
    done.add(n.start);
    return [laneOf(n)];
  };
}

const E = 21;  // about one eighth in steps (20.77)
const scenarios = [];

// 1. Attract mode, then perfect play right on the beat.
{
  const r = new Run('attract_then_perfect');
  r.play(120);
  r.doStep({ h9: 200 });
  r.play(40 * E, aimPlayer(() => 0));
  scenarios.push(r);
}

// 2. Early and late presses at every offset from -6 to +6 sixteenths.
{
  const r = new Run('early_late_sweep');
  r.doStep({ h9: 57 });
  let i = 0;
  const offs = [-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6];
  r.play(70 * E, aimPlayer(() => offs[i++ % offs.length]));
  scenarios.push(r);
}

// 3. Wrong lanes: every third note on the wrong lane.
{
  const r = new Run('wrong_lanes');
  r.doStep({ h9: 311 });
  let i = 0;
  r.play(40 * E, aimPlayer(() => 0, (n) => (i++ % 3 === 2 ? (n.lane + 1) % 3 : n.lane)));
  scenarios.push(r);
}

// 4. Play, then stay silent for 40 eighths (longer than the loop), then play.
{
  const r = new Run('silence_and_loop_wrap');
  r.doStep({ h9: 123 });
  r.play(20 * E, aimPlayer(() => 1));
  r.play(40 * E);
  r.play(24 * E, aimPlayer(() => -1));
  scenarios.push(r);
}

// 5. Restart in the middle of a game, and presses in the count-in bar.
{
  const r = new Run('restart');
  r.doStep({ h9: 390 });
  r.play(15 * E, aimPlayer(() => 2));
  r.doStep({ h9: 50 });
  r.play(4 * E, (run, t) => (t % 40 === 0 ? [t % 3] : []));
  r.play(20 * E, aimPlayer(() => -3));
  scenarios.push(r);
}

// 6. Random presses: random lanes, random times, sometimes two at once.
{
  const r = new Run('random_presses');
  const rnd = makeRandom(1234);
  r.doStep({ h9: 256 });
  r.play(60 * E, () => {
    if (rnd() > 0.12) return [];
    const a = Math.floor(rnd() * 3);
    return rnd() < 0.2 ? [a, (a + 1) % 3] : [a];
  });
  scenarios.push(r);
}

// 7. A long perfect run: combo and best stop at 99, score keeps counting.
{
  const r = new Run('long_combo');
  r.doStep({ h9: 77 });
  r.play(200 * E, aimPlayer(() => 0));
  scenarios.push(r);
}

const out = {
  about: 'Generated by tools/gen_vectors.js from reference/game_logic/chip.js. Do not edit.',
  inc: INC, ph: PH, win: WIN,
  scenarios: scenarios.map((s) => s.toJSON()),
};
const file = path.join(__dirname, '..', 'test', 'vectors.json');
fs.writeFileSync(file, JSON.stringify(out) + '\n');
for (const s of scenarios) {
  const c = s.chip;
  console.log(`${s.name.padEnd(24)} steps ${String(s.step).padStart(5)}  hits ${String(c.hits).padStart(3)}  ` +
              `misses ${String(c.misses).padStart(3)}  score ${String(c.score).padStart(4)}  best ${c.best}  records ${s.expect.length}`);
}
console.log(`wrote ${path.relative(process.cwd(), file)} (${fs.statSync(file).size} bytes)`);
