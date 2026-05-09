# 00. 環境構築チェックリスト

本教材を始める前に、開発環境が整っていることを確認します。所要時間は初回 30 分程度(Xcode のダウンロードを含む)。

## 必要なもの

| 項目 | バージョン | 確認コマンド |
|---|---|---|
| macOS | 26 以降 | `sw_vers` |
| Xcode | 16 以降 | `xcodebuild -version` |
| Swift | 6.0 以降 | `swift --version` |
| xcodegen | 任意のバージョン | `xcodegen --version` |
| make | macOS 標準 | `make --version` |

## チェックリスト

### 1. macOS のバージョン

ZoomacIt は macOS 26+ を最小デプロイメントターゲットにしています。古い macOS では起動できません。

```bash
sw_vers
# ProductName:    macOS
# ProductVersion: 26.x.x
```

### 2. Xcode のインストール

App Store から「Xcode」を検索してインストール。インストール後、一度起動して各種コンポーネントの初期化を済ませておきます。

```bash
xcodebuild -version
# Xcode 16.x
```

### 3. Command Line Tools

Xcode インストール時に同梱される CLI ツール群です。`xcodebuild` `swift` `clang` などが入ります。

```bash
xcode-select --install   # 既に入っていれば「already installed」と表示される
swift --version
# Apple Swift version 6.0 ...
```

### 4. xcodegen のインストール

ZoomacIt は xcodegen でプロジェクトを生成します。Homebrew で入れます。

```bash
# Homebrew が未インストールなら https://brew.sh/ から導入
brew install xcodegen
xcodegen --version
```

> **NOTE**
> `xcodegen` は `src/project.yml` を変更したときだけ使います。普段の開発では起動しません。本教材を読むだけなら不要ですが、Part IV のハンズオンで設定タブを追加するときに `make generate` 経由で間接的に使います。

### 5. リポジトリの取得とビルド確認

```bash
cd ~/somewhere
git clone https://github.com/07JP27/ZoomacIt.git
cd ZoomacIt
make build
make test
make run
```

`make build` と `make test` が成功し、`make run` でメニューバーに ZoomacIt のアイコンが表示されれば準備完了です。

### 6. 画面収録の許可

`make run` でアプリを起動した直後、macOS から「画面収録」の許可ダイアログが出ます。これは ZoomacIt が画面拡大機能で `ScreenCaptureKit` を使うために必要です。

「システム設定 → プライバシーとセキュリティ → 画面収録」で ZoomacIt にチェックを入れ、アプリを再起動します。

> **NOTE**
> 画面収録の許可はホットキー機能(⌃1 / ⌃2 / ⌃3)を試すときに必要です。教材の文法解説部分(Part II の大半)を読むだけなら、許可なしでも進められます。

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `make build` が `xcodebuild: error: ...` で失敗 | Xcode の最初の起動でライセンス同意していない | `sudo xcodebuild -license accept` |
| `xcodebuild: error: SDK ... not found` | macOS 26 SDK が無い古い Xcode | Xcode を最新版に更新 |
| `make: xcodegen: command not found` | xcodegen 未インストール | `brew install xcodegen` |
| ホットキーが動かない | 画面収録 (またはアクセシビリティ) 未許可 | システム設定で許可 → アプリ再起動 |

---

準備ができたら、[01. Swift とは / なぜ ZoomacIt で学ぶか](./part1-welcome/01-what-is-swift.md) から始めてください。
