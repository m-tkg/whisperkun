import AppKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TranscriptionRecord.createdAt, order: .reverse) private var records: [TranscriptionRecord]

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("文字起こし履歴").font(.headline)
                Spacer()
                Button("すべて削除", role: .destructive) { clearAll() }
                    .disabled(records.isEmpty)
            }

            if records.isEmpty {
                Spacer()
                Text("まだ履歴はありません").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.text).lineLimit(3)
                            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button("コピー") { copy(record.text) }
                            Button("削除", role: .destructive) {
                                context.delete(record); try? context.save()
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .padding()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(records[index]) }
        try? context.save()
    }

    private func clearAll() {
        for record in records { context.delete(record) }
        try? context.save()
    }
}
