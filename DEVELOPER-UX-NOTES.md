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
