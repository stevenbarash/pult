# Release-Hardening + UX-Polish Pass — Design

Date: 2026-06-13
Status: Approved (design); implementation plan pending
Sub-project: A of 3 (A: this pass · B: TestFlight/App Store Connect plumbing · C: launch motion)

## Context

Pult is a feature-complete native SwiftUI Google TV remote for iOS 27+: it
reimplements Android TV Remote Service v2 (hand-rolled protobuf, mutual-TLS
client identity in the keychain, real port-6467 pairing and port-6466 command
channel), plus a Liquid Glass remote surface, lock-screen Live Activity
mini-remote, Control Center / Action button / widget controls, and
Siri/Shortcuts App Intents.

This sub-project is the first of a three-part program decided during
brainstorming:

- **Distribution model:** public **TestFlight beta first** (then decide
  OSS vs. paid for 1.0).
- **Launch hook:** **"the remote Google should've built"** — taste/UX is the
  headline; lock-screen magic, the reverse-engineered protocol, and deep iOS
  system integration are supporting beats.
- **Sequencing:** polish & harden first (this spec), then TestFlight plumbing,
  then the launch motion.
- **Validation:** the maintainer has an iPhone + Google TV on hand and will run
  validation steps live, in the loop.
- **Approach:** **hybrid** — a fast targeted audit to set the floor, then
  demo-path-first as the spine.

### Current state (measured 2026-06-13)

- `make verify` green: SwiftPM compile of app sources + xmllint of schemes +
  plutil lint of plists/entitlements + project check.
- `swift test` green: **91/91 tests pass** (protocol, session, codec,
  discovery, store, intents, validation layer) via
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Unknown / unproven:** the full iOS-27 app build (`make verify-full` /
  `xcode-build-simulator`, incl. the `PultWidgets` extension) has not been run
  this pass; real-device behavior is validated only for `Android.local` (as of
  2026-06-11); broad UX polish, accessibility, and empty/error/loading coverage
  are unaudited.

These are exactly the gaps this pass closes.

## Goal & definition of done

Take Pult from "feature-complete and compiles" to "a beautiful, demo-able,
TestFlight-ready beta" that backs the taste hook. Done means **all** of:

1. `swift test` green **and** `make verify-full` green (full iOS-27 simulator
   build incl. the widget extension), and we do not regress them.
2. The **demo hero-path** (below) runs flawlessly and looks gorgeous end-to-end
   on the physical iPhone + Google TV — recordable in one take.
3. No crashes or dead-ends in the hero-path or the top beta paths; every failure
   has a designed, on-brand recovery (no raw errors, no silent no-ops).
4. A tester with zero context can install, find their TV, pair, and control it
   without help.
5. Accessibility floor met: VoiceOver labels on every control, Dynamic Type
   survives, 44pt minimum targets (brand spec), reduced-motion respected.
6. Brand applied consistently: app icon, color discipline (no system-blue
   identity, no purple gradients), type, and spacing per `Docs/PultBrandSpec.md`.
7. No placeholder copy anywhere user-visible, including Info.plist permission
   strings.

## Scope

**In scope:** build/test health; real-device hardening of the hero-path and top
beta paths; UX polish (motion, haptics, typography, empty/error/loading states);
onboarding/first-run; the accessibility floor; brand/icon consistency; a
user-visible copy pass.

**Out of scope (deferred):**

- → Sub-project B: App Store Connect record, signing/upload pipeline, TestFlight
  tester management, store screenshots, privacy nutrition labels.
- → Sub-project C: demo *video production*, landing page, waitlist, the launch
  thread.
- This pass *does* produce a flawless, recorded hero-path — the raw material C
  edits into the launch video. We do not produce marketing artifacts here.
- Solving the IP / Google-ToS question (see Risks) — flagged for a deliberate
  decision before C, not resolved here.

## The demo hero-path (the spine)

