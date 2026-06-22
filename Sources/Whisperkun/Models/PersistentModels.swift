import Foundation
import SwiftData
import WhisperkunCore

/// ユーザー辞書の項目（用語の置換）。
@Model
final class DictionaryEntry {
    var from: String
    var to: String
    var caseSensitive: Bool
    var createdAt: Date

    init(from: String, to: String, caseSensitive: Bool = true, createdAt: Date = .now) {
        self.from = from
        self.to = to
        self.caseSensitive = caseSensitive
        self.createdAt = createdAt
    }

    var rule: DictionaryRule {
        DictionaryRule(from: from, to: to, caseSensitive: caseSensitive)
    }
}

/// スニペット（`{{key}}` → 展開後テキスト）。
@Model
final class Snippet {
    var key: String
    var value: String
    var createdAt: Date

    init(key: String, value: String, createdAt: Date = .now) {
        self.key = key
        self.value = value
        self.createdAt = createdAt
    }
}

/// アプリ別ワークフロー。
@Model
final class Workflow {
    var name: String
    var bundleIDs: [String]
    var instructions: String?
    var localeID: String?
    var createdAt: Date

    init(name: String, bundleIDs: [String] = [], instructions: String? = nil, localeID: String? = nil, createdAt: Date = .now) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.instructions = instructions
        self.localeID = localeID
        self.createdAt = createdAt
    }

    var rule: WorkflowRule {
        WorkflowRule(name: name, bundleIDs: bundleIDs, instructions: instructions, localeID: localeID)
    }
}

/// 文字起こし履歴の1件。
@Model
final class TranscriptionRecord {
    var text: String
    var appBundleID: String?
    var createdAt: Date

    init(text: String, appBundleID: String? = nil, createdAt: Date = .now) {
        self.text = text
        self.appBundleID = appBundleID
        self.createdAt = createdAt
    }
}
