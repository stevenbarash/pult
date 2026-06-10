import SwiftUI
import WidgetKit

@main
struct PultWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RemoteLiveActivity()
        RemoteSessionControl()
        RemoteCommandControl()
        OpenRemoteControl()
    }
}
