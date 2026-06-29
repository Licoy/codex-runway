#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s -v 0.0.4 [-p]\n' "$(basename "$0")" >&2
  exit 2
}

VERSION=""
PUSH=0

while getopts ":v:p" opt; do
  case "$opt" in
    v) VERSION="$OPTARG" ;;
    p) PUSH=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -eq 0 ]] || usage
[[ -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Version must use x.y.z format, got: %s\n' "$VERSION" >&2
  exit 2
}

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  printf 'Tracked working tree is not clean. Commit or stash changes first.\n' >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

PLIST="Resources/Info.plist"
TAG="v$VERSION"
CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"

if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
  printf 'Info.plist is already at %s.\n' "$VERSION" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  printf 'Local tag already exists: %s\n' "$TAG" >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1 &&
  git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  printf 'Remote tag already exists: %s\n' "$TAG" >&2
  exit 1
fi

IFS=. read -r MAJOR MINOR PATCH <<<"$VERSION"
BUILD=$((10#$MAJOR * 1000000 + 10#$MINOR * 1000 + 10#$PATCH))

VERSION="$VERSION" BUILD="$BUILD" perl -0pi -e '
  $short = s{(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)}{$1$ENV{VERSION}$2};
  $build = s{(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)}{$1$ENV{BUILD}$2};
  die "Missing version keys\n" unless $short && $build;
' "$PLIST"
plutil -lint "$PLIST" >/dev/null

git add "$PLIST"
git commit -m "chore(release): bump version to $VERSION"
git tag -a "$TAG" -m "Release $TAG"

if [[ "$PUSH" -eq 1 ]]; then
  BRANCH="$(git branch --show-current)"
  [[ -n "$BRANCH" ]] || {
    printf 'Cannot push from a detached HEAD.\n' >&2
    exit 1
  }

  git push origin "$BRANCH"
  git push origin "$TAG"
fi

printf 'Bumped to %s (build %s), committed and tagged %s.\n' "$VERSION" "$BUILD" "$TAG"
if [[ "$PUSH" -eq 0 ]]; then
  printf 'Push with: git push origin HEAD && git push origin %s\n' "$TAG"
fi
