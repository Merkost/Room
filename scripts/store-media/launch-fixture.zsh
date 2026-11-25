#!/bin/zsh
set -euo pipefail

if [[ ${1:-} == --help ]]; then
    print 'Usage: zsh scripts/store-media/launch-fixture.zsh <build-directory> <state-directory> <scene> [--interactive] [--light]'
    print 'Scenes: overview, disk-map, caches, caches-review, developer, memory, history, settings, monitor, ai-tools'
    exit 0
fi
if [[ $# -lt 3 || $# -gt 5 ]]; then
    print -u2 'Supply the build directory, state directory and scene. Use --help for usage.'
    exit 2
fi

bundle="${1:A}/Room Screenshot Fixture.app"
state_dir="${2:A}"
scene=$3
case "$scene" in
    overview|disk-map|caches|caches-review|developer|memory|history|settings|monitor|ai-tools) ;;
    *) print -u2 "Unknown fixture scene: $scene"; exit 2 ;;
esac
if [[ ! -x "$bundle/Contents/MacOS/StoreScreenshotFixture" ]]; then
    print -u2 'Build the Store media fixture first.'
    exit 2
fi

mkdir -p "$state_dir"
run_dir="$(mktemp -d "$state_dir/fixture.XXXXXX")"
open -g -n -a "$bundle" --env "ROOM_MAIN_MENU_TEST_OUTPUT=$run_dir/menu-probe.json" --args "${@:3}"
for (( attempt = 0; attempt < 100; attempt++ )); do
    if [[ -s "$run_dir/pid" ]]; then
        cat "$run_dir/pid"
        print
        exit 0
    fi
    sleep 0.1
done
print -u2 "The fixture did not report its PID. Run state: $run_dir"
exit 1
