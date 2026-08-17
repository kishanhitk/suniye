import SwiftUI

/// A settings line: what it is, what it is set to, and a chevron saying it opens.
///
/// No card, no explainer underneath — the value carries the meaning, and the
/// detail that used to sit permanently on the page moves into whatever the row
/// opens. A second line appears only when the first cannot carry it.
struct DisclosureSettingRow: View {
    let title: String
    var secondLine: String?
    let value: String
    var isEnabled = true
    var action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.primary)
                    if let secondLine {
                        Text(secondLine)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Text(value)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .multilineTextAlignment(.trailing)

                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                }
            }
            .font(AppTypography.rowTitle)
            .padding(.vertical, 13)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && isEnabled ? MainWindowPalette.selectedFill.opacity(0.5) : .clear)
                    .padding(.horizontal, -6)
            )
        }
        .buttonStyle(PressableButtonStyle(pressedScale: 1))
        .disabled(!isEnabled || action == nil)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Group heading. Sentence case, not an uppercase mono label: one level of
/// hierarchy needs one weight, not a different typeface.
struct SettingsGroupHeading: View {
    let text: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(AppTypography.groupHeading)
                .foregroundStyle(Color.primary)
            if let note {
                Text(note)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hairline between rows, inset so it reads as a separator rather than a border.
struct RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(MainWindowPalette.divider)
            .frame(height: 1)
    }
}

/// A row whose control is a switch. The explanation that used to sit underneath
/// every toggle moves to an info tip, so the page stays a list of settings
/// rather than a wall of grey prose.
struct ToggleSettingRow: View {
    let title: String
    var info: String?
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            SettingRowLabel(title: title, info: info)

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
        }
        .font(AppTypography.rowTitle)
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A row that only reports a value — no chevron, because nothing opens.
struct ValueSettingRow: View {
    let title: String
    var info: String?
    let value: String
    var valueFont: Font = AppTypography.rowTitle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            SettingRowLabel(title: title, info: info)
            Spacer(minLength: 12)
            Text(value)
                .font(valueFont)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .font(AppTypography.rowTitle)
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
    }
}

/// A row whose control is a menu or any small inline control.
struct ControlSettingRow<Control: View>: View {
    let title: String
    var info: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            SettingRowLabel(title: title, info: info)
            Spacer(minLength: 12)
            control
        }
        .font(AppTypography.rowTitle)
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
    }
}

/// Title plus an optional info tip. The tip carries the sentence that used to be
/// a permanent second line, so it is available without being in the way.
struct SettingRowLabel: View {
    let title: String
    var info: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(Color.primary)
            if let info {
                Image(systemName: "info.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.tertiaryText)
                    .help(info)
                    .accessibilityLabel(info)
            }
        }
    }
}

/// Groups a page's rows: a heading, then hairline-separated rows.
struct SettingsGroup<Content: View>: View {
    let heading: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroupHeading(text: heading, note: note)
            VStack(spacing: 0) {
                content
            }
        }
    }
}


/// Motion for content that inserts into or leaves a settings list: banners,
/// warnings, rows that only exist in one state. These push everything below
/// them, so the reflow is what actually needs bridging — the transition is
/// deliberately just opacity, letting the container animate the layout.
enum SettingsMotion {
    static func curve(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    /// Opacity only, so it needs no reduced-motion variant: a cross-fade is
    /// already the gentle form.
    static let notice: AnyTransition = .opacity

    /// The page-level banner sits above everything and shoves the whole page
    /// down, so it also comes from the edge it pushes from.
    static func banner(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
}
