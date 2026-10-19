import SwiftUI
import AppKit

/// Big rounded panel button (layout.psd); `highlighted` = green (new image waiting).
struct PanelButtonStyle: ButtonStyle {
    var highlighted = false
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(configuration: configuration, highlighted: highlighted, prominent: prominent)
    }
}

private struct PanelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let highlighted: Bool
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var fill: Color {
        if highlighted { return .green }
        if prominent { return .accentColor }
        return Color(nsColor: .controlColor)
    }

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(highlighted || prominent ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.35)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The value line under a panel button (folder, overlay name, file name).
struct InfoLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
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
