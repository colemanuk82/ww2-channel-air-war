#!/usr/bin/env python3
"""Hand over the cockpit frames one at a time, in a stable order.

Keeps a sent-list so nothing is repeated, converts the next available frame to a chat-sized JPEG and
prints the path for delivery. Run it after each capture lands:

  python3 tools/next_cockpit.py
"""
import os, subprocess, sys

FF = r"C:/Users/colem/AppData/Local/hermes/tools/ffmpeg-9.0.1-win32-x64/bin/ffmpeg.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # tools/ -> repo root
SRC = os.path.join(ROOT, "build", "cockpit_new")
DST = os.path.join(ROOT, "build", "share", "one")
STATE = os.path.join(DST, ".sent")

ORDER = ["a20", "b25", "b26", "bf109", "bf110", "blenheim", "c47", "defiant", "do17", "fw190",
         "fw200", "he111", "hurricane", "ju52", "ju87", "ju88", "lancaster", "me262", "mosquito",
         "p38", "p47", "p51", "spitfire", "tempest", "typhoon"]

os.makedirs(DST, exist_ok=True)
sent = set(open(STATE).read().split()) if os.path.exists(STATE) else set()

ready = [i for i in ORDER if os.path.exists(os.path.join(SRC, "%s.png" % i))]
pending = [i for i in ready if i not in sent]

print("captured: %d/25   already sent: %d   waiting to send: %d" % (len(ready), len(sent), len(pending)))
if not pending:
    print("NOTHING-READY")
    sys.exit(0)

# hand over one at a time, as asked
for i in pending[:1]:
    src = os.path.join(SRC, "%s.png" % i)
    dst = os.path.join(DST, "%s.jpg" % i)
    subprocess.run([FF, "-y", "-i", src, "-vf", "scale=1600:-1", "-q:v", "3", dst],
                   capture_output=True, text=True)
    if os.path.exists(dst):
        sent.add(i)
        open(STATE, "w").write("\n".join(sorted(sent)))
        print("SEND %s  (%s, %d bytes)" % (dst.replace("\\", "/"), i, os.path.getsize(dst)))
    else:
        print("convert failed for", i)
print("remaining after this: %d" % len([x for x in ORDER if os.path.exists(os.path.join(SRC, '%s.png' % x)) and x not in sent]))
