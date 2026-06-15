# Lock Screen Widget Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a production-ready Lock Screen remote with a media-weighted Hybrid default layout, a Media alternate layout, and a native in-app setting for switching between them.

**Architecture:** Put the layout preference in `PultCore` so the app, intents, widget extension, tests, and smoke check share one source of truth. Carry the selected layout in `RemoteSessionAttributes.ContentState`, refresh active Live Activities when the setting changes, and render explicit Hybrid/Media widget layout variants in `RemoteLiveActivity.swift`.

**Tech Stack:** Swift 6.3, SwiftUI, ActivityKit, WidgetKit, AppIntents, App Group `UserDefaults`, Swift Testing, Pult Makefile verification gates.

---

## File Structure

- Create `Sources/PultCore/RemoteActivityLayout.swift`: pure shared layout enum and App Group preference store.
- Modify `Tests/PultCoreTests/DeviceStoreTests.swift`: Swift Testing coverage for default, invalid, and saved layout preference behavior.
- Modify `Sources/PultCoreCheck/main.swift`: smoke coverage for layout preference behavior in environments where `swift test` is blocked.
- Modify `Sources/PultApp/RemoteSessionActivity.swift`: add `RemoteActivityLayout` to the Live Activity content state.
- Modify `Sources/PultApp/RemoteActivityController.swift`: read the shared preference, include it in every activity update, and expose a refresh method for active activities.
- Create `Sources/PultApp/LockScreenRemoteSettingsView.swift`: native settings sheet for the Hybrid/Media segmented control.
- Modify `Sources/PultApp/RemoteRootView.swift`: present the settings sheet and refresh activities after layout changes.
- Modify `Sources/PultApp/CommandPaletteView.swift`: expose the Lock Screen settings from the command palette.
- Modify `Sources/PultWidgets/RemoteLiveActivity.swift`: render explicit Hybrid and Media layout variants, with larger play/pause, mute, and volume controls.
- Modify `Pult.xcodeproj/project.pbxproj`: add the new Swift files to the matching Xcode groups and source build phases.

---

### Task 1: Shared Layout Preference

**Files:**
- Create: `Sources/PultCore/RemoteActivityLayout.swift`
- Modify: `Tests/PultCoreTests/DeviceStoreTests.swift`
- Modify: `Sources/PultCoreCheck/main.swift`
- Later project membership: `Pult.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing Swift Testing coverage**

Append this to `Tests/PultCoreTests/DeviceStoreTests.swift`:

```swift
@Test
func remoteActivityLayoutDefaultsToHybridWhenMissingOrInvalid() {
    let suite = makeSuite("pult.tests.remote-activity-layout-default")
    let store = RemoteActivityLayoutStore(defaults: suite)

    #expect(store.load() == .hybrid)

    suite.set("future-layout", forKey: RemoteActivityLayoutStore.key)

    #expect(store.load() == .hybrid)
}

@Test
func remoteActivityLayoutPersistsMediaSelection() {
    let suite = makeSuite("pult.tests.remote-activity-layout-save")
    let store = RemoteActivityLayoutStore(defaults: suite)

    store.save(.media)

    #expect(suite.string(forKey: RemoteActivityLayoutStore.key) == RemoteActivityLayout.media.rawValue)
    #expect(store.load() == .media)
}

@Test
func remoteActivityLayoutProvidesSettingsCopy() {
    #expect(RemoteActivityLayout.hybrid.displayTitle == "Hybrid")
    #expect(RemoteActivityLayout.media.displayTitle == "Media")
    #expect(RemoteActivityLayout.hybrid.settingsDescription.contains("D-pad"))
    #expect(RemoteActivityLayout.media.settingsDescription.contains("playback"))
}
```

- [ ] **Step 2: Add smoke coverage before implementation**

Append this near the other device/defaults checks in `Sources/PultCoreCheck/main.swift`, after the selected-device checks:

```swift
let layoutDefaults = UserDefaults(suiteName: "pult.corecheck.remote-activity-layout")!
layoutDefaults.removePersistentDomain(forName: "pult.corecheck.remote-activity-layout")
let layoutStore = RemoteActivityLayoutStore(defaults: layoutDefaults)
expect(layoutStore.load() == .hybrid, "remote activity layout should default to hybrid")
layoutDefaults.set("future-layout", forKey: RemoteActivityLayoutStore.key)
expect(layoutStore.load() == .hybrid, "invalid remote activity layout should fall back to hybrid")
layoutStore.save(.media)
expect(layoutStore.load() == .media, "remote activity layout save failed")
expect(RemoteActivityLayout.media.displayTitle == "Media", "remote activity layout title failed")
```

- [ ] **Step 3: Run the smoke check and verify RED**

Run:

```bash
make core-check
```

Expected: FAIL at compile time because `RemoteActivityLayoutStore` and `RemoteActivityLayout` do not exist yet.

- [ ] **Step 4: Implement the shared type and store**

Create `Sources/PultCore/RemoteActivityLayout.swift`:

```swift
import Foundation

