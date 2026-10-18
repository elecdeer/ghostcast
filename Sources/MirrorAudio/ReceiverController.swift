import Darwin
import Foundation
import MirrorAudioCore
import Observation

/// uxplay プロセスの起動・停止と、ログからの状態追跡を行う。
@MainActor
@Observable
final class ReceiverController {
    private(set) var state: ReceiverState = .stopped

    private var process: Process?
    private var isStopping = false

    /// ログの保存先。起動のたびに上書きする。
    static let logURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/MirrorAudio/uxplay.log")

    /// アプリに同梱された uxplay のパス。
    ///
    /// Contents/MacOS に置くと uxplay（内部で NSApplication を使う）がアプリ本体と同一視され、
    /// 終了要求などの Apple Event を横取りしてしまうため Contents/Helpers に置いている。
    private var uxplayURL: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/uxplay")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// 現在の設定で uxplay を起動する。
    func start(config: ReceiverConfig) {
        guard !state.isRunning else { return }
        guard let uxplayURL else {
            state = .failed(message: "uxplay がアプリに同梱されていません")
            return
        }

        // uxplay はパイプ出力だと printf がフルバッファリングされログが届かないため、pty に繋ぐ
        var primary: Int32 = -1
        var replica: Int32 = -1
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
            state = .failed(message: "pty を作成できませんでした")
            return
        }

        let process = Process()
        process.executableURL = uxplayURL
        process.arguments = config.arguments
        let replicaHandle = FileHandle(fileDescriptor: replica, closeOnDealloc: true)
        process.standardOutput = replicaHandle
        process.standardError = replicaHandle
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.handleTermination(status: status) }
        }

        do {
            try process.run()
        } catch {
            close(primary)
            state = .failed(message: "起動に失敗しました: \(error.localizedDescription)")
            return
        }
        // 子プロセスが複製を持っているので親側の replica は閉じる（閉じないと EOF が来ない）
        try? replicaHandle.close()

        self.process = process
        isStopping = false
        state = .starting
        startReading(fd: primary)
    }

    /// uxplay を SIGINT で正常終了させる。応答しなければ SIGTERM で止める。
    func stop() {
        guard let process, process.isRunning else { return }
        isStopping = true
        process.interrupt()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let process = self.process, process.isRunning else { return }
            process.terminate()
        }
    }

    /// 設定変更を反映するため再起動する。
    func restart(config: ReceiverConfig) {
        guard let process, process.isRunning else {
            start(config: config)
            return
        }
        stop()
        Task { [weak self] in
            // 終了を待ってから起動しないとポートが埋まったままになる
            while process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            self?.start(config: config)
        }
    }

    /// アプリ終了時に呼ぶ。孤児プロセスを残さないよう終了まで待つ。
    func terminateSynchronously() {
        guard let process, process.isRunning else { return }
        isStopping = true
        process.interrupt()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate() }
    }

    private func handleTermination(status: Int32) {
        process = nil
        if isStopping || status == 0 {
            state = .stopped
        } else {
            state = .failed(message: "uxplay が終了しました（コード \(status)）")
        }
        isStopping = false
    }

    private func handleLine(_ line: String) {
        guard let event = LogParser.event(from: line) else { return }
        state = state.applying(event)
    }

    /// pty の出力を別スレッドで読み、ログファイルへ書きつつ行ごとにメインへ渡す。
    private func startReading(fd: Int32) {
        let logURL = Self.logURL
        let thread = Thread { [weak self] in
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try? FileHandle(forWritingTo: logURL)

            var lineBuffer = LineBuffer()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                // 子プロセス終了後は EIO が返るのでループを抜ける
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                let chunk = Data(buffer[0..<count])
                log?.write(chunk)
                let lines = lineBuffer.append(chunk)
                guard !lines.isEmpty else { continue }
                Task { @MainActor in
                    for line in lines { self?.handleLine(line) }
                }
            }
            try? log?.close()
            close(fd)
        }
        thread.start()
    }
}
