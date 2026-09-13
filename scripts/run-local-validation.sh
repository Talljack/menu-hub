#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
destination="${XCODE_DESTINATION:-platform=macOS,arch=$(uname -m)}"

cd "$repo_root"
command -v xcodegen >/dev/null || { print -u2 "xcodegen is required."; exit 1; }

print "Generating the Xcode project..."
xcodegen generate

print "Running Swift package tests..."
swift test

print "Running Xcode unit and integration tests..."
xcodebuild test \
  -project MenuHub.xcodeproj \
  -scheme MenuHub \
  -destination "$destination" \
  -skip-testing:MenuHubUITests \
  CODE_SIGNING_ALLOWED=NO

if ! security find-identity -v -p codesigning | rg -q 'Apple Development:'; then
  print -u2 "An Apple Development signing identity is required to launch MenuHubUITests."
  exit 1
fi

print "Running signed macOS UI tests..."
xcodebuild test \
  -project MenuHub.xcodeproj \
  -scheme MenuHub \
  -destination "$destination" \
  -only-testing:MenuHubUITests

print "Local validation passed."
