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
            }
            .onChange(of: geo.size) { _, size in
                state.paneSize = size
            }
            .onDisappear { removeScrollMonitor() }
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
                app.photoFrame = frame.clamped()
            }
            .onEnded { _ in state.dragStart = nil }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8 * s) {
                Spacer()
                VStack(alignment: .trailing, spacing: 6 * s) {
                    zoomBadge
                    if app.adjustmentsDirty { dirtyBadge }
                    adjustmentIcons
                }
                frameButton
            }
            Spacer()
        }
        .padding(12 * s)
    }

    private var zoomBadge: some View {
        Text(String(format: "%.1f%%", app.photoZoom * 100))
            .font(.system(size: 11 * s, weight: .bold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 4 * s)
            .background(.regularMaterial, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(count: 2) { app.photoFrame = nil }
            .help("Photo size relative to the overlay's photo area — double-click to reset to 100%")
    }

    /// "! old value" when the current gamma/rotation differ from what was processed.
    private var dirtyBadge: some View {
        let parts: [String] = [
            abs(app.gamma - app.appliedGamma) > 0.0005 ? "γ\(Self.num(app.appliedGamma))" : nil,
            abs(app.rotation - app.appliedRotation) > 0.0005 ? "r=\(Int(app.appliedRotation))°" : nil,
        ].compactMap { $0 }
        return Text("! " + parts.joined(separator: " · "))
            .font(.system(size: 10 * s, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7 * s)
            .padding(.vertical, 3 * s)
            .background(Capsule().fill(Color.orange))
            .help("Processed image uses the old values — will re-process")
    }

    private var adjustmentIcons: some View {
        HStack(spacing: 5 * s) {
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
            iconButton("rotate.left", help: "Rotate left 1°") { app.rotate(by: -1) }
            iconButton("rotate.right", help: "Rotate right 1°") { app.rotate(by: 1) }
        }
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11 * s, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 22 * s, height: 22 * s)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6 * s))
                .overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Color.secondary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func num(_ v: Double) -> String {
        var out = String(format: "%.2f", v)
        while out.contains("."), out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }

    private var frameButton: some View {
        Button {
            state.showFrame.toggle()
        } label: {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 12 * s, weight: .bold))
                .padding(6 * s)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7 * s))
                .overlay(
                    RoundedRectangle(cornerRadius: 7 * s)
                        .stroke(Color.secondary.opacity(0.35))
                )
        }
        .buttonStyle(.plain)
        .help("Photo frame — set X / Y / W / H by hand")
        .popover(isPresented: $state.showFrame) {
            PhotoFrameEditor()
                .environmentObject(app)
                .padding()
        }
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
        app.photoFrame = app.effectiveFrame.scaled(by: factor, around: pivot)
        return true
    }
}

@MainActor
private final class PreviewState: ObservableObject {
    @Published var showFrame = false
    @Published var showGamma = false
    @Published var showScroll = false
    @Published var showZoom = false

    var mouse: CGPoint?
    var paneSize: CGSize = .zero
    var dragStart: PhotoFrame?
    var monitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
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
                Button("Reset") { app.photoFrame = nil }
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
                app.photoFrame = frame.clamped()
            }
        )
    }
}
