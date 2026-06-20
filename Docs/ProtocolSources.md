# Protocol Source Notes

This package is prepared for Android TV Remote Service protocol v2 over TLS.

Primary implementation references used for the package shape:

- Google Android TV Remote Service Play listing, describing same-network phone remote, d-pad/touchpad, microphone, and keyboard support.
- Aymkdn assistant-freebox-cloud wiki page for Google TV / Android TV Remote Control v2, including pairing and command ports 6467 and 6466.
- tronikos/androidtvremote2 for v2 protocol behavior, pairing flow, app links, key commands, IME text, volume updates, and optional voice flow.

Pult implements the Android TV Remote v2 command codec in `Sources/PultCore/RemoteMessageCodec.swift` as `AndroidTVRemoteMessageCodec`, using hand-rolled protobuf wire coding for the subset in the vendored protocol references. Configure and set-active responses currently preserve the observed client feature code `622`; treat it as a feature-bit mask and implementation constant until physical-device evidence proves a different negotiation is safe.

Known feature bits decoded by `RemoteProtocolFeature`:

- `1`: ping
- `2`: key
- `4`: IME
- `8`: voice
- `16`: unknown/reserved
- `32`: power command capability, not power state
- `64`: volume
- `512`: app link

The default client response `622` is `2 + 4 + 8 + 32 + 64 + 512`.

Generated SwiftProtobuf files, if added later, should keep the upstream license headers from the vendored `.proto` source.
