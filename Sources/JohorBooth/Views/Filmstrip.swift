import AppKit
import SwiftUI

/// Horizontal filmstrip of the livefolder, under the big preview.
///
/// Click a thumbnail to load it into the preview, scroll sideways to walk the
/// folder, or hover one and press space for the macOS Quick Look panel.
struct Filmstrip: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var library: ImageLibrary
    @ObservedObject var thumbs: ThumbnailStore

    @StateObject private var state = StripState()
    @Environment(\.uiScale) private var s

    private var cellHeight: CGFloat { 74 * s }
    private var cellWidth: CGFloat { 108 * s }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6 * s) {
                    ForEach(library.files, id: \.self) { url in
                        ThumbCell(
                            url: url,
                            isCurrent: url == library.current,
                            width: cellWidth,
                            height: cellHeight,
                            thumbs: thumbs
                        )
                        .id(url)
                        .onTapGesture { library.select(url) }
                        .onHover { inside in
                            if inside {
                                state.hovered = url.path
                            } else if state.hovered == url.path {
                                state.hovered = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 6 * s)
                .padding(.vertical, 5 * s)
            }
            .onContinuousHover { phase in
                if case .ended = phase { state.hovered = nil }
            }
            .onChange(of: library.current) { _, new in
                guard let new else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .onChange(of: library.files.count) { _, _ in
                if let current = library.current {
                    proxy.scrollTo(current, anchor: .center)
                }
            }
        }
        .frame(height: cellHeight + 10 * s)
        .background(
            RoundedRectangle(cornerRadius: 10 * s)
                .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10 * s)
                .stroke(Color.secondary.opacity(0.25))
        )
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Space → Quick Look

    private func installKeyMonitor() {
        guard state.monitor == nil else { return }
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard event.keyCode == 49,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                      !isTyping,
                      !QuickLook.shared.isOpen,
                      let path = state.hovered,
                      let index = library.files.firstIndex(where: { $0.path == path })
                else { return event }
                QuickLook.shared.show(library.files, index: index)
                return nil
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
    var hovered: String?
    var monitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

private struct ThumbCell: View {
    let url: URL
    let isCurrent: Bool
    let width: CGFloat
    let height: CGFloat
    @ObservedObject var thumbs: ThumbnailStore
    @Environment(\.uiScale) private var s

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
        .opacity(isCurrent ? 1 : 0.85)
        .help(url.lastPathComponent)
        .onAppear { thumbs.load(url) }
    }
}
