# Protocol Source Notes

This package is prepared for Android TV Remote Service protocol v2 over TLS.

Primary implementation references used for the package shape:

- Google Android TV Remote Service Play listing, describing same-network phone remote, d-pad/touchpad, microphone, and keyboard support.
- Aymkdn assistant-freebox-cloud wiki page for Google TV / Android TV Remote Control v2, including pairing and command ports 6467 and 6466.
- tronikos/androidtvremote2 for v2 protocol behavior, pairing flow, app links, key commands, IME text, volume updates, and optional voice flow.

Generated SwiftProtobuf files should keep the upstream license headers from the vendored `.proto` source. The current `PlaceholderRemoteMessageCodec` is deterministic test plumbing, not a wire-compatible protobuf codec.
