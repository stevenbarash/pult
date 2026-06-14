# Agent Instructions

## Project Shape

- `Sources/PultApp`: SwiftUI iOS app target, App Intents, Xcode device-run surface.
- `Sources/PultCore`: protocol, transport, storage, session, and model code shared by app and checks.
- `Sources/PultWidgets`: WidgetKit appex (Live Activity remote + controls), Xcode-only target — not part of Package.swift.
- `Sources/PultCoreCheck`: runnable SwiftPM smoke checks for environments where `swift test` is not usable.
- `Tests/PultCoreTests`: Swift Testing unit tests for full Xcode/Swift toolchains.
- `Pult.xcodeproj`: device-installable iOS app project. `Package.swift` alone does not install an iOS app bundle.

## Current Scope Boundaries

- Pairing, mutual TLS with a persistent client identity, and the v2 `RemoteMessage` codec are implemented against the protocol references vendored in `Docs/Protocol/` and have unit/check coverage. End-to-end physical-TV control is per saved TV: unvalidated until a stored validation report or explicit user/device evidence exists, then documented only as "validated on physical Google TV as of YYYY-MM-DD" for the passed areas.
- Text entry over the v2 IME channel is implemented from the TV's published IME field status and has unit/check coverage. Keyboard behavior is unvalidated for a TV until the Diagnostics validation report or explicit user/device evidence shows the keyboard area passed.
- Bonjour/local-network discovery is implemented for Android TV Remote Service Bonjour types with manual IP entry as the required fallback. Discovery and reachability are unvalidated for a TV/network until a physical-device validation report or explicit user/device evidence records the scan/manual-host and reachability result.
- `Pult Direct` and `Pult Release Direct` schemes exist because iOS beta device runs may crash under Xcode debugger injection.
- The lock-screen remote (Live Activity, controls, and headless intents) is implemented. Locked/headless behavior is unvalidated for a TV until a physical-device validation report or explicit user/device evidence records those areas as passed.

## Known Physical Validation Evidence

- `Android.local` (`host: Android.local`) is validated on physical Google TV as
  of 2026-06-11 by explicit user/device evidence. Passed areas: setup,
  discovery/reachability, pairing, command channel, protocol handshake, d-pad,
  select, back, home, media controls, volume, mute, power behavior, keyboard
  text entry, favorite app links, Lock Screen Live Activity, locked command
  sending, Control Center TV Command, Siri/Shortcuts command, and background
  reconnect. Keep validation claims scoped to this TV unless another TV has its
  own stored validation report or explicit user/device evidence.

## Verification

Use the narrowest check that matches the change:

- Core or UI source changes: `make build`
- Core behavior changes: `make core-check`
- Test changes or full Xcode toolchain available: `swift test`
- App/core Swift file additions or moves: `make xcode-project-check`
- Project/scheme/plist edits: `xmllint --noout Pult.xcodeproj/xcshareddata/xcschemes/*.xcscheme` and `plutil -lint Pult.xcodeproj/project.pbxproj Sources/PultApp/Supporting/Info.plist Sources/PultWidgets/Supporting/Info.plist Sources/PultApp/Pult.entitlements Sources/PultWidgets/PultWidgets.entitlements` (see `make metadata-check`)
- Full installable-app CLI build, including Xcode target membership, widget extension, App Intents metadata, and SDK availability: `make verify-full`. It defaults to `XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; override that variable if another full Xcode should be used. Command Line Tools alone are not enough.

Prefer `make verify` for the default local agent check. It redirects `HOME` into `.build/home` and uses SwiftPM's `--disable-sandbox` flag because Codex already provides the outer workspace sandbox and this local Command Line Tools install can fail when nested SwiftPM tooling writes outside the workspace.
It also checks that Swift files in `Sources/PultApp`, `Sources/PultCore`, and `Sources/PultWidgets` are present in the matching Xcode groups and target source build phases.

`swift test` may fail in command-line-tool-only environments with `no such module 'Testing'`. Treat that as a toolchain issue if `swift build` and `swift run PultCoreCheck` pass; use Xcode 26+ or a matching full Xcode developer directory for Swift Testing.

## Device Runs

- Use `Pult Release Direct` first on physical iOS beta devices.
- If debugging is needed, try `Pult Direct` before the normal `Pult` scheme.
- If a device crash stops in `__abort_with_payload`, collect the full crash report or device console backtrace. The trap frame alone is not enough to identify the caller.
- Clean build folder and delete the app from the device after changing bundle, framework, scheme, or signing settings.

## Coding Rules

- Keep SwiftUI state local unless a feature needs shared state. Use `@Observable`, `@State`, `@Bindable`, and explicit injection consistently with the existing code.
- Prefer `.task` / `.task(id:)` for lifecycle-bound async work, and add cancellation or timeout handling for long-running network operations.
- Keep network protocol code in `PultCore`; keep SwiftUI view code in `PultApp`.
- Do not add real protocol claims without tests plus either a stored validation report or explicit user/device evidence. Update docs to say "validated on physical Google TV as of YYYY-MM-DD" only when backed by that evidence, and name only the passed areas.
- Do not introduce new production dependencies without explaining why they are needed and how they are verified.

## Review Focus

Before handing work back, check:

- app still builds;
- smoke check passes when core logic changed;
- Xcode project metadata remains valid when project files changed;
- UI remains usable on compact iPhone widths;
- remote/pairing behavior is not overstated beyond implemented protocol support.
