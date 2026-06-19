# Pult

Pult is a native SwiftUI Google TV remote for iOS 27 and later, with App Intents integration for Siri and system discovery. It implements Android TV Remote Service protocol v2, with separate layers for device discovery, pairing, mutual-TLS transport, command sessions, App Intents, and the main remote UI.

## Current Scope

- Bonjour/local-network discovery for Android TV Remote Service devices, command-port reachability probing, manual Google TV host entry fallback, and cached device records.
- Real v2 pairing on port 6467: pairing request/option/configuration exchange, 6-hex-digit code entry, and the SHA-256 certificate-bound pairing secret.
- Persistent RSA-2048 client identity (self-signed certificate built by `X509SelfSignedCertificate`, stored in the keychain) presented via mutual TLS on every connection.
- Command channel on port 6466: answers the TV's configure/set-active/ping messages and sends key presses and app links as protobuf `RemoteMessage`s.
- Hand-rolled protobuf wire coding (`ProtobufCoding`) covering the message subset in `Docs/Protocol/pairingmessage.proto` and `Docs/Protocol/remotemessage.proto` — no SwiftProtobuf dependency.
- Varint length-prefix framing used by Android TV Remote Service messages.
- Key-code mapping for remote, media, volume, and power actions.
- SwiftUI Liquid Glass remote surface with two navigation modes (swipe touchpad and ring d-pad), media controls, hold-to-repeat volume controls, device status, segmented-code pairing flow, and connection error detail.
- Saved-TV management sheet with native list editing, swipe-to-delete, and reorder support.
- Favorite app launcher with editable app-link shortcuts for common streaming apps and custom URLs.
- Diagnostics sheet with selected-TV/session/discovery details, protocol timestamps, volume/text-field status, copyable output, a guided validation runner, per-TV validation reports, and a persisted physical-device checklist. A stored validation report or explicit user/device evidence is the source for wording such as "validated on physical Google TV as of <date>" for the areas that passed.
- Reconnect-hardened command sending for app UI, favorite app links, and headless intents: stale sessions are refreshed before sending, and dead sends redial once before failing.
- Lock-screen Live Activity mini-remote with interactive App Intent buttons (d-pad, media, volume, power) designed to work without unlocking; locked/headless behavior is validated for `Android.local` as of 2026-06-11 and remains per-TV evidence for other devices.
- Control Center / Lock Screen / Action button controls: a "TV Remote" summon control, a configurable single-command control, and an open-app control.
- 14-command parameterized App Intents with Siri phrases, plus intents for opening the remote and summoning or dismissing the lock-screen session.
- Saved TVs exposed as App Intents entities so Siri, Shortcuts, and system controls can resolve a specific TV by name or host instead of relying only on the selected device.
- Saved TVs indexed for system search and donated as recent remote actions; controls can target either the selected TV or a configured TV.
- App Intent parameter summaries keep Shortcuts and Control configuration readable when actions include both a command and a TV.
- Widget and Live Activity glyphs opt into full-color accented rendering so status and command affordances stay legible under iOS 27 system tinting.
- App Group device store shared between app and intents, with persisted device selection.
- mTLS client identity stored with after-first-unlock keychain protection so headless intents can dial while the device is locked.
- TV keyboard sheet backed by v2 IME field-status messages and batch-edit text insertion; end-to-end keyboard behavior is validated for `Android.local` as of 2026-06-11 and remains per-TV evidence for other devices.
- Voice search starts the TV's v2 voice session and streams iPhone microphone audio as PCM 16-bit mono 8 kHz chunks. End-to-end voice behavior remains per-TV unvalidated until a Diagnostics/checklist report or explicit user/device evidence records it.

## Physical Validation

All current setup, pairing, discovery/reachability, command-channel, remote
control, keyboard, favorite app link, lock-screen/headless, Control Center,
Siri/Shortcuts, and background-reconnect areas are validated on physical Google
TV as of 2026-06-11 for `Android.local` (host `Android.local`). The detailed
evidence record lives in `Docs/PhysicalDeviceValidationChecklist.md`.

## Privacy Metadata

