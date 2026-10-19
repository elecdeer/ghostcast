import AppKit
import MirrorAudioCore
import ServiceManagement
import SwiftUI

/// UserDefaults のキー。
enum SettingsKey {
    static let serverName = "serverName"
    static let bufferTimeMillis = "bufferTimeMillis"
    static let maxQueueMillis = "maxQueueMillis"
    static let autoStart = "autoStart"
    static let forceGameMode = "forceGameMode"
    /// 最後に iPhone から設定された音量（dB）。次回起動時の初期音量にする。
    static let lastVolumeDecibels = "lastVolumeDecibels"
}

/// 起動時の自動開始と終了時の後始末を担う。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let receiver = ReceiverController()
    let wifi = WiFiMonitor()
    let loginItem = LoginItemModel()
    let gameMode = GameModeManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            SettingsKey.serverName: ReceiverConfig.defaultServerName,
            SettingsKey.bufferTimeMillis: ReceiverConfig.defaultBufferTimeMillis,
            SettingsKey.maxQueueMillis: ReceiverConfig.defaultMaxQueueMillis,
            SettingsKey.autoStart: true,
            SettingsKey.forceGameMode: true,
        ])
        wifi.start()
        receiver.onRunningChanged = { [weak self] running in
            self?.updateGameMode(receiverRunning: running)
        }
        receiver.onVolumeChanged = { decibels in
            UserDefaults.standard.set(decibels, forKey: SettingsKey.lastVolumeDecibels)
        }
        if UserDefaults.standard.bool(forKey: SettingsKey.autoStart) {
            receiver.start(config: Self.currentConfig())
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        receiver.terminateSynchronously()
        gameMode.restoreSynchronously()
    }

    /// 受信中かつ設定が有効ならゲームモードを強制オンにし、そうでなければ元に戻す。
    func updateGameMode(receiverRunning: Bool? = nil) {
        let running = receiverRunning ?? receiver.state.isRunning
        if running && UserDefaults.standard.bool(forKey: SettingsKey.forceGameMode) {
            gameMode.forceOn()
        } else {
            gameMode.restore()
        }
    }

    /// 保存済みの設定から ``ReceiverConfig`` を作る。
    static func currentConfig() -> ReceiverConfig {
        let defaults = UserDefaults.standard
        return ReceiverConfig(
            serverName: defaults.string(forKey: SettingsKey.serverName) ?? ReceiverConfig.defaultServerName,
            bufferTimeMicros: defaults.integer(forKey: SettingsKey.bufferTimeMillis) * 1000,
            maxQueueMicros: defaults.integer(forKey: SettingsKey.maxQueueMillis) * 1000,
            initialVolumeDecibels: defaults.object(forKey: SettingsKey.lastVolumeDecibels) as? Double
        )
    }
}

@main
struct MirrorAudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(receiver: appDelegate.receiver, wifi: appDelegate.wifi, gameMode: appDelegate.gameMode)
        } label: {
            Image(systemName: Self.symbol(for: appDelegate.receiver.state))
        }
        .menuBarExtraStyle(.menu)

        Window("MirrorAudio 設定", id: "settings") {
            SettingsView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
    }

    /// 状態に応じたメニューバーアイコン。
    private static func symbol(for state: ReceiverState) -> String {
        switch state {
        case .connected: "headphones.circle.fill"
        case .starting, .waiting: "headphones"
        case .stopped: "headphones.slash"
        case .failed: "exclamationmark.triangle"
        }
    }
}

/// メニューバーのドロップダウン。
struct MenuContent: View {
    let receiver: ReceiverController
    let wifi: WiFiMonitor
    let gameMode: GameModeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
        if gameMode.isForcing {
            Text("🎮 ゲームモード強制オン（Bluetooth 低遅延）")
        }
        if let reason = gameMode.unavailableReason {
            Text("⚠️ \(reason)")
        }
        if wifi.isWiFiConnected {
            Text("⚠️ Wi-Fi 接続中（遅延・途切れの原因）")
        }
        Divider()
        if receiver.state.isRunning {
            Button("停止") { receiver.stop() }
        } else {
            Button("開始") { receiver.start(config: AppDelegate.currentConfig()) }
        }
        Button("ログを表示") {
            NSWorkspace.shared.open(ReceiverController.logURL)
        }
        Button("設定…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch receiver.state {
        case .stopped: "停止中"
        case .starting: "起動中…"
        case .waiting: "待機中（iPhone から画面ミラーリング）"
        case .connected(let name): "接続中: \(name)"
        case .failed(let message): "エラー: \(message)"
        }
    }
}

/// ログイン時起動（ログイン項目）の状態。
///
/// SwiftUI の `@State` は Command Line Tools の SDK だとマクロ実装が無くビルドできないため、Observable で持つ。
@MainActor
@Observable
final class LoginItemModel {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var errorMessage: String?

    /// ログイン項目への登録・解除を行う。
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "ログイン項目の変更に失敗しました: \(error.localizedDescription)"
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

/// 設定ウィンドウ。
struct SettingsView: View {
    let appDelegate: AppDelegate
    @AppStorage(SettingsKey.serverName) private var serverName = ReceiverConfig.defaultServerName
    @AppStorage(SettingsKey.bufferTimeMillis) private var bufferTimeMillis = ReceiverConfig.defaultBufferTimeMillis
    @AppStorage(SettingsKey.maxQueueMillis) private var maxQueueMillis = ReceiverConfig.defaultMaxQueueMillis
    @AppStorage(SettingsKey.autoStart) private var autoStart = true
    @AppStorage(SettingsKey.forceGameMode) private var forceGameMode = true

    private var receiver: ReceiverController { appDelegate.receiver }
    private var loginItem: LoginItemModel { appDelegate.loginItem }

    private static let bufferChoices = [20, 40, 60, 80, 100, 200]
    private static let queueChoices = [20, 40, 60, 100, 200, 500]

    var body: some View {
        Form {
            TextField("表示名", text: $serverName)
            Picker("出力バッファ", selection: $bufferTimeMillis) {
                ForEach(Self.bufferChoices, id: \.self) { Text("\($0) ms").tag($0) }
            }
            Text("小さいほど低遅延。音が途切れる場合は大きくしてください。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("遅延の上限（キュー）", selection: $maxQueueMillis) {
                ForEach(Self.queueChoices, id: \.self) { Text("\($0) ms").tag($0) }
            }
            Text("Wi-Fi の詰まりで溜まった音をここまでで捨てます。小さいほど遅延が安定しますが、音飛びしやすくなります。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("受信中はゲームモードを強制オン", isOn: Binding(
                get: { forceGameMode },
                set: {
                    forceGameMode = $0
                    appDelegate.updateGameMode()
                }
            ))
            Text("AirPods との Bluetooth 通信頻度が上がり遅延が下がります。Xcode 付属の gamepolicyctl を使います。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("アプリ起動時にレシーバーを開始", isOn: $autoStart)
            Toggle("ログイン時にアプリを起動", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            if let message = loginItem.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("適用して再起動") {
                    receiver.restart(config: AppDelegate.currentConfig())
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
