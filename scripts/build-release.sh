#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
configuration="${CONFIGURATION:-Release}"
derived_data="$repo_root/DerivedData/Release"
dist_dir="$repo_root/dist"
archive_root="$dist_dir/Menu Hub-$version"

"$repo_root/scripts/validate-version.sh" "v$version"
command -v xcodegen >/dev/null || { print -u2 "xcodegen is required."; exit 1; }

cd "$repo_root"
xcodegen generate
if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  swift test
fi

xcodebuild \
  -project MenuHub.xcodeproj \
  -scheme MenuHub \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

app_path="$derived_data/Build/Products/$configuration/MenuHub.app"
[[ -d "$app_path" ]] || { print -u2 "Built app not found: $app_path"; exit 1; }

mkdir -p "$dist_dir"
rm -rf "$archive_root"
mkdir -p "$archive_root"
ditto "$app_path" "$archive_root/Menu Hub.app"

if [[ "${BUILD_ONLY:-0}" != "1" ]]; then
  artifact="$dist_dir/Menu-Hub-$version-macos-universal.zip"
  rm -f "$artifact" "$artifact.sha256"
  ditto -c -k --sequesterRsrc --keepParent "$archive_root/Menu Hub.app" "$artifact"
  shasum -a 256 "$artifact" > "$artifact.sha256"
  print "Release artifact: $artifact"
fi

print "Built app: $archive_root/Menu Hub.app"
