import SwiftUI

@main
struct HeyAgentApp: App {
    @StateObject private var hub = TriggerHub()
    @StateObject private var gazeRunner = GazeBridgeCommandRunner()
    @StateObject private var bridge = BridgeSupervisor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hub)
                .environmentObject(gazeRunner)
                .environmentObject(bridge)
        }
        .defaultSize(width: 580, height: 920)
    }
}
