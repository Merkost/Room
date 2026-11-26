#!/bin/zsh
set -euo pipefail

if [[ ${1:-} == --help ]]; then
    print 'Usage: zsh scripts/store-media/build-fixture.zsh <build-directory>'
    exit 0
fi
if [[ $# -ne 1 || -z $1 ]]; then
    print -u2 'Supply a build directory. Use --help for usage.'
    exit 2
fi

tools_dir="${0:A:h}"
repo="${tools_dir:h:h}"
build_dir="${1:A}"
scratch="$build_dir/swiftpm"
name='Room Screenshot Fixture.app'
if [[ -e "$build_dir/$name" || -e "$build_dir/capture-window" ]]; then
    print -u2 'Choose a new build directory or move the previous fixture outputs before rebuilding.'
    exit 2
fi
edition="${ROOM_FIXTURE_EDITION:-store}"
defines=()
[[ $edition == store ]] && defines=(-D ROOM_APP_STORE)
ROOM_EDITION=$edition swift test --package-path "$repo" --scratch-path "$scratch" --build-system swiftbuild list

products="$scratch/out/Products/Debug"
link_lists=("$scratch"/out/Intermediates.noindex/Room.build/Debug/RoomApp-*-testable-t.build/Objects-normal/arm64/*.LinkFileList(N))
if [[ ${#link_lists[@]} -ne 1 || ! -f "$products/RoomCore.o" || ! -d "$products/Room_RoomApp.bundle" ]]; then
    print -u2 'Unexpected SwiftBuild debug-test product layout. See docs/APP_STORE.md for the fixture toolchain.'
    exit 2
fi
app_objects="${link_lists[1]:h}"
objects=()
while IFS= read -r object; do
    [[ -z $object ]] || objects+=("$object")
done < "${link_lists[1]}"

stage="$(mktemp -d "$build_dir/.fixture-stage.XXXXXX")"
trap 'rm -r -- "$stage"' EXIT
bundle="$stage/$name"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$tools_dir/FixtureInfo.plist" "$bundle/Contents/Info.plist"
ditto "$products/Room_RoomApp.bundle" "$bundle/Contents/Resources/Room_RoomApp.bundle"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos26.0 "${defines[@]}" \
    -I "$app_objects" -I "$products" \
    "$tools_dir/StoreScreenshotFixture.swift" "${objects[@]}" "$products/RoomCore.o" \
    -o "$bundle/Contents/MacOS/StoreScreenshotFixture"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos26.0 \
    "$tools_dir/capture-window.swift" -o "$stage/capture-window"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"

mv "$bundle" "$build_dir/$name"
mv "$stage/capture-window" "$build_dir/capture-window"
print -r -- "$build_dir/$name"
