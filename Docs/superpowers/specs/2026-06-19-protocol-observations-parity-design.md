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
- Decode inbound `remote_set_active.active` when present. If the frame is
  empty, record an observed set-active request with `active = nil`.
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

Use the known-working `Android.local` setup to capture real behavior before
changing product semantics:

- Does `remote_start` arrive on every connect?
- Does `remote_start(false)` ever appear, and what TV/user-visible state matches
  it?
- Does `remote_ime_key_inject.app_info` arrive only around text entry, or also
  during app switches?
- What raw `remote_configure.code1` and `remote_set_active.active` values appear
  on real hardware?
- Does preserving `622` remain required, or can a dynamic negotiated mask safely
  replace it?

The app should make these captures repeatable by saving a local protocol
evidence block with validation reports. The block is diagnostic evidence only:
it can carry raw masks, `remote_start`, configure device info, IME app info, and
IME batch counters, but it must not pass validation areas or change product
claims by itself.

#### Remaining Stage 2 / Parity TODO

- Run repeated fresh-connect evidence captures on `Android.local` and at least
  one additional TV, saving the copied validation reports for comparison.
- Record whether `remote_start` appears on every connect, only after particular
  TV states, or only from specific Android TV Remote Service builds.
- Capture any observed `remote_start(false)` event with simultaneous manual
  notes for TV wake/sleep, foreground app, and visible playback state.
- Switch apps while no text field is focused, then focus text fields in multiple
  apps, to determine whether `remote_ime_key_inject.app_info` is IME-scoped or
  a broader app signal.
- Compare raw configure and set-active feature masks across sessions, TVs, and
  service versions before changing the fixed `622` client response.
- Keep dynamic negotiation disabled until repeated physical captures prove a
  negotiated mask works at least as reliably as the current compatibility path.
- After physical evidence is collected, compare Pult's captured protocol/state
  behavior against `tronikos/androidtvremote2` and write a Stage 3 product spec
  for any observation worth promoting beyond Diagnostics.

### Stage 3: Product Promotion

Promote only observations that prove stable and useful through a separate
product spec and repeated evidence across sessions. Promotion remains per-TV and
per-build by default.

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
- Sending IME app package/label or configure device-info values to telemetry.
- Changing configure/set-active response behavior in Stage 1.

## Architecture

### Wire DTOs

`AndroidTVRemoteMessageCodec` remains policy-free. It decodes named protocol
payloads and encodes responses, but does not decide whether an observation is
user-visible, current, validated, or product-worthy.

Add protocol DTOs in `PultCore` with explicit fields:

- `RemoteDeviceInfo`: `model`, `vendor`, `unknown1`, `unknown2`,
  `packageName`, `appVersion`.
- `RemoteConfigureRequest`: `code: RemoteProtocolCode?`,
  `deviceInfo: RemoteDeviceInfo?`.
- `RemoteSetActiveRequest`: `active: RemoteProtocolCode?`.
- `RemoteAppInfo`: `counter`, `unknownInt2`, `unknownInt3`,
  `unknownString4`, `unknownInt7`, `unknownInt8`, `label`, `appPackage`,
  `unknownInt13`.
- `RemoteImeKeyInjectObservation`: `appInfo: RemoteAppInfo?`,
  `textFieldStatus: RemoteTextFieldStatus?`.
- `RemoteImeObjectObservation`: `start`, `end`, `value`.
- `RemoteEditInfoObservation`: `insert`,
  `textFieldStatus: RemoteImeObjectObservation?`.
- `RemoteImeBatchEditObservation`: `imeCounter`, `fieldCounter`,
  `editInfo: [RemoteEditInfoObservation]`, and any derived
  `textFieldStatus: RemoteTextFieldStatus?` built from the latest edit object
  when preserving current text-entry behavior.
- `RemoteProtocolCode`: `rawValue`, decoded raw feature-bit labels, and
  `unknownBits`.

Update `IncomingRemoteMessage` to carry payloads:

- `.configure(RemoteConfigureRequest)`
- `.setActive(RemoteSetActiveRequest)`
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

Missing protocol scalar fields must remain unobserved, not defaulted into facts.
`remote_start` emits `.started(false)` only when field 1 is present with varint
`0`; if field 1 is absent or malformed, return `.other` and do not update
`remoteStart`. Missing configure and set-active codes remain `nil`, not raw `0`.

### Feature Codes

Add a small decoder for known raw bits:

- `ping = 1`
- `key = 2`
- `ime = 4`
- `voice = 8`
- `unknown1 = 16`
- `powerCommandCapability = 32`
- `volume = 64`
- `appLink = 512`

Stage 1 treats these as raw feature-bit labels for protocol-code diagnostics. It
does not treat the decoded labels as complete support truth and does not replace
Pult's current response policy. For example, the fixed client response `622`
does not include the `ping` bit even though Pult currently answers ping
requests.

Add `RemoteProtocolNegotiator` in `PultCore` as a pure value type owned by
`RemoteSession`, but start conservatively:

- `static let defaultClientResponseRawCode: UInt64 = 622`
- `clientResponseCode: RemoteProtocolCode`
- `makeConfigureResponseObservation(at:deviceID:attempt:)`
- `makeSetActiveResponseObservation(at:deviceID:attempt:)`

