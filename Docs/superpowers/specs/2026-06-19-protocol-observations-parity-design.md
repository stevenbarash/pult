# Protocol Observations Parity Design

## Goal

Bring Pult closer to `tronikos/androidtvremote2` protocol/state parity without
overclaiming Android TV Remote v2 as a full TV-state or media-state API.

Stage 1 is deliberately named **Protocol Observations**, not **TV State**. Pult
will decode and surface additional wire-level facts that the TV emits during the
remote protocol session, while preserving current command behavior and current
physical-validation claim boundaries.

## Context

Pult already implements the core Android TV Remote v2 path: discovery, pairing,
mutual TLS, command framing, key commands, app links, IME text entry, volume
updates, voice session frames, Live Activity controls, App Intents, and
diagnostics. The parity gap with `androidtvremote2` is now mostly about what
Pult observes from inbound protocol frames and how honestly it exposes those
observations.

The initial design was too broad in three places:

- It called IME-derived `app_package` a current-app feed. That is not proven.
- It risked treating `remote_start.started` as TV power state. That is not
  proven.
- It proposed dynamic feature negotiation before proving that changing Pult's
  existing `622` configure/set-active response is safe on the validated TV.

## Scope

### Stage 1: Protocol Observations

Implement read-only protocol observation parity:

- Decode inbound `remote_configure.code1` and `remote_configure.device_info`.
- Decode inbound `remote_start.started`.
- Decode inbound `remote_ime_key_inject.app_info`, especially `app_package`
  and optional label, while preserving any text-field status carried in the
  same frame.
- Decode `remote_ime_batch_edit` counters as first-class IME counters, while
  retaining Pult's existing text edit parsing where useful.
- Track all new protocol facts in `RemoteSession` as ephemeral,
  connection-scoped observations with source, timestamp, device identity, and
  connection attempt.
- Add a Diagnostics section named `Protocol Observations`.
- Include observations in copied diagnostics text.
- Update docs that currently say v2 exposes no current-app or power-related
  signals, replacing absolute claims with precise protocol-observation language.

### Stage 2: Physical Evidence Spike

Use the validated `Android.local` setup to capture real behavior before changing
product semantics:

- Does `remote_start` arrive on every connect?
- Does `remote_start(false)` ever appear, and what TV/user-visible state matches
  it?
- Does `remote_ime_key_inject.app_info` arrive only around text entry, or also
  during app switches?
- What raw `remote_configure.code1` and `remote_set_active.active` values appear
  on real hardware?
- Does preserving `622` remain required, or can a dynamic negotiated mask safely
  replace it?

### Stage 3: Product Promotion

Promote only observations that prove stable and useful:

- A text-entry surface may use IME app info to say which app/text field is
  asking for input.
- Diagnostics may become richer if observations prove consistent.
- Do not add an app-name dashboard, now-playing card, or power-state light
  unless a separate transport or real protocol evidence supports it.

### Out Of Scope

- Expanding the visible remote key catalog.
- Changing Live Activity controls.
- Adding Cast, MediaSession, ADB, or now-playing metadata.
- Persisting protocol observations as validation claims.
- Sending app package names to telemetry.
- Changing configure/set-active response behavior in Stage 1.

## Architecture

### Wire DTOs

`AndroidTVRemoteMessageCodec` remains policy-free. It decodes named protocol
payloads and encodes responses, but does not decide whether an observation is
user-visible, current, validated, or product-worthy.

Add protocol DTOs in `PultCore`:

- `RemoteDeviceInfo`: model, vendor, package name, app version, raw unknown
  values where retained.
- `RemoteConfigureRequest`: raw code, optional device info.
- `RemoteAppInfo`: package, label, counter, and raw fields retained when useful.
- `RemoteImeKeyInjectObservation`: optional app info plus optional text-field
  status.
- `RemoteImeBatchEditObservation`: IME counter, field counter, optional edit
  object parsed from the frame.
- `RemoteProtocolCode`: raw code plus decoded feature labels where known.

Update `IncomingRemoteMessage` to carry payloads:

- `.configure(RemoteConfigureRequest)`
- `.setActive`
- `.pingRequest(UInt64)`
- `.started(Bool)`
- `.volume(level:maximum:muted:)`
- `.textFieldStatus(RemoteTextFieldStatus)`
- `.imeKeyInject(RemoteImeKeyInjectObservation)`
- `.imeBatchEdit(RemoteImeBatchEditObservation)`
- `.voiceBegin(sessionID:)`
- `.error`
- `.other`

If one IME frame carries both app info and text-field status, the session must
update both. App info and text state are not mutually exclusive.

### Feature Codes

Add a small decoder for known raw bits:

- `ping = 1`
- `key = 2`
- `ime = 4`
- `voice = 8`
- `unknown1 = 16`
- `power = 32`
- `volume = 64`
- `appLink = 512`

Stage 1 treats these as diagnostics labels for raw protocol codes. It does not
replace Pult's current response policy.

Add `RemoteProtocolNegotiator` as a pure type, but start conservatively:

