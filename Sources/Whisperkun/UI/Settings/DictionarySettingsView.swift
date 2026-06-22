import SwiftData
import SwiftUI

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DictionaryEntry.createdAt) private var entries: [DictionaryEntry]

    @State private var newFrom = ""
    @State private var newTo = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("認識結果の用語を置換します（誤認識の補正など）。")
                .font(.caption).foregroundStyle(.secondary)

            Table(entries) {
                TableColumn("変換元", value: \.from)
                TableColumn("変換先", value: \.to)
                TableColumn("大小区別") { entry in
                    Text(entry.caseSensitive ? "する" : "しない")
                }
                TableColumn("") { entry in
                    Button(role: .destructive) {
                        context.delete(entry)
                        try? context.save()
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("変換元", text: $newFrom)
                TextField("変換先", text: $newTo)
                Button("追加") { add() }
                    .disabled(newFrom.isEmpty)
            }
        }
        .padding()
    }

    private func add() {
        context.insert(DictionaryEntry(from: newFrom, to: newTo))
        try? context.save()
        newFrom = ""; newTo = ""
    }
}
