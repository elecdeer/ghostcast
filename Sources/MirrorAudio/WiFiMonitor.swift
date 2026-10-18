import Foundation
import MirrorAudioCore
import Observation

/// Wi-Fi がネットワークに接続しているかを定期的に調べる。
///
/// Mac の Wi-Fi と Bluetooth は無線チップを共用するため、Wi-Fi 接続中は AirPods への出力が遅延・途切れやすい。
@MainActor
@Observable
final class WiFiMonitor {
    private(set) var isWiFiConnected = false

    private var task: Task<Void, Never>?

    /// 監視を開始する。
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let connected = await Self.checkWiFiConnected()
                self?.isWiFiConnected = connected
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Wi-Fi インターフェースに IP アドレスが割り当てられているかを調べる。
    ///
    /// 電源のオン/オフではなく IP の有無で見るのは、電源オンでも未接続なら干渉が小さいため。
    private nonisolated static func checkWiFiConnected() async -> Bool {
        guard let ports = run("/usr/sbin/networksetup", ["-listallhardwareports"]),
              let device = NetworkSetupParser.wifiDevice(fromHardwarePorts: ports),
              let address = run("/usr/sbin/ipconfig", ["getifaddr", device])
        else { return false }
        return !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// コマンドを実行して標準出力を返す。失敗時は nil。
    private nonisolated static func run(_ path: String, _ arguments: [String]) -> String? {
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
