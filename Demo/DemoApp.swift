import SwiftUI
import CapabilityPlane
import CapabilityPlaneUI

/// The app owns the compiled-in fleet and policy (DemoFleet.swift); the library's
/// console view only renders whatever plane it is handed.
@main
struct CapabilityPlaneDemoApp: App {
    @StateObject private var model = DemoFleet.makeConsoleModel()

    var body: some Scene {
        WindowGroup {
            CapabilityConsoleView(model: model)
        }
    }
}
