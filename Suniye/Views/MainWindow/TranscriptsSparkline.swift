import Charts
import SwiftUI

/// Words per day as a compact sparkline. Small and unlabelled on purpose — it
/// sits beside the headline to show the shape of the habit, not to be read off.
struct TranscriptsSparkline: View {
    let days: [DailyWordCount]

    private var peak: Int {
        days.map(\.words).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            chart
                .frame(width: 180, height: 40)

            Text(caption)
                .font(AppTypography.codeCaption)
                .foregroundStyle(MainWindowPalette.tertiaryText)
                .tracking(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words per day over the last \(days.count) days, peak \(peak)")
    }

    private var caption: String {
        "WORDS / DAY · \(days.count)D · PEAK \(peak)"
    }

    private var chart: some View {
        Chart {
            ForEach(days) { day in
                AreaMark(
                    x: .value("Day", day.dayKey),
                    y: .value("Words", day.words)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Day", day.dayKey),
                    y: .value("Words", day.words)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            // The most recent day carries the point: it is the one value the
            // reader actually looks for.
            if let latest = days.last, latest.words > 0 {
                PointMark(
                    x: .value("Day", latest.dayKey),
                    y: .value("Words", latest.words)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(24)
            }
        }
        .chartYScale(domain: 0...max(peak, 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
