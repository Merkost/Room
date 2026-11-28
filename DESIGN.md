# Room interface

Room is a native macOS utility used in short, deliberate sessions: inspect storage, understand a measurement, review a change, and keep recovery available. The interface should feel calm, precise, and immediately useful.

## Identity and materials

The approved identity is C4, the soft pocket. `Resources/RoomMark.svg` is the canonical geometry. Keep its compound path, even-odd fill, proportions, and upright orientation intact. The app icon uses white on graphite `#222527`.

Use native Liquid Glass for navigation, buttons, menus, and transient surfaces. The working canvas uses semantic macOS window and control surfaces. Avoid decorative glows, nested glass enclosures, and ornamental cards around individual metrics. System appearance, Reduce Motion, and Reduce Transparency remain authoritative.

## Hierarchy

- One system font family: San Francisco through SwiftUI system fonts. Headings use semibold; measurements use regular or medium with tabular digits.
- Page titles: 22–24 pt. Section titles: 16 pt. Body and row labels: 13–14 pt. Supporting labels: 12 pt; functional text never falls below 11 pt.
- The primary measured amount is 36–40 pt; sibling amounts are 20–24 pt. Units stay attached to their value and baseline. A missing measurement never displays as a measured zero.
- The main canvas uses 40 pt gutters at detail widths of 700 pt and above, and 24 pt below that. Screen titles align with the content column. Section gaps are 24 pt. Group padding and content corners are 16 pt.
- One primary action per working context. In the window it lives in the dock's action slot and nowhere else; sheets, the popover and onboarding keep their own. Secondary actions use ordinary glass or plain controls. Controls in a row share their height and baseline.
- Each screen has one headline and one body of evidence; the body repeats no figure or control. The dock's figure is that place's summary.

## Working surfaces

Clean starts with the next useful action. Before a scan, show an honest ready state; after a scan, show measured, clearable, and held amounts from the same report. A Store user with no approved folders can choose a folder and start scanning from the primary action.

Caches lists everything it found and nothing it merely looked at: Safe to remove (ticked), Used recently (unticked, selectable), and Open right now (waits until the app quits). Everything selected still goes through review into Trash. Besides named tools, Room recognises caches by their shape: a Chromium or Electron app's rendering caches (never its storage, cookies or sessions), downloaded app updates, and Xcode's device support. An app's open profile lock counts as the app running. A folder's name alone never makes it removable.

Developer is one screen with no tabs and no folder step: projects and tool folders are found automatically, shown as a composition strip over two columns (one when narrow). Choosing folders only adds to or skips what was found. Projects of every common kind list the folders their tools rebuild (node_modules, target, .build, .venv and the like), each proven by the project's own files. Projects untouched for a month are ticked and lead the list; the dock's Review moves ticked folders to Trash, checking each again on disk first. The App Store edition shows them without ticks.

Memory is one screen with nothing behind a disclosure: a Now / 15 min / 1 hour range with one pressure sentence, the curve, App memory, Wired, Compressed and Swap, then apps that can be quit beside background processes that are view only. Curve time without a reading stays empty. Advice appears only when pressure asks for it, before the lists. Resident process sizes include shared pages, are never totalled, and never imply a guaranteed RAM saving.

Disk Map gives the largest area to the actual folder map. Keep one clear folder context, labeled Scan/Rescan/Stop, category evidence, and hidden-file controls. Developer resources group related rows, align sizes to one trailing edge, and expose uncertainty about use and project references.

Navigation is a floating Liquid Glass dock: Overview, Disk Map, Caches, Developer and Memory, each with its figure and engine state, then a fixed-width slot for the screen's next step, so neither the places nor the button move. History, Settings and Go to sit in the top bar. Screens reserve the dock's height. Playful moments are one-shot, tied to a real event, and fade in place under Reduce Motion. The menu-bar popup uses the same type, spacing, metric meanings, and action hierarchy as the app.

## Interaction and truth

Motion communicates a selection, measurement update, disclosure, or transition. Use short, interruptible native transitions. Avoid perpetual decorative motion; reduced motion keeps immediate feedback without spatial movement.

Preserve visible keyboard focus, accessible labels, shortcuts, and native folder pickers. Permission requests stay beside the action that requires them. A scan is read-only. Cleanup remains a separate reviewed action with its exact access requirements and consequences visible. Store and direct-edition capabilities must remain distinct.

Validate the actual native app at its minimum window size and a typical desktop size, in light and dark appearance. Inspect ready, scanning, results, permission, selection, and review states. A screenshot of a sample folder is labeled as a sample; build, upload, submission, and release are separate outcomes.
