import AppKit
import SwiftUI

struct StylePageStatusPill: View {
    let text: String
    let isPositive: Bool

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(isPositive ? .green : MainWindowPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isPositive ? Color.green.opacity(0.1) : MainWindowPalette.selectedFill)
            )
    }
}

struct StylePageProviderStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

struct StylePageProviderTagBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.caption)
            .foregroundStyle(MainWindowPalette.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(MainWindowPalette.selectedFill.opacity(0.7))
            )
    }
}

struct StylePageRadioIndicator: View {
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(indicatorColor, lineWidth: 1.3)

            if isSelected {
                Circle()
                    .fill(indicatorColor)
                    .padding(4)
            }
        }
        .frame(width: 14, height: 14)
    }

    private var indicatorColor: Color {
        if isSelected {
            return .accentColor
        }
        return isEnabled ? MainWindowPalette.tertiaryText : MainWindowPalette.divider
    }
}

struct StylePageProviderIcon: View {
    let provider: MagicFormatProvider

    var body: some View {
        if provider == .appleFoundationModels && symbolName == "apple.intelligence" {
            Image(systemName: symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 30, height: 30)
                .background(iconBackground(MainWindowPalette.selectedFill.opacity(0.75)))
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(iconBackground(color.opacity(0.12)))
        }
    }

    private func iconBackground(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
    }

    private var symbolName: String {
        switch provider {
        case .automatic:
            return "wand.and.stars"
        case .appleFoundationModels:
            return NSImage(systemSymbolName: "apple.intelligence", accessibilityDescription: nil) == nil
                ? "sparkles"
                : "apple.intelligence"
        case .localGemma:
            return "cpu"
        case .openAICompatible:
            return "key.horizontal"
        }
    }

    private var color: Color {
        switch provider {
        case .automatic:
            return .purple
        case .appleFoundationModels:
            return .blue
        case .localGemma:
            return .green
        case .openAICompatible:
            return .orange
        }
    }
}

struct StylePageVocabularyTag: View {
    let term: String
    var isAutoLearned = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isAutoLearned {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(MainWindowPalette.secondaryText)
                    .help("Learned from your edits")
            }

            Text(term)
                .font(AppTypography.callout)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(MainWindowPalette.selectedFill)
        )
        .overlay(
            Capsule()
                .stroke(MainWindowPalette.cardStroke, lineWidth: 0.5)
        )
    }
}
