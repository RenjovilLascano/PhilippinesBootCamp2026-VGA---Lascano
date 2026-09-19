// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// Dinorobong Tubo Dance Project: a rhythm game on one Tiny Tapeout tile.
//
// Top module. It connects the blocks and runs the game once per frame:
//
//   hvsync_generator  beam position and VGA sync pulses
//   inputs            synchronised buttons, rising-edge pulses
//   tempo             song position (eighth 0..31 and 16 phases per eighth)
//   notes             random stream of notes (lane + length)
//   judge             hit / miss decisions
//   dance             dance frame 0..31 and the miss screen
//   stats             score, combo, best combo, misses
//
// Game step: at the end of the last visible line, while the beam is outside
// the picture, the game takes one step in three clocks:
//   step0  tempo moves on (or a new game starts)
//   step1  new eighth for the dancers; has the note window closed?  (miss)
//   step2  judge the button press, if any                          (hit/miss)
//
// Test mode (for simulation and bring-up): hold LEFT, MIDDLE, RIGHT and START
// (ui[3:0] = 1111) while reset is released. Then
//   * the game steps once per scanline instead of once per frame (525x faster)
//   * uo_out shows internal state instead of VGA; ui[7:4] picks the byte
//     (see the debug table at the bottom of this file).

`default_nettype none

module tt_um_renjovillascano_tubo_dance (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ---------------- VGA timing ----------------
  wire       hsync, vsync, display_on;
  wire [9:0] hpos, vpos;

  hvsync_generator vga_sync (
      .clk       (clk),
      .reset     (~rst_n),
      .hsync     (hsync),
      .vsync     (vsync),
      .display_on(display_on),
      .hpos      (hpos),
      .vpos      (vpos)
  );

  // ---------------- test mode, chosen at reset ----------------
  reg test_mode;
  always @(posedge clk) if (!rst_n) test_mode <= (ui_in[3:0] == 4'b1111);

  // ---------------- buttons ----------------
  wire [3:0] rise;
  wire       mute;

  inputs buttons (
      .clk    (clk),
      .rst_n  (rst_n),
      .btn    (ui_in[3:0]),
      .mute_in(ui_in[7]),
      .rise   (rise),
      .mute   (mute)
  );

  // ---------------- game step sequencer ----------------
  wire line_end = (hpos == 10'd799);
  wire step0    = line_end && (test_mode || vpos == 10'd479);
  reg  step1, step2;
  reg  playing;     // 0 until the first START (attract mode)
  reg  start_pend;  // START pressed, the new game begins at the next step0

  always @(posedge clk) begin
    if (!rst_n) begin
      step1      <= 1'b0;
      step2      <= 1'b0;
      playing    <= 1'b0;
      start_pend <= 1'b0;
    end else begin
      step1 <= step0;
      step2 <= step1;
      if (rise[3]) start_pend <= 1'b1;
      else if (step0) start_pend <= 1'b0;
      if (step0 && start_pend) playing <= 1'b1;
    end
  end

  wire restart = step0 && start_pend;
  wire game_on = playing && !start_pend;

  // The seed is the beam position at the moment START is pressed: a human
  // cannot time that, so every game gets a different note stream. Bit 0 is
  // forced to 1 so the seed is never 0 (an LFSR stuck at 0 never moves).
  wire [15:0] seed = {vpos[5:0], hpos[9:1], 1'b1};

  // ---------------- song clock ----------------
  wire [15:0] acc;
  wire [ 4:0] pos;
  wire        wrap;

  tempo song_clock (
      .clk    (clk),
      .rst_n  (rst_n),
      .step   (step0),
      .restart(restart),
      .acc    (acc),
      .pos    (pos),
      .wrap   (wrap)
  );

  wire [3:0] phase = acc[15:12];

  // ---------------- notes and judging ----------------
  wire [15:0] rng;
  wire [ 4:0] note_start;
  wire [ 1:0] note_lane, note_len;
  wire        hit, miss, late;
  wire [ 2:0] result;

  notes note_stream (
      .clk      (clk),
      .rst_n    (rst_n),
      .load_seed(rise[3]),
      .seed     (seed),
      .restart  (restart),
      .advance  (hit || miss),
      .rng      (rng),
      .start    (note_start),
      .lane     (note_lane),
      .len      (note_len)
  );

  judge judge_unit (
      .clk        (clk),
      .rst_n      (rst_n),
      .clear      (restart),
      .press      (rise[2:0]),
      .check_late (step1 && game_on),
      .check_press(step2 && game_on),
      .pos        (pos),
      .phase      (phase),
      .note_start (note_start),
      .note_lane  (note_lane),
      .hit        (hit),
      .miss       (miss),
      .late       (late),
      .result     (result)
  );

  // ---------------- dancers and score ----------------
  wire [4:0] frame;
  wire       err, follow;

  dance dancers (
      .clk       (clk),
      .rst_n     (rst_n),
      .playing   (playing),
      .restart   (restart),
      .new_eighth(step1 && wrap),
      .pos       (pos),
      .hit       (hit),
      .late      (late),
      .miss      (miss),
      .note_start(note_start),
      .note_len  (note_len),
      .frame     (frame),
      .err       (err),
      .follow    (follow)
  );

  wire [15:0] score;
  wire [ 7:0] combo, best, misses;

  stats counters (
      .clk     (clk),
      .rst_n   (rst_n),
      .clear   (restart),
      .hit     (hit),
      .miss    (miss),
      .note_len(note_len),
      .score   (score),
      .combo   (combo),
      .best    (best),
      .misses  (misses)
  );

  // ---------------- outputs ----------------
  // TinyVGA Pmod: {HSYNC, B0, G0, R0, VSYNC, B1, G1, R1}
  wire [7:0] vga_out = {hsync, 3'b000, vsync, 3'b000};

  // Debug bytes, test mode only (ui[7:4] selects):
  //   0 {err, playing, follow, frame[4:0]}    1 {pos[4:0], result[2:0]}
  //   2 {note_start[4:0], 1'b0, note_lane}     3 {phase[3:0], 2'b0, note_len}
  //   4 score[7:0]  5 score[15:8]  6 combo  7 best  8 misses   (BCD)
  reg [7:0] debug_out;
  always @(*) begin
    case (ui_in[7:4])
      4'd0:    debug_out = {err, playing, follow, frame};
      4'd1:    debug_out = {pos, result};
      4'd2:    debug_out = {note_start, 1'b0, note_lane};
      4'd3:    debug_out = {phase, 2'b00, note_len};
      4'd4:    debug_out = score[7:0];
      4'd5:    debug_out = score[15:8];
      4'd6:    debug_out = combo;
      4'd7:    debug_out = best;
      4'd8:    debug_out = misses;
      default: debug_out = 8'h00;
    endcase
  end

  assign uo_out  = test_mode ? debug_out : vga_out;
  assign uio_out = 8'h00;
  assign uio_oe  = 8'h80;  // uio[7] is the audio output

  wire _unused = &{ena, uio_in, display_on, mute, rng, acc[11:0], 1'b0};

endmodule
