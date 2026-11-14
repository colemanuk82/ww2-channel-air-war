#!/usr/bin/env python
"""WW2 debug tool: run headless scenarios, analyse the state log, serve the browser viewer.

  python tools/dbg/dbg.py run --style raf_bomber --wingmen 3 [--secs 150] [--name x] [--extra "--spot=2"]
  python tools/dbg/dbg.py check x            # analyse a run, exit 1 on problems
  python tools/dbg/dbg.py at x 42.5          # every aircraft's pose/state at t
  python tools/dbg/dbg.py summary x          # JSON summary (agents, events, findings)
  python tools/dbg/dbg.py serve [--port 8765]   # viewer + JSON API, http://127.0.0.1:8765/

API (serve): GET /api/runs | /api/run?name= | /api/summary?name= | /api/at?name=&t= |
             POST/GET /api/sim?style=&wingmen=&secs=&name=&extra=   (runs the headless sim, returns the summary)
A run log is build/dbg/<name>.json; coordinates are in the airfield's local frame (x right, z along the
runway, take-off toward -Z, yaw clockwise from the take-off direction). See tools/dbg/README.md.
"""
import argparse, json, math, os, subprocess, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RUNS = os.path.join(ROOT, "build", "dbg")
VIEWER = os.path.join(os.path.dirname(__file__), "viewer")
GODOT = os.environ.get("GODOT", r"F:\godot-std\bin\godot.windows.editor.double.x86_64.console.exe")


# ------------------------------------------------------------------ running
def run_sim(style="raf_bomber", wingmen=2, secs=150, name="", extra="", aircraft="spitfire", timeout=240):
    name = name or style
    out = "build/dbg/%s.json" % name
    cmd = [GODOT, "--headless", "--fixed-fps", "60", "--path", ROOT, "scenes/dbg.tscn", "--",
           "--style=%s" % style, "--wingmen=%d" % wingmen, "--secs=%s" % secs, "--aircraft=%s" % aircraft, "--out=%s" % out]
    cmd += [a for a in extra.split() if a]
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
    log = [l for l in (p.stdout + p.stderr).splitlines() if any(k in l for k in ("DBG", "SCRIPT ERROR", "Parse Error", "ERROR"))]
    path = os.path.join(ROOT, out)
    if not os.path.exists(path) or "DBG_DONE" not in " ".join(log):
        raise RuntimeError("scenario failed:\n" + "\n".join(log))
    return name, round(time.time() - t0, 1), log


def load(name):
    p = name if name.endswith(".json") and os.path.isabs(name) else os.path.join(RUNS, name if name.endswith(".json") else name + ".json")
    with open(p, encoding="utf8") as f:
        return json.load(f)


