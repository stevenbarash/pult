# Pult — Product Strategy

*From a guided product-strategy session, 2026-06-16. This is the "why & in what order" layer above [`appideas.md`](../appideas.md) (the living backlog). When the two disagree on sequence, this document wins.*

---

## One-line positioning

> **The Apple TV Remote, but for Google TVs** — instant from the lock screen, no app to open, no ads. Just press play.

---

## Strategy Context

- **Ambition:** Craft / pride / portfolio. The bar is *"the remote Steven actually wants to use,"* not downloads or revenue. Scale & money are secondary.
- **Implication of that ambition:** optimize for **depth on the differentiator, not breadth of surface area.** No TAM/SAM/SOM, no monetization funnel, no growth loops, no reach-for-reach's-sake.
- **Release posture:** TestFlight-first, solo builder. Spec → plan → build rhythm per sub-project.
- **Platform ceilings (don't fight these):** Android TV Remote **v2** protocol exposes commands + volume only — no now-playing/title/art, no app name, no power-state light. iOS Live Activities support discrete buttons/toggles only — no gestures, drag, or press-and-hold.

## Target Customer

- **Primary persona — the "where's-the-remote" household.** An iPhone owner with an Android TV (Sony / TCL / Nvidia Shield / Chromecast w/ Google TV) whose physical remote is regularly lost, dead, buried in the couch, or shared. The phone is always in hand and charged.
- **Job-to-be-done:** *"When I sit down to watch and the remote isn't in my hand, I want to pause/play (and basic control) instantly from my phone — without opening a clunky, ad-filled app — so I don't have to get up."*
- **Deliberately tiny job.** The core need is "just press pause/play," not a full-featured remote. Richness is a bonus, never the entry ticket.

## Problem Framing

- **Problem:** iPhone owners with Android TVs have **no instant, trustworthy, always-present remote.** Apple gives its own users a built-in Control Center remote for Apple TV; Android TV users get nothing equivalent. Google's app makes you open it and wait; third-party apps are ad-ridden and clunky. So people fall back to the physical remote — or suffer.
- **The real competitor is friction, not any one app.** Users named all of them (physical remote, "nothing/suffer," Google's apps, third-party apps) — which means the named apps are *why they don't already have a good phone remote.* **The bar to beat is "faster and easier than standing up."** A remote that lags loses to the couch every time.
- **Why now:** iOS Live Activities, lock-screen presence, and the Action Button make a *no-app-open* remote possible for the first time; the v2 protocol exposes just enough (commands + volume) to do it well.

## Core Insight — the Trust Triad

**The product is a trust triad: Instant + Trustworthy + There. Beauty rides on top of it.**

| Triad leg (foundation) | Hypothesis | Maps to |
|---|---|---|
| **Instant** | A warm, persistent-while-visible session makes taps feel instantaneous → user reaches for Pult, not the physical remote. | #1 Warm Live Session |
| **Trustworthy** | Heartbeat + fast cold reconnect + honest-failure card → it connects when needed and never lies. | reliability slice of #1 + honest-failure card |
| **There** | Lock-screen persistence + static widget + Action Button → zero friction to summon. *This is the Apple-TV-remote promise.* | subset of #4 (Reach) |
| *Premium (secondary)* | Live volume bar + polish → the remote you're proud of + the viral screenshot. | #2 + #3 |

## Prioritization

- **Framework:** Make-or-break, foundation-first — filtered by the craft goal (cut anything that's reach-for-adoption rather than craft-core).
- **Decision:** **Foundation-first.** Complete the triad before the beauty layer. This *reorders* `appideas.md`, which currently ships the premium layer (#2 volume bar, #3 polish) ahead of the Thereness leg.

## Roadmap / Sequencing

- **NOW — Instant + Trustworthy.** Finish #1 Warm Live Session (warm window, heartbeat, fast cold reconnect, optimistic feel) + the reliability/honest-failure card. Measurement-gated: ship each mechanism when real-TV numbers justify it.
- **NEXT — There.** Static lock-screen widget (one-tap "start remote"), Action Button to summon/fire a command, and rock-solid Live Activity presence/persistence. *(The "TV wants text" affordance and seamless auto-reconnect can ride here as trust polish.)*
- **LATER — Premium.** Live volume bar (#2 — cheap, already parsed into `RemoteSession.volumeStatus`), then layout & motion polish (#3, designed around the volume bar).
- **CUT / PARKED (reach-for-adoption, not craft-core).** Apple Watch app + complication, expanded Siri/Shortcuts breadth, per-TV layout, StandBy bedside mode, adaptive auto-layout. Revisit *only* if the goal shifts from craft to reach/business.
- **DON'T CHASE (platform-bounded).** Hold-to-repeat / swipe touchpad (Live Activities = discrete buttons only); now-playing card / app name / power light (absent from v2 protocol).

## Success Metrics — triangulate all three

- **GATE — the personal test.** You reach for Pult over the physical remote *every time, without thinking* — even when the real remote is right there. If you still grab the physical one, it's not done.
- **HONEST — measured thresholds, build over build.** Median tap latency < target; connect-on-first-tap success > threshold; stale-state incidents per session = 0. *(You already have the latency measurement methodology + Diagnostics command timing — turn "target/threshold" into real numbers from your baseline.)*
- **GENERALIZES — testers.** 2–5 TestFlight users independently say some version of *"I stopped using my real remote."*

## Next Steps

1. **Continue #1 Warm Live Session** — let real-TV measurements gate which mechanisms ship.
2. **Add a thin reliability slice** — extend the Diagnostics failed-row flagging into a user-facing honest-failure card.
3. **Spec the "There" epic** — static widget + Action Button (small spec → plan → build).
4. **Set the numbers** — convert the measured-metric targets into concrete thresholds from your latency baseline.
5. **Reconcile `appideas.md` ordering** — move #2/#3 to LATER and pull the widget + Action Button up to NEXT, so the backlog matches this sequence.
