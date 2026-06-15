# Sarasa Term SC Nerd Font Tap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single GitHub repo that auto-patches Sarasa Term SC (RIBBI) with Nerd Font glyphs on every upstream release and serves it as a self-updating Homebrew cask.

**Architecture:** One repo doubles as build automation (`.github/workflows/build.yml` + `scripts/`) and Homebrew tap (`Casks/`). A daily workflow checks `be5invis/Sarasa-Gothic` for a new release; if found it downloads the SuperTTC, extracts the 4 Term SC weights with fontforge, patches each with the nerd-fonts font-patcher (custom flags), merges them into one TTC with fonttools, verifies correctness, publishes a GitHub Release, and rewrites the cask + `version.txt` so `brew upgrade` picks it up.

**Tech Stack:** Bash, fontforge (+python), fonttools (TTC merge), 7z (SuperTTC extraction), jq, GitHub CLI (`gh`), GitHub Actions, Homebrew cask, bats-core (shell unit tests).

---

## File Structure

```
homebrew-sarasa-term-sc-nerd/
├── README.md                              # install + how-it-works
├── LICENSE-OFL.txt                        # SIL OFL 1.1 (Sarasa)
├── LICENSE-NERDFONTS.txt                  # Nerd Fonts MIT
├── .gitignore                             # work/, dist/, *.7z, *.ttc, *.ttf, fontpatcher/
├── version.txt                            # last built upstream version (single line)
├── config.sh                              # shared constants sourced by all scripts
├── scripts/
│   ├── check-upstream.sh                  # latest upstream tag vs version.txt → build decision
│   ├── build-fonts.sh                     # download → extract → patch → merge TTC → dist/
│   ├── verify-fonts.sh                    # assert width/glyph-count/name/icons/faces; gate
│   └── update-cask.sh                     # render Casks/*.rb + write version.txt
├── tests/
│   ├── check-upstream.bats
│   └── update-cask.bats
├── Casks/
│   └── font-sarasa-term-sc-nerd.rb        # bootstrapped, then rewritten by CI
└── .github/workflows/
    └── build.yml
```

Responsibilities: each script does one thing and is independently runnable. `config.sh` is the single source of truth for family/weights/flags so a future expansion (Mono, TC/J/K, more weights) is a config edit, not a rewrite.

---

## Task 1: Repo scaffold

**Files:**
- Create: `config.sh`, `.gitignore`, `LICENSE-OFL.txt`, `LICENSE-NERDFONTS.txt`

- [ ] **Step 1: Write `config.sh`**

```bash
# config.sh — single source of truth, sourced by all scripts.
UPSTREAM_REPO="be5invis/Sarasa-Gothic"
THIS_REPO="wangkezun/homebrew-sarasa-term-sc-nerd"

# Subfont name (in SuperTTC)  ->  clean output weight label
# Regular has no suffix in the SuperTTC subfont name.
SUBFONT_BASE="Sarasa Term SC"
WEIGHTS=("Regular" "Bold" "Italic" "BoldItalic")
weight_subfont() {            # $1 = weight label -> exact SuperTTC subfont name
  case "$1" in
    Regular)    echo "$SUBFONT_BASE" ;;
    Bold)       echo "$SUBFONT_BASE Bold" ;;
    Italic)     echo "$SUBFONT_BASE Italic" ;;
    BoldItalic) echo "$SUBFONT_BASE Bold Italic" ;;
  esac
}

PATCHED_FAMILY="SarasaTermSC Nerd Font Mono"
TTC_NAME="SarasaTermSCNerdFontMono.ttc"
CASK_TOKEN="font-sarasa-term-sc-nerd"

FONTPATCHER_VERSION="v3.4.0"
FONTPATCHER_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${FONTPATCHER_VERSION}/FontPatcher.zip"

# Patch recipe (see spec "背景:为何是这些参数").
PATCH_FLAGS=(--single-width-glyphs --makegroups 1 --cell "0:540:-285:965")
GLYPH_SETS=(--fontawesome --fontawesomeext --fontlogos --octicons --pomicons \
            --powerline --powerlineextra --powersymbols --codicons --weather)
# NOTE: deliberately NO --material (Material Design ~7000 glyphs would break the 65535 sfnt limit).

GLYPH_LIMIT=65535
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
work/
dist/
fontpatcher/
*.7z
*.zip
*.ttc
*.ttf
```

- [ ] **Step 3: Add license files**

