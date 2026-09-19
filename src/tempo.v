// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// tempo: the song clock, stepped once per video frame.
//
// `acc` is a 12-bit phase accumulator: it counts how far we are inside the
// current eighth note, from 0 (the eighth just started) to 4095 (about to
// end). Every frame we add INC. When the sum overflows, a new eighth begins
// and `pos` (the eighth number inside the 32-eighth loop) moves on by one.
//
//   frames per eighth = 4096 / 197 = 20.792
//   frame rate        = 25.175 MHz / (800 * 525) = 59.940 Hz
//   one eighth        = 346.9 ms  ->  86.49 BPM, loop of 32 eighths = 11.10 s
//   (the original song loop: 11.09 s, 86.56 BPM)
//
// The top 4 bits of `acc` split the eighth into 16 phases (sixteenths of an
// eighth). They are the time resolution of the judge.

`default_nettype none

module tempo (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        step,     // one video frame has passed
    input  wire        restart,  // new game: jump to the start of eighth 0
    output reg  [11:0] acc,      // position inside the eighth
    output reg  [ 4:0] pos,      // eighth number 0..31 inside the loop
    output reg         wrap      // 1 when the last step started a new eighth
);

  localparam [11:0] INC = 12'd197;

  wire [12:0] sum = {1'b0, acc} + {1'b0, INC};

  always @(posedge clk) begin
    if (!rst_n) begin
      acc  <= 12'd0;
      pos  <= 5'd0;
      wrap <= 1'b0;
    end else if (restart) begin
      acc  <= 12'd0;
      pos  <= 5'd0;
      wrap <= 1'b1;  // eighth 0 begins now
    end else if (step) begin
      acc  <= sum[11:0];
      pos  <= pos + {4'd0, sum[12]};
      wrap <= sum[12];
    end
  end

endmodule
