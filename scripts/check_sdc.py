#!/usr/bin/env python3
"""check_sdc.py READBACK.sdc PERIOD_NS --netlist NETLIST.v

Checks the constraints OpenSTA actually loaded (its write_sdc readback), not the SDC source, against an
independent copy of the numbers in spec 6.3 / D-011:
  - one clock, named clk, on port clk, period == PERIOD_NS (the Makefile's single source)
  - every non-clock input port: set_input_delay = 0.2 * period, and the driving cell buf_2 pin X
  - every output port: set_output_delay = 0.2 * period, and set_load 0.01 (pF)
  - nothing else: a missing, duplicated or extra constraint, or a constraint on the clock port, is a problem
The port list comes from the netlist, not from the SDC, so a port the SDC forgot is found.
Exit 0 ok, 1 problems, 2 unreadable input.
"""
import argparse
import re
import sys

IO_FRACTION = 0.2
DRIVING_CELL = "sky130_fd_sc_hd__buf_2"
DRIVING_PIN = "X"
LOAD_PF = 0.01
CLOCK_PORT = "clk"
TOL = 6e-5  # write_sdc prints four decimals


def die(msg):
    print(f"check_sdc: {msg}")
    sys.exit(2)


def read(path):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError as exc:
        die(f"cannot read {path}: {exc}")


def netlist_ports(path):
    ins, outs = [], []
    for kind, rng, name in re.findall(r"^\s*(input|output)\s*(\[\d+:\d+\])?\s*(\w+)\s*;", read(path), re.M):
        names = [name]
        if rng:
            hi, lo = map(int, re.findall(r"\d+", rng))
            names = [f"{name}[{i}]" for i in range(max(hi, lo), min(hi, lo) - 1, -1)]
        (ins if kind == "input" else outs).extend(names)
    if CLOCK_PORT not in ins:
        die(f"netlist {path} has no input port '{CLOCK_PORT}'")
    return [p for p in ins if p != CLOCK_PORT], outs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("readback")
    ap.add_argument("period", type=float)
    ap.add_argument("--netlist", required=True)
    args = ap.parse_args()

    text = read(args.readback)
    data_in, outs = netlist_ports(args.netlist)
    want_delay = IO_FRACTION * args.period
    problems = []

    clocks, in_delay, out_delay, drive, load, other = [], {}, {}, {}, {}, []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("current_design"):
            continue
        m = re.match(r"^create_clock -name (\S+) -period ([0-9.]+) \[get_ports \{(\S+)\}\]$", line)
        if m:
            clocks.append((m.group(1), float(m.group(2)), m.group(3)))
            continue
        m = re.match(r"^set_(input|output)_delay ([0-9.]+) -clock \[get_clocks \{(\S+)\}\] -add_delay \[get_ports \{(.+)\}\]$", line)
        if m:
            kind, val, clk, port = m.groups()
            (in_delay if kind == "input" else out_delay).setdefault(port, []).append((float(val), clk))
            continue
        m = re.match(r"^set_driving_cell -lib_cell (\S+) -pin \{(\S+)\} .*\[get_ports \{(.+)\}\]$", line)
        if m:
            drive.setdefault(m.group(3), []).append((m.group(1), m.group(2)))
            continue
        m = re.match(r"^set_load -pin_load ([0-9.]+) \[get_ports \{(.+)\}\]$", line)
        if m:
            load.setdefault(m.group(2), []).append(float(m.group(1)))
            continue
        other.append(line)

    # clock
    if len(clocks) != 1:
        problems.append(f"expected exactly one create_clock, found {len(clocks)}")
    else:
        name, period, port = clocks[0]
        if name != "clk" or port != CLOCK_PORT:
            problems.append(f"clock is '{name}' on port '{port}', expected 'clk' on '{CLOCK_PORT}'")
        if abs(period - args.period) > TOL:
            problems.append(f"clock period {period} != expected {args.period} (CLK_PERIOD_NS)")
    for kind, table in (("set_input_delay", in_delay), ("set_output_delay", out_delay),
                        ("set_driving_cell", drive), ("set_load", load)):
        if CLOCK_PORT in table:
            problems.append(f"{kind} on the clock port {CLOCK_PORT}")

    def one(table, port, kind):
        vals = table.get(port, [])
        if not vals:
            problems.append(f"{kind} missing for {port}")
        elif len(vals) > 1:
            problems.append(f"{kind} on {port} appears {len(vals)} times")
        else:
            return vals[0]
        return None

    for port in data_in:
        v = one(in_delay, port, "set_input_delay")
        if v and (abs(v[0] - want_delay) > TOL or v[1] != "clk"):
            problems.append(f"set_input_delay on {port}: {v[0]} -clock {v[1]}, expected {want_delay:.4f} -clock clk")
        d = one(drive, port, "set_driving_cell")
        if d and d != (DRIVING_CELL, DRIVING_PIN):
            problems.append(f"set_driving_cell on {port}: {d[0]} pin {d[1]}, expected {DRIVING_CELL} pin {DRIVING_PIN}")
    for port in outs:
        v = one(out_delay, port, "set_output_delay")
        if v and (abs(v[0] - want_delay) > TOL or v[1] != "clk"):
            problems.append(f"set_output_delay on {port}: {v[0]} -clock {v[1]}, expected {want_delay:.4f} -clock clk")
        ld = one(load, port, "set_load")
        if ld is not None and abs(ld - LOAD_PF) > TOL:
            problems.append(f"set_load on {port}: {ld}, expected {LOAD_PF:.4f}")
    known = set(data_in) | set(outs) | {CLOCK_PORT}
    for table, kind in ((in_delay, "set_input_delay"), (out_delay, "set_output_delay"), (drive, "set_driving_cell"), (load, "set_load")):
        for port in table:
            if port not in known:
                problems.append(f"{kind} on {port}, which is not a port of the netlist")
    for line in other:
        problems.append(f"unexpected constraint: {line[:100]}")

    if problems:
        for p in problems:
            print("SDC PROBLEM: " + p)
        print(f"check_sdc: FAIL ({len(problems)} problem(s))")
        sys.exit(1)
    print(f"check_sdc: ok (period {args.period} ns; {len(data_in)} inputs, {len(outs)} outputs; "
          f"delays {want_delay:.4f} ns, {DRIVING_CELL}, {LOAD_PF} pF)")


if __name__ == "__main__":
    main()
