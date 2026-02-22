import SwiftUI

struct VocabularyPageView: View {
    @Bindable var appState: AppState
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vocabulary")
                .font(AppTypography.ui(size: 32, weight: .bold))

            HStack(spacing: 10) {
                TextField("Add glossary term", text: $newTerm)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    appState.addVocabularyTerm(newTerm)
                    newTerm = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("These terms are included as keyword hints for LLM polishing.")
                .font(AppTypography.ui(size: 12))
                .foregroundStyle(.secondary)

            if appState.llmVocabulary.isEmpty {
                Spacer()
                Text("No glossary terms")
                    .font(AppTypography.ui(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(appState.llmVocabulary, id: \.self) { term in
                    HStack {
                        Text(term)
                            .font(AppTypography.ui(size: 13))
                        Spacer()
                        Button("Remove", role: .destructive) {
                            appState.removeVocabularyTerm(term)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(22)
    }
}
