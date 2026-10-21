# Architecture

Room is a Swift package with an executable and two test targets.

| Area | Responsibility |
|---|---|
| `Sources/RoomCore` | Metadata scanning, cache catalogue, disk maps, memory snapshots, local analysis, and recovery receipts |
| `Sources/RoomApp` | Native views, observable models, menu bar monitor, and macOS file permission dialogs |
| `Tests/RoomCoreTests` | Scanner, classification, filesystem identity, and recovery boundaries |
| `Tests/RoomAppTests` | Selection, permission, cancellation, and action boundaries |
| `Resources` | Application metadata, icon, and Store entitlements |
| `scripts` | Local build and packaging |
| `website` | Static public marketing, support, and privacy pages |

## Editions

`ROOM_EDITION=store` defines `ROOM_APP_STORE` across app, core, and test targets. The Store build removes external model execution and app-termination controls at compile time. It also replaces broad catalogue discovery with explicit approved-folder inputs.

Read approvals and temporary cleanup write approvals are distinct. Review grants bind to physical folder identity and expire with their review. Restore uses exact receipt locations and exact Trash-item authorization rather than a broad Trash grant.

## Data flow

An explicit scan runs on its engine actor and reports partial progress to the main-actor model. Models separate measured, eligible, and held bytes. Cleanup operates only on candidates minted by a completed scan and revalidates them before mutation.

Disk mapping reads metadata rather than file contents. Analysis is advisory and cannot bypass cleanup protections. Memory measurements are observations; occupancy and residual swap alone do not establish pressure.

Recovery receipts remain local. Restore validates the original receipt, current item identity, and destination state. A changed or regenerated destination is left in place.
