import SwiftUI
import PultCore

@main
struct PultApp: App {
    // The same instance intents resolve via SharedRemote, so a command sent
    // from the Lock Screen and the on-screen remote drive one session.
    private let model = SharedRemote.model

    var body: some Scene {
        WindowGroup {
            RemoteRootView(model: model)
                // Applied above the root so sheets, which inherit their
                // environment from inside RemoteRootView, pick it up too.
                .tint(.pultAccent)
        }
    }
}
