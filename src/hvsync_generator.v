// SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
// SPDX-License-Identifier: Apache-2.0
//
// hvsync_generator: VGA 640x480 @ 60 Hz timing (25.175 MHz pixel clock).
//
// Same ports and timing as the hvsync_generator used by the TT VGA
// Playground, written from scratch so this repository stays Apache-2.0.
//
//   one line  = 640 visible + 16 front porch + 96 sync + 48 back porch = 800 clocks
//   one frame = 480 visible + 10 front porch +  2 sync + 33 back porch = 525 lines
//
// hpos/vpos give the beam position. display_on is high inside the visible
// 640x480 area. Both sync pulses are active low.

`default_nettype none

module hvsync_generator (
    input  wire       clk,
    input  wire       reset,
    output reg        hsync,
    output reg        vsync,
    output wire       display_on,
    output reg  [9:0] hpos,
    output reg  [9:0] vpos
);

  localparam H_DISPLAY = 640, H_SYNC_START = 656, H_SYNC_END = 751, H_MAX = 799;
  localparam V_DISPLAY = 480, V_SYNC_START = 490, V_SYNC_END = 491, V_MAX = 524;

  wire hmaxxed = (hpos == H_MAX) || reset;
  wire vmaxxed = (vpos == V_MAX) || reset;

  always @(posedge clk) begin
    hsync <= ~(hpos >= H_SYNC_START && hpos <= H_SYNC_END);
    vsync <= ~(vpos >= V_SYNC_START && vpos <= V_SYNC_END);
    hpos  <= hmaxxed ? 10'd0 : hpos + 10'd1;
    if (hmaxxed) vpos <= vmaxxed ? 10'd0 : vpos + 10'd1;
  end

  assign display_on = (hpos < H_DISPLAY) && (vpos < V_DISPLAY);

endmodule
