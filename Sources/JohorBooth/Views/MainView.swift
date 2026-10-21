import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        GeometryReader { geo in
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
            .environment(\.uiScale, UIScale.factor(for: geo.size))
        }
        .frame(minWidth: 900, minHeight: 600)
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
    @Environment(\.uiScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            ZStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("JohorStudio.com").font(.system(size: 22 * s, weight: .bold))
                    Text("Custom BOOTH").font(.system(size: 22 * s)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                HStack {
                    Spacer()
                    Text(app.paths.root.lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(app.paths.root.path)
                }
            }
            HStack(spacing: 6) {
                TabButton(.print)
                TabButton(.upload)
                TabButton(.log)
                TabButton(.screen)
                Spacer()
                SyncControl(upload: upload, compact: true)
                    .frame(width: 190 * s)
                if screen.isOpen {
                    Label("2nd screen ON", systemImage: "display.2").foregroundStyle(.green)
                }
            }
            .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 20 * s)
        .padding(.vertical, 12 * s)
    }
}

struct TabButton: View {
    @EnvironmentObject var app: AppState
    @Environment(\.uiScale) private var s
    let tab: MainTab

    init(_ tab: MainTab) { self.tab = tab }

    var body: some View {
        let selected = app.tab == tab
        Button {
            app.tab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 13 * s, weight: .bold))
                .padding(.horizontal, 16 * s)
                .padding(.vertical, 7 * s)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.clear))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
