import Foundation
import SwiftData
import whisperkunCore

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
