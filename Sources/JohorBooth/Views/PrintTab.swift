import SwiftUI
import AppKit

struct PrintTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: ImageLibrary
    @ObservedObject var printer: PrintService

    @StateObject private var copiesText = Box("5")
    @StateObject private var confirmCopies = Box<Int?>(nil)
    @StateObject private var showArea = Box(false)

    /// Upload does not need the hotfolder.
    private var canUpload: Bool {
        app.overlayCI != nil && library.current != nil && !printer.busy
    }

    private var canPrint: Bool {
        app.detailsLoaded && library.current != nil && !printer.busy
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            PreviewPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            panel
                .frame(width: 340)
        }
        .padding(24)
        .alert(
            "Print \(confirmCopies.value ?? 0) cop\(confirmCopies.value == 1 ? "y" : "ies")?",
            isPresented: Binding(get: { confirmCopies.value != nil }, set: { if !$0 { confirmCopies.value = nil } })
        ) {
            Button("Print") {
                if let n = confirmCopies.value { printer.printCopies(n) }
                confirmCopies.value = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { confirmCopies.value = nil }
        } message: {
            Text("\(library.current?.lastPathComponent ?? "")\nJPG 1800×1200 → hotfolder")
        }
    }

    private var panel: some View {
        VStack(spacing: 10) {
            Button("DIRECTORY") { app.chooseCameraFolder() }
                .buttonStyle(PanelButtonStyle())
            InfoLine(app.cameraFolderDisplay)

            Button("HOTFOLDER") { app.chooseHotfolder() }
                .buttonStyle(PanelButtonStyle())
                .padding(.top, 8)
            InfoLine(app.hotfolderDisplay)

            Button("SELECT OVERLAY") { app.chooseOverlay() }
                .buttonStyle(PanelButtonStyle())
                .padding(.top, 8)
            HStack(spacing: 4) {
                InfoLine(app.overlayName)
                Button {
                    showArea.value.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Adjust the photo area (X/Y/W/H)")
                .popover(isPresented: $showArea.value) {
                    AreaEditor(title: "Photo area in overlay (2500×1667)", area: $app.settings.printArea, defaultArea: .printDefault)
                        .padding()
                }
            }

            Button("LATEST IMAGE NAME") { library.loadLatest() }
                .buttonStyle(PanelButtonStyle(highlighted: library.hasNewer))
                .keyboardShortcut("l", modifiers: [])
                .help(library.hasNewer ? "New image waiting — press to load (L)" : "Load the newest image (L)")
                .padding(.top, 8)
            InfoLine(library.current?.lastPathComponent ?? "—")

            HStack(spacing: 10) {
                Button("PREV") { library.prev() }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(!library.canPrev)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("NEXT") { library.next() }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(!library.canNext)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }

            Text("PRINT, COPIES")
                .font(.headline)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button("\(n)") { confirmCopies.value = n }
                        .buttonStyle(PanelButtonStyle())
                        .disabled(!canPrint)
                }
            }
            TextField("", text: $copiesText.value)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .bold))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .onChange(of: copiesText.value) { _, new in
                    var digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    if let n = Int(digits), n > 20 { digits = "20" }
                    if digits != new { copiesText.value = digits }
                }
            Button("PRINT") { confirmCopies.value = Int(copiesText.value) }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .disabled(!canPrint || (Int(copiesText.value) ?? 0) < 1)
            Button("UPLOAD") { printer.uploadOnly() }
                .buttonStyle(PanelButtonStyle())
                .disabled(!canUpload)
                .help("Send this photo to TrueNAS only — no JPG to the hotfolder")

            Text(printer.busy ? "Working…" : printer.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

struct PreviewPane: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .underPageBackgroundColor))
            if let image = app.previewImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            }
            if let message = app.previewMessage {
                Text(message)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
