import SwiftUI

/// Choosing a recogniser is a rare, expert action — the app ships with a good
/// default and keeps it current. So this page states what is running, and folds
/// the alternatives away behind one row rather than presenting a library the
/// user is expected to shop in.
struct SpeechModelPage: View {
    @Bindable var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOtherModels = false
    @State private var pendingDeleteModelID: ASRModelID?

    private var otherModels: [ASRModelCatalogEntry] {
        appState.availableASRModelEntries.filter { $0.id != appState.currentASRModelEntry.id }
    }

    /// A multi-gigabyte download cannot hide behind a disclosure: whenever an
    /// operation is running or has failed, the section opens itself.
    private var isOtherModelsExpanded: Binding<Bool> {
        Binding(
            get: {
                if let active = appState.activeASRModelOperationID, active != appState.currentASRModelEntry.id {
                    return true
                }
                return showsOtherModels
            },
            set: { showsOtherModels = $0 }
        )
    }

    var body: some View {
        DetailScrollContainer {
            header

            // Progress and failures stay at the top level, never inside the
            // collapsed section.
            if let banner = appState.asrModelBanner {
                InlineStatusBanner(
                    icon: banner.tone.icon,
                    tint: banner.tone.color,
                    title: banner.title,
                    detail: banner.detail,
                    progress: banner.progress
                )
            }

            activeModelCard

            if !otherModels.isEmpty {
                otherModelsSection
            }
        }
        .confirmationDialog(
            "Delete this model?",
            isPresented: Binding(
                get: { pendingDeleteModelID != nil },
                set: { if !$0 { pendingDeleteModelID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteModelID {
                    appState.deleteASRModel(pendingDeleteModelID)
                }
                pendingDeleteModelID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModelID = nil
            }
        } message: {
            Text("You will have to download it again to use it.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailPageTitle(title: "Speech Model")
            // The claim this page exists to make.
            Text("Recognition happens on this Mac. Audio is never uploaded.")
                .font(AppTypography.body)
                .foregroundStyle(MainWindowPalette.secondaryText)
        }
    }

    // MARK: - Active model

    private var activeModelCard: some View {
        let entry = appState.currentASRModelEntry

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.displayName)
                    .font(AppTypography.cardTitle)
                if appState.asrModelStatusNeedsAttention {
                    StatusPill(title: appState.modelStatusValue, tint: appState.modelStatusColor)
                }
                Spacer(minLength: 12)
            }

            HStack(alignment: .top, spacing: 28) {
                // Languages carries the longest value ("25 European languages"),
                // so it gets the width instead of wrapping to two lines while the
                // other two sit half empty.
                factColumn("Languages", entry.languageSummary, minWidth: 190)
                factColumn("Speed", entry.speedLabel)
                factColumn("On disk", diskText(for: entry))
            }

            if appState.modelPrimaryActionTitle != "Current" || !entry.isSystemManaged {
                CardDivider()

                HStack(spacing: 16) {
                    if appState.modelPrimaryActionTitle != "Current" {
                        Button(appState.modelPrimaryActionTitle) {
                            appState.performPrimaryASRAction(for: entry.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))
                    }

                    if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                        Button("Reveal in Finder") {
                            appState.openModelFolder(for: entry.id)
                        }
                        .buttonStyle(.link)
                        .font(AppTypography.body)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
        )
    }

    private func factColumn(_ label: String, _ value: String, minWidth: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(AppTypography.caption)
                .tracking(0.6)
                .foregroundStyle(MainWindowPalette.tertiaryText)
            Text(value)
                .font(AppTypography.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: minWidth, maxWidth: .infinity, alignment: .leading)
    }

    /// System models are owned by macOS, so there is no footprint to report.
    private func diskText(for entry: ASRModelCatalogEntry) -> String {
        entry.isSystemManaged ? "Built into macOS" : appState.asrModelInstalledSizeText(for: entry.id)
    }

    // MARK: - Other models

    private var otherModelsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showsOtherModels.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                        .rotationEffect(.degrees(isOtherModelsExpanded.wrappedValue ? 90 : 0))
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other models")
                            .font(AppTypography.bodyMedium)
                            .foregroundStyle(Color.primary)
                        // Driven by the catalogue, so it cannot go stale.
                        Text("Wider language coverage or a smaller download. Not recommended otherwise.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(MainWindowPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Text("\(otherModels.count)")
                        .font(AppTypography.codeCaption)
                        .foregroundStyle(MainWindowPalette.tertiaryText)
                        .padding(.top, 3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(pressedScale: 0.997))

            if isOtherModelsExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(otherModels) { entry in
                        CardDivider()
                        otherModelRow(entry)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius, style: .continuous)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOtherModelsExpanded.wrappedValue)
    }

    private func otherModelRow(_ entry: ASRModelCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.displayName)
                    .font(AppTypography.bodyMedium)
                StatusPill(
                    title: appState.asrModelStatusText(for: entry.id),
                    tint: appState.asrModelStatusColor(for: entry.id)
                )

                Spacer(minLength: 12)

                Button(appState.asrModelPrimaryActionTitle(for: entry.id)) {
                    appState.performPrimaryASRAction(for: entry.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!appState.asrModelCanPerformPrimaryAction(for: entry.id))

                if appState.asrModelSecondaryActionsEnabled(for: entry.id) {
                    ActionIconButton(
                        systemName: "trash",
                        accessibilityLabel: "Delete \(entry.displayName)",
                        tint: MainWindowPalette.tertiaryText,
                        hoverTint: MainWindowPalette.destructive
                    ) {
                        pendingDeleteModelID = entry.id
                    }
                }
            }

            Text(entry.description)
                .font(AppTypography.subheadline)
                .foregroundStyle(MainWindowPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(metaLine(for: entry))
                .font(AppTypography.caption)
                .foregroundStyle(MainWindowPalette.tertiaryText)

            if let progressLabel = appState.asrModelProgressLabel(for: entry.id) {
                VStack(alignment: .leading, spacing: 6) {
                    if appState.activeASRModelOperationID == entry.id, appState.phase == .downloadingModel {
                        ProgressView(value: appState.downloadProgress)
                            .progressViewStyle(.linear)
                    } else if appState.activeASRModelOperationID == entry.id, appState.phase == .loading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(progressLabel)
                        .font(AppTypography.caption)
                        .foregroundStyle(MainWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaLine(for entry: ASRModelCatalogEntry) -> String {
        [entry.languageSummary, entry.speedLabel, entry.qualityLabel, entry.sizeDisplayText]
            .joined(separator: " · ")
    }
}
