import SwiftUI

/// Edits the summary templates. Changes stay drafts until Done.
struct MeetingTemplateEditor: View {
    let templates: MeetingTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [MeetingTemplate] = []
    @State private var saved: [MeetingTemplate] = []
    @State private var selectedID: String?
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Templates")
                .font(AppTypography.cardTitle)
            HStack(alignment: .top, spacing: 16) {
                templateList
                if let index = selectedIndex {
                    editor(for: index)
                } else {
                    Spacer()
                }
            }
            HStack {
                if let index = selectedIndex, let defaultSections = drafts[index].defaultSections {
                    Button("Reset to Default") {
                        drafts[index].sections = defaultSections
                    }
                    .disabled(drafts[index].sections == defaultSections)
                }
                Spacer()
                Button("Done") { save() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .task {
            saved = await templates.templates()
            drafts = saved
            selectedID = drafts.first?.id
        }
        .alert("Couldn’t save the templates", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var selectedIndex: Int? {
        drafts.firstIndex { $0.id == selectedID }
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(drafts) { template in
                    row(template)
                }
                Button("New Template") {
                    let template = MeetingTemplate(id: UUID().uuidString, name: "New template", sections: MeetingTemplate.general.sections)
                    drafts.append(template)
                    selectedID = template.id
                }
                .padding(.top, 8)
            }
        }
        .frame(width: 150, alignment: .topLeading)
    }

    private func row(_ template: MeetingTemplate) -> some View {
        let isSelected = template.id == selectedID
        return Text(template.name)
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { selectedID = template.id }
            .contextMenu {
                if !template.isBuiltIn {
                    Button("Delete Template") {
                        drafts.removeAll { $0.id == template.id }
                        if selectedID == template.id {
                            selectedID = drafts.first?.id
                        }
                    }
                }
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func editor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Name")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                TextField("Name", text: $drafts[index].name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .disabled(drafts[index].isBuiltIn)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Instructions for the summary")
                    .font(AppTypography.caption)
                    .foregroundStyle(MainWindowPalette.secondaryText)
                TextEditor(text: $drafts[index].sections)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
            }
        }
    }

    /// Done keeps the drafts; with no change it only closes.
    private func save() {
        guard drafts != saved else {
            dismiss()
            return
        }
        Task {
            do {
                try await templates.replace(with: drafts)
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
