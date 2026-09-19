// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// judge: decides whether a button press hits the current note.
//
// Time is measured in sixteenths of an eighth: t = pos * 16 + phase. The
// note starts at s = start * 16. The difference d = t - s is kept as a 9-bit
// two's complement number, so it wraps nicely around the 32-eighth loop
// (d is negative while the note is still ahead of us).
//
//   |d| <= 4 when a button is pressed -> judged (right lane = hit, wrong lane = miss)
//   d > 4 and still not judged        -> miss (the window has closed)
//   any other press                   -> ignored
//
// A hit is Perfect for |d| <= 1, Great for |d| <= 2, otherwise Good.
//
// Presses arrive at any clock; the first one is kept in `pend_*` until the
// next game step so that the whole game updates once per frame. Each game
// step has two parts (see project.v): `check_late` looks for a closed window
// first, then `check_press` judges the pending press (against the next note
// if the current one was just missed), exactly like chip.js.

`default_nettype none

module judge (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,        // new game: forget presses and results
    input  wire [2:0] press,        // one-clock pulses {RIGHT, MIDDLE, LEFT}
    input  wire       check_late,   // game step, part 1
    input  wire       check_press,  // game step, part 2
    input  wire [4:0] pos,
    input  wire [3:0] phase,
    input  wire [4:0] note_start,
    input  wire [1:0] note_lane,
    output wire       hit,          // pulse: right lane inside the window
    output wire       miss,         // pulse: wrong lane, or window closed
    output wire       late,         // with hit: we are at or after the note start
    output reg  [2:0] result        // last result, see RES_* below
);

  localparam [2:0] RES_NONE = 3'd0, RES_PERFECT = 3'd1, RES_GREAT = 3'd2,
                   RES_GOOD = 3'd3, RES_MISS = 3'd4, RES_WRONG = 3'd5;

  // ---- remember the first press since the last game step ----
  reg       pend;
  reg [1:0] pend_lane;
  wire      any_press = |press;
  wire [1:0] press_lane = press[0] ? 2'd0 : press[1] ? 2'd1 : 2'd2;

  wire       have_press = pend | any_press;  // a press this very clock counts too
  wire [1:0] use_lane   = pend ? pend_lane : press_lane;

  // ---- distance between now and the note start ----
  wire [8:0] d      = {pos, phase} - {note_start, 4'd0};
  wire       ahead  = d[8];                       // d < 0
  wire [8:0] abs_d = ahead ? -d : d;             // |d|
  wire       in_window = (abs_d <= 9'd4);

  assign late = !ahead;

  wire window_closed = check_late && !ahead && !in_window;
  wire judged_press  = check_press && have_press && in_window;
  wire right_lane    = (use_lane == note_lane);

  assign hit  = judged_press && right_lane;
  assign miss = window_closed || (judged_press && !right_lane);

  always @(posedge clk) begin
    if (!rst_n || clear) begin
      pend      <= 1'b0;
      pend_lane <= 2'd0;
      result    <= RES_NONE;
    end else begin
      if (check_press) pend <= 1'b0;
      else if (any_press && !pend) begin
        pend      <= 1'b1;
        pend_lane <= press_lane;
      end

      if (window_closed) result <= RES_MISS;
      else if (judged_press)
        result <= !right_lane     ? RES_WRONG :
                  abs_d <= 9'd1    ? RES_PERFECT :
                  abs_d <= 9'd2    ? RES_GREAT : RES_GOOD;
    end
  end

endmodule
