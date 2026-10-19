import SwiftUI
import AppKit

struct UploadTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var upload: UploadManager

    private var statusColor: Color {
        if upload.checking { return .yellow }
        if upload.enabled { return .green }
        if upload.recovered { return .blue }
        return app.settings.truenasPath == nil ? .gray : .red
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("1. TrueNAS folder") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Choose folder…") { upload.chooseFolder() }
                            Button("Test connection") { upload.testNow() }
                                .disabled(app.settings.truenasPath == nil || upload.checking)
                        }
                        Text(app.settings.truenasPath ?? "Not selected")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            StatusDot(color: statusColor)
                            Text(upload.status).font(.headline)
                            if upload.checking { ProgressView().controlSize(.small) }
                        }
                        Toggle("UPLOAD enabled (same as the checkbox next to the tab)", isOn: Binding(
                            get: { upload.enabled || upload.checking },
                            set: { upload.userToggled($0) }
                        ))
                        .disabled(upload.checking)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("2. Sync queue") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Waiting to upload") {
                            Text("\(upload.pending) file(s)").monospacedDigit()
                        }
                        LabeledContent("Done (on TrueNAS)") {
                            Text("\(upload.done) file(s)").monospacedDigit()
                        }
                        LabeledContent("Last sync") {
                            Text(upload.lastSync.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                        }
                        LabeledContent("Upload folder") {
                            Text(WorkPaths.upload(in: app.cameraFolderURL).path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        HStack {
                            Button("Sync now") { upload.syncNow() }
                                .disabled(!upload.enabled)
                            Button("Refresh counts") { upload.refreshCounts() }
                            Button("Show in Finder") {
                                NSWorkspace.shared.open(WorkPaths.upload(in: app.cameraFolderURL))
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("How it works") {
                    Text("""
                    • Every print saves one WebP (2500×1667, quality 50) to the upload folder.
                    • With UPLOAD ticked, new WebP files are copied to TrueNAS right away, and the whole folder is re-checked every 30 seconds.
                    • A file already on TrueNAS (same name) is not uploaded again — it is just moved to upload/DONE. After an internet/NAS drop everything left behind syncs automatically once UPLOAD is ticked again.
                    • If TrueNAS cannot be reached, a popup appears and UPLOAD is unticked. Printing keeps working. When TrueNAS comes back, the header shows "TrueNAS available — tick UPLOAD".
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear { upload.refreshCounts() }
    }
}
