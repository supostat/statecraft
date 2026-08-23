#!/usr/bin/env bash
# Builds the deployable landing into dist/ from two sources of truth:
# the production page (site/index.html) and the design tokens
# (design/system/tokens.css). Fails red when the page still carries
# etalon-only artifacts or lost a mandatory production meta.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "build.sh: $1" >&2; exit 1; }

rm -rf dist
mkdir dist
cp site/index.html dist/index.html
cp site/tokens.css dist/tokens.css

# design/ lives outside git (working design layer). When it is present
# locally, the tracked production copy must match it — drift fails red.
if [ -f design/system/tokens.css ] && ! cmp -s design/system/tokens.css site/tokens.css; then
  fail "site/tokens.css drifted from design/system/tokens.css; re-copy after finishing design work"
fi

for leftover in etalon-switcher data-fixture design-fixtures design-states setFixture; do
  if grep -q "$leftover" dist/index.html; then
    fail "etalon artifact leaked into production: $leftover"
  fi
done

for required in og:title og:description rel=\"canonical\" rel=\"icon\" localStorage tokens.css; do
  if ! grep -q "$required" dist/index.html; then
    fail "mandatory production marker missing: $required"
  fi
done

echo "build.sh: dist/ ready (index.html + tokens.css)"
