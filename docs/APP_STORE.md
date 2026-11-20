# Mac App Store listing draft

## Name

Room: Disk Space & Memory

## Subtitle

See what fills your Mac

## Promotional text

Find large files in a map of the folders you choose. Review cache moves and check memory pressure from your menu bar.

## Keywords

`treemap,folder,file,large,hidden,ram,swap,cache,emulator,compression,monitor,visualizer,scan,history`

## Description

Room turns the folders you choose into a map you can explore. Find large files, see what’s inside a folder, and pin the places you check often.

Explore your storage
Find large and hidden items where macOS allows access. Reopen a saved map, filter by category, or compare scans when history is available.

Review before you move
See what’s taking up space in supported caches. Room can move eligible npm downloads older than 30 days that pass local verification. Review the selection and approve the exact folders before anything moves to Trash. A receipt lets you restore unchanged items when their original locations are available. Files still take up space in Trash until you empty it.

Keep memory in view
See memory pressure, RAM use, compression, and swap. Put memory or free space in your menu bar for a quick check.

Understand your developer storage
Review Android and Apple simulator storage and see which Gradle versions your projects reference. AI Tools shows caches, history, worktrees, and local models in the tool folders you approve. Optional on-device analysis can suggest what to inspect next.

Room runs on your Mac without an account, ads, or in-app purchases. Requires an Apple silicon Mac running macOS 26 or later. Made by Merkost.

## Product page links

| Field | Value |
| --- | --- |
| Marketing URL | https://room.merkost.dev/ |
| Support URL | https://room.merkost.dev/support/ |
| Privacy policy URL | https://room.merkost.dev/privacy/ |

Primary category **Utilities**. Secondary category **Developer Tools**.

## Field lengths

| Field | Used | Limit |
| --- | ---: | ---: |
| Name | 25 | 30 characters |
| Subtitle | 23 | 30 characters |
| Promotional text | 117 | 170 characters |
| Keywords | 100 | 100 UTF-8 bytes |
| Description | 1,254 | 4,000 characters |

[App information limits](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-compliance-information) · [Product page fields](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)

## Capture Store media

From the repository root, build the local Store fixture on an Apple silicon Mac running macOS 26 or later. The fixture linker uses SwiftBuild debug-test products and expects the Xcode 27.2 layout. The video renderer also needs Python 3.9 or later and FFmpeg with `ffprobe` and `libx264`.

```sh
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/room-media-build.XXXXXX")
state_dir=$(mktemp -d /private/tmp/room-media-state.XXXXXX)
media_dir=$(mktemp -d "${TMPDIR:-/tmp}/room-store-media.XXXXXX")
mkdir -p "$media_dir/captures" "$media_dir/recordings"
zsh scripts/store-media/build-fixture.zsh "$build_dir"
capture="$build_dir/capture-window"
"$capture" preflight
```

The ad hoc signed fixture displays the Store UI with fictional storage, projects and memory history. It has a separate bundle identifier and writes its sample data under `state_dir`. Use a neutral temporary path because the Disk Map inspector can display the sample folder path. The Trash provider rejects moves in the fixture. Window capture requires existing macOS Screen Recording access.

```sh
fixture_pid=$(zsh scripts/store-media/launch-fixture.zsh "$build_dir" "$state_dir" overview)
"$capture" list "$fixture_pid"
window_id=$("$capture" list "$fixture_pid" | awk 'NR == 1 {print $1}')
"$capture" png "$fixture_pid" "$window_id" "$media_dir/captures/overview.png"
kill -TERM "$fixture_pid"
```

Use the same sequence for `disk-map`, `caches-review`, `developer`, `memory`, `monitor`, and `ai-tools`. Name each PNG after the scene. Wait for the scene to load before capturing. Add `--include-child-windows` to the Caches capture so the attached review sheet appears.

```sh
swift scripts/store-media/render-screenshots.swift "$media_dir/captures" "$media_dir/screenshots"
```

The screenshot renderer uses the tracked Room icon and [shot manifest](../scripts/store-media/shots.json) to create seven 2880×1800 opaque sRGB PNGs. The Monitor composition shows the native readout inside a fixture window. It omits the macOS menu bar anchor. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

## Record and render previews

Launch the fixture with `--interactive` to bring it forward for a recording. Verify its window ID with `list`. Start recordings one at a time because overlapping sessions can interrupt macOS recording. The recorder fits the fixture window in a 1920×1080 frame and excludes system and microphone audio.

| Recording | Native footage |
| --- | --- |
| `overview.mov` | Hold Overview with its measured map. |
| `overview-map-interactive.mov` | Start in Overview, open Disk Map, step into Mobile Studio, then choose Largest 20. |
| `cache-review-interactive.mov` | Start on the populated Caches review and deselect two rows. Record with `--include-child-windows`. |
| `memory.mov` | Hold Memory with the sample pressure chart. |
| `monitor.mov` | Hold the Monitor fixture window with the disk, memory and cache readouts. |

```sh
"$capture" record "$fixture_pid" "$window_id" 24 "$media_dir/recordings/overview-map-interactive.mov"
python3 scripts/store-media/render-previews.py --recordings "$media_dir/recordings" --exports "$media_dir/previews"
python3 scripts/store-media/render-previews.py --verify "$media_dir"/previews/*.mov
```

The [preview edit sheet](../scripts/store-media/preview-edits.json) records the cuts for the captured takes. Adjust cut times for a new take with `--edit-sheet` and render an individual preview with `--only`. The renderer verifies progressive 1920×1080 H.264 High Level 4.0 at 30 fps with BT.709 and silent stereo AAC. It saves a five-second poster and a JSON report with the input and output hashes for each preview. Review the final frames for visible sample paths, UI changes and legibility before publishing. [Apple preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/)

Keep the source tools, manifests and caption copy in Git. Keep raw captures, generated media, local fixture state and certificate or signing artifacts in external build or release storage. Choose the final listing copy, assets, build and release timing in App Store Connect as a separate publisher step.
