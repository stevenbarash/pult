# Physical Device Validation Checklist

Use this checklist before claiming Pult works end to end with a specific Google
TV. Local builds and protocol checks are necessary, but they do not prove
behavior on a real TV.

Physical-device claims are per TV and per area. Until a stored validation report
or explicit user/device evidence exists, describe pairing, discovery, keyboard,
remote controls, and system-surface behavior as unvalidated for that TV. After
evidence exists, docs may say "validated on physical Google TV as of YYYY-MM-DD"
only for the areas that passed.

The in-app Diagnostics sheet includes a guided validation runner. Use it first,
and re-run it whenever protocol, discovery, pairing, intent, widget, entitlement,
signing, or storage behavior changes:
it records the selected TV, pairing state, fresh connection result, protocol
traffic timestamps, Bonjour visibility, command-port reachability, keyboard
readiness, and manual command checks. Manual rows send a command, then wait for
you to mark pass or fail after watching the TV.

Diagnostics may also copy and persist a Stage 2 protocol evidence block with
session-scoped observations such as configure/set-active feature codes, device
info, IME app observations, IME batch summaries, and `remote_start.started` when
the TV publishes them. Saved evidence includes per-observation provenance and
per-question status rows for the Stage 2 parity questions. These are useful
debugging context, but they do not pass any physical-validation area by
themselves and must not be cited as proof of foreground-app, power-state,
now-playing, or dynamic-negotiation behavior.

## Evidence To Record

- Date: `YYYY-MM-DD`, matching the day the real-device validation was run.
- Device name: the selected saved TV name shown in Pult.
- Host: the selected TV host or IP address shown in Diagnostics.
- Passed areas: list only areas that passed, such as discovery, reachability,
  pairing, command handshake, keyboard, d-pad, media, volume, favorite app links,
  lock-screen Live Activity, Control Center, Siri/Shortcuts, and background
  reconnect.

The copied Diagnostics validation report can supply the device name, host,
timestamps, summary, step results, and the Stage 2 protocol evidence block when
the active session matches the selected TV. The checklist below is the manual
record for observations that require watching the TV or using system surfaces.

## Recorded Physical Validation

- Date: `2026-06-11`
- Device name: `Android.local`
- Host: `Android.local`
- Evidence source: user/device validation on a physical iPhone and Google TV.
- Passed areas: setup, same-Wi-Fi reachability, Bonjour/manual-host path,
  pairing, command channel, protocol handshake, d-pad, select, back, home, media
  controls, volume, mute, power behavior, keyboard text entry, favorite app
  links, Lock Screen Live Activity, locked command sending, Control Center TV
  Command, Siri/Shortcuts command, and background reconnect.

Pult may describe those areas as "validated on physical Google TV as of
2026-06-11" for `Android.local`. Other TVs still need their own validation
record before receiving the same claim.

## Setup

- iPhone and Google TV are on the same Wi-Fi network.
- The TV is awake and visible on the network.
- The TV appears in Bonjour discovery, or manual host entry reaches the command
  port.
- Pairing accepts the 6-character code shown on the TV.
- The command channel reaches Online after pairing.

## Remote Controls

- D-pad moves focus up, down, left, and right.
- Select activates the focused item.
- Back returns inside an app.
- Home returns to Google TV home.
- Play/pause, rewind, and fast-forward work in at least one video app.
- Volume up, volume down, and mute work with the TV's configured volume route.
- Power behavior matches the TV model's supported sleep or wake behavior.
- Keyboard text entry works in a focused TV text field, including delete and
  enter.
- Favorite app links open the intended TV app or the expected fallback target.

## System Surfaces

- Starting the remote from Pult shows the Lock Screen Live Activity.
- A Live Activity command sends while the iPhone is locked.
- A Control Center TV Command sends to the selected or configured TV.
- A Siri or Shortcuts command sends to a named TV.
- The app reconnects cleanly after being backgrounded and resumed.

## Diagnostics To Capture On Failure

- Selected TV name, host, command port, and pairing port.
- Pairing state and connection state.
- Last sent and last received protocol timestamps.
- Last protocol or transport error.
- Discovery state, selected-TV source, and command-port reachability.
- Latest volume state, if reported by the TV.
- Latest focused TV text field status, if text entry is being tested.
- The latest validation report summary for the selected TV, including date,
  device name, host, and passed areas.

The in-app Diagnostics sheet can copy these values while testing.