Run:
```bash
curl -fsSL https://raw.githubusercontent.com/be5invis/Sarasa-Gothic/master/LICENSE -o LICENSE-OFL.txt
curl -fsSL https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/LICENSE -o LICENSE-NERDFONTS.txt
```
Expected: two non-empty files. If the Sarasa `LICENSE` path 404s, fetch `OFL.txt` from the same repo instead. Eyeball `LICENSE-OFL.txt` for a **Reserved Font Name** clause; if "Sarasa" is reserved, note it in README (see Task 8) — distribution under a renamed family ("...Nerd Font Mono") is still OFL-compliant, but the RFN must not be reused verbatim.

- [ ] **Step 4: Commit**

```bash
git add config.sh .gitignore LICENSE-OFL.txt LICENSE-NERDFONTS.txt
git commit -m "chore: repo scaffold, config and licenses"
```

---

## Task 2: `check-upstream.sh` (TDD)

Decides whether a build is needed by comparing the upstream latest tag to `version.txt`.

**Files:**
- Create: `scripts/check-upstream.sh`
- Test: `tests/check-upstream.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/check-upstream.bats
setup() { source "${BATS_TEST_DIRNAME}/../scripts/check-upstream.sh"; }

@test "needs_build true when tags differ" {
  run needs_build "v1.0.31" "v1.0.30"; [ "$status" -eq 0 ]
}
@test "needs_build false when tags equal" {
  run needs_build "v1.0.30" "v1.0.30"; [ "$status" -eq 1 ]
}
@test "needs_build false when latest empty" {
  run needs_build "" "v1.0.30"; [ "$status" -eq 1 ]
}
@test "needs_build false when latest is literal null" {
  run needs_build "null" "v1.0.30"; [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/check-upstream.bats`
Expected: FAIL — `check-upstream.sh` does not exist / `needs_build` not found.

- [ ] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# scripts/check-upstream.sh — emits build decision to stdout (GitHub Actions output format).
set -euo pipefail

needs_build() {   # $1 latest tag, $2 current tag -> exit 0 if a build is needed
  [ -n "$1" ] && [ "$1" != "null" ] && [ "$1" != "$2" ]
}

main() {
  local dir; dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local latest current
  latest="$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
      "https://api.github.com/repos/be5invis/Sarasa-Gothic/releases/latest" | jq -r .tag_name)"
  current="$(cat "$dir/version.txt" 2>/dev/null || echo "none")"
  if needs_build "$latest" "$current"; then
    echo "build_needed=true"; echo "version=$latest"
  else
    echo "build_needed=false"; echo "version=$current"
  fi
}

[ "${BASH_SOURCE[0]}" = "${0}" ] && main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/check-upstream.bats`
Expected: PASS (4 tests). (Install runner first if missing: `brew install bats-core`.)

- [ ] **Step 5: Commit**

```bash
git add scripts/check-upstream.sh tests/check-upstream.bats
git commit -m "feat: upstream version check with build decision"
```

---

## Task 3: `update-cask.sh` (TDD)

Renders the cask file and writes `version.txt`. Pure templating — the highest-risk-for-typos piece (a wrong sha256 breaks `brew install`).

**Files:**
- Create: `scripts/update-cask.sh`
- Test: `tests/update-cask.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/update-cask.bats
setup() { source "${BATS_TEST_DIRNAME}/../scripts/update-cask.sh"; }

