import SwiftUI
import PultCore

@main
struct PultApp: App {
    @State private var model = RemoteControlModel()

    var body: some Scene {
        WindowGroup {
            RemoteRootView(model: model)
                // Applied above the root so sheets, which inherit their
                // environment from inside RemoteRootView, pick it up too.
                .tint(.pultAccent)
        }
    }
}
