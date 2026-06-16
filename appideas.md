# Pult — App Improvement Ideas

Running list of ideas for making the app better, captured during the lock-screen-excellence work. Each has a **why** and a rough **status**. The lock-screen widget is the main differentiator, so most of these orbit it.

**Status legend:** 🔨 in progress · 📋 planned/next · 💭 idea (uncommitted) · ⛔ parked (deliberately) · 🚧 platform-constrained

Cross-refs: spec `Docs/superpowers/specs/2026-06-15-warm-live-session-design.md` · plan `Docs/superpowers/plans/2026-06-15-warm-live-session-measurement.md` · testing `Docs/LatencyMeasurementMethodology.md`.

---

## The lock-screen program — the differentiator

Decomposed into 4 sequenced sub-projects (each its own spec → plan → build).

### 1. Warm Live Session — 🔨
*Instant taps + live volume from one persistent-while-visible session.* The measurement pass is shipped (on `main`); the mechanisms below ship once real-TV numbers justify them.
- **warm window** — background-task grace re-armed per tap, so a burst of taps reuses one live socket
- **heartbeat** — keep the socket healthy so the staleness check stops forcing re-dials
- **fast cold reconnect** — TLS session resumption + cached TV IP (skip mDNS) for the unavoidable first-tap-after-rest
- **optimistic feel** — instant press feedback, deliver underneath; honest "reconnecting / tap again" only when it really fails
- **why:** a lock-screen remote that lags on every tap trains the user to grab the physical remote. Instant *is* the product.

### 2. Live volume bar — 📋 (rides on the warm session)
The TV pushes its real volume (level/max/mute); show it as a live bar on the Live Activity + Dynamic Island.
- **why:** the only "remote that shows the TV" state the v2 protocol actually exposes — a premium, differentiating touch. (Already parsed into `RemoteSession.volumeStatus`; just needs plumbing into the Activity. Device-dependent — degrade to hidden when absent.)

### 3. Layout & motion polish — 📋
Perfect the button geometry, hierarchy, press animation, and Dynamic Island choreography (within the buttons/toggles-only Live Activity).
- **why:** the viral screenshot. Make it the most beautiful remote anyone's seen on a lock screen. Designs around the volume bar from #2.

### 4. Reach — be everywhere you grab a remote — 📋
- **Action Button** → summon the remote / fire a chosen command
- **static lock-screen widget** → one-tap "start remote" (distinct from the Live Activity)
- **Apple Watch** app + complication
- **expanded Siri / App Shortcuts** (some already exist)
- **why:** surround the moment, not just the lock screen.

---

## Smaller / cross-cutting ideas

- **"TV wants text" affordance** — 💭 when the TV focuses a text field it sends the field's label ("Search"); surface a keyboard prompt on the lock screen so typing is one tap away.
- **Honest failure reconciliation** — 📋 when a command truly fails, the card flips to "reconnecting / tap again" instead of a frozen spinner. (The measurement build already flags failed rows in Diagnostics; extend the principle to the user-facing card.)
- **Seamless auto-reconnect** — 💭 silent reconnect with a manual Retry banner as fallback (the T5 item deferred post-beta in the release program).
- **Per-TV layout** — 💭 remember Hybrid vs. Media per TV. Scoped out of v1; revisit only if real usage proves people want different layouts per device.

---

## Parked / platform-constrained — so we don't chase them

- **StandBy bedside mode** — ⛔ deliberately cut (your call). A nightstand-friendly remote was on the table; deprioritized.
- **Adaptive auto-layout from recent commands** — ⛔ scoped out; predictable muscle memory beats a layout that shifts under you.
- **Hold-to-repeat / swipe touchpad on the lock screen** — 🚧 Live Activities support only discrete buttons/toggles — no gestures, drag, or press-and-hold. Richness has to come from elsewhere.
- **Now-playing card (title/art/scrubber), current-app name/icon, power/standby light** — 🚧 none exist in the Android TV Remote **v2** protocol; they'd need Cast/MediaSession, a transport Pult doesn't speak. Don't design a now-playing card on this connection.

---

## Non-feature follow-ups (housekeeping that unblocks the above)

- **TestFlight pipeline** — first upload tripped ASC validation (framework Info.plist version keys); fixed on `main`. Keep an eye out for further ASC validation issues on the next upload (sub-project B territory).
