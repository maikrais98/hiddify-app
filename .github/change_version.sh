#!/usr/bin/env bash
set -euo pipefail

SED() { [[ "${OSTYPE:-}" == "darwin"* ]] && sed -i '' "$@" || sed -i "$@"; }

current_version=$(sed -E -n 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/\1/p' pubspec.yaml)
current_build=$(sed -E -n 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/\2/p' pubspec.yaml)
[[ -n "$current_version" && -n "$current_build" ]] || { echo "Unable to read current version" >&2; exit 1; }

MARKETING_VERSION=${1:-}
BUILD_NUMBER=${2:-}
[[ -n "$MARKETING_VERSION" ]] || read -r -p "Marketing version (x.y.z): " MARKETING_VERSION
[[ -n "$BUILD_NUMBER" ]] || read -r -p "Build number (positive integer): " BUILD_NUMBER

[[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid marketing version: $MARKETING_VERSION (expected x.y.z)" >&2
  exit 1
}
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
  echo "Invalid build number: $BUILD_NUMBER (expected a positive integer)" >&2
  exit 1
}

SED "s/^version: .*/version: ${MARKETING_VERSION}+${BUILD_NUMBER}/" pubspec.yaml
SED "s/^msix_version: .*/msix_version: ${MARKETING_VERSION}.${BUILD_NUMBER}/" windows/packaging/msix/make_config.yaml
SED -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" ios/Runner.xcodeproj/project.pbxproj
SED -E "s/MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+;/MARKETING_VERSION = ${MARKETING_VERSION};/g" ios/Runner.xcodeproj/project.pbxproj

echo "Version synchronized: ${MARKETING_VERSION}+${BUILD_NUMBER}"

if [[ "${VERSION_ONLY:-0}" == "1" ]]; then
  exit 0
fi

echo "WARNING: release mode commits, tags, and pushes the current branch"
if [[ "$(curl -o /dev/null -I -s -w "%{http_code}" "https://github.com/hiddify/hiddify-core/releases/download/v${CORE_VERSION:?CORE_VERSION is required}/hiddify-core-linux-amd64.tar.gz")" == "404" ]]; then
  echo "Core v${CORE_VERSION} not found" >&2
  exit 3
fi

git tag "$MARKETING_VERSION" >/dev/null
gitchangelog > HISTORY.md || {
  git tag -d "$MARKETING_VERSION"
  echo "Please run pip install gitchangelog pystache mustache markdown" >&2
  exit 2
}
git tag -d "$MARKETING_VERSION" >/dev/null
git add hiddify-core dependencies.properties ios/Runner.xcodeproj/project.pbxproj pubspec.yaml windows/packaging/msix/make_config.yaml HISTORY.md
git commit -m "release: version ${MARKETING_VERSION} (${BUILD_NUMBER})"
git push
git tag "v${MARKETING_VERSION}"
git push -u origin HEAD --tags
