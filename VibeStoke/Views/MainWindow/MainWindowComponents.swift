import SwiftUI

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AttentionBanner: View {
    let items: [AttentionItem]
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

struct RecentActivityRow: View {
    let result: RecentResult
    let onCopy: () -> Void
    let onDelete: () -> Void

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(Self.timestampFormatter.string(from: result.createdAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                if result.wasLLMPolished {
                    Label("LLM", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy") {
                    onCopy()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Copy") {
                onCopy()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}
