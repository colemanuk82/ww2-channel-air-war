"""Generate the radio voice lines with edge-tts (Microsoft neural voices).

Free, no API key. Drop-in alternative to tools/generate_voices_elevenlabs.py: it reads the same
assets/voice/*.csv tables and writes the same layout (assets/voice/<file>.mp3), so nothing else in the
game needs to change. Existing files are skipped unless --force, so it is safe to re-run or to use it
just to fill the gaps.

Why edge-tts for this cast: the CSV "voice" column describes each speaker's accent. edge-tts has no
"German accent in English" voice, but a German (de-DE / de-AT) voice reading English text *is* English
with a German accent, which is exactly what the Luftwaffe speakers are written as. Same trick for the
Polish, Welsh, New Zealand and Canadian speakers - pick the native voice and let the accent fall out.

Setup:
    python -m pip install edge-tts

Usage:
    python tools/generate_voices_edge.py --dry-run        # what is missing / what it would do
    python tools/generate_voices_edge.py --missing        # only generate the lines with no mp3 yet
    python tools/generate_voices_edge.py --only "RAF rear gunner"
    python tools/generate_voices_edge.py --force          # re-record everything with these voices
    python tools/generate_voices_edge.py --sample 12 --out out/samples   # a taste test, no game files touched

Options:
    --csv NAME      only this table (repeatable), e.g. --csv voice_ops.csv (default: all of them)
    --out DIR       write here instead of assets/voice (for samples)
    --jobs N        parallel requests (default 4)
"""
import argparse
import asyncio
import csv
import os
import random
import sys

try:
    import edge_tts
except ImportError:
    raise SystemExit("edge-tts is not installed. Run: python -m pip install edge-tts")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VOICE_DIR = os.path.join(ROOT, "assets", "voice")

TABLES = ["voice_lines.csv", "voice_story.csv", "voice_generic.csv", "voice_bulk.csv",
          "voice_final.csv", "voice_ops.csv", "voice_places.csv", "voice_more.csv",
          "voice_variants.csv", "voice_last.csv"]

# speaker -> (edge-tts voice, rate, pitch). Chosen to match the accent in the CSV "voice" column.
CAST = {
    # ---- RAF / Allied
    "RAF sector controller":   ("en-GB-RyanNeural",   "+0%",  "-2Hz"),   # RP, calm, measured
    "RAF airfield tower":      ("en-GB-MaisieNeural", "+2%",  "+0Hz"),   # WAAF, bright, precise
    "RAF wingman":             ("en-GB-RyanNeural",   "+8%",  "+3Hz"),   # Yorkshire, energetic
    "RAF wing leader":         ("en-GB-RyanNeural",   "-2%",  "-1Hz"),   # RP wing commander
    "RAF squadron leader":     ("en-GB-ThomasNeural", "-2%",  "-5Hz"),   # Glasgow, gruff
    "RAF section leader":      ("en-NZ-MitchellNeural", "+0%", "+0Hz"),  # New Zealander
    "RAF pilot":               ("pl-PL-MarekNeural",  "+0%",  "+0Hz"),   # 303 Sqn, Polish
    "RAF operations room":     ("cy-GB-AledNeural",   "-2%",  "-2Hz"),   # Welsh, reassuring
    "RAF intelligence officer": ("en-GB-ThomasNeural", "-5%", "-6Hz"),   # older, measured (briefings)
    "RAF flying instructor":   ("en-GB-ThomasNeural", "-3%",  "-2Hz"),   # Lancashire, patient
    "RAF bomber captain":      ("en-GB-RyanNeural",   "-4%",  "-3Hz"),   # Lancaster skipper, authority
    "RAF bomber pilot":        ("en-GB-ThomasNeural", "+2%",  "+0Hz"),   # Midlands, terse
    "RAF navigator":           ("en-GB-RyanNeural",   "+0%",  "+0Hz"),   # Home Counties, precise
    "RAF bomb aimer":          ("en-CA-LiamNeural",   "+0%",  "+0Hz"),   # Canadian
    "RAF wireless operator":   ("en-GB-RyanNeural",   "+6%",  "+1Hz"),   # Estuary, quick and dry
    "RAF rear gunner":         ("en-GB-RyanNeural",   "+10%", "+2Hz"),   # 19, Cockney, nervy
    "RAF mid-upper gunner":    ("en-IE-ConnorNeural", "+3%",  "-4Hz"),   # Glaswegian, gruff
    "Player (RAF leader)":     ("en-GB-RyanNeural",   "+1%",  "-1Hz"),   # flight lieutenant, clipped
    "RAF bomber crew":         ("en-GB-RyanNeural",   "+2%",  "+0Hz"),
    "Coastguard, Dover":       ("en-GB-ThomasNeural", "-6%",  "-8Hz"),   # late 50s, weathered
    "Observer Corps":          ("en-GB-ThomasNeural", "-4%",  "-4Hz"),   # West Country, careful
    "Air-Sea Rescue":          ("en-GB-RyanNeural",   "+4%",  "-2Hz"),   # Cockney launch skipper
    # ---- Luftwaffe (German voices reading English = English with a German accent)
    "Luftwaffe controller":    ("de-DE-ConradNeural", "+0%",  "-2Hz"),   # precise, cool, formal
    "Luftwaffe airfield tower": ("de-DE-KatjaNeural", "+2%",  "+0Hz"),   # Nachrichtenhelferin
    "Luftwaffe wingman":       ("de-DE-KillianNeural", "+8%", "+3Hz"),   # Bavarian, eager
    "Luftwaffe pilot":         ("de-AT-JonasNeural",  "+2%",  "+2Hz"),   # Viennese, cheerful
    "Player (Luftwaffe leader)": ("de-DE-ConradNeural", "-3%", "-3Hz"),  # Staffelkapitaen, crisp
    "Luftwaffe formation leader": ("de-DE-ConradNeural", "-2%", "-2Hz"), # Gruppenkommandeur
    "Luftwaffe briefing officer": ("de-DE-ConradNeural", "-5%", "-5Hz"), # Oberst, stern
    "Luftwaffe flying instructor": ("de-DE-ConradNeural", "-3%", "-3Hz"),
    "Luftwaffe ground control": ("de-DE-ConradNeural", "+0%",  "-2Hz"),  # Gefechtsstand
    "Luftwaffe radar operator": ("de-DE-ConradNeural", "-5%", "-2Hz"),   # flat, monotone
    "Luftwaffe sea rescue":    ("de-DE-ConradNeural", "-3%",  "-5Hz"),   # Hamburg, dry
    "Luftwaffe flak officer":  ("de-DE-ConradNeural", "+8%",  "-3Hz"),   # gruff, shouting
    "Luftwaffe flight engineer": ("de-DE-KillianNeural", "+0%", "+0Hz"), # Berlin
    "Luftwaffe radio operator": ("de-DE-KillianNeural", "+6%", "+1Hz"),  # Hessian, quick
    "Luftwaffe bomber commander": ("de-DE-ConradNeural", "-2%", "-2Hz"),
    "Luftwaffe bomber pilot":  ("de-DE-KillianNeural", "+0%",  "-1Hz"),  # terse, concentrated
    "Luftwaffe dorsal gunner": ("de-DE-KillianNeural", "+5%",  "+2Hz"),  # Saxon
    "Luftwaffe ventral gunner": ("de-DE-KillianNeural", "-2%", "+0Hz"),  # Swabian, steady
}
FALLBACK = ("en-GB-RyanNeural", "+0%", "+0Hz")

