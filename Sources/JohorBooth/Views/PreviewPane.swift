import AppKit
import SwiftUI

/// The big preview, drawn in canvas space: the livefolder photo underneath the
/// overlay artwork, laid out exactly as it will be printed.
///
/// Scroll over it to zoom the photo, drag to move it, and the four-arrow button
/// opens the manual X/Y/W/H panel. Only the photo moves — the overlay is fixed.
struct PreviewPane: View {
    @EnvironmentObject var app: AppState
    @StateObject private var state = PreviewState()
    @StateObject private var commitPulse = Box(false)
    @Environment(\.uiScale) private var s

    private var canvas: CGSize { Compositor.canvas }

    var body: some View {
        GeometryReader { geo in
            let k = scale(for: geo.size)
            let origin = CGPoint(
                x: (geo.size.width - canvas.width * k) / 2,
                y: (geo.size.height - canvas.height * k) / 2
            )
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .underPageBackgroundColor))

                if app.previewPhoto != nil, app.overlayCG != nil {
                    canvasStack(k: k)
                        .offset(x: origin.x, y: origin.y)
                }

                if let message = app.previewMessage {
                    Text(message)
                        .font(.system(size: 18 * s, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                chrome

                if app.hasSpecific {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red, lineWidth: 3 * s)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    state.mouse = point
                case .ended:
                    state.mouse = nil
                }
            }
            .onAppear {
                state.paneSize = geo.size
                installScrollMonitor()
                installKeyMonitor()
            }
            .onChange(of: geo.size) { _, size in
                state.paneSize = size
            }
            .onDisappear {
                removeScrollMonitor()
                removeKeyMonitor()
            }
        }
    }

    // MARK: - Layers

    /// Photo first, overlay on top, both clipped to the canvas rect.
    private func canvasStack(k: CGFloat) -> some View {
        let frame = app.effectiveFrame
        let width = canvas.width * k
        let height = canvas.height * k
        return ZStack(alignment: .topLeading) {
            if let photo = app.previewPhoto {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: frame.w * k, height: frame.h * k)
                    .clipped()
                    .offset(x: frame.x * k, y: frame.y * k)
            }
            if let overlay = app.overlayCG {
                Image(decorative: overlay, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(panGesture(k: k))
    }

    private func panGesture(k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if state.dragStart == nil {
                    state.dragStart = app.effectiveFrame
                }
                guard let start = state.dragStart, k > 0 else { return }
                var frame = start
                frame.x += value.translation.width / k
                frame.y += value.translation.height / k
                app.updateEffectiveFrame(frame.clamped())
            }
            .onEnded { _ in state.dragStart = nil }
    }

    // MARK: - Chrome

    private var chrome: some View {
        HStack(alignment: .top) {
            globalColumn
            Spacer()
            perPhotoColumn
        }
        .padding(12 * s)
        .onChange(of: app.hasPendingCommit) { _, on in commitPulse.value = on }
    }

    private var zoomBadge: some View {
        Text(String(format: "%.1f%%", app.photoZoom * 100))
            .font(.system(size: 12 * s, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 4 * s)
            .background(.regularMaterial, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(count: 2) { app.resetZoom() }
            .help("Photo size relative to the overlay's photo area — double-click to reset to 100%")
    }

    private var globalColumn: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Text("Global setting")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8 * s) {
                zoomBadge
                iconButton("arrow.up.and.down.and.arrow.left.and.right", help: "Photo frame — set X / Y / W / H") {
                    state.showFrame.toggle()
                }
                .popover(isPresented: $state.showFrame) {
                    PhotoFrameEditor()
                        .environmentObject(app)
                        .padding()
                }
            }
            iconButton("sun.max", help: "Brightness gamma") { state.showGamma.toggle() }
                .popover(isPresented: $state.showGamma) {
                    NumberPopup(icon: "sun.max", suffix: "", initialValue: app.gamma, onApply: { app.setGamma($0) }, isPresented: $state.showGamma)
                }
            iconButton("scroll", help: "Mouse scroll zoom amount") { state.showScroll.toggle() }
                .popover(isPresented: $state.showScroll) {
                    NumberPopup(icon: "scroll", suffix: "", initialValue: app.settings.zoomGamma, onApply: { app.settings.zoomGamma = $0 }, isPresented: $state.showScroll)
                }
            iconButton("plus.magnifyingglass", help: "Zoom % per step") { state.showZoom.toggle() }
                .popover(isPresented: $state.showZoom) {
                    NumberPopup(icon: "plus.magnifyingglass", suffix: "%", initialValue: app.settings.zoomStep, onApply: { app.settings.zoomStep = $0 }, isPresented: $state.showZoom)
                }
            iconButton("rotate.left", help: "Rotate left 0.1°") { app.rotate(by: -0.1) }
            iconButton("rotate.right", help: "Rotate right 0.1°") { app.rotate(by: 0.1) }
        }
    }

    private var perPhotoColumn: some View {
        VStack(alignment: .trailing, spacing: 8 * s) {
            Text("This photo setting")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(.secondary)
            commitButton
            iconButton("pencil", help: "Edit this photo") {
                app.beginEdit()
                state.showPhotoEdit = true
            }
            .popover(isPresented: $state.showPhotoEdit) {
                PhotoEditDialog(isPresented: $state.showPhotoEdit)
                    .environmentObject(app)
            }
            iconButton("arrow.uturn.backward", help: "Reset this photo", enabled: app.hasSpecific) {
                app.resetPhotoSettings()
            }
        }
    }

    private var commitButton: some View {
        let color: Color = app.hasSpecific ? .red : Color.secondary.opacity(0.4)
        return Button {
            app.commitWebp()
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18 * s, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 40 * s, height: 40 * s)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9 * s))
                .overlay(
                    RoundedRectangle(cornerRadius: 9 * s)
                        .stroke(color.opacity(0.6), lineWidth: app.hasPendingCommit ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!app.hasSpecific)
        .opacity(app.hasPendingCommit ? (commitPulse.value ? 0.4 : 1) : 1)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: commitPulse.value)
        .help(app.hasPendingCommit ? "Commit changes (update WebP)" : (app.hasSpecific ? "Committed" : "Follows global"))
    }

    private func iconButton(_ name: String, help: String, tint: Color? = nil, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 16 * s, weight: .bold))
                .foregroundStyle(enabled ? (tint ?? .primary) : Color.secondary.opacity(0.35))
                .frame(width: 40 * s, height: 40 * s)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9 * s))
                .overlay(RoundedRectangle(cornerRadius: 9 * s).stroke(Color.secondary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    // MARK: - Geometry

    /// Canvas pixels → points, fitted inside the pane with a small margin.
    private func scale(for size: CGSize) -> CGFloat {
        let inset = 20 * s
        let width = max(1, size.width - inset)
        let height = max(1, size.height - inset)
        return min(width / canvas.width, height / canvas.height)
    }

    // MARK: - Scroll = zoom

    private func installScrollMonitor() {
        guard state.monitor == nil else { return }
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                handleScroll(event) ? nil : event
            }
        }
    }

    private func removeScrollMonitor() {
        if let monitor = state.monitor {
            NSEvent.removeMonitor(monitor)
            state.monitor = nil
        }
    }

    /// Q / E rotate (counterclockwise / clockwise) — only when the mouse is over
    /// the big preview. Holding the key follows the system key-repeat rate.
    private func installKeyMonitor() {
        guard state.keyMonitor == nil else { return }
        state.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard state.mouse != nil, !isTyping else { return event }
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
                switch event.keyCode {
                case 12: // Q — counterclockwise
                    app.rotate(by: -0.1)
                    return nil
                case 14: // E — clockwise
                    app.rotate(by: 0.1)
                    return nil
                default:
                    return event
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = state.keyMonitor {
            NSEvent.removeMonitor(monitor)
            state.keyMonitor = nil
        }
    }

    /// Don't zoom while a text field (the gamma / count boxes) has focus.
    private var isTyping: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    /// Only when the pointer is over the preview — everywhere else scroll passes
    /// through to whatever is underneath (the filmstrip, the panel, popovers).
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let point = state.mouse, state.paneSize.width > 1 else { return false }
        // Scrolling the preview deselects any focused text field so zoom works again.
        if isTyping { NSApp.keyWindow?.makeFirstResponder(nil) }
        let k = scale(for: state.paneSize)
        guard k > 0 else { return false }
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return false }

        // One step = `zoomStep` %. A mouse-wheel notch is `gamma` steps; a trackpad
        // gesture maps its pixel delta to steps (10 px = one step). Scroll up = zoom in.
        let stepPercent = max(0.01, app.settings.zoomStep)
        let stepCount: Double
        if event.hasPreciseScrollingDeltas {
            stepCount = Double(dy) / 10.0
        } else {
            stepCount = (dy > 0 ? -1 : 1) * max(0.05, app.settings.zoomGamma)
        }
        let area = app.settings.printArea.cgRect
        guard area.width > 0 else { return false }
        let currentZoom = app.effectiveFrame.w / area.width
        guard currentZoom > 0 else { return false }

        // Clamp to 10% – 600% of the overlay's photo area.
        let targetZoom = min(6.0, max(0.1, currentZoom * pow(1 + stepPercent / 100, stepCount)))
        guard abs(targetZoom - currentZoom) > 0.0001 else { return true }

        let origin = CGPoint(
            x: (state.paneSize.width - canvas.width * k) / 2,
            y: (state.paneSize.height - canvas.height * k) / 2
        )
        let pivot = CGPoint(x: (point.x - origin.x) / k, y: (point.y - origin.y) / k)
        let factor = targetZoom / currentZoom
        app.updateEffectiveFrame(app.effectiveFrame.scaled(by: factor, around: pivot))
        return true
    }
}

