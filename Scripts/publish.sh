#!/usr/bin/env bash
# Publish an already built, notarized and installed release to GitHub Releases, then put its
# appcast into the landing site, which serves the feed at https://bobuk.io/apps/ting/appcast.xml.
# Run Scripts/release.sh first. The release is created as a draft, all assets are uploaded,
# and only then is it published, so the feed never points at a missing archive. The GitHub
# release keeps its appcast.xml too: Ting 0.6.1 and older read the feed from there.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
REPOSITORY=bobuk-io/ting
TAG="v${MARKETING_VERSION}"
ZIP="dist/Ting-${MARKETING_VERSION}-universal.zip"
SUMS="dist/SHA256SUMS.txt"
APPCAST="dist/appcast.xml"
NOTES="docs/releases/${TAG}.md"
LANDING=${LANDING:-"$ROOT/../landing"}
SITE_FEED="$LANDING/public/apps/ting/appcast.xml"

for file in "$ZIP" "$SUMS" "$APPCAST" "$NOTES"; do
  [[ -f "$file" ]] || { echo "Missing $file. Run Scripts/release.sh first." >&2; exit 1; }
done
command -v gh >/dev/null || { echo "The GitHub CLI (gh) is required." >&2; exit 1; }
[[ -d "$LANDING/public" ]] || { echo "No landing site at $LANDING; set LANDING to its checkout." >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || { echo "Commit changes before publishing." >&2; exit 1; }
COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git ls-remote origin refs/heads/main | cut -f1)
[[ "$COMMIT" == "$REMOTE_COMMIT" ]] || { echo "Push the release commit to main before publishing." >&2; exit 1; }
grep -q "sparkle:version>${BUILD_NUMBER}<" "$APPCAST" || { echo "The appcast is not for build ${BUILD_NUMBER}." >&2; exit 1; }
(cd dist && shasum -a 256 -c SHA256SUMS.txt)

# The build number must grow past both published feeds. The first release has none yet.
PUBLISHED=0
for FEED_URL in "https://github.com/${REPOSITORY}/releases/latest/download/appcast.xml" "https://bobuk.io/apps/ting/appcast.xml"; do
  FEED=$(curl -fsSL --max-time 30 "$FEED_URL?v=$(date +%s)" 2>/dev/null || true)
  BUILD=$(printf '%s' "$FEED" | grep -o 'sparkle:version>[0-9]*<' | head -1 | tr -dc '0-9')
  if [[ -n "$BUILD" && "$BUILD" -gt "$PUBLISHED" ]]; then PUBLISHED=$BUILD; fi
done
if gh release view --repo "$REPOSITORY" >/dev/null 2>&1 && [[ "$PUBLISHED" -eq 0 ]]; then
  echo "Cannot read the published build number." >&2
  exit 1
fi
if [[ "$BUILD_NUMBER" -le "$PUBLISHED" ]]; then
  echo "BUILD_NUMBER=$BUILD_NUMBER must be greater than the published $PUBLISHED." >&2
  exit 1
fi
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  echo "Release $TAG already exists." >&2
  exit 1
fi

gh release create "$TAG" --repo "$REPOSITORY" --target "$COMMIT" --draft \
  --title "Ting ${MARKETING_VERSION}" --notes-file "$NOTES" \
  "$ZIP" "$SUMS" "$APPCAST"
gh release edit "$TAG" --repo "$REPOSITORY" --draft=false --latest

# The archive is public now: the site feed may point at it.
mkdir -p "$(dirname "$SITE_FEED")"
cp "$APPCAST" "$SITE_FEED"
echo "PUBLISHED: $TAG on GitHub Releases."
echo "FEED_READY: $SITE_FEED"
echo "Next: in $LANDING run npm run sync:github && npm run build && npm test, commit, push and npm run deploy."
