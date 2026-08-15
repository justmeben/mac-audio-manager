import AppKit
import SwiftUI

@main
struct AudioManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @StateObject private var mixer = AppMixerController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceManager)
                .environmentObject(mixer)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Critical: destroy all taps, otherwise tapped apps stay muted.
        AppMixerController.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
