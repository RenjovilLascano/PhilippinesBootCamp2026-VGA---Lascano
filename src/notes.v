// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// notes: holds the "current note", the next one the player has to hit.
//
// The song is an endless stream of back-to-back notes, so there is no chart
// in memory: only the random generator state and the current note. When the
// current note has been judged (hit or missed), `advance` makes the next note
// start right where this one ends.
//
// A new game starts from a seed. When START is pressed, `load_seed` puts the
// seed into the generator; `restart` then creates the first note at eighth 8
// (the first bar is a free count-in).
//
// The screen shows notes that are further ahead by running its own copy of
// note_gen from this state (see render.v), so no note queue is needed here.

`default_nettype none

module notes (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_seed,  // START was pressed: remember the seed
    input  wire [15:0] seed,       // never 0 (bit 0 is always 1)
    input  wire        restart,    // new game: first note at eighth 8
    input  wire        advance,    // current note judged: move to the next
    output reg  [15:0] rng,
    output reg  [ 4:0] start,      // eighth where the note begins
    output reg  [ 1:0] lane,
    output reg  [ 1:0] len         // length code: 1, 2, 4 or 8 eighths
);

  localparam [4:0] COUNT_IN = 5'd8;

  wire [ 4:0] next_start = restart ? COUNT_IN : start + (5'd1 << len);
  wire [15:0] next_rng;
  wire [ 1:0] next_lane, next_len;

  note_gen gen (
      .rng_in (rng),
      .start  (next_start[2:0]),
      .rng_out(next_rng),
      .lane   (next_lane),
      .len    (next_len)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      rng   <= 16'hACE1;
      start <= COUNT_IN;
      lane  <= 2'd0;
      len   <= 2'd0;
    end else if (load_seed) begin
      rng <= seed;
    end else if (restart || advance) begin
      rng   <= next_rng;
      start <= next_start;
      lane  <= next_lane;
      len   <= next_len;
    end
  end

endmodule
