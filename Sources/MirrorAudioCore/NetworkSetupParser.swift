import Foundation

/// `networksetup` コマンドの出力を解析する。
public enum NetworkSetupParser {
    /// `networksetup -listallhardwareports` の出力から Wi-Fi のデバイス名（例: en1）を取り出す。
    public static func wifiDevice(fromHardwarePorts output: String) -> String? {
        var inWiFiBlock = false
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                inWiFiBlock = line == "Hardware Port: Wi-Fi"
            } else if inWiFiBlock, line.hasPrefix("Device:") {
                let device = line.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
                return device.isEmpty ? nil : device
            }
        }
        return nil
    }
}
