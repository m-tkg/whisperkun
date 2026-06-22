import FoundationModels
import Foundation

/// Foundation Models（オンデバイスLLM）による文字起こしテキストの整形を担う。
///
/// 既定では「意味を変えずに整える」軽整形を行う。モデルが利用不可な端末・状態では
/// 生テキストへフォールバックし、入力フローを止めない。
@MainActor
final class AIService {
    /// 既定の軽整形プロンプト。フィラー除去・句読点補完など、意味を変えない範囲に限定する。
    static let defaultFormattingInstructions = """
    あなたは音声入力テキストの整形アシスタントです。
    入力された音声認識結果を、意味を一切変えずに自然な文章へ整えてください。
    - 「えー」「あのー」「えっと」などのフィラーを除去する
    - 句読点を適切に補う
    - 明らかな重複や言い直しのみ最小限に整理する
    要約・翻訳・情報の追加は禁止です。整形後の本文だけを出力してください。
    """

    /// オンデバイスモデルが現在利用可能か。
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// 録音開始時に用意しておくセッション。確定後の整形レイテンシを下げるため、
    /// 発話中にモデル読み込み（prewarm）を済ませておく。
    private var preparedSession: LanguageModelSession?

    /// 利用不可の理由を日本語で返す（UI表示用）。利用可能なら nil。
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "この端末は Apple Intelligence 非対応です"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence が有効になっていません"
            case .modelNotReady: return "モデルの準備中です"
            @unknown default: return "オンデバイスモデルを利用できません"
            }
        @unknown default:
            return "オンデバイスモデルを利用できません"
        }
    }

    /// 録音開始時に呼び、整形用セッションを事前に読み込む（レイテンシ低減）。
    /// 確定後に `format` で同じ指示が使われる前提。利用不可なら何もしない。
    func prewarm(instructions: String? = nil) {
        guard isAvailable else { return }
        let session = LanguageModelSession(instructions: instructions ?? Self.defaultFormattingInstructions)
        session.prewarm()
        preparedSession = session
    }

    /// テキストを整形して返す。利用不可・失敗時は元テキストをそのまま返す。
    /// - Parameters:
    ///   - text: 整形対象（音声認識の確定テキスト）。
    ///   - instructions: ワークフロー固有の指示。nil なら既定の軽整形を使う。
    func format(_ text: String, instructions: String? = nil) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isAvailable else { return text }

        // prewarm 済みセッションがあれば使い回す（1回限り）。無ければ都度生成。
        let session = preparedSession ?? LanguageModelSession(instructions: instructions ?? Self.defaultFormattingInstructions)
        preparedSession = nil

        do {
            let response = try await session.respond(to: trimmed)
            let formatted = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return formatted.isEmpty ? text : formatted
        } catch {
            // 生成失敗時は生テキストで挿入を続行する。
            return text
        }
    }
}
