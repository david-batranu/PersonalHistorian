import SwiftUI

@main
struct PersonalHistorianApp: App {
    @State private var appState = AppState()
    
    // Using an AppDelegate to hide from dock is handled by LSUIElement in Info.plist,
    // but we can add window observations here if needed.

    var body: some Scene {
        MenuBarExtra("Personal Historian", systemImage: "clock.arrow.circlepath") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Personal Historian", id: "main") {
            MainView()
                .environment(appState)
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
                .environment(appState)
        }
        
        Window("Permission Guide", id: "permissions") {
            PermissionGuideView {
                if appState.checkPermissions() == .granted {
                    appState.startRecording()
                }
            }
            .environment(appState)
        }
        .windowResizability(.contentSize)
    }
}
