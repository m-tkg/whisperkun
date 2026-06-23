import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DictionaryEntry.createdAt) private var entries: [DictionaryEntry]

    @State private var newFrom = ""
    @State private var newTo = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("認識結果の用語を置換します（誤認識の補正など）。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("エクスポート") { exportDictionary() }
                    .disabled(entries.isEmpty)
                Button("インポート") { importDictionary() }
            }

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

    // MARK: - エクスポート / インポート

    /// 書き出し/読み込みに使う辞書ファイルの形式。
    private struct DictionaryFile: Codable {
        struct Entry: Codable {
            var from: String
            var to: String
            var caseSensitive: Bool
        }
        var entries: [Entry]
    }

    private func exportDictionary() {
        let file = DictionaryFile(entries: entries.map {
            .init(from: $0.from, to: $0.to, caseSensitive: $0.caseSensitive)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(file) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "whisperkun-dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DictionaryFile.self, from: data) else {
            showImportError()
            return
        }

        // From をキーに upsert マージ: 同じ From は上書き、無いものは追加、既存はそのまま残す。
        let existing = (try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? []
        var byFrom: [String: DictionaryEntry] = [:]
        for entry in existing { byFrom[entry.from] = entry }

        for imported in file.entries where !imported.from.isEmpty {
            if let entry = byFrom[imported.from] {
                entry.to = imported.to
                entry.caseSensitive = imported.caseSensitive
            } else {
                let entry = DictionaryEntry(from: imported.from, to: imported.to, caseSensitive: imported.caseSensitive)
                context.insert(entry)
                byFrom[imported.from] = entry
            }
        }
        try? context.save()
    }

    private func showImportError() {
        let alert = NSAlert()
        alert.messageText = String(localized: "インポートに失敗しました")
        alert.informativeText = String(localized: "ファイルの読み込みまたは解析に失敗しました。")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
