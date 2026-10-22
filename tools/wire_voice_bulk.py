"""Appends the make_voice_bulk_data texts to scripts/radio.gd and scripts/modes/ops_room.gd (run once)."""
import re
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_voice_bulk_data import WING, BRIEF, OPS, CHAT  # noqa: E402
from make_voice_more_data import BRIEF_SIX  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QS = r'(?<!\\)"(?:[^"\\]|\\.)*"'


def esc(t):
    return t.replace('"', '\\"')


def count(txt):
    return len(re.findall(QS, txt))


# ---- radio.gd
p = os.path.join(ROOT, "scripts", "radio.gd")
s = open(p, encoding="utf-8").read()
for key, start, al, ax, _d in WING:
    for grp, lines in ((1, al), (2, ax)):
        m = re.search(r'\t"%s": \{"Allies": \[(.*?)\],\n\t\t"Axis": \[(.*?)\]\}' % re.escape(key), s, re.S)
        assert count(m.group(grp)) == start - 1, (key, grp, count(m.group(grp)), start)
        s = s[:m.end(grp)] + ", " + ", ".join('"%s"' % esc(t) for t in lines) + s[m.end(grp):]
s = s.replace('for sfx in ["_b", "_c", "_d"]:', 'for sfx in ["_b", "_c", "_d", "_e", "_f"]:')
for const, side in (("CHATTER_ALLIES", "allies"), ("CHATTER_AXIS", "axis")):
    i = s.index("const %s" % const)
    j = s.index("\n]", i)
    body = s[i:j]
    n_now = body.count("\n\t[")
    assert n_now == (34 if side == "allies" else 31), (const, n_now)
    s = s[:j] + "".join('\n\t["%s", "%s"],' % (esc(c), esc(t)) for c, _spk, t in CHAT[side]) + s[j:]
open(p, "w", encoding="utf-8", newline="").write(s)

# ---- ops_room.gd
p = os.path.join(ROOT, "scripts", "modes", "ops_room.gd")
s = open(p, encoding="utf-8").read()
six = {k for k, _a, _x in BRIEF_SIX}
for kind, (al, _ax) in BRIEF.items():
    off = s.index("const HEADLINES")
    m = re.compile(r'\t"%s": \[(.*?)\],\n' % kind).search(s, off)
    assert count(m.group(1)) == (6 if kind in six else 5), (kind, count(m.group(1)))
    s = s[:m.end(1)] + ", " + ", ".join('"%s"' % esc(t) for t in al) + s[m.end(1):]
TABLE = {"open": "OPENERS", "followup": "FOLLOWUPS", "success": "SUCCESS_LINES", "fail": "FAIL_LINES", "hit": "HIT_LINES"}
for key, start, al, ax in OPS:
    for side, lines in (("Allies", al), ("Axis", ax)):
        i = s.index("const %s" % TABLE[key])
        m = re.compile(r'\t"%s": \[(.*?)\],' % side, re.S).search(s, i)
        assert count(m.group(1)) == start - 1, (key, side, count(m.group(1)))
        if key in ("open", "followup"):
            lines = ["{call}, " + t[0].lower() + t[1:] if not t.startswith("Ops") and not t.startswith("Jaf") else "{call}, " + t for t in lines]
        s = s[:m.end(1)] + ",\n\t\t" + ", ".join('"%s"' % esc(t) for t in lines) + s[m.end(1):]
# follow-up openers: pick only recorded ones, not the same twice running
a = '''		var fi: int = _rng.randi() % 4
		_say(String(FOLLOWUPS[side][fi]).format(fmt), 0.0, "followup_%d" % (fi + 1))'''
b = '''		var fl: Array = FOLLOWUPS[side]
		var favail: Array = []
		for k in fl.size():
			if (k < 4 or _clip("followup_%d" % (k + 1)) != "") and k != int(_last_take.get("followup", -1)):
				favail.append(k)
		var fi: int = int(favail[_rng.randi() % favail.size()]) if not favail.is_empty() else 0
		_last_take["followup"] = fi
		_say(String(fl[fi]).format(fmt), 0.0, "followup_%d" % (fi + 1))'''
assert a in s
s = s.replace(a, b)
open(p, "w", encoding="utf-8", newline="").write(s)
print("wired")
