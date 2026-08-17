import Charts
import SwiftUI

/// Words dictated per day. A total tells you nothing about whether the habit is
/// forming; fourteen bars do. Swift Charts ships with the platform (macOS 13+),
/// so this costs no dependency.
struct DashboardActivityChart: View {
    let days: [DailyWordCount]

    private var busiestDay: Int {
        days.map(\.words).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Last \(days.count) days")
                    .font(AppTypography.subheadlineSemibold)
                Spacer(minLength: 8)
                Text("\(days.reduce(0) { $0 + $1.words }.abbreviatedString) words")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
            }

            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.dayKey),
                    y: .value("Words", day.words),
                    width: .ratio(0.62)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .foregroundStyle(Color.accentColor.opacity(day.words == 0 ? 0.18 : 0.85))
                .accessibilityLabel(day.accessibilityDateLabel)
                .accessibilityValue("\(day.words) words")
            }
            // A flat run of zeroes would otherwise scale to fill the plot and
            // read as activity; pin the domain so empty days stay empty.
            .chartYScale(domain: 0...max(busiestDay, 1))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: axisDayKeys) { value in
                    if let key = value.as(String.self) {
                        AxisValueLabel {
                            Text(DailyWordCount(dayKey: key, words: 0).shortDayLabel)
                                .font(AppTypography.caption)
                                .foregroundStyle(MainWindowPalette.tertiaryText)
                        }
                    }
                }
            }
            .frame(height: 88)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppMetrics.metricPanelCornerRadius, style: .continuous)
                .fill(MainWindowPalette.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.metricPanelCornerRadius, style: .continuous)
                .strokeBorder(MainWindowPalette.cardStroke, lineWidth: 1)
        )
    }

    /// First, middle and last day only — fourteen labels would be unreadable at
    /// this width, and the shape of the bars is the point.
    private var axisDayKeys: [String] {
        guard days.count > 2 else {
            return days.map(\.dayKey)
        }
        return [days[0].dayKey, days[days.count / 2].dayKey, days[days.count - 1].dayKey]
    }
}

extension DailyWordCount {
    /// "6 Aug" — short enough for three axis labels at sidebar-constrained widths.
    var shortDayLabel: String {
        guard let date else {
            return ""
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    var accessibilityDateLabel: String {
        guard let date else {
            return dayKey
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
