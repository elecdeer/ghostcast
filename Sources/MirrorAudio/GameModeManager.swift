import Foundation
import MirrorAudioCore
import Observation

/// 受信中だけ macOS のゲームモードを強制オンにする。
///
/// ゲームモード中は AirPods との Bluetooth 通信頻度が上がり音声遅延が下がるが、
/// 通常は「ゲームが全画面で最前面」のときしか有効にならないため、Xcode 付属の gamepolicyctl で強制する。
@MainActor
@Observable
final class GameModeManager {
    /// このアプリがゲームモードを強制オンにしている最中か。
    private(set) var isForcing = false
    /// gamepolicyctl が見つからない（Xcode 未導入など）場合のメッセージ。
    private(set) var unavailableReason: String?

    /// 強制前のポリシー。ユーザーが自分で設定していた値を上書きしたまま残さないために覚えておく。
    private var policyToRestore: GameModePolicy?
    /// 開始・停止が連続しても gamepolicyctl の呼び出し順が入れ替わらないよう直列化する。
    private var queue: Task<Void, Never>?

    /// ゲームモードを強制オンにする。
    func forceOn() {
        enqueue { [weak self] in
            guard let self, !self.isForcing else { return }
            guard let tool = await Self.toolPath() else {
                self.unavailableReason = "gamepolicyctl が見つかりません（Xcode が必要です）"
                return
            }
            self.unavailableReason = nil
            let current = await Self.run(tool, ["game-mode", "status"]).flatMap(GameModePolicy.parse(statusOutput:))
            // 既にユーザーが強制オンにしているなら触らない
            if current == .on { return }
            guard await Self.run(tool, ["game-mode", "set", GameModePolicy.on.rawValue]) != nil else { return }
            self.policyToRestore = current ?? .auto
            self.isForcing = true
        }
    }

    /// 強制前のポリシーに戻す。
    func restore() {
        enqueue { [weak self] in
            guard let self, self.isForcing, let policy = self.policyToRestore else { return }
            guard let tool = await Self.toolPath() else { return }
            _ = await Self.run(tool, ["game-mode", "set", policy.rawValue])
            self.isForcing = false
            self.policyToRestore = nil
        }
    }

    /// アプリ終了時に呼ぶ。非同期処理を待てないので同期的に戻す。
    func restoreSynchronously() {
        guard isForcing, let policy = policyToRestore, let tool = Self.toolPathSync() else { return }
        _ = Self.runSync(tool, ["game-mode", "set", policy.rawValue])
        isForcing = false
        policyToRestore = nil
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private nonisolated static func toolPath() async -> String? {
        await Task.detached { toolPathSync() }.value
    }

    /// `xcrun --find` で gamepolicyctl の場所を探す。xcode-select の設定に従うので Xcode のパスを決め打ちしない。
    private nonisolated static func toolPathSync() -> String? {
        runSync("/usr/bin/xcrun", ["--find", "gamepolicyctl"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private nonisolated static func run(_ path: String, _ arguments: [String]) async -> String? {
        await Task.detached { runSync(path, arguments) }.value
    }

    /// コマンドを実行して標準出力を返す。失敗時は nil。
    private nonisolated static func runSync(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
