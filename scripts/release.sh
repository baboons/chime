#!/usr/bin/env bash
# Cuts a release: bumps the version, commits, tags and pushes. The tag push
# makes CI build, sign and publish it.
#
#   scripts/release.sh 0.2.0
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh <major.minor.patch>"
cd "$(dirname "$0")/.."

[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "releases are cut from main"
if ! git diff --quiet || ! git diff --cached --quiet; then die "commit or stash your changes first"; fi
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main isn't in sync with origin/main"
! git rev-parse -q --verify "refs/tags/v$version" > /dev/null || die "v$version already exists"

current="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
echo "Releasing $current → $version"

/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" Resources/Info.plist
# Only the [package] version, the first `version =` line.
sed -i '' -E "1,/^version = /s/^version = \".*\"/version = \"$version\"/" core/Cargo.toml
cargo metadata --format-version 1 --manifest-path core/Cargo.toml > /dev/null # refreshes Cargo.lock

git add Resources/Info.plist core/Cargo.toml core/Cargo.lock
# Releasing the version already in the tree (the first release) has nothing to commit.
git diff --cached --quiet || git commit -m "release: v$version"
git tag -a "v$version" -m "Chime $version"
git push origin main "v$version"

echo "Pushed v$version. CI builds and publishes it: https://github.com/baboons/chime/actions"
