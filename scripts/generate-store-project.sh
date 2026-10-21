#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h:h}"
xcodegen_bin="${ROOM_XCODEGEN_BIN:-$(command -v xcodegen || true)}"

if [[ -z "$xcodegen_bin" || ! -x "$xcodegen_bin" ]]; then
    print -u2 "XcodeGen 2.45.3 or newer is required. Install it or set ROOM_XCODEGEN_BIN."
    exit 1
fi

"$xcodegen_bin" generate --spec "$source_dir/project.yml" --project-root "$source_dir" --project "$source_dir"
print "Generated $source_dir/RoomStore.xcodeproj with shared StoreArchive scheme."
