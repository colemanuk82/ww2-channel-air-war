"""Generate the radio voice lines with ElevenLabs.

Reads assets/voice/voice_lines.csv (made by tools/make_voice_lines.py). For each speaker it designs a voice from
the cast description (ElevenLabs Voice Design), generates that speaker's lines as MP3 into
assets/voice/<allies|axis>/<id>.mp3, then deletes the designed voice again so the free plan's custom-voice slots
never run out. Files that already exist are skipped, so the script can be re-run to resume (e.g. next month
when the free credits refill).

Setup (PowerShell):
    $env:ELEVENLABS_API_KEY = "<your key>"          # from elevenlabs.io > Developers > API keys
    python tools/generate_voices_elevenlabs.py --dry-run     # shows what it will do and the character cost
    python tools/generate_voices_elevenlabs.py               # generates everything

Options:
    --dry-run          list the work and the estimated credits, call nothing
    --only "<speaker>" only this speaker (as in the CSV "speaker" column), e.g. --only "RAF wingman"
    --force            regenerate files that already exist
    --keep-voices      keep the designed voices in your ElevenLabs account (needs free voice slots)
    --model <id>       text-to-speech model (default eleven_multilingual_v2)
    --premade          use ElevenLabs' built-in voices (the free plan cannot design voices through the API)

Free plan note: the free plan requires attribution and does not include a commercial licence. Check
ElevenLabs' current terms before shipping the voices in anything you sell.
"""
import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "assets", "voice", "voice_lines.csv")
OUT_DIR = os.path.join(ROOT, "assets", "voice")
API = "https://api.elevenlabs.io"

# Built-in ElevenLabs voices (usable on the free plan, which cannot design new voices through the API).
# Used with --premade. The Luftwaffe side speaks German (the CSV "speak" column).
PREMADE = {
    "RAF sector controller": "onwK4e9ZLuTAKqWW03F9",     # Daniel - British, authoritative
    "RAF airfield tower": "Xb7hH8MSUJpSbSDYk0k2",        # Alice - British woman
    "RAF wingman": "IKne3meq5aSn9XLyUdCD",               # Charlie - young Australian
    "Player (RAF leader)": "JBFqnCBsd6RMkjVDRZzb",       # George - warm British
    "RAF squadron leader": "N2lVS1w4EtoT3dr4eOWO",       # Callum - husky
    "RAF section leader": "TX3LPaxmHKxFdv7VOQHJ",        # Liam - young
    "RAF pilot": "bIHbv24MWmeRgasZH58o",                 # Will
    "Coastguard, Dover": "pqHfZKP75CyOyWqMBSUR",         # Bill - older
    "Observer Corps": "nPczCjzI2devNBz1zQrb",            # Brian - deep
    "Air-Sea Rescue": "cjVigY5qzO86Huf0OWal",            # Eric
    "Luftwaffe controller": "nPczCjzI2devNBz1zQrb",      # Brian - deep, calm
    "Luftwaffe airfield tower": "pFZP5JQG7iQjIQuC4Bku",  # Lily - woman
    "Luftwaffe wingman": "SOYHLrjzK2X1ezoPC6cr",         # Harry - young, intense
    "Player (Luftwaffe leader)": "N2lVS1w4EtoT3dr4eOWO", # Callum
    "Luftwaffe pilot": "TX3LPaxmHKxFdv7VOQHJ",           # Liam
    "Luftwaffe sea rescue": "pqHfZKP75CyOyWqMBSUR",      # Bill
    "Luftwaffe radar operator": "cjVigY5qzO86Huf0OWal",  # Eric
    "Luftwaffe flak officer": "CwhRBWXzGAHq8TQ4Fs17",    # Roger
    "RAF operations room": "onwK4e9ZLuTAKqWW03F9",       # Daniel - British controller (Dam Busters chatter)
    "RAF wing leader": "JBFqnCBsd6RMkjVDRZzb",          # George - warm British (Dam Busters chatter)
    "RAF intelligence officer": "nPczCjzI2devNBz1zQrb",  # Brian - older, measured (briefings)
    "Luftwaffe briefing officer": "CwhRBWXzGAHq8TQ4Fs17",  # Roger - stern (briefings)
    "Luftwaffe formation leader": "N2lVS1w4EtoT3dr4eOWO", # Callum - husky (used when the Voice Design quota is spent)
}
FALLBACK_VOICE = "JBFqnCBsd6RMkjVDRZzb"

# Voice Design needs 100-1000 characters of sample text; this is added to a speaker's own lines when short.
PAD_ALLIES = " Roger, understood. Keep your eyes open over the coast, the weather is clearing from the west and the Channel is quiet for now."
PAD_AXIS = " Understood. Keep watching the coast, the weather is clearing from the west and the Channel is quiet for now."


def call(method, path, key, body=None, accept="application/json", tries=5):
    data = None if body is None else json.dumps(body).encode("utf-8")
    for attempt in range(tries):
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("xi-api-key", key)
        req.add_header("Accept", accept)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                raw = r.read()
                return raw if accept != "application/json" else (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "replace")
            if e.code in (409, 429, 500, 502, 503) and attempt < tries - 1:
                wait = 5 * (attempt + 1)
                print("    busy (%d), retrying in %d s" % (e.code, wait))
                time.sleep(wait)
                continue
            raise SystemExit("ElevenLabs error %d on %s %s:\n%s" % (e.code, method, path, msg))
        except urllib.error.URLError as e:
            if attempt < tries - 1:
                time.sleep(5)
                continue
            raise SystemExit("network error: %s" % e)


