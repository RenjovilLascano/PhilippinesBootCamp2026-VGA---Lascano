const { Chip, chart, PH, WIN } = require('./chip.js');
let ok = true; const check = (c, m) => { if (!c) { ok = false; console.log('FAIL:', m); } };

// 1) Perfect play (hits at exact start, also early/late within window): dancers always in sync
for (const off of [0, -4, -2, 3, 4]) {
  const c = new Chip(0xACE1); let outOfSync = 0;
  for (let e = 0; e < 32 * 20; e++) {
    c.tick();
    for (let ph = 0; ph < PH; ph++) {
      // press for the note starting at e (or e+1 when pressing early)
      const target = off < 0 ? e + 1 : e;
      const phPress = off < 0 ? PH + off : off;
      if (ph === phPress && c.note.start === target) c.press(c.note.lane, ph);
      c.phase(ph);
    }
    if (c.frame !== e % 32) outOfSync++;
  }
  check(c.misses === 0 && outOfSync === 0, `perfect play off=${off}: misses=${c.misses} outOfSync=${outOfSync}`);
  const sumLen = c.events.reduce((a, ev) => a + ev.note.len, 0);
  check(c.score === sumLen, `score = sum of hit note values (${c.score} vs ${sumLen})`);
  if (off === 0) console.log(`perfect play: ${c.hits} hits, score ${c.score}, 0 misses, photo in sync for all ${32*20} eighths`);
}

// 2) Miss one note, then hit the next: photo freezes, then catches up by the missed amount
{
  const c = new Chip(0xACE1); const notes = chart(0xACE1, 6); const skip = 2; let log = [], errLog = [];
  for (let e = 0; e < notes[5].start + 1; e++) {
    c.tick();
    const idx = notes.findIndex(n => n.start === e);
    if (idx >= 0 && idx !== skip) c.press(notes[idx].lane, 0);
    for (let ph = 0; ph < PH; ph++) c.phase(ph);
    log.push(c.frame); errLog.push(c.err);
  }
  const m = notes[skip], nxt = notes[skip + 1];
  const frozen = log.slice(m.start, nxt.start).every(f => f === m.start - 1);
  check(frozen, 'photo should freeze during the missed note');
  check(log[nxt.start] === nxt.start % 32, 'photo should catch up on the next hit');
  check(errLog[m.start] === true && errLog[nxt.start] === false, 'miss screen on after the miss, off after the next hit');
  console.log(`missed note ${skip} (${m.len} eighths): photo froze at ${m.start-1} for ${m.len}, then jumped to ${log[nxt.start]} (+${log[nxt.start]-(m.start-1)}) on the next hit`);
}

// 3) Wrong lane = miss; press outside window ignored
{
  const c = new Chip(0xACE1);
  for (let e = 0; e < 8; e++) c.tick();       // abs = 7
  c.phase(0);
  check(c.press(0, 0) === null, 'press far from a note is ignored');
  c.tick();                                    // abs = 8, first note
  const r = c.press((c.events.length, (c.note.lane + 1) % 3), 1);
  check(r && r.type === 'wrong' && c.misses === 1 && c.combo === 0 && c.err, 'wrong lane counts as a miss and shows the miss screen');
  check(c.score === 0, 'a miss adds nothing to the score');
  console.log('wrong lane -> miss, stray press -> ignored');
}

// 4) Chart statistics: lengths, alignment, lanes
{
  const n = chart(0xACE1, 2000); const lens = {}, lanes = [0,0,0]; let aligned = true;
  n.forEach(x => { lens[x.len] = (lens[x.len]||0)+1; lanes[x.lane]++; if (x.start % x.len) aligned = false; });
  check(aligned, 'every note aligned to its length');
  console.log('lengths', lens, 'lanes', lanes, 'aligned', aligned);
}
console.log(ok ? 'ALL CHECKS PASSED' : 'SOME CHECKS FAILED');
