import AVFoundation
import Foundation
import Observation
import Speech

enum TranscriptionError: Error {
    case audioFormatUnavailable
}

/// 文字起こしの実行状態。
enum TranscriptionPhase: Equatable {
    case idle
    case preparing      // モデル/言語アセットの準備中
    case listening      // 録音・認識中
    case failed(String)
}

/// マイク入力を取り込み、Speech framework の `SpeechAnalyzer` + `SpeechTranscriber`
/// でリアルタイム文字起こしする中核サービス。
///
/// 取り込み(AVAudioEngine)→`AnalyzerInputConverter`で要求フォーマットへ変換→
/// `SpeechAnalyzer`へ投入、という流れを一手に担う。変換器が両者の間に必要なため、
/// マイク取り込みと解析を本クラスへ統合している。
@MainActor
@Observable
final class TranscriptionService {
    /// 確定済み＋暫定の表示用テキスト。HUDのライブ表示に使う。
    private(set) var liveText: String = ""
    private(set) var phase: TranscriptionPhase = .idle

    /// 文字起こしに使うロケール。
    var locale: Locale

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// 確定済みテキスト（isFinal の結果を連結したもの）。
    private var finalizedText = AttributedString()

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.locale = locale
    }

    var isRunning: Bool {
        if case .listening = phase { return true }
        if case .preparing = phase { return true }
        return false
    }

    /// 録音と文字起こしを開始する。
    func start() async {
        // 既に動作中（preparing/listening）なら何もしない。idle/failed からは開始する。
        switch phase {
        case .preparing, .listening: return
        case .idle, .failed: break
        }
        phase = .preparing
        liveText = ""
        finalizedText = AttributedString()

        do {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // 言語アセットが未インストールならダウンロードする。
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }

            // 解析器が要求する最適フォーマットを取得し、その形式へ変換する。
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw TranscriptionError.audioFormatUnavailable
            }
            let bufferConverter = BufferConverter(outputFormat: analyzerFormat)
            let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

            // マイクのネイティブフォーマットでタップを張り、コールバック内で変換して投入する。
            // タップはオーディオのリアルタイムスレッドで呼ばれる。`@Sendable` を付けて
            // クロージャを非隔離にしないと、@MainActor 隔離と推論されオーディオスレッド上で
            // 実行時の隔離アサーション（SIGTRAP）でクラッシュする。捕捉する値はいずれも
            // Sendable（continuation / @unchecked Sendable な bufferConverter）。
            let recordingFormat = engine.inputNode.outputFormat(forBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { @Sendable buffer, _ in
                if let converted = try? bufferConverter.convert(buffer) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }

            try await analyzer.start(inputSequence: inputStream)
            engine.prepare()
            try engine.start()

            self.transcriber = transcriber
            self.analyzer = analyzer
            self.inputContinuation = continuation

            // 結果ストリームを購読（@MainActor を継承するため UI 状態を直接更新できる）。
            resultsTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        self.apply(text: result.text, isFinal: result.isFinal)
                    }
                } catch {
                    self.phase = .failed(error.localizedDescription)
                }
            }

            phase = .listening
        } catch {
            cleanup()
            phase = .failed(error.localizedDescription)
        }
    }

    /// 録音を停止し、確定テキストを返す。
    @discardableResult
    func stop() async -> String {
        guard isRunning else { return String(finalizedText.characters) }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputContinuation?.finish()

        // 末尾まで解析を確定させ結果購読の完了を待つ。ただし Speech 側で稀に確定処理が
        // 返らず「認識中」のまま固着するため、タイムアウトで打ち切る。
        let finished = await finishWithTimeout(seconds: 3)

        // 正常確定なら確定テキスト、タイムアウト時は暫定込みの表示テキストで代替する。
        let finalized = String(finalizedText.characters)
        let result = finished ? finalized : (finalized.isEmpty ? liveText : finalized)

        cleanup()
        phase = .idle
        return result
    }

    /// 確定処理（finalize＋結果購読の完了）を待つ。期限内に終われば true、超過なら false。
    /// 超過時は残りの処理を諦めて呼び出し元を進める（固着防止）。
    private func finishWithTimeout(seconds: Double) async -> Bool {
        // self を跨がせないよう、必要な値はローカルに取り出してから渡す。
        let analyzer = self.analyzer
        let resultsTask = self.resultsTask
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                try? await analyzer?.finalizeAndFinishThroughEndOfInput()
                await resultsTask?.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func apply(text: AttributedString, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            liveText = String(finalizedText.characters)
        } else {
            // 暫定結果は確定済みの後ろに付けて表示する（確定はまだしない）。
            liveText = String((finalizedText + text).characters)
        }
    }

    private func cleanup() {
        resultsTask?.cancel()
        resultsTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
    }
}
