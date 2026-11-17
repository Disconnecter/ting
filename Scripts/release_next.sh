#!/usr/bin/env bash
# Release the next patch version of Ting with one command and no arguments: raise the
# version, run Scripts/release.sh, commit and push main, run Scripts/publish.sh, then build,
# commit, push and deploy the landing site and wait until the live feed has the new build.
# The mode comes from facts, never from a state file, so a failed run is started again
# with the same command:
#   new release  - vV is published and the live feed has build B: raise to the next version;
#   build        - there is no GitHub release vV: release V again from Scripts/release.sh;
#   tail         - vV is published but the live feed lacks build B: only the steps after
#                  the GitHub release (site feed, Homebrew cask, landing site) run.
# All checks that can fail run before the first change of any file.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
REPOSITORY=bobuk-io/ting
FEED_URL=${TING_FEED_URL:-https://bobuk.io/apps/ting/appcast.xml}
FEED_WAIT=${TING_FEED_WAIT:-120}
FEED_INTERVAL=${TING_FEED_INTERVAL:-10}
LANDING=${LANDING:-"$ROOT/../landing"}
VERSION_FILE=version.env
SWIFT_VERSION_FILE=Sources/TingCore/TingVersion.swift

die() { echo "release_next: $*" >&2; exit 1; }

if [[ $# -gt 0 ]]; then
  echo "Usage: Scripts/release_next.sh (it takes no arguments)" >&2
  exit 2
fi
[[ -n "${APP_IDENTITY:-}" ]] || die "Set APP_IDENTITY to a Developer ID Application signing identity."
[[ -n "${NOTARY_PROFILE:-}" ]] || die "Set NOTARY_PROFILE to a saved notarytool Keychain profile."
for tool in gh git npm curl; do
  command -v "$tool" >/dev/null || die "The command $tool is required."
done

# Read the version without sourcing anything else from the file.
CURRENT_VERSION=$(sed -n -E 's/^MARKETING_VERSION=([^[:space:]]*)$/\1/p' "$VERSION_FILE")
CURRENT_BUILD=$(sed -n -E 's/^BUILD_NUMBER=([^[:space:]]*)$/\1/p' "$VERSION_FILE")
[[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION in $VERSION_FILE is not X.Y.Z."
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || die "BUILD_NUMBER in $VERSION_FILE is not a number."
grep -q "marketing = \"${CURRENT_VERSION}\"" "$SWIFT_VERSION_FILE" \
  || die "$SWIFT_VERSION_FILE does not hold version $CURRENT_VERSION of $VERSION_FILE."

[[ "$(git symbolic-ref --short -q HEAD || true)" == main ]] || die "Check out branch main of ting."
git fetch --quiet origin
git merge-base --is-ancestor origin/main HEAD \
  || die "main is behind or diverged from origin/main; bring it up to date first."

[[ -d "$LANDING" ]] || die "No landing checkout at $LANDING; set LANDING to its checkout."
LANDING=$(cd "$LANDING" && pwd -P)
[[ "$(cd "$LANDING" && git rev-parse --show-toplevel 2>/dev/null || true)" == "$LANDING" ]] \
  || die "$LANDING is not a git checkout."
[[ "$(cd "$LANDING" && git symbolic-ref --short -q HEAD || true)" == main ]] \
  || die "Check out branch main in $LANDING."

# The GitHub release state of vV: empty (none), true (draft) or false (published).
TAG="v${CURRENT_VERSION}"
RELEASE_STATE=$(gh release list --repo "$REPOSITORY" --limit 100 --json tagName,isDraft \
  --jq ".[] | select(.tagName == \"$TAG\") | .isDraft") \
  || die "Cannot read the GitHub releases of $REPOSITORY."
FEED=$(curl -fsSL --max-time 30 "$FEED_URL?v=$(date +%s)") || die "Cannot read the live feed $FEED_URL."
grep -q 'sparkle:version>[0-9]*<' <<<"$FEED" || die "The live feed $FEED_URL has no build number."
FEED_HAS_BUILD=false
if grep -q "sparkle:version>${CURRENT_BUILD}<" <<<"$FEED"; then FEED_HAS_BUILD=true; fi

case "$RELEASE_STATE" in
  true) die "A draft release $TAG exists; publish or delete it first." ;;
  false)
    if [[ "$FEED_HAS_BUILD" == true ]]; then MODE=new; else MODE=tail; fi ;;
  '') MODE=build ;;
  *) die "Unexpected GitHub release state of $TAG: $RELEASE_STATE" ;;
esac

if [[ "$MODE" == new ]]; then
  IFS=. read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"
  VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
  BUILD=$((CURRENT_BUILD + 1))
else
  VERSION=$CURRENT_VERSION
  BUILD=$CURRENT_BUILD
fi
NOTES="docs/releases/v${VERSION}.md"
echo "release_next: mode $MODE, Ting $VERSION (build $BUILD)."

# The ting tree may hold only the files of this release.
case "$MODE" in
  new) ALLOWED=("$NOTES") ;;
  build) ALLOWED=("$VERSION_FILE" "$SWIFT_VERSION_FILE" "$NOTES") ;;
  tail) ALLOWED=() ;;
