import Foundation
import Testing
@testable import MirrorAudioCore

@Suite struct ReceiverConfigTests {
    @Test func 映像なし低遅延の引数を組み立てる() {
        let config = ReceiverConfig(serverName: "Mac mini Audio", bufferTimeMicros: 40_000)
        #expect(config.arguments == [
            "-n", "Mac mini Audio", "-nh", "-vs", "0", "-vsync", "no",
            "-as", "queue max-size-time=60000000 max-size-buffers=0 max-size-bytes=0 leaky=downstream"
                + " ! osxaudiosink buffer-time=40000 latency-time=10000",
        ])
    }

    @Test func 初期音量を指定しなければvolを付けない() {
        let config = ReceiverConfig(serverName: "x", bufferTimeMicros: 40_000)
        #expect(!config.arguments.contains("-vol"))
    }

    @Test func 初期音量をvolの割合に変換して付ける() {
        let config = ReceiverConfig(serverName: "x", bufferTimeMicros: 40_000, initialVolumeDecibels: -15.0)
        #expect(Array(config.arguments.suffix(2)) == ["-vol", "0.500"])
    }

    @Test func 音量の割合は範囲内に収める() {
        #expect(ReceiverConfig.volumeFraction(fromDecibels: 0.0) == 1.0)
        #expect(ReceiverConfig.volumeFraction(fromDecibels: 3.0) == 1.0)
        #expect(ReceiverConfig.volumeFraction(fromDecibels: -30.0) == 0.01)
        #expect(ReceiverConfig.volumeFraction(fromDecibels: -144.0) == 0.01)
    }

    @Test func キューの上限をナノ秒で指定する() {
        let config = ReceiverConfig(serverName: "x", bufferTimeMicros: 40_000, maxQueueMicros: 100_000)
        #expect(config.arguments.last?.hasPrefix("queue max-size-time=100000000 ") == true)
    }

    @Test func 空のサーバー名は既定名になる() {
        let config = ReceiverConfig(serverName: "   ", bufferTimeMicros: 40_000)
        #expect(config.arguments[1] == ReceiverConfig.defaultServerName)
    }

    @Test func バッファ長はlatencyTime未満にならない() {
        let config = ReceiverConfig(serverName: "x", bufferTimeMicros: 5_000, latencyTimeMicros: 10_000)
        #expect(config.arguments.last?.hasSuffix("! osxaudiosink buffer-time=10000 latency-time=10000") == true)
    }
}

@Suite struct LogParserTests {
    @Test func 待ち受け開始を検出する() {
        #expect(LogParser.event(from: "Initialized server socket(s)") == .ready)
    }

    @Test func 接続した端末名を取り出す() {
        let line = "connection request from deer iPhone (iPhone17,1) with deviceID = 8A:35:88:7D:B9:D7"
        #expect(LogParser.event(from: line) == .clientConnected(deviceName: "deer iPhone"))
    }

    @Test func 切断を検出する() {
        #expect(LogParser.event(from: "Connection closed on socket 15") == .clientDisconnected)
    }

    @Test func 音量の変化を検出する() {
        let line = "AirPlay volume -14.4 dB (slider 52%): GStreamer volume 0.192"
        #expect(LogParser.event(from: line) == .volumeChanged(decibels: -14.4))
    }

    @Test func 無関係な行は無視する() {
        #expect(LogParser.event(from: "raop_rtp starting audio") == nil)
        #expect(LogParser.event(from: "initial_volume attenuation -15.000000 db") == nil)
    }
}

@Suite struct LineBufferTests {
    @Test func CRLFを取り除いて行に分割する() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("a\r\nb\r\n".utf8)) == ["a", "b"])
    }

    @Test func 途中で切れた行は次のチャンクと結合する() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("hel".utf8)).isEmpty)
        #expect(buffer.append(Data("lo\nwor".utf8)) == ["hello"])
        #expect(buffer.append(Data("ld\n".utf8)) == ["world"])
    }
}

@Suite struct ReceiverStateTests {
    @Test func 起動中にreadyで待機中になる() {
        #expect(ReceiverState.starting.applying(.ready) == .waiting)
    }

    @Test func 接続と切断で状態が遷移する() {
        let connected = ReceiverState.waiting.applying(.clientConnected(deviceName: "iPhone"))
        #expect(connected == .connected(deviceName: "iPhone"))
        #expect(connected.applying(.clientDisconnected) == .waiting)
    }

    @Test func 音量の変化では状態が変わらない() {
        let connected = ReceiverState.connected(deviceName: "iPhone")
        #expect(connected.applying(.volumeChanged(decibels: -10)) == connected)
    }

    @Test func 停止中のイベントは無視する() {
        #expect(ReceiverState.stopped.applying(.clientConnected(deviceName: "iPhone")) == .stopped)
        #expect(ReceiverState.failed(message: "x").applying(.ready) == .failed(message: "x"))
    }
}

@Suite struct NetworkSetupParserTests {
    @Test func WiFiのデバイス名を取り出す() {
        let output = """
        Hardware Port: Ethernet
        Device: en0
        Ethernet Address: d0:11:e5:19:2c:05

        Hardware Port: Wi-Fi
        Device: en1
        Ethernet Address: d0:11:e5:1d:14:f8
        """
        #expect(NetworkSetupParser.wifiDevice(fromHardwarePorts: output) == "en1")
    }

    @Test func WiFiが無ければnil() {
        let output = "Hardware Port: Ethernet\nDevice: en0\n"
        #expect(NetworkSetupParser.wifiDevice(fromHardwarePorts: output) == nil)
    }
}

@Suite struct GameModePolicyTests {
    @Test func 強制オンを読み取る() {
        let output = """
        Game mode is \u{1B}[0;32mon\u{1B}[0;0m.
        Game mode enablement policy is currently disabled. Game mode is forced always on.
        """
        #expect(GameModePolicy.parse(statusOutput: output) == .on)
    }

    @Test func 自動を読み取る() {
        let output = """
        Game mode is \u{1B}[0;31moff\u{1B}[0;0m.
        Game mode enablement policy is currently automatic. The system must meet all specified requirements to enable game mode.
        """
        #expect(GameModePolicy.parse(statusOutput: output) == .auto)
    }

    @Test func 強制オフを読み取る() {
        let output = "Game mode enablement policy is currently disabled. Game mode is forced always off."
        #expect(GameModePolicy.parse(statusOutput: output) == .off)
    }

    @Test func 想定外の出力はnil() {
        #expect(GameModePolicy.parse(statusOutput: "error") == nil)
    }
}