public enum RemoteActivityLayout: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case hybrid
    case media

    public static let `default`: RemoteActivityLayout = .hybrid

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .hybrid: "Hybrid"
        case .media: "Media"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .hybrid:
            "D-pad stays visible while play/pause, mute, and volume get larger Lock Screen targets."
        case .media:
            "Playback, mute, and volume take priority for watching without browsing TV menus."
        }
    }
}

public struct RemoteActivityLayoutStore {
    public static let key = "pult.remoteActivityLayout"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = PultAppGroup.sharedDefaults()) {
        self.defaults = defaults
    }

    public func load() -> RemoteActivityLayout {
        guard let rawValue = defaults.string(forKey: Self.key),
              let layout = RemoteActivityLayout(rawValue: rawValue) else {
            return .default
        }
        return layout
    }

    public func save(_ layout: RemoteActivityLayout) {
        defaults.set(layout.rawValue, forKey: Self.key)
    }
}
```

- [ ] **Step 5: Run the smoke check and verify GREEN for shared logic**

Run:

```bash
make core-check
```

Expected: PASS.

- [ ] **Step 6: Run Swift Testing when the local toolchain supports it**

Run:

```bash
swift test --filter remoteActivityLayout --disable-sandbox
```

Expected on a full Swift Testing toolchain: PASS. If this environment reports `no such module 'Testing'`, treat it as the known local toolchain limitation only if `make core-check` passed.

---

### Task 2: Live Activity State Carries Layout

**Files:**
- Modify: `Sources/PultApp/RemoteSessionActivity.swift`
- Modify: `Sources/PultApp/RemoteActivityController.swift`

- [ ] **Step 1: Update the activity content state**

Modify `Sources/PultApp/RemoteSessionActivity.swift`:

```swift
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation
import PultCore

/// Identity and state of the lock-screen remote Live Activity. Compiled into
/// both the app and the widget extension; ActivityKit requires the exact same
/// type on both sides.
struct RemoteSessionAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case connecting
        case connected
        case failed
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        var message: String?
        var layout: RemoteActivityLayout

        init(
            status: Status,
            message: String? = nil,
            layout: RemoteActivityLayout = .default
        ) {
            self.status = status
            self.message = message
            self.layout = layout
        }
    }

    var deviceID: UUID
    var deviceName: String
}
#endif
```

- [ ] **Step 2: Update the controller to read and refresh layout**

In `Sources/PultApp/RemoteActivityController.swift`, change the stored properties and initializer:

```swift
@MainActor
final class RemoteActivityController {
    static let shared = RemoteActivityController()

    private let layoutStore: RemoteActivityLayoutStore

    private init(layoutStore: RemoteActivityLayoutStore = RemoteActivityLayoutStore()) {
        self.layoutStore = layoutStore
    }
```

Change all calls from `Self.content(...)` to `content(...)`.

Add this method after `noteOutcome`:

```swift
    func refreshLayout() async {
        let layout = layoutStore.load()
        for activity in Activity<RemoteSessionAttributes>.activities {
            let state = activity.content.state
            await activity.update(Self.content(
                status: state.status,
                message: state.message,
                layout: layout
            ))
        }
    }
```

Replace the existing static `content(for:message:)` helper with these helpers:

```swift
    private func content(for state: ConnectionState, message: String?) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        let layout = layoutStore.load()
        let contentState: RemoteSessionAttributes.ContentState = switch state {
        case .connected: .init(status: .connected, message: message, layout: layout)
        case .connecting: .init(status: .connecting, message: message, layout: layout)
        case .disconnected: .init(status: .failed, message: message ?? "Disconnected", layout: layout)
        case let .failed(text): .init(status: .failed, message: message ?? text, layout: layout)
        }
        return Self.content(state: contentState)
    }

    private static func content(
        status: RemoteSessionAttributes.Status,
        message: String?,
        layout: RemoteActivityLayout
    ) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        content(state: .init(status: status, message: message, layout: layout))
    }

    private static func content(
        state: RemoteSessionAttributes.ContentState
    ) -> ActivityContent<RemoteSessionAttributes.ContentState> {
        // Without presses for a long stretch the remote is probably done;
        // let the system render it stale rather than confidently live.
        ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 4 * 60 * 60))
    }
