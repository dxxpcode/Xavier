import SwiftUI

@main
struct XavierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.appState.modelManager)
                .environmentObject(appDelegate.appState.voiceSession)
                .environmentObject(appDelegate.appState.settings)
        }
    }
}
