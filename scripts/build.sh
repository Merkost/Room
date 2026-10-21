#!/bin/zsh
set -euo pipefail
source_dir="${0:A:h:h}"
task_build_dir="${ROOM_BUILD_DIR:-${TMPDIR:-/tmp}/Room-build}"
app_destination="${1:-${source_dir:h}/Room.app}"
task_bundle_stage="$(mktemp -d "${TMPDIR:-/tmp}/Room-bundle.XXXXXX")"
trap 'if [[ -d "$task_bundle_stage" ]]; then rm -r -- "$task_bundle_stage"; fi' EXIT
staged_app="$task_bundle_stage/Room.app"

swift build --package-path "$source_dir" --scratch-path "$task_build_dir" --configuration release --product Room
binary_dir="$(swift build --package-path "$source_dir" --scratch-path "$task_build_dir" --configuration release --show-bin-path)"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/Room" "$staged_app/Contents/MacOS/Room"
cp "$source_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
if [[ -f "$source_dir/Resources/Room.icns" ]]; then
    cp "$source_dir/Resources/Room.icns" "$staged_app/Contents/Resources/Room.icns"
fi
xattr -cr "$staged_app"
codesign --force --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
mkdir -p "${app_destination:h}"
ditto --norsrc --noextattr "$staged_app" "$app_destination"
ditto -c -k --norsrc --noextattr --keepParent "$staged_app" "${app_destination:r}-macOS.zip"
print "Built $app_destination"
print "Packaged ${app_destination:r}-macOS.zip"
