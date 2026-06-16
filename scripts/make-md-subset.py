#!/usr/bin/env python3
# scripts/make-md-subset.py <MaterialDesignIconsDesktop.ttf> <glyphnames.json> <whitelist.txt> <out.ttf>
#
# Material Design Icons (nf-md-*, ~6880 glyphs) cannot be patched in whole: with
# Sarasa Term SC's full CJK base the font would exceed the sfnt 65535-glyph limit.
# This builds a trimmed MD source font that DOES fit, by dropping the bulkiest
# low-value buckets (outline duplicates, vehicles, games, zodiac) while force-
# keeping every codepoint that eza/lsd reference (whitelist). font-patcher then
# adds this subset via --custom.
import json
import re
import sys

from fontTools import subset

MD_LO, MD_HI = 0xF0001, 0xF1AF0          # Material Design PUA range
MAX_KEEP = 5100                          # safety cap below the ~5206 headroom

# Buckets dropped to get under the limit. Order of magnitude: ~1950 glyphs.
DROP = [
    r"_outline$",                        # outline duplicates of solid icons (~1700)
    r"^(car|truck|bus|motorbike|moped|scooter|train|airplane|helicopter|rocket"
    r"|ferry|sail|ship|tractor|van|caravan|rickshaw|segway|gondola|tram|subway|taxi)",
    r"^(chess|cards|dice|poker|controller|gamepad|nintendo|sony_play|microsoft_xbox)",
    r"^zodiac",
]
DROP_RE = [re.compile(p) for p in DROP]


def main():
    src, glyphnames, whitelist_path, out = sys.argv[1:5]

    db = json.load(open(glyphnames))
    md = {int(v["code"], 16): k[3:]
          for k, v in db.items()
          if k.startswith("md-") and isinstance(v, dict) and "code" in v}

    whitelist = set()
    for line in open(whitelist_path):
        line = line.strip()
        if line.startswith("#") or not line:
            continue
        whitelist.add(int(line.split()[0][2:], 16))   # "U+F0306  md-key" -> 0xF0306

    raw_dropped = {cp for cp, name in md.items()
                   if any(r.search(name) for r in DROP_RE)}
    rescued = raw_dropped & whitelist          # would-be-dropped but eza/lsd need them
    dropped = raw_dropped - whitelist
    keep = (set(md) - dropped)

    print("MD total: %d  dropped: %d  whitelist rescued: %d  -> keep: %d"
          % (len(md), len(dropped), len(rescued), len(keep)))
    if len(keep) > MAX_KEEP:
        sys.exit("keep count %d exceeds safety cap %d" % (len(keep), MAX_KEEP))

    opt = subset.Options()
    opt.glyph_names = True          # font-patcher --custom keys glyphs by name
    opt.layout_features = []        # icons need no GSUB/GPOS
    opt.name_IDs = []
    opt.recalc_bounds = True
    font = subset.load_font(src, opt)
    sub = subset.Subsetter(options=opt)
    sub.populate(unicodes=keep)
    sub.subset(font)
    subset.save_font(font, out, opt)
    print("wrote %s" % out)


if __name__ == "__main__":
    main()
