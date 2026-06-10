# Pult Remote UX Redesign — Design

Date: 2026-06-09
Status: implemented autonomously per user directive ("build a compelling, high-quality,
professional-grade UX using latest SwiftUI concepts, hidden elements, good animations").

## Goal

Upgrade the Pult remote UI from a functional grid of glass panels into a polished,
tactile, iOS 26 Liquid Glass remote experience, without changing `PultCore` protocol
behavior or the `RemoteControlModel` API surface.

## Approaches considered

1. **Polish in place** — restyle existing clusters. Low risk, but keeps the cramped
   header and flat button grid; doesn't reach "professional grade".
2. **Dual-mode control surface redesign (chosen)** — touchpad + ring D-pad modes,
   device chrome moved to the toolbar, redesigned pairing, haptics and animations
   throughout. UI-layer only; medium scope.
3. **Multi-tab app (remote / devices / settings)** — overkill for the current scope
   (one remote, manual device entry). Rejected per YAGNI.

## Design

### Root view & device chrome
- `NavigationStack` with an inline title showing the selected device via a toolbar
  `Menu` (device list with checkmarks + "Add TV…"), and a trailing pair/connect
  action that adapts to state.
- Connection state shown as an animated capsule (pulsing dot while connecting,
  green when online). Failures surface as a dismissible banner with a Retry button.
- No devices → `ContentUnavailableView` with an "Add TV" CTA; the remote surface is
  hidden until a device exists.
- Auto-connect: `.task(id: selectedDevice.id)` connects when a paired device is
  selected and the session is disconnected.

### Control surface (the "hidden element")
- Two modes, persisted with `@AppStorage("controlMode")`:
  - **Touchpad** (default): a large glass gesture pad. Directional swipe sends
    up/down/left/right; tap sends select. A chevron flashes in the swipe direction
    and a dot pulses on tap as feedback. A usage hint fades out after first gestures.
  - **D-pad**: a circular remote-style ring built from four annular-sector wedge
    buttons (`DPadWedge` shape) around a center select button.
- Both render inside one `GlassEffectContainer`; switching modes morphs the glass
  with `glassEffectID`. A small glass segmented toggle switches modes.

### Clusters
- Utility row: Back, Home, Keyboard, Power (power tinted red).
- Media row: rewind, play/pause, fast-forward.
- Volume capsule: volume down, mute, volume up; volume buttons auto-repeat while
  held (initial delay then repeating fire), implemented with a press-tracking
  gesture, not a timer-per-view.
- Every key press triggers `.sensoryFeedback(.impact)`.

### Pairing flow
- Phase-driven UI with animated transitions between connecting / code entry /
  paired / failed.
- Code entry is a 6-box segmented field backed by a hidden focused `TextField`
  (uppercased, filtered to the pairing alphabet), auto-submitting at 6 characters.
- Failure shakes the code boxes and fires `.sensoryFeedback(.error)`; success shows
  a bouncing checkmark seal and `.sensoryFeedback(.success)`.

### Forms
- Add TV: focus management (`@FocusState`), host validation hint, keyboard submit
  chaining, clearer field labeling with icons.
- TV Keyboard: same shell, plus a footer noting TV-side support is required.

## Components & files
- `RemoteRootView.swift` — navigation chrome, device menu, sheets, auto-connect.
- `RemoteControlSurface.swift` — layout, status banner, mode toggle, D-pad, clusters.
- `TouchpadView.swift` (new) — gesture pad with swipe/tap recognition + feedback.
- `RemoteControls.swift` (new) — shared button styles, hold-to-repeat button,
  glass panel helpers.
- `PairingView.swift`, `AddDeviceView.swift`, `TextEntryView.swift` — redesigned in
  place.
- `Pult.xcodeproj/project.pbxproj` — register the two new files (file refs, group
  children, sources build phase) so `make xcode-project-check` passes.

## Constraints
- `swift build` compiles the app target for macOS 26 too, so iOS-only APIs stay
  behind `#if os(iOS)`; haptics use cross-platform `.sensoryFeedback`.
- No `PultCore` behavior changes; no new dependencies.
- UI must remain usable on compact iPhone widths (AGENTS.md review focus).

## Error handling
- Connection failures: banner + retry, never dead-ends.
- Pairing failures: human-readable message from `RemoteControlModel.describe`,
  retry resets the code field.

## Testing / verification
- `make verify` (build, core-check, metadata-check, xcode-project-check).
- No core logic changes, so no new unit tests; UI behavior verified by build and
  manual device run (physical device required for network/haptics).
