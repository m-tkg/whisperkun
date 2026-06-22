import SwiftData
import SwiftUI

struct SnippetsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Snippet.createdAt) private var snippets: [Snippet]

    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("テキスト中の {{キー}} を展開します。組み込み: {{DATE}} {{TIME}} {{DATETIME}}")
                .font(.caption).foregroundStyle(.secondary)

            Table(snippets) {
                TableColumn("キー") { snippet in Text("{{\(snippet.key)}}") }
                TableColumn("展開後", value: \.value)
                TableColumn("") { snippet in
                    Button(role: .destructive) {
                        context.delete(snippet)
                        try? context.save()
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("キー（例: sig）", text: $newKey)
                TextField("展開後テキスト", text: $newValue)
                Button("追加") { add() }
                    .disabled(newKey.isEmpty)
            }
        }
        .padding()
    }

    private func add() {
        context.insert(Snippet(key: newKey, value: newValue))
        try? context.save()
        newKey = ""; newValue = ""
    }
}
