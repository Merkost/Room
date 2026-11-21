#!/bin/zsh
set -euo pipefail
umask 077
export LC_ALL=C

usage() {
    cat <<'USAGE'
Usage: verify-store.sh archive [Room.xcarchive]
       verify-store.sh package Room.pkg
       verify-store.sh signing [Store.provisionprofile]

Verify existing Room artifacts or inspect local Store signing availability.
See scripts/STORE-ARCHIVE.md.
USAGE
}

fail() { print -u2 -- "Verification failed: $1"; exit 1; }
plist() { /usr/libexec/PlistBuddy -c "Print $1" "$2" 2>/dev/null; }

mode="${1:---help}"
if [[ "$mode" == --help || "$mode" == -h ]]; then usage; exit 0; fi
(( $# <= 2 )) || { usage >&2; exit 2; }
case "$mode" in
    archive|signing) ;;
    package) (( $# == 2 )) || { usage >&2; exit 2; } ;;
    *) usage >&2; exit 2 ;;
esac

source_dir="${0:A:h:h}"
info="$source_dir/Resources/Info-Store.plist"
entitlements="$source_dir/Resources/Room-Store.entitlements"
expected_bundle="$(plist :CFBundleIdentifier "$info")" || fail "Missing Store bundle metadata."
expected_version="$(plist :CFBundleShortVersionString "$info")" || fail "Missing Store version."
expected_build="$(plist :CFBundleVersion "$info")" || fail "Missing Store build number."
expected_executable="$(plist :CFBundleExecutable "$info")" || fail "Missing Store executable name."
expected_macos="$(plist :LSMinimumSystemVersion "$info")" || fail "Missing Store macOS requirement."
expected_team="$(plist :teamID "$source_dir/scripts/ExportOptions-AppStore.plist")" || fail "Missing Store team configuration."
expected_arch="$(/usr/bin/awk '$1 == "ARCHS:" { print $2; exit }' "$source_dir/project.yml")"
[[ "$expected_bundle" =~ '^[[:alnum:].-]+$' && "$expected_team" =~ '^[A-Z0-9]{10}$' \
    && "$expected_executable" =~ '^[[:alnum:]_-]+$' && -n "$expected_arch" ]] || fail "Invalid Store project metadata."

scratch="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/room-store-verify.XXXXXX")"
trap '/bin/rm -rf -- "$scratch"' EXIT

check_entitlements() {
    /usr/bin/python3 - "$entitlements" "$1" "$mode" "$expected_team" "$expected_bundle" <<'PY'
import plistlib
import sys

expected_path, actual_path, mode, team, bundle = sys.argv[1:]
with open(expected_path, "rb") as file:
    expected = plistlib.load(file)
with open(actual_path, "rb") as file:
    actual = plistlib.load(file)
identifiers = {
    "com.apple.developer.team-identifier": team,
    "com.apple.application-identifier": f"{team}.{bundle}",
    "application-identifier": f"{team}.{bundle}",
}
debug = {"get-task-allow", "com.apple.security.get-task-allow"}
unrestricted = {
    "com.apple.security.app-sandbox",
    "com.apple.security.files.user-selected.read-write",
    "com.apple.security.files.bookmarks.app-scope",
}
if expected.keys() != unrestricted or any(expected[key] is not True for key in unrestricted):
    sys.exit("Review the verifier's provisioning rule for the updated entitlement contract.")
if any(actual.get(key) is not True for key in expected):
    sys.exit("The required sandbox, folder selection or bookmark entitlement is missing.")
if actual.keys() - expected.keys() - identifiers.keys() - debug:
    sys.exit("The signed app contains an unexpected entitlement.")
if any(key in actual and actual[key] != value for key, value in identifiers.items()):
    sys.exit("A signed identifier entitlement does not match Room's Store configuration.")
if any(key in actual and type(actual[key]) is not bool for key in debug):
    sys.exit("A signed debug entitlement has an invalid value.")
if mode == "package" and any(key in actual and actual[key] is not False for key in debug):
    sys.exit("The exported app permits debug attachment.")
PY
}

