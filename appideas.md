# Pult — App Improvement Ideas

Running list of ideas for making the app better, captured during the lock-screen-excellence work. Each has a **why** and a rough **status**. The lock-screen widget is the main differentiator, so most of these orbit it.

**Status legend:** 🔨 in progress · 📋 planned/next · 💭 idea (uncommitted) · ⛔ parked (deliberately) · 🚧 platform-constrained

Cross-refs: strategy `Docs/ProductStrategy.md` · spec `Docs/superpowers/specs/2026-06-15-warm-live-session-design.md` · plan `Docs/superpowers/plans/2026-06-15-warm-live-session-measurement.md` · testing `Docs/LatencyMeasurementMethodology.md`.

---

## The lock-screen program — the differentiator

The product is a **Trust Triad: Instant + Trustworthy + There.** Beauty rides on top. Sequenced **foundation-first** — finish the triad before the premium layer. Ordering rationale + positioning live in `Docs/ProductStrategy.md`; each item is still its own spec → plan → build.

### NOW — Instant + Trustworthy (the foundation)

**Warm Live Session — 🔨**
*Instant taps + live volume from one persistent-while-visible session.* The measurement pass is shipped (on `main`); the mechanisms below ship once real-TV numbers justify them.
- **warm window** — v1 shipped: background-task grace is re-armed for headless lock-screen/control interactions, so a burst can reuse one live socket; still needs physical-device timing confirmation before calling the foundation done
- **heartbeat** — keep the socket healthy so the staleness check stops forcing re-dials
- **fast cold reconnect** — TLS session resumption + cached TV IP (skip mDNS) for the unavoidable first-tap-after-rest
- **optimistic feel** — instant press feedback, deliver underneath; honest "reconnecting / tap again" only when it really fails
- **honest-failure card** — when a command truly fails, the card flips to "reconnecting / tap again" instead of a frozen spinner (extend the Diagnostics failed-row flagging to the user-facing card)
- **why:** a lock-screen remote that lags or lies trains the user to grab the physical remote. The bar is *faster & easier than standing up.* Instant + trustworthy *is* the product.

### NEXT — There (zero friction to summon) — 📋
*The Apple-TV-remote promise: it's on the lock screen / Action Button the instant you need it, no app-open. Spec: `Docs/superpowers/specs/2026-06-16-there-epic-design.md`.*
- **static lock-screen widget** → one-tap "start remote" (distinct from the Live Activity)
- **Action Button** → summon the remote / fire a chosen command
- **Live Activity presence** → make the buttons reliably there & persistent when a session is live
- **why:** "there" is the third leg of the triad — a remote you have to go open is just another app.

### LATER — Premium (rides on the triad; the craft & the screenshot)

**Live volume bar — 📋**
The TV pushes its real volume (level/max/mute); show it as a live bar on the Live Activity + Dynamic Island.
- **why:** the clearest product-grade "remote that shows the TV" state the v2 protocol exposes — a premium, differentiating touch. (Already parsed into `RemoteSession.volumeStatus`; just needs plumbing into the Activity. Device-dependent — degrade to hidden when absent.) Other protocol observations, such as feature codes, IME app observations, and `remote_start.started`, stay in Diagnostics unless physical evidence proves a product behavior. *Cheap & differentiating, but rides on top of the triad — promote it the moment the foundation is proven.*

**Layout & motion polish — 📋**
Perfect the button geometry, hierarchy, press animation, and Dynamic Island choreography (within the buttons/toggles-only Live Activity).
- **why:** the viral screenshot. Make it the most beautiful remote anyone's seen on a lock screen. Designs around the live volume bar.

---

## Smaller / cross-cutting ideas

- **"TV wants text" affordance** — 💭 when the TV focuses a text field it sends the field's label ("Search"); surface a keyboard prompt on the lock screen so typing is one tap away.
- **Honest failure reconciliation** — 🔨 promoted into NOW (Warm Live Session → honest-failure card). When a command truly fails, the card flips to "reconnecting / tap again" instead of a frozen spinner. (The measurement build already flags failed rows in Diagnostics; extend the principle to the user-facing card.)
- **Seamless auto-reconnect** — 💭 silent reconnect with a manual Retry banner as fallback (the T5 item deferred post-beta in the release program).
- **Per-TV layout** — 💭 remember Hybrid vs. Media per TV. Scoped out of v1; revisit only if real usage proves people want different layouts per device.

---

## Parked / platform-constrained — so we don't chase them

- **Apple Watch app + complication** — ⛔ cut given the craft goal (reach-for-adoption, not craft-core). Was part of old sub-project #4. Revisit only if the ambition shifts from craft to reach/business.
- **Expanded Siri / App Shortcuts breadth** — ⛔ same call; the few shortcuts that already exist stay, but don't broaden the surface for now.
- **StandBy bedside mode** — ⛔ deliberately cut (your call). A nightstand-friendly remote was on the table; deprioritized.
- **Adaptive auto-layout from recent commands** — ⛔ scoped out; predictable muscle memory beats a layout that shifts under you.
- **Hold-to-repeat / swipe touchpad on the lock screen** — 🚧 Live Activities support only discrete buttons/toggles — no gestures, drag, or press-and-hold. Richness has to come from elsewhere.
- **Now-playing card (title/art/scrubber), current-app name/icon, power/standby light** — 🚧 not product-truth surfaces on the Android TV Remote **v2** connection. Pult can show session-scoped protocol observations in Diagnostics, including IME app observations and `remote_start.started`, but those are not a stable foreground-app feed, now-playing metadata, or authoritative power state. Don't design a now-playing card on this connection.

---

## Non-feature follow-ups (housekeeping that unblocks the above)

- **TestFlight pipeline** — first upload tripped ASC validation (framework Info.plist version keys); fixed on `main`. Keep an eye out for further ASC validation issues on the next upload (sub-project B territory).
