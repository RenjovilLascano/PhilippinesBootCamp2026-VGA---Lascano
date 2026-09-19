// Dinorobong Tubo Dance Project - chip model (reference for the Verilog design).
// Everything here is integer / event based so it maps 1:1 onto hardware:
//   tick()            <- TICK input: a new eighth note starts (pos = 0..31)
//   press(lane, ph)   <- LEFT/MIDDLE/RIGHT button, ph = phase 0..PH-1 inside the eighth
//   phase(ph)         <- sub-eighth time passes (used for late-miss detection)
// Outputs: frame (0..31), err (miss screen on/off), last judgement, hit/miss counters, score, current note.
// Score: every hit adds the note's value in eighths (+1/+2/+4/+8, the label drawn on the note).

const PH = 16;             // phase resolution: 16 steps per eighth note
const WIN = 4;             // hit window = +/- 4/16 of an eighth (~87 ms at 86.6 BPM)
const COUNT_IN = 8;        // first bar: dancers move freely, first note starts at eighth 8

function lfsrStep(r) {     // 16-bit Galois LFSR, taps 0xB400 (maximal length)
  const lsb = r & 1;
  r >>= 1;
  if (lsb) r ^= 0xB400;
  return r;
}

// Note generator: lane 0..2, length 1/2/4/8 eighths, aligned so it sounds musical
// (a note of length L may only start on a multiple of L within the 32-eighth loop).
function nextNote(rng, start) {
  let r = rng;
  for (let i = 0; i < 4; i++) r = lfsrStep(r);        // 4 fresh bits per step
  let lane = r & 3;
  if (lane === 3) lane = (r >> 2) & 3;                    // re-roll once...
  if (lane === 3) lane = 1;                               // ...then middle (5:6:5 balance)
  const c = (r >> 4) & 15;
  let len = c < 6 ? 1 : c < 12 ? 2 : c < 15 ? 4 : 8;    // 6:6:3:1 weighting
  while ((start % len) !== 0) len >>= 1;                  // alignment clamp
  return { rng: r, note: { start, lane, len } };
}

// Deterministic song chart from a seed (the browser uses this for look-ahead;
// the chip generates the same notes one at a time).
function chart(seed, count, firstStart = COUNT_IN) {
  const out = []; let rng = seed, s = firstStart;
  for (let i = 0; i < count; i++) { const g = nextNote(rng, s); rng = g.rng; out.push(g.note); s += g.note.len; }
  return out;
}

class Chip {
  constructor(seed = 0xACE1) { this.reset(seed); }
  reset(seed = 0xACE1) {
    this.seed = seed;
    this.abs = -1;            // absolute eighth counter (song position, unwrapped)
    this.ph = 0;
    this.frame = 0;           // photo index 0..31 (output)
    this.err = false;         // true after a miss/wrong lane, until the next correct press (output)
    this.playStart = 0;       // photos may follow the music from playStart ...
    this.playEnd = COUNT_IN;  // ... up to (not including) playEnd  (count-in bar is free)
    const g = nextNote(seed, COUNT_IN); this.rng = g.rng; this.note = g.note;
    this.judged = false;
    this.hits = 0; this.misses = 0; this.combo = 0; this.best = 0; this.score = 0;
    this.last = null;         // {type:'hit'|'miss'|'wrong', note, off}
    this.events = [];
  }
  _advanceNote() {
    const g = nextNote(this.rng, this.note.start + this.note.len);
    this.rng = g.rng; this.note = g.note; this.judged = false;
  }
  _judge(type, off = 0) {
    const n = this.note;
    if (type === 'hit') {
      this.err = false;
      this.hits++; this.score += n.len; this.combo++; this.best = Math.max(this.best, this.combo);
      this.playStart = n.start; this.playEnd = n.start + n.len;
      if (this.abs >= n.start) this.frame = ((this.abs % 32) + 32) % 32;  // late hit: catch up now
    } else { this.misses++; this.combo = 0; this.err = true; }
    this.last = { type, note: n, off }; this.events.push(this.last);
    this._advanceNote();
  }
  tick() {                              // a new eighth note begins
    this.abs++; this.ph = 0;
    if (this.abs >= this.playStart && this.abs < this.playEnd) this.frame = this.abs % 32;
  }
  phase(ph) {                           // time inside the current eighth (0..PH-1)
    this.ph = ph;
    // window for current note closed without a press -> miss (repeat: a whole note
    // sequence can't be skipped in one step, but loop in case several are overdue)
    while (this.abs * PH + ph > this.note.start * PH + WIN) this._judge('miss');
  }
  press(lane, ph = this.ph) {
    this.phase(ph);
    const t = this.abs * PH + ph, s = this.note.start * PH;
    if (Math.abs(t - s) > WIN) return null;           // outside any window: ignored
    this._judge(lane === this.note.lane ? 'hit' : 'wrong', t - s);
    return this.last;
  }
}

if (typeof module !== 'undefined') module.exports = { Chip, chart, nextNote, lfsrStep, PH, WIN, COUNT_IN };
