#!/usr/bin/env bash
# Render the cask from an immutable release archive; --publish updates the tap.
# Safe to rerun independently if publishing the tap failed after a release.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source version.env
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --publish ) ]]; then
  echo "Usage: Scripts/update_homebrew.sh [--publish]" >&2
  exit 1
fi
[[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version." >&2; exit 1; }
ARCHIVE="Ting-${MARKETING_VERSION}-universal.zip"
ZIP="dist/$ARCHIVE"
[[ -f "$ZIP" ]] || { echo "Missing $ZIP." >&2; exit 1; }
SHA256=$(shasum -a 256 "$ZIP" | cut -d ' ' -f1)
CASK=$(printf '%s\n' \
  'cask "ting" do' \
  "  version \"$MARKETING_VERSION\"" \
  "  sha256 \"$SHA256\"" \
  '' \
  '  url "https://github.com/bobuk-io/ting/releases/download/v#{version}/Ting-#{version}-universal.zip"' \
  '  name "Ting"' \
  '  desc "Leader-key launcher for apps and URLs"' \
  '  homepage "https://bobuk.io/apps/ting/"' \
  '' \
  '  livecheck do' \
  '    url :url' \
  '    strategy :github_latest' \
  '  end' \
  '' \
  '  auto_updates true' \
  '  depends_on macos: :sonoma' \
  '' \
  '  app "Ting.app"' \
  '' \
  '  zap trash: [' \
  '    "~/.config/ting",' \
  '    "~/Library/Application Support/Ting",' \
  '    "~/Library/Caches/io.bobuk.ting",' \
  '    "~/Library/Preferences/io.bobuk.ting.plist",' \
  '    "~/Library/Saved Application State/io.bobuk.ting.savedState",' \
  '  ]' \
  'end')
if [[ "${1:-}" != --publish ]]; then
  printf '%s\n' "$CASK"
  exit 0
fi

# Do not point Homebrew at a draft, prerelease, missing or mismatched archive.
RELEASE=$(gh api "repos/bobuk-io/ting/releases/tags/v${MARKETING_VERSION}")
printf '%s' "$RELEASE" | jq -e --arg name "$ARCHIVE" --arg digest "sha256:$SHA256" \
  '.draft == false and .prerelease == false and any(.assets[]; .name == $name and .digest == $digest)' >/dev/null || {
  echo "The published release does not match $ZIP." >&2
  exit 1
}
ENDPOINT="repos/bobuk-io/homebrew-tap/contents/Casks/ting.rb"
EXISTING=$(gh api "$ENDPOINT")
CONTENT=$(printf '%s\n' "$CASK" | base64 | tr -d '\n')
if [[ "$(printf '%s' "$EXISTING" | jq -r '.content' | tr -d '\n')" == "$CONTENT" ]]; then
  echo "Homebrew cask is already up to date."
  exit 0
fi
printf '%s' "$EXISTING" | jq --arg content "$CONTENT" --arg version "$MARKETING_VERSION" \
  '{message: ("chore(ting): update cask to " + $version), content: $content, sha: .sha}' |
  gh api --method PUT "$ENDPOINT" --input - >/dev/null
echo "HOMEBREW_UPDATED: bobuk-io/tap/ting $MARKETING_VERSION"
