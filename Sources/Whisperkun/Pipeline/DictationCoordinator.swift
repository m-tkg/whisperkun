import AppKit
import Foundation
import Observation
import WhisperkunCore

/// パイプラインが後処理に使うデータ一式（SwiftDataから供給）。
struct PipelineData: Sendable {
    var dictionaryRules: [DictionaryRule] = []
    var snippets: [String: String] = [:]
    var workflows: [WorkflowRule] = []
}

/// ディクテーションの一連の流れを統括する。
///
/// ホットキー（または手動トグル）→ 録音/文字起こし → HUD表示 → 確定テキストの挿入、
/// という流れを束ねる。M4でAI整形、M5で辞書/スニペット/ワークフローを
/// 確定〜挿入の間に差し込んでいく。
@MainActor
@Observable
final class DictationCoordinator {
    let transcription: TranscriptionService
    private let insertion: TextInsertionService
    private let ai: AIService
    private let hud: HUDController
    private let hotkey: HotkeyService
    private let dictionary = DictionaryService()
    private let snippetService = SnippetService()
    private let workflowService = WorkflowService()

    /// AI整形を行うか（ユーザー設定。既定オン）。
    var aiFormattingEnabled = true

    /// ワークフロー指定が無いときの既定ロケール。
    var defaultLocaleID = "ja-JP"

    /// 録音開始時に SwiftData から最新データを取得するためのプロバイダ。
    var loadPipelineData: (() -> PipelineData)?

    /// 確定テキストを履歴へ保存するためのコールバック（text, appBundleID）。
    var onTranscript: ((String, String?) -> Void)?

    /// 後処理に使うデータ（begin時に loadPipelineData で更新）。
    private var dictionaryRules: [DictionaryRule] = []
    private var snippets: [String: String] = [:]
    private var workflows: [WorkflowRule] = []

    /// 録音開始時に確定したターゲット情報。
    private var targetBundleID: String?
    private var activeWorkflow: WorkflowRule?

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

    /// ホットキーの方式と修飾キーを反映する。`modifier` が nil なら監視を停止する。
    /// （設定がある場合の監視開始は権限を知る AppState 側で行う。）
    func applyHotkeySettings(mode: HotkeyMode, modifier: HotkeyModifier?) {
        hotkey.mode = mode
        hotkey.modifier = modifier
        if modifier == nil {
            hotkey.uninstall()
        }
    }

    /// ホットキーが設定済みか（修飾キーが割り当てられているか）。
    var hotkeyConfigured: Bool { hotkey.modifier != nil }

    /// 現在割り当てられている修飾キー（未設定なら nil）。
    var hotkeyModifier: HotkeyModifier? { hotkey.modifier }

    /// 手動トグル（メニューバーから / ホットキーのトグル方式と等価）。
    func toggle() {
        if transcription.isRunning {
            end()
        } else {
            begin()
        }
    }

    private func begin() {
        guard !transcription.isRunning, !isFinishing else { return }

        // 最新の辞書/スニペット/ワークフローを取り込む。
        if let data = loadPipelineData?() {
            dictionaryRules = data.dictionaryRules
            snippets = data.snippets
            workflows = data.workflows
        }

        // 録音開始時点の前面アプリを確定し、対応ワークフローを選ぶ。
        // 自分（メニュー/HUD）は非アクティブ化のため前面に出ず、ターゲットは維持される。
        targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activeWorkflow = workflowService.select(for: targetBundleID, from: workflows)

        // ロケールはワークフロー指定優先、無ければ既定。
        transcription.locale = Locale(identifier: activeWorkflow?.localeID ?? defaultLocaleID)

        // AI整形を使うなら、発話中にモデルを読み込んでおき確定後のレイテンシを下げる。
        if aiFormattingEnabled {
            ai.prewarm(instructions: activeWorkflow?.instructions)
        }

        hud.show(transcription)
        Task { await transcription.start() }
    }

    private func end() {
        guard transcription.isRunning, !isFinishing else { return }
        isFinishing = true
        Task {
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

    /// 確定テキストの後処理パイプライン: 辞書置換 → AI整形 → スニペット展開。
    private func process(_ text: String) async -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // 1. 辞書で用語を補正（AIに正しい語を見せるため整形より前）。
        result = dictionary.apply(result, rules: dictionaryRules)

        // 2. AI整形（ワークフロー固有プロンプトがあれば使用）。
        if aiFormattingEnabled {
            result = await ai.format(result, instructions: activeWorkflow?.instructions)
        }

        // 3. スニペット/プレースホルダ展開。
        result = snippetService.expand(result, snippets: snippets, now: Date())

        return result
    }
}
