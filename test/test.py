# SPDX-FileCopyrightText: © 2026 Renjovil Joseph Lascano
# SPDX-License-Identifier: Apache-2.0
#
# cocotb tests for the Dinorobong Tubo Dance chip.
#
# test_golden_vectors replays test/vectors.json (made by tools/gen_vectors.js
# from the golden model chip.js) and checks the chip's state after every
# game step. It uses the chip's test mode:
#   * hold ui[3:0] = 1111 while reset is released
#   * the game then steps once per scanline (every 800 clocks)
#   * uo_out shows debug byte number ui[7:4] (see the table in src/project.v)
#
# Timing: after reset is released the beam starts at hpos 0 of line 0.
# Clock edge n (counting from 1) sees hpos = (n - 1) mod 800 before it
# updates. Line k ends at edge 800 * (k + 1), where step k happens.

import json
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, Timer

LINE = 800              # clocks per scanline = clocks per game step in test mode
LINES_PER_FRAME = 525
READ_AT = 20            # read the state 20 clocks after a step
PRESS_AT, RELEASE_AT = 100, 300  # hold lane buttons from hpos 100 to 300

VECTORS = json.loads((Path(__file__).parent / "vectors.json").read_text())
GATE_LEVEL = os.environ.get("GATES") == "yes"
# Gate-level simulation is much slower: replay a shorter selection there.
GL_SCENARIOS = {"attract_then_perfect", "early_late_sweep", "restart"}

START = 0x08


class Bench:
    """Drives the chip and keeps count of clock edges since reset."""

    def __init__(self, dut):
        self.dut = dut
        self.edge = 0
        self.buttons = 0

    async def reset(self, test_mode):
        dut = self.dut
        dut.ena.value = 1
        dut.uio_in.value = 0
        dut.ui_in.value = 0x0F if test_mode else 0
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 10)
        await FallingEdge(dut.clk)
        dut.rst_n.value = 1
        dut.ui_in.value = 0
        self.edge = 0
        self.buttons = 0

    async def to_edge(self, n):
        """Wait until just after clock edge n."""
        assert n > self.edge, f"cannot go back in time ({n} <= {self.edge})"
        await ClockCycles(self.dut.clk, n - self.edge)
        self.edge = n

    def set_buttons(self, value):
        self.buttons = value
        self.dut.ui_in.value = value

    async def read(self, index):
        """Debug byte `index` (ui[7:4] selects it, buttons stay as they are)."""
        self.dut.ui_in.value = (index << 4) | self.buttons
        await Timer(1, unit="ns")
        value = int(self.dut.uo_out.value)
        self.dut.ui_in.value = self.buttons
        return value


async def replay(bench, scenario, log):
    events = {}
    for step, kind, arg in scenario["events"]:
        events.setdefault(step, []).append((kind, arg))
    expect = {row[0]: row[1:] for row in scenario["expect"]}

    acc, pos = 0, 0          # our own copy of src/tempo.v
    wanted = None
    for step in range(scenario["steps"]):
        line_start = LINE * step
        restarted = False
        for kind, arg in events.get(step, []):
            if kind == "start":
                # The seed is sampled 2 edges after the button changes, when
                # hpos = 2 * h9; see src/inputs.v and src/project.v.
                await bench.to_edge(line_start + 2 * arg - 1)
                bench.set_buttons(START)
                await bench.to_edge(line_start + 2 * arg + 8)
                bench.set_buttons(0)
                restarted = True
            else:
                mask = sum(1 << lane for lane in arg)
                await bench.to_edge(line_start + PRESS_AT)
                bench.set_buttons(mask)
                await bench.to_edge(line_start + RELEASE_AT)
                bench.set_buttons(0)

        if restarted:
            acc, pos = 0, 0
        else:
            acc += VECTORS["inc"]
            if acc >= 1 << 16:
                acc -= 1 << 16
                pos = (pos + 1) % 32

        await bench.to_edge(LINE * (step + 1) + READ_AT)
        wanted = expect.get(step, wanted)
        got = [await bench.read(i) for i in range(9)]
        got[0] &= ~0x20                       # `follow` is not in chip.js
        exp = list(wanted)
        exp[1] |= pos << 3
        exp[3] |= (acc >> 12) << 4
        if got != exp:
            names = ["err/play/frame", "pos/result", "note start/lane", "phase/len",
                     "score lo", "score hi", "combo", "best", "misses"]
            diff = ", ".join(f"{n}: got {g:02x} want {e:02x}"
                             for n, g, e in zip(names, got, exp) if g != e)
            raise AssertionError(f"{scenario['name']} step {step}: {diff}")
    log.info(f"{scenario['name']}: {scenario['steps']} steps match chip.js")


@cocotb.test()
async def test_vga_timing(dut):
    """Normal mode: 96-clock hsync every 800 clocks, 2-line vsync every 525 lines."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    bench = Bench(dut)
    await bench.reset(test_mode=False)

    def hsync():
        return (int(dut.uo_out.value) >> 7) & 1

    def vsync():
        return (int(dut.uo_out.value) >> 3) & 1

    # hsync, sampled every clock over two lines (low while hpos is 656..751)
    low = []
    for edge in range(1, 2 * LINE + 1):
        await bench.to_edge(edge)
        await ReadOnly()  # see the values after this edge
        if not hsync():
            low.append(edge)
    assert low == [e for line in (0, 1) for e in range(LINE * line + 657, LINE * line + 753)], \
        "hsync must be low for 96 clocks, once per 800-clock line"

    # vsync, sampled in the middle of the lines around the pulse, two frames
    for frame in (0, 1):
        for line, level in ((489, 1), (490, 0), (491, 0), (492, 1)):
            await bench.to_edge(LINE * (LINES_PER_FRAME * frame + line) + 400)
            await ReadOnly()
            assert vsync() == level, f"vsync on line {line} should be {level}"
    dut._log.info("hsync 96/800 clocks, vsync 2/525 lines")


@cocotb.test()
async def test_golden_vectors(dut):
    """Replay every golden scenario and compare the state after each step."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())
    bench = Bench(dut)
    for scenario in VECTORS["scenarios"]:
        if GATE_LEVEL and scenario["name"] not in GL_SCENARIOS:
            continue
        await bench.reset(test_mode=True)
        await replay(bench, scenario, dut._log)
