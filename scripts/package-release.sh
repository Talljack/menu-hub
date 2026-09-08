#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
dist_dir="$repo_root/dist"
release_kind="${RELEASE_KIND:-unsigned}"
architectures=(arm64 x86_64)

case "$release_kind" in
  signed) suffix="" ;;
  unsigned) suffix="-UNSIGNED" ;;
  *) print -u2 "RELEASE_KIND must be signed or unsigned."; exit 1 ;;
esac

stage_root="$(mktemp -d "$dist_dir/.dmg-stage.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT

# Do not let artifacts from the retired Universal channel leak into a release
# when packaging is rerun in a non-clean local workspace.
rm -f "$dist_dir/Menu-Hub-$version-macos-universal.zip" \
  "$dist_dir/Menu-Hub-$version-macos-universal.zip.sha256" \
  "$dist_dir/Menu-Hub-$version-macos-universal.dmg" \
  "$dist_dir/Menu-Hub-$version-macos-universal.dmg.sha256"

for architecture in "${architectures[@]}"; do
  app="$dist_dir/Menu Hub-$version-$architecture/Menu Hub.app"
  executable="$app/Contents/MacOS/MenuHub"
  [[ -d "$app" ]] || { print -u2 "Built app not found: $app"; exit 1; }
  [[ "$(lipo -archs "$executable")" == "$architecture" ]] || {
    print -u2 "Expected $architecture executable at $executable."
    exit 1
  }

  base="$dist_dir/Menu-Hub-$version-macos-$architecture$suffix"
  zip="$base.zip"
  dmg="$base.dmg"
  rm -f "$zip" "$zip.sha256" "$dmg" "$dmg.sha256"

  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

  staging="$stage_root/$architecture"
  mkdir -p "$staging"
  ditto "$app" "$staging/Menu Hub.app"
  ln -s /Applications "$staging/Applications"
  hdiutil create \
    -volname "Menu Hub $version ($architecture)" \
    -srcfolder "$staging" \
    -ov \
    -format UDZO \
    "$dmg"

  (cd "$dist_dir" && shasum -a 256 "${zip:t}" > "${zip:t}.sha256")
  (cd "$dist_dir" && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
  print "Packaged $architecture: ${zip:t} and ${dmg:t}"
done
