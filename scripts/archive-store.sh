#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h:h}"
artifact_dir="${ROOM_STORE_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/Room-Store-distribution}"
archive_path="${ROOM_STORE_ARCHIVE_PATH:-$artifact_dir/Room.xcarchive}"
export_path="${ROOM_STORE_EXPORT_PATH:-$artifact_dir/export}"
derived_data="${ROOM_STORE_DERIVED_DATA:-$artifact_dir/DerivedData}"
export_options="${ROOM_STORE_EXPORT_OPTIONS:-$source_dir/scripts/ExportOptions-AppStore.plist}"
dry_run=false
allow_provisioning=false
action=archive
action_set=false

usage() {
    cat <<'USAGE'
Usage: archive-store.sh [--dry-run] [--allow-provisioning-updates] [archive|export|all]

archive  Generate the native project and archive with xcodebuild (default).
export   Export an existing archive locally for App Store Connect.
all      Archive, then export locally. This command never uploads.

--dry-run                    Print commands without generating, building or signing.
--allow-provisioning-updates  Let Xcode contact Apple to manage signing assets.

Paths may be set using ROOM_STORE_ARTIFACTS_DIR, ROOM_STORE_ARCHIVE_PATH,
ROOM_STORE_EXPORT_PATH, ROOM_STORE_DERIVED_DATA and ROOM_STORE_EXPORT_OPTIONS.
See scripts/STORE-ARCHIVE.md for signing requirements and verification boundaries.
USAGE
}

while (( $# )); do
    case "$1" in
        --dry-run) dry_run=true ;;
        --allow-provisioning-updates) allow_provisioning=true ;;
        archive|export|all)
            if $action_set; then print -u2 "Choose only one action."; exit 2; fi
            action="$1"
            action_set=true
            ;;
        -h|--help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

run_command() {
    if $dry_run; then
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

typeset -a provisioning_args
provisioning_args=()
if $allow_provisioning; then provisioning_args=(-allowProvisioningUpdates); fi

if [[ "$action" == archive || "$action" == all ]]; then
    if [[ -e "$archive_path" ]]; then
        print -u2 "Archive already exists: $archive_path"
        print -u2 "Choose a new ROOM_STORE_ARCHIVE_PATH to preserve the previous artifact."
        exit 1
    fi
    run_command "$source_dir/scripts/generate-store-project.sh"
    run_command xcodebuild archive \
        -project "$source_dir/RoomStore.xcodeproj" \
        -scheme StoreArchive \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$archive_path" \
        -derivedDataPath "$derived_data" \
        "${provisioning_args[@]}"
fi

if [[ "$action" == export || "$action" == all ]]; then
    if [[ ! -f "$export_options" ]]; then
        print -u2 "Export options not found: $export_options"
        exit 1
    fi
    /usr/bin/plutil -lint -s "$export_options"
    export_destination="$(/usr/libexec/PlistBuddy -c 'Print :destination' "$export_options" 2>/dev/null || true)"
    if [[ -n "$export_destination" && "$export_destination" != export ]]; then
        print -u2 "This script supports local export only. Set destination to export in the export options."
        exit 1
    fi
    if ! $dry_run && [[ ! -d "$archive_path" ]]; then
        print -u2 "Archive not found: $archive_path"
        exit 1
    fi
    if [[ -e "$export_path" ]]; then
        print -u2 "Export destination already exists: $export_path"
        print -u2 "Choose a new ROOM_STORE_EXPORT_PATH to preserve the previous export."
        exit 1
    fi
    run_command xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options" \
        "${provisioning_args[@]}"
fi

if $dry_run; then
    print "Dry run only. No project generation, compilation, signing, export or upload was performed."
else
    print "Completed $action. Inspect the archive/export and signing before uploading separately."
fi