The exact flow we make flawless and beautiful, validated live on device and
recorded, in order:

1. **First launch** — a launch/onboarding moment that signals taste immediately
   (`PultLaunchView`).
2. **Discover + pair** — the TV appears fast in discovery; clean 6-digit
   pairing; the command channel reaches Online.
3. **The remote surface** — the Liquid Glass deck: touchpad ⇄ d-pad toggle,
   media controls, hold-to-repeat volume, haptics. The centerpiece.
4. **Keyboard** — type into the TV from the phone (a notorious official-app pain
   point; a high-impact "ooh" moment).
5. **Supporting "wow" beats** — lock-screen Live Activity controlling the TV
   *while locked*; "Hey Siri, turn up the volume on the TV"; Control Center
   control; Action button.

## The fast audit (the floor)

Before demo-path work, a quick triage sweep across seven dimensions, producing
one severity-tagged punch list:

1. Build/test health (full iOS build, widget extension, signing/entitlements).
2. Real-device behavior of each surface.
3. UX polish gaps (motion, haptics, typography, spacing, color discipline).
4. Accessibility (VoiceOver, Dynamic Type, contrast, reduced motion, 44pt).
5. Empty/error/loading coverage (no-network, TV-not-found, pairing-failed,
   session-dropped, local-network-permission-denied, no-saved-TVs).
6. App Store review-compliance landmines (permission strings, private API,
   background behavior claims, metadata honesty).
7. Copy / brand consistency.

## Triage model & exit criteria

Every finding is tagged:

- **demo-critical** — breaks or cheapens the hero-path.
- **beta-blocking** — crashes, data loss, dead-ends, likely review rejection, or
  broken accessibility for testers outside the hero-path.
- **nice-to-have** — deferred and logged.

**Exit criteria:** all demo-critical **and** all beta-blocking findings cleared;
nice-to-haves logged for post-launch. No gold-plating the long tail before
launch.

## Validation strategy

Respect the repo's strict per-area / per-TV evidence culture
(`Docs/PhysicalDeviceValidationChecklist.md`). As we harden live on the
`Android.local` setup, record passed areas with date and host. Areas we cannot
prove across multiple TV models stay honestly labeled "beta, unvalidated" —
TestFlight testers become that evidence. No "validated" claim ships without
evidence. Use the in-app Diagnostics guided validation runner as the first-line
check whenever protocol, discovery, pairing, intent, widget, entitlement,
signing, or storage behavior changes.

## Execution shape (phases)

0. **Foundation green** — get `make verify-full` green (resolve the iOS-27 SDK /
   Xcode dependency); confirm `swift test` green; wire both so we catch
   regressions.
1. **Audit + triage** — run the seven-dimension sweep; produce the
   severity-tagged punch list.
2. **Demo hero-path** — make the hero-path flawless and beautiful;
   live-validate each step on device.
3. **Beta-blockers** — clear all remaining beta-blocking findings (error/empty
   states, a11y floor, crashes).
4. **Consistency sweep + record** — final brand/copy/a11y consistency pass;
   record the hero-path as the hand-off artifact to Sub-project C.

Each phase ends with green `make verify-full` and `swift test`.

## Risks & open questions

- **iOS 27 SDK dependency.** `make verify-full` needs an Xcode with the iOS 27
  SDK; the README defaults to `Xcode-beta.app`. Confirm whether
  `/Applications/Xcode.app` carries the iOS 27 SDK or whether the beta Xcode is
  required. Resolved in Phase 0.
- **IP / Google ToS.** Going viral raises the profile of a reverse-engineered
  protocol reimplementation. Out of scope to solve here; flagged for a
  deliberate go/no-go decision before the public launch motion (Sub-project C).
- **Single-TV validation ceiling.** Only one TV model can be truly validated
  pre-beta; the beta framing must set that expectation, and multi-TV robustness
  must be labeled accordingly until tester evidence arrives.
