# Agentic iOS Workflow

This repository is set up so humans and coding agents can make small, verifiable iOS changes without relying on hidden Xcode state.

## Current Guidance Snapshot

As of June 2026, Xcode itself advertises coding-agent support and emphasizes a loop of previews, Simulator/device testing, Swift Testing, CI, debugging, and Instruments. Codex guidance emphasizes durable repo instructions in `AGENTS.md`, clear verification commands, scoped sandbox/network access, and review of the resulting diff before accepting changes.

Sources:

- Apple Xcode overview: https://developer.apple.com/xcode/
- Apple Swift Testing docs: https://developer.apple.com/documentation/testing
- Codex manual, `Best practices` and `Custom instructions with AGENTS.md`: https://developers.openai.com/codex/codex-manual.md

## Repository Contract For Agents

1. Start by reading `AGENTS.md`, `README.md`, and the files relevant to the requested change.
2. Prefer direct source edits over broad project churn.
3. Keep generated or environment-specific state out of source changes.
4. Run `make verify` before final handoff unless the task explicitly does not touch code.
5. If `swift test` fails because `Testing` is unavailable, report the toolchain gap and include `swift build` plus `swift run PultCoreCheck` results.
6. For device issues, prefer the direct schemes before changing app code:
   - `Pult Release Direct`
   - `Pult Direct`
   - `Pult`

## Best Practices Applied Here

- `AGENTS.md` captures durable agent instructions so future sessions do not rediscover project layout, schemes, and verification commands.
- `Makefile` provides stable command names for build, smoke checks, metadata validation, and full verification. SwiftPM commands redirect `HOME` into `.build/home` and use `--disable-sandbox` because Codex already provides the outer workspace sandbox and this local Command Line Tools install can fail when nested SwiftPM tooling writes outside the workspace.
- Direct Xcode schemes isolate app behavior from debugger/diagnostic injection on beta OS devices.
- `README.md` points to the same workflow so human and agent instructions stay aligned.

## Known Follow-Up Work

- Replace `PlaceholderRemoteMessageCodec` with generated protobuf-backed Android TV Remote Service messages.
- Implement real pairing validation and credential generation before claiming device control support.
- Add timeout/cancellation handling for `NetworkRemoteTransport.connect`.
- Add an asset catalog with `AppIcon` or remove the app-icon build setting until assets exist.
- Add compact-width UI validation for the fixed remote button grid.
