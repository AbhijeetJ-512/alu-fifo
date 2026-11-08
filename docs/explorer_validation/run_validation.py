#!/usr/bin/env python3
"""run_validation.py - check the explorer's cycle model against the real RTL.

    python3 docs/explorer_validation/run_validation.py        (from the repository root; needs Verilator)

For every scenario on the explorer page (plus a long random one), at FIFO depths 2, 4 and 8, this runs the same stimulus through
rtl/ in Verilator (docs/explorer_validation/tb_replay.sv, with the bound checkers on) and writes build/explorer_check.html. Open that
page in a browser: it runs the model that is embedded in docs/architecture_explorer.html and compares all 17 per-cycle values
(handshakes, data, flags, FIFO pointers, transfer, ALU result) with the RTL trace, and prints PASS or the first mismatch.
"""
import json, os, random, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "docs", "explorer_validation"))
PAGE = os.path.join(ROOT, "docs", "architecture_explorer.html")
BUILD = os.path.join(ROOT, "build", "explorer_check")
DEPTHS = (2, 4, 8)
NCYC = 130
NCYC_RAND = 330
NAMES = []


def page_parts():
    src = open(PAGE, encoding="utf-8").read()
    m = re.search(r"const DATA=\{.*?\};\nconst \{META[^\n]*\}=DATA;\n(.*?)</script>", src, re.S)
    if not m:
        sys.exit("cannot find the model in " + PAGE)
    sim = m.group(1)
    sc = re.search(r"const SCEN=(\[.*?\]);\n", sim, re.S)
    return sim, json.loads(sc.group(1))


def expand(p, n=512):
    return [(p["pre"][i] if i < len(p["pre"]) else p["loop"][(i - len(p["pre"])) % len(p["loop"])]) for i in range(n)]


def make_random():
    r = random.Random(20261108)
    edge = [0, 1, 2, 0x7FFF, 0x8000, 0xFFFF, 0x00FF, 0xFF00, 0x000F, 0x0010]
    pick = lambda: r.choice(edge) if r.random() < 0.5 else r.getrandbits(16)
    cmds = [[r.randrange(8), pick(), pick()] for _ in range(150)]
    def runs(p_hi):
        s = ""
        while len(s) < 512:
            s += ("1" if r.random() < p_hi else "0") * r.randint(1, 14)
        return s[:512]
    return dict(id="rand", name="random", desc="", cmds=cmds, src=dict(pre=runs(0.7), loop="1"), snk=dict(pre=runs(0.45), loop="1"))


def main():
    sim, scens = page_parts()
    scens.append(make_random())
    os.makedirs(BUILD, exist_ok=True)
    rtl = [os.path.join(ROOT, "rtl", f) for f in ("alu_pkg.sv", "alu.sv", "sync_fifo.sv", "alu_fifo_top.sv")]
    verif = [os.path.join(ROOT, "verif", f) for f in ("sync_fifo_checker.sv", "alu_fifo_checker.sv", "checker_binds.sv")]
    tb = os.path.join(ROOT, "docs", "explorer_validation", "tb_replay.sv")
    traces, asserts = {}, {}
    for d in DEPTHS:
        out = os.path.join(BUILD, "sim_d%d" % d)
        subprocess.check_call(["verilator", "--binary", "--timing", "--assert", "--x-initial", "unique", "-j", "4", "-GDEPTH=%d" % d, "--top-module", "tb_replay",
                               "-Wno-fatal", "-Wno-DECLFILENAME", "-Wno-UNUSEDSIGNAL", "-Wno-UNUSEDPARAM", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC", "--Mdir", out] + rtl + verif + [tb],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for s in scens:
            base = os.path.join(BUILD, "%s.d%d" % (s["id"], d))
            open(base + ".cmds", "w").write("".join("%09x\n" % ((c[0] << 32) | (c[1] << 16) | c[2]) for c in s["cmds"]))
            open(base + ".src", "w").write("\n".join(expand(s["src"])) + "\n")
            open(base + ".snk", "w").write("\n".join(expand(s["snk"])) + "\n")
            nc = NCYC_RAND if s["id"] == "rand" else NCYC
            p = subprocess.run([os.path.join(out, "Vtb_replay"), "+cmds=" + base + ".cmds", "+src=" + base + ".src", "+snk=" + base + ".snk", "+n=%d" % len(s["cmds"]),
                                "+ncyc=%d" % nc, "+log=" + base + ".log", "+verilator+rand+reset+2", "+verilator+seed+7"], capture_output=True, text=True)
            txt = p.stdout + p.stderr
            asserts["%s.%d" % (s["id"], d)] = len(re.findall(r"Assertion failed|%Error|\$error\b", txt))
            traces["%s.%d" % (s["id"], d)] = [l.split() for l in open(base + ".log").read().splitlines()]
    page = """<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Explorer model check</title></head><body style="font:14px ui-monospace,monospace;padding:16px">
<h1 style="font:600 18px sans-serif">Explorer model against the RTL</h1><pre id="out">running…</pre>
<script>%s
SCEN.push(%s);
const RTL=%s, ASSERTS=%s, DEPTHS=%s, NC=%d, NCR=%d;
const res=[]; let bad=0, cycles=0;
const F=['cycle','in_valid','in_ready','op','a','b','out_valid','out_ready','out_y','out_flags','in_wr','in_rd','out_wr','out_rd','xfer','alu_y','alu_flags'];
for(const sc of SCEN){ for(const d of DEPTHS){
  const key=sc.id+'.'+d, rtl=RTL[key]; const n=sc.id==='rand'?NCR:NC; const tr=SIM.trace(sc.id,d,n); let first=null, ok=true;
  if(rtl.length!==n){ ok=false; first='rtl trace has '+rtl.length+' lines, expected '+n; }
  else for(let i=0;i<n&&ok;i++){ const r=rtl[i].map((x,j)=>parseInt(x,j===0?10:16)); const m=tr[i];
    for(let j=0;j<17;j++){ if(r[j]!==m[j]){ ok=false; first='cycle '+(i+1)+' '+F[j]+': RTL '+r[j].toString(16)+' model '+m[j].toString(16); break; } } }
  cycles+=n; if(!ok) bad++;
  res.push((ok?'PASS ':'FAIL ')+key.padEnd(12)+' '+n+' cycles, 17 values each'+(first?'  <- '+first:'')+(ASSERTS[key]?'  [RTL log mentions an assertion: '+ASSERTS[key]+']':'')); } }
const out=(bad?'FAIL: '+bad+' of '+res.length+' runs differ':'PASS: '+res.length+' runs ('+cycles+' cycles x 17 values) identical to the RTL')+'\\n\\n'+res.join('\\n');
document.getElementById('out').textContent=out; window.CHECK_RESULT=out;
</script></body></html>""" % (sim, json.dumps(scens[-1]), json.dumps(traces), json.dumps(asserts), json.dumps(list(DEPTHS)), NCYC, NCYC_RAND)
    outp = os.path.join(ROOT, "build", "explorer_check.html")
    open(outp, "w").write(page)
    print("RTL traces: %d runs; wrote %s" % (len(traces), os.path.relpath(outp, ROOT)))
    print("assertion mentions in RTL runs:", {k: v for k, v in asserts.items() if v})


if __name__ == "__main__":
    main()