def free_voice_slots(key):
    """Delete voices this script made earlier ("WW2 Channel - ...") so a new one fits under the plan's limit."""
    res = call("GET", "/v1/voices", key)
    for v in res.get("voices", []):
        if str(v.get("name", "")).startswith("WW2 Channel - "):
            call("DELETE", "/v1/voices/%s" % v["voice_id"], key)
            print("   removed old voice: %s" % v["name"])


def design_voice(key, speaker, description, sample):
    res = call("POST", "/v1/text-to-voice/design", key, {
        "voice_description": description,
        "text": sample,
        "model_id": "eleven_multilingual_ttv_v2",
        "seed": zlib.crc32(speaker.encode("utf-8")) % 1000000,   # same speaker -> same voice on a re-run
    })
    previews = res.get("previews") or []
    if not previews:
        raise SystemExit("Voice Design returned no previews for %s" % speaker)
    gen_id = previews[0]["generated_voice_id"]
    made = call("POST", "/v1/text-to-voice", key, {
        "voice_name": "WW2 Channel - " + speaker,
        "voice_description": description,
        "generated_voice_id": gen_id,
    })
    return made["voice_id"]


def tts(key, vid, body):
    """Text-to-speech; an unknown built-in voice id falls back to George."""
    try:
        return call("POST", "/v1/text-to-speech/%s?output_format=mp3_44100_128" % vid, key, body, accept="audio/mpeg")
    except SystemExit as e:
        if vid != FALLBACK_VOICE and ("404" in str(e) or "voice_not_found" in str(e)):
            print("    voice %s not available, using the fallback voice" % vid)
            return call("POST", "/v1/text-to-speech/%s?output_format=mp3_44100_128" % FALLBACK_VOICE, key, body, accept="audio/mpeg")
        raise


def settings_for(direction):
    d = direction.lower()
    urgent = any(w in d for w in ("urgent", "alert", "excited", "panicked", "shocked", "keen"))
    return {
        "stability": 0.32 if urgent else 0.55,
        "similarity_boost": 0.8,
        "style": 0.45 if urgent else 0.2,
        "use_speaker_boost": True,
        "speed": 1.08 if urgent else 1.0,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--keep-voices", action="store_true")
    ap.add_argument("--model", default="eleven_multilingual_v2")
    ap.add_argument("--csv", default=CSV_PATH, help="line list (default assets/voice/voice_lines.csv)")
    ap.add_argument("--premade", action="store_true", help="use built-in voices (free plan) instead of Voice Design")
    a = ap.parse_args()

    rows = list(csv.DictReader(open(a.csv, encoding="utf-8")))
    speakers = []
    for r in rows:
        if r["speaker"] not in speakers:
            speakers.append(r["speaker"])
    if a.only:
        speakers = [s for s in speakers if s.lower() == a.only.lower()]
        if not speakers:
            raise SystemExit("no speaker called %r in the CSV" % a.only)

    plan = []
    total_chars = 0
    for spk in speakers:
        todo = []
        for r in rows:
            if r["speaker"] != spk:
                continue
            out = os.path.join(OUT_DIR, r["file"].replace("/", os.sep) + ".mp3")
            if os.path.exists(out) and not a.force:
                continue
            todo.append((r, out))
        if not todo:
            continue
        lines = " ".join(r["line"] for r, _ in todo)
        pad = PAD_AXIS if todo[0][0]["side"] == "axis" else PAD_ALLIES
        # Voice Design needs at least 100 characters of sample text; keep it short (it costs credits too)
        sample = lines
        while len(sample) < 100:
            sample += pad
        if len(sample) > 160:
            cut = sample.rfind(" ", 100, 160)
            sample = sample[:cut if cut > 0 else 160]
        cost = (0 if a.premade else len(sample)) + sum(len(r.get("speak") or r["line"]) for r, _ in todo)
        total_chars += cost
        plan.append((spk, todo, sample))
        print("%-28s %3d lines  ~%d chars" % (spk, len(todo), cost))
    print("total: %d speakers, %d lines, about %d credits" % (len(plan), sum(len(t) for _, t, _ in plan), total_chars))
    if a.dry_run or not plan:
        return 0

    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key:
        raise SystemExit("Set the ELEVENLABS_API_KEY environment variable first (see the top of this file).")

    for spk, todo, sample in plan:
        desc = todo[0][0]["voice"]
        print("\n== %s\n   voice: %s" % (spk, desc))
        if not a.premade and not a.keep_voices:
            free_voice_slots(key)
        vid = PREMADE.get(spk, FALLBACK_VOICE) if a.premade else design_voice(key, spk, desc, sample)
        try:
            for r, out in todo:
                os.makedirs(os.path.dirname(out), exist_ok=True)
                audio = tts(key, vid, {
                    "text": r.get("speak") or r["line"],
                    "model_id": a.model,
                    "voice_settings": settings_for(r.get("direction", "")),
                })
                with open(out, "wb") as f:
                    f.write(audio)
                print("   %-34s %s" % (r["file"], r["line"]))
        finally:
            if not a.keep_voices and not a.premade:
                try:
                    call("DELETE", "/v1/voices/%s" % vid, key)
                except SystemExit as e:
                    print("   (could not delete the designed voice: %s)" % e)
    print("\nDone. Open the project in Godot (or run the --import command) so the new files are imported.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
