import Testing
@testable import whisperkunCore

@Suite struct BundleIdentityTests {
    @Test func ローカルビルドのIDは末尾のlocalを除いた基底IDになる() {
        #expect(BundleIdentity.baseID("com.mtkg.whisperkun.local") == "com.mtkg.whisperkun")
    }

    @Test func 本番IDはそのまま返す() {
        #expect(BundleIdentity.baseID("com.mtkg.whisperkun") == "com.mtkg.whisperkun")
    }

    @Test func nilはnilを返す() {
        #expect(BundleIdentity.baseID(nil) == nil)
    }

    @Test func 空文字はそのまま返す() {
        #expect(BundleIdentity.baseID("") == "")
    }

    @Test func 中間にlocalを含むIDは除去しない() {
        #expect(BundleIdentity.baseID("com.local.whisperkun") == "com.local.whisperkun")
    }

    @Test func ローカルビルドの判定() {
        #expect(BundleIdentity.isLocal("com.mtkg.whisperkun.local"))
        #expect(!BundleIdentity.isLocal("com.mtkg.whisperkun"))
        #expect(!BundleIdentity.isLocal(nil))
        #expect(!BundleIdentity.isLocal(""))
    }
}
