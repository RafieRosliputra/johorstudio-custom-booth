import SwiftUI
import AppKit

struct LogTab: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if app.logDetached {
            VStack(spacing: 12) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("The log is open in its own window.")
                    .font(.title3)
                Button("Bring back into this tab") { dismissWindow(id: "log") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LogView(inWindow: false)
        }
    }
}

struct LogView: View {
    let inWindow: Bool
    @ObservedObject private var store = LogStore.shared
    @Environment(\.openWindow) private var openWindow
    @StateObject private var follow = Box(true)
    @StateObject private var filter = Box<LogLevel?>(nil)

    private var visible: [LogEntry] {
        guard let level = filter.value else { return store.entries }
        return store.entries.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Show", selection: $filter.value) {
                    Text("All").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(LogLevel?.some(level))
                    }
                }
                .frame(width: 160)
                Toggle("Auto-scroll", isOn: $follow.value)
                Spacer()
                Button("Open log folder") {
                    if let folder = store.folder { NSWorkspace.shared.open(folder) }
                }
                if !inWindow {
                    Button {
                        openWindow(id: "log")
                    } label: {
                        Label("Detach", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .padding(10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { entry in
                            LogRow(entry: entry).id(entry.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: store.entries.count) { _, _ in
                    if follow.value, let last = visible.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = visible.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var color: Color {
        switch entry.level {
        case .info: return .primary
        case .ok: return .green
        case .warn: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.time.string(from: entry.date)).foregroundStyle(.secondary)
            Text(entry.level.rawValue)
                .foregroundStyle(color)
                .frame(width: 48, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(entry.level == .info ? Color.primary : color)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}
