// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// dance: which dance frame (0..31) the dancers show, and the miss screen.
//
// Dance frame k is the pose that belongs to eighth k of the music. The idea
// of the game: the dancers only move while you keep hitting notes.
//
// * Hitting a note that starts at s with length L lets the dancers follow
//   the music for eighths s .. s+L-1 (they are "following" until the music
//   reaches play_end = s+L). A late hit jumps to the current eighth at once.
// * When the music reaches play_end without a new hit, the dancers freeze.
// * A miss switches on the miss screen (`err`) until the next hit. That hit
//   jumps straight to the current music position, so the dancers skip the
//   steps they missed.
// * Before the first START (attract mode) the dancers simply follow the music.
//
// This is the `playStart / playEnd` logic of chip.js. playStart is not
// needed: after a hit the music can only be at or past the note start at
// the next new eighth. The `follow` flag replaces "music < playEnd", which
// would otherwise wrap around after 32 eighths.

`default_nettype none

module dance (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       playing,     // 0 = attract mode before the first START
    input  wire       restart,     // new game: count-in bar plays freely
    input  wire       new_eighth,  // game step in which a new eighth began
    input  wire [4:0] pos,
    input  wire       hit,
    input  wire       late,        // the hit came at or after the note start
    input  wire       miss,
    input  wire [4:0] note_start,
    input  wire [1:0] note_len,
    output reg  [4:0] frame,
    output reg        err,         // 1 = show the miss screen
    output reg        follow       // 1 = frames still follow the music
);

  localparam [4:0] COUNT_IN = 5'd8;

  reg [4:0] play_end;

  always @(posedge clk) begin
    if (!rst_n || restart) begin
      frame    <= 5'd0;
      err      <= 1'b0;
      follow   <= 1'b1;
      play_end <= COUNT_IN;
    end else if (hit) begin
      err      <= 1'b0;
      follow   <= 1'b1;
      play_end <= note_start + (5'd1 << note_len);
      if (late) frame <= pos;
    end else begin
      if (miss) err <= 1'b1;
      if (new_eighth) begin
        if (!playing) frame <= pos;
        else if (follow) begin
          if (pos == play_end) follow <= 1'b0;
          else frame <= pos;
        end
      end
    end
  end

endmodule
