/// 音声認識の結果ストリーム（確定/暫定）から表示用・確定テキストを組み立てる純ロジック。
///
/// - 確定（isFinal）結果は末尾に連結して蓄積する。
/// - 暫定結果は「確定済みの後ろに付けた表示」を作るだけで、蓄積はしない（次の暫定/確定で置き換わる）。
public struct TranscriptAssembler: Sendable, Equatable {
    /// 確定済みテキスト（isFinal の結果を連結したもの）。
    public private(set) var finalizedText = ""
    /// 確定済み＋暫定の表示用テキスト。HUD のライブ表示に使う。
    public private(set) var liveText = ""

    public init() {}

    /// 認識結果を1件取り込み、表示用テキストを更新する。
    public mutating func apply(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            liveText = finalizedText
        } else {
            // 暫定結果は確定済みの後ろに付けて表示する（確定はまだしない）。
            liveText = finalizedText + text
        }
    }

    /// 停止時に返す確定テキスト。
    /// 正常確定（finished）なら確定テキスト、タイムアウト時は暫定込みの表示テキストで代替する
    /// （確定が空でなければ確定を優先。内容が欠けないためのフォールバック）。
    public func finalText(finished: Bool) -> String {
        finished ? finalizedText : (finalizedText.isEmpty ? liveText : finalizedText)
    }
}
