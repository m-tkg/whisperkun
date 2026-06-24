import AppKit
import Foundation
import Observation
import whisperkunCore

/// パイプラインが後処理に使うデータ一式（SwiftDataから供給）。
struct PipelineData: Sendable {
    var dictionaryRules: [DictionaryRule] = []
}

/// ディクテーションの一連の流れを統括する。
///
/// ホットキー（または手動トグル）→ 録音/文字起こし → HUD表示 → 確定テキストの挿入、
/// という流れを束ねる。確定〜挿入の間に辞書置換とAI整形を差し込む。
@MainActor
@Observable
final class DictationCoordinator {
    let transcription: TranscriptionService
    private let insertion: TextInsertionService
    private let ai: AIService
    private let hud: HUDController
    private let hotkey: HotkeyService
    private let dictionary = DictionaryService()

    /// AI整形を行うか（ユーザー設定。既定オン）。
    var aiFormattingEnabled = true

    /// 文字起こしの既定ロケール。
    var defaultLocaleID = "ja-JP"

    /// 録音開始時に SwiftData から最新データを取得するためのプロバイダ。
    var loadPipelineData: (() -> PipelineData)?

    /// 確定テキストを履歴へ保存するためのコールバック（text, appBundleID）。
    var onTranscript: ((String, String?) -> Void)?

    /// 後処理に使うデータ（begin時に loadPipelineData で更新）。
    private var dictionaryRules: [DictionaryRule] = []

    /// 録音開始時に確定した前面アプリ（履歴保存用）。
    private var targetBundleID: String?

    /// 録音セッションが開始済みか（begin/end を同期的に判定するためのフラグ）。
    /// transcription.phase は非同期に更新されるため、それに依存せずここで管理する。
    private var isActive = false

    /// 確定テキストの挿入中など、停止処理が進行中かどうか。
    private(set) var isFinishing = false

    init(
        transcription: TranscriptionService = TranscriptionService(),
        insertion: TextInsertionService = TextInsertionService(),
        ai: AIService = AIService(),
        hud: HUDController = HUDController(),
        hotkey: HotkeyService = HotkeyService()
    ) {
        self.transcription = transcription
        self.insertion = insertion
        self.ai = ai
        self.hud = hud
        self.hotkey = hotkey

        hotkey.onStart = { [weak self] in self?.begin() }
        hotkey.onStop = { [weak self] in self?.end() }
        hud.onCancel = { [weak self] in self?.cancel() }
    }

    /// HUD の中止ボタンから呼ぶ。録音を強制停止し、確定テキストは破棄して状態をリセットする。
    /// preparing 中でも止められるよう、開始処理の完了を待たずに stop する
    /// （stop が世代を進めて進行中の開始処理を無効化するため、.listening への遷移は起きない）。
    func cancel() {
        isActive = false
        isFinishing = false
        Task {
            _ = await transcription.stop()
            hud.hide()
        }
    }

    /// AI整形が実際に利用可能か（設定オン かつ モデル利用可）。
    var aiAvailable: Bool { ai.isAvailable }
    var aiUnavailableReason: String? { ai.unavailableReason }

    /// ホットキー監視を開始する（アクセシビリティ権限が必要）。
    @discardableResult
    func installHotkey() -> Bool {
        hotkey.install()
    }

    var hotkeyInstalled: Bool { hotkey.isInstalled }
    var isRecording: Bool { transcription.isRunning }

    /// ホットキーの方式と修飾キーを反映する。`modifiers` が空なら監視を停止する。
    /// （設定がある場合の監視開始は権限を知る AppState 側で行う。）
    func applyHotkeySettings(mode: HotkeyMode, modifiers: Set<HotkeyModifier>) {
        hotkey.mode = mode
        hotkey.modifiers = modifiers
        if modifiers.isEmpty {
            hotkey.uninstall()
        }
    }

    /// ホットキーが設定済みか（修飾キーが割り当てられているか）。
    var hotkeyConfigured: Bool { !hotkey.modifiers.isEmpty }

    /// 現在割り当てられている修飾キーの組み合わせ（未設定なら空）。
    var hotkeyModifiers: Set<HotkeyModifier> { hotkey.modifiers }

    /// 手動トグル（メニューバーから / ホットキーのトグル方式と等価）。
    func toggle() {
        if isActive {
            end()
        } else {
            begin()
        }
    }

    private func begin() {
        // isActive を同期的に判定。短い発話で begin/end が交錯しても破綻しない。
        guard !isActive, !isFinishing else { return }
        isActive = true

        // 最新の辞書を取り込む。
        if let data = loadPipelineData?() {
            dictionaryRules = data.dictionaryRules
        }

        // 録音開始時点の前面アプリを確定（履歴保存用）。
        // 自分（メニュー/HUD）は非アクティブ化のため前面に出ず、ターゲットは維持される。
        targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        transcription.locale = Locale(identifier: defaultLocaleID)

        // AI整形を使うなら、発話中にモデルを読み込んでおき確定後のレイテンシを下げる。
        if aiFormattingEnabled {
            ai.prewarm()
        }

        hud.show(transcription)
        // セッションの世代を同期的に確定してから非同期セットアップを走らせる。
        let generation = transcription.beginSession()
        Task { await transcription.runSession(generation: generation) }
    }

    private func end() {
        guard isActive, !isFinishing else { return }
        isActive = false
        isFinishing = true
        Task {
            // 開始処理の完了は待たない。stop が世代を進めて進行中の開始処理を無効化するため、
            // preparing 中に止めても .listening へ遷移して固着することはない。
            let text = await transcription.stop()
            let processed = await process(text)
            hud.hide()
            if !processed.isEmpty {
                insertion.insert(processed)
                onTranscript?(processed, targetBundleID)
            }
            isFinishing = false
        }
    }

    /// 確定テキストの後処理パイプライン: 辞書置換 → AI整形。
    private func process(_ text: String) async -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // 1. 辞書で用語を補正（AIに正しい語を見せるため整形より前）。
        result = dictionary.apply(result, rules: dictionaryRules)

        // 2. AI整形（既定の軽整形）。整形中は HUD にスピナーを表示。
        if aiFormattingEnabled {
            hud.state.isFormatting = true
            result = await ai.format(result)
            hud.state.isFormatting = false
        }

        return result
    }
}