- default `clientResponseRawCode = 622`
- record inbound configure raw code
- record outbound configure/set-active raw code
- expose decoded labels for both raw values

Dynamic `supported intersection requested` negotiation is a later-stage change
after physical capture proves that changing `622` is safe.

### Session State

Add `RemoteProtocolObservation<Value>`:

- `value`
- `receivedAt`
- `deviceID`
- `connectionAttempt`
- `source`

Add `RemoteSessionProtocolState`:

- `remoteStart: RemoteProtocolObservation<Bool>?`
- `appInfo: RemoteProtocolObservation<RemoteAppInfo>?`
- `deviceInfo: RemoteProtocolObservation<RemoteDeviceInfo>?`
- `negotiation: RemoteProtocolObservation<RemoteProtocolNegotiation>?`

The state is in-memory and connection-scoped. It resets on connect, disconnect,
and failure. It must not be copied into persisted TV records or validation
passed areas.

`RemoteSession` remains the owner because it is already the MainActor observable
holder for connection state, text-field status, volume status, timestamps, and
the read loop.

### Device Freshness

Every observation is keyed to the session device and connection attempt. The
Diagnostics UI should display observations for `model.session.device`, not imply
they belong to `model.selectedDevice` when those differ.

Stage 1 should also fix the mismatch where selecting a different TV can leave an
old session's observations visible against the new selected TV. Preserve current
selection behavior and avoid disconnecting just because selection changed.
Diagnostics should label both the selected TV and the session TV, and protocol
observations should appear under the session TV. If there is no active session
device, the section should say `Not observed this session`.

## User-Facing Design

Add a new Diagnostics section after `Session`:

- `Protocol Remote Start`: `Observed started at 2:14 PM`, `Observed stopped at
  2:14 PM`, or `Not observed this session`.
- `Protocol App Info`: package and optional label, with `from IME key inject`.
- `Protocol Device Info`: model, vendor, package name, app version.
- `Protocol Configure Code`: inbound raw code plus decoded labels.
- `Protocol Client Code`: outbound raw code plus decoded labels.

The language must remain observational:

- Use `observed`, `reported`, `from IME`, and `this session`.
- Do not use `current app`, `TV is on`, `power state`, or `validated` for these
  rows unless later physical evidence and separate product decisions justify
  that wording.

Copied diagnostics should include the same rows. Validation reports should not.

## Documentation Changes

Replace absolute v2 ceiling statements with precise language:

> Android TV Remote v2 exposes commands plus opportunistic protocol
> observations: volume, connection liveness, text-field focus, `remote_start`,
> configure device info, and IME app package when emitted. It does not provide
> now-playing title/art/scrubber metadata, a stable foreground-app feed, or an
> authoritative TV power/standby state.

Docs to update during implementation:

- `Docs/LatencyMeasurementMethodology.md`
- `Docs/ProductStrategy.md`
- `Docs/superpowers/specs/2026-06-15-warm-live-session-design.md`
- `Docs/ProtocolSources.md`
- `README.md`, if its current scope bullets need a new diagnostics line

`Docs/ProtocolSources.md` also contains an obsolete sentence that names
`PlaceholderRemoteMessageCodec` as current deterministic test plumbing. The
implementation docs pass should correct that because Pult now has a real v2
wire codec.

## Error Handling

Observation decode failures should not break remote command sending.

- Malformed optional subfields become absent optional values.
- A fully undecodable frame can remain `.other` or `.error` according to current
  codec behavior.
- If `remote_ime_key_inject` has app info but malformed text status, preserve
  app info.
- If `remote_ime_key_inject` has text status but no app info, preserve text
  status.
- Attempt-scoped state updates must be ignored after a newer connection attempt
  starts.
- State mutations after `await send(...)` need a fresh attempt check.

## Testing

Use the repo's narrow checks:

- Codec tests for `remote_configure` payload decoding, device info parsing, IME
  app info parsing, combined IME app+text-field frames, IME batch counters,
  `remote_start`, and raw feature-code label decoding.
- Session tests for state reset on connect/disconnect/fail, attempt scoping,
  observation timestamps/device IDs, session-vs-selected-device behavior, and
  preserving existing configure/set-active response bytes.
- Core smoke updates in `Sources/PultCoreCheck/main.swift`.
- App diagnostics compile coverage through `make build`.
- `make core-check` for protocol/core changes.
- `make verify` after app diagnostics/docs integration, with known local
  sandbox/toolchain failure modes handled according to `AGENTS.md`.

Stage 1 must not require physical TV validation to merge, because it is decode
and diagnostics work. Stage 2 is the physical validation/capture task.

## Success Criteria

- Existing remote commands still use the same validated command path.
- Configure and set-active responses still use the current raw `622` behavior in
  Stage 1.
- The app can show copied diagnostics with remote start, IME app info, device
  info, and raw feature-code observations when frames are seen.
- Docs no longer say v2 has no current-app or power-related signal in absolute
  terms.
- Docs still make clear that v2 does not provide now-playing media metadata, a
  stable foreground-app feed, or authoritative power/standby state.
- No protocol observation is treated as a physical validation passed area.