esac
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  path=${line:3}
  ok=false
  for allowed in ${ALLOWED[@]+"${ALLOWED[@]}"}; do [[ "$path" == "$allowed" ]] && ok=true; done
  [[ "$ok" == true ]] || die "Commit or remove the change of $path in ting first."
done < <(git status --porcelain=v1 -uall)

[[ -f "$NOTES" ]] || die "Write the release notes $NOTES first."
grep -q '[^[:space:]]' "$NOTES" || die "The release notes $NOTES are empty."

SITE_FEED_PATH=public/apps/ting/appcast.xml
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  path=${line:3}
  [[ "$MODE" == tail && "$path" == "$SITE_FEED_PATH" ]] && continue
  die "Commit or remove the change of $path in $LANDING first."
done < <(cd "$LANDING" && git status --porcelain=v1 -uall)

if [[ "$MODE" == tail ]]; then
  ZIP="dist/Ting-${VERSION}-universal.zip"
  for file in "$ZIP" dist/SHA256SUMS.txt dist/appcast.xml; do
    [[ -f "$file" ]] || die "Missing $file of the published release $TAG."
  done
  grep -q "sparkle:version>${BUILD}<" dist/appcast.xml || die "dist/appcast.xml is not for build $BUILD."
  (cd dist && shasum -a 256 -c SHA256SUMS.txt >/dev/null) || die "dist/SHA256SUMS.txt does not match the archive."
fi

# The checks are done: from here on, files change.
export LANDING
if [[ "$MODE" == new ]]; then
  sed -i '' -E "s/^MARKETING_VERSION=.*/MARKETING_VERSION=${VERSION}/; s/^BUILD_NUMBER=.*/BUILD_NUMBER=${BUILD}/" "$VERSION_FILE"
  sed -i '' -E "s/(marketing = \")[^\"]*(\")/\1${VERSION}\2/" "$SWIFT_VERSION_FILE"
  grep -qx "MARKETING_VERSION=${VERSION}" "$VERSION_FILE" && grep -qx "BUILD_NUMBER=${BUILD}" "$VERSION_FILE" \
    || die "Could not raise the version in $VERSION_FILE."
  grep -q "marketing = \"${VERSION}\"" "$SWIFT_VERSION_FILE" || die "Could not raise the version in $SWIFT_VERSION_FILE."
  echo "release_next: raised the version to $VERSION (build $BUILD)."
fi

if [[ "$MODE" == tail ]]; then
  mkdir -p "$LANDING/$(dirname "$SITE_FEED_PATH")"
  cp dist/appcast.xml "$LANDING/$SITE_FEED_PATH"
  bash "$ROOT/Scripts/update_homebrew.sh" --publish
else
  bash "$ROOT/Scripts/release.sh"
  git add -- "$VERSION_FILE" "$SWIFT_VERSION_FILE" "$NOTES"
  if ! git diff --cached --quiet; then git commit --quiet -m "Release Ting ${VERSION}"; fi
  git push origin main
  bash "$ROOT/Scripts/publish.sh"
fi

# The landing site serves the feed of installed copies.
(
  cd "$LANDING"
  npm run sync:github
  npm run build
  npm test
  git add -A
  if ! git diff --cached --quiet; then git commit --quiet -m "Ting ${VERSION}: update feed"; fi
  git push origin main
  npm run deploy
)

DEADLINE=$((SECONDS + FEED_WAIT))
while true; do
  LIVE=$(curl -fsSL --max-time 30 "$FEED_URL?v=$(date +%s)" 2>/dev/null || true)
  grep -q "sparkle:version>${BUILD}<" <<<"$LIVE" && break
  ((SECONDS < DEADLINE)) || die "The live feed $FEED_URL still has no build $BUILD after ${FEED_WAIT}s."
  sleep "$FEED_INTERVAL"
done
echo "RELEASE_DONE: Ting ${VERSION} (build ${BUILD})"
