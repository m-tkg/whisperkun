import SwiftData
import SwiftUI

struct WorkflowsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workflow.createdAt) private var workflows: [Workflow]

    @State private var showingEditor = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("前面アプリに応じて整形プロンプトや言語を切り替えます。対象アプリ未指定はすべてに適用（既定）。")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach(workflows) { workflow in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workflow.name).font(.headline)
                        Text(workflow.bundleIDs.isEmpty ? "すべてのアプリ（既定）" : workflow.bundleIDs.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let instructions = workflow.instructions, !instructions.isEmpty {
                            Text(instructions).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }

            Button("ワークフローを追加") { showingEditor = true }
        }
        .padding()
        .sheet(isPresented: $showingEditor) {
            WorkflowEditorView { name, bundleIDs, instructions, localeID in
                context.insert(Workflow(name: name, bundleIDs: bundleIDs, instructions: instructions, localeID: localeID))
                try? context.save()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(workflows[index]) }
        try? context.save()
    }
}

/// 新規ワークフロー入力シート。
private struct WorkflowEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (_ name: String, _ bundleIDs: [String], _ instructions: String?, _ localeID: String?) -> Void

    @State private var name = ""
    @State private var bundleIDsText = ""
    @State private var instructions = ""
    @State private var localeID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ワークフローを追加").font(.headline)
            Form {
                TextField("名前", text: $name)
                TextField("対象アプリ bundle ID（カンマ区切り・空でall）", text: $bundleIDsText)
                TextField("言語コード（例: en-US・空で既定）", text: $localeID)
                VStack(alignment: .leading) {
                    Text("AI整形の指示（空で既定）")
                    TextEditor(text: $instructions).frame(height: 80).border(.quaternary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    let bundleIDs = bundleIDsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    onSave(
                        name.isEmpty ? "新しいワークフロー" : name,
                        bundleIDs,
                        instructions.isEmpty ? nil : instructions,
                        localeID.isEmpty ? nil : localeID
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
    }
}