URGENT_WORDS = ("urgent", "alert", "excited", "panicked", "shocked", "keen", "shout", "quick")


def settings(row):
    """(voice, rate, pitch) for a line: the speaker's cast entry, pushed faster if the direction says so."""
    voice, rate, pitch = CAST.get(row.get("speaker", ""), FALLBACK)
    d = (row.get("direction") or "").lower()
    if any(w in d for w in URGENT_WORDS):
        try:
            r = int(rate.rstrip("%"))
            rate = "%+d%%" % min(r + 12, 30)
        except ValueError:
            pass
    return voice, rate, pitch


def load(csv_names):
    rows = []
    for name in csv_names:
        path = os.path.join(VOICE_DIR, name)
        if not os.path.exists(path):
            print("  (no such table: %s)" % name)
            continue
        with open(path, encoding="utf-8") as f:
            for r in csv.DictReader(f):
                r["__csv"] = name
                rows.append(r)
    return rows


async def synth(text, voice, rate, pitch, out, jobs, sem):
    async with sem:
        c = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
        await c.save(out)


async def run(items, jobs):
    sem = asyncio.Semaphore(jobs)
    tasks = [synth(t, v, r, p, o, jobs, sem) for (t, v, r, p, o) in items]
    return await asyncio.gather(*tasks, return_exceptions=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", action="append", default=[])
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--missing", action="store_true", help="only lines with no mp3 yet (default behaviour anyway)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--out", default="")
    ap.add_argument("--sample", type=int, default=0, help="record N random lines instead of the full set")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    rows = load(a.csv or TABLES)
    if a.only:
        rows = [r for r in rows if r.get("speaker", "").lower() == a.only.lower()]
        if not rows:
            raise SystemExit("no speaker called %r" % a.only)

    out_root = a.out or VOICE_DIR
    if a.sample:
        rows = random.Random(7).sample(rows, min(a.sample, len(rows)))

    todo, skipped = [], 0
    for r in rows:
        rel = r.get("file", "")
        text = (r.get("speak") or r.get("line") or "").strip()
        if not rel or not text:
            continue
        out = os.path.join(out_root, rel.replace("/", os.sep) + ".mp3")
        if os.path.exists(out) and not a.force and not a.out and not a.sample:
            skipped += 1
            continue
        voice, rate, pitch = settings(r)
        todo.append((text, voice, rate, pitch, out, r))
    if a.limit:
        todo = todo[:a.limit]

    print("rows %d   to record %d   already present %d   ->  %s" % (len(rows), len(todo), skipped, out_root))
    by_voice = {}
    for (_, v, _, _, _, _) in todo:
        by_voice[v] = by_voice.get(v, 0) + 1
    for v in sorted(by_voice):
        print("   %-26s %4d lines" % (v, by_voice[v]))
    if a.dry_run or not todo:
        for (t, v, rate, pitch, o, r) in todo[:20]:
            print("   %-34s %-24s %s | %s" % (os.path.relpath(o, ROOT), v, r.get("speaker"), t[:54]))
        return 0

    items = [(t, v, rate, pitch, o) for (t, v, rate, pitch, o, _) in todo]
    fails = 0
    BATCH = 60
    done = 0
    for i in range(0, len(items), BATCH):
        chunk = items[i:i + BATCH]
        for (t, v, rate, pitch, o) in chunk:
            os.makedirs(os.path.dirname(o), exist_ok=True)
        res = asyncio.run(run(chunk, a.jobs))
        for (t, v, rate, pitch, o), r in zip(chunk, res):
            done += 1
            if isinstance(r, Exception):
                fails += 1
                print("  FAIL %-34s %s" % (os.path.relpath(o, ROOT), str(r)[:110]))
        print("  %d/%d" % (done, len(items)))
    print("\nDone: %d recorded, %d failed." % (len(items) - fails, fails))
    if fails == 0 and not a.out and not a.sample:
        print("Run Godot once (or --import) so the new mp3s are imported.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
