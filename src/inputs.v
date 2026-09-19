// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// inputs: makes the push buttons safe to use inside the chip.
//
// A button can change at any moment, not in step with our clock. Each button
// goes through two flip-flops (a "synchroniser") so the rest of the design
// only sees clean values. We then compare with the value one clock earlier:
// "now pressed, before not pressed" is a rising edge, reported as a pulse
// that lasts exactly one clock. The mute switch is only synchronised.
//
// Button bounce needs no filter here: after a judged press the next note is
// at least one eighth (about 346 ms) away, far longer than any bounce.

`default_nettype none

module inputs (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] btn,      // {START, RIGHT, MIDDLE, LEFT}, 1 = pressed
    input  wire       mute_in,  // 1 = silence
    output wire [3:0] rise,     // one-clock pulse when a button goes down
    output wire       mute
);

  reg [3:0] sync1, sync2, prev;
  reg [1:0] mute_sync;

  always @(posedge clk) begin
    if (!rst_n) begin
      sync1     <= 4'b0;
      sync2     <= 4'b0;
      prev      <= 4'b0;
      mute_sync <= 2'b0;
    end else begin
      sync1     <= btn;
      sync2     <= sync1;
      prev      <= sync2;
      mute_sync <= {mute_sync[0], mute_in};
    end
  end

  assign rise = sync2 & ~prev;
  assign mute = mute_sync[1];

endmodule
