import Foundation

/// uxplay の起動設定。
public struct ReceiverConfig: Equatable, Sendable {
    /// iPhone の「画面ミラーリング」一覧に表示される名前。
    public var serverName: String
    /// osxaudiosink のバッファ長（マイクロ秒）。小さいほど低遅延だが途切れやすい。
    public var bufferTimeMicros: Int
    /// osxaudiosink の1回あたりの書き込み単位（マイクロ秒）。
    public var latencyTimeMicros: Int
    /// 出力直前のキューに溜められる最大時間（マイクロ秒）。超えた分は古い音から捨てる。
    public var maxQueueMicros: Int
    /// 接続時に iPhone へ伝える初期音量（dB）。nil なら uxplay の既定（最大音量）。
    public var initialVolumeDecibels: Double?

    public init(
        serverName: String,
        bufferTimeMicros: Int,
        latencyTimeMicros: Int = 10_000,
        maxQueueMicros: Int = ReceiverConfig.defaultMaxQueueMillis * 1000,
        initialVolumeDecibels: Double? = nil
    ) {
        self.serverName = serverName
        self.bufferTimeMicros = bufferTimeMicros
        self.latencyTimeMicros = latencyTimeMicros
        self.maxQueueMicros = maxQueueMicros
        self.initialVolumeDecibels = initialVolumeDecibels
    }

    /// uxplay の音量（dB）を `-vol` に渡す 0〜1 の値に変換する。
    ///
    /// uxplay は既定の音量範囲 -30〜0 dB に線形で割り当てるので、その逆変換をする。
    /// 0 を渡すと無音で始まってしまい接続が切れたように見えるため、最小でもわずかに音が出る値にする。
    public static func volumeFraction(fromDecibels decibels: Double) -> Double {
        min(1.0, max(0.01, (decibels + 30.0) / 30.0))
    }

    public static let defaultServerName = "Mac mini Audio"
    public static let defaultBufferTimeMillis = 40
    public static let defaultMaxQueueMillis = 60

    /// uxplay に渡すコマンドライン引数を組み立てる。
    ///
    /// 映像は捨て（`-vs 0`）、映像との同期待ちもしない（`-vsync no`）ことで遅延を最小化する。
    public var arguments: [String] {
        let name = serverName.trimmingCharacters(in: .whitespaces)
        // buffer-time が latency-time を下回ると GStreamer がエラーになるため下限を揃える
        let latency = max(1, latencyTimeMicros)
        let buffer = max(latency, bufferTimeMicros)
        let maxQueueNanos = max(1, maxQueueMicros) * 1000
        var arguments = [
            "-n", name.isEmpty ? Self.defaultServerName : name,
            "-nh",
            "-vs", "0",
            "-vsync", "no",
            // -as の文字列は uxplay のパイプライン末尾にそのまま連結されるので、sink の手前に要素を挟める。
            // sync=false の sink はWi-Fiの詰まりで届いた音を全部鳴らし、溜まった遅延が二度と縮まない。
            // leaky キューで古い音を捨てて遅延の上限を固定する。
            "-as", "queue max-size-time=\(maxQueueNanos) max-size-buffers=0 max-size-bytes=0 leaky=downstream"
                + " ! osxaudiosink buffer-time=\(buffer) latency-time=\(latency)",
        ]
        if let initialVolumeDecibels {
            let fraction = Self.volumeFraction(fromDecibels: initialVolumeDecibels)
            arguments += ["-vol", String(format: "%.3f", fraction)]
        }
        return arguments
    }
}
