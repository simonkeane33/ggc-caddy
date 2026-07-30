#!/usr/bin/env bash
# lint-no-em-dash.sh
# Fail if any em dash (U+2014) is found in website/ or docs/ files.
# Run from repo root: bash scripts/lint-no-em-dash.sh

set -euo pipefail

ERRORS=0

check_dir() {
  local dir="$1"
  local label="$2"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  local matches
  matches=$(grep -rI '—' "$dir" || true)
  if [ -n "$matches" ]; then
    echo "Em dash found in $label files:"
    echo "$matches"
    ERRORS=1
  fi
}

check_dir "website/" "website"
check_dir "greystones-caddy-ios/docs/" "docs"

if [ "$ERRORS" -ne 0 ]; then
  echo
  echo "Replace em dashes (—) with hyphens (-) before committing."
  exit 1
fi

echo "No em dashes found. Clean."
exit 0
