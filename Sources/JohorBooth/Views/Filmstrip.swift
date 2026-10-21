import AppKit
import SwiftUI

/// Horizontal filmstrip of the livefolder, under the big preview.
///
/// Click a thumbnail to load it into the preview (no auto-centring), drag or
/// scroll the strip sideways, hover one and press space for Quick Look, or use
/// the ‹ › chevrons / arrow keys to step and snap the selection to the centre.
struct Filmstrip: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: ImageLibrary
    @ObservedObject var thumbs: ThumbnailStore

    @StateObject private var state = StripState()
    @Environment(\.uiScale) private var s

    private var cellHeight: CGFloat { 118 * s }
    private var cellWidth: CGFloat { 177 * s }
    private var gap: CGFloat { 6 * s }
    private var edgePad: CGFloat { 6 * s }

    private var contentWidth: CGFloat {
        let n = library.files.count
        guard n > 0 else { return 0 }
        return edgePad * 2 + CGFloat(n) * cellWidth + CGFloat(n - 1) * gap
    }

    private var maxOffset: CGFloat { max(0, contentWidth - state.viewport) }

    var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", enabled: library.canPrev, glow: glowLeft) { snap(-1) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(library.files, id: \.self) { url in
                            ThumbCell(
                                url: url,
                                isCurrent: url == library.current,
                                width: cellWidth,
                                height: cellHeight,
                                thumbs: thumbs
                            )
                            .onTapGesture { library.select(url) }
                            .onTapGesture(count: 2) { reveal(url) }
                            .onHover { inside in
                                if inside {
                                    state.hovered = url.path
                                } else if state.hovered == url.path {
                                    state.hovered = nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, edgePad)
                    .offset(x: -state.offsetX)
                }
                .frame(width: geo.size.width, height: cellHeight + edgePad * 2, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        state.stripHover = true
                    case .ended:
                        state.stripHover = false
                        state.hovered = nil
                    }
                }
                .gesture(dragGesture)
                .onAppear {
                    state.viewport = geo.size.width
                    installScrollMonitor()
                }
                .onChange(of: geo.size) { _, size in
                    state.viewport = size.width
                    state.offsetX = clampedOffset(state.offsetX)
                }
                .onChange(of: library.files.count) { _, _ in
                    state.offsetX = clampedOffset(state.offsetX)
                }
            }
            chevron("chevron.right", enabled: library.canNext, glow: glowRight) { snap(+1) }
        }
        .frame(height: cellHeight + edgePad * 2)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor(); removeScrollMonitor() }
    }

    // MARK: - Position / snap

    private func leadingX(_ i: Int) -> CGFloat {
        edgePad + CGFloat(i) * (cellWidth + gap)
    }

    private func centerOffset(_ i: Int) -> CGFloat {
        clampedOffset(leadingX(i) + cellWidth / 2 - state.viewport / 2)
    }

    private func clampedOffset(_ x: CGFloat) -> CGFloat {
        max(0, min(x, maxOffset))
    }

    /// Selected photo is entirely off-screen to the left → light the left chevron.
    private var glowLeft: Bool {
        guard let i = library.currentIndex else { return false }
        return leadingX(i) + cellWidth < state.offsetX - 0.5
    }

    private var glowRight: Bool {
        guard let i = library.currentIndex else { return false }
        return leadingX(i) > state.offsetX + state.viewport + 0.5
    }

    /// Step the selection and snap it to the centre (chevrons / arrow keys).
    private func snap(_ delta: Int) {
        if delta < 0 { library.prev() } else { library.next() }
        guard let i = library.currentIndex else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            state.offsetX = centerOffset(i)
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if state.dragStart == nil { state.dragStart = state.offsetX }
                state.offsetX = clampedOffset((state.dragStart ?? 0) - value.translation.width)
            }
            .onEnded { _ in state.dragStart = nil }
    }

    // MARK: - Scroll wheel

    private func installScrollMonitor() {
        guard state.scrollMonitor == nil else { return }
        state.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard state.stripHover, !isTyping else { return event }
                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                let delta = abs(dx) > abs(dy) ? dx : dy
                guard delta != 0 else { return event }
                state.offsetX = clampedOffset(state.offsetX - delta)
                return nil
            }
        }
    }

    private func removeScrollMonitor() {
        if let monitor = state.scrollMonitor {
            NSEvent.removeMonitor(monitor)
            state.scrollMonitor = nil
        }
    }

    /// Big white ‹ › at each end — step + snap to centre, like the mockup.
    private func chevron(_ name: String, enabled: Bool, glow: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 26 * s, weight: .bold))
                .foregroundStyle(enabled ? (glow ? Color.yellow : Color.white) : Color.white.opacity(0.25))
                .shadow(color: glow ? Color.yellow.opacity(0.9) : .clear, radius: 5)
                .frame(width: 40 * s)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .background(Color.black.opacity(0.45))
        .help(name == "chevron.left" ? "Previous photo" : "Next photo")
    }

    // MARK: - Keys: ← → step, space = Quick Look

    private func installKeyMonitor() {
        guard state.monitor == nil else { return }
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard !isTyping else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                switch event.keyCode {
                case 49: // space
                    guard mods.isEmpty,
                          !QuickLook.shared.isOpen,
                          let path = state.hovered,
                          let index = library.files.firstIndex(where: { $0.path == path })
                    else { return event }
                    QuickLook.shared.show(app.preview.quickLookURLs(for: library.files), index: index)
                    return nil
                case 123: // left arrow
                    guard mods.isEmpty else { return event }
                    snap(-1)
                    return nil
                case 124: // right arrow
                    guard mods.isEmpty else { return event }
                    snap(+1)
                    return nil
                default:
                    return event
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = state.monitor {
            NSEvent.removeMonitor(monitor)
            state.monitor = nil
        }
    }

    /// Don't steal space from a text field (the print count box).
    private var isTyping: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }
}

@MainActor
private final class StripState: ObservableObject {
    @Published var offsetX: CGFloat = 0
    var viewport: CGFloat = 0
    var hovered: String?
    var stripHover = false
    var dragStart: CGFloat?
    var monitor: Any?
    var scrollMonitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }
}

private struct ThumbCell: View {
    let url: URL
    let isCurrent: Bool
    let width: CGFloat
    let height: CGFloat
    @ObservedObject var thumbs: ThumbnailStore
    @Environment(\.uiScale) private var s

    private var caption: String {
        let base = url.deletingPathExtension().lastPathComponent
        return base.count > 5 ? "…" + String(base.suffix(5)) : base
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6 * s)
                .fill(Color.black.opacity(0.55))
            if let image = thumbs.image(for: url) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(1)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6 * s))
        .overlay(
            RoundedRectangle(cornerRadius: 6 * s)
                .strokeBorder(
                    isCurrent ? Color.accentColor : Color.white.opacity(0.12),
                    lineWidth: isCurrent ? 2.5 : 1
                )
        )
        .overlay(alignment: .bottom) {
            Text(caption)
                .font(.system(size: 10 * s, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 4 * s)
                .padding(.vertical, 2 * s)
                .background(Color.black.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 3 * s))
                .padding(2 * s)
        }
        .opacity(isCurrent ? 1 : 0.85)
        .help(url.lastPathComponent)
        .onAppear { thumbs.load(url) }
    }
}
