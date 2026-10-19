import SwiftUI
import AppKit

@main
struct JohorBoothApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()

    var body: some Scene {
        Window("johorstudio-custom-photobooth", id: "main") {
            MainView()
                .environmentObject(app)
        }
        .defaultSize(width: Self.screenSize.width, height: Self.screenSize.height)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Detached log: resizable; closing it puts the log back into the LOG tab.
        Window("johorstudio-custom-photobooth — Log", id: "log") {
            LogView(inWindow: true)
                .environmentObject(app)
                .frame(minWidth: 500, minHeight: 300)
                .onAppear { app.logDetached = true }
                .onDisappear { app.logDetached = false }
        }
        .defaultSize(width: 900, height: 600)
    }

    static var screenSize: CGSize {
        NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
