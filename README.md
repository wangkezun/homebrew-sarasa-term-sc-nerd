# Sarasa Term SC Nerd Font (auto-built tap)

Nerd Fonts–patched **Sarasa Term SC** that keeps Sarasa's strict **2:1 CJK-to-Latin width**
and uses an **enlarged icon size** (`--cell 0:540`). Auto-rebuilt whenever
[be5invis/Sarasa-Gothic](https://github.com/be5invis/Sarasa-Gothic) ships a release.

## Install

```bash
brew tap wangkezun/sarasa-term-sc-nerd
brew trust wangkezun/sarasa-term-sc-nerd        # newer Homebrew requires trusting third-party casks
brew install --cask font-sarasa-term-sc-nerd
```

Then set your terminal font to **`SarasaTermSC Nerd Font Mono`**. Updates arrive via `brew upgrade`.

## What's inside

- Family: `SarasaTermSC Nerd Font Mono`, weights Regular/Bold/Italic/BoldItalic (one TTC).
- Patched with nerd-fonts font-patcher: `--single-width-glyphs --makegroups 1 --cell 0:540:-285:965`
  plus all icon sets, including a **trimmed Material Design** subset. The full ~6880-glyph Material
  Design set would push the CJK base over the 65535 sfnt limit, so it's trimmed to ~4900 glyphs
  (dropping outline-duplicate/vehicle/game/zodiac buckets) while force-keeping every icon eza and
  lsd reference. See `scripts/make-md-subset.py`.

## How it updates

A daily GitHub Actions workflow checks the upstream latest release, and on a new version:
rebuilds the fonts, verifies them (CJK width, glyph count, family name, icons), publishes a
GitHub Release, and rewrites the cask — so `brew update && brew upgrade` tracks upstream automatically.

## Licensing

Sarasa Gothic: SIL OFL 1.1 (`LICENSE-OFL.txt`). Nerd Fonts: MIT (`LICENSE-NERDFONTS.txt`).
Patched fonts are renamed ("… Nerd Font Mono") per OFL.
