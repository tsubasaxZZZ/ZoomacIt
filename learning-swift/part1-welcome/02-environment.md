# 02. 環境構築 — Xcode・xcodegen・make

## この章で学ぶこと

- macOS Swift 開発に必要なツール 3 種(Xcode、xcodegen、make)
- ZoomacIt のビルド・実行・テストの流れ
- Java 開発(Maven / Gradle)との対応関係

---

## ツールチェーンの全体像

ZoomacIt をビルドするには、次の 3 つのツールが必要です。

| ツール | 役割 | Java 開発で言うと |
|---|---|---|
| **Xcode** | Swift コンパイラ + ビルドシステム + 統合開発環境 | JDK + IntelliJ IDEA を一体化したもの |
| **xcodegen** | YAML から Xcode プロジェクトファイル(`.xcodeproj`)を生成 | Maven の `pom.xml` / Gradle の `build.gradle.kts` から IDE プロジェクトを生成する役 |
| **make** | コマンドラインからビルド・実行・テストを呼び出すラッパー | Maven/Gradle のラッパー(`mvnw`、`gradlew`)に近い |

> **NOTE**
> Xcode は Apple Silicon Mac の App Store から無料でダウンロードできます。インストール時に Command Line Tools(`xcodebuild`、`swift` などの CLI)も一緒に入ります。本教材では Xcode 16 以降 / macOS 26 以降を前提にしています。

## なぜ xcodegen を使うのか

Xcode のプロジェクトファイル `.xcodeproj` は、内部的に巨大な XML(正確には ASCII Plist)で、複数人で同時に編集するとマージ競合が頻発します。これは Java で言えば、IntelliJ IDEA の `.iml` ファイルを Git にコミットしているようなもので、現実的に運用が困難です。

そこで ZoomacIt は **`src/project.yml` という YAML ファイルからプロジェクト定義を生成する** xcodegen を使います。設定の真実は YAML 側にあり、`.xcodeproj` はそこから機械的に生成される派生物です。

```bash
make generate    # src/project.yml から src/ZoomacIt.xcodeproj を再生成
```

`src/project.yml` を変更したときだけ `make generate` を実行する運用です。普段は `.xcodeproj` を再生成する必要はありません。

> **NOTE**
> `.xcodeproj` も Git にコミットされていますが、これは「初回 clone した直後に Xcode で開けるようにするため」の便宜です。`project.yml` を変更したら、必ず `make generate` を走らせてコミットし直します。

## Makefile が提供するコマンド

ZoomacIt のルートディレクトリで `make <target>` を実行することで、Xcode を開かずに CLI から開発サイクルを回せます。

| コマンド | 内容 | Java 開発で言うと |
|---|---|---|
| `make build` | Debug ビルド | `mvn compile` / `gradle build` |
| `make test` | 単体テスト実行 | `mvn test` / `gradle test` |
| `make run` | ビルドして起動 | `gradle run` |
| `make release` | Release ビルド + Developer ID 署名 | `mvn package -P release` |
| `make notarize` | Release ビルド + Apple notarization | (Java には対応物なし) |
| `make dmg VERSION=1.0.0` | notarize + DMG 作成 | (Java には対応物なし) |
| `make clean` | ビルド成果物の削除 | `mvn clean` / `gradle clean` |
| `make generate` | `project.yml` から `.xcodeproj` 再生成 | (対応物なし、xcodegen 特有) |

`make notarize` と `make dmg` は配布用で、学習中は使いません。**最初に覚えるのは `build` / `test` / `run` の 3 つで十分** です。

## はじめてのビルド

リポジトリをクローンしたら、次の順で動作確認します。

```bash
# 1. ZoomacIt のルートディレクトリへ移動
cd /path/to/ZoomacIt

# 2. ビルドできることを確認
make build

# 3. テストが通ることを確認
make test

# 4. アプリを起動
make run
```

`make run` の後、画面右上のメニューバーに ZoomacIt のアイコンが現れます。Dock にはアイコンが表示されません。これは `Info.plist` の `LSUIElement=true` という設定によるもので、メニューバー常駐型の macOS アプリの典型的な構成です(詳細は Part III で扱います)。

> **NOTE**
> 初回起動時に「画面収録」の許可が求められます。これは ZoomacIt が画面拡大機能で `ScreenCaptureKit` API を使うために必要です。「システム設定 → プライバシーとセキュリティ → 画面収録」で許可してください。許可後はアプリを再起動する必要があります。

## ビルド出力先

`make build` を実行すると、リポジトリ直下の `build/` ディレクトリに成果物が出力されます。

```
build/
└── Build/
    └── Products/
        ├── Debug/
        │   └── ZoomacIt.app       ← Debug ビルドの成果物
        └── Release/
            └── ZoomacIt.app       ← Release ビルドの成果物
```

`make run` は内部的に `open build/Build/Products/Debug/ZoomacIt.app` を実行しています。Java で言えば `java -jar target/myapp.jar` 相当です。

## .env ファイル(配布時のみ)

リポジトリ直下に `.env` を置くと、Makefile がそれを読み取ります。これは notarization に必要な Apple ID / Team ID / App-specific Password を環境変数として渡すためのもので、**学習中は不要** です。テンプレートは [`.env.example`](../../.env.example) にあります。

## 開発サイクルのまとめ

学習を進めるうえで、覚えておくべきコマンドは次の 3 つだけです。

```bash
make build    # コードを書いたらまずこれ
make test    # テストを足したり既存テストの動作確認
make run      # 実際にアプリを動かして確認
```

Xcode を開いて GUI でビルドする方法もありますが、本教材では原則 CLI で進めます。理由は、ターミナルでのフィードバックループが速く、エラーメッセージが正確に追えるためです。Xcode の GUI が必要になるのは、ビジュアルデバッガで View 階層を覗くときくらいです。

---

## 次に読む章

→ [03. A Swift Tour(ZoomacIt 版)](./03-swift-tour.md)
