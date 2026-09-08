#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
configuration="${CONFIGURATION:-Release}"
dist_dir="$repo_root/dist"
architectures=(arm64 x86_64)

"$repo_root/scripts/validate-version.sh" "v$version"
command -v xcodegen >/dev/null || { print -u2 "xcodegen is required."; exit 1; }

cd "$repo_root"
xcodegen generate
if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  swift test
fi

mkdir -p "$dist_dir"
for architecture in "${architectures[@]}"; do
  derived_data="$repo_root/DerivedData/Release-$architecture"
  archive_root="$dist_dir/Menu Hub-$version-$architecture"
  xcodebuild \
    -project MenuHub.xcodeproj \
    -scheme MenuHub \
    -configuration "$configuration" \
    -derivedDataPath "$derived_data" \
    -destination 'generic/platform=macOS' \
    ARCHS="$architecture" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

  app_path="$derived_data/Build/Products/$configuration/MenuHub.app"
  [[ -d "$app_path" ]] || { print -u2 "Built app not found: $app_path"; exit 1; }
  rm -rf "$archive_root"
  mkdir -p "$archive_root"
  ditto "$app_path" "$archive_root/Menu Hub.app"

  executable="$archive_root/Menu Hub.app/Contents/MacOS/MenuHub"
  [[ "$(lipo -archs "$executable")" == "$architecture" ]] || {
    print -u2 "Unexpected architecture for $executable: $(lipo -archs "$executable")"
    exit 1
  }
  print "Built $architecture app: $archive_root/Menu Hub.app"
done

if [[ "${BUILD_ONLY:-0}" != "1" ]]; then
  RELEASE_KIND="${RELEASE_KIND:-unsigned}" "$repo_root/scripts/package-release.sh"
  RELEASE_KIND="${RELEASE_KIND:-unsigned}" "$repo_root/scripts/validate-release-artifacts.sh"
fi
