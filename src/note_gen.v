// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// note_gen: works out the next note from the random generator (no memory,
// pure logic). Same recipe as nextNote() in reference/game_logic/chip.js.
//
// 1. Step a 16-bit Galois LFSR (taps 0xB400) four times: shift right, and
//    if the bit that fell out was 1, flip the tap bits.
// 2. lane = r[1:0]; if that is 3, try r[3:2]; if still 3, use the middle.
// 3. c = r[7:4] picks the length: 0-5 -> 1 eighth, 6-11 -> 2, 12-14 -> 4,
//    15 -> 8 (the chance of each length is 6:6:3:1).
// 4. A note of length L may only start on a multiple of L. So the length is
//    halved until it fits: the length code is limited by the number of
//    trailing zero bits of the start position.
//
// Lengths are given as a 2-bit code: 0 = 1 eighth, 1 = 2, 2 = 4, 3 = 8.

`default_nettype none

module note_gen (
    input  wire [15:0] rng_in,
    input  wire [ 2:0] start,    // low bits of where the new note begins
    output wire [15:0] rng_out,
    output wire [ 1:0] lane,     // 0 left, 1 middle, 2 right
    output wire [ 1:0] len       // length code
);

  function [15:0] lfsr_step(input [15:0] r);
    lfsr_step = (r >> 1) ^ (r[0] ? 16'hB400 : 16'h0000);
  endfunction

  assign rng_out = lfsr_step(lfsr_step(lfsr_step(lfsr_step(rng_in))));

  wire [1:0] try1 = rng_out[1:0];
  wire [1:0] try2 = rng_out[3:2];
  assign lane = (try1 != 2'd3) ? try1 : (try2 != 2'd3) ? try2 : 2'd1;

  wire [3:0] c = rng_out[7:4];
  wire [1:0] wanted = (c < 4'd6) ? 2'd0 : (c < 4'd12) ? 2'd1 : (c < 4'd15) ? 2'd2 : 2'd3;

  // Longest length code allowed at this start: 0 if odd, 1 if a multiple
  // of 2, 2 if a multiple of 4, 3 if a multiple of 8 (or 0).
  wire [1:0] fits = start[0] ? 2'd0 : start[1] ? 2'd1 : start[2] ? 2'd2 : 2'd3;

  assign len = (wanted < fits) ? wanted : fits;

endmodule
