#!/usr/bin/env bash
# Offline tests of Scripts/release_next.sh: a temporary ting tree and landing checkout with
# local bare origins, stub release scripts and mock gh, npm and curl. Never touches the real
# repository, GitHub, the tap, the landing site or /Applications.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_GIT=$(command -v git)
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$HOME" "$TMP/bin"
printf '[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' > "$GIT_CONFIG_GLOBAL"
export STATE="$TMP/state" TING_FEED_URL=https://feed.invalid/appcast.xml TING_FEED_WAIT=0 TING_FEED_INTERVAL=0
export REAL_GIT
# Inherited Git locations or configuration must not lead the test into a real repository.
unset $("$REAL_GIT" rev-parse --local-env-vars) GIT_CONFIG_SYSTEM
# A sentinel landing checkout: an inherited LANDING must never be used.
SENTINEL="$TMP/sentinel"
"$REAL_GIT" init -q --bare "$SENTINEL.git"
(cd "$TMP" && "$REAL_GIT" clone -q "$SENTINEL.git" sentinel 2>/dev/null && cd sentinel \
  && "$REAL_GIT" commit -q --allow-empty -m sentinel && "$REAL_GIT" push -q origin main)
SENTINEL_HEAD=$("$REAL_GIT" -C "$SENTINEL" rev-parse HEAD)
export LANDING="$SENTINEL"

