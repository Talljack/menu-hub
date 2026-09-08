#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
project_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\([^"]*\)"/\1/p' "$repo_root/project.yml" | head -1)"

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "VERSION must use semantic X.Y.Z format: $version"
  exit 1
fi

if [[ -z "$version" || "$version" != "$project_version" ]]; then
  print -u2 "VERSION ($version) does not match project.yml MARKETING_VERSION ($project_version)."
  exit 1
fi

if [[ $# -gt 0 ]]; then
  tag="${1#refs/tags/}"
  if [[ "$tag" != "v$version" ]]; then
    print -u2 "Tag $tag must match v$version."
    exit 1
  fi
fi

print "Menu Hub version $version is consistent."
