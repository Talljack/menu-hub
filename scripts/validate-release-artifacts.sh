#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
dist_dir="$repo_root/dist"
release_kind="${RELEASE_KIND:-unsigned}"
expected_team_id="${EXPECTED_TEAM_ID:-636LV693YD}"
architectures=(arm64 x86_64)

case "$release_kind" in
  signed) suffix="" ;;
  unsigned) suffix="-UNSIGNED" ;;
  *) print -u2 "RELEASE_KIND must be signed or unsigned."; exit 1 ;;
esac

work_root="$(mktemp -d "$dist_dir/.validate-release.XXXXXX")"
mounted=""
cleanup() {
  if [[ -n "$mounted" ]]; then hdiutil detach "$mounted" -quiet || true; fi
  rm -rf "$work_root"
}
trap cleanup EXIT

validate_app() {
  local app="$1"
  local architecture="$2"
  local executable="$app/Contents/MacOS/MenuHub"
  [[ -d "$app" ]] || { print -u2 "Missing app: $app"; return 1; }
  [[ "$(lipo -archs "$executable")" == "$architecture" ]] || {
    print -u2 "Wrong architecture in $app: $(lipo -archs "$executable")"
    return 1
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]] || {
    print -u2 "Wrong bundle version in $app"
    return 1
  }
  if [[ "$release_kind" == signed ]]; then
    codesign --verify --deep --strict --verbose=2 "$app"
    local signature_details
    signature_details="$(codesign -d --verbose=4 "$app" 2>&1)"
    [[ "$signature_details" == *"TeamIdentifier=$expected_team_id"* ]] || {
      print -u2 "Unexpected signing Team ID in $app"
      return 1
    }
    [[ "$signature_details" == *"flags="*"runtime"* ]] || {
      print -u2 "Hardened Runtime is missing from $app"
      return 1
    }
    local entitlements
    entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"
    if [[ "$entitlements" == *"<key>com.apple.security.get-task-allow</key>"*"<true/>"* ]]; then
      print -u2 "Debug get-task-allow entitlement is enabled in $app"
      return 1
    fi
    spctl --assess --type execute --verbose=2 "$app"
  fi
}

for architecture in "${architectures[@]}"; do
  base="$dist_dir/Menu-Hub-$version-macos-$architecture$suffix"
  zip="$base.zip"
  dmg="$base.dmg"
  [[ -f "$zip" && -f "$dmg" && -f "$zip.sha256" && -f "$dmg.sha256" ]] || {
    print -u2 "Missing release artifacts for $architecture."
    exit 1
  }
  [[ "$(awk '{print $2}' "$zip.sha256")" == "${zip:t}" ]] || {
    print -u2 "ZIP checksum must use a portable basename for $architecture."
    exit 1
  }
  [[ "$(awk '{print $2}' "$dmg.sha256")" == "${dmg:t}" ]] || {
    print -u2 "DMG checksum must use a portable basename for $architecture."
    exit 1
  }
  (cd "$dist_dir" && shasum -a 256 -c "${zip:t}.sha256" -c "${dmg:t}.sha256")
  unzip -tq "$zip"
  extract="$work_root/zip-$architecture"
  mkdir -p "$extract"
  ditto -x -k "$zip" "$extract"
  validate_app "$extract/Menu Hub.app" "$architecture"

  mountpoint="$work_root/dmg-$architecture"
  mkdir -p "$mountpoint"
  hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$dmg" -quiet
  mounted="$mountpoint"
  validate_app "$mountpoint/Menu Hub.app" "$architecture"
  [[ -L "$mountpoint/Applications" && "$(readlink "$mountpoint/Applications")" == /Applications ]] || {
    print -u2 "DMG Applications shortcut is missing for $architecture."
    exit 1
  }
  hdiutil detach "$mountpoint" -quiet
  mounted=""
  print "Validated $architecture DMG and ZIP."
done
