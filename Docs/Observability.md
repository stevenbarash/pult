# Observability

Pult uses Apple-native observability for local diagnostics and PostHog for
TestFlight product analytics when the Xcode app target is built.

## Native Signals

- `OSLog` emits structured events under the `app.pult` subsystem.
- Command timing samples write to the App Group diagnostics log only while the
  Diagnostics "Record Command Timing" toggle is enabled.
- MetricKit is registered at app launch when the framework is available.
- MetricKit payload receipt is logged by byte count only; payload contents are
  not copied into app logs.

## Event Privacy

Telemetry events distinguish public and private metadata. Public metadata may
appear in logs; private metadata is intentionally omitted from the rendered log
message.

Do not log:

- TV hostnames or IP addresses
- saved TV names
- pairing codes
- typed text
- certificate, key, or pairing-secret material

Current public fields are limited to coarse states such as command key,
command action, pairing failure class, discovery result count, reachability
state, and timing.

## PostHog

The Xcode app target links the PostHog iOS SDK from
`https://github.com/PostHog/posthog-ios.git` and `PultApp` initializes it at
launch. The import and setup call remain guarded by `canImport(PostHog)` so
SwiftPM-only checks, which do not build the installable iOS app target, keep
working without the Xcode package graph.

The app bundle reads `PultPostHogProjectToken` from
`Sources/PultApp/Supporting/Info.plist`.

`PultPostHogHost` is optional and defaults to `https://us.i.posthog.com`.
Use `https://eu.i.posthog.com` for an EU PostHog project.

When the Diagnostics "Record Command Timing" toggle is enabled, the app also
captures a `command_timing_recorded` PostHog event for each timing sample. Its
properties are limited to command key, WARM/COLD classification, dialed flag,
success flag, fresh-launch heuristic, and coarse phase timings (`total_ms`,
`tcp_tls_ms`, `configure_ms`, and `send_ms_approx`). Timing events follow the
same runtime toggle as the local diagnostics log, so they are off for normal
TestFlight use unless measurement is explicitly turned on.

Do not log private telemetry fields into PostHog events. TV hostnames, IP
addresses, saved TV names, pairing codes, typed text, certificates, keys, and
pairing-secret material must stay out of event properties.
