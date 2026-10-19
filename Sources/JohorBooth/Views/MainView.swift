import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(upload: app.upload, screen: app.screen)
            Divider()
            Group {
                switch app.tab {
                case .print: PrintTab(library: app.library, printer: app.printer)
                case .upload: UploadTab(upload: app.upload)
                case .log: LogTab()
                case .screen: ScreenTab(capture: app.capture, screen: app.screen)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .onAppear { app.start() }
        .alert(
            app.alert?.title ?? "",
            isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } }),
            presenting: app.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var upload: UploadManager
    @ObservedObject var screen: SecondScreenController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("JohorStudio.com").font(.title2.bold())
                Text("Custom BOOTH").font(.title2).foregroundStyle(.secondary)
                Spacer()
                Text(app.paths.root.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(app.paths.root.path)
            }
            HStack(spacing: 6) {
                TabButton(.print)
                HStack(spacing: 2) {
                    TabButton(.upload)
                    Toggle("", isOn: Binding(
                        get: { upload.enabled || upload.checking },
                        set: { upload.userToggled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(upload.checking)
                    .help("Upload to TrueNAS (checks the connection first)")
                }
                TabButton(.log)
                TabButton(.screen)
                Spacer()
                if upload.recovered {
                    Label("TrueNAS available — tick UPLOAD", systemImage: "externaldrive.badge.checkmark")
                        .foregroundStyle(.blue)
                }
                if upload.enabled {
                    Label("Upload ON", systemImage: "icloud.and.arrow.up").foregroundStyle(.green)
                }
                if screen.isOpen {
                    Label("2nd screen ON", systemImage: "display.2").foregroundStyle(.green)
                }
            }
            .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct TabButton: View {
    @EnvironmentObject var app: AppState
    let tab: MainTab

    init(_ tab: MainTab) { self.tab = tab }

    var body: some View {
        let selected = app.tab == tab
        Button {
            app.tab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.clear))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
