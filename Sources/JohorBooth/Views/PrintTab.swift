import SwiftUI
import AppKit

struct PrintTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: ImageLibrary
    @ObservedObject var printer: PrintService

    @StateObject private var copiesText = Box("")
    @StateObject private var showArea = Box(false)
    @StateObject private var actionLog = Box("—")
    @StateObject private var toast = Box<String?>(nil)
    @StateObject private var pendingPrint = Box<Int?>(nil)
    @StateObject private var monitors = PrintTabMonitors()
    @Environment(\.uiScale) private var s

    /// Printing still needs the details + a loaded image; a busy printer just
    /// queues the job, so the buttons stay enabled.
    private var canSend: Bool {
        app.detailsLoaded && library.current != nil
    }

    // MARK: - Actions

    /// Buttons 1–5: send straight away, no popup.
    private func quickPrint(_ n: Int) {
        guard canSend else { return }
        printer.printCopies(n)
        actionLog.value = "SENT TO PRINTER \(n) COPIES"
        showToast("SENT TO PRINTER \(n) COPIES")
    }

    /// White box + PRINT: 6–20 copies only, confirmed with OK/Cancel.
    private func requestCustomPrint() {
        guard canSend else { return }
        guard let n = Int(copiesText.value), n > 0 else { return }
        if n <= 5 {
            actionLog.value = "USE BUTTONS 1–5 FOR 1 TO 5 COPIES"
            showToast("USE BUTTONS 1–5")
            return
        }
        pendingPrint.value = n
    }

    private func confirmCustomPrint() {
        guard let n = pendingPrint.value else { return }
        pendingPrint.value = nil
        printer.printCopies(n)
        copiesText.value = ""
        actionLog.value = "CUSTOM PRINT SENT"
        showToast("CUSTOM PRINT SENT")
    }

    private func sanitizeCopies() {
        let digits = copiesText.value.filter(\.isNumber)
        let target = Int(digits).map { String(min($0, 20)) } ?? ""
        if copiesText.value != target { copiesText.value = target }
    }

    private func showToast(_ text: String) {
        toast.value = text
        monitors.toastTimer?.invalidate()
        let box = toast
        monitors.toastTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            Task { @MainActor in box.value = nil }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
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

            if let text = toast.value {
                Text(text)
                    .font(.system(size: 16 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18 * s)
                    .padding(.vertical, 10 * s)
                    .background(Capsule().fill(Color.green))
                    .shadow(radius: 6 * s)
                    .padding(.top, 14 * s)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast.value)
        .onAppear {
            app.capture.addClient("print")
            installMonitors()
        }
        .onDisappear {
            app.capture.removeClient("print")
            removeMonitors()
            monitors.toastTimer?.invalidate()
        }
        .alert(
            "Print copies?",
            isPresented: Binding(
                get: { pendingPrint.value != nil },
                set: { if !$0 { pendingPrint.value = nil } }
            )
        ) {
            Button("OK") { confirmCustomPrint() }
            Button("Cancel", role: .cancel) { pendingPrint.value = nil }
        } message: {
            Text("\(pendingPrint.value ?? 0) copies will be sent to the printer.\nPress Space to confirm, Esc to cancel.")
        }
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
                Button("NEXT") { library.next() }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(!library.canNext)
            }

            // ---- PRINT, COPIES ----
            Text("PRINT, COPIES")
                .font(.system(size: 22 * s, weight: .bold))
                .padding(.top, 16 * s)

            Text(actionLog.value)
                .font(.system(size: 13 * s, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 1–5 quick copy buttons — send immediately, no popup.
            HStack(spacing: 8 * s) {
                ForEach(1...5, id: \.self) { n in
                    Button("\(n)") { quickPrint(n) }
                        .buttonStyle(PanelButtonStyle(prominent: true))
                        .disabled(!canSend)
                }
            }

            // Custom count (6–20) + PRINT, in their own outlined box.
            VStack(spacing: 8 * s) {
                TextField("6–20", text: $copiesText.value)
                    .font(.system(size: 28 * s, weight: .bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 6 * s)
                    .padding(.horizontal, 8 * s)
                    .background(RoundedRectangle(cornerRadius: 8 * s).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 8 * s).stroke(Color.secondary.opacity(0.5)))
                    .onChange(of: copiesText.value) { _, _ in sanitizeCopies() }
                Button("PRINT") { requestCustomPrint() }
                    .buttonStyle(PanelButtonStyle(prominent: true))
                    .disabled(!canSend)
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

    /// Left-click purges (no confirmation), right-click opens the printer queue.
    private var purgeButton: some View {
        Button("PURGE PRINT QUEUE") { app.purgePrintQueue() }
            .buttonStyle(PanelButtonStyle(destructive: true))
            .help("Remove all jobs from the default printer's queue (right-click to view the queue)")
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { monitors.purgeRect = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, r in monitors.purgeRect = r }
                }
            )
    }

    // MARK: - Key / right-click monitors

    private func installMonitors() {
        // Space = OK, Esc = Cancel while the custom-print popup is up.
        if monitors.key == nil {
            monitors.key = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                MainActor.assumeIsolated { () -> NSEvent? in
                    guard pendingPrint.value != nil else { return event }
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if event.keyCode == 49, mods.isEmpty {
                        confirmCustomPrint()
                        return nil
                    }
                    if event.keyCode == 53, mods.isEmpty {
                        pendingPrint.value = nil
                        return nil
                    }
                    return event
                }
            }
        }
        // Right-click on PURGE opens the default printer queue.
        if monitors.right == nil {
            monitors.right = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { event in
                MainActor.assumeIsolated { () -> NSEvent? in
                    guard let window = event.window, let content = window.contentView else { return event }
                    let p = event.locationInWindow
                    let point = CGPoint(x: p.x, y: content.bounds.height - p.y)
                    if monitors.purgeRect.contains(point) {
                        PrinterQueue.openQueueWindow()
                        return nil
                    }
                    return event
                }
            }
        }
    }

    private func removeMonitors() {
        if let key = monitors.key { NSEvent.removeMonitor(key); monitors.key = nil }
        if let right = monitors.right { NSEvent.removeMonitor(right); monitors.right = nil }
    }
}

@MainActor
private final class PrintTabMonitors: ObservableObject {
    var key: Any?
    var right: Any?
    var purgeRect: CGRect = .zero
    var toastTimer: Timer?

    deinit {
        if let key { NSEvent.removeMonitor(key) }
        if let right { NSEvent.removeMonitor(right) }
    }
}
