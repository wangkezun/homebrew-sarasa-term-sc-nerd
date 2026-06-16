#!/usr/bin/env bash
# scripts/check-upstream.sh — emits build decision to stdout (GitHub Actions output format).
set -euo pipefail

needs_build() {   # $1 latest tag, $2 current tag -> exit 0 if a build is needed
  [ -n "$1" ] && [ "$1" != "null" ] && [ "$1" != "$2" ]
}

valid_tag() {     # exit 0 if $1 is a safe tag (no chars that could inject into $GITHUB_OUTPUT)
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

main() {
  local dir; dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local latest current
  latest="$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
      "https://api.github.com/repos/be5invis/Sarasa-Gothic/releases/latest" | jq -r .tag_name)"
  current="$(cat "$dir/version.txt" 2>/dev/null || echo "none")"
  # A non-empty tag that isn't a clean token is suspicious — refuse rather than echo it into $GITHUB_OUTPUT.
  if [ -n "$latest" ] && [ "$latest" != "null" ] && ! valid_tag "$latest"; then
    echo "refusing unexpected upstream tag: $latest" >&2; exit 1
  fi
  if needs_build "$latest" "$current"; then
    echo "build_needed=true"; echo "version=$latest"
  else
    echo "build_needed=false"; echo "version=$current"
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi
