import AppKit
import SwiftUI

/// macOS のゲームモードを発動させるための全画面ウィンドウを管理する。
///
/// ゲームモード中は AirPods との Bluetooth 通信頻度が上がり音声遅延が下がる。
/// ゲームモードは「ゲームカテゴリのアプリが全画面で最前面」のときしか有効にならず、
/// 外部から強制する手段（gamepolicyctl）は Xcode が必要なため、自前で全画面ウィンドウを出す。
@MainActor
final class GameModeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// 黒い全画面ウィンドウを表示する。既に表示中なら前面に出すだけ。
    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = EscapableWindow(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MirrorAudio ゲームモード"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: GameModeView())
        window.delegate = self
        self.window = window

        // LSUIElement（accessory）のままだと最前面アプリ扱いにならずゲームモードが発動しない可能性があるため、
        // 表示中だけ通常アプリに切り替える
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Esc キーで閉じられるウィンドウ。
private final class EscapableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// ゲームモード待機中の画面。
private struct GameModeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
            Text("ゲームモード待機中")
                .font(.title)
            Text("メニューバーにゲームモードのアイコンが出ていれば有効です。\nEsc で終了します。")
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
