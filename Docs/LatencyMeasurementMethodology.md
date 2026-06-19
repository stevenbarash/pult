# Lock-Screen Tap-Latency: Testing Methodology

**What this is:** a runbook *and* the reasoning behind it — how to measure how fast a lock-screen remote command actually reaches the TV, and how to turn the numbers into a build decision. Read this when you pick the **Warm Live Session** work back up.

**One-line how:** build to a real iPhone + Google TV → app → **Diagnostics → toggle "Record Command Timing" on** → run the protocol below → read the WARM/COLD breakdown → toggle off.

Background and rationale live in:
- Spec: `Docs/superpowers/specs/2026-06-15-warm-live-session-design.md`
- Plan: `Docs/superpowers/plans/2026-06-15-warm-live-session-measurement.md`

---

## 1. Why this matters

The lock-screen widget is the app's main differentiator. Its whole value is that it *feels* like a hardware remote: glance, tap, the TV responds. A lock-screen remote that lags on every tap is worse than useless — it trains the user to reach for the physical remote instead. So tap latency isn't a polish item; **it is the product.** Everything else (layout, live volume, reach) sits on top of "the tap is instant."

## 2. Why the latency happens — the anatomy of a tap

When you tap a button on the Live Activity, iOS runs the app's intent (`SendRemoteKeyIntent`) inside the app's process and calls `RemoteControlModel.performHeadlessCommand`. Before the key can go out, the model needs a live, connected session to the TV. The catch:

> **iOS suspends (and eventually kills) the app between taps, and an app cannot keep a TCP/mTLS socket open while suspended.** There is no entitlement for a generic persistent socket; VoIP/PushKit would be App Store policy abuse; and the connection is LAN-direct, so there's no relay server to hold it. There is also no client heartbeat today, and any gap over ~30s is treated as stale.

So in real tap-watch-tap usage, almost every tap finds a **dead socket** and has to **re-dial the TV from scratch** before the command is sent. A cold tap pays, in order:

| Phase | What it is | Why it costs |
|---|---|---|
| **process wake/launch** | iOS relaunches the app if it was reaped | full process + SDK init |
| **resolve** | find the TV's address | ≈0 here — the host/IP is already known, no mDNS on the command path |
| **tcp+tls** | TCP connect + mutual-TLS handshake | loads the client cert from the keychain, exchanges certs both ways — multi-RTT |
| **configure** | the Android TV Remote **v2** `configure` handshake | the channel isn't usable for commands until the TV sends `configure` and the client replies — *gated on the TV* |
| **send** | the actual key frame | tiny |

**The command itself (`send`) is the smallest part.** Everything before it is connection setup that, ideally, shouldn't happen on every press. The entire reason to measure is to learn **how big each pre-send phase actually is on your hardware**, because that decides which fixes are worth building.

## 3. What we measure, and why each number is diagnostic

| Field | Meaning | Why it's diagnostic |
|---|---|---|
| **total (ms)** | entry → sent wall time | the headline "how laggy is it" |
| **WARM / COLD** | reused a live socket vs. had to dial | the most important classifier — if every tap is COLD, the socket isn't surviving between taps |
| **tcp+tls (ms)** | TLS-dominated cold cost | if it dominates → the lever is TLS session resumption + cached address |
| **configure (ms)** | protocol-handshake cost | if it dominates → largely protocol-gated (hard to remove) → mask it instead |
| **send (~ms)** | derived remainder | should be tiny; if large, the socket-write path is suspect |
| **fresh launch** | command arrived right after the process first touched the remote stack | distinguishes "process was killed" cold from "process alive but socket stale" cold |
| **Volume pushes** | count + last level/max/mute | confirms whether *this* TV emits live volume at all (device-dependent) and roughly how often |

## 4. How to run it — the protocol (~5 min on the couch)

**Prereqs:** a real iPhone with the app installed (TestFlight or a dev build) + a paired Google/Android TV on the same network. Measurement is **off by default** and writes nothing until you turn it on.

