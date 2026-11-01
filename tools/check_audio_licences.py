"""Fails the build if any audio file in the repo is not covered by the licence allowlist.

Every sound effect, music track and voice line that ships with the game must be covered by
tools/audio_allowlist.json: either an explicit per-track entry with its title, artist and source,
or a "generated" prefix for audio our own scripts synthesise (the AI voices).

This exists because a commercial film soundtrack was once dropped into assets/music/ingame/ and
shipped in every release for ~80 versions. Commercial recordings cannot be redistributed with the
game, so a stray file must stop the release instead of quietly riding along.

Usage:
  python tools/check_audio_licences.py            # whole repo
  python tools/check_audio_licences.py --staged   # only files newly added/changed in the index
Exit codes: 0 clean, 1 unlicensed audio found, 2 allowlist missing or malformed.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOWLIST = ROOT / "tools" / "audio_allowlist.json"
AUDIO_EXTS = {".mp3", ".ogg", ".wav", ".flac", ".m4a", ".aac", ".opus", ".wma", ".aiff"}
SCAN_DIRS = ["assets"]


def load_allowlist() -> tuple[set[str], list[str]]:
    try:
        data = json.loads(ALLOWLIST.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"ERROR: {ALLOWLIST.relative_to(ROOT)} is missing")
        raise SystemExit(2)
    except json.JSONDecodeError as e:
        print(f"ERROR: {ALLOWLIST.relative_to(ROOT)} is not valid JSON: {e}")
        raise SystemExit(2)
    tracks = data.get("tracks") or []
    if not tracks:
        print("ERROR: the allowlist has no tracks - refusing to pass")
        raise SystemExit(2)
    paths = set()
    for t in tracks:
        for key in ("path", "title", "artist", "source"):
            if not t.get(key):
                print(f"ERROR: allowlist entry missing '{key}': {t}")
                raise SystemExit(2)
        paths.add(t["path"])
    generated = [g for g in (data.get("generated") or []) if g]
    return paths, generated


def rel(p: pathlib.Path) -> str:
    return p.relative_to(ROOT).as_posix()


def staged_audio() -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=AM", "-z"],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout.decode("utf-8", "surrogateescape")
    return [p for p in out.split("\0") if p and pathlib.Path(p).suffix.lower() in AUDIO_EXTS]


def all_audio() -> list[str]:
    found = []
    for top in SCAN_DIRS:
        base = ROOT / top
        if not base.is_dir():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix.lower() in AUDIO_EXTS:
                found.append(rel(p))
    return found


def main() -> int:
    allowed, generated = load_allowlist()
    candidates = staged_audio() if "--staged" in sys.argv[1:] else all_audio()
    missing = [p for p in candidates if p not in allowed and not any(p.startswith(g) for g in generated)]

    print(f"audio licence check: {len(candidates)} file(s) checked against {len(allowed)} allowlisted track(s)")
    if missing:
        print(f"\nBLOCKED: {len(missing)} audio file(s) have no licence entry in tools/audio_allowlist.json:")
        for p in sorted(missing):
            print(f"  {p}")
        print(
            "\nOnly add audio you can legally redistribute (e.g. Pixabay Content License, CC0).\n"
            "Commercial, film, TV, game or broadcast recordings must never be committed - the player\n"
            "imports their own copies through Options > Music at run time.\n"
            "If the file is legitimate, add an entry with title, artist and source to\n"
            "tools/audio_allowlist.json and to ATTRIBUTION.md."
        )
        return 1

    absent = sorted(p for p in allowed if not (ROOT / p).exists())
    if absent:
        print(f"\nwarning: {len(absent)} allowlisted track(s) are not on disk (stale allowlist):")
        for p in absent:
            print(f"  {p}")

    print("OK: every audio file is covered by the allowlist")
    return 0


if __name__ == "__main__":
    sys.exit(main())
