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
cp site/compare.html dist/compare.html
cp site/tokens.css dist/tokens.css
cp site/og-image.png dist/og-image.png

# The design/ layer now belongs to the example store (its tokens are the
# shop's), so the landing's tokens live independently in site/tokens.css —
# no cross-check against design/system/tokens.css anymore.

for leftover in etalon-switcher data-fixture design-fixtures design-states setFixture; do
  if grep -q "$leftover" dist/index.html; then
    fail "etalon artifact leaked into production: $leftover"
  fi
done

for required in og:title og:description og:image twitter:card rel=\"canonical\" rel=\"icon\" localStorage tokens.css; do
  if ! grep -q "$required" dist/index.html; then
    fail "mandatory production marker missing: $required"
  fi
done

# The compare page ships with the landing: it must name its subject and
# stay on the shared tokens, and the landing must link to it.
for required in statesman aasm tokens.css rel=\"canonical\"; do
  if ! grep -q "$required" dist/compare.html; then
    fail "compare page marker missing: $required"
  fi
done
grep -q "compare.html" dist/index.html || fail "landing lost its link to compare.html"

echo "build.sh: dist/ ready (index.html + compare.html + tokens.css + og-image.png)"
