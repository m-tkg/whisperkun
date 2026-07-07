import AVFoundation
import Foundation
import Observation
import OSLog
import Speech
import whisperkunCore

private let txLog = Log.logger(category: "transcription")

enum TranscriptionError: Error {
    case audioFormatUnavailable
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
    private(set) var phase: TranscriptionPhase = .idle {
        didSet {
            guard phase != oldValue else { return }
            // phase 遷移の背骨ログ。「認識中」固着時に、どこで遷移が止まったかを
            // Console.app（subsystem:com.mtkg.whisperkun）で時系列に追える。
            txLog.debug("phase: \(String(describing: oldValue), privacy: .public) -> \(String(describing: self.phase), privacy: .public) gen=\(self.session.generation, privacy: .public)")
        }
    }

    /// 文字起こしに使うロケール。
    var locale: Locale

    /// 取り込み用エンジン。セッションごとに作り直す（使い回さない）。
    /// 単一インスタンスを使い回すと、開始/停止サイクルをまたいでリアルタイム状態が
    /// 持ち越され、停止時に CoreAudio の IO スレッドが解放済み IOProc を呼ぶ競合
    /// （EXC_BAD_ACCESS）を誘発するため。
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    /// 認識結果（確定/暫定）からのテキスト組み立て（純ロジックは Core 側）。
    private var assembler = TranscriptAssembler()