```

- [ ] **Step 3: Build-check the guarded ActivityKit changes**

Run:

```bash
make build
```

Expected: PASS. This keeps the macOS SwiftPM variant compiling with the iOS-only ActivityKit code compiled out.

---

### Task 3: In-App Lock Screen Settings

**Files:**
- Create: `Sources/PultApp/LockScreenRemoteSettingsView.swift`
- Modify: `Sources/PultApp/RemoteRootView.swift`
- Modify: `Sources/PultApp/CommandPaletteView.swift`

- [ ] **Step 1: Create the settings view**

Create `Sources/PultApp/LockScreenRemoteSettingsView.swift`:

```swift
import SwiftUI
import PultCore

struct LockScreenRemoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLayout: RemoteActivityLayout

    private let store: RemoteActivityLayoutStore
    private let onLayoutChange: () async -> Void

    init(
        store: RemoteActivityLayoutStore = RemoteActivityLayoutStore(),
        onLayoutChange: @escaping () async -> Void = {}
    ) {
        self.store = store
        self.onLayoutChange = onLayoutChange
        _selectedLayout = State(initialValue: store.load())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Lock Screen Layout", selection: $selectedLayout) {
                        ForEach(RemoteActivityLayout.allCases) { layout in
                            Text(layout.displayTitle).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Chooses which controls Pult emphasizes in the Lock Screen remote.")
                } header: {
                    Text("Layout")
                } footer: {
                    Text(selectedLayout.settingsDescription)
                }

                Section {
                    layoutRow(
                        layout: .hybrid,
                        systemImage: "button.programmable",
                        detail: "Best for browsing menus: d-pad stays visible while play/pause, mute, and volume are promoted."
                    )
                    layoutRow(
                        layout: .media,
                        systemImage: "playpause",
                        detail: "Best for watching: playback, mute, and volume take the largest Lock Screen targets."
                    )
                } header: {
                    Text("Modes")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Lock Screen Remote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .scrollContentBackground(.hidden)
            .background { RemoteBackground() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedLayout) { _, newValue in
                store.save(newValue)
                Task { await onLayoutChange() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func layoutRow(
        layout: RemoteActivityLayout,
        systemImage: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(layout == selectedLayout ? Color.pultAccent : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(layout.displayTitle)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if layout == selectedLayout {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.pultAccent)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            selectedLayout = layout
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(layout.displayTitle). \(detail)")
    }
}
```

- [ ] **Step 2: Wire the settings sheet into the root view**

In `Sources/PultApp/RemoteRootView.swift`, add a sheet case:

```swift
        case lockScreenSettings
```

Add this item inside `deviceMenu` when a selected device exists, near Diagnostics:

```swift
            Button("Lock Screen Remote...", systemImage: "lock.rectangle.stack", action: presentLockScreenSettings)
```

Add this sheet branch:

```swift
        case .lockScreenSettings:
            LockScreenRemoteSettingsView(onLayoutChange: refreshLockScreenRemoteLayout)
                .presentationSizing(.form)
```

Add this presenter:

```swift
    private func presentLockScreenSettings() {
        presentedSheet = .lockScreenSettings
    }
```

Add this refresh method near `autoConnectIfNeeded()`:

```swift
    @MainActor
    private func refreshLockScreenRemoteLayout() async {
        #if canImport(ActivityKit) && os(iOS)
        await RemoteActivityController.shared.refreshLayout()
        #endif
    }
```

- [ ] **Step 3: Add the command palette action**

In `Sources/PultApp/CommandPaletteView.swift`, add the action case:

```swift
    case lockScreenSettings
```

In `RemoteQuickCommand.commands(device:connectionState:)`, append this command when `hasDevice` is true, near Diagnostics:

```swift
            commands.append(
                RemoteQuickCommand(
                    id: "lock-screen-settings",
                    title: "Lock Screen Remote",
                    subtitle: "Choose Hybrid or Media controls for the Live Activity.",
                    systemImage: "lock.rectangle.stack",
                    tint: .pultAccent,
                    scope: .setup,
                    aliases: ["live activity", "lock screen", "widget", "media layout", "hybrid layout"],
                    isEnabled: true,
                    action: .lockScreenSettings
                )
            )
```

In `Sources/PultApp/RemoteRootView.swift`, handle the palette command:

```swift
        case .lockScreenSettings:
            presentSheetAfterDismiss(.lockScreenSettings)
```

- [ ] **Step 4: Build-check the settings UI**

Run:

```bash
make build
```

Expected: PASS.

---

### Task 4: Hybrid And Media Live Activity Layouts

**Files:**
- Modify: `Sources/PultWidgets/RemoteLiveActivity.swift`

- [ ] **Step 1: Import the shared layout model**

At the top of `Sources/PultWidgets/RemoteLiveActivity.swift`, add:

```swift
import PultCore
```

- [ ] **Step 2: Make the expanded Dynamic Island layout-aware**

Replace the bottom expanded Dynamic Island region with:

```swift
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandCommandRow(layout: context.state.layout)
                }
```

Add this view near the other private widget views:

```swift
private struct DynamicIslandCommandRow: View {
    let layout: RemoteActivityLayout

    private var commands: [RemoteKeyOption] {
        switch layout {
        case .hybrid:
            [.back, .volumeDown, .playPause, .mute, .volumeUp, .home]
        case .media:
            [.rewind, .volumeDown, .playPause, .mute, .volumeUp, .fastForward]
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(commands, id: \.rawValue) { command in
                KeyButton(
                    command: command,
                    size: command == .playPause || command == .mute ? 38 : 32
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 3: Route the medium Live Activity by layout**

Replace `SupplementalMediumRemoteView.body` with:

```swift
    var body: some View {
        switch context.state.layout {
        case .hybrid:
            HybridRemoteLayout(context: context)
        case .media:
            MediaRemoteLayout(context: context)
        }
    }
```

- [ ] **Step 4: Add the Hybrid layout**

Add this below `SupplementalMediumRemoteView`:

```swift
private struct HybridRemoteLayout: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            DPadCluster()

            VStack(spacing: 8) {
                RemoteActivityStatusColumn(context: context)
                KeyButton(command: .power, size: 30)
                EndActivityButton()
            }
            .frame(maxWidth: .infinity)

            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    KeyButton(command: .volumeDown, size: 36)
                    KeyButton(command: .playPause, size: 42)
                    KeyButton(command: .volumeUp, size: 36)
                }
                GridRow {
                    KeyButton(command: .back, size: 32)
                    KeyButton(command: .mute, size: 42)
                    KeyButton(command: .home, size: 32)
                }
                GridRow {
                    KeyButton(command: .rewind, size: 30)
                    EmptyCell()
                    KeyButton(command: .fastForward, size: 30)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 5: Add the Media layout**

Add this below `HybridRemoteLayout`:

```swift
private struct MediaRemoteLayout: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 8) {
                RemoteActivityStatusColumn(context: context)
                HStack(spacing: 6) {
                    KeyButton(command: .power, size: 30)
                    EndActivityButton()
                }
            }
            .frame(maxWidth: .infinity)

            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    KeyButton(command: .rewind, size: 34)
                    KeyButton(command: .playPause, size: 46)
                    KeyButton(command: .fastForward, size: 34)
                }
                GridRow {
                    KeyButton(command: .volumeDown, size: 42)
                    KeyButton(command: .mute, size: 46)
                    KeyButton(command: .volumeUp, size: 42)
                }
                GridRow {
                    KeyButton(command: .back, size: 34)
                    KeyButton(command: .select, size: 34)
                    KeyButton(command: .home, size: 34)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 6: Extract shared status and dismiss controls**

Add these shared views and remove the duplicated inline status/dismiss code from the old medium layout:

```swift
private struct RemoteActivityStatusColumn: View {
    let context: ActivityViewContext<RemoteSessionAttributes>

    var body: some View {
        VStack(spacing: 4) {
            Text(context.attributes.deviceName)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
            StatusBadge(status: context.state.status, isStale: context.isStale)
            if let message = context.state.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct EndActivityButton: View {
    var body: some View {
        Button(intent: EndRemoteSessionIntent()) {
            Image(systemName: "xmark")
                .widgetAccentedRenderingMode(.fullColor)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide remote")
        .accessibilityHint("Disconnects and removes the Lock Screen remote")
    }
}
```

- [ ] **Step 7: Build-check what SwiftPM can see**

Run:

```bash
make build
```

Expected: PASS. The widget extension itself is Xcode-only; the full widget/App Intents gate runs after Task 5 adds new source files to the Xcode project.

---

### Task 5: Xcode Project Membership

**Files:**
- Modify: `Pult.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add build file entries**

In the `PBXBuildFile` section, add unique entries:

```pbxproj
		010000000000000000000060 /* RemoteActivityLayout.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000153 /* RemoteActivityLayout.swift */; };
		010000000000000000000061 /* LockScreenRemoteSettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 010000000000000000000154 /* LockScreenRemoteSettingsView.swift */; };
```

- [ ] **Step 2: Add file references**

In the `PBXFileReference` section, add:

```pbxproj
		010000000000000000000153 /* RemoteActivityLayout.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RemoteActivityLayout.swift; sourceTree = "<group>"; };
		010000000000000000000154 /* LockScreenRemoteSettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LockScreenRemoteSettingsView.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add files to groups**

In group `010000000000000000000604 /* PultApp */`, add `LockScreenRemoteSettingsView.swift` near the other user-facing views:

```pbxproj
				010000000000000000000154 /* LockScreenRemoteSettingsView.swift */,
```

In group `010000000000000000000605 /* PultCore */`, add `RemoteActivityLayout.swift` near `DeviceDiscovery.swift` because both use App Group defaults:

```pbxproj
				010000000000000000000153 /* RemoteActivityLayout.swift */,
```

- [ ] **Step 4: Add files to source build phases**

In app sources phase `010000000000000000000521 /* Sources */`, add:

```pbxproj
				010000000000000000000061 /* LockScreenRemoteSettingsView.swift in Sources */,
```

In core sources phase `010000000000000000000522 /* Sources */`, add:

```pbxproj
				010000000000000000000060 /* RemoteActivityLayout.swift in Sources */,
```

- [ ] **Step 5: Verify project membership**

Run:

```bash
make xcode-project-check
```

Expected: PASS.

---

### Task 6: Final Verification And Commit

**Files:**
- All files modified by Tasks 1-5.

- [ ] **Step 1: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Run SwiftPM build**

Run:

```bash
make build
```

Expected: PASS.

- [ ] **Step 3: Run core smoke check**

Run:

```bash
make core-check
```

Expected: PASS.

- [ ] **Step 4: Run project metadata checks**

Run:

```bash
make metadata-check
make xcode-project-check
```

Expected: both PASS.

- [ ] **Step 5: Run full widget/App Intents verification**

Run:

```bash
make verify-full
```

Expected: PASS with Xcode simulator build success and App Intents metadata export success.

- [ ] **Step 6: Inspect final diff**

Run:

```bash
git status --short
git diff -- Sources/PultCore/RemoteActivityLayout.swift Tests/PultCoreTests/DeviceStoreTests.swift Sources/PultCoreCheck/main.swift Sources/PultApp/RemoteSessionActivity.swift Sources/PultApp/RemoteActivityController.swift Sources/PultApp/LockScreenRemoteSettingsView.swift Sources/PultApp/RemoteRootView.swift Sources/PultApp/CommandPaletteView.swift Sources/PultWidgets/RemoteLiveActivity.swift Pult.xcodeproj/project.pbxproj
```

Expected: only implementation files are modified. `.superpowers/` remains untracked scratch output and should not be staged.

- [ ] **Step 7: Commit implementation**

Run:

```bash
git add Sources/PultCore/RemoteActivityLayout.swift Tests/PultCoreTests/DeviceStoreTests.swift Sources/PultCoreCheck/main.swift Sources/PultApp/RemoteSessionActivity.swift Sources/PultApp/RemoteActivityController.swift Sources/PultApp/LockScreenRemoteSettingsView.swift Sources/PultApp/RemoteRootView.swift Sources/PultApp/CommandPaletteView.swift Sources/PultWidgets/RemoteLiveActivity.swift Pult.xcodeproj/project.pbxproj
git commit -m "feat: add configurable lock screen remote layouts"
```

Expected: commit succeeds. Do not stage `.superpowers/`.

---

## Self-Review

Spec coverage:

- Hybrid default and Media alternate are implemented by Tasks 1, 2, and 4.
- In-app customization is implemented by Task 3.
- Shared App Group persistence is implemented and tested by Task 1.
- Active Live Activity refresh is implemented by Task 2 and used by Task 3.
- Widget/App Intents verification is covered by Task 6.
- Out-of-scope items are not included: no adaptive mode, no custom per-button Live Activity grid, no protocol behavior changes, no new dependencies.

Placeholder scan:

- The plan contains no placeholder sections and no deferred implementation steps.

Type consistency:

- `RemoteActivityLayout`, `RemoteActivityLayoutStore`, `LockScreenRemoteSettingsView`, and `RemoteSessionAttributes.ContentState.layout` are named consistently across tasks.
