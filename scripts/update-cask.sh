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

[ "${BASH_SOURCE[0]}" = "${0}" ] && main "$@" || true
