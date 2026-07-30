/// `flagsChanged` イベントの生 flags（UInt64）から「選択した修飾キーがすべて押下中か」を
/// 判定する純ロジック。
///
/// 通常の物理修飾キーは device-dependent ビット（`deviceMask`）で左右を区別して判定する。
/// ただし macOS システム設定「修飾キー」のリマップ（例: Caps Lock→Control）由来のイベントは
/// クラスマスク（maskControl 等）だけが立ち、左右の device ビットが立たない（keyCode も
/// 57 のまま）。そのため device ビット必須の判定だけではリマップキーの押下を永久に
/// 取りこぼす。フォールバックとして「クラスは押下だが同クラス左右どちらの device ビットも
/// 無い」場合をリマップ由来とみなして押下扱いにする。
public enum HotkeyFlagsEvaluator {
    /// 選択した修飾キーがすべて押下中か。空集合は常に false（未設定＝無効）。
    public static func isDown(flags: UInt64, modifiers: Set<HotkeyModifier>) -> Bool {
        guard !modifiers.isEmpty else { return false }
        return modifiers.allSatisfy { isSatisfied(flags: flags, modifier: $0) }
    }

    /// 1 修飾キー分の判定。device ビット一致、またはリマップフォールバック。
    ///
    /// フォールバックは同クラスのどの device ビットも立っていないときだけ成立するため、
    /// 例えば「左 Control」選択中に物理の右 Control を押しても（右 device ビットが立つので）
    /// 誤検出しない。{左, 右} 両選択＋リマップ由来イベントは左右を区別できないため
    /// 押下扱いとする（仕様）。
    static func isSatisfied(flags: UInt64, modifier: HotkeyModifier) -> Bool {
        if flags & modifier.deviceMask != 0 { return true }
        return (flags & modifier.classMask != 0) && (flags & modifier.classDeviceMask == 0)
    }
}
