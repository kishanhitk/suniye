import AppKit
import SwiftUI

enum AppTypography {
    private static let preferredFamily = "Google Sans"
    private static func scaledSize(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<15:
            return size
        case 15..<21:
            return size * 0.9
        case 21..<33:
            return size * 0.74
        default:
            return size * 0.58
        }
    }

    static func ui(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let adjustedSize = scaledSize(size)
        if NSFont(name: preferredFamily, size: adjustedSize) != nil {
            return .custom(preferredFamily, size: adjustedSize).weight(weight)
        }
        return .system(size: adjustedSize, weight: weight, design: design)
    }

    static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaledSize(size), weight: weight, design: .serif)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaledSize(size), weight: weight, design: .monospaced)
    }
}

enum AppTheme {
    static let windowBackground = Color(red: 0.93, green: 0.93, blue: 0.92)
    static let shellBackground = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.96)
    static let cardBackground = Color(red: 0.97, green: 0.97, blue: 0.96)
    static let warmCardBackground = Color(red: 0.94, green: 0.94, blue: 0.93)
    static let subtleBackground = Color(red: 0.92, green: 0.92, blue: 0.90)
    static let border = Color.black.opacity(0.08)
    static let primaryText = Color.black.opacity(0.87)
    static let secondaryText = Color.black.opacity(0.56)
    static let ctaFill = Color.black.opacity(0.9)
}

enum AppLayout {
    static let windowCornerRadius: CGFloat = 20
    static let panelCornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 12
    static let chipCornerRadius: CGFloat = 10
}

struct PrimaryDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.ui(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.9 : 1.0))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .fill(AppTheme.ctaFill.opacity(configuration.isPressed ? 0.82 : 1.0))
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct SoftPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.ui(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .fill(AppTheme.subtleBackground.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
    }
}

func formatByteCount(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func formatDayHeader(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM d, yyyy"
    return formatter.string(from: date).uppercased()
}