The app declares `NSLocalNetworkUsageDescription` and the Android TV Remote Service Bonjour types in `Sources/PultApp/Supporting/Info.plist`. Nearby discovery scans `_androidtvremote2._tcp` and `_androidtvremote._tcp` when the Add TV flow opens or when the user retries a scan, which is when iOS may present the Local Network prompt. Found TVs are probed on their command port so the UI can distinguish found, reachable, pairing-required, paired, and unavailable states. The Add TV flow explains retry and Settings recovery without treating local-network permission as a directly readable authorization status. Manual IP entry remains available for TVs, routers, or permission states that do not advertise or scan reliably.

## Observability

Pult emits privacy-safe `OSLog` telemetry for app launch, MetricKit setup,
discovery, reachability, pairing, remote commands, session connection, and TV
keyboard sends. MetricKit is registered at app launch when available. The Xcode
app target links the PostHog iOS SDK and reads `PultPostHogProjectToken` from
`Sources/PultApp/Supporting/Info.plist`; SwiftPM-only checks keep the PostHog
import compile-gated. Diagnostics command timing is off by default; when the
Diagnostics toggle is enabled, timing samples write locally and emit
privacy-safe `command_timing_recorded` events to PostHog. See
`Docs/Observability.md`.

## Build

```sh
swift build
swift run PultCoreCheck
```

For the default local verification path, run:

```sh
make verify
```

To fully build the installable Xcode app from the CLI, including the widget
extension and App Intents metadata, run:

```sh
make verify-full
```

`verify-full` uses full Xcode through `XCODE_DEVELOPER_DIR`, defaulting to
`/Applications/Xcode-beta.app/Contents/Developer` for the iOS 27 SDK. If you
want a different Xcode, override it:

```sh
make verify-full XCODE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

Command Line Tools alone are not enough for the full app build. The full target
builds the `Pult` scheme for `generic/platform=iOS Simulator` with DerivedData
inside `.build/XcodeDerivedData`. For a signing-aware Release/device CLI build,
use `make xcode-build-device`.

After a change has been confirmed working and is ready for internal TestFlight,
run:

```sh
make ship-testflight MESSAGE="describe the shipped change"
```

Preview the release path without committing, pushing, archiving, or uploading:

```sh
make ship-testflight DRY_RUN=1 MESSAGE="describe the shipped change"
```

For a device build, open `Pult.xcodeproj` in Xcode, select the `Pult Release Direct` scheme for physical beta devices, choose your iPhone as the run destination, set your signing team and bundle identifier, then press Run. Opening `Package.swift` only builds SwiftPM products and may not install an iOS app bundle. The `Pult` scheme also builds and embeds the `PultWidgets` extension (Live Activity remote and controls).

Local-network permission, TLS behavior, haptics, pairing, keyboard input, and locked/headless controls need a physical iPhone on the same network as the Google TV to validate end to end. Re-run validation from the Diagnostics sheet for the selected TV, then use `Docs/PhysicalDeviceValidationChecklist.md` to capture manual evidence: date, device name, host, and passed areas. Docs may say "validated on physical Google TV as of YYYY-MM-DD" only for areas backed by a stored validation report or explicit user/device evidence; otherwise, describe the area as unvalidated for that TV.

The `Tests/PultCoreTests` files use Swift Testing. This workspace currently uses Command Line Tools only, so `PultCoreCheck` is the runnable SwiftPM verification path if `swift test` cannot import `Testing`.

## Agentic Development

Repo-specific agent guidance lives in `AGENTS.md`. The applied iOS agent workflow is documented in `Docs/AgenticIOSWorkflow.md`.

Use these conventions when working with Codex, Xcode coding agents, or other agentic tools:

- keep prompts scoped with goal, context, constraints, and done criteria;
- run deterministic checks before handoff;
- prefer direct Xcode schemes on beta devices before changing app code for debugger-injection crashes;
- treat the pairing and command protocol as reference-faithful, and treat real-device behavior as per-TV evidence: unvalidated until Diagnostics/checklist evidence exists, then "validated on physical Google TV as of YYYY-MM-DD" only for the passed areas.
