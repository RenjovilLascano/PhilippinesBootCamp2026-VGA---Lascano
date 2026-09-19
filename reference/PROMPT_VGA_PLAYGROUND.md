# Dinorobong Tubo Dance Project: a 1-tile Tiny Tapeout VGA rhythm game

You are working in our GitHub repository for a Tiny Tapeout (TT) competition entry.
Build the **Dinorobong Tubo Dance Project** as a **self-contained VGA game on one TT
tile**: the chip generates the picture (VGA), the music (audio PWM) and all the game
logic, and it must run in the **TT VGA Playground** (https://vga-playground.com).
Judges evaluate the design, the README and supporting files, and the overall project
organization.

Work in phases. **Stop and report to me at every CHECKPOINT** before continuing.

---

## 1. Background and the files I'm giving you (in `reference/`)

We first built a browser prototype that uses 32 real photos, a real song and a miss
photo. **These cannot fit on a 1-tile chip:** TT's own guide notes that 32 bytes of
storage already use about 70% of a tile. So the chip version keeps the exact game rules
but **draws stylized dancers** and **synthesizes its own beat**.

- `reference/prototype/dinorobong_tubo.html`: the playable prototype. **Open it and play
  it first.** It defines the rules, the feel, the look (night-street palette, 32-bulb
  string, jeepney-colored lanes, +1/+2/+4/+8 note labels, red miss screen) and the text.
  `reference/prototype/src/` has its source and assets.
- `reference/game_logic/chip.js`: **the golden model of the game rules.** The chip must
  behave exactly like it (see section 3). `test_chip.js` holds its tests (`node test_chip.js`).
- `reference/art/poses_contact_sheet.jpg`: the 32 dance photos, numbered 0–31 (one per
  eighth note). Use it to design the dancer poses.
- `reference/art/miss_photo_original.webp` and `miss_photo_red.jpg`: the miss photo
  (three people posing) and its red-tinted version as shown in the prototype. Use it as
  the reference for the chip's miss screen.
- `reference/audio/BABABA_loop_32k.wav`: the original 11.09 s loop (32 eighths,
  ≈86.6 BPM). **Reference only. Never embed it or copy its melody into the chip.**
- `reference/audio/rhythm.json`: an automatic, rough onset analysis (kick, snare, hat per
  16th note, and bass estimates). Use it only as a starting point for the drum groove.

**Team:** [NAMES] · **School:** [SCHOOL] · **GitHub user:** [USERNAME]
**Media credits and permission:** [DANCERS / VIDEO / MUSIC / MISS PHOTO (TikTok @sagingsabad): WHO, AND CONFIRMATION WE MAY USE IT]

---

## 2. Platform facts (verify against current TT docs before relying on them)
- VGA: 640×480 @ 60 Hz, **25.175 MHz** clock, TinyVGA Pmod pinout on `uo_out`:
  `uo[0] R1, uo[1] G1, uo[2] B1, uo[3] VSYNC, uo[4] R0, uo[5] G0, uo[6] B0, uo[7] HSYNC`
  (2 bits per color = 64 colors). Use the playground's `hvsync_generator`.
- Audio: TT Audio Pmod, mono PWM on **`uio[7]`** (`uio_oe[7] = 1`). A PWM rate of at least
  about 200 kHz is recommended.
- Inputs: the VGA Playground shows 8 clickable `ui_in` buttons and supports a gamepad.
  Check the TT gamepad Pmod pinout and whether its standard decoder module fits.
- The project must load in the playground via
  `https://vga-playground.com/?repo=https://github.com/[USERNAME]/[REPO]`, which reads
  `info.yaml` and the source files. Follow the TT Verilog template structure exactly.
- **Exactly 1 tile (`tiles: "1x1"`).** Never increase it.

---

## 3. Game rules (identical to `chip.js`)
- **Tempo:** 32 eighth notes per loop (4 bars of 4/4), about 86.6 BPM (an eighth ≈
  346 ms ≈ 20.8 video frames). Derive the time from a **phase accumulator stepped once
  per video frame** (for example 16 bits; one eighth = one wrap of the fraction). Choose
  the increment so the tempo is as close to 86.6 BPM as practical. The top 4 fraction
  bits are the 1/16 phase used for judging.
- **Notes:** an endless random stream of back-to-back notes, each with a lane (0 left,
  1 middle, 2 right) and a length of 1/2/4/8 eighths. Generator: 16-bit Galois LFSR,
  taps `0xB400`, stepped 4× per note. `lane = r&3`; if 3 then `(r>>2)&3`; if still 3
  then lane 1. `c = (r>>4)&15`: 0–5 → 1, 6–11 → 2, 12–14 → 4, 15 → 8. Halve the length
  until `start % len == 0`. The first note starts at eighth 8 (**bar 1 is a free
  count-in**). New seed per game (from a free-running counter), never 0.
- **Judging:** a press counts for the next unjudged note within **±4/16 of an eighth**
  of its start. Right lane = **hit** (≤1/16 Perfect, ≤2/16 Great, else Good). Wrong lane
  = **miss** (note used up). No press by the window's end = **miss**. Presses outside
  every window are ignored.
- **Dancers (the core idea):** "dance frame" k (0–31) belongs to eighth k. On a hit of
  a note starting at s with length L, the dancers play through frames s … s+L−1 in time
  with the music (if the hit is late, jump to the current frame immediately). **On a
  miss, the miss screen appears** (section 4) and stays **until the next correct
  press**. That hit makes the dancers jump straight to the current music position,
  catching up by the missed amount. Perfect play = dancers always in sync with the beat.
- Track hits, misses, combo, best combo.

---

## 4. What the screen and speakers should do

**Screen (640×480). Suggested layout; adapt it to fit the tile:**
```
 ●○●●●●●●  ●●●●●●●●  ●●●●●●●●  ●●●●●●●●     <- 32 bulbs: lit = music position, ring = dance frame
 ┌──────────── stage ───────────┐ ┌─ L ─┬─ M ─┬─ R ─┐
 │  two dancers (stylized)       │ │ +2  │     │     │   notes fall toward the line;
 │  pose = dance frame 0..31     │ │     │ +1  │     │   label = +1/+2/+4/+8
 │                               │ │     │     │ +4  │   pale tail = note length
 └───────────────────────────────┘ ├─────┴─────┴─────┤ <- hit line
   combo 12        score 0345      │ flash on hit    │
```
- **Palette:** night-sky dark blue background, bulb amber, lanes jeepney red / amber /
  denim blue, near-white dancers, all mapped to the 64-color TinyVGA palette.
- **Dancers:** two stylized figures (blocky or stick-figure) whose pose follows the
  dance frame. Suggested approach: design **8 key poses** from the contact sheet (one
  per 4 frames: #0–3 wide squat with low hands, #8–11 hands behind the head, #16–19
  standing tall with an arm up and a sway, #24–27 leaning back with an arm over the
  head, and so on). Add a small per-frame offset (bounce/sway) so all 32 steps look
  different. The poses should be recognisable as the real choreography.
- **Miss screen (the chip version of the red miss photo):** the stage turns red (red-
  shade background with dark-red figures), showing **three figures in the "miss photo"
  pose** (tall figure with an arm up, a shorter one in the middle, a bald one with an
  arm behind the head). It stays until the next correct press.
- Bulb string, falling notes with their +N label, hit line, a flash on hits, combo and
  score digits (a simple 7-segment-style font is enough).

**Audio (on-chip synthesis, original):** a groove at the same tempo. At minimum kick and
hi-hat (LFSR noise with a decay) so players can hear the beat, then a snare/clap, and a
simple bass line if area allows. Use `rhythm.json` as a starting point, then simplify so
it sounds good. Add a short blip on hits and a low buzz on misses. Mute input.

**Priority if area is tight** (ask me before dropping anything in the first group):
1. Must-have: VGA timing, game rules, falling notes with lanes and labels, dancers (at
   least 4 poses), miss screen, kick + hat audio, buttons.
2. Should-have: 8 poses with per-frame offsets, bulb string, score/combo, snare, hit/miss sounds.
3. Nice-to-have: bass line, gamepad support, flash effects, three-figure miss pose detail.

---

## 5. Pinout (proposed; document any change)

| Pin | Name | Meaning |
|---|---|---|
| `ui[0..2]` | LEFT, MIDDLE, RIGHT | buttons (synchronised, rising edge) |
| `ui[3]` | START | start / restart a game (new seed) |
| `ui[4..6]` | gamepad | TT gamepad Pmod if supported, otherwise unused |
| `ui[7]` | MUTE | 1 = silence |
| `uo[7:0]` | VGA | TinyVGA pinout above |
| `uio[7]` | AUDIO | PWM audio (output) |
| other `uio` | | unused (inputs) |

Add a **simulation-only speed-up** if useful for tests (e.g. a spare input that steps
the tempo accumulator per scanline instead of per frame), clearly documented.

---

## 6. Phases

### PHASE A: Audit and setup
Show the repo tree and compare it with the TT **Verilog** template. If the repo came
from the Wokwi template, migrate it and remove Wokwi-only parts. Keep the TT workflows
(gds, docs, test, fpga) intact. Top module: `tt_um_[username]_tubo_dance`. Run
`node reference/game_logic/test_chip.js`. Put the reference material in `reference/`
(or `docs/reference/`) in the repo, **without** the WAV if I haven't confirmed the music rights.
**CHECKPOINT A:** findings and a size budget plan (flip-flops per block).

### PHASE B: Game core + golden-vector tests
- `src/`: small modules with header comments, e.g. `tempo.v` (frame accumulator),
  `notes.v` (LFSR + a small look-ahead queue for drawing), `judge.v`, `dance.v`
  (frame + miss state), `inputs.v`, and the top module.
- `tools/gen_vectors.js`: runs `chip.js` on many scenarios (perfect play, early/late at
  every phase, wrong lanes, misses, long silence, loop wrap, restarts) using the **same
  frame-based tempo schedule** as the chip. It writes expected per-event outputs.
- `test/test.py` (cocotb): replays the vectors and checks the dance frame, miss state,
  judgements and current note, using exposed debug state or observable outputs. It
  must pass RTL and gate-level (`GL_TEST`).
**CHECKPOINT B:** results and cell count (yosys `stat`).

### PHASE C: Graphics and audio
- `src/render.v`, `src/poses.v`, `src/digits.v`, `src/audio.v` (or similar).
- `tools/render_frame.py` (Verilator or iverilog): simulate the chip and save
  **PNG screenshots** (title/count-in, gameplay, miss screen) and a short **GIF** to
  `docs/images/`. Check that the dancers visibly follow the contact sheet's
  choreography and the miss screen reads as the miss photo.
- Tell me how to check it in the VGA Playground (the `?repo=` link).
**CHECKPOINT C:** screenshots plus an audio description (or a WAV rendered from simulation).

### PHASE D: Fit in 1 tile
Push and read the **gds** Action summary (utilisation, cells, precheck). If it's too
big, shrink it using the priority list: fewer or cheaper poses, narrower counters,
fewer look-ahead notes, simpler digits. **Ask me** before cutting a must-have.
**CHECKPOINT D:** final utilisation and what was simplified.

### PHASE E: Companion web version (optional, ask me first)
The photo-based prototype (`reference/prototype/`) can live in `web/` as a
companion showing the original concept with real photos. TT workflows use GitHub Pages
for the GDS viewer, so **ask me where to host it** and don't break the TT workflows.

### PHASE F: Documentation (heavily judged)
**README.md**, in this order:
1. Title, tagline, badges, and a gameplay GIF from simulation
2. **Play it:** the VGA Playground `?repo=` link, the controls, and a 3-line how-to
3. What it is (2–3 sentences)
4. Why it matters: it teaches note values by feel (an eighth, quarter, half or whole note
   moves the dancers 1, 2, 4 or 8 steps). Also rhythm literacy, and celebrating local
   street dance. Concrete and honest.
5. How it works: a Mermaid block diagram (tempo, note generator, judge, dance state,
   renderer, audio) and a short paragraph per block. Explain how the photos became
   poses and why (tile memory limits).
6. The exact rules
7. Pinout table (all ui/uo/uio pins)
8. Hardware: TT demo board, TinyVGA Pmod, Audio Pmod, buttons or gamepad, clock 25.175 MHz
9. Build, simulate and test (cocotb, golden vectors, screenshots)
10. Design decisions and limitations (tempo accuracy, judging resolution, area trade-offs)
11. Repository layout (a tree with one line per item)
12. Credits (dancers, video, music inspiration, miss photo, TT template and VGA
    Playground), team, license

**docs/info.md**: the TT datasheet page (How it works / How to test / External hardware)
with one screenshot. **info.yaml**: title, author, description, `language: "Verilog"`,
`clock_hz: 25175000`, `tiles: "1x1"`, `top_module`, `source_files`, descriptive pin
names; don't change `yaml_version`.

Code quality everywhere: SPDX headers, `default_nettype none`, comments written for a
student reader, no dead code, no lint warnings, `.gitignore` for build and simulation output.

---

## 7. Working rules
- Use a new branch `tubo-vga`. Make small, clear commits. Don't force-push or rewrite `main`.
- Iterate until **gds, docs and test are green** and gds reports 1x1.
- Never embed the song or the photos in the chip. Only use media we have rights to.
- Ask before changing game rules, cutting must-haves, or doing anything irreversible.

## 8. Final report
1. File-by-file summary
2. Utilisation, cells, and test counts (JS, cocotb RTL, gate-level)
3. Screenshots and the VGA Playground link
4. What was simplified, and what still needs real-hardware testing
5. Manual steps for me (merge, check in the VGA Playground, submit a new revision on
   app.tinytapeout.com)