@MainActor
private final class PreviewState: ObservableObject {
    @Published var showFrame = false
    @Published var showGamma = false
    @Published var showScroll = false
    @Published var showZoom = false
    @Published var showPhotoEdit = false

    var mouse: CGPoint?
    var paneSize: CGSize = .zero
    var dragStart: PhotoFrame?
    var monitor: Any?
    var keyMonitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

/// Manual X / Y / W / H for the photo frame — the same numbers the print uses.
struct PhotoFrameEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.uiScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text("Photo frame (canvas 2500×1667)")
                .font(.system(size: 13 * s, weight: .bold))

            Grid(alignment: .leading, horizontalSpacing: 10 * s, verticalSpacing: 6 * s) {
                GridRow {
                    field("X", \.x)
                    field("Y", \.y)
                }
                GridRow {
                    field("W", \.w)
                    field("H", \.h)
                }
            }

            HStack(spacing: 8 * s) {
                Button("Reset") { app.resetZoom() }
                    .font(.system(size: 11 * s))
                Button("Centre") { app.centrePhoto() }
                    .font(.system(size: 11 * s))
                Spacer()
            }
        }
        .frame(width: 240 * s)
    }

    private func field(_ label: String, _ key: WritableKeyPath<PhotoFrame, Double>) -> some View {
        HStack(spacing: 4 * s) {
            Text(label)
                .font(.system(size: 11 * s, weight: .semibold))
                .frame(width: 14 * s, alignment: .leading)
            TextField(
                label,
                value: binding(key),
                format: .number.grouping(.never).precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12 * s))
            .frame(width: 62 * s)
        }
    }

    private func binding(_ key: WritableKeyPath<PhotoFrame, Double>) -> Binding<Double> {
        Binding(
            get: { app.effectiveFrame[keyPath: key].rounded() },
            set: { newValue in
                var frame = app.effectiveFrame
                frame[keyPath: key] = newValue
                app.updateEffectiveFrame(frame.clamped())
            }
        )
    }
}

