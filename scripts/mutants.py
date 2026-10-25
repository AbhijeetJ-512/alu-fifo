#!/usr/bin/env python3
"""mutants.py - mutation run over the RTL (spec 5.4).

  mutants.py --selftest
  mutants.py --vflags "<verilator flags>" --rtl <rtl files> --verif <verif files> --main-cpp <cpp>
             --sim-args "<run args>" [--only M01,M02] [--jobs N] [--report FILE]

Each mutant is a verif/mutants/<id>.mut file: a deliberate bug, applied to a copy of rtl/, built
with the checkers, run through the full testbench. The fired set is read from the output: the
label of every assertion that fired, plus "scoreboard" for the testbench's own checks. A mutant
is killed when its fired set is non-empty (or the run aborts/times out). Pass = every mutant is
killed AND every intended check fired; and, over the whole set, every assertion defined in verif/*_checker.sv is bound to at
least one mutant (listed as its intended check) and fired in some run: an assertion no bug was ever aimed at is unproven. Then the intended assertions are removed (a compile-time
define, see verif/*_checker.sv) and the mutant is run again: caught by some other check, or it
survives. That second column shows which checks are the only guard for a bug. It is reported,
not a failure.

The testbench's $fatal is ignored under +verilator+error+limit, so the verdict comes from the
output text, never from the exit status alone.

.mut format (one `key: value` per line; '#' comments; \n in a replace becomes a newline):
  id: M01
  desc: what the bug is
  intended: a_full_def            # comma-separated labels, or scoreboard
  edit: rtl/sync_fifo.sv          # one or more edits; find must occur exactly once in the file
                                  # (a file under verif/ is edited in this mutant's own copy: testbench/checker mutants)
    find: <exact text>
    replace: <text>
"""
import argparse
import concurrent.futures
import glob
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class MutantError(Exception):
    pass


@dataclass
class Mutant:
    id: str
    desc: str
    intended: list
    edits: list = field(default_factory=list)  # (file, find, replace)


def parse_mut(path):
    keys, edits, cur = {}, [], None
    with open(path) as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            key, sep, val = line.strip().partition(":")
            if not sep:
                raise MutantError(f"{path}:{n}: expected 'key: value'")
            val = val[1:] if val.startswith(" ") else val
            if key == "edit":
                cur = {"file": val}
                edits.append(cur)
            elif key in ("find", "replace"):
                if cur is None:
                    raise MutantError(f"{path}:{n}: '{key}' before any 'edit'")
                cur[key] = val.replace("\\n", "\n")
            elif key in ("id", "desc", "intended"):
                keys[key] = val
            else:
                raise MutantError(f"{path}:{n}: unknown key '{key}'")
    for k in ("id", "desc", "intended"):
        if k not in keys:
            raise MutantError(f"{path}: missing '{k}'")
    if not edits:
        raise MutantError(f"{path}: no edit")
    for e in edits:
        if "find" not in e or "replace" not in e:
            raise MutantError(f"{path}: edit of {e['file']} needs both find and replace")
    intended = [x.strip() for x in keys["intended"].split("#")[0].split(",") if x.strip()]
    return Mutant(keys["id"], keys["desc"], intended, [(e["file"], e["find"], e["replace"]) for e in edits])


def apply_edits(m, src_root, dest_root):
    """Copy src_root/rtl/*.sv to dest_root/rtl and apply the mutant's edits (each find exactly once)."""
    shutil.rmtree(dest_root, ignore_errors=True)
    os.makedirs(os.path.join(dest_root, "rtl"))
    for f in glob.glob(os.path.join(src_root, "rtl", "*.sv")):
        shutil.copy(f, os.path.join(dest_root, "rtl"))
    for file, find, rep in m.edits:
        path = os.path.join(dest_root, file)
        if file.startswith("verif/") and not os.path.exists(path):
            origin = os.path.join(src_root, file)
            if not os.path.exists(origin):
                raise MutantError(f"{m.id}: {file} does not exist")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            shutil.copy(origin, path)  # a testbench/checker mutant edits its own copy, never the original
        if not os.path.exists(path):
            raise MutantError(f"{m.id}: {file} does not exist")
        with open(path) as fh:
            text = fh.read()
        n = text.count(find)
        if n != 1:
            raise MutantError(f"{m.id}: find string occurs {n} times in {file}, must be exactly once: {find!r}")
        with open(path, "w") as fh:
            fh.write(text.replace(find, rep))


LABEL = re.compile(r"Assertion failed in \S*?\.(a_\w+):")


