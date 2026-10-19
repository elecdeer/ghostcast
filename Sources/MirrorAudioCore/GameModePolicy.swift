/// `gamepolicyctl game-mode set` に渡すゲームモードの有効化ポリシー。
public enum GameModePolicy: String, Equatable, Sendable {
    /// 条件（ゲームが全画面で最前面など）を満たしたときだけ有効。macOS の既定。
    case auto
    /// 常に有効。
    case on
    /// 常に無効。
    case off

    /// `gamepolicyctl game-mode status` の出力から現在のポリシーを読み取る。読み取れなければ nil。
    public static func parse(statusOutput: String) -> GameModePolicy? {
        if statusOutput.contains("forced always on") { return .on }
        if statusOutput.contains("forced always off") { return .off }
        if statusOutput.contains("currently automatic") { return .auto }
        return nil
    }
}
