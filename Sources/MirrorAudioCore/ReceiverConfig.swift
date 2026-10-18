/// uxplay の起動設定。
public struct ReceiverConfig: Equatable, Sendable {
    /// iPhone の「画面ミラーリング」一覧に表示される名前。
    public var serverName: String
    /// osxaudiosink のバッファ長（マイクロ秒）。小さいほど低遅延だが途切れやすい。
    public var bufferTimeMicros: Int
    /// osxaudiosink の1回あたりの書き込み単位（マイクロ秒）。
    public var latencyTimeMicros: Int

    public init(serverName: String, bufferTimeMicros: Int, latencyTimeMicros: Int = 10_000) {
        self.serverName = serverName
        self.bufferTimeMicros = bufferTimeMicros
        self.latencyTimeMicros = latencyTimeMicros
    }

    public static let defaultServerName = "Mac mini Audio"
    public static let defaultBufferTimeMillis = 40

    /// uxplay に渡すコマンドライン引数を組み立てる。
    ///
    /// 映像は捨て（`-vs 0`）、映像との同期待ちもしない（`-vsync no`）ことで遅延を最小化する。
    public var arguments: [String] {
        let name = serverName.trimmingCharacters(in: .whitespaces)
        // buffer-time が latency-time を下回ると GStreamer がエラーになるため下限を揃える
        let latency = max(1, latencyTimeMicros)
        let buffer = max(latency, bufferTimeMicros)
        return [
            "-n", name.isEmpty ? Self.defaultServerName : name,
            "-nh",
            "-vs", "0",
            "-vsync", "no",
            "-as", "osxaudiosink buffer-time=\(buffer) latency-time=\(latency)",
        ]
    }
}
