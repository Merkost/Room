# Room interface

Room is a native macOS utility used in short, deliberate sessions: inspect storage, understand a measurement, review a change, and keep recovery available. The interface should feel calm, precise, and immediately useful.

## Identity and materials

The approved identity is C4, the soft pocket. `Resources/RoomMark.svg` is the canonical geometry. Keep its compound path, even-odd fill, proportions, and upright orientation intact. The app icon uses white on graphite `#222527`.

Use native Liquid Glass for navigation, buttons, menus, and transient surfaces. The working canvas uses semantic macOS window and control surfaces. Avoid decorative glows, nested glass enclosures, and ornamental cards around individual metrics. System appearance, Reduce Motion, and Reduce Transparency remain authoritative.

## Hierarchy

- One system font family: San Francisco through SwiftUI system fonts. Headings use semibold; measurements use regular or medium with tabular digits.
- Page titles: 22–24 pt. Section titles: 16 pt. Body and row labels: 13–14 pt. Supporting labels: 12 pt; functional text never falls below 11 pt.
- The primary measured amount is 36–40 pt; sibling amounts are 20–24 pt. Units stay attached to their value and baseline. A missing measurement never displays as a measured zero.
- Canvas gutters: 24–28 pt. Section gaps: 24 pt. Group padding and content corners: 16 pt. Use proximity and alignment before adding containers.
- One primary action per working context, using the system accent and native prominent glass. Secondary actions use ordinary glass or plain controls. Controls in a row share their height and baseline.

## Working surfaces

Clean starts with the next useful action. Before a scan, show an honest ready state; after a scan, show measured, clearable, and held amounts from the same report. A Store user with no approved folders can choose a folder and start scanning from the primary action.

Memory leads with measured usage, actual pressure, and the refresh action. Compression, available memory, and swap have distinct labels. Suggestions precede long process lists. Resident process sizes never imply a guaranteed RAM saving.

Disk Map gives the largest area to the actual folder map. Keep one clear folder context, labeled Scan/Rescan/Stop, category evidence, and hidden-file controls. Developer resources group related rows, align sizes to one trailing edge, and expose uncertainty about use and project references.

Navigation uses stable targets: Clean, Memory, Disk Map, Activity, Developer, and Agent work in the direct edition. Store has the first five. Number shortcuts follow their visual order. Keep the product identity, destinations, and settings aligned without duplicate enclosures. The menu-bar popup uses the same type, spacing, metric meanings, and action hierarchy as the app.

## Shared components

`Sources/RoomApp/DesignSystem` is the presentation source of truth. Reuse its semantic roles rather than adding a second token scale or a screen-specific version of a shared component.

| Component | Contract |
| --- | --- |
| `RoomTypography`, `RoomSpace`, `RoomRadius`, `RoomSurface` | Native system typography, a 4–28 pt spacing scale, semantic opaque working surfaces, and accessible selection/hover treatment. |
| `RoomPageHeader`, `RoomSectionHeader` | One heading with contextual actions; stack complete groups before labels compress. Expose heading semantics. |
| `RoomMetric`, `RoomByteMetric` | Keep value/unit together, distinguish unavailable from zero, and expose lower-bound measurements visually and to accessibility. |
| `RoomContentGroup`, `RoomPathLabel` | Group related work with a 16 pt inset. Paths remain selectable and fully available to accessibility. |
| `RoomStatusNotice`, `RoomEmptyState` | Consistent feedback, a clear explanation, and a useful next action. Meaning never depends on color alone. |
| `RoomSheetLayout` | Fixed heading and native action footer around one scrollable body. Preserve default/cancel keys and operation-specific dismissal guards. |
| `RoomSelectionCheckbox` | Native off/on/mixed state and keyboard focus. Choosing a mixed source selects all eligible items; a full source can be cleared. |
| `roomAction`, `RoomMotionPolicy` | Native primary/secondary/quiet actions. App motion preference and system Reduce Motion jointly govern custom transitions. |

Domain-specific maps, charts, emulator graphics, and repository evidence remain purpose-built. They consume shared roles without being forced into a generic card. A selected item retains its original scan identity and partial status; an open sheet must not silently inherit evidence from another scan.

## Interaction and truth

Motion communicates a selection, measurement update, disclosure, or transition. Use short, interruptible native transitions. Avoid perpetual decorative motion; reduced motion keeps immediate feedback without spatial movement.

Preserve visible keyboard focus, accessible labels, shortcuts, and native folder pickers. Permission requests stay beside the action that requires them. A scan is read-only. Cleanup remains a separate reviewed action with its exact access requirements and consequences visible. Store and direct-edition capabilities must remain distinct.

Validate the actual native app at its minimum window size and a typical desktop size, in light and dark appearance. Inspect ready, scanning, results, permission, selection, and review states. A screenshot of a sample folder is labeled as a sample; build, upload, submission, and release are separate outcomes.
