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
                    gammaField
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

    /// Mouse-wheel zoom sensitivity, right under the zoom badge (icon only).
    private var gammaField: some View {
        NumberCommitField(
            icon: "slider.horizontal.3",
            suffix: "",
            value: Binding(
                get: { app.settings.zoomGamma },
                set: { app.settings.zoomGamma = $0 }
            )
        )
        .padding(.horizontal, 6 * s)
        .padding(.vertical, 3 * s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7 * s))
        .help("Mouse scroll zoom amount (Enter to apply)")
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
        guard !isTyping else { return false }
        guard let point = state.mouse, state.paneSize.width > 1 else { return false }
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

            Divider()

            // Zoom step (%) and mouse-scroll amount — icon only, Enter to commit.
            HStack(spacing: 12 * s) {
                NumberCommitField(
                    icon: "plus.magnifyingglass",
                    suffix: "%",
                    value: Binding(
                        get: { app.settings.zoomStep },
                        set: { app.settings.zoomStep = $0 }
                    )
                )
                .help("Zoom % per scroll step (Enter to apply)")

                NumberCommitField(
                    icon: "slider.horizontal.3",
                    suffix: "",
                    value: Binding(
                        get: { app.settings.zoomGamma },
                        set: { app.settings.zoomGamma = $0 }
                    )
                )
                .help("Mouse scroll zoom amount (Enter to apply)")
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
