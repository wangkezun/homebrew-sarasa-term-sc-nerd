#!/usr/bin/env bash
# scripts/verify-fonts.sh <font.ttf|font.ttc>
# Asserts: Latin A=500, CJK 你=1000, glyphs<65535, family name, key icons present.
# For a .ttc, every face is checked.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/config.sh"

FONT="$1"
fontforge -lang=py -c '
import fontforge, sys
path = sys.argv[1]
family_expected = sys.argv[2]
limit = int(sys.argv[3])
names = fontforge.fontsInFile(path)          # list of subfont names; 1 entry for a plain TTF
problems = []
for nm in (names or [None]):
    f = fontforge.open(path + (("(%s)" % nm) if nm else ""))
    label = nm or f.fontname
    if f[0x41].width != 500:   problems.append("%s: Latin A width %d != 500" % (label, f[0x41].width))
    if f[0x4F60].width != 1000: problems.append("%s: CJK 你 width %d != 1000" % (label, f[0x4F60].width))
    gc = len(list(f.glyphs()))
    if gc >= limit:  problems.append("%s: glyph count %d >= %d" % (label, gc, limit))
    if f.familyname != family_expected: problems.append("%s: family %r != %r" % (label, f.familyname, family_expected))
    # FontAwesome/devicons/octicons (built-in sets) + Material Design (--custom subset, eza/lsd icons)
    for cp in (0xF07B, 0xE725, 0xF015, 0xF0306, 0xF024F, 0xF075A):
        try: f[cp]
        except TypeError: problems.append("%s: missing icon U+%04X" % (label, cp))
    f.close()
if problems:
    print("VERIFY FAIL:"); [print("  - " + p) for p in problems]; sys.exit(1)
print("VERIFY OK: %s (%d face[s])" % (path, len(names or [None])))
' "$FONT" "$PATCHED_FAMILY" "$GLYPH_LIMIT"
