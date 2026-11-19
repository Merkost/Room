#!/bin/zsh
# Design gates for Room (18-BUILD-PLAN-AND-TESTS.md §6).
# Usage: scripts/check-design-gates.sh [--report|--counts] [Sources/RoomApp]
# --report prints violations above the per-file ceilings. --counts emits the raw ceiling format.
# Allowed exceptions: Sources/RoomApp/Design/ (RoomTokens and friends) and lines carrying `// design-gate: allow <reason>`.
set -u
mode=strict
if [[ "${1:-}" == --report || "${1:-}" == --counts ]]; then
  mode="${1#--}"
  shift
fi
root="${1:-Sources/RoomApp}"
root="${root%/}"
if [[ ! -d "$root" ]]; then
  print -ru2 -- "Missing source directory: $root"
  exit 2
fi
if [[ "$mode" != strict ]]; then
  findings="$(mktemp)"
  trap 'rm -f -- "$findings"' EXIT
fi
fail=0
report() {
  if [[ "$mode" == strict ]]; then
    print -r -- "$1"
  else
    print -r -- "$1" >> "$findings"
  fi
  fail=1
}

files=(${(f)"$(rg --files --glob '*.swift' --glob '!**/Design/**' "$root" | sort)"})
for f in $files; do
  # G1 literal fonts and sizes
  grep -nE '\.font\(\.system\(size:|Font\.system\(size:|\.system\(size: *[0-9]' "$f" | grep -v 'design-gate: allow' | while read -r l; do report "G1 literal font  $f:$l"; done
  # G2 literal colours and tints
  grep -nE 'Color\(red:|Color\(hue:|NSColor\(red:|NSColor\(srgbRed:|Color\(white:|\.tint\(Color\.|#[0-9A-Fa-f]{6}' "$f" | grep -v 'design-gate: allow' | while read -r l; do report "G2 literal colour $f:$l"; done
  grep -nE '\.(green|orange|red|cyan|blue|purple|pink|yellow|mint|teal|indigo)\b' "$f" | grep -E 'Color|tint|foreground|fill|stroke' | grep -v 'design-gate: allow' | while read -r l; do report "G2 system hue    $f:$l"; done
  # G3 literal radii and opacity surfaces
  grep -nE 'cornerRadius: *[0-9]|\.opacity\(0\.0[0-9]+\)' "$f" | grep -v 'design-gate: allow' | while read -r l; do report "G3 literal shape $f:$l"; done
  # G4 ad-hoc animations
  grep -nE '\.smooth\(duration:|\.spring\(response:|\.easeInOut\(duration:|\.easeOut\(duration:|\.linear\(duration:' "$f" | grep -v 'design-gate: allow' | while read -r l; do report "G4 literal motion $f:$l"; done
  # G5 no tilt: rotation and 3D are banned except the spinner glyph
  grep -nE 'rotationEffect|rotation3DEffect|projectionEffect|transform3D|CATransform3D|\.rotate\(' "$f" | grep -v 'design-gate: allow spinner' | while read -r l; do report "G5 rotation      $f:$l"; done
  # G6 no browser
  grep -niE 'chrome|chromium|WKWebView|SFSafariViewController' "$f" | grep -v 'design-gate: allow' | while read -r l; do report "G6 browser       $f:$l"; done
  # G7 reduce-motion recomputed outside RoomMotion
  grep -nE 'motionEnabled *&& *!reduceMotion' "$f" | while read -r l; do report "G7 motion policy $f:$l (use @Environment(\\.roomMotion))"; done
  # G9 Hide masking (PE-25): figures in masked views must go through RoomMaskable
  case "$f" in
    *Overview*|*Rooms*|*MenuBar*|*DiskMap*|*Caches*|*Receipt*|*History*|*/Views/Shell/*|*RoomRootView.swift|*RoomSheets.swift|*Developer*)
      grep -nE 'Text\((RoomFormat\.|.*formatted\(\.byteCount|.*ByteCountFormatter)' "$f" | grep -v 'RoomMaskable' | grep -v 'design-gate: allow' | while read -r l; do report "G9 unmasked size $f:$l (wrap in RoomMaskable)"; done ;;
  esac
done
# G10 debug-only affordances (AP-14, AP-15, MBF-6): the Trash and menu bar simulators must sit in a file guarded by #if DEBUG
grep -rlE 'Simulate Trash Emptied|RoomDebugTrashSimulator|RoomDebugMenuBarScenario' --include='*.swift' "$root" | while read -r f; do
  grep -q '^[[:space:]]*#if DEBUG[[:space:]]*$' "$f" || report "G10 debug-only     $f (wrap the simulator in #if DEBUG)"
done
# G8 Trash is never emptied (PR-15, CA-A6): whole tree, Design/ included, no allow escape
grep -rnE 'emptyTrash|empty (the )?trash|kAEEmptyTrash|"empty"' --include='*.swift' "$root" | grep -viE 'Text\(|String\(localized|//' | while read -r l; do report "G8 trash emptying $l"; done
if [[ "$mode" != strict ]]; then
  counts() {
    awk -v root="$root/" '{
      offset = index($0, root)
      if (offset == 0) next
      filename = substr($0, offset + length(root))
      sub(/:[0-9]+:.*/, "", filename)
      sub(/ \(wrap.*/, "", filename)
      print $1, filename
    }' "$findings" | sort | uniq -c | awk '{ print $2, $3, $1 }'
  }
  if [[ "$mode" == counts ]]; then
    counts
    exit 0
  fi
  baseline="${0:A:h}/design-gate-baseline.txt"
  counts | awk '
    FILENAME != "-" && NF == 3 { ceiling[$1 SUBSEP $2] = $3; next }
    NF == 3 && $3 > ceiling[$1 SUBSEP $2] {
      printf "%s %s: %d findings, ceiling %d\n", $1, $2, $3, ceiling[$1 SUBSEP $2]
      failed = 1
    }
    END { exit failed }
  ' "$baseline" -
  exit $?
fi
(( fail )) && { print "design gates: FAIL"; exit 1 } || { print "design gates: pass"; exit 0 }
