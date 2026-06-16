# Warm Live Session Design

**Date:** 2026-06-15
**Status:** Approved for implementation planning — measurement pass first
**Sub-project:** 1 of the "Lock Screen excellence" program (foundation)

## Goal

Make Pult's Lock Screen remote feel like a hardware remote: every tap reaches the TV with no perceptible delay, and the Live Activity reflects the TV's real volume. Both come from one capability — a session kept live while the Live Activity is on screen. This is the app's headline differentiator.

## Why this is one sub-project, not two

Two findings from investigation collapsed the original "fix latency" (A) and "show the TV" (B) directions into a single foundation:

1. **Latency root cause (code trace).** `RemoteControlModel.executeRemoteAction` runs `ensureFreshConnection(staleAfter: 30)` and re-dials on nearly every tap. There is no warm process, no client heartbeat, and any gap over 30 seconds since the last received frame forces a fresh TCP + mutual-TLS + protocol-`configure` handshake before the key is sent. With no keep-alive, the process and socket rarely survive between intermittent taps — which matches the reported "every tap is laggy." Evidence: `RemoteControlModel.swift` (`staleAfter: 30`), `RemoteSession.needsConnectionRefresh`, `RemoteTransport.connect` (8s connect ceiling), `RemoteSession.waitForConfiguration` (5s ceiling). No `beginBackgroundTask`/`performExpiringActivity`/heartbeat exists.

2. **Live-state ceiling (protocol spike).** The reverse-engineered Android TV Remote **v2** protocol exposes, as inbound state: **volume** (absolute level + max + mute — already decoded into the observable `RemoteSession.volumeStatus`, with a ready 0–1 `normalizedLevel`), **connection liveness**, and **text-field focus** (the TV asking for input, with a field label). It does **not** carry now-playing media metadata, the current foreground app, or a power/standby flag — those live in Cast/MediaSession, a transport Pult does not speak. So "a remote that shows the TV" realistically means **live volume + status**.

**The convergence:** receiving volume pushes requires a persistently open session — the exact thing the latency fix needs. Build "keep one live session feeding the Lock Screen" once and you get instant taps *and* a live volume bar.

## iOS constraints (non-negotiable, they shape everything)

- An app cannot keep an arbitrary mTLS socket open while suspended. There is no entitlement for a generic persistent TCP/TLS connection. VoIP/PushKit would be App Store policy abuse for a non-VoIP app, and the connection is LAN-direct with no relay server, so push-kept sockets are not an option.
- Background execution after the app leaves the foreground is a **grace window** (`beginBackgroundTask` / `performExpiringActivity`), on the order of ~30 seconds, and can be re-armed on each interaction.
- Therefore the achievable goal is: **hold the socket across active-use bursts, recover fast when it is cold, and feel instant always.** We do not promise a socket that lives indefinitely on the lock screen, because the OS does not allow it.

## Approved direction

Sub-project 1 is **Warm Live Session**: a session kept live while the Live Activity is on screen that (1) collapses tap latency and (2) streams live volume/mute + status into the Activity. **Which mechanisms ship is decided by measurement**, not assumption.

Four candidate mechanisms (final selection gated on Phase 0 numbers):

- **Warm window** — request background-execution grace on each interaction so the socket survives to the next tap within a burst.
- **Heartbeat** — a periodic ping while the process is alive that keeps the socket healthy and `lastReceivedAt` fresh, so the staleness check stops forcing needless re-dials.
- **Fast cold reconnect** — reuse the TV's cached IP (skip mDNS), attempt TLS session resumption to shorten the handshake, and trim worst-case ceilings, so the unavoidable first-tap-after-rest is as short as physically possible.
- **Optimistic feel** — return the intent fast with immediate press feedback and deliver underneath; if delivery truly fails, the card honestly flips to "reconnecting / tap again" rather than freezing on a spinner.

## Phase 0 — Measurement pass (the concrete, plannable deliverable)

This is what we build and run **first**. It is measurement only: logging and instrumentation, **no behavior change** to the command path. Its output finalizes the warm-session design.

### What it measures

Per command (both the lock-screen intent path and the in-app path), timestamp these phases:

- `t0` — intent `perform()` entry (or in-app action start)
- `t1` — connection decision (warm reuse vs. dial)
- `t2` — transport connect start
- `t3` — `NWConnection` reaches `.ready` (TCP + mutual-TLS complete)
- `t4` — `connectionState` reaches `.connected` (protocol `configure` handshake complete)
- `t5` — command frame written (send complete)

Derived phase durations: `resolve`, `tcp+tls`, `configure`, `send`, and `total`. Each command is classified **WARM** (reused socket) or **COLD** (re-dialed), plus a **fresh-process-launch** indicator derived from process age at command time (a process-start timestamp captured at the earliest process init).

Volume telemetry: count of inbound `RemoteSetVolumeLevel` pushes, the last `level/max/muted`, and inter-arrival gaps — this confirms whether the maintainer's TV emits live volume and how often.

### How it is captured

