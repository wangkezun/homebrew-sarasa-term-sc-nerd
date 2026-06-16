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
# Material Design (~6880 glyphs) can't be patched whole: with the full CJK base the font
# would exceed the 65535 sfnt limit. Instead build-fonts.sh trims MD to a ~4900-glyph subset
# (see scripts/make-md-subset.py) and adds it via --custom. Inputs:
MD_GLYPH_SRC="src/glyphs/materialdesign/MaterialDesignIconsDesktop.ttf"  # relative to fontpatcher dir
MD_WHITELIST="scripts/eza-lsd-md-icons.txt"                              # relative to repo root

GLYPH_LIMIT=65535