`AndroidTVRemoteMessageCodec` must expose the raw client response code it uses
for `encodeConfigureResponse()` and `encodeSetActiveResponse()` so diagnostics
and encoded bytes cannot drift. Stage 1 keeps that value at `622`.

Add `RemoteProtocolNegotiation`:

- `inboundConfigureCode: RemoteProtocolObservation<RemoteProtocolCode>?`
- `inboundSetActiveCode: RemoteProtocolObservation<RemoteProtocolCode>?`
- `outboundConfigureCode: RemoteProtocolObservation<RemoteProtocolCode>?`
- `outboundSetActiveCode: RemoteProtocolObservation<RemoteProtocolCode>?`
- `clientResponsePolicy = fixed622Stage1`

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
- `negotiation: RemoteProtocolNegotiation`

The state is in-memory and connection-scoped. `protocolState` resets only when a
new connection attempt increments `connectAttempt`, on `disconnect()`, and
inside `fail(..., attempt:)` when the failed attempt is current. Joining an
in-flight connect to the same device must not reset observations. Protocol state
must not be copied into persisted TV records or validation passed areas.

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

For Diagnostics, "active session device" means `model.session.device` only while
`connectionState` is `.connecting` or `.connected`. Failed or disconnected
sessions show protocol observations as `Not observed this session`, even if
`RemoteSession.device` still holds the last target.

## User-Facing Design

Add a new Diagnostics section after `Session`:

- `Protocol remote_start`: `remote_start.started=true observed at 2:14 PM`,
  `remote_start.started=false observed at 2:14 PM`, or
  `Not observed this session`. Do not render this as on/off, awake/asleep,
  started/stopped, or power state.
- `IME App Info`: package and optional label observed in
  `remote_ime_key_inject.app_info`, captioned as `from IME key inject, not a
  foreground-app feed`.
- `Protocol Device Info`: model, vendor, package name, app version.
- `Protocol Configure Code`: inbound raw code plus decoded labels.
- `Protocol Client Code`: `configure 622 (...)`, `set-active 622 (...)`.

The language must remain observational:

- Use `observed`, `reported`, `from IME`, and `this session`.
- Do not use `current app`, `TV is on`, `power state`, or `validated` for these
  rows unless later physical evidence and separate product decisions justify
  that wording.

Copied diagnostics may include protocol observations only under a separate
`Protocol Observations (not validation evidence)` block. Stage 2 validation
reports may append a local protocol evidence block when the active session
matches the selected TV; that block must preserve observation provenance and
explicit question statuses. `ValidationRunItem`, `ValidationReport.passedAreas`,
persisted `PhysicalDeviceValidationRecord`, checklist completion, and PostHog
validation events must not include protocol observation values.

Treat IME app package/label and configure device-info package/model/vendor/version
as private diagnostic fields. They may be shown in Diagnostics and copied only
by explicit Copy Diagnostics action. Do not send them to PostHog, OSLog public
fields, MetricKit, `command_timing_recorded`, `validation_run_completed`, or any
other analytics event.

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
- `appideas.md`
- `Docs/ProtocolSources.md`
- `Docs/Observability.md`
- `Docs/PhysicalDeviceValidationChecklist.md`
- `README.md`, if its current scope bullets need a new diagnostics line

Before closing implementation, run:

```sh
rg -n "current-app|current app|app name|power-state|power/standby|no .*power|no .*app|now-playing" README.md Docs appideas.md
```

`Docs/ProtocolSources.md` also contains an obsolete sentence that names
`PlaceholderRemoteMessageCodec` as current deterministic test plumbing. The
implementation docs pass should correct that because Pult now has a real v2
wire codec.

## Error Handling

Observation subfield decode failures should not break remote command sending.
Catch malformed optional nested observation payloads locally and treat only that
optional value as absent.

- Malformed optional subfields become absent optional values.
- If `remote_ime_key_inject` has app info but malformed text status, preserve
  app info.
- If `remote_ime_key_inject` has text status but no app info, preserve text
  status.
- Do not broadly swallow top-level framing or protobuf-reader failures in
  `RemoteSession`; those keep current failure behavior unless a separate tested
  change proves masking them is safe.
- Attempt-scoped state updates must be ignored after a newer connection attempt
  starts.
- State mutations after `await send(...)` need a fresh attempt check.

## Testing

Use the repo's narrow checks:

- Codec tests for `remote_configure` payload decoding, device info parsing,
  set-active frames with both empty payload and explicit `active`, IME app info
  parsing, combined IME app+text-field frames, repeated IME `edit_info` entries
  with preserved ordering, IME batch counters, `remote_start` present/absent
  semantics, and raw feature-code label decoding.
- Session tests for protocol-state reset on new connect attempt, disconnect,
  and current-attempt failure; no reset when joining an in-flight same-device
  connect; attempt scoping; observation timestamps/device IDs; and preserving
  existing configure/set-active response bytes.
- Selected-vs-session labeling should be covered by a pure diagnostics
  formatter test if one is introduced. Otherwise, cover it with app build plus
  copied diagnostics review, because `RemoteSession` has no selected-device
  concept.
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
