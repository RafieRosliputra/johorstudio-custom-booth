import SwiftUI
import AppKit

/// One control for TrueNAS: grey = not connected, green = connected,
/// pulsing green = autosync on but photos still waiting to go out.
/// A one-line log sits underneath with speed and how many files are left.
struct SyncControl: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var upload: UploadManager
    var compact = false

    @StateObject private var pulse = Box(false)
    @Environment(\.uiScale) private var s

    private var remaining: Int { upload.remaining }

    private var pulsing: Bool { upload.enabled && remaining > 0 }

    private var tint: Color {
        upload.connected ? (remaining > 0 ? .green : Color(nsColor: .systemGreen)) : Color(nsColor: .tertiaryLabelColor)
    }

    private var label: String {
        if upload.checking { return "CHECKING…" }
        return upload.enabled ? "AUTOSYNC ENABLED" : "SYNC"
    }

    private var statusLine: String {
        if !upload.connected {
            return upload.checking ? "checking connection…" : "not connected"
        }
        if remaining > 0 {
            return "uploading · \(remaining) remaining"
        }
        let n = app.library.files.count
        return n == 0 ? "connected, nothing to sync" : "connected, in-synced \(n) files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            Button {
                upload.toggle()
            } label: {
                HStack(spacing: 8 * s) {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 8 * s, height: 8 * s)
                    Text(label)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle(compact: compact))
            .tint(tint)
            .background(
                RoundedRectangle(cornerRadius: (compact ? 7 : 10) * s)
                    .fill(tint.opacity(pulsing ? (pulse.value ? 0.85 : 0.35) : 1))
            )
            .opacity(upload.checking ? 0.6 : 1)
            .disabled(upload.checking)
            .help(upload.enabled
                ? "Autosync is on — click to stop sending photos to TrueNAS"
                : "Connect to TrueNAS and autosync every photo in the livefolder")

            Text(statusLine)
                .font(.system(size: (compact ? 10 : 11) * s, weight: .medium, design: .monospaced))
                .foregroundStyle(upload.connected ? .secondary : .tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: pulsing) { _, on in pulse.value = on }
        .onAppear {
            pulse.value = pulsing
            upload.refreshCounts()
            app.printer.refreshUnsynced()
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse.value)
    }
}
