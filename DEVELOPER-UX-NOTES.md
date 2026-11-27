# Developer screen UX notes

## Audit (before)
- Hierarchy: a "Project tools" card with a tinted icon tile repeated the toolbar title; six tabs sat above any data; the "Ready to scan" card said almost nothing. Three equal figure cards competed, with no single number.
- Density and consistency: every list used its own row (canvas-filled rows, accent-washed icon squares in Storage, per-row capsules in orphans). Sizes used decimals everywhere ("12.4 GB"). Lists were unbounded.
- Clarity: "Remove…" on a scan folder did not say that files are untouched. No line said Room only reads. Folder disclosure was a card above the results.
- Copy: "Scan folders", "Remove from Developer?" vague. Empty/partial states were terse.
- Motion/a11y: panel change used one fade for tabs; rows did not arrive in order; rows were several a11y elements with no single label. Scan progress is a phase string plus item count only; the engine reports no total, so determinate progress is not possible without engine changes (left alone).
- Not captured: error alert and Store edition visuals (Store tests and build only).

## Changed
- Start page (no data): headline, one filled Scan or "Choose projects folder…", a read-only line, folders as a quiet disclosure, links to other views. No tabs.
- Results: summary header (hero total, "≥" when partial, thin Developer-teal breakdown bar and legend), then tabs only for views with data plus a "More views" menu. Tabs and layout changes fade 150 ms through `roomMotion`.
- One shared row (name, quiet location, whole-unit tabular size, one Show in Finder action, hover wash, 44 pt min height) for orphans, tool storage, simulators and AI tools; sorted by size; "Show N more" after 8 rows; orphans grouped by kind; rows fade in with a capped stagger.
- Hide masks names and sizes on every touched row; row accessibility label reads name, location, size; Show in Finder is an accessibility action.
- Copy: "Folders Room reads", "Stop reading this folder?", "Room only reads sizes and version files. Nothing is moved or deleted."
- DEBUG-only fixture hook `ROOM_DEBUG_DEVELOPER_ROOT` (isolated defaults, throwaway folder) for screenshots.

## Polish round 2
- One filled button per screen: Rescan (or Scan before the first scan) is the only primary; "Projects Folder…" is a plain accent link, the tool/device folder menus are borderless. While scanning, Stop is the quiet glass button.
- Hero reads "Total Developer storage found" with "X of it is not referenced by the projects you chose" (X carries "≥" when partial). Legend kinds are "Not referenced by your projects" and "Used by your projects", one line each (grid minimum widened, lineLimit 1).
- Project legend shortens "Xcode DerivedData" to "DerivedData" (`RoomDevPinKind.legendTitle`) and never wraps inside an entry.
- Per-project bars scale to the largest project via `RoomDeveloperList.barFractions` (largest = full width, others proportional, 3% minimum sliver, zero stays empty).
- Scan progress stays indeterminate: `DeveloperResourcesProgress` carries only a phase, an inspected-node count and the current path; the engine never knows a total in advance (it walks trees), so a determinate bar would be invented. The row shows the phase and a running item count.
- Screenshots (sample data in a throwaway folder, `after2-*.png` in shots/developer-ux): results, scanning, empty, partial (an oversize build script forces lower-bound sizes), badfolder (a file chosen as the projects folder: Room accepts it and reports notes, so no error alert could be provoked). The error alert, the DerivedData legend entry and a fully complete (non-partial) result were not captured.

## One scan for every section
- "Scan all" / "Rescan all" is the same button on every section. One press reads projects, devices, tool storage, AI tools and (Direct) agent worktrees; a part with no folder is skipped, and Stop ends all of it.
- The scan, sidebar row and activity pill last until the worktrees are read too. A running remote check or move holds the button back.
- Disk Map keeps a visible Rescan (or Map Again) at the bottom right in every view; it turns quiet while rooms are ticked.

## Scan buttons and scan animation

- Before a screen has anything to show, its scan button is large and in the middle. Once there are results it moves to the bottom right.
- Overview's "Scan everything" runs the same read-only Caches, Home folder, Developer and Memory reads their own screens run. Each is a room: its walls trace while it is read, its dots rise only as far as the engine has counted (whole rows, rounded down), and its figure appears when done. A part that cannot start says why.
- Smaller forms: Developer shows one short room per part; Caches and Disk Map show one wall segment per counted place or folder.
- The trace runs only while a scan runs. Reduce Motion keeps a still accent wall.

