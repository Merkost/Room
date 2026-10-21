#!/bin/zsh
set -euo pipefail
source_dir="${0:A:h:h}"
task_build_dir="${ROOM_BUILD_DIR:-${TMPDIR:-/tmp}/Room-Store-build}"
app_destination="${1:-${source_dir:h}/Room Store.app}"
signing_identity="${ROOM_SIGNING_IDENTITY:--}"
task_bundle_stage="$(mktemp -d "${TMPDIR:-/tmp}/Room-Store-bundle.XXXXXX")"
trap 'if [[ -d "$task_bundle_stage" ]]; then rm -r -- "$task_bundle_stage"; fi' EXIT
staged_app="$task_bundle_stage/Room.app"

ROOM_EDITION=store swift build --package-path "$source_dir" --scratch-path "$task_build_dir" --configuration release --product Room
binary_dir="$(ROOM_EDITION=store swift build --package-path "$source_dir" --scratch-path "$task_build_dir" --configuration release --show-bin-path)"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/Room" "$staged_app/Contents/MacOS/Room"
cp "$source_dir/Resources/Info-Store.plist" "$staged_app/Contents/Info.plist"
cp "$source_dir/Resources/Room.icns" "$staged_app/Contents/Resources/Room.icns"
if [[ -n "${ROOM_PROVISIONING_PROFILE:-}" ]]; then
    cp "$ROOM_PROVISIONING_PROFILE" "$staged_app/Contents/embedded.provisionprofile"
fi
xattr -cr "$staged_app"
codesign --force --sign "$signing_identity" --options runtime --entitlements "$source_dir/Resources/Room-Store.entitlements" "$staged_app"
codesign --verify --deep --strict "$staged_app"
mkdir -p "${app_destination:h}"
ditto --norsrc --noextattr "$staged_app" "$app_destination"
ditto -c -k --norsrc --noextattr --keepParent "$staged_app" "${app_destination:r}-sandbox.zip"
print "Built sandboxed Store candidate: $app_destination"
print "ZIP is a test artifact. App Store distribution requires a matching profile, distribution identity, signed installer, validation and upload."
