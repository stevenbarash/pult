import Foundation
import Observation
import SwiftUI
import PultCore
#if canImport(GameController)
@preconcurrency import GameController
#endif
#if canImport(UIKit)
import UIKit
#endif

struct RemoteHardwareCommand {
    var key: RemoteKey
    var isRepeat: Bool = false

    var shouldSend: Bool {
        !isRepeat || key.allowsHardwareRepeat
    }

    init(key: RemoteKey, isRepeat: Bool = false) {
        self.key = key
        self.isRepeat = isRepeat
    }

    init?(keyPress: KeyPress) {
        guard let key = RemoteKey(keyEquivalent: keyPress.key) else { return nil }
        self.init(key: key, isRepeat: keyPress.phase == .repeat)
    }
}

/// The semantic category of a remote key press, used to select the
/// appropriate haptic weight. Three cases keep the feel palette small
/// and tasteful: a heavy confirm thud, a featherweight directional tick,
/// and a mid-weight tap for everything else.
enum HapticKind {
    /// D-pad centre / select / enter — heavier thud to confirm selection.
    case select
    /// Directional swipe or d-pad arrow — softer, lighter tick.
    case directional
    /// Standard button tap (back, home, media, mute, power, …).
    case standard
}

@MainActor
@Observable
final class RemoteKeyPressFeedback {
    // Separate counters so SwiftUI can bind distinct SensoryFeedback modifiers.
    var selectTrigger = 0
    var directionalTrigger = 0
    var standardTrigger = 0

    func play(kind: HapticKind) {
        switch kind {
        case .select:      selectTrigger += 1
        case .directional: directionalTrigger += 1
        case .standard:    standardTrigger += 1
        }
    }
}

struct RemoteKeyPressFeedbackEmitter: View {
    let feedback: RemoteKeyPressFeedback

    // Heavy thud for select/confirm.
    private let selectFeedback = SensoryFeedback.impact(weight: .heavy, intensity: 0.85)
    // Feather-light tick for directional navigation.
    private let directionalFeedback = SensoryFeedback.impact(weight: .light, intensity: 0.50)
    // Mid-weight tap for standard buttons — close to the original feel.
    private let standardFeedback = SensoryFeedback.impact(flexibility: .rigid, intensity: 0.78)

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .sensoryFeedback(selectFeedback, trigger: feedback.selectTrigger)
            .sensoryFeedback(directionalFeedback, trigger: feedback.directionalTrigger)
            .sensoryFeedback(standardFeedback, trigger: feedback.standardTrigger)
    }
}

private extension RemoteKey {
    var allowsHardwareRepeat: Bool {
        switch self {
        case .up, .down, .left, .right, .volumeUp, .volumeDown:
            true
        case .delete:
            true
        case .select, .back, .home, .voiceSearch, .search, .power, .mute, .playPause, .rewind, .fastForward, .enter:
            false
        }
    }

    init?(keyEquivalent: KeyEquivalent) {
        switch keyEquivalent {
        case .upArrow:
            self = .up
        case .downArrow:
            self = .down
        case .leftArrow:
            self = .left
        case .rightArrow:
            self = .right
        case .return:
            self = .enter
        case .space:
            self = .playPause
        case .escape:
            self = .back
        case .delete, .deleteForward:
            self = .delete
        case .home:
            self = .home
        case "m", "M":
            self = .mute
        default:
            return nil
        }
    }
}

#if canImport(UIKit)
struct HardwareKeyboardBridge: UIViewRepresentable {
    let send: (RemoteKey) -> Void

    func makeUIView(context: Context) -> HardwareKeyboardView {
        HardwareKeyboardView(send: send)
    }

    func updateUIView(_ uiView: HardwareKeyboardView, context: Context) {
        uiView.send = send
        uiView.requestFocus()
    }
}

final class HardwareKeyboardView: UIView {
    var send: (RemoteKey) -> Void

    init(send: @escaping (RemoteKey) -> Void) {
        self.send = send
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        Self.keyCommandDefinitions.map { definition in
            let command = UIKeyCommand(
                input: definition.input,
                modifierFlags: [],
                action: #selector(handleKeyCommand(_:))
            )
            command.discoverabilityTitle = definition.title
            command.wantsPriorityOverSystemBehavior = true
            command.allowsAutomaticMirroring = false
            return command
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestFocus()
    }

    func requestFocus() {
        guard window != nil, !isFirstResponder else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            _ = self.becomeFirstResponder()
        }
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        guard let input = command.input,
              let key = RemoteKey(keyCommandInput: input) else {
            return
        }
        send(key)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandledPresses = Set<UIPress>()

        for press in presses {
            if let key = RemoteKey(press: press) {
                send(key)
            } else {
                unhandledPresses.insert(press)
            }
        }

        if !unhandledPresses.isEmpty {
            super.pressesBegan(unhandledPresses, with: event)
        }
    }

    private static let keyCommandDefinitions: [(input: String, title: String)] = [
        (UIKeyCommand.inputUpArrow, "Up"),
        (UIKeyCommand.inputDownArrow, "Down"),
        (UIKeyCommand.inputLeftArrow, "Left"),
        (UIKeyCommand.inputRightArrow, "Right"),
        ("\r", "Enter"),
        (" ", "Play or Pause"),
        (UIKeyCommand.inputEscape, "Back"),
        ("\u{8}", "Delete"),
        ("\u{7F}", "Delete"),
        ("m", "Mute")
    ]
}

private extension RemoteKey {
    init?(keyCommandInput: String) {
        switch keyCommandInput {
        case UIKeyCommand.inputUpArrow:
            self = .up
        case UIKeyCommand.inputDownArrow:
            self = .down
        case UIKeyCommand.inputLeftArrow:
            self = .left
        case UIKeyCommand.inputRightArrow:
            self = .right
        case "\r":
            self = .enter
        case " ":
            self = .playPause
        case UIKeyCommand.inputEscape:
            self = .back
        case "\u{8}", "\u{7F}":
            self = .delete
        case "m", "M":
            self = .mute
        default:
            return nil
        }
    }

