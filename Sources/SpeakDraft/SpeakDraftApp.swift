import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // menu bar only（與 Info.plist LSUIElement 雙保險；此處 NSApp 已建立）
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.start()
    }
}

@main
struct SpeakDraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: iconName)
        }

        Settings {
            SettingsView()
        }
    }

    private var iconName: String {
        switch state.phase {
        case .recording: return "waveform"
        case .transcribing, .rewriting: return "ellipsis.circle"
        case .pasting: return "list.clipboard"
        case .idle: return state.errorMessage != nil ? "exclamationmark.triangle" : "mic"
        }
    }
}