ASSERT_DEF = re.compile(r"^[ \t]*(a_\w+)[ \t]*:[ \t]*assert[ \t]+property\b", re.M)


def assertion_labels(text):
    """Labels of the named assertions defined in a checker source (covers and comments are not assertions)."""
    return set(ASSERT_DEF.findall(text))


def unbound_assertions(labels, mutants):
    """Assertions no mutant lists as its intended check: nothing in the repo shows they can fail."""
    return set(labels) - {lab for m in mutants for lab in m.intended}


def never_fired(labels, fired_union):
    """Assertions that fired in no mutant run."""
    return set(labels) - set(fired_union)


def fired_set(output):
    fired = set(LABEL.findall(output))
    if "SCOREBOARD MISMATCH" in output or re.search(r"^TB FAIL", output, re.M):
        fired.add("scoreboard")
    return fired


def selftest():
    import os
    import tempfile

    problems = []

    def check(name, cond):
        print(("ok   " if cond else "FAIL ") + name)
        if not cond:
            problems.append(name)

    two_asserts_and_scoreboard = (
        "[10] %Error: x.sv:2: Assertion failed in TOP.tb.dut.u_chk.a_one: a_one\n"
        "[20] %Error: y.sv:3: Assertion failed in TOP.tb.dut.u_in_fifo.u_chk.a_two: a_two\n"
        "SCOREBOARD MISMATCH output=3 got=1 want=2\n"
    )
    check("fired_set: two assertions and the scoreboard",
          fired_set(two_asserts_and_scoreboard) == {"a_one", "a_two", "scoreboard"})
    check("fired_set: a clean run fires nothing", fired_set("TB PASS seed=1 cmds=5\n") == set())
    check("fired_set: a TB FAIL line counts as the scoreboard",
          fired_set("TB FAIL fill: wrong number accepted\n") == {"scoreboard"})
    check("fired_set: the TB's own fail task is not an assertion label",
          fired_set("[5] %Fatal: tb.sv:60: Assertion failed in TOP.tb_alu_fifo.fail: TB FAIL x\n") == set())

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "src")
        os.makedirs(os.path.join(src, "rtl"))
        with open(os.path.join(src, "rtl", "foo.sv"), "w") as fh:
            fh.write("a b a\nline two\n")
        mut_text = (
            "id: M98\ndesc: two edits\nintended: a_x, scoreboard\n"
            "edit: rtl/foo.sv\n  find: b\n  replace: B\n"
            "edit: rtl/foo.sv\n  find: line two\n  replace: line\\nthree\n"
        )
        path = os.path.join(tmp, "M98.mut")
        with open(path, "w") as fh:
            fh.write(mut_text)
        m = parse_mut(path)
        check("parse_mut: id, intended list and two edits",
              m.id == "M98" and m.intended == ["a_x", "scoreboard"] and len(m.edits) == 2)
        dest = os.path.join(tmp, "dest")
        apply_edits(m, src, dest)
        with open(os.path.join(dest, "rtl", "foo.sv")) as fh:
            check("apply_edits: both edits applied, \\n becomes a newline", fh.read() == "a B a\nline\nthree\n")

        for label, find in (("matches twice", "a"), ("matches nowhere", "zzz")):
            bad = os.path.join(tmp, "M99.mut")
            with open(bad, "w") as fh:
                fh.write(f"id: M99\ndesc: bad\nintended: scoreboard\nedit: rtl/foo.sv\n  find: {find}\n  replace: q\n")
            try:
                apply_edits(parse_mut(bad), src, os.path.join(tmp, "dest2"))
                check(f"apply_edits: a find that {label} must abort", False)
            except MutantError as exc:
                check(f"apply_edits: a find that {label} aborts naming the mutant", "M99" in str(exc))

    sample = (
        "  a_one: assert property (@(posedge clk) x) else $error(\"a_one\");\n"
        "  a_two: assert property (@(posedge clk) y) else $error(\"a_two\");\n"
        "  c_bin: cover property (@(posedge clk) z);\n"
        "// a_commented: assert property (@(posedge clk) w)\n"
        "  a_three : assert property (@(posedge clk) v) else $error(\"a_three\");\n"
    )
    check("assertion_labels: assertions only, not covers or comments",
          assertion_labels(sample) == {"a_one", "a_two", "a_three"})
    m1 = Mutant("MA", "d", ["a_one", "scoreboard"], [])
    m2 = Mutant("MB", "d", ["a_two"], [])
    check("unbound_assertions: labels no mutant lists as intended",
          unbound_assertions({"a_one", "a_two", "a_three"}, [m1, m2]) == {"a_three"})
    check("never_fired: labels that fired in no mutant run",
          never_fired({"a_one", "a_two", "a_three"}, {"a_one", "scoreboard"}) == {"a_two", "a_three"})

    with tempfile.TemporaryDirectory() as tmp2:
        src = os.path.join(tmp2, "src")
        os.makedirs(os.path.join(src, "rtl"))
        os.makedirs(os.path.join(src, "verif"))
        with open(os.path.join(src, "rtl", "r.sv"), "w") as fh:
            fh.write("r\n")
        with open(os.path.join(src, "verif", "tb.sv"), "w") as fh:
            fh.write("// stay unchanged\n")
        m = Mutant("M97", "tb edit", ["a_in_hold"], [("verif/tb.sv", "// stay unchanged", "in_a = ~in_a;")])
        dest = os.path.join(tmp2, "dest")
        apply_edits(m, src, dest)
        with open(os.path.join(dest, "verif", "tb.sv")) as fh:
            tb_changed = fh.read() == "in_a = ~in_a;\n"
        with open(os.path.join(src, "verif", "tb.sv")) as fh:
            src_untouched = fh.read() == "// stay unchanged\n"
        check("apply_edits: a verif/ file is edited in the copy only", tb_changed and src_untouched)

    if problems:
        print(f"mutants selftest: FAIL ({len(problems)})")
        sys.exit(1)
    print("mutants selftest: ok")


