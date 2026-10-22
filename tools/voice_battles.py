"""Briefings + radio dialogue for the D-Day and Dunkirk missions (both sides). Merged into make_voice_story.py."""
import battle_data as B

M_EXTRA = {}
BRIEF_EXTRA = {}
for _m in B.MISSIONS:
    for _side, _s in _m["sides"].items():
        _k = (_m["id"], _side.lower())
        M_EXTRA[_k] = _s["lines"]
        BRIEF_EXTRA[_k] = _s["brief"]