    @MainActor
    init?(press: UIPress) {
        switch press.type {
        case .upArrow:
            self = .up
        case .downArrow:
            self = .down
        case .leftArrow:
            self = .left
        case .rightArrow:
            self = .right
        case .select:
            self = .select
        case .menu:
            self = .back
        case .playPause:
            self = .playPause
        @unknown default:
            if let key = press.key.flatMap({ RemoteKey(hidUsage: $0.keyCode.rawValue) }) {
                self = key
            } else {
                return nil
            }
        }
    }

    init?(hidUsage: Int) {
        switch hidUsage {
        case 0x28, 0x77:
            self = .enter
        case 0x58:
            self = .select
        case 0x29, 0x76:
            self = .back
        case 0x2A, 0x4C:
            self = .delete
        case 0x2C, 0x48:
            self = .playPause
        case 0x4A:
            self = .home
        case 0x4F:
            self = .right
        case 0x50:
            self = .left
        case 0x51:
            self = .down
        case 0x52:
            self = .up
        case 0x7F:
            self = .mute
        case 0x80:
            self = .volumeUp
        case 0x81:
            self = .volumeDown
        default:
            return nil
        }
    }
}
#endif

#if canImport(GameController)
struct GameControllerBridge: View {
    let send: (RemoteKey) -> Void
    @State private var input = GameControllerRemoteInput()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                input.start(send: send)
            }
            .onDisappear {
                input.stop()
            }
    }
}

@MainActor
private final class GameControllerRemoteInput {
    private var send: ((RemoteKey) -> Void)?
    private var notificationTokens: [NSObjectProtocol] = []

    func start(send: @escaping (RemoteKey) -> Void) {
        self.send = send
        installNotificationsIfNeeded()
        GCController.controllers().forEach(configure)
    }

    func stop() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        GCController.controllers().forEach(clearHandlers)
        send = nil
    }

    private func installNotificationsIfNeeded() {
        guard notificationTokens.isEmpty else { return }

        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor in
                    self?.configure(controller)
                }
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor in
                    self?.clearHandlers(controller)
                }
            }
        )
    }

    private func configure(_ controller: GCController) {
        clearHandlers(controller)

        if let gamepad = controller.extendedGamepad {
            configure(gamepad)
        } else if let gamepad = controller.microGamepad {
            configure(gamepad)
        }
    }

    private func configure(_ gamepad: GCExtendedGamepad) {
        bind(gamepad.dpad)
        bind(gamepad.leftThumbstick)
        bind(gamepad.buttonA, to: .select)
        bind(gamepad.buttonB, to: .back)
        bind(gamepad.buttonX, to: .playPause)
        bind(gamepad.buttonY, to: .home)
        bind(gamepad.leftShoulder, to: .rewind)
        bind(gamepad.rightShoulder, to: .fastForward)
        bind(gamepad.leftTrigger, to: .volumeDown)
        bind(gamepad.rightTrigger, to: .volumeUp)
        bind(gamepad.buttonMenu, to: .back)

        if let options = gamepad.buttonOptions {
            bind(options, to: .mute)
        }
        if let home = gamepad.buttonHome {
            bind(home, to: .home)
        }
        if let leftThumbstickButton = gamepad.leftThumbstickButton {
            bind(leftThumbstickButton, to: .back)
        }
        if let rightThumbstickButton = gamepad.rightThumbstickButton {
            bind(rightThumbstickButton, to: .select)
        }
    }

    private func configure(_ gamepad: GCMicroGamepad) {
        bind(gamepad.dpad)
        bind(gamepad.buttonA, to: .select)
        bind(gamepad.buttonX, to: .back)
        bind(gamepad.buttonMenu, to: .playPause)
    }

    private func bind(_ dpad: GCControllerDirectionPad) {
        bind(dpad.up, to: .up)
        bind(dpad.down, to: .down)
        bind(dpad.left, to: .left)
        bind(dpad.right, to: .right)
    }

    private func bind(_ button: GCControllerButtonInput, to key: RemoteKey) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.send?(key)
            }
        }
    }

    private func clearHandlers(_ controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            clearHandlers(gamepad)
        }
        if let gamepad = controller.microGamepad {
            clearHandlers(gamepad)
        }
    }

    private func clearHandlers(_ gamepad: GCExtendedGamepad) {
        [gamepad.dpad, gamepad.leftThumbstick, gamepad.rightThumbstick].forEach(clearHandlers)
        [
            gamepad.buttonA,
            gamepad.buttonB,
            gamepad.buttonX,
            gamepad.buttonY,
            gamepad.leftShoulder,
            gamepad.rightShoulder,
            gamepad.leftTrigger,
            gamepad.rightTrigger,
            gamepad.buttonMenu,
            gamepad.buttonOptions,
            gamepad.buttonHome,
            gamepad.leftThumbstickButton,
            gamepad.rightThumbstickButton
        ]
        .compactMap(\.self)
        .forEach { $0.pressedChangedHandler = nil }
    }

    private func clearHandlers(_ gamepad: GCMicroGamepad) {
        clearHandlers(gamepad.dpad)
        [gamepad.buttonA, gamepad.buttonX, gamepad.buttonMenu].forEach {
            $0.pressedChangedHandler = nil
        }
    }

    private func clearHandlers(_ dpad: GCControllerDirectionPad) {
        [dpad.up, dpad.down, dpad.left, dpad.right].forEach {
            $0.pressedChangedHandler = nil
        }
    }
}
#endif
