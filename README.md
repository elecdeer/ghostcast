# MirrorAudio

iPhone の AirPlay 画面ミラーリングを受信し、**音声だけ**を Mac で再生するメニューバーアプリ。
iPhone でゲームをしながら、Mac に繋いだ AirPods で音を聞くためのもの。

中身は [UxPlay](https://github.com/FDH2/UxPlay) を `-vs 0 -vsync no` で起動するラッパー。
音声のみの AirPlay ではなくミラーリングを使うのは、多くのゲームが音声 AirPlay に音を流さないため。

## ビルド

前提: UxPlay を `~/Dev/github.com/FDH2/UxPlay/build/uxplay` にビルド済み（`UXPLAY_BIN` で変更可）。

```bash
scripts/build-app.sh
```

`~/Applications/MirrorAudio.app` にインストールされる。

テスト:

```bash
swift test
```

> Command Line Tools の swift は、プロジェクトのパスに空白があるとマクロ（`@Observable` / `@Test`）を解決できない。
> `build-app.sh` は自動で一時ディレクトリにコピーしてビルドするが、`swift test` は空白のないパスで実行すること。

## 音量

iPhone から変更された音量を覚えておき、次回起動時に `-vol` で初期音量として渡す（uxplay は再起動すると最大音量に戻るため）。

## 低遅延のコツ

- Mac の **Wi-Fi をオフ**にして有線 LAN で繋ぐ（Wi-Fi と Bluetooth が無線チップを取り合うため）
- iPhone に要求する映像を最小限にする（既定 320x180・5fps）。映像は捨てるだけなので、iPhone の圧縮負荷と Wi-Fi の帯域が減り音声が安定する
- 受信中は macOS の**ゲームモードを強制オン**にする（AirPods との Bluetooth 通信頻度が上がる）。Xcode 付属の `gamepolicyctl` を使うため Xcode が必要。終了・停止時は元のポリシーに戻す
- 出力バッファは設定から変更可能（既定 40ms）
- 出力直前に leaky キューを挟み、Wi-Fi の詰まりで溜まった音を捨てて遅延の上限を固定している（既定 60ms、設定で変更可能）
