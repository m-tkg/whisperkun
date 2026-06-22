import AVFoundation

/// マイクの PCM バッファを `SpeechAnalyzer` が要求するフォーマットへ変換する。
///
/// SDK 提供の `AnalyzerInputConverter` は macOS 27+ 限定のため、macOS 26 対応として
/// `AVAudioConverter` で同等の変換を自前で行う。
final class BufferConverter {
    enum ConversionError: Error {
        case converterUnavailable
        case bufferAllocationFailed
    }

    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    /// 入力バッファを出力フォーマットへ変換して返す。フォーマットが一致する場合はそのまま返す。
    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == outputFormat {
            return buffer
        }

        // 入力フォーマットが変わったら変換器を作り直す。
        if converter == nil || converter?.inputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw ConversionError.converterUnavailable
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw ConversionError.bufferAllocationFailed
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if let conversionError {
            throw conversionError
        }
        return output
    }
}
