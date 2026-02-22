import AppKit
import SwiftUI

enum AppTypography {
    private static let preferredFamily = "Google Sans"

    static func ui(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        if NSFont(name: preferredFamily, size: size) != nil {
            return .custom(preferredFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: design)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum AppTheme {
    static let cardBackground = Color.gray.opacity(0.12)
    static let subtleBackground = Color.gray.opacity(0.08)
    static let border = Color.gray.opacity(0.22)
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