/// Vertical per-photo editor: gamma / rotation / pan / zoom with `- Label +`
/// buttons and a text field each. Edits the preview-only draft; OK commits.
struct PhotoEditDialog: View {
    @EnvironmentObject var app: AppState
    @Environment(\.uiScale) private var s
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text("Edit this photo")
                .font(.system(size: 14 * s, weight: .bold))

            AdjustRow(label: "Gamma", step: 0.1, value: binding(\.gamma))
            AdjustRow(label: "Rotation", step: 0.1, value: binding(\.rotation))
            AdjustRow(label: "Pan X", step: 1, value: binding(\.x))
            AdjustRow(label: "Pan Y", step: 1, value: binding(\.y))
            AdjustRow(label: "Zoom W", step: 1, value: binding(\.w))
            AdjustRow(label: "Zoom H", step: 1, value: binding(\.h))

            Text("CMD+C to copy setting")
                .font(.system(size: 10 * s))
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("OK") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14 * s)
        .frame(width: 240 * s)
        .onDisappear { app.draft = nil }
    }

    private func binding(_ kp: WritableKeyPath<PhotoAdjustment, Double>) -> Binding<Double> {
        Binding(
            get: { app.draft?[keyPath: kp] ?? 0 },
            set: { v in app.updateDraft { $0[keyPath: kp] = v } }
        )
    }

    private func commit() {
        if let d = app.draft { app.commitSpecific(d) }
        app.draft = nil
        isPresented = false
    }

    private func cancel() {
        app.draft = nil
        isPresented = false
    }
}
