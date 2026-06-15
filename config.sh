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
