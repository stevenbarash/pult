# PostHog post-wizard report

The wizard has completed a PostHog analytics integration for Pult, a SwiftUI iOS/macOS app that controls Google/Android TVs via the Android TV Remote protocol.

The PostHog iOS SDK was already installed and configured in this project (posthog-ios ≥ 3.59.3 via SPM, token read from `Info.plist`). The wizard added `captureApplicationLifecycleEvents = true` to the existing config and instrumented 10 business-critical events across 6 source files, covering the full user journey from adding a TV through pairing, key command sending, and advanced feature usage.

| Event | Description | File |
|---|---|---|
| `tv_paired` | User successfully completed TV pairing | `Sources/PultApp/PairingView.swift` |
| `pairing_failed` | TV pairing process ended in a failure state | `Sources/PultApp/PairingView.swift` |
| `tv_added` | User added a TV via manual IP or network discovery | `Sources/PultApp/AddDeviceView.swift` |
| `key_command_sent` | User successfully sent a remote key command to the TV | `Sources/PultApp/RemoteRootView.swift` |
| `command_failed` | User attempted a key command but it failed to reach the TV | `Sources/PultApp/RemoteRootView.swift` |
| `app_link_launched` | User sent a favorite app link to the TV | `Sources/PultApp/FavoriteAppLauncherView.swift` |
| `favorite_app_added` | User added a custom app link to favorites | `Sources/PultApp/FavoriteAppLauncherView.swift` |
| `text_sent_to_tv` | User sent text from the TV Keyboard view | `Sources/PultApp/TextEntryView.swift` |
| `command_palette_action_run` | User executed an action from the Command Palette | `Sources/PultApp/RemoteRootView.swift` |
| `validation_run_completed` | User completed a physical device validation run | `Sources/PultApp/DiagnosticsAndValidationView.swift` |

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics (wizard) — Dashboard](https://us.posthog.com/project/477702/dashboard/1736463)
- [Key Commands Sent Over Time](https://us.posthog.com/project/477702/insights/mac93NPh)
- [Onboarding Funnel: Add TV → Pair → First Command](https://us.posthog.com/project/477702/insights/PBWFI8hv)
- [Feature Adoption: App Links, Keyboard & Palette](https://us.posthog.com/project/477702/insights/08x23kD3)
- [Pairing Success vs Failure](https://us.posthog.com/project/477702/insights/5fxQUsJc)
- [Total Key Commands (Last 30 Days)](https://us.posthog.com/project/477702/insights/OFECtMsA)

## Verify before merging

- [ ] Run a full production build (the wizard only verified the files it touched) and fix any lint or type errors introduced by the generated code.
- [ ] Run the test suite — call sites that were rewritten or instrumented may need updated mocks or fixtures.

### Agent skill

We've left an agent skill folder in your project. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.
