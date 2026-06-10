# Lock-Screen Remote ("Pult Anywhere") — Design

**Date:** 2026-06-10
**Status:** Awaiting user review

## Goal

Control a paired Google TV from the iPhone lock screen without unlocking, getting as
close as iOS 26 public APIs allow to the system Apple TV Remote experience.

## What iOS 26 allows (and doesn't)

- A full interactive third-party UI on the lock screen (swipe touchpad, gestures) is
  **not possible** — that is a private system surface.
- **Live Activities** render on the lock screen and Dynamic Island and may contain
  `Button(intent:)` controls. Buttons fire App Intents **without unlocking**. A
  `LiveActivityIntent` runs **in the app's process**, so it can reuse the app's
  transport stack. Lock-screen presentation height is capped (~160 pt). Buttons only —
  no drags, no long-press, so no touchpad and no hold-to-repeat volume.
- **Controls** (`ControlWidget`, iOS 18+) are single App Intent-backed buttons/toggles
  that surface in Control Center, the two lock-screen slots, and the Action button.
  They also run without unlocking when the intent does not open the app.
- **Interactive snippets** (`SnippetIntent`, new in iOS 26) show interactive SwiftUI
  over Siri/Spotlight/Shortcuts results — but **cannot be launched from controls**, so
  they are a stretch goal, not the core.
- Intents that run while the device is locked cannot read keychain items protected at
  the default `kSecAttrAccessibleWhenUnlocked` level. Pult's mTLS client identity
  currently uses that default, so every locked-screen send would fail today.

## Approaches considered

1. **Live Activity remote + controls (chosen).** A persistent mini-remote on the lock
   screen while a session is active, plus one-tap controls for summoning it and for
   single commands. Most capable; needs a new widget extension target and an
   app-process headless send path.
2. **Controls only.** Much less plumbing, but each surface is a single button — no
   d-pad, no remote "surface." Rejected as the end state; controls are still included
   as part of approach 1.
3. **Now Playing / notification surfaces.** Media-key-only, wrong interaction model
   for a d-pad remote. Rejected.

## User experience

- **Summon:** pressing the **"TV Remote" control** (lock-screen slot, Control Center,
  or Action button) runs `StartRemoteSessionIntent`: the app wakes in the background,
  connects to the selected paired TV, and a Live Activity mini-remote appears on the
  lock screen. Connecting in the foreground app starts the same Live Activity
  automatically (on by default; toggleable later if it proves noisy).
- **Use:** the Live Activity shows a d-pad cluster (up/down/left/right/select), back,
  home, play/pause, volume −/+, mute, and power, plus the device name and a
  connection-status indicator. Every press fires `SendRemoteKeyIntent` without
  unlocking. The Dynamic Island expanded view shows a media row (back, play/pause,
  vol −/+, home); compact shows a TV glyph plus status dot.
- **Errors:** a failed send flips the activity's status line to a short message
  ("Couldn't reach Living Room TV") and the status dot to red; the next successful
  press clears it.
- **Dismiss:** an ✕ button in the activity runs `EndRemoteSessionIntent`
  (disconnect + end activity). Activities also end via the system 8-hour limit with a
  stale appearance after a `staleDate`.
- **Siri:** parameterized App Shortcuts ("Pause the TV with Pult", "TV remote") work
  from the lock screen as another no-unlock path.

## Architecture

New pieces, by layer:

### PultCore (must keep building on macOS CLT — no ActivityKit/AppIntents imports)

- **Keychain accessibility migration** (`ClientIdentity.swift`): create the private
  key and certificate with `kSecAttrAccessibleAfterFirstUnlock`; on load, detect
  legacy items and `SecItemUpdate` them to the new accessibility class. Without this,
  locked-screen mTLS fails. (Effective verification is device-only; unit tests cover
  the attribute dictionaries via injection where practical.)
- **Shared device store:** `UserDefaultsDeviceStore` moves to the App Group suite
  `group.app.pult` with a one-time migration from `UserDefaults.standard`. Device
  *selection* becomes persisted (`pult.selectedDeviceID`) instead of "first device
  wins", because intents need to know which TV to dial; the app UI reads/writes the
  same selection.
- **`RemoteControlModel.performHeadlessCommand(_:)`** (new): the single entry point
  intents call. Reuses the live `RemoteSession` when connected, otherwise dials and
  awaits the configure handshake, then sends the key — and redials once when a
  session that still claims "connected" turns out dead (the normal case after the
  app sat suspended in the background). The connection then stays open for as long
  as iOS keeps the process alive, so rapid follow-up presses reuse it. Covered by
  Swift Testing tests with mock transports.

