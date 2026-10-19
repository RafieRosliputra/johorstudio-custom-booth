import SwiftUI
import AppKit

/// Big rounded panel button (layout.psd); `highlighted` = green (new image waiting).
struct PanelButtonStyle: ButtonStyle {
    var highlighted = false
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(configuration: configuration, highlighted: highlighted, prominent: prominent, destructive: destructive)
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
            .font(.system(size: 15 * s, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 40 * s)
            .foregroundStyle(highlighted || prominent || destructive ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 10 * s).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10 * s).stroke(Color.secondary.opacity(0.35)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 10 * s))
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
