import Foundation

/// 音声入力（マイク）デバイスの識別情報。
///
/// `uid` は CoreAudio の `kAudioDevicePropertyDeviceUID`（同じ機器なら再接続後も同一）で、
/// 実行のたびに変わる `AudioDeviceID` の代わりに設定へ永続化する。
public struct AudioInputDevice: Sendable, Equatable, Identifiable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }

    public var id: String { uid }
}

/// 保存された入力デバイス設定を、実際に接続されているデバイス一覧に照らして解決する純ロジック。
public enum AudioInputDeviceSelection {
    /// 録音で実際に使う入力デバイスの UID を返す。`nil` は「システム既定の入力を使う」を意味する。
    /// 保存されたデバイスが接続されていなければ既定へフォールバックする（録音自体は必ず行える）。
    public static func resolve(preferredUID: String?, available: [AudioInputDevice]) -> String? {
        guard let preferredUID, !preferredUID.isEmpty else { return nil }
        return available.contains { $0.uid == preferredUID } ? preferredUID : nil
    }

    /// 保存済みだが現在は接続されていないデバイスを返す（無ければ `nil`）。
    /// 設定 UI はこれを選択肢に残し、機器を挿し直したときに選択が元へ戻るようにする。
    /// 表示名が保存されていない場合は UID を表示名として使う。
    public static func missingPreferred(
        available: [AudioInputDevice],
        preferredUID: String?,
        preferredName: String?
    ) -> AudioInputDevice? {
        guard let preferredUID, !preferredUID.isEmpty else { return nil }
        guard !available.contains(where: { $0.uid == preferredUID }) else { return nil }
        let name = preferredName.flatMap { $0.isEmpty ? nil : $0 } ?? preferredUID
        return AudioInputDevice(uid: preferredUID, name: name)
    }
}
