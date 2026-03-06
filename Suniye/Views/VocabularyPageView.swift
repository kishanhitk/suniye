import SwiftUI

struct VocabularyPageView: View {
    @Bindable var appState: AppState
    @State private var newTerm = ""
    @State private var showComposer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeaderRow(title: "Dictionary", actionTitle: "Add new") {
                    showComposer.toggle()
                }

                HStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("All")
                            .font(AppTypography.ui(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.primaryText)
                        Rectangle()
                            .fill(AppTheme.primaryText)
                            .frame(width: 26, height: 2)
                    }
                    Spacer()
                }
                .padding(.top, 6)

                AppShellCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Flow speaks the way you speak.")
                            .font(AppTypography.serif(size: 50, weight: .regular))
                            .foregroundStyle(AppTheme.primaryText)

                        Text("Personal terms are injected into style polishing. Add names, acronyms, and domain language so dictation output stays on-brand.")
                            .font(AppTypography.ui(size: 23, weight: .medium))
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if !appState.llmVocabulary.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                                ForEach(Array(appState.llmVocabulary.prefix(8)), id: \.self) { term in
                                    TagChip(text: term)
                                }
                            }
                        }

                        Button("Add new word") {
                            showComposer = true
                        }
                        .buttonStyle(PrimaryDarkButtonStyle())
                    }
                    .padding(22)
                    .background(AppTheme.warmCardBackground)
                }

                if showComposer {
                    AppShellCard {
                        HStack(spacing: 10) {
                            TextField("Add personal term", text: $newTerm)
                                .font(AppTypography.ui(size: 15))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                        .fill(AppTheme.panelBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppLayout.chipCornerRadius, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1)
                                )

                            Button("Save") {
                                appState.addVocabularyTerm(newTerm)
                                newTerm = ""
                            }
                            .buttonStyle(PrimaryDarkButtonStyle())
                            .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Cancel") {
                                newTerm = ""
                                showComposer = false
                            }
                            .buttonStyle(SoftPillButtonStyle())
                        }
                        .padding(16)
                    }
                }

                if appState.llmVocabulary.isEmpty {
                    AppShellCard {
                        Text("No dictionary entries yet")
                            .font(AppTypography.ui(size: 16))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(20)
                    }
                } else {
                    DataTableCard {
                        ForEach(Array(appState.llmVocabulary.enumerated()), id: \.element) { index, term in
                            HStack(spacing: 14) {
                                Text(term)
                                    .font(AppTypography.ui(size: 20))
                                    .foregroundStyle(AppTheme.primaryText)

                                Spacer()

                                RowActionButton(title: "Remove", role: .destructive) {
                                    appState.removeVocabularyTerm(term)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if index < appState.llmVocabulary.count - 1 {
                                Divider().overlay(AppTheme.border)
                            }
                        }
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 980, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}