1. **Turn it on.** App → **Diagnostics → Record Command Timing** (on).
2. **Cold taps.** Lock the phone, wait **~2–3 min** (let iOS suspend the app), tap **one** command from the Live Activity. Repeat **~5×.** → the number that matters most: real-world cold-dial cost.
3. **Burst.** Immediately tap **Volume-Up ~5× fast.** → are taps 2–5 actually WARM/instant (process surviving) or all COLD (process dying each time)?
4. **Volume.** Change the volume with the **TV's own remote** and watch the **Volume Pushes** row tick up. → live-volume feasibility + rough cadence.
5. **Read.** Diagnostics → Command Timing → **Refresh Timings** → read each tap's WARM/COLD `tcp+tls · configure · send` breakdown. Failed commands are flagged (not valid latency data).
6. **Turn it off.**

**Deep profile (optional):** the build also emits `os_signpost` under subsystem **`app.pult`**, categories **`dial`** (per-phase intervals) and **`command-timing`** (per-command events). With a cabled device, open Instruments → os_signpost for nanosecond-accurate intervals.

**PostHog readout:** when the Xcode app target is built with PostHog configured,
the same toggle also emits one `command_timing_recorded` event per sample. The
event carries only public timing fields: command key, WARM/COLD, dialed,
success, fresh-launch heuristic, and coarse phase milliseconds.

## 5. How to read results → what to build

The numbers aren't the deliverable; **the decision is.** Map observations to mechanisms:

| Observation | What it means | Build |
|---|---|---|
| Cold total > ~400 ms | re-dial is the pain | **warm window** + **fast cold reconnect** |
| Burst taps 2–5 still COLD | process dies per intent | **warm window** is the priority |
| Burst taps 2–5 WARM | process survives bursts | heartbeat likely unnecessary; fix only the cold edge |
| `tcp+tls` dominates | TLS handshake is the cost | **TLS session resumption + cached IP** (skip mDNS) |
| `configure` dominates | protocol-gated, hard to remove | **optimistic feedback** to mask it |
| Volume pushes reliable | TV reports volume | ship the **live volume bar** |
| Volume pushes absent/rare | this TV/route doesn't report it | degrade the bar to hidden; revisit per-device |

The four candidate mechanisms — **warm window** (background-task grace re-armed per tap), **heartbeat** (keep the socket healthy so staleness stops forcing re-dials), **fast reconnect** (TLS resumption + cached address), **optimistic feel** (instant feedback, deliver underneath) — are the menu. Measurement tells you which earn their place, so you don't build machinery the numbers don't justify.

## 6. The ceiling — what you can't measure or fix (so you don't chase it)

- **No persistent socket while suspended.** The best achievable is: instant during active-use bursts (warm window), fast recovery otherwise, instant-*feeling* always (optimistic). A socket that lives forever on the lock screen is not on the menu.
- **v2 live-state ceiling.** The Android TV Remote v2 protocol pushes only **volume (level/max/mute), connection liveness, and text-field focus.** There is **no** now-playing title/art/scrubber, **no** current-app, **no** power/standby — those need Cast/MediaSession, a transport Pult doesn't speak. Don't design a now-playing card.
- **Live Activities are buttons/toggles only.** No swipe touchpad, drag, or press-and-hold on the lock screen. Richer interaction has to come from elsewhere.

## 7. Where the code is

- **Measurement types:** `Sources/PultCore/CommandTiming.swift`, `CommandTimingLog.swift` (App-Group file-per-sample ring buffer), `CommandTimingRecorder.swift` (flag-gated; App-Group key **`pult.measureTimings`**; emits signposts), `ProcessClock.swift`.
- **Capture points:** `RemoteSession.swift` (dial-phase ms, volume-push counters, `dial` signpost intervals) and `RemoteControlModel.executeRemoteAction` (the WARM/COLD wrapper around the verbatim command body — behavior-preserving).
- **Readout UI:** the **Command Timing** section in `Sources/PultApp/DiagnosticsAndValidationView.swift`.

## 8. Caveats

- **Off by default.** The toggle flips an App-Group flag (`pult.measureTimings`). Turn it off when done so it never records locally or emits timing events to PostHog for normal users.
- **Volume is device-dependent** and its push cadence is unconfirmed across models — treat the volume readout as per-TV evidence, not a guarantee.
- **Timings are wall-clock,** not isolated CPU time; `send (~)` is a *derived remainder* (it absorbs decision overhead), so read it as an upper bound.
- **Numbers are evidence for a design decision, not a validation claim.** Per the repo's evidence culture, don't claim a latency figure is "validated" for a TV unless you captured it on that TV.
