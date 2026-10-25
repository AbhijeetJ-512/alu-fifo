#!/usr/bin/env python3
"""alu_fifo diagrams (dgm.py: one spec -> .drawio + PNG + SVG). Run: python3 docs/portfolio/diagrams/make_diagrams.py"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)   # dgm.py sits next to this file
from dgm import Diagram  # noqa: E402


def architecture():
    d = Diagram("alu_fifo - 16-bit ALU between two FIFOs (architecture)", 1250, 640)
    d.legend = ("data", "ctrl")
    d.legend_pos = (1040, 12)
    d.group("g", 190, 80, 880, 330, "alu_fifo_top  (W = 16, DEPTH = 8, single clock, synchronous active-low reset)", label_pos="top")
    d.box("src", 20, 200, 150, 90, "Producer", "io", sub="in_valid, in_ready\nin_op[2:0], in_a, in_b", size=12)
    d.box("fin", 215, 175, 190, 130, "u_in_fifo", "mem", sub="sync_fifo\nWIDTH = 3 + 2W = 35\nDEPTH = 8, first-word-fall-through\nwrap-bit pointers", size=12)
    d.box("alu", 470, 170, 230, 140, "u_alu  (combinational)", "accent", sub="ADD  SUB  AND  OR\nXOR  SLL  SRL  SLTU\ny, c, v from op / a / b", size=12)
    d.box("flg", 470, 330, 230, 55, "flags {N, Z, C, V}", "block", sub="N = y[W-1], Z = (y == 0), C, V from ALU", size=11)
    d.box("fout", 765, 175, 190, 130, "u_out_fifo", "mem", sub="sync_fifo\nWIDTH = 4 + W = 20\nDEPTH = 8", size=12)
    d.box("snk", 1095, 200, 140, 90, "Consumer", "io", sub="out_valid, out_ready\nout_y, out_flags", size=12)
    d.box("xf", 470, 100, 230, 50, "xfer = !in_empty && !out_full", "ctrl", sub="one transfer per cycle", size=11)
    d.arrow("a1", "src", "fin", label="push (in_valid && in_ready)\n{op, a, b}", lpos=(193, 150))
    d.arrow("a2", "fin", "alu", label="dout: op, a, b", lpos=(437, 235))
    d.arrow("a3", "alu", "fout", sside="r", dside="l", sf=0.35, df=0.35, label="y", lpos=(733, 205))
    d.arrow("a4", "alu", "flg", sside="b", dside="t", label="c, v, y", lpos=(520, 322))
    d.arrow("a5", "flg", "fout", sside="r", dside="b", sf=0.5, df=0.3, via=[(740, 357), (822, 357)], label="flags", lpos=(780, 366))
    d.arrow("a6", "fout", "snk", label="pop (out_valid && out_ready)\n{flags, y}", lpos=(1010, 150))
    d.arrow("c1", "xf", "fin", kind="ctrl", sside="l", dside="t", sf=0.5, df=0.5, via=[(310, 125)], label="in_pop", lpos=(390, 117))
    d.arrow("c2", "xf", "fout", kind="ctrl", sside="r", dside="t", sf=0.5, df=0.5, via=[(860, 125)], label="out_push", lpos=(790, 117))
    d.arrow("c3", "fin", "src", kind="ctrl", sside="b", dside="b", sf=0.3, df=0.5, via=[(272, 450), (95, 450)], label="in_ready = !in_full", lpos=(185, 441))
    d.arrow("c4", "fout", "snk", kind="ctrl", sside="b", dside="b", sf=0.7, df=0.5, via=[(898, 480), (1165, 480)], label="out_valid = !out_empty", lpos=(1030, 471))
    d.group("gv", 190, 505, 880, 110, "Verification attached with bind (never read by synthesis)", label_pos="top")
    d.box("ck1", 215, 540, 280, 55, "sync_fifo_checker", "io", sub="own occupancy model, FIFO rules", size=11)
    d.box("ck2", 540, 540, 280, 55, "alu_fifo_checker", "io", sub="handshake rules, flags, latency, bookkeeping", size=11)
    d.box("tb", 865, 540, 190, 55, "tb_alu_fifo", "io", sub="scoreboard + random", size=11)
    return d


def flowchart():
    d = Diagram("alu_fifo - operation flowchart (one clock cycle)", 1150, 900)
    d.legend = ("flow",)
    d.legend_pos = (950, 12)
    C, W = 380, 300
    cx = C + W / 2
    d.box("rst", C, 55, W, 55, "Reset: rst_n low", "term", sub="pointers cleared: both FIFOs empty", size=12)
    d.box("dpush", C, 140, W, 80, "in_valid && !in_full ?", "dec", sub="(in_ready = !in_full)", size=12)
    d.box("push", 760, 155, 330, 52, "Push {op, a, b} into u_in_fifo", "proc", sub="write pointer advances", size=12)
    d.box("dx", C, 255, W, 80, "xfer ?", "dec", sub="!in_empty && !out_full", size=12)
    d.box("hold", 60, 270, 240, 50, "Hold: nothing moves", "proc", sub="in FIFO empty or out FIFO full", size=11)
    d.box("alu", C, 370, W, 70, "ALU computes y, c, v from the head", "proc", sub="op selects ADD..SLTU; flags N,Z,C,V derived", size=12)
    d.box("mv", C, 470, W, 62, "Same cycle: pop u_in_fifo, push {flags, y}", "proc", sub="u_out_fifo", size=12)
    d.box("dout", C, 565, W, 80, "out_valid && out_ready ?", "dec", sub="(out_valid = !out_empty)", size=12)
    d.box("pop", 760, 580, 330, 52, "Pop {flags, y}: consumer takes the result", "proc", sub="read pointer advances", size=12)
    d.box("end", C, 690, W, 52, "Next cycle", "term", size=12)
    for a, b, lab in [("rst", "dpush", ""), ("dpush", "dx", "no / after push"), ("dx", "alu", "yes"), ("alu", "mv", ""), ("mv", "dout", ""), ("dout", "end", "no: result stays valid and stable")]:
        d.arrow("m_" + a, a, b, kind="flow", sside="b", dside="t", label=lab, lpos=(cx + 55, (d.node(a).y + d.node(a).h + d.node(b).y) / 2) if lab else None)
    d.arrow("p1", "dpush", "push", kind="flow", sside="r", dside="l", label="yes", lpos=(715, 168))
    d.arrow("p1b", "push", "dx", kind="flow", sside="b", dside="r", sf=0.5, df=0.5, via=[(925, 295)])
    d.arrow("p2", "dx", "hold", kind="flow", sside="l", dside="r", label="no", lpos=(340, 283))
    d.arrow("p2b", "hold", "dout", kind="flow", sside="b", dside="l", sf=0.5, df=0.5, via=[(180, 605)])
    d.arrow("p3", "dout", "pop", kind="flow", sside="r", dside="l", label="yes", lpos=(715, 592))
    d.arrow("p3b", "pop", "end", kind="flow", sside="b", dside="r", sf=0.5, df=0.5, via=[(925, 716)])
    d.text("n", 40, 790, "The two FIFO decisions (push and xfer) and the pop decision are all evaluated in the same cycle; an input push and a transfer can both happen.\n"
                         "Back-pressure: a full output FIFO stops xfer, the input FIFO then fills, and in_ready falls - nothing is dropped or reordered.\n"
                         "Latency: a command pushed in cycle t is at the head of u_in_fifo in t+1 (first-word fall-through), and its result is visible in u_out_fifo in t+2.", 11, italic=True)
    return d


def impl_flow():
    d = Diagram("alu_fifo - verification and implementation flow", 1250, 470)
    d.legend = ()
    xs = [20, 215, 410, 605, 800, 995]
    names = [("RTL + checkers", "rtl/*.sv\nverif/*_checker.sv", "block"), ("Verilator", "sim + assertions\nline/toggle + cover bins", "accent"), ("Mutation run", "22 injected bugs,\nwith/without assertions", "ctrl"),
             ("Yosys", "synth to Sky130 HD\nstructural checks", "block"), ("OpenSTA", "SDC read-back checked\nsetup/hold report", "block"), ("OpenROAD", "floorplan, place, CTS,\nrepair, route, extract", "accent")]
    for i, (n, s, k) in enumerate(names):
        d.box("s%d" % i, xs[i], 120, 175, 100, n, k, sub=s, size=12)
        if i:
            d.arrow("f%d" % i, "s%d" % (i - 1), "s%d" % i, kind="data")
    d.box("r1", 215, 290, 380, 90, "docs/results/final/*  (snapshots)", "mem", sub="summary, coverage, mutants, SDC read-back, route DRC counts", size=12)
    d.box("r2", 655, 290, 515, 90, "README results block", "mem", sub="spliced verbatim from the snapshots by scripts/readme_results.py\nscripts/acceptance.sh fails if they ever differ", size=12)
    d.arrow("g1", "s1", "r1", kind="ctrl", sside="b", dside="t", sf=0.5, df=0.3)
    d.arrow("g2", "s5", "r2", kind="ctrl", sside="b", dside="t", sf=0.5, df=0.8)
    d.arrow("g3", "r1", "r2", kind="ctrl", sside="r", dside="l")
    d.text("n", 20, 410, "Self-tests prove most gates can fail on a bad input (rules, coverage, synthesis, SDC, summary, PnR checks). Verilator's own -Wall lint has no self-test.", 11, italic=True)
    return d


if __name__ == "__main__":
    for n, f in (("alu_fifo_architecture", architecture), ("alu_fifo_flowchart", flowchart), ("alu_fifo_flow", impl_flow)):
        print(n, "overflow:", f().export_all(HERE, n))
