import SwiftUI
import AppKit

/// Big rounded panel button (layout.psd); `highlighted` = green (new image waiting).
struct PanelButtonStyle: ButtonStyle {
    var highlighted = false
    var prominent = false
    var destructive = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(
            configuration: configuration,
            highlighted: highlighted,
            prominent: prominent,
            destructive: destructive,
            compact: compact
        )
    }
}

/// UI scale from the window size: 100% at 1500×950 and up, down to 70% for small windows.
enum UIScale {
    static func factor(for size: CGSize) -> CGFloat {
        min(1, max(0.7, min(size.width / 1500, size.height / 950)))
    }
}

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

private struct PanelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let highlighted: Bool
    let prominent: Bool
    let destructive: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.uiScale) private var s

    var fill: Color {
        if destructive { return .red }
        if highlighted { return .green }
        if prominent { return .accentColor }
        return Color(nsColor: .controlColor)
    }

    var body: some View {
        configuration.label
            .font(.system(size: (compact ? 13 : 15) * s, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: (compact ? 30 : 40) * s)
            .foregroundStyle(highlighted || prominent || destructive ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: (compact ? 7 : 10) * s).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: (compact ? 7 : 10) * s).stroke(Color.secondary.opacity(0.35)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: (compact ? 7 : 10) * s))
    }
}

/// The value line under a panel button (folder, overlay name, file name).
struct InfoLine: View {
    let text: String
    @Environment(\.uiScale) private var s
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .help(text)
    }
}

/// X/Y/W/H editor for a placement rectangle.
struct AreaEditor: View {
    let title: String
    @Binding var area: AreaRect
    let defaultArea: AreaRect

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    field("X", $area.x)
                    field("Y", $area.y)
                }
                GridRow {
                    field("W", $area.w)
                    field("H", $area.h)
                }
            }
            Button("Reset to default") { area = defaultArea }
        }
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).frame(width: 16, alignment: .leading)
            TextField(label, value: value, format: .number.grouping(.never).precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Stepper("", value: value, step: 1)
                .labelsHidden()
        }
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 10, height: 10)
    }
}

/// View-local state without the `@State` macro, so the app builds with the
/// Command Line Tools alone (they lack the SwiftUI macro plugin). Use with @StateObject.
final class Box<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// "Show photo for [5] sec" — the same 2nd-screen countdown setting in PRINT and SCREEN.
struct SecondsField: View {
    @Binding var seconds: Int
    var label = "Show photo for"

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            TextField("", value: $seconds, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 50)
            Stepper("", value: $seconds, in: 1...60)
                .labelsHidden()
            Text("sec")
        }
    }
}

/// A small numeric field that only commits on Enter — type freely, the value
/// (and the field) stays put until you press Return. Icon only, no text label.
struct NumberCommitField: View {
    let icon: String
    let suffix: String
    @Binding var value: Double
    @Environment(\.uiScale) private var s
    @StateObject private var text = Box("")

    private var currentValue: Double { value }

    var body: some View {
        HStack(spacing: 4 * s) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.secondary)
            }
            TextField("", text: $text.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11 * s))
                .multilineTextAlignment(.center)
                .frame(width: 56 * s)
                .onSubmit { commit() }
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text.value = Self.format(value) }
        .onChange(of: currentValue) { _, v in text.value = Self.format(v) }
    }

    private func commit() {
        let cleaned = text.value
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        if let d = Double(cleaned), d > 0 {
            value = d
        }
        text.value = Self.format(value)
    }

    private static func format(_ v: Double) -> String {
        var out = String(format: "%.2f", v)
        while out.contains("."), out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }
}

/// A small popup to enter one number — OK applies (or press Enter), Cancel dismisses.
struct NumberPopup: View {
    let icon: String
    let suffix: String
    let initialValue: Double
    var onApply: (Double) -> Void
    @Binding var isPresented: Bool
    @Environment(\.uiScale) private var s
    @StateObject private var text = Box("")
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10 * s) {
            HStack(spacing: 6 * s) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 14 * s))
                        .foregroundStyle(.secondary)
                }
                TextField("", text: $text.value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14 * s))
                    .multilineTextAlignment(.center)
                    .frame(width: 90 * s)
                    .focused($focused)
                    .onSubmit { apply() }
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8 * s) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12 * s)
        .onAppear {
            text.value = Self.format(initialValue)
            DispatchQueue.main.async { focused = true }
        }
    }

    private func apply() {
        let cleaned = text.value
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        if let d = Double(cleaned), d > 0 {
            onApply(d)
        }
        isPresented = false
    }

    private static func format(_ v: Double) -> String {
        var out = String(format: "%.2f", v)
        while out.contains("."), out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out
    }
}

/// Takes only right-clicks; left clicks fall through to the view underneath.
struct RightClickOnly: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> RView {
        let v = RView()
        v.action = action
        return v
    }

    func updateNSView(_ nsView: RView, context: Context) { nsView.action = action }

    final class RView: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp: return super.hitTest(point)
            default: return nil
            }
        }
        override func rightMouseDown(with event: NSEvent) { action() }
    }
}
