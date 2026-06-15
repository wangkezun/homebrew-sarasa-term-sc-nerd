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

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi
