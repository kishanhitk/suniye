import AppKit
import SwiftUI

/// Shows the call card at the top right of the screen, over other apps and
/// full-screen calls, without taking focus.
@MainActor
final class MeetingCallCardPresenter {
    private static let margin: CGFloat = 12
    /// The card enters from the right edge and leaves along it.
    private static let travel: CGFloat = 16
    private static let enterDuration: TimeInterval = 0.25
    private static let exitDuration: TimeInterval = 0.18
    private static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    private let meetings: MeetingCoordinator
    private let openSettings: () -> Void
    private var panel: NSPanel?

    init(meetings: MeetingCoordinator, openSettings: @escaping () -> Void) {
        self.meetings = meetings
        self.openSettings = openSettings
    }

    func show(_ card: MeetingCallCard?) {
        dismiss()
        guard let card else { return }
        let hosting = NSHostingController(rootView: MeetingCallCardView(card: card, meetings: meetings, openSettings: openSettings))
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hosting.view.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.view.fittingSize)

        guard let screen = NSScreen.main else { return }
        let resting = NSPoint(
            x: screen.visibleFrame.maxX - panel.frame.width - Self.margin,
            y: screen.visibleFrame.maxY - panel.frame.height - Self.margin
        )
        panel.setFrameOrigin(NSPoint(x: resting.x + travel, y: resting.y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.enterDuration
            context.timingFunction = Self.easeOut
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(resting)
        }
    }

    private func dismiss() {
        guard let panel else { return }
        self.panel = nil
        let exit = NSPoint(x: panel.frame.origin.x + travel, y: panel.frame.origin.y)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.exitDuration
            context.timingFunction = Self.easeOut
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(exit)
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    /// Reduce Motion keeps the fade and drops the travel.
    private var travel: CGFloat {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.travel
    }
}

struct MeetingCallCardView: View {
    let card: MeetingCallCard
    let meetings: MeetingCoordinator
    let openSettings: () -> Void

    var body: some View {
        Group {
            switch card {
            case let .offer(app):
                offer(app)
            case let .startedAutomatically(app, cancelEndsAt):
                started(app, cancelEndsAt: cancelEndsAt)
            case let .callEnded(app, silent, _, stopsAt):
                ended(app, silent: silent, stopsAt: stopsAt)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func offer(_ app: MeetingCallApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AppGlyph()
                Heading(title: "Record this \(app.callName)?", detail: "\(app.name) is using the microphone.")
                Spacer(minLength: 0)
                Menu {
                    Button("Never Ask for \(app.name)") { meetings.neverAsk(for: app) }
                    Divider()
                    Button("Meeting Settings…", action: openSettings)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
            }
            HStack(spacing: 8) {
                Button {
                    Task { await meetings.recordOfferedCall() }
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                Button("Not Now") { meetings.declineOffer() }
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle)
        }
        .frame(width: 328, alignment: .leading)
    }

    private func started(_ app: MeetingCallApp, cancelEndsAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppGlyph()
                Text("Recording \(app.callName)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button("Cancel") {
                    Task { await meetings.cancelAutomaticRecording() }
                }
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle)
            }
            CancelTrack(endsAt: cancelEndsAt)
                .accessibilityLabel("Time left to cancel")
        }
        .frame(width: 272, alignment: .leading)
    }

    private func ended(_ app: MeetingCallApp, silent: Bool, stopsAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AppGlyph()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(stopsAt.timeIntervalSince(context.date).rounded(.up)))
                    Heading(
                        title: silent ? "No sound from \(app.name)" : "\(app.name) left the call",
                        detail: "Recording stops in \(seconds) s."
                    )
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("Stop Now") {
                    Task { await meetings.stopEndedCall() }
                }
                .buttonStyle(.borderedProminent)
                Button("Keep Recording") { meetings.keepRecording() }
            }
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle)
        }
        .frame(width: 328, alignment: .leading)
    }
}

/// The app icon, as in the main window's sidebar.
private struct AppGlyph: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}

private struct Heading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Empties at the rate of the time left to cancel.
private struct CancelTrack: View {
    let endsAt: Date
    @State private var fraction: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: proxy.size.width * fraction)
                }
        }
        .frame(height: 2)
        .onAppear {
            withAnimation(.linear(duration: max(0, endsAt.timeIntervalSinceNow))) {
                fraction = 0
            }
        }
    }
}