### PultApp (shared-membership intent files compiled into app + widget targets)

- **`SendRemoteKeyIntent: LiveActivityIntent`** (`openAppWhenRun = false`) — parameter
  is a new `RemoteKeyEntity`/`AppEnum` covering all 14 `RemoteKey` cases. Runs in the
  app process: resolves the selected device, sends via `HeadlessCommandService`,
  updates the Live Activity content state. Replaces `SendRemoteCommandIntent` and the
  `SharedIntentCommandQueue` enqueue-and-hope mechanism, which is deleted.
- **`StartRemoteSessionIntent: LiveActivityIntent`** — connect + start (or refresh)
  the Live Activity from anywhere intents run, including controls.
- **`EndRemoteSessionIntent`** — disconnect + end the activity.
- **`OpenRemoteIntent`** stays as-is (full app UI, requires unlock by design).
- **`PultShortcuts`** updated: parameterized phrases for `SendRemoteKeyIntent`
  ("Pause the TV with \(.applicationName)") and a "TV remote" phrase for
  `StartRemoteSessionIntent`; the dead `SendRemoteCommandIntent` shortcut is removed.
- **`RemoteActivityController`** (app-side) — owns `Activity<RemoteSessionAttributes>`
  lifecycle: start on connect, update on `ConnectionState` change and send errors,
  end on disconnect. The app exposes one process-wide `RemoteControlModel` (promoted
  from `@State` in `PultApp` to a shared instance) so intents and UI drive the same
  session.
- **`RemoteSessionAttributes: ActivityAttributes`** — fixed: device id + name;
  `ContentState`: status (connecting/connected/failed), optional short message.

### PultWidgets (new WidgetKit extension target, embedded in Pult)

- **Live Activity widget** — lock-screen view (≤160 pt: header with device name,
  status dot, power, ✕; d-pad cluster; media/volume cluster) and Dynamic Island
  presentations. iOS 26 Liquid Glass styling comes from the system; tint via
  `activityBackgroundTint` to match `.pultAccent`.
- **Controls:**
  - `RemoteSessionControl` — "TV Remote" button running `StartRemoteSessionIntent`
    (the lock-screen-slot hero).
  - `RemoteCommandControl` — user-configurable single-command button
    (`AppIntentControlConfiguration` + config intent choosing the command; default
    play/pause).
  - `OpenRemoteControl` — opens the app to the full touchpad.
- Extension links the `PultCore` framework; intent + attribute files have dual target
  membership.

### Project plumbing

- New `PultWidgets` appex target in `Pult.xcodeproj` (iOS 26 min, same team/bundle
  prefix: `app.pult.Pult.PultWidgets`), embedded in the app target.
- App + extension entitlements: App Group `group.app.pult`.
- App `Info.plist`: `NSSupportsLiveActivities = YES`.
- `make xcode-project-check` extended to cover `Sources/PultWidgets`.

## Data flow (locked-screen press)

1. User taps "volume up" in the Live Activity.
2. System runs `SendRemoteKeyIntent` in the Pult app process (launched in the
   background if needed; no unlock prompt because `openAppWhenRun = false`).
3. Intent reads the selected `DeviceRecord` from the App Group store, calls
   `HeadlessCommandService`, which reuses the lingering connection or performs a fast
   mTLS connect (identity now readable after first unlock) → configure → key press.
4. Intent updates the activity content state (status/error) and returns. Failures
   surface in the activity, never as an unlock prompt.

## Out of scope

- Swipe touchpad or any gesture input on the lock screen (API doesn't exist).
- Hold-to-repeat volume in the Live Activity (buttons can't long-press).
- Push-token (remote) Live Activity updates; local updates only.
- Interactive snippets (Siri/Spotlight remote popup) — optional follow-up, kept out of
  the first cut since they can't launch from controls and locked behavior is unverified.
- Apple Watch, accessory lock-screen widgets, text entry.

## Risks / device-only verification

Per AGENTS.md, no protocol or behavior claims without device evidence. These need a
physical iPhone + Google TV: intent execution while locked, keychain access after
first unlock, background local-network access, cold-connect latency per press
(~2 round trips on LAN, expected well under a second), Live Activity update budget.
`make verify`, `swift test`, and `PultCoreCheck` cover everything testable off-device
(store migration, headless service logic, codec/framing unchanged).
