#!/usr/bin/env bash
# scripts/build-fonts.sh <upstream_version_tag>
# Produces dist/SarasaTermSCNerdFontMono-<Weight>.ttf (4) and dist/SarasaTermSCNerdFontMono.ttc
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/config.sh"
VERSION="$1"
WORK="$DIR/work"; DIST="$DIR/dist"; FP="$DIR/fontpatcher"
rm -rf "$WORK" "$DIST"; mkdir -p "$WORK" "$DIST"

# 1. font-patcher (pinned)
if [ ! -x "$FP/font-patcher" ]; then
  curl -fSL -o "$WORK/FontPatcher.zip" "$FONTPATCHER_URL"
  mkdir -p "$FP"; unzip -oq "$WORK/FontPatcher.zip" -d "$FP"
fi

# 2. download upstream SuperTTC archive for this version, extract the .ttc
# Prefer the hinted SuperTTC .zip (extractable with plain unzip; excludes "Unhinted").
asset_url="$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
  "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${VERSION}" \
  | jq -r '.assets[] | select(.name | test("^Sarasa-SuperTTC-[0-9][0-9.]*\\.zip$")) | .browser_download_url' | head -1)"
[ -n "$asset_url" ] || { echo "no hinted SuperTTC zip for ${VERSION}" >&2; exit 1; }
curl -fSL -o "$WORK/sarasa.zip" "$asset_url"
unzip -oq "$WORK/sarasa.zip" -d "$WORK"
TTC_SRC="$(find "$WORK" -iname 'Sarasa-SuperTTC*.ttc' | head -1)"
[ -n "$TTC_SRC" ] || { echo "SuperTTC .ttc not found after extract" >&2; exit 1; }

# 3. build trimmed Material Design subset once (shared across weights), added via --custom
MD_SUBSET="$WORK/md-subset.ttf"
python3 "$DIR/scripts/make-md-subset.py" \
  "$FP/$MD_GLYPH_SRC" "$FP/glyphnames.json" "$DIR/$MD_WHITELIST" "$MD_SUBSET"

# 4. extract + patch each weight
for w in "${WEIGHTS[@]}"; do
  sub="$(weight_subfont "$w")"
  raw="$WORK/SarasaTermSC-$w.ttf"
  fontforge -lang=py -c 'import fontforge,sys; g=fontforge.open(sys.argv[1]); g.generate(sys.argv[2]); g.close()' \
    "${TTC_SRC}(${sub})" "$raw" 2>/dev/null
  rm -rf "$WORK/patched"; mkdir -p "$WORK/patched"
  fontforge -script "$FP/font-patcher" "${PATCH_FLAGS[@]}" "${GLYPH_SETS[@]}" --custom "$MD_SUBSET" \
    -out "$WORK/patched" "$raw" >/dev/null 2>&1
  out="$(find "$WORK/patched" -iname '*.ttf' | head -1)"
  [ -n "$out" ] || { echo "patch produced no file for $w" >&2; exit 1; }
  mv "$out" "$DIST/SarasaTermSCNerdFontMono-$w.ttf"
done

# 4b. normalize the family name + restore post.isFixedPitch=1 on each weight. Upstream Sarasa Term ships isFixedPitch as 1,
# but fontforge's subfont extraction in step 4 recomputes it to 0 (the 2:1 dual width
# makes advances non-uniform). macOS/CoreText reads this flag for its monospace trait,
# so without it the family stops showing up in editors'/terminals' "fixed-width" pickers.
for w in "${WEIGHTS[@]}"; do
  python3 - "$DIST/SarasaTermSCNerdFontMono-$w.ttf" "$PATCHED_FAMILY" <<'PY'
import sys
from fontTools.ttLib import TTFont
f = TTFont(sys.argv[1])
family = sys.argv[2]
f["post"].isFixedPitch = 1
# makegroups bakes the enabled glyph-set list into the Typographic Family (name ID 16),
# producing the very long "...Plus Font Awesome Plus..." name. macOS/CoreText prefers
# name 16 over name 1 when present, so that long string is what shows up in Font Book and
# font pickers. Re-assert one clean family on both the legacy (1) and typographic (16)
# records so CoreText groups the four RIBBI weights under a single clean family name.
# name 2/4 are already correct (RIBBI); 17 stays unset.
name = f["name"]
for nid in (1, 16):
    for rec in [r for r in name.names if r.nameID == nid]:
        name.setName(family, nid, rec.platformID, rec.platEncID, rec.langID)
f.save(sys.argv[1])
PY
done

# 5. merge into a single TTC (fonttools dedups identical tables)
python3 - "$DIST/$TTC_NAME" \
  "$DIST/SarasaTermSCNerdFontMono-Regular.ttf" \
  "$DIST/SarasaTermSCNerdFontMono-Bold.ttf" \
  "$DIST/SarasaTermSCNerdFontMono-Italic.ttf" \
  "$DIST/SarasaTermSCNerdFontMono-BoldItalic.ttf" <<'PY'
import sys
from fontTools.ttLib import TTFont, TTCollection
out = sys.argv[1]
ttc = TTCollection()
ttc.fonts = [TTFont(p) for p in sys.argv[2:]]
ttc.save(out)
PY

echo "built: $DIST"
ls -la "$DIST"