- A small value type in PultCore (e.g. `CommandTiming`) plus a `TimingRecorder` seam. The recorder is injectable and a no-op unless a debug/measurement flag is set, so it never affects release behavior.
- Persist samples to a **concurrency-safe App Group store**: a bounded ring buffer (about the last 50 commands) that survives process suspension/relaunch and tolerates writes from the headless-intent process while the foreground app reads. Use file-coordinated atomic writes, not naïve shared-`UserDefaults` mutation, to avoid cross-process corruption. Losing an occasional sample is acceptable; corrupting state or affecting a command is not.
- Emit `os_signpost` interval events per phase (a dedicated signpost category) so the maintainer can also open Instruments for a nanosecond-accurate profile when a number looks surprising.
- The in-app Diagnostics view gains a **Command Timing** section that shows the last-N breakdowns (warm/cold + phase milliseconds + total) and the volume-push stats, readable on-device with no Mac, cable, or Instruments.

### Test protocol (maintainer, on the real Google TV)

1. **Cold taps** — lock the phone, wait ~2–3 minutes so iOS suspends the app, tap one command from the Live Activity. Repeat ~5 times. Sizes the real cold-dial cost.
2. **Burst** — immediately tap Volume-Up ~5 times fast. Confirms whether taps 2–5 are actually warm/instant (i.e. whether the process survives between taps).
3. **Volume** — change the volume with the TV's own remote and watch whether a push arrives in the readout. Confirms live-volume feasibility and cadence.
4. **Read** — open the app → Diagnostics → read the Command Timing section.

### Decision criteria (how the numbers finalize the warm-session design)

- Cold-dial `total` greater than roughly 400 ms → the **warm window + fast reconnect** mechanisms are justified.
- Burst taps 2–5 already WARM/instant → the process is surviving; **heartbeat** may be unnecessary. Burst taps still COLD → the process dies per intent; the **warm window** is the priority.
- `configure` phase dominates → that cost is protocol-gated and less fixable; lean harder on **optimistic feel**.
- `tcp+tls` phase dominates → **TLS session resumption + cached address** is the highest-value lever.
- Volume pushes arrive reliably with reasonable cadence → the **live volume bar ships** in the warm-session feature. Pushes absent or rare on this TV → the bar degrades to hidden and we revisit volume per-device.

## Architecture (measurement pass)

- **PultCore** holds the instrumentation, woven into the existing connect/send path: `RemoteSession.connect`/`performConnect`, `RemoteTransport.connect`, the `RemoteSession.handle` transition to `.connected` and its volume case, and `RemoteControlModel.executeRemoteAction`. A `CommandTiming` value type plus a `TimingRecorder` protocol (default no-op) keep it testable and release-safe.
- **Shared storage** extends `PultAppGroup` with a concurrency-safe, bounded timing log (file-coordinated). A process-start timestamp is captured at the earliest app/intent process init to support the fresh-launch indicator.
- **PultApp** adds the Diagnostics "Command Timing" section that reads the shared log.
- **Signposts** use `OSSignposter` / `os.Logger` in PultCore under a dedicated category.

## Data flow

Lock-screen tap → `SendRemoteKeyIntent.perform()` (app process via `LiveActivityIntent`) → `executeRemoteAction` emits phase timestamps → `TimingRecorder` writes a `CommandTiming` to the App Group log and emits signposts → later, the foregrounded app's Diagnostics view reads the log → the maintainer reads the breakdown. Volume pushes update `volumeStatus` as today; the recorder additionally counts them.

## Error handling

- Instrumentation must never alter command behavior or introduce a failure path. All recording is best-effort and swallows its own errors.
- The ring buffer is bounded; no unbounded growth.
- Two processes may write concurrently; use file coordination / atomic replace to avoid corruption, and prefer dropping a sample over risking the command.
- The whole measurement path is gated behind a build/measurement flag so it never reaches TestFlight users by default.

## Accessibility & production UI

The measurement pass adds only a Diagnostics readout, which follows existing Diagnostics conventions (native list, no color-only meaning, explicit labels). It introduces no new user-facing remote UI. The eventual live volume bar and any warm-session UI changes carry their own accessibility requirements in the follow-on design (44 pt targets preserved, non-color status, explicit labels, no decorative chrome).

## Testing

- Unit tests in PultCore, all deterministic and network-free: `CommandTiming` phase-delta math, ring-buffer bounding/eviction, WARM/COLD classification, and the volume-push counter.
- The latency and volume numbers themselves are gathered from the device via the test protocol, not asserted in CI.
- The existing suite stays green.

## Verification

- `make build` and `make core-check` for PultCore changes.
- `make xcode-project-check` if Swift files are added or moved.
- `make metadata-check` if project/scheme/plist/entitlement metadata changes.
- `make verify-full` because intent and Live Activity surfaces are touched by the instrumentation.
- No new physical-validation claims beyond what the maintainer reports from the test protocol, per AGENTS.md and the validation checklist.

## Out of scope (this spec)

- The warm-session mechanisms themselves (warm window, heartbeat, fast reconnect, optimistic feel) — their final design is selected by the Phase 0 numbers and written up as a follow-on. This spec commits only the measurement pass, the decision framework, and the agreed direction.
- Layout and motion redesign of the Live Activity (sub-project 3).
- Reach surfaces — Action Button, a static Lock-Screen widget, Apple Watch (sub-project 4).
- Now-playing / current-app / power live state (not in the v2 protocol).
- Per-TV layout settings; new protocol behavior; new production dependencies.

## Follow-on

After the measurement pass runs on the maintainer's TV, finalize the warm-session mechanism design (selected by the numbers) in a sibling spec, then plan and build it. Then proceed to sub-project 3 (layout/motion) and 4 (reach).
