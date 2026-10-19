import SwiftUI
import AppKit

struct ScreenTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var capture: CaptureManager
    @ObservedObject var screen: SecondScreenController
    @StateObject private var displays = Box<[DisplayChoice]>([])

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Color.black
                    if app.settings.showTabPreview {
                        SecondScreenContent(app: app, controller: screen)
                    } else {
                        Text("Preview off — the 2nd screen is still live")
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 8) {
                    StatusDot(color: capture.running ? .green : .gray)
                    Text(capture.running ? "LIVE — \(capture.activeDevice ?? "starting…")" : "Live feed off")
                    Spacer()
                    Button("Test countdown with latest image") { screen.testWithLatest() }
                }
                .font(.callout)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Form {
                Section("Capture device") {
                    Picker("Device", selection: $app.settings.captureDeviceID) {
                        Text("Auto (first capture card)").tag(String?.none)
                        ForEach(capture.devices) { device in
                            Text(device.name).tag(String?.some(device.id))
                        }
                    }
                    Button("Refresh devices") { capture.refreshDevices() }
                }
                Section("2nd monitor") {
                    Picker("Display", selection: $app.settings.screenDisplayID) {
                        Text("Auto (second monitor)").tag(UInt32?.none)
                        ForEach(displays.value) { display in
                            Text(display.name).tag(UInt32?.some(display.id))
                        }
                    }
                }
                Section("Live feed") {
                    AreaEditor(title: "Live area on screen (1920×1080)", area: $app.settings.liveArea, defaultArea: .liveDefault)
                    Toggle("Mirror live feed", isOn: $app.settings.mirrorLive)
                    Toggle("Mirror overlay", isOn: $app.settings.mirrorOverlay)
                    Toggle("Show preview in this tab", isOn: $app.settings.showTabPreview)
                    Stepper("Show new photo for \(app.settings.countdownSeconds)s", value: $app.settings.countdownSeconds, in: 1...15)
                }
                Section {
                    if screen.isOpen {
                        Button("Stop 2nd screen", role: .destructive) { screen.close() }
                    } else {
                        Button("Start 2nd screen") { screen.open() }
                            .keyboardShortcut(.defaultAction)
                    }
                    Text("Esc on the 2nd screen also closes it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)
        }
        .padding(24)
        .onAppear {
            capture.refreshDevices()
            displays.value = DisplayChoice.all()
            updatePreviewClient()
        }
        .onDisappear { capture.removeClient("tab") }
        .onChange(of: app.settings.showTabPreview) { _, _ in updatePreviewClient() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays.value = DisplayChoice.all()
        }
    }

    private func updatePreviewClient() {
        if app.settings.showTabPreview {
            capture.addClient("tab")
        } else {
            capture.removeClient("tab")
        }
    }
}

struct DisplayChoice: Identifiable {
    let id: UInt32
    let name: String

    static func all() -> [DisplayChoice] {
        NSScreen.screens.map { screen in
            let size = screen.frame.size
            return DisplayChoice(
                id: SecondScreenController.displayID(screen),
                name: "\(screen.localizedName) (\(Int(size.width))×\(Int(size.height)))"
            )
        }
    }
}
