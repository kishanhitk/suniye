import SwiftUI

/// Edits the summary templates. Changes stay drafts until Save.
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
                if let index = selectedIndex, let defaultSections = drafts[index].defaultSections, drafts[index].sections != defaultSections {
                    Button("Restore default") {
                        drafts[index].sections = defaultSections
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(drafts == saved)
            }
        }
        .padding(20)
        .frame(width: 620, height: 460)
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
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                ForEach(drafts) { template in
                    Text(template.name).tag(template.id)
                }
            }
            .listStyle(.bordered)
            HStack(spacing: 0) {
                Button {
                    let template = MeetingTemplate(id: UUID().uuidString, name: "New template", sections: MeetingTemplate.general.sections)
                    drafts.append(template)
                    selectedID = template.id
                } label: {
                    Image(systemName: "plus").frame(width: 20, height: 20)
                }
                .help("Add a template")
                Button {
                    drafts.removeAll { $0.id == selectedID }
                    selectedID = drafts.first?.id
                } label: {
                    Image(systemName: "minus").frame(width: 20, height: 20)
                }
                .help("Delete the template")
                .disabled(selectedIndex.map { drafts[$0].isBuiltIn } ?? true)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .frame(width: 170)
    }

    private func editor(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(AppTypography.bodyMedium)
            TextField("Name", text: $drafts[index].name)
                .disabled(drafts[index].isBuiltIn)
            Text("Instructions")
                .font(AppTypography.bodyMedium)
                .padding(.top, 4)
            TextEditor(text: $drafts[index].sections)
                .font(AppTypography.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MainWindowPalette.editorBackground)
                )
        }
    }

    private func save() {
        let removed = saved.filter { old in !drafts.contains { $0.id == old.id } }
        let changed = drafts.filter { !saved.contains($0) }
        Task {
            do {
                for template in removed {
                    try await templates.delete(id: template.id)
                }
                for template in changed {
                    try await templates.save(template)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