    /// 世代（generation）と phase 遷移判断の状態機械（純ロジックは Core 側でテスト済み）。
    /// beginSession で世代を進め、stop でも進める。進行中の runSession は自分の世代と
    /// 一致しなくなったら中断して .listening へ遷移しない。
    /// 遷移のたびに `syncPhase()` で公開プロパティ `phase` へ反映する。
    private var session = TranscriptionSession()

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.locale = locale
    }

    var isRunning: Bool { session.isRunning }

    /// 現在のセッション世代（診断スナップショット用の読み取り専用公開）。
    var generation: Int { session.generation }

    /// 状態機械の phase を公開プロパティへ反映する（didSet の遷移ログもここで発火する）。
    private func syncPhase() {
        phase = session.phase
    }

    /// セッションを同期的に開始する。世代を進め `.preparing` にし、その世代を返す。
    /// 実際の非同期セットアップは `runSession(generation:)` で行う。
    @discardableResult
    func beginSession() -> Int {
        let generation = session.begin()
        syncPhase()
        liveText = ""
        assembler = TranscriptAssembler()
        return generation
    }

    /// `beginSession` で得た世代でセットアップを行う。途中で世代が変わっていたら
    /// （stop / 新しい beginSession が走ったら）中断し、`.listening` へは遷移しない。
    func runSession(generation gen: Int) async {
        do {
            // .volatileResults 単独だと暫定結果が約12秒周期のバッチでしか届かず、
            // 短い発話では停止まで liveText が空のまま（HUD が「…」固定）になる。
            // .fastResults を足すと発話開始 約1秒から連続ストリームになりライブ表示が成立する。
            // 速報ドラフトは後続の暫定/確定で置き換わるため、挿入テキストの品質には影響しない。
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // 言語アセットが未インストールならダウンロードする。
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard session.isCurrent(gen) else { return }  // 既に停止/再開された

            // 解析器が要求する最適フォーマットを取得し、その形式へ変換する。
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw TranscriptionError.audioFormatUnavailable
            }
            guard session.isCurrent(gen) else { return }

            let bufferConverter = BufferConverter(outputFormat: analyzerFormat)
            let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)

            // マイクのネイティブフォーマットでタップを張り、コールバック内で変換して投入する。
            // タップはオーディオのリアルタイムスレッドで呼ばれる。`@Sendable` を付けて
            // クロージャを非隔離にしないと、@MainActor 隔離と推論されオーディオスレッド上で
            // 実行時の隔離アサーション（SIGTRAP）でクラッシュする。捕捉する値はいずれも
            // Sendable（continuation / @unchecked Sendable な bufferConverter）。
            // セッションごとに新しいエンジンを生成する（使い回しによるリアルタイム状態の
            // 持ち越し＝停止時の IO スレッド競合を断つ）。コミットするまで self には載せない。
            let engine = AVAudioEngine()
            let recordingFormat = engine.inputNode.outputFormat(forBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { @Sendable buffer, _ in
                if let converted = try? bufferConverter.convert(buffer) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }

            try await analyzer.start(inputSequence: inputStream)
            // ここから .listening 確定までは同期処理のみ（await を挟まない）＝世代チェックと原子的。
            guard session.isCurrent(gen) else {
                engine.inputNode.removeTap(onBus: 0)
                continuation.finish()
                return
            }
            engine.prepare()
            try engine.start()

            self.engine = engine
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
                    // 従来から世代によらず失敗を反映する（結果ストリームのエラー）。
                    self.session.forceFail(message: error.localizedDescription)
                    self.syncPhase()
                }
            }

            session.commitListening(gen)
            syncPhase()
        } catch {
            // 自分の世代のときだけ失敗を反映（古い世代なら stop 側が状態を持つ）。
            if session.fail(gen, message: error.localizedDescription) {
                cleanup()
                syncPhase()
            }
        }
    }

    /// 録音を停止し、確定テキストを返す。
    @discardableResult
    func stop() async -> String {
        // 進行中の runSession を無効化する（preparing 中でも .listening 化を止める）。
        // stop() は世代を進め、停止処理が必要（＝進行中だった）かを返す。
        guard session.stop() else { return assembler.finalizedText }

        // どの経路で抜けても必ずリソースを解放し phase を idle に戻す（「認識中」固着の保険）。
        // 現状 engine.stop()/removeTap は throws ではないが、将来の早期 return / await
        // キャンセル追加でも復帰を保証するため defer に集約する。
        defer {
            cleanup()
            session.finishStop()
            syncPhase()
        }

        // IO スレッドを先に静止させてから tap を外す。リアルタイムスレッド稼働中に
        // tap を解放すると、CoreAudio の IO スレッドが解放済み IOProc を呼んで
        // クラッシュ（EXC_BAD_ACCESS at 0x0）することがあるため、順序が重要。
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()

        // 末尾まで解析を確定させ結果購読の完了を待つ。ただし Speech 側の確定処理は短い発話でも
        // 一定時間返らないことがあり、その間 phase が .listening のままで「認識中」が居残って見える。
        // 待ち過ぎを避けるため短い上限で打ち切る（超過分は liveText フォールバックで補うので内容は欠けない）。
        let finished = await finishWithTimeout(seconds: 1.0)

        // 正常確定なら確定テキスト、タイムアウト時は暫定込みの表示テキストで代替する。
        return assembler.finalText(finished: finished)
    }

    /// 確定処理（finalize＋結果購読の完了）を待つ。期限内に終われば true、超過なら false。
    /// 超過時は残りの処理を諦めて呼び出し元を進める（固着防止）。
    ///
    /// `finalizeAndFinishThroughEndOfInput()` は Speech 側で稀にキャンセルにも応答せず返らず、
    /// 構造化タスクで待つと task group ごと固着する（「認識中」のまま停止できない不具合）。
    /// `withTimeout` は遅れた処理を待たずに必ず期限内で返すため、固着を確実に防ぐ。
    private func finishWithTimeout(seconds: Double) async -> Bool {
        // self を跨がせないよう、必要な値はローカルに取り出してから渡す。
        let analyzer = self.analyzer
        let resultsTask = self.resultsTask
        let finished = await withTimeout(seconds: seconds) {
            try? await analyzer?.finalizeAndFinishThroughEndOfInput()
            await resultsTask?.value
            return true
        }
        if finished == nil {
            txLog.warning("finalize timed out after \(seconds, privacy: .public)s; forcing stop")
        }
        return finished ?? false
    }

    private func apply(text: AttributedString, isFinal: Bool) {
        // 属性は使わないため String に落として組み立てる（組み立て規則は Core 側でテスト済み）。
        assembler.apply(text: String(text.characters), isFinal: isFinal)
        liveText = assembler.liveText
    }

    private func cleanup() {
        resultsTask?.cancel()
        resultsTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        engine = nil
    }
}
