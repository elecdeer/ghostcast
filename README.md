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

## 低遅延のコツ

- Mac の **Wi-Fi をオフ**にして有線 LAN で繋ぐ（Wi-Fi と Bluetooth が無線チップを取り合うため）
- 出力バッファは設定から変更可能（既定 40ms）
