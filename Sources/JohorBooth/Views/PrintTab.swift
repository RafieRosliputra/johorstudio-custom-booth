import SwiftUI
import AppKit

struct PrintTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: ImageLibrary
    @ObservedObject var printer: PrintService

    @StateObject private var copiesText = Box("0")
    @StateObject private var showArea = Box(false)
    @StateObject private var confirmPurge = Box(false)
    @Environment(\.uiScale) private var s

    /// Upload does not need the hotfolder.
    private var canPrint: Bool {
        app.detailsLoaded && library.current != nil && !printer.busy
    }

    private func tapDigit(_ n: Int) {
        let current = Int(copiesText.value) ?? 0
        copiesText.value = String(min(current * 10 + n, 20))
    }

    private func printNow() {
        guard let n = Int(copiesText.value), n > 0 else { return }
        printer.printCopies(n)
        copiesText.value = "0"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24 * s) {
            VStack(spacing: 8 * s) {
                PreviewPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Filmstrip(library: library, thumbs: app.thumbs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 10 * s) {
                ScrollView(.vertical, showsIndicators: false) {
                    panel
                }
                purgeButton
            }
            .frame(width: 340 * s)
        }
        .padding(24 * s)
        .onAppear { app.capture.addClient("print") }
        .onDisappear { app.capture.removeClient("print") }
    }

    private var panel: some View {
        VStack(spacing: 10 * s) {
            Button("DIRECTORY") { app.chooseCameraFolder() }
                .buttonStyle(PanelButtonStyle())
            InfoLine(app.cameraFolderDisplay)

            Button("HOTFOLDER") { app.chooseHotfolder() }
                .buttonStyle(PanelButtonStyle())
                .padding(.top, 8 * s)
            InfoLine(app.hotfolderDisplay)

            Button("SELECT OVERLAY") { app.chooseOverlay() }
                .buttonStyle(PanelButtonStyle())
                .padding(.top, 8 * s)
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
                .padding(.top, 8 * s)
            InfoLine(library.current?.lastPathComponent ?? "—")

            HStack(spacing: 10 * s) {
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
                .font(.system(size: 15 * s, weight: .bold))
                .padding(.top, 16 * s)

            // Custom print count: digits 1–0 build the number, PRINT runs it,
            // then the count resets to 0. Outlined so it stays apart from COPY.
            VStack(spacing: 8 * s) {
                HStack(spacing: 4 * s) {
                    ForEach(1...9, id: \.self) { n in
                        Button("\(n)") { tapDigit(n) }
                            .buttonStyle(PanelButtonStyle(compact: true))
                            .disabled(!canPrint)
                    }
                    Button("0") { tapDigit(0) }
                        .buttonStyle(PanelButtonStyle(compact: true))
                        .disabled(!canPrint)
                }
                Button("PRINT") { printNow() }
                    .buttonStyle(PanelButtonStyle(prominent: true, compact: true))
                    .disabled(!canPrint || (Int(copiesText.value) ?? 0) < 1)
            }
            .padding(10 * s)
            .overlay(
                RoundedRectangle(cornerRadius: 10 * s)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
            )

            SyncControl(upload: app.upload, compact: true)

            Text(printer.busy ? "Working…" : printer.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity)

            screenPreview
                .padding(.top, 8 * s)
        }
    }

    /// What the 2nd screen shows now; click it to show the current photo there.
    private var screenPreview: some View {
        VStack(spacing: 6 * s) {
            Text("2ND SCREEN — click to show this photo")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(.secondary)
            SecondScreenContent(app: app, controller: app.screen)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8 * s))
                .overlay(RoundedRectangle(cornerRadius: 8 * s).stroke(Color.secondary.opacity(0.4)))
                .contentShape(Rectangle())
                .onTapGesture { app.sendCurrentToScreen() }
                .opacity(library.current == nil ? 0.6 : 1)
                .help("Show the current photo on the 2nd screen")
            SecondsField(seconds: $app.settings.countdownSeconds)
                .font(.system(size: 12 * s))
        }
    }

    private var purgeButton: some View {
        Button("PURGE PRINT QUEUE") { confirmPurge.value = true }
            .buttonStyle(PanelButtonStyle(destructive: true))
            .help("Remove all jobs from the default printer's queue")
            .alert("Caution", isPresented: $confirmPurge.value) {
                Button("Purge all jobs", role: .destructive) { app.purgePrintQueue() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Purge all printer job (remove all print queue)?\n\nEvery job on the default printer will be removed and will NOT print. This cannot be undone.")
            }
    }
}