@dataclass
class Result:
    fired: set
    rc: int
    passed: bool
    note: str = ""      # build error / timeout text

    @property
    def killed(self):
        return bool(self.fired) or self.rc != 0 or bool(self.note)


def build_and_run(m, ctx, neutralise):
    work = os.path.join(ROOT, "build", "mut", m.id + ("-neut" if neutralise else ""))
    apply_edits(m, ROOT, work)
    defs = ["-DNEUTRALISE_" + lab.upper() for lab in neutralise]
    rtl = [os.path.join(work, r) for r in ctx.rtl]
    verif = [os.path.join(work, v) if os.path.exists(os.path.join(work, v)) else os.path.join(ROOT, v) for v in ctx.verif]
    cmd = ["verilator", *shlex.split(ctx.vflags), "--Mdir", os.path.join(work, "obj"), *defs, *rtl, *verif,
           os.path.abspath(ctx.main_cpp)]
    try:
        b = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return Result(set(), -1, False, "build timeout")
    if b.returncode != 0:
        return Result(set(), b.returncode, False, "BUILD ERROR: " + (b.stdout + b.stderr).strip()[-400:])
    run = [os.path.join(work, "obj", "Vtb_alu_fifo"), *shlex.split(ctx.sim_args), "+verilator+error+limit+1000"]
    try:
        r = subprocess.run(run, cwd=ROOT, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return Result({"timeout"}, -1, False, "run timeout")
    out = r.stdout + r.stderr
    fired = fired_set(out)
    return Result(fired, r.returncode, "TB PASS" in out and not fired)


def run_mutant(m, ctx):
    normal = build_and_run(m, ctx, [])
    asserts = [lab for lab in m.intended if lab.startswith("a_")]
    neut = build_and_run(m, ctx, asserts) if asserts and not normal.note else None
    return m, normal, neut


def fmt_set(s):
    return "{" + ", ".join(sorted(s)) + "}" if s else "{}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--vflags")
    ap.add_argument("--rtl", nargs="+")
    ap.add_argument("--verif", nargs="+")
    ap.add_argument("--main-cpp")
    ap.add_argument("--sim-args")
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--mutants-dir", default=os.path.join(ROOT, "verif", "mutants"))
    ap.add_argument("--report", default=os.path.join(ROOT, "build", "reports", "mutants.txt"))
    ctx = ap.parse_args()
    if ctx.selftest:
        selftest()
        return
    for need in ("vflags", "rtl", "verif", "main_cpp", "sim_args"):
        if getattr(ctx, need) is None:
            ap.error(f"--{need.replace('_', '-')} is required")

    try:
        mutants = [parse_mut(p) for p in sorted(glob.glob(os.path.join(ctx.mutants_dir, "M*.mut")))]
    except MutantError as exc:
        print(f"mutants: {exc}")
        sys.exit(2)
    if ctx.only:
        want = set(ctx.only.split(","))
        mutants = [m for m in mutants if m.id in want]
    if not mutants:
        print("mutants: no mutants selected")
        sys.exit(2)

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=ctx.jobs) as pool:
        futs = {pool.submit(run_mutant, m, ctx): m for m in mutants}
        for fut in concurrent.futures.as_completed(futs):
            try:
                m, normal, neut = fut.result()
            except MutantError as exc:
                print(f"mutants: {exc}")
                sys.exit(2)
            results.append((m, normal, neut))
            print(f"  {m.id}: killed={normal.killed} fired={fmt_set(normal.fired)}", flush=True)
    results.sort(key=lambda t: t[0].id)

    problems = []
    rows = []
    for m, normal, neut in results:
        intended_fired = all(lab in normal.fired for lab in m.intended)
        if normal.note:
            problems.append(f"{m.id}: {normal.note}")
        elif not normal.killed:
            problems.append(f"{m.id}: NOT KILLED (no check fired, run passed)")
        elif not intended_fired:
            missing = [lab for lab in m.intended if lab not in normal.fired]
            problems.append(f"{m.id}: intended check(s) {missing} did not fire (fired {fmt_set(normal.fired)})")
        if neut is None:
            neutral = "n/a (intended is the scoreboard)" if not normal.note else "n/a (build failed)"
        elif neut.note:
            neutral = neut.note
        elif neut.fired:
            neutral = "caught by " + fmt_set(neut.fired)
        else:
            neutral = "SURVIVES (the intended check was the only guard)"
        rows.append((m, normal, intended_fired, neutral))

    # whole-set gates (skipped when --only selects a subset)
    labels = set()
    for v in ctx.verif:
        if v.endswith("_checker.sv"):
            with open(os.path.join(ROOT, v)) as fh:
                labels |= assertion_labels(fh.read())
    fired_union = set().union(*[n.fired for _, n, _ in results])
    gate_lines = []
    if ctx.only:
        gate_lines.append("assertion gates skipped: --only selected a subset of the mutants")
    else:
        unb = unbound_assertions(labels, [m for m, _, _ in results])
        nf = never_fired(labels, fired_union)
        gate_lines.append(f"assertions defined in verif/*_checker.sv : {len(labels)}")
        gate_lines.append(f"assertions with no mutant bound to them  : {', '.join(sorted(unb)) or 'none'}")
        gate_lines.append(f"assertions that fired in no mutant run   : {', '.join(sorted(nf)) or 'none'}")
        if unb:
            problems.append(f"assertions no mutant is bound to (nothing shows they can fail): {sorted(unb)}")
        if nf:
            problems.append(f"assertions that fired in no mutant run: {sorted(nf)}")

    os.makedirs(os.path.dirname(ctx.report), exist_ok=True)
    with open(ctx.report, "w") as out:
        out.write("# Mutation run: each row is one deliberate RTL bug run through the full testbench.\n")
        out.write("# fired     = checks that fired (assertion labels; 'scoreboard' = the testbench's own checks)\n")
        out.write("# intended  = the check(s) the bug is bound to; 'ok' when all of them fired\n")
        out.write("# neutralised = same bug with the intended assertion(s) removed at compile time\n")
        out.write(f"# run args  : {ctx.sim_args}\n# flags     : {ctx.vflags}\n\n")
        for m, normal, intended_fired, neutral in rows:
            verdict = "KILLED" if normal.killed and not normal.note else ("BUILD ERROR" if normal.note else "SURVIVED")
            out.write(f"{m.id}  {verdict}  intended {'ok' if intended_fired else 'MISSING'}\n")
            out.write(f"    bug        : {m.desc}\n")
            out.write(f"    intended   : {', '.join(m.intended)}\n")
            out.write(f"    fired      : {fmt_set(normal.fired)}\n")
            out.write(f"    neutralised: {neutral}\n")
        killed = sum(1 for _, n, _, _ in rows if n.killed and not n.note)
        out.write(f"\nmutants: {len(rows)}, killed {killed}, intended check fired in "
                  f"{sum(1 for _, _, f, _ in rows if f)}\n")
        sole = [m.id for m, _, _, neutral in rows if neutral.startswith("SURVIVES")]
        out.write(f"only guard for their bug (survive with the intended check removed): {', '.join(sole) or 'none'}\n")
        for gl in gate_lines:
            out.write(gl + "\n")
        if problems:
            out.write("\nPROBLEMS\n" + "\n".join("  " + p for p in problems) + "\n")
    print(f"mutants: {len(rows)} run, {killed} killed, report {os.path.relpath(ctx.report, ROOT)}")
    if problems:
        for p in problems:
            print("  PROBLEM " + p)
        sys.exit(1)


if __name__ == "__main__":
    main()
