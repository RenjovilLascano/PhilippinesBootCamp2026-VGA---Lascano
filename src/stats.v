// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// stats: score, combo and best combo, kept as decimal digits.
//
// Every counter is stored as BCD: 4 bits per decimal digit. The screen can
// then draw each digit directly, with no binary-to-decimal converter.
//
//   score  4 digits: a hit adds the note's value, 1, 2, 4 or 8 (wraps after 9999)
//   combo  2 digits: hits in a row, back to 0 on a miss (stops at 99)
//   best   2 digits: the highest combo of this game

`default_nettype none

module stats (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,     // new game
    input  wire        hit,
    input  wire        miss,
    input  wire [ 1:0] note_len,  // length code of the note that was hit
    output reg  [15:0] score,
    output reg  [ 7:0] combo,
    output reg  [ 7:0] best
);

  // Add 0..9 to one BCD digit: returns {carry, digit}.
  function [4:0] bcd_add(input [3:0] digit, input [3:0] value);
    reg [4:0] sum;
    begin
      sum     = {1'b0, digit} + {1'b0, value};
      bcd_add = (sum > 5'd9) ? {1'b1, sum[3:0] - 4'd10} : sum;
    end
  endfunction

  // Two-digit BCD counter +1 that stops at 99.
  function [7:0] inc99(input [7:0] v);
    begin
      if (v == 8'h99) inc99 = v;
      else if (v[3:0] == 4'd9) inc99 = {v[7:4] + 4'd1, 4'd0};
      else inc99 = {v[7:4], v[3:0] + 4'd1};
    end
  endfunction

  wire [4:0] d0 = bcd_add(score[3:0], 4'd1 << note_len);
  wire [4:0] d1 = bcd_add(score[7:4], {3'd0, d0[4]});
  wire [4:0] d2 = bcd_add(score[11:8], {3'd0, d1[4]});
  wire [4:0] d3 = bcd_add(score[15:12], {3'd0, d2[4]});  // carry out dropped: wraps at 9999
  wire _unused = d3[4];

  wire [7:0] combo_next = inc99(combo);

  always @(posedge clk) begin
    if (!rst_n || clear) begin
      score  <= 16'h0000;
      combo  <= 8'h00;
      best   <= 8'h00;
    end else if (hit) begin
      score <= {d3[3:0], d2[3:0], d1[3:0], d0[3:0]};
      combo <= combo_next;
      if (combo_next > best) best <= combo_next;  // BCD compares like binary
    end else if (miss) begin
      combo <= 8'h00;
    end
  end

endmodule