check_profile() {
    local input="$1" certificate_mode="$2" certificate_path="$3"
    [[ -f "$input" ]] || fail "The specified provisioning profile is missing."
    /usr/bin/security cms -D -i "$input" -o "$scratch/profile.plist" >/dev/null 2>&1 \
        || fail "The provisioning profile could not be decoded."
    /usr/bin/python3 - "$scratch/profile.plist" "$expected_team" "$expected_bundle" "$certificate_mode" "$certificate_path" <<'PY'
from datetime import datetime, timedelta, timezone
from hashlib import sha1
from pathlib import Path
import plistlib
import sys

path, team, bundle, mode, identities = sys.argv[1:]
with open(path, "rb") as file:
    profile = plistlib.load(file)
entitlements = profile.get("Entitlements", {})
app_id = entitlements.get("com.apple.application-identifier", entitlements.get("application-identifier"))
allowed = {f"{team}.{bundle}"}
if mode == "archive":
    allowed.add(f"{team}.*")
if team not in profile.get("TeamIdentifier", []) or app_id not in allowed:
    sys.exit("The profile does not match Room's configured team and application.")
platforms = profile.get("Platform", [])
if platforms and not {"OSX", "macOS"}.intersection(platforms):
    sys.exit("The profile is for another platform.")
valid_until = profile.get("ExpirationDate")
created_at = profile.get("CreationDate")
now = datetime.now(timezone.utc)
if not isinstance(valid_until, datetime) or valid_until.replace(tzinfo=timezone.utc) <= now:
    sys.exit("The provisioning profile has expired or has no valid expiry.")
if isinstance(created_at, datetime) and created_at.replace(tzinfo=timezone.utc) > now + timedelta(minutes=5):
    sys.exit("The provisioning profile is not yet valid for this system clock.")
if mode != "archive" and (
    profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")
    or entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow")
):
    sys.exit("The profile is for device-limited or independent distribution.")
certificates = profile.get("DeveloperCertificates", [])
if mode == "signing":
    local_ids = set(Path(identities).read_text().splitlines())
    matches = any(sha1(cert).hexdigest().upper() in local_ids for cert in certificates)
else:
    matches = Path(identities).read_bytes() in certificates
if not matches:
    sys.exit("The profile does not authorize the exact app signing certificate.")
PY
    print "Provisioning metadata matches the signing certificate and is current."
}

check_app() {
    local app="$1" bundle_info="$1/Contents/Info.plist" signer architecture profile
    [[ -f "$bundle_info" ]] || fail "Missing Room.app bundle metadata."
    [[ "$(plist :CFBundleIdentifier "$bundle_info")" == "$expected_bundle" \
        && "$(plist :CFBundleShortVersionString "$bundle_info")" == "$expected_version" \
        && "$(plist :CFBundleVersion "$bundle_info")" == "$expected_build" \
        && "$(plist :CFBundleExecutable "$bundle_info")" == "$expected_executable" \
        && "$(plist :CFBundlePackageType "$bundle_info")" == APPL \
        && "$(plist :LSMinimumSystemVersion "$bundle_info")" == "$expected_macos" ]] \
        || fail "The app bundle does not match this checkout's Store metadata."
    architecture="$(/usr/bin/xcrun lipo -archs "$app/Contents/MacOS/$expected_executable" 2>/dev/null)" \
        || fail "The app executable is missing or unreadable."
    [[ "$architecture" == "$expected_arch" ]] || fail "The executable architecture does not match the Store project."

    /usr/bin/codesign --verify --deep --strict --all-architectures "$app" >/dev/null 2>&1 \
        || fail "The app's sealed code signature did not verify."
    /usr/bin/codesign --verify --strict \
        -R="anchor apple generic and identifier \"$expected_bundle\" and certificate leaf[subject.OU] = \"$expected_team\"" \
        "$app" >/dev/null 2>&1 || fail "The signature lacks the configured Apple signing team or bundle identifier."
    signer="$(/usr/bin/codesign --display --verbose=4 "$app" 2>&1 \
        | /usr/bin/awk '/^Authority=/ { sub(/^Authority=/, ""); sub(/:.*/, ""); if (!seen++) print }')" \
        || fail "The app signing identity could not be inspected."
    case "$mode:$signer" in
        'archive:Apple Development'|'archive:Mac Developer'|\
        'package:Apple Distribution'|'package:3rd Party Mac Developer Application'|'package:Mac App Distribution') ;;
        *) fail "The app is signed for a different distribution channel." ;;
    esac
    /usr/bin/codesign --display --xml --entitlements - "$app" > "$scratch/entitlements.plist" 2>/dev/null \
        || fail "Could not extract signed entitlements."
    check_entitlements "$scratch/entitlements.plist"

    profile="$app/Contents/embedded.provisionprofile"
    if [[ -e "$profile" ]]; then
        /usr/bin/codesign --display --extract-certificates="$scratch/app-cert-" "$app" >/dev/null 2>&1 \
            || fail "Could not extract the app's public signing certificate."
        check_profile "$profile" "$mode" "$scratch/app-cert-0"
    else
        print "No embedded profile. Room's current sandbox entitlements do not require one for the Mac App Store."
    fi
    print -- "Verified Room $expected_version ($expected_build), $architecture, and the signed Store sandbox entitlements."
}