@test "render_cask embeds version, sha, url, ttc filename" {
  run render_cask "v1.0.30" "deadbeef" "https://example.com/x.ttc"
  [ "$status" -eq 0 ]
  [[ "$output" == *'version "v1.0.30"'* ]]
  [[ "$output" == *'sha256 "deadbeef"'* ]]
  [[ "$output" == *'url "https://example.com/x.ttc"'* ]]
  [[ "$output" == *'font "SarasaTermSCNerdFontMono.ttc"'* ]]
  [[ "$output" == *'cask "font-sarasa-term-sc-nerd"'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/update-cask.bats`
Expected: FAIL — `render_cask` not found.

- [ ] **Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
# scripts/update-cask.sh — write Casks/<token>.rb and version.txt
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/config.sh"

render_cask() {   # $1 version  $2 sha256  $3 url
  cat <<EOF
cask "${CASK_TOKEN}" do
  version "$1"
  sha256 "$2"

  url "$3"
  name "Sarasa Term SC Nerd Font Mono"
  desc "Sarasa Term SC patched with Nerd Fonts (CJK 2:1 width preserved, enlarged icons)"
  homepage "https://github.com/${THIS_REPO}"

  font "${TTC_NAME}"
end
EOF
}

main() {   # $1 version  $2 sha256  $3 url
  mkdir -p "$DIR/Casks"
  render_cask "$1" "$2" "$3" > "$DIR/Casks/${CASK_TOKEN}.rb"
  printf '%s\n' "$1" > "$DIR/version.txt"
}

[ "${BASH_SOURCE[0]}" = "${0}" ] && main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/update-cask.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/update-cask.sh tests/update-cask.bats
git commit -m "feat: cask renderer and version.txt writer"
```

---

## Task 4: `verify-fonts.sh` (the correctness gate)

Asserts a font file meets all invariants. Run on every produced TTF and on the TTC. Exits non-zero (failing the CI build) on any violation — this is what prevents shipping a broken font.

**Files:**
- Create: `scripts/verify-fonts.sh`

- [ ] **Step 1: Write `verify-fonts.sh`**

```bash
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
    for cp in (0xF07B, 0xE725, 0xF015):
        try: f[cp]
        except TypeError: problems.append("%s: missing icon U+%04X" % (label, cp))
    f.close()
if problems:
    print("VERIFY FAIL:"); [print("  - " + p) for p in problems]; sys.exit(1)
print("VERIFY OK: %s (%d face[s])" % (path, len(names or [None])))
' "$FONT" "$PATCHED_FAMILY" "$GLYPH_LIMIT"
```

- [ ] **Step 2: Verify the gate FAILS on a non-conforming font**

Run (uses any stock font; family name won't match):
```bash
scripts/verify-fonts.sh /System/Library/Fonts/Menlo.ttc; echo "exit=$?"
```
Expected: prints `VERIFY FAIL:` lines and `exit=1`.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-fonts.sh
git commit -m "feat: font correctness gate (width/glyphs/name/icons)"
```

> The PASS path is exercised end-to-end in Task 5 against a freshly built font.

---

## Task 5: `build-fonts.sh` (download → extract → patch → merge TTC)

**Files:**
- Create: `scripts/build-fonts.sh`

- [ ] **Step 1: Write `build-fonts.sh`**

```bash
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

# 3. extract + patch each weight
for w in "${WEIGHTS[@]}"; do
  sub="$(weight_subfont "$w")"
  raw="$WORK/SarasaTermSC-$w.ttf"
  fontforge -lang=py -c 'import fontforge,sys; g=fontforge.open(sys.argv[1]); g.generate(sys.argv[2]); g.close()' \
    "${TTC_SRC}(${sub})" "$raw" 2>/dev/null
  rm -rf "$WORK/patched"; mkdir -p "$WORK/patched"
  fontforge -script "$FP/font-patcher" "${PATCH_FLAGS[@]}" "${GLYPH_SETS[@]}" \
    -out "$WORK/patched" "$raw" >/dev/null 2>&1
  out="$(find "$WORK/patched" -iname '*.ttf' | head -1)"
  [ -n "$out" ] || { echo "patch produced no file for $w" >&2; exit 1; }
  mv "$out" "$DIST/SarasaTermSCNerdFontMono-$w.ttf"
done

# 4. merge into a single TTC (fonttools dedups identical tables)
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
```

- [ ] **Step 2: Dry-run the build locally**

Run (set a real recent tag; uses ~792MB download — fine on a dev box):
```bash
export GITHUB_TOKEN=$(gh auth token)
LATEST=$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/be5invis/Sarasa-Gothic/releases/latest | jq -r .tag_name)
scripts/build-fonts.sh "$LATEST"
```
Expected: `dist/` contains 4 TTFs (~27-28MB each) + `SarasaTermSCNerdFontMono.ttc`.

- [ ] **Step 3: Run the gate against the build output (verify PASS path)**

Run:
```bash
for f in dist/*.ttf dist/*.ttc; do scripts/verify-fonts.sh "$f"; done
```
Expected: `VERIFY OK` for every file (TTC reports 4 faces). If anything FAILs, stop and diagnose before continuing.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-fonts.sh
git commit -m "feat: build pipeline (extract, patch, merge TTC)"
```

---

## Task 6: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Write `build.yml`**

```yaml
name: build
on:
  schedule:
    - cron: "0 6 * * *"   # daily 06:00 UTC
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: build
  cancel-in-progress: false

jobs:
  check:
    runs-on: ubuntu-latest
    outputs:
      build_needed: ${{ steps.c.outputs.build_needed }}
      version: ${{ steps.c.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - id: c
        env: { GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} }
        run: bash scripts/check-upstream.sh >> "$GITHUB_OUTPUT"

  build:
    needs: check
    if: needs.check.outputs.build_needed == 'true'
    runs-on: ubuntu-latest
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      VERSION: ${{ needs.check.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - name: Install deps
        run: |
          sudo apt-get update
          sudo apt-get install -y fontforge jq unzip
          pip3 install --quiet fonttools

      - name: Build fonts
        run: bash scripts/build-fonts.sh "$VERSION"

      - name: Verify fonts
        run: for f in dist/*.ttf dist/*.ttc; do bash scripts/verify-fonts.sh "$f"; done

      - name: Package TTFs
        run: (cd dist && zip -q SarasaTermSCNerdFontMono-TTF.zip SarasaTermSCNerdFontMono-*.ttf)

      - name: Create / update release
        run: |
          gh release create "$VERSION" \
            dist/SarasaTermSCNerdFontMono.ttc \
            dist/SarasaTermSCNerdFontMono-TTF.zip \
            --title "$VERSION" --notes "Auto-built from be5invis/Sarasa-Gothic $VERSION" \
          || gh release upload "$VERSION" \
            dist/SarasaTermSCNerdFontMono.ttc \
            dist/SarasaTermSCNerdFontMono-TTF.zip --clobber

      - name: Update cask
        run: |
          SHA=$(shasum -a 256 dist/SarasaTermSCNerdFontMono.ttc | awk '{print $1}')
          URL="https://github.com/${{ github.repository }}/releases/download/${VERSION}/SarasaTermSCNerdFontMono.ttc"
          bash scripts/update-cask.sh "$VERSION" "$SHA" "$URL"

      - name: Commit cask + version
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Casks/*.rb version.txt
          git commit -m "release: ${VERSION}" && git push || echo "nothing to commit"
```

- [ ] **Step 2: Lint the YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml')); print('yaml ok')"`
Expected: `yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: daily build + release + cask update workflow"
```

---

## Task 7: Bootstrap cask + README, create remote, first run

**Files:**
- Create: `Casks/font-sarasa-term-sc-nerd.rb` (placeholder), `README.md`

- [ ] **Step 1: Bootstrap a placeholder cask + version.txt from the local build**

Run (uses the `dist/` from Task 5; produces a real, installable cask before CI ever runs):
```bash
export GITHUB_TOKEN=$(gh auth token)
LATEST=$(cat /dev/stdin <<<"$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/be5invis/Sarasa-Gothic/releases/latest | jq -r .tag_name)")
SHA=$(shasum -a 256 dist/SarasaTermSCNerdFontMono.ttc | awk '{print $1}')
URL="https://github.com/wangkezun/homebrew-sarasa-term-sc-nerd/releases/download/${LATEST}/SarasaTermSCNerdFontMono.ttc"
scripts/update-cask.sh "$LATEST" "$SHA" "$URL"
cat Casks/font-sarasa-term-sc-nerd.rb version.txt
```
Expected: a cask with real version/sha and `version.txt` populated.

- [ ] **Step 2: Write `README.md`**

```markdown
# Sarasa Term SC Nerd Font (auto-built tap)

Nerd Fonts–patched **Sarasa Term SC** that keeps Sarasa's strict **2:1 CJK-to-Latin width**
and uses an **enlarged icon size** (`--cell 0:540`). Auto-rebuilt whenever
[be5invis/Sarasa-Gothic](https://github.com/be5invis/Sarasa-Gothic) ships a release.

## Install

\`\`\`bash
brew tap wangkezun/sarasa-term-sc-nerd
brew install --cask font-sarasa-term-sc-nerd
\`\`\`

Then set your terminal font to **`SarasaTermSC Nerd Font Mono`**. Updates arrive via `brew upgrade`.

## What's inside

- Family: `SarasaTermSC Nerd Font Mono`, weights Regular/Bold/Italic/BoldItalic (one TTC).
- Patched with nerd-fonts font-patcher: `--single-width-glyphs --makegroups 1 --cell 0:540:-285:965`
  plus all icon sets **except Material Design** (dropping it keeps the glyph count under the
  65535 sfnt limit; the icons lsd/terminals use live in the 4-hex PUA, not Material Design).

## Licensing

Sarasa Gothic: SIL OFL 1.1 (`LICENSE-OFL.txt`). Nerd Fonts: MIT (`LICENSE-NERDFONTS.txt`).
Patched fonts are renamed ("… Nerd Font Mono") per OFL.
```

- [ ] **Step 3: Commit, create remote, push**

```bash
git add Casks/font-sarasa-term-sc-nerd.rb version.txt README.md
git commit -m "feat: bootstrap cask and README"
gh repo create wangkezun/homebrew-sarasa-term-sc-nerd --public --source=. --remote=origin --push
```
Expected: repo created and pushed; Actions tab shows the workflow.

- [ ] **Step 4: Manually upload the first release (so the bootstrap cask resolves)**

Run:
```bash
(cd dist && zip -q SarasaTermSCNerdFontMono-TTF.zip SarasaTermSCNerdFontMono-*.ttf)
gh release create "$(cat version.txt)" \
  dist/SarasaTermSCNerdFontMono.ttc dist/SarasaTermSCNerdFontMono-TTF.zip \
  --title "$(cat version.txt)" --notes "Initial release"
```
Expected: release exists; the cask `url` now resolves.

---

## Task 8: End-to-end acceptance

- [ ] **Step 1: Trigger CI manually and confirm it no-ops on the current version**

Run: `gh workflow run build.yml` then `gh run watch`
Expected: `check` job outputs `build_needed=false` (version.txt already matches latest); `build` job skipped. Confirms the guard works.

- [ ] **Step 2: Force a build path test**

Run:
```bash
echo "force-rebuild-test" > version.txt && git commit -am "test: force rebuild" && git push
gh workflow run build.yml && gh run watch
```
Expected: `build` job runs, verifies, (re)uploads release assets, and commits `release: <version>` restoring the correct `version.txt`. Then revert if needed: `git pull`.

- [ ] **Step 3: Install via brew on this machine (real acceptance)**

Run:
```bash
brew untap wangkezun/sarasa-term-sc-nerd 2>/dev/null || true
brew tap wangkezun/sarasa-term-sc-nerd
brew install --cask font-sarasa-term-sc-nerd
ls -la ~/Library/Fonts/SarasaTermSCNerdFontMono.ttc
```
Expected: TTC installed. Remove the hand-built loose TTFs to avoid duplicate families:
```bash
rm -f ~/Library/Fonts/SarasaTermSCNerdFontMono-*.ttf
```
Then `Cmd+Q` Warp, reopen, confirm font `SarasaTermSC Nerd Font Mono` renders CJK + icons.

- [ ] **Step 4: Final commit**

```bash
git add -A && git commit -m "docs: mark tap live" --allow-empty && git push
```

---

## Self-Review

**Spec coverage:**
- Single-repo build+tap → Tasks 1,6,7 ✓
- Daily cron + manual trigger → Task 6 ✓
- Version diff guard / no empty releases → Tasks 2,6,8 ✓
- Pinned FontPatcher → config.sh + build-fonts.sh ✓
- Patch recipe (single-width / makegroups / cell 540 / no material) → config.sh ✓
- TTC via fonttools → build-fonts.sh ✓
- Verification gate (width/glyphs<65535/name/icons/faces) → Task 4 + CI step ✓
- Release with TTC + TTF → Task 6 ✓
- Cask auto-update + version.txt → Tasks 3,6 ✓
- Install UX `brew tap`/`install` → README + Task 8 ✓
- Licensing (OFL + Nerd, RFN check) → Task 1 step 3, README ✓
- Test strategy (manual dispatch first, then cron) → Task 8 ✓

**Placeholder scan:** No TBD/TODO; every step has concrete code/commands. The only runtime-variable is the upstream asset URL, resolved by `jq` pattern match (build-fonts.sh).

**Type/name consistency:** `CASK_TOKEN=font-sarasa-term-sc-nerd`, `TTC_NAME=SarasaTermSCNerdFontMono.ttc`, `PATCHED_FAMILY="SarasaTermSC Nerd Font Mono"` used identically across config/verify/update-cask/build/README. Weight labels (`Regular/Bold/Italic/BoldItalic`) consistent between `WEIGHTS`, `weight_subfont`, build loop, and TTC merge order.

**Known risk flagged for execution:** if a future Sarasa SC grows past 65535 even without Material Design, `verify-fonts.sh` fails the build loudly (by design) — at which point the icon set must be trimmed further.
