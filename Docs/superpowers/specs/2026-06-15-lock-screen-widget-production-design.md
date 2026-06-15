# Lock Screen Widget Production Design

**Date:** 2026-06-15
**Status:** Approved for implementation planning

## Goal

Make Pult's Lock Screen remote feel production-ready by combining fast physical-remote muscle memory with larger targets for the most common couch-side commands: play/pause, mute, and volume.

## Approved Direction

Pult will ship a media-weighted **Hybrid** Live Activity layout as the default. It keeps directional navigation visible, but gives playback and sound controls the most visual weight. Users can switch the Live Activity to a **Media** layout in app settings when they mainly use Pult for pause, mute, and volume.

This is intentionally not a fully custom per-button Live Activity grid. The Control Center command widget already handles single-command customization better than a dense Lock Screen settings system would. The Live Activity should preserve predictable muscle memory.

## UX

### Hybrid Layout

Hybrid is the default Lock Screen layout.

- D-pad stays visible for menu browsing: up, down, left, right, and select.
- Play/pause and mute become the largest buttons.
- Volume down and volume up become prominent medium buttons near play/pause and mute.
- Back, home, power, and dismiss remain available without competing with the high-frequency controls.
- Status remains compact: device name, connection state, stale state, and short failure text when needed.

### Media Layout

Media is the alternate user-selected layout.

- Play/pause, mute, volume down, and volume up dominate the surface.
- Back, home, rewind, and fast-forward remain one tap away.
- D-pad is reduced or omitted from the Lock Screen view because the user chose playback control over navigation density.
- Dynamic Island expanded presentation follows the same media-first priority.

### Control Center And Action Button

Existing configurable command controls remain the right customization path for one-off commands.

- The session control starts or refreshes the Live Activity for a configured or selected TV.
- The command control stays configurable by TV and remote command.
- The open-remote control continues to open the full app and can require unlock.

## In-App Customization

Add a small settings surface for Lock Screen behavior. It should be reachable from the main remote UI and use native controls, not a decorative custom settings page.

Settings:

- `Lock Screen Layout`: segmented control with `Hybrid` and `Media`.
- Default value: `Hybrid`.
- Storage: App Group defaults so the app, intents, controls, and widget extension agree.
- Scope: global for this implementation. Per-TV layout can be added later if real user behavior proves it necessary.

The settings UI should not introduce new protocol claims. It controls presentation only.

## Architecture

### Shared Preference

Create a small shared type for the Lock Screen layout preference in code compiled by both the app and widget extension.

Required model:

- `RemoteActivityLayout`: `Codable`, `Hashable`, and `CaseIterable`.
- Cases: `hybrid`, `media`.
- Stable raw values for persistence.
- Display title and short description for settings UI.

Persist the selected layout in `PultAppGroup.sharedDefaults()` under a dedicated key such as `pult.remoteActivityLayout`. Unknown or missing values fall back to `hybrid`.

### Live Activity State

Extend `RemoteSessionAttributes.ContentState` with the selected layout. The widget should render directly from `context.state.layout` so a preference change can update an active Live Activity without waiting for a command press.

`RemoteActivityController` should read the shared preference when building activity content. It should also expose a refresh path that updates existing activities when the user changes the setting in the app.

### App Settings Entry

Add a focused settings sheet or section from the main remote surface. The smallest production path is a `LockScreenRemoteSettingsView` presented from the existing device/title menu or command palette. It should:

- Show the current layout in a segmented picker.
- Explain the two modes with short, concrete text.
- Update the shared preference immediately.
- Refresh the active Live Activity after changes.

### Widget Rendering

Refactor `RemoteLiveActivity.swift` so layout variants are explicit rather than tangled in conditionals.

Expected units:

- `SupplementalMediumRemoteView`: routes to Hybrid or Media.
- `HybridRemoteLayout`: default layout, d-pad plus large media controls.
- `MediaRemoteLayout`: alternate playback-first layout.
- Shared button components continue to enforce at least 44 point hit areas.
- Status components remain shared.

Dynamic Island:

- Compact/minimal states can stay simple: TV glyph plus status.
- Expanded state should respect the selected layout where practical.
- For Hybrid, keep play/pause central and common media controls in the bottom row.
- For Media, prioritize play/pause, mute, volume, rewind, and fast-forward.

## Error Handling

The layout preference must never block remote commands.

- Missing App Group defaults fall back to Hybrid.
- Invalid persisted values fall back to Hybrid.
- If a Live Activity update fails, the app should continue saving the preference; the next activity start will use it.
- Existing command failure messages remain scoped to connection or send failures.

## Accessibility And Production UI Requirements

- Preserve 44 point minimum hit targets for every tappable command.
- Do not rely on color alone for connection state.
- Keep labels explicit: "Play or Pause", "Mute", "Volume Up", and "Volume Down".
- Avoid fixed text that can collide inside compact Live Activity bounds.
- Keep the visual treatment native and quiet: no decorative gradients, no novelty icons, no extra chrome.
- Use SF Symbols only for functional icons.

## Verification

Required checks after implementation:

- `make build` for app and shared Swift source changes.
- `make core-check` if shared core behavior or persistence helpers are added to `PultCore`.
- `make xcode-project-check` if Swift files are added or moved.
- `make metadata-check` if project, scheme, plist, or entitlement metadata changes.
- `make verify-full` because WidgetKit, ActivityKit, and App Intents surfaces are in scope.

Physical validation claims remain scoped per AGENTS.md. Do not claim a new TV or new locked-device behavior is physically validated unless a validation report or explicit user/device evidence exists.

## Out Of Scope

- Fully custom per-button Live Activity grid.
- Adaptive automatic layout switching based on recent commands.
- Swipe touchpad or hold-to-repeat on the Lock Screen.
- Per-TV layout settings.
- New protocol behavior.
- New production dependencies.
