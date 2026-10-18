import Foundation

/// uxplay の標準出力の1行を ``ReceiverEvent`` に変換する。
public enum LogParser {
    /// 1行のログからイベントを取り出す。関係ない行なら nil。
    public static func event(from line: String) -> ReceiverEvent? {
        if line.contains("Initialized server socket") {
            return .ready
        }
        if let match = line.firstMatch(of: /connection request from (.+) \([^)]*\) with deviceID/) {
            return .clientConnected(deviceName: String(match.1))
        }
        if line.contains("Connection closed on socket") {
            return .clientDisconnected
        }
        return nil
    }
}

/// バイト列のチャンクを行単位に切り出すバッファ。
///
/// pty 経由の出力は改行が `\r\n` になるため、`\r` も取り除く。
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    /// チャンクを追加し、完結した行を返す。改行で終わっていない末尾は次回に持ち越す。
    public mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            lines.append(line)
        }
        return lines
    }
}
