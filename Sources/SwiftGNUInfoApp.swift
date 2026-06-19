import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct SwiftGNUInfoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SSHConnectionStore()
    @StateObject private var preferences = AppPreferencesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(preferences)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(colorScheme)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch preferences.theme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
