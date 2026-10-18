/// uxplay のログから読み取れる出来事。
public enum ReceiverEvent: Equatable, Sendable {
    /// サーバーが待ち受けを開始した。
    case ready
    /// iPhone が接続した。
    case clientConnected(deviceName: String)
    /// iPhone との接続が切れた。
    case clientDisconnected
}

/// レシーバーの状態。
public enum ReceiverState: Equatable, Sendable {
    case stopped
    case starting
    case waiting
    case connected(deviceName: String)
    case failed(message: String)

    /// uxplay プロセスが動作中とみなせるか。
    public var isRunning: Bool {
        switch self {
        case .starting, .waiting, .connected: true
        case .stopped, .failed: false
        }
    }

    /// ログイベントを適用した次の状態を返す。プロセスが動いていない間のイベントは無視する。
    public func applying(_ event: ReceiverEvent) -> ReceiverState {
        guard isRunning else { return self }
        switch event {
        case .ready:
            // 接続中に ready が来ることはないが、来ても接続表示を消さない
            if case .connected = self { return self }
            return .waiting
        case .clientConnected(let name):
            return .connected(deviceName: name)
        case .clientDisconnected:
            return .waiting
        }
    }
}
