import Charts
import SwiftUI

/// Words per day as a compact sparkline. Small and unlabelled on purpose — it
/// sits beside the headline to show the shape of the habit, not to be read off.
struct TranscriptsSparkline: View {
    let days: [DailyWordCount]

    @State private var hoveredDayKey: String?

    private var peak: Int {
        days.map(\.words).max() ?? 0
    }

    private var hoveredDay: DailyWordCount? {
        hoveredDayKey.flatMap { key in days.first { $0.dayKey == key } }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            chart
                // Tall enough that the block matches the headline stack beside
                // it, so the two bottom edges line up.
                .frame(width: 180, height: 64)

            // The caption doubles as the readout. A floating tooltip over a
            // 64pt chart would overflow into the headline beside it; this reuses
            // space the layout has already committed to, so nothing shifts.
            Text(caption)
                .font(AppTypography.codeCaption)
                .foregroundStyle(hoveredDay == nil ? MainWindowPalette.tertiaryText : Color.primary)
                .tracking(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words per day over the last \(days.count) days, peak \(peak)")
    }

    private var caption: String {
        guard let hoveredDay else {
            return "WORDS / DAY · \(days.count)D · PEAK \(peak)"
        }
        let label = hoveredDay.date.map { Self.dayFormatter.string(from: $0).uppercased() } ?? hoveredDay.dayKey
        return "\(label) · \(hoveredDay.words) WORDS"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

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

            if let hoveredDay {
                RuleMark(x: .value("Day", hoveredDay.dayKey))
                    .foregroundStyle(MainWindowPalette.tertiaryText.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Day", hoveredDay.dayKey),
                    y: .value("Words", hoveredDay.words)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(44)
            }
        }
        .chartYScale(domain: 0...max(peak, 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            hoveredDayKey = dayKey(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hoveredDayKey = nil
                        }
                    }
            }
        }
    }

    /// The x scale is categorical, one band per day, so the hit test asks the
    /// chart which band the pointer is over rather than doing the maths here.
    private func dayKey(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let plotFrame = proxy.plotFrame else {
            return nil
        }
        return proxy.value(atX: location.x - geometry[plotFrame].origin.x, as: String.self)
    }
}
