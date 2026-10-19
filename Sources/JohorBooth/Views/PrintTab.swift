import SwiftUI
import AppKit

struct PrintTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: ImageLibrary
    @ObservedObject var printer: PrintService

    @State private var copiesText = "5"
    @State private var confirmCopies: Int?
    @State private var showArea = false

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
            "Print \(confirmCopies ?? 0) cop\(confirmCopies == 1 ? "y" : "ies")?",
            isPresented: Binding(get: { confirmCopies != nil }, set: { if !$0 { confirmCopies = nil } })
        ) {
            Button("Print") {
                if let n = confirmCopies { printer.printCopies(n) }
                confirmCopies = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { confirmCopies = nil }
        } message: {
            Text("\(library.current?.lastPathComponent ?? "")\nJPG 1800×1200 → hotfolder")
        }
    }

    private var panel: some View {
        VStack(spacing: 10) {
            Button("DIRECTORY") { app.chooseCameraFolder() }
                .buttonStyle(PanelButtonStyle())
            InfoLine(app.cameraFolderDisplay)

            Button("SELECT OVERLAY") { app.chooseOverlay() }
                .buttonStyle(PanelButtonStyle())
                .padding(.top, 8)
            HStack(spacing: 4) {
                InfoLine(app.overlayName)
                Button {
                    showArea.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Adjust the photo area (X/Y/W/H)")
                .popover(isPresented: $showArea) {
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
                    Button("\(n)") { confirmCopies = n }
                        .buttonStyle(PanelButtonStyle())
                        .disabled(!canPrint)
                }
            }
            TextField("", text: $copiesText)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .bold))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .onChange(of: copiesText) { _, new in
                    var digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    if let n = Int(digits), n > 20 { digits = "20" }
                    if digits != new { copiesText = digits }
                }
            Button("PRINT") { confirmCopies = Int(copiesText) }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .disabled(!canPrint || (Int(copiesText) ?? 0) < 1)

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
