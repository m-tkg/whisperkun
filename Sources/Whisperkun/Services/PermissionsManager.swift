import AVFoundation
import ApplicationServices
import Observation
import Speech

/// 権限の状態を3値で表現する。
enum PermissionState: Equatable {
    case notDetermined
    case denied
    case granted
}

/// マイク・音声認識・アクセシビリティの権限を一元管理する。
///
/// 文字起こし(`SpeechTranscriber`)にはマイクと音声認識、
/// 他アプリへの自動ペースト(CGEvent)にはアクセシビリティ権限が必要。
@MainActor
@Observable
final class PermissionsManager {
    private(set) var microphone: PermissionState = .notDetermined
    private(set) var speechRecognition: PermissionState = .notDetermined
    /// アクセシビリティはユーザーがシステム設定で付与するため、付与/未付与の2値で扱う。
    private(set) var accessibilityGranted: Bool = false

    /// 文字起こし〜自動入力までの全機能が利用可能か。
    var allGranted: Bool {
        microphone == .granted && speechRecognition == .granted && accessibilityGranted
    }

    init() {
        refresh()
    }

    /// システムへ問い合わせて各権限の現在状態を反映する（プロンプトは出さない）。
    func refresh() {
        microphone = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        speechRecognition = Self.map(SFSpeechRecognizer.authorizationStatus())
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// マイク権限を要求する（未決定時にシステムプロンプトを表示）。
    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
    }

    /// 音声認識権限を要求する。
    func requestSpeechRecognition() async {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        speechRecognition = Self.map(status)
    }

    /// アクセシビリティ権限を要求する。
    ///
    /// 付与はシステム設定パネルでの操作が必要なため、プロンプトを表示して
    /// システム設定アプリへ誘導するに留まる。付与結果は `refresh()` で取得する。
    func requestAccessibility() {
        // kAXTrustedCheckOptionPrompt はグローバル可変参照で Swift 6 の並行性チェックに抵触するため、
        // 同値の文字列リテラルをキーに用いる。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