# Mocks record their calls in $STATE/calls.log.
cat > "$TMP/bin/git" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in commit|push) echo "git[$(basename "$PWD")] $*" >> "$STATE/calls.log" ;; esac
exec "$REAL_GIT" "$@"
MOCK
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "gh $*" >> "$STATE/calls.log"
[[ ! -e "$STATE/gh_fail" ]] || { echo 'gh: network error' >&2; exit 1; }
[[ $# -eq 5 && "$1 $2 $3 $4" == 'api --paginate repos/bobuk-io/ting/releases?per_page=100 --jq' ]] \
  || { echo "Unexpected gh call: $*" >&2; exit 1; }
# releases.json holds the pages of the API; --paginate applies the filter to each page.
jq -c '.[]' "$STATE/releases.json" | while IFS= read -r page; do jq -r "$5" <<<"$page"; done
MOCK
cat > "$TMP/bin/npm" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "npm $*" >> "$STATE/calls.log"
# The deploy makes the site feed live.
if [[ "$*" == 'run deploy' ]]; then cp public/apps/ting/appcast.xml "$STATE/live.xml"; fi
MOCK
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
echo "curl ${*: -1}" >> "$STATE/calls.log"
[[ ! -e "$STATE/curl_fail" ]] || exit 22
cat "$STATE/live.xml"
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"

feed() { printf '<rss><item><sparkle:version>%s</sparkle:version></item></rss>\n' "$1"; }

# A fresh world: ting 0.7.4 (build 19), release v0.7.4 draft state $1 (empty: none), live feed build $2.
setup() {
  rm -rf "$TMP/w" "$STATE"
  mkdir -p "$TMP/w" "$STATE"
  : > "$STATE/calls.log"
  if [[ -n "$1" ]]; then
    jq -n --argjson draft "$1" '[[{tag_name:"v0.7.4",draft:$draft}]]' > "$STATE/releases.json"
  else
    echo '[[]]' > "$STATE/releases.json"
  fi
  feed "$2" > "$STATE/live.xml"
  TING="$TMP/w/ting" LAND="$TMP/w/landing"
  export LANDING="$LAND"
  mkdir -p "$TING/Scripts" "$TING/Sources/TingCore" "$TING/docs/releases"
  cp "$ROOT/Scripts/release_next.sh" "$TING/Scripts/"
  cat > "$TING/Scripts/release.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "release.sh $*" >> "$STATE/calls.log"
[[ ! -e "$STATE/release_fail" ]] || { echo 'Notarization was not accepted (Invalid).' >&2; exit 1; }
source version.env
mkdir -p dist
echo "archive $MARKETING_VERSION" > "dist/Ting-${MARKETING_VERSION}-universal.zip"
(cd dist && shasum -a 256 "Ting-${MARKETING_VERSION}-universal.zip" > SHA256SUMS.txt)
printf '<rss><item><sparkle:version>%s</sparkle:version></item></rss>\n' "$BUILD_NUMBER" > dist/appcast.xml
STUB
  cat > "$TING/Scripts/publish.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "publish.sh $*" >> "$STATE/calls.log"
[[ "$(git rev-parse HEAD)" == "$(git ls-remote origin refs/heads/main | cut -f1)" ]] || { echo 'not pushed' >&2; exit 1; }
cp dist/appcast.xml "$LANDING/public/apps/ting/appcast.xml"
source version.env
jq --arg tag "v$MARKETING_VERSION" '[[{tag_name:$tag,draft:false}]] + .' "$STATE/releases.json" > "$STATE/releases.new"
mv "$STATE/releases.new" "$STATE/releases.json"
STUB
  cat > "$TING/Scripts/update_homebrew.sh" <<'STUB'
#!/usr/bin/env bash
echo "update_homebrew.sh $*" >> "$STATE/calls.log"
STUB
  printf '# Version.\nMARKETING_VERSION=0.7.4\nBUILD_NUMBER=19\n' > "$TING/version.env"
  printf 'public enum TingVersion {\n    public static let marketing = "0.7.4"\n}\n' \
    > "$TING/Sources/TingCore/TingVersion.swift"
  echo 'Notes of 0.7.4.' > "$TING/docs/releases/v0.7.4.md"
  printf 'dist/\n' > "$TING/.gitignore"
  mkdir -p "$LAND/public/apps/ting"
  feed "$2" > "$LAND/public/apps/ting/appcast.xml"
  local repo
  for repo in "$TING" "$LAND"; do
    "$REAL_GIT" init -q --bare "$repo.git"
    (cd "$repo" && "$REAL_GIT" init -q && "$REAL_GIT" add -A && "$REAL_GIT" commit -qm init \
      && "$REAL_GIT" remote add origin "$repo.git" && "$REAL_GIT" push -q origin main)
  done
  # A Ticket merged locally, not pushed yet: main is ahead of origin.
  (cd "$TING" && echo change > feature.txt && "$REAL_GIT" add feature.txt && "$REAL_GIT" commit -qm feature)
}
notes() { echo "Notes of $1." > "$TING/docs/releases/v$1.md"; }
run() { (cd "$TING" && LANDING="$LAND" APP_IDENTITY="${APP_IDENTITY-Developer ID Application: Test}" \
  NOTARY_PROFILE="${NOTARY_PROFILE-test}" bash Scripts/release_next.sh "$@" >"$STATE/out" 2>"$STATE/err"); }
fail() { echo "FAIL: $*" >&2; echo '--- stdout' >&2; cat "$STATE/out" >&2; echo '--- stderr' >&2; cat "$STATE/err" >&2
  echo '--- calls' >&2; cat "$STATE/calls.log" >&2; exit 1; }
version_is() { grep -qx "MARKETING_VERSION=$1" "$TING/version.env" && grep -qx "BUILD_NUMBER=$2" "$TING/version.env" \
  && grep -q "marketing = \"$1\"" "$TING/Sources/TingCore/TingVersion.swift"; }
snapshot() {
  SNAP_TING=$(cd "$TING" && "$REAL_GIT" rev-parse HEAD) SNAP_TING_ORIGIN=$("$REAL_GIT" -C "$TING.git" rev-parse main)
  SNAP_LAND=$(cd "$LAND" 2>/dev/null && "$REAL_GIT" rev-parse HEAD || true)
  SNAP_FILES=$(cat "$TING/version.env" "$TING/Sources/TingCore/TingVersion.swift")
}
# The run stopped with a message matching $1 and changed nothing.
stopped() {
  if run "${@:2}"; then fail "accepted: $1"; fi
  grep -q -- "$1" "$STATE/err" || fail "no message '$1'"
  [[ "$(cat "$TING/version.env" "$TING/Sources/TingCore/TingVersion.swift")" == "$SNAP_FILES" ]] || fail "version changed: $1"
  [[ "$(cd "$TING" && "$REAL_GIT" rev-parse HEAD)" == "$SNAP_TING" ]] || fail "ting commit: $1"
  [[ "$("$REAL_GIT" -C "$TING.git" rev-parse main)" == "$SNAP_TING_ORIGIN" ]] || fail "ting push: $1"
  [[ "$(cd "$LAND" 2>/dev/null && "$REAL_GIT" rev-parse HEAD || true)" == "$SNAP_LAND" ]] || fail "landing commit: $1"
  if [[ -d "$LAND" && -z "${LANDING_DIRTY:-}" ]]; then
    [[ -z "$(cd "$LAND" && "$REAL_GIT" status --porcelain)" ]] || fail "landing changed: $1"
  fi
  ! grep -Eq '^(release\.sh|publish\.sh|update_homebrew|npm|git)' "$STATE/calls.log" || fail "a step ran: $1"
}
# The recorded calls hold these lines in this order.
in_order() {
  local pattern line=0 found
  for pattern in "$@"; do
    found=$(tail -n "+$((line + 1))" "$STATE/calls.log" | grep -n -m1 -E -- "$pattern" | cut -d: -f1) \
      || fail "missing in order: $pattern"
    line=$((line + found))
  done
}

# 1. Any argument: usage, non-zero, no change.
setup false 19; notes 0.7.5; snapshot
stopped 'Usage: Scripts/release_next.sh' --dry-run
[[ ! -s "$STATE/calls.log" ]] || fail 'argument run called a command'

# 4. A missing APP_IDENTITY or NOTARY_PROFILE is named.
APP_IDENTITY='' stopped 'Set APP_IDENTITY'
NOTARY_PROFILE='' stopped 'Set NOTARY_PROFILE'

# 3. Missing or empty notes of the next version.
rm "$TING/docs/releases/v0.7.5.md"
stopped 'docs/releases/v0.7.5.md first'
: > "$TING/docs/releases/v0.7.5.md"
stopped 'docs/releases/v0.7.5.md are empty'

# 9. Other stops before any change.
notes 0.7.5; echo x > "$TING/other.txt"
stopped 'change of other.txt'
rm "$TING/other.txt"
echo y >> "$TING/version.env"; snapshot
stopped 'change of version.env'
setup false 19; notes 0.7.5
(cd "$TING" && "$REAL_GIT" push -q origin main && "$REAL_GIT" reset -q --hard HEAD~1); snapshot
stopped 'behind or diverged'
(cd "$TING" && echo other > other.txt && "$REAL_GIT" add other.txt && "$REAL_GIT" commit -qm other); snapshot
stopped 'behind or diverged'
setup false 19; notes 0.7.5; rm -rf "$LAND"; snapshot
stopped 'No landing checkout'
setup false 19; notes 0.7.5; echo draft > "$LAND/draft.txt"; snapshot
LANDING_DIRTY=1 stopped 'change of draft.txt in'
setup true 19; notes 0.7.5; snapshot
stopped 'draft release v0.7.4'
setup false 19; notes 0.7.5; touch "$STATE/gh_fail"; snapshot
stopped 'Cannot read the GitHub releases'
setup false 19; notes 0.7.5; touch "$STATE/curl_fail"; snapshot
stopped 'Cannot read the live feed'

# A draft or a published current release beyond the first page of the API is found.
others() { jq -n '[range(100) | {tag_name: "v0.0.\(.)", draft: false}]'; }
setup true 19; notes 0.7.5
jq --argjson others "$(others)" '[$others] + .' "$STATE/releases.json" > "$STATE/r" && mv "$STATE/r" "$STATE/releases.json"
snapshot
stopped 'draft release v0.7.4'
setup false 19; notes 0.7.5
jq --argjson others "$(others)" '[$others] + .' "$STATE/releases.json" > "$STATE/r" && mv "$STATE/r" "$STATE/releases.json"
run || fail 'run with the release on page 2 failed'
grep -q 'mode new' "$STATE/out" || fail 'release on page 2 not found'
version_is 0.7.5 20 || fail 'release on page 2: version not raised'

setup false 19; notes 0.7.5
jq '. + .' "$STATE/releases.json" > "$STATE/r" && mv "$STATE/r" "$STATE/releases.json"; snapshot
stopped 'More than one GitHub release has the tag v0.7.4'

# 2 and 5. A full new release, in order.
setup false 19; notes 0.7.5
run || fail 'good run failed'
version_is 0.7.5 20 || fail 'version not raised to 0.7.5 (build 20)'
in_order '^release\.sh' '^git\[ting\] commit --quiet -m Release Ting 0\.7\.5$' '^git\[ting\] push origin main$' \
  '^publish\.sh' '^npm run sync:github$' '^npm run build$' '^npm test$' \
  '^git\[landing\] commit --quiet -m Ting 0\.7\.5: update feed$' '^git\[landing\] push origin main$' \
  '^npm run deploy$' '^curl https://feed\.invalid/appcast\.xml'
[[ "$(tail -1 "$STATE/out")" == 'RELEASE_DONE: Ting 0.7.5 (build 20)' ]] || fail 'last line'
[[ "$(cd "$TING" && "$REAL_GIT" show --name-only --format= HEAD | sort | tr '\n' ' ')" == \
  'Sources/TingCore/TingVersion.swift docs/releases/v0.7.5.md version.env ' ]] || fail 'release commit files'
[[ "$(cd "$TING" && "$REAL_GIT" rev-parse HEAD)" == "$("$REAL_GIT" -C "$TING.git" rev-parse main)" ]] || fail 'ting not pushed'
[[ "$(cd "$LAND" && "$REAL_GIT" rev-parse HEAD)" == "$("$REAL_GIT" -C "$LAND.git" rev-parse main)" ]] || fail 'landing not pushed'
grep -q 'sparkle:version>20<' "$STATE/live.xml" || fail 'feed not deployed'

# 6. A failing release.sh: no commit, no push, no publish, the raised version stays.
setup false 19; notes 0.7.5; snapshot; touch "$STATE/release_fail"
if run; then fail 'accepted failing release.sh'; fi
grep -q 'Notarization was not accepted' "$STATE/err" || fail 'message of release.sh'
version_is 0.7.5 20 || fail 'raised version lost'
[[ "$(cd "$TING" && "$REAL_GIT" rev-parse HEAD)" == "$SNAP_TING" ]] || fail 'commit after failure'
[[ "$("$REAL_GIT" -C "$TING.git" rev-parse main)" == "$SNAP_TING_ORIGIN" ]] || fail 'push after failure'
! grep -Eq '^(publish\.sh|npm|git)' "$STATE/calls.log" || fail 'a step ran after failure'

# 7. The next run goes on with the same version.
rm "$STATE/release_fail"; : > "$STATE/calls.log"
run || fail 'second run failed'
version_is 0.7.5 20 || fail 'second run raised the version again'
grep -q 'mode build' "$STATE/out" || fail 'second run mode'
in_order '^release\.sh' '^git\[ting\] commit --quiet -m Release Ting 0\.7\.5$' '^publish\.sh' '^npm run deploy$'
[[ "$(tail -1 "$STATE/out")" == 'RELEASE_DONE: Ting 0.7.5 (build 20)' ]] || fail 'second run last line'

# 8. The tail: published, the live feed lacks the build.
setup false 18
(cd "$TING" && bash Scripts/release.sh) && : > "$STATE/calls.log"
# publish.sh had already copied the appcast: that one landing change is allowed.
cp "$TING/dist/appcast.xml" "$LAND/public/apps/ting/appcast.xml"
run || fail 'tail run failed'
version_is 0.7.4 19 || fail 'tail raised the version'
! grep -Eq '^(release|publish)\.sh' "$STATE/calls.log" || fail 'tail built or published'
cmp -s "$TING/dist/appcast.xml" "$STATE/live.xml" || fail 'tail did not deploy the appcast'
in_order '^update_homebrew\.sh --publish$' '^npm run sync:github$' '^npm run build$' '^npm test$' \
  '^git\[landing\] commit --quiet -m Ting 0\.7\.4: update feed$' '^git\[landing\] push origin main$' '^npm run deploy$'
[[ "$(cd "$LAND" && "$REAL_GIT" show HEAD:public/apps/ting/appcast.xml)" == "$(cat "$TING/dist/appcast.xml")" ]] \
  || fail 'appcast not committed in landing'
[[ "$(tail -1 "$STATE/out")" == 'RELEASE_DONE: Ting 0.7.4 (build 19)' ]] || fail 'tail last line'

# The tail stops when the manifest does not list this archive or its digest differs.
setup false 18; (cd "$TING" && bash Scripts/release.sh) && : > "$STATE/calls.log"
echo other > "$TING/dist/other.txt"
(cd "$TING/dist" && shasum -a 256 other.txt > SHA256SUMS.txt); snapshot
stopped 'has no entry for Ting-0.7.4-universal.zip'
(cd "$TING/dist" && shasum -a 256 Ting-0.7.4-universal.zip other.txt > SHA256SUMS.txt)
echo corrupted >> "$TING/dist/Ting-0.7.4-universal.zip"
stopped 'does not match dist/Ting-0.7.4-universal.zip'

# The tail stops on a dirty ting tree, and a feed that never goes live fails the run.
setup false 18; (cd "$TING" && bash Scripts/release.sh) && : > "$STATE/calls.log"
echo x >> "$TING/docs/releases/v0.7.4.md"; snapshot
stopped 'change of docs/releases/v0.7.4.md'
git -C "$TING" checkout -q -- docs/releases/v0.7.4.md; echo draft > "$LAND/draft.txt"; snapshot
LANDING_DIRTY=1 stopped 'change of draft.txt in'
setup false 19; notes 0.7.5
# npm without a working deploy.
printf '%s\n' '#!/usr/bin/env bash' 'echo "npm $*" >> "$STATE/calls.log"' > "$TMP/bin/npm"
if run; then fail 'accepted a feed that never went live'; fi
grep -q 'still has no build 20' "$STATE/err" || fail 'feed timeout message'

[[ "$("$REAL_GIT" -C "$SENTINEL" rev-parse HEAD)" == "$SENTINEL_HEAD" \
  && "$("$REAL_GIT" -C "$SENTINEL.git" rev-parse main)" == "$SENTINEL_HEAD" \
  && -z "$("$REAL_GIT" -C "$SENTINEL" status --porcelain)" ]] || fail 'the inherited LANDING checkout was touched'

echo 'release_next tests passed.'
