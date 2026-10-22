"""Builds data/legal.json (shown in-game) from docs/legal/*.txt.
Fill in the three values below ONCE before a commercial release, then re-run this script."""
import json, pathlib, datetime
ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBLISHER = "[PUBLISHER NAME]"          # your legal name or studio name
CONTACT = "[CONTACT EMAIL]"             # a monitored support address
JURISDICTION = "England and Wales"      # governing law for the EULA
DATE = datetime.date.today().strftime("%d %B %Y")

def sub(t):
    return t.replace("{PUBLISHER}", PUBLISHER).replace("{CONTACT}", CONTACT).replace("{JURISDICTION}", JURISDICTION).replace("{DATE}", DATE)

def rd(p):
    return pathlib.Path(p).read_text(encoding="utf-8").replace("\r\n", "\n").strip()

L = ROOT / "docs" / "legal"
credits = sub(rd(L / "CREDITS.txt"))
credits += "\n\n----- Ocean3D Lite licence -----\n" + rd(ROOT / "addons" / "ocean3d_lite" / "LICENSE.md")
credits += "\n\n----- Barlow font licence -----\n" + rd(ROOT / "assets" / "fonts" / "OFL-Barlow.txt")
data = {"epilepsy": rd(L / "EPILEPSY.txt"), "eula": sub(rd(L / "EULA.txt")), "privacy": sub(rd(L / "PRIVACY.txt")),
        "credits": credits, "version": 1}
out = json.dumps(data, indent=1, ensure_ascii=True).replace("\n", "\r\n")
(ROOT / "data" / "legal.json").write_bytes(out.encode("utf-8"))
print("wrote data/legal.json", len(out), "bytes")
