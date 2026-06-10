# Pult

Pult is a native SwiftUI Google TV remote for iOS 26 and later. It implements Android TV Remote Service protocol v2, with separate layers for device discovery, pairing, mutual-TLS transport, command sessions, App Intents, and the main remote UI.

## Current Scope

- Manual Google TV host entry and cached device records.
- Real v2 pairing on port 6467: pairing request/option/configuration exchange, 6-hex-digit code entry, and the SHA-256 certificate-bound pairing secret.
- Persistent RSA-2048 client identity (self-signed certificate built by `X509SelfSignedCertificate`, stored in the keychain) presented via mutual TLS on every connection.
- Command channel on port 6466: answers the TV's configure/set-active/ping messages and sends key presses and app links as protobuf `RemoteMessage`s.
- Hand-rolled protobuf wire coding (`ProtobufCoding`) covering the message subset in `Docs/Protocol/pairingmessage.proto` and `Docs/Protocol/remotemessage.proto` — no SwiftProtobuf dependency.
- Varint length-prefix framing used by Android TV Remote Service messages.
- Key-code mapping for remote, media, volume, and power actions.
- SwiftUI Liquid Glass remote surface with two navigation modes (swipe touchpad and ring d-pad), media controls, hold-to-repeat volume controls, device status, segmented-code pairing flow, and connection error detail.
- App Intents for opening the remote and a small set of high-value commands.

Text entry over the v2 IME channel is not implemented yet; the text command reports "not supported" instead of sending bytes the TV would reject.

## Privacy Metadata

The app declares `NSLocalNetworkUsageDescription` in `Sources/PultApp/Supporting/Info.plist`. Bonjour service types are not declared yet because the v2 references are inconsistent across devices; the MVP supports manual IP entry and cached records.

## Build

```sh
swift build
swift run PultCoreCheck
```

For the default local verification path, run:

```sh
make verify
```

For a device build, open `Pult.xcodeproj` in Xcode, select the `Pult Release Direct` scheme for physical beta devices, choose your iPhone as the run destination, set your signing team and bundle identifier, then press Run. Opening `Package.swift` only builds SwiftPM products and may not install an iOS app bundle.

Local-network permission, TLS behavior, haptics, and real pairing need a physical device on the same network as the Google TV.

The `Tests/PultCoreTests` files use Swift Testing. This workspace currently uses Command Line Tools only, so `PultCoreCheck` is the runnable SwiftPM verification path if `swift test` cannot import `Testing`.

## Agentic Development

Repo-specific agent guidance lives in `AGENTS.md`. The applied iOS agent workflow is documented in `Docs/AgenticIOSWorkflow.md`.

Use these conventions when working with Codex, Xcode coding agents, or other agentic tools:

- keep prompts scoped with goal, context, constraints, and done criteria;
- run deterministic checks before handoff;
- prefer direct Xcode schemes on beta devices before changing app code for debugger-injection crashes;
- treat the pairing and command protocol as reference-faithful but pending validation against a physical Google TV.