check_installer() {
    local package="$1" installer_leaf
    /usr/sbin/pkgutil --check-signature "$package" > "$scratch/package-signature.txt" 2>&1 \
        || fail "The installer package signature did not verify."
    /usr/bin/grep -Eq '^[[:space:]]*Status: signed by a certificate trusted by (macOS|Mac OS X)([[:space:]]|$)' \
        "$scratch/package-signature.txt" || fail "macOS does not trust the installer package signature."
    installer_leaf="$(/usr/bin/awk '/^[[:space:]]+1\. / { sub(/^[[:space:]]+1\. /, ""); print; exit }' \
        "$scratch/package-signature.txt")"
    case "$installer_leaf" in
        '3rd Party Mac Developer Installer: '*|'Mac Installer Distribution: '*) ;;
        *) fail "The installer lacks a Mac App Store installer signature." ;;
    esac
    if [[ "$installer_leaf" != *" ($expected_team)" && "$installer_leaf" != *": $expected_team" ]]; then
        /usr/bin/xar -f "$package" --dump-toc="$scratch/package-toc.xml" >/dev/null 2>&1 \
            || fail "Could not read the installer's certificate table."
        /usr/bin/xmllint --nonet --xpath 'string((/xar/toc/signature//*[local-name()="X509Certificate"])[1])' \
            "$scratch/package-toc.xml" 2>/dev/null | /usr/bin/base64 -D > "$scratch/installer-cert.der" \
            || fail "Could not extract the installer's public certificate."
        /usr/bin/openssl x509 -inform DER -in "$scratch/installer-cert.der" -noout -subject -nameopt RFC2253 2>/dev/null \
            | /usr/bin/grep -Eq "(^subject=|,)OU=$expected_team(,|$)" \
            || fail "The installer signature is for another team."
    fi
    print "Verified the Mac App Store installer signature."
}

case "$mode" in
    archive)
        artifact_dir="${ROOM_STORE_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/Room-Store-distribution}"
        archive="${2:-${ROOM_STORE_ARCHIVE_PATH:-$artifact_dir/Room.xcarchive}}"
        archive="${archive:A}"
        archive_info="$archive/Info.plist"
        [[ -f "$archive_info" ]] || fail "No Xcode archive metadata at the supplied path."
        app_path="Applications/$expected_executable.app"
        [[ "$(plist :ApplicationProperties:ApplicationPath "$archive_info")" == "$app_path" \
            && "$(plist :ApplicationProperties:CFBundleIdentifier "$archive_info")" == "$expected_bundle" \
            && "$(plist :ApplicationProperties:CFBundleShortVersionString "$archive_info")" == "$expected_version" \
            && "$(plist :ApplicationProperties:CFBundleVersion "$archive_info")" == "$expected_build" ]] \
            || fail "Xcode archive metadata does not match this Store release."
        check_app "$archive/Products/$app_path"
        print "Development archive verified."
        ;;
    package)
        package="${2:A}"
        [[ -f "$package" && "$package" == *.pkg ]] || fail "Supply an exported flat installer package."
        check_installer "$package"
        /usr/sbin/pkgutil --expand-full "$package" "$scratch/package" >/dev/null 2>&1 \
            || fail "The installer payload could not be expanded."
        typeset -a apps
        apps=()
        while IFS= read -r -d '' app; do
            apps+=("$app")
        done < <(/usr/bin/find "$scratch/package" -type d -name '*.app' -prune -print0)
        [[ "${#apps}" == 1 && "${apps[1]:t}" == "$expected_executable.app" ]] || fail "The installer must contain one Room.app."
        check_app "${apps[1]}"
        print "Mac App Store package verified locally."
        ;;
    signing)
        /usr/bin/security find-identity -v > "$scratch/identities" 2>/dev/null \
            || fail "Could not inspect local signing availability."
        /usr/bin/awk -v team="$expected_team" '
            (index($0, "(" team ")") || index($0, ": " team "\"")) &&
            /"(Apple Distribution|3rd Party Mac Developer Application|Mac App Distribution): / { print $2 }
        ' "$scratch/identities" > "$scratch/distribution-ids"
        missing=false
        if [[ -s "$scratch/distribution-ids" ]]; then
            print "Local Store application signing identity found."
        else
            print "No valid local Store application signing identity for the configured team."
            missing=true
        fi
        if /usr/bin/awk -v team="$expected_team" '
            (index($0, "(" team ")") || index($0, ": " team "\"")) &&
            /"(3rd Party Mac Developer Installer|Mac Installer Distribution): / { found=1 }
            END { exit !found }
        ' "$scratch/identities"; then
            print "Local Mac App Store installer signing identity found."
        else
            print "No valid local Mac App Store installer signing identity for the configured team."
            missing=true
        fi
        if (( $# == 2 )); then
            check_profile "${2:A}" signing "$scratch/distribution-ids"
        else
            print "No profile supplied. The current Store entitlement contract does not require one."
        fi
        if $missing; then exit 1; fi
        ;;
esac
