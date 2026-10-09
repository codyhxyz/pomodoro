#!/bin/bash
# Xcode Cloud: after a Developer ID archive is exported and notarized, wrap it in a
# DMG installer and, when GITHUB_TOKEN is set as a workflow secret, attach it to the
# GitHub release for the tag that triggered the build.
set -euo pipefail

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ] || [ -z "${CI_DEVELOPER_ID_SIGNED_APP_PATH:-}" ]; then
  echo "No Developer ID export in this action; skipping DMG."
  exit 0
fi

app="$(find "$CI_DEVELOPER_ID_SIGNED_APP_PATH" -maxdepth 1 -name '*.app' | head -1)"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
dmg="$CI_DERIVED_DATA_PATH/PomodoroOverlay-$version.dmg"
"$CI_PRIMARY_REPOSITORY_PATH/scripts/make-dmg.sh" "$app" "$dmg"
xcrun stapler staple "$dmg" || true

if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${CI_TAG:-}" ]; then
  repo="codyhxyz/pomodoro"
  api="https://api.github.com/repos/$repo"
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json")
  release_id="$(curl -fsS "${auth[@]}" "$api/releases/tags/$CI_TAG" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' 2>/dev/null \
    || curl -fsS "${auth[@]}" -X POST "$api/releases" -d "{\"tag_name\":\"$CI_TAG\",\"name\":\"$CI_TAG\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  curl -fsS "${auth[@]}" -H "Content-Type: application/octet-stream" \
    --data-binary @"$dmg" "https://uploads.github.com/repos/$repo/releases/$release_id/assets?name=$(basename "$dmg")" >/dev/null
  echo "Uploaded $(basename "$dmg") to $CI_TAG"
fi
