import AppKit
import Observation
import SwiftUI
import whisperkunCore

/// HUD 固有の表示状態（録音以外の進行表示）。AI整形中などに使う。
@MainActor
@Observable
final class HUDState {
    /// AI整形が進行中か。true の間はスピナーを表示する。
    var isFormatting = false
}

/// 録音中に画面下部へ浮かぶフローティングインジケータの内容。
struct RecordingHUDView: View {
    @Bindable var transcription: TranscriptionService
    @Bindable var state: HUDState
    /// 中止ボタンが押されたとき（録音を強制終了して破棄）。
    var onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                Text(transcription.liveText.isEmpty ? "…" : transcription.liveText)
                    .font(.title3)
                    .lineLimit(3)
                    // 3行を超えたら先頭側を省略し、いま喋っている最新部分を常に見せる。
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("録音を中止")
            .padding(8)
        }
    }

    private var statusLabel: String {
        if state.isFormatting { return String(localized: "AIで整形中") }
        switch transcription.phase {
        case .preparing: return String(localized: "準備中")
        case .listening: return String(localized: "認識中")
        case .failed: return String(localized: "エラー")
        case .idle: return ""
        }
    }

    /// 状態ごとに色を変えて一目で区別できるようにする。
    private var statusColor: Color {
        if state.isFormatting { return .purple }
        switch transcription.phase {
        case .listening: return .green
        case .preparing: return .secondary
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        // 整形中は録音フェーズに関わらず AI 整形アイコンを優先表示する（認識中と区別）。
        if state.isFormatting {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(.purple)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            switch transcription.phase {
            case .listening:
                Image(systemName: "waveform")
                    .font(.title)
                    .foregroundStyle(.green)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            case .preparing:
                ProgressView().controlSize(.small)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.red)
            case .idle:
                Image(systemName: "mic").font(.title).foregroundStyle(.secondary)
            }
        }
    }
}

