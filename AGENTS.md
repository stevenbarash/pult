# Agent Instructions

## Project Shape

- `Sources/PultApp`: SwiftUI iOS app target, App Intents, Xcode device-run surface.
- `Sources/PultCore`: protocol, transport, storage, session, and model code shared by app and checks.
- `Sources/PultCoreCheck`: runnable SwiftPM smoke checks for environments where `swift test` is not usable.
- `Tests/PultCoreTests`: Swift Testing unit tests for full Xcode/Swift toolchains.
- `Pult.xcodeproj`: device-installable iOS app project. `Package.swift` alone does not install an iOS app bundle.

## Current Scope Boundaries

- Pairing, mutual TLS with a persistent client identity, and the v2 `RemoteMessage` codec are implemented against the protocol references vendored in `Docs/Protocol/`. They have unit/check coverage but still need validation against a physical Google TV before claiming end-to-end control works.
- Text entry over the v2 IME channel is not implemented; `RemoteCommand.text` throws `unsupportedCommand`.
- Manual IP entry is the supported device-discovery path. Bonjour/local-network service discovery is not implemented yet.
- `Pult Direct` and `Pult Release Direct` schemes exist because iOS beta device runs may crash under Xcode debugger injection.

## Verification

Use the narrowest check that matches the change:

- Core or UI source changes: `make build`
- Core behavior changes: `make core-check`
- Test changes or full Xcode toolchain available: `swift test`
- App/core Swift file additions or moves: `make xcode-project-check`
- Project/scheme/plist edits: `xmllint --noout Pult.xcodeproj/xcshareddata/xcschemes/*.xcscheme` and `plutil -lint Pult.xcodeproj/project.pbxproj Sources/PultApp/Supporting/Info.plist`

Prefer `make verify` for the default local agent check. It redirects `HOME` into `.build/home` and uses SwiftPM's `--disable-sandbox` flag because Codex already provides the outer workspace sandbox and this local Command Line Tools install can fail when nested SwiftPM tooling writes outside the workspace.
It also checks that Swift files in `Sources/PultApp` and `Sources/PultCore` are present in the matching Xcode groups and target source build phases.

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
- Do not add real protocol claims without tests or device evidence.
- Do not introduce new production dependencies without explaining why they are needed and how they are verified.

## Review Focus

Before handing work back, check:

- app still builds;
- smoke check passes when core logic changed;
- Xcode project metadata remains valid when project files changed;
- UI remains usable on compact iPhone widths;
- remote/pairing behavior is not overstated beyond implemented protocol support.