# ------------------------------------------------------------------ analysis
def _seg_dist(px, pz, a, b):
    ax, az = a; bx, bz = b
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0 if l2 == 0 else max(0, min(1, ((px - ax) * dx + (pz - az) * dz) / l2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def route_dist(route, x, z):
    return min((_seg_dist(x, z, route[i], route[i + 1]) for i in range(len(route) - 1)), default=1e9)


def series(d):
    """{agent_id: [(t, x, z, yaw, speed, state, wp)]} (frames only list spawned aircraft)."""
    out = {a["id"]: [] for a in d["agents"]}
    for t, rows in d["frames"]:
        for r in rows:
            out[r[0]].append((t, r[1], r[2], r[3], r[4], r[5], r[6]))
    return out


def analyse(d, off_route=25.0, stuck_secs=20.0, overlap=0.6, reverse_m=15.0):
    """Findings: dicts {kind, t, agents, msg}. Kinds: overlap, off_route, stuck, reversing, no_line_up, wp_regress."""
    f = []
    ser = series(d)
    ag = {a["id"]: a for a in d["agents"]}
    ids = list(ser)
    # overlap: two aircraft closer than 0.6 x the sum of their radii (first frame of each episode)
    pair_on = {}
    by_t = [(t, {r[0]: r for r in rows}) for t, rows in d["frames"]]
    for t, rows in by_t:
        for i in range(len(ids)):
            for j in range(i + 1, len(ids)):
                a, b = rows.get(ids[i]), rows.get(ids[j])
                if not a or not b:
                    continue
                dist = math.hypot(a[1] - b[1], a[2] - b[2])
                lim = (ag[ids[i]]["radius"] + ag[ids[j]]["radius"]) * overlap
                key = (ids[i], ids[j])
                if dist < lim and not pair_on.get(key):
                    f.append({"kind": "overlap", "t": t, "agents": list(key), "msg": "%s and %s only %.1f m apart (limit %.1f)" % (key[0], key[1], dist, lim)})
                pair_on[key] = dist < lim
    for aid, s in ser.items():
        route = ag[aid]["route"]
        # off route
        on = False
        for t, x, z, yaw, sp, st, wp in s:
            dd = route_dist(route, x, z)
            if dd > off_route and not on:
                f.append({"kind": "off_route", "t": t, "agents": [aid], "msg": "%s is %.0f m off its route" % (aid, dd)})
            on = dd > off_route
        # stuck: 'stopped' (not holding) for a long time
        run_start = None
        for t, x, z, yaw, sp, st, wp in s:
            if st == "stopped":
                run_start = run_start if run_start is not None else t
                if t - run_start >= stuck_secs and not any(e["kind"] == "stuck" and e["agents"] == [aid] and e["t"] >= run_start for e in f):
                    f.append({"kind": "stuck", "t": run_start, "agents": [aid], "msg": "%s stopped (not at the hold) for %.0f s+ from t=%.0f at wp%d" % (aid, stuck_secs, run_start, wp)})
            else:
                run_start = None
        # reversing: the waypoint index stalls while the aircraft travels far (circling / overshoot)
        # measured as the path length covered while wp does not advance
        plen, wp0, t0, flagged = 0.0, None, None, False
        for k in range(1, len(s)):
            if s[k][6] != wp0:
                wp0, plen, t0, flagged = s[k][6], 0.0, s[k][0], False
                continue
            plen += math.hypot(s[k][1] - s[k - 1][1], s[k][2] - s[k - 1][2])
            leg = math.hypot(route[wp0][0] - route[max(wp0 - 1, 0)][0], route[wp0][1] - route[max(wp0 - 1, 0)][1]) if wp0 is not None and wp0 < len(route) else 0.0
            if plen > leg * 1.6 + 60 and not flagged and s[k][5] != "holding":
                f.append({"kind": "wp_stall", "t": s[k][0], "agents": [aid], "msg": "%s travelled %.0f m since t=%.0f without reaching waypoint %d (overshoot / circling)" % (aid, plen, t0, wp0)})
                flagged = True
        # heading flip: speed>3 and travelling AWAY from the current waypoint for a sustained spell
        if s and ag[aid]["t_done"] < 0:
            f.append({"kind": "no_line_up", "t": s[-1][0], "agents": [aid], "msg": "%s never lined up (last state %s, wp%d)" % (aid, s[-1][5], s[-1][6])})
    f.sort(key=lambda e: e["t"])
    return f


def summary(d):
    ser = series(d)
    ag = []
    for a in d["agents"]:
        s = ser[a["id"]]
        ag.append({"id": a["id"], "spot": a["spot"], "route_legs": len(a["route"]), "spawn_t": a["spawn_t"],
                   "lined_up_t": a["t_done"] if a["t_done"] >= 0 else None,
                   "final": {"t": s[-1][0], "x": s[-1][1], "z": s[-1][2], "yaw": s[-1][3], "state": s[-1][5], "wp": s[-1][6]} if s else None,
                   "max_speed": max((r[4] for r in s), default=0)})
    return {"layout": {k: d["layout"][k] for k in ("style", "name", "heading_deg", "runway")},
            "reason": d["reason"], "sim_secs": d["sim_secs"], "agents": ag, "events": d["events"], "findings": analyse(d)}


def at(d, t):
    best = min(d["frames"], key=lambda fr: abs(fr[0] - t))
    return {"t": best[0], "aircraft": [{"id": r[0], "x": r[1], "z": r[2], "yaw": r[3], "speed": r[4], "state": r[5], "wp": r[6], "throttle": r[7], "brake": r[8]} for r in best[1]]}


# ------------------------------------------------------------------ server
class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else body.encode("utf8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        self.do_GET()

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        try:
            if u.path == "/api/runs":
                os.makedirs(RUNS, exist_ok=True)
                names = sorted((n[:-5] for n in os.listdir(RUNS) if n.endswith(".json")), key=lambda n: -os.path.getmtime(os.path.join(RUNS, n + ".json")))
                return self._send(200, json.dumps(names))
            if u.path == "/api/run":
                return self._send(200, json.dumps(load(q["name"])))
            if u.path == "/api/summary":
                return self._send(200, json.dumps(summary(load(q["name"])), indent=1))
            if u.path == "/api/at":
                return self._send(200, json.dumps(at(load(q["name"]), float(q["t"]))))
            if u.path == "/api/sim":
                name, secs_taken, _ = run_sim(q.get("style", "raf_bomber"), int(q.get("wingmen", 2)), q.get("secs", "150"), q.get("name", ""), q.get("extra", ""), q.get("aircraft", "spitfire"))
                s = summary(load(name)); s["run"] = name; s["wall_secs"] = secs_taken
                return self._send(200, json.dumps(s, indent=1))
            path = "index.html" if u.path in ("/", "") else u.path.lstrip("/")
            fp = os.path.normpath(os.path.join(VIEWER, path))
            if fp.startswith(VIEWER) and os.path.isfile(fp):
                ct = {"html": "text/html", "js": "text/javascript", "css": "text/css"}.get(fp.rsplit(".", 1)[-1], "application/octet-stream")
                return self._send(200, open(fp, "rb").read(), ct + "; charset=utf-8")
            self._send(404, '{"error":"not found"}')
        except Exception as e:  # noqa
            self._send(500, json.dumps({"error": str(e)}))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run"); r.add_argument("--style", default="raf_bomber"); r.add_argument("--wingmen", type=int, default=2)
    r.add_argument("--secs", default="150"); r.add_argument("--name", default=""); r.add_argument("--extra", default=""); r.add_argument("--aircraft", default="spitfire")
    for n in ("check", "summary"):
        c = sub.add_parser(n); c.add_argument("name")
    a_ = sub.add_parser("at"); a_.add_argument("name"); a_.add_argument("t", type=float)
    s = sub.add_parser("serve"); s.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    if args.cmd == "run":
        name, secs, _ = run_sim(args.style, args.wingmen, args.secs, args.name, args.extra, args.aircraft)
        sm = summary(load(name))
        print("run '%s' in %.1fs wall: %s (%.0fs simulated)" % (name, secs, sm["reason"], sm["sim_secs"]))
        for a in sm["agents"]:
            print("  %-7s spot %-3s lined_up %s final %s" % (a["id"], a["spot"], a["lined_up_t"], a["final"]["state"] if a["final"] else "-"))
        for f_ in sm["findings"]:
            print("  FINDING t=%6.1f %-10s %s" % (f_["t"], f_["kind"], f_["msg"]))
    elif args.cmd == "check":
        sm = summary(load(args.name))
        for f_ in sm["findings"]:
            print("t=%6.1f %-10s %s" % (f_["t"], f_["kind"], f_["msg"]))
        print("%d finding(s)" % len(sm["findings"]))
        sys.exit(1 if sm["findings"] else 0)
    elif args.cmd == "summary":
        print(json.dumps(summary(load(args.name)), indent=1))
    elif args.cmd == "at":
        print(json.dumps(at(load(args.name), args.t), indent=1))
    elif args.cmd == "serve":
        print("viewer: http://127.0.0.1:%d/" % args.port)
        ThreadingHTTPServer(("127.0.0.1", args.port), H).serve_forever()


if __name__ == "__main__":
    main()
