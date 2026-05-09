---
title: ZoomacIt で学ぶ Swift ハンズオン — 実装プラン
status: plan
audience: Java 経験者 / Swift 初学者
generated: 2026-05-09
---

# ZoomacIt で学ぶ Swift ハンズオン — 実装プラン

## 0. プランの目的とゴール

このドキュメントは、リポジトリ `ZoomacIt`(macOS メニューバーアプリ、Windows ZoomIt クローン)を **Swift 学習教材** として再構成するための **実装プラン** である。チュートリアル本体ではなく、「どう作るか」の設計図にあたる。

### 教材としてのゴール

1. **Swift の基礎を体系的に学べる**(Apple 公式 *The Swift Programming Language* の目次に準拠)
2. **すべての文法項目が ZoomacIt の実コードに紐付いている**(「教科書のオモチャ例」ではなく、実プロダクトの該当箇所を見せる)
3. **Java 経験者向け**にチューニング(共通する文法はチートシート、Swift 特有のものは丁寧に解説)
4. **読みやすい説明 + コードスニペット** の構成(Apple 公式ドキュメントの語り口を踏襲)

### 学習者像 (前提)

- Java を業務レベルで理解している(クラス、継承、インターフェース、ジェネリクス、ラムダ等は既知)
- macOS 開発・Xcode・AppKit/SwiftUI は未経験
- ゴールは「ZoomacIt のコードを自力で読み・改修できる」レベル

---

## 1. ZoomacIt コードベースの教材的価値(調査サマリ)

サブエージェントによる調査で確認できた事実を整理する。これが「なぜこのリポジトリを教材に使えるか」の根拠になる。

### 1.1 Swift 言語機能の網羅性

| Swift 機能 | 教材として使える実装場所 |
|---|---|
| Enum + raw values + `CaseIterable` + `Sendable` | `Models/Settings.swift` の `PenColor` / `FontWeightOption` |
| Optional + 安全アンラップ + `??` | `Settings.swift`(`PenColor(rawValue:) ?? .red`) |
| Computed property | `DrawingState.swift`(`var currentNSColor: NSColor`) |
| Struct(値型)vs Class(参照型) | `Stroke.swift`(struct) vs `DrawingState.swift`(final class) |
| Closure + `[weak self]` capture list | `App/AppDelegate.swift` のホットキーハンドラ |
| `@escaping` クロージャプロパティ | `Core/HotkeyManager.swift`(`var onZoomHotkey: (() -> Void)?`) |
| Carbon C コールバック / `@convention(c)` / `UnsafeMutableRawPointer` | `Core/HotkeyManager.swift`(Swift から C への橋渡しの実例) |
| async / await + `@MainActor` + `Task` | `Overlay/BreakTimerWindowController.swift`、`StillZoomWindowController.swift` |
| `@unchecked Sendable` | `Settings.swift`、`HotkeyManager.swift`(Swift 6 strict concurrency 下での現実解) |
| Extension | `Utilities/CGContext+Extensions.swift`、`NSScreen+Extensions.swift` |
| Inheritance + `override` | `Draw/DrawingCanvasView.swift`(`NSView` サブクラス) |
| Pure function + 単体テスト | `Overlay/ZoomMath.swift` + `ZoomMathTests.swift` |
| Protocol 適合 | `NSApplicationDelegate`、`CaseIterable`、`Sendable` |
| Error handling(`try await ... throws`) | `BreakTimerWindowController.swift` の `SCShareableContent.excludingDesktop...` |

### 1.2 設計ドキュメントの充実

`design/` 配下に 6 本(`ARCHITECTURE.md`, `CONCEPT.md`, `Draw.md`, `Zoom.md`, `BreakTimer.md`, `Spotlight.md`)。実装と同期しており、「なぜこう設計したか」を引用できる。

### 1.3 教材として注意すべき点

- **ファイル規模に偏りあり**: `DrawingCanvasView.swift` が 766 行と巨大。初学者にいきなり読ませない。基礎章では `Stroke.swift`(52 行)や `ZoomMath.swift`(60 行)など小さいファイルを選ぶ。
- **Carbon API・C 橋渡し**は **応用編** に隔離。基礎の解説で混ぜない。
- **macOS 26+ / Swift 6.0** 前提。古い情報源を引かないよう、Apple 公式 + Context7 MCP で随時裏取りする。

---

## 2. 教材全体の構成(章立て)

Apple 公式 *The Swift Programming Language* の目次に準拠しつつ、Java 経験者向けに **チートシート章** と **Swift 特有・丁寧解説章** を分離する。

### 凡例

- 🟢 **チートシート章**: Java と本質的に同じ概念。表 + 短いコードで一気通貫。
- 🟡 **丁寧章**: Swift 特有 or Java と挙動が違うもの。文章で丁寧に + 実コード引用。
- 🔴 **応用章**: macOS / AppKit / 並行性 / C 橋渡しなど、Swift を超えた領域。

### 全章一覧

| # | 章タイトル | 種別 | 主な引用ファイル |
|---|---|---|---|
| **Part I — Welcome to Swift** | | | |
| 01 | Swift とは / なぜ ZoomacIt で学ぶか | 🟡 | (なし、概論) |
| 02 | 環境構築 — Xcode・xcodegen・make | 🟡 | `Makefile`, `src/project.yml` |
| 03 | A Swift Tour(ZoomacIt 版) | 🟡 | `main.swift`, `Stroke.swift` |
| **Part II — Language Guide(基礎)** | | | |
| 04 | The Basics(変数・型・Optional 入門) | 🟢+🟡 | `DrawingState.swift` |
| 05 | Basic Operators | 🟢 | `ZoomMath.swift` |
| 06 | Strings and Characters | 🟢+🟡 | `Settings.swift`(文字列補間) |
| 07 | Collection Types | 🟢 | `DrawingCanvasView.swift`(`[CGPoint]`) |
| 08 | Control Flow | 🟢+🟡 | `DrawingState.swift`(`switch`) |
| 09 | Functions | 🟢+🟡 | `ZoomMath.swift`(引数ラベル) |
| 10 | Closures | 🟡 | `AppDelegate.swift`、`HotkeyManager.swift` |
| 11 | Enumerations | 🟡 | `PenColor`, `FontWeightOption`, `BackgroundMode` |
| 12 | Structures and Classes | 🟡 | `Stroke.swift` vs `DrawingState.swift` |
| 13 | Properties | 🟡 | `DrawingState.swift`(computed)、`Settings.swift`(observer 相当) |
| 14 | Methods | 🟢+🟡 | `Settings.swift`(static)、`DrawingState.swift`(mutating 不要例) |
| 15 | Subscripts | 🟢 | (該当少、`Dictionary` 経由で簡潔に) |
| 16 | Inheritance | 🟢+🟡 | `DrawingCanvasView.swift`(`NSView` 派生) |
| 17 | Initialization | 🟡 | `Stroke.swift`(memberwise)、`Settings.swift`(`private init`) |
| 18 | Deinitialization | 🟡 | `OverlayWindowController.swift`(リソース解放) |
| 19 | Optional Chaining | 🟡 | `HotkeyManager.swift`(`onZoomHotkey?()`) |
| 20 | Error Handling | 🟡 | `BreakTimerWindowController.swift`(`try await`) |
| 21 | Concurrency | 🔴 | `BreakTimerWindowController.swift`、`@MainActor`、`Task`、`Sendable` |
| 22 | Type Casting | 🟢 | `AppDelegate.swift` |
| 23 | Nested Types | 🟢 | `Settings.Keys`(nested enum) |
| 24 | Extensions | 🟡 | `CGContext+Extensions.swift` |
| 25 | Protocols | 🟡 | `NSApplicationDelegate` 適合、`CaseIterable` |
| 26 | Generics | 🟢+🟡 | (リポジトリ内例少 → 補助例で `Array<T>` を解説) |
| 27 | Opaque Types | 🟡 | (SwiftUI `some View` を `BreakTimerView.swift` で) |
| 28 | Automatic Reference Counting | 🟡 | `[weak self]` capture(`AppDelegate.swift`) |
| 29 | Memory Safety | 🟡 | (概念中心、`inout` の競合説明) |
| 30 | Access Control | 🟡 | `Settings.swift`(`final class`, `private let`) |
| 31 | Advanced Operators | 🟢 | (補助例中心) |
| **Part III — ZoomacIt 応用編(macOS / 実装パターン)** | | | |
| 32 | AppKit と SwiftUI の混在 | 🔴 | `SettingsView.swift` ↔ `DrawingCanvasView.swift` |
| 33 | NSView を継承して描画する | 🔴 | `DrawingCanvasView.swift` |
| 34 | Carbon API と C 橋渡し | 🔴 | `HotkeyManager.swift` |
| 35 | ScreenCaptureKit と async/await | 🔴 | `BreakTimerWindowController.swift` |
| 36 | UserDefaults とシングルトン設定 | 🔴 | `Settings.swift` |
| 37 | XCTest による単体テスト | 🔴 | `ZoomMathTests.swift` |
| **Part IV — ハンズオン(自分の手でビルド)** | | | |
| 38 | ハンズオン 1: 新しいペン色を追加する | 🟢 | `PenColor` enum 拡張 |
| 39 | ハンズオン 2: 新しいシェイプ(三角形)を追加 | 🟡 | `ShapeRenderer.swift` |
| 40 | ハンズオン 3: 新しいホットキーアクション | 🟡 | `HotkeyManager` + `AppDelegate` |
| 41 | ハンズオン 4: 設定タブを 1 つ増やす | 🟡 | `SettingsView.swift` + 新 Tab |
| 42 | ハンズオン 5: 新機能 “Magnifier Lens” を実装 | 🔴 | 全レイヤー横断 |

---

## 3. 各章の詳細設計テンプレート

すべての章は以下の固定構造で書く(Apple 公式の語り口に倣う)。

```
# 章タイトル

## この章で学ぶこと
- 箇条書き 3〜5 行

## (Java 経験者向け)チートシート     ← 🟢 章のみ。1ページ以内の早見表
| Java | Swift | 補足 |
|---|---|---|
| ... | ... | ... |

## 解説本文                              ← 🟡🔴 章のみ。文章中心
段落で丁寧に説明。Apple 公式ドキュメント風に
「○○ は △△ である。これは□□のために必要となる。」
というフォーマルな書き口を維持する。
段落のあとにコードスニペット 1 つ、その下に
何が起きているかの 1 段落解説を続ける。

```swift
// 短い擬似コード or ZoomacIt からの最小抜粋
```

## ZoomacIt の実コードを読む
> 引用元: `src/ZoomacIt/Models/Settings.swift:120-145`

```swift
// 実ファイルからのコピー(必要なら省略コメント `// ...` を入れる)
```

この実装が章テーマの何を体現しているかを 2〜3 段落で説明する。

## ハンズオン(任意、章末ミニ課題)
- 「○○ を変更してビルドしてみよう」レベルの 5〜15 分課題
- 答え合わせのセクションは折りたたみで(VitePress なら `<details>`)
```

### 3.1 文章のトーン

ユーザーが添付した Apple 公式『The Swift Programming Language』の Inheritance 章を参考にする:

- **能動態 + 説明的**: 「クラスは ... を継承できる。継承するクラスを *サブクラス* と呼び、継承元を *スーパークラス* と呼ぶ。」
- **専門用語は初出で *イタリック* + 定義**
- **NOTE ブロック**で重要な脱線を分離
- **コードはコンパイル可能な完全形** で示す(部分抜粋には省略コメントを入れる)
- 1 段落 = 1 アイデア。長文段落で詰め込まない

### 3.2 コードスニペットの方針

- **教材専用の最小例**(20 行以内)→ 概念理解
- **ZoomacIt 実コードからの抜粋** → 実プロダクトでの使われ方理解

両方をセットで提示する。実コード抜粋には必ず **ファイルパス + 行番号** を `> 引用元:` で書く。

---

## 4. 章ごとの設計指針(主要章のみ・実装方針メモ)

> **注**: このセクションは「実装するときに迷わないための指針」であり、実物のチュートリアル本文・コード例ではない。完成形のドラフトは別途、各章ファイルとして作成する。

ここでは「特に設計の判断が必要な章」だけ、執筆者(または執筆エージェント)が押さえるべきポイントを列挙する。残りの章は §3 のテンプレートにそのまま流し込めば書ける。

### Ch04. The Basics(🟢+🟡)

- **チートシート部** — `var`/`let`/型注釈/`Optional` のシンタックスを Java 対応表で並べる。本文ボリュームは 1 ページ未満。
- **丁寧解説部** — 以下 3 点は Swift 特有なので、概念背景・なぜそう設計されたかを段落で解説:
  - `let` がデフォルトという哲学(Java の `final` 不要化)
  - Optional は型システムによる null 安全(Java `Optional<T>` クラスとの違い、`?` / `!` / `??` の使い分け)
  - 型推論の射程(関数戻り値・クロージャ・タプルにも効く)
- **引用候補**: `Models/DrawingState.swift`(`var penWidth` / `let` 定数 / Optional プロパティが揃っている)
- **書き方の注意**: Optional はこの章では「導入のみ」。アンラップのバリエーション全体は Ch19 で深掘る。

### Ch10. Closures(🟡)

- **段階構成**: ①基本構文 → ②末尾クロージャ → ③`@escaping` → ④capture list の順に積み上げる。
- **Java 比較ポイント**: ラムダ式と似ているが、`[weak self]` の存在が決定的に違う。これは ARC(Ch28)と密接に関わるため、forward reference で「あとで詳述」と明示する。
- **引用候補**: `App/AppDelegate.swift`(ホットキーハンドラの `[weak self]`)、`Core/HotkeyManager.swift`(クロージャプロパティ `var onZoomHotkey: (() -> Void)?`)
- **書き方の注意**: メモリ管理の話を深掘りしすぎない。「循環参照を防ぐためにこう書く」までで止め、深い議論は Ch28 に移譲する。

### Ch12. Structures and Classes(🟡)

- **教材としての中心テーマ**: 「Java 経験者にとって最大の概念差」として位置づけ、章を太めに書く。
- **書き分けの軸**:
  - struct はコピー(値型)、class は参照共有
  - 「struct を優先、class は理由があるとき」という Swift コミュニティの規範
  - class を選ぶべき場面の典型(identity 必要 / AppKit 継承 / `deinit` 必要 / Objective-C 互換)
- **引用候補(対比構造で見せる)**:
  - struct 例: `Models/Stroke.swift`(描画ストロークの値型データ)
  - class 例: `Models/DrawingState.swift`(複数 View で共有される状態管理クラス)
- **書き方の注意**: 「なぜ Stroke は struct で DrawingState は class なのか」という設問を立て、ZoomacIt の設計判断を解説に組み込む。これがそのまま Java 経験者への一番のメッセージになる。

### Ch21. Concurrency(🔴)

- **位置づけ**: Swift 6 の strict concurrency は、2026 年時点で Swift 学習における最重要トピック。Java の `synchronized` / `Thread` / `CompletableFuture` とはモデルが違うため、対応表よりも概念図(actor 隔離・Sendable 境界)の図解を優先する。
- **解説の柱(順番固定)**:
  1. `async`/`await` の基本(Java `CompletableFuture` との対比)
  2. Actor モデル(`actor` キーワード)
  3. `@MainActor` による UI スレッド隔離(Swing EDT を「言語化したもの」と説明すると刺さる)
  4. `Sendable` プロトコル
  5. `@unchecked Sendable` の現実解(Carbon・UserDefaults などレガシー資産との接続)
- **引用候補**: `Overlay/BreakTimerWindowController.swift`(`async`/`await` + `@MainActor` + `Task`)、`Models/Settings.swift`(`@unchecked Sendable`)
- **書き方の注意**: ZoomacIt の `@unchecked Sendable` 採用は「ベストプラクティス」というより「現実解」。誤解を招かないよう、必ず NOTE ブロックで「本来は actor 化や `Sendable` 適合が望ましいが、ここでは ○○ という理由で `@unchecked` を選んでいる」と添える。

---

## 5. ハンズオン課題(Part IV)の設計方針

> **注**: 各ハンズオンの「具体的な手順書」は実装フェーズで起こす。ここでは課題の **狙い・難易度・触る範囲** だけを定義する。

ハンズオンは「Part II の文法を、Part III の応用を、Part IV で手を動かして統合する」ピラミッドの頂点。**易→難** の階段になるよう難易度を設計する。

| # | タイトル | 難易度 | 学習狙い | 触るレイヤー |
|---|---|---|---|---|
| Ch38 | 新しいペン色を追加 | 🟢 易 | Enum + raw values + computed property + テスト追加サイクル | Models, Settings |
| Ch39 | 新しいシェイプ(三角形)を追加 | 🟡 中 | enum + switch の網羅性、関数追加、NSBezierPath | Models, Draw |
| Ch40 | 新しいホットキーアクション | 🟡 中 | `@escaping` クロージャプロパティ、シングルトン経由設定読み出し | Core, App, Settings |
| Ch41 | 設定タブを 1 つ増やす | 🟡 中 | SwiftUI の `View` protocol、`@AppStorage`、opaque return type | Settings |
| Ch42 | Magnifier Lens 機能(卒業課題) | 🔴 難 | 全レイヤー横断、`@MainActor`、ScreenCaptureKit、NSWindow 制御 | 全層 |

### 各ハンズオンの設計指針

**Ch38(易)** — 既存の `enum PenColor` を 1 行拡張するだけで効果が出る、最小サイクルで Swift の楽しさを伝える課題にする。テスト追加までを含めて 15 分で終わるサイズに保つ。

**Ch39(中)** — Swift の `switch` 網羅性チェックがコンパイラに守られていることを、わざと 1 ケース忘れさせてエラーを体験してもらうステップを入れる。Swift の型安全さを実感してもらう仕掛け。

**Ch40(中)** — クロージャプロパティを増やす作業を通じて、「ホットキー → クロージャ呼び出し → 副作用」というアーキの背骨を読み解く回。Carbon API の中身は触らせない(それは Part III)。

**Ch41(中)** — SwiftUI 初登場の本格演習。`@AppStorage` と `@State` の違いに気づかせる構成にする。

**Ch42(難・卒業課題)** — 仕様だけ与えて自力で設計させる。教材で先回りして手取り足取り書かない。**仕様**(`⌃4` で起動するルーペ、マウス周辺 200×200pt を 4 倍ズームして円形ウィンドウ、ESC で終了)を提示し、解答例は別ブランチに置く方針。

### ハンズオン共通フォーマット(実装時に使うテンプレート)

```
# Ch{N}. {タイトル}

## 課題概要
1〜2 段落でゴールを記述。

## 前提
- 完了しておくべき章のリスト
- 動作確認に必要なコマンド (`make build` 等)

## 学習狙い
箇条書き 3〜5 項目

## ステップ
1. ...
2. ...
(各ステップにヒント、「失敗例」サブセクションを併記)

## 動作確認
- ビルド / 実行 / 期待挙動

## 解答例
<details><summary>クリックで展開</summary>
... 完全コード例
</details>

## さらにチャレンジ
発展課題 1〜2 つ
```

---

## 6. 制作ワークフロー(サブエージェント活用方針)

ユーザー要望「**なるべくサブエージェントを使う**」に応えて、各章の執筆を並列化する。

### 6.1 章のフェーズ分け

各章ごとに **3 フェーズ** で進める:

| フェーズ | 担当 | 成果物 |
|---|---|---|
| **F1. 調査** | `Explore` サブエージェント | 該当 Swift 機能が ZoomacIt のどこで使われているかのマッピング、引用すべき行番号リスト |
| **F2. 執筆** | `general-purpose` サブエージェント | テンプレート(§3)に沿った markdown 章ドラフト |
| **F3. レビュー** | メイン Claude(または別 `general-purpose`) | コード抜粋の事実確認、Apple 公式との整合性、Java 比較の正しさ |

### 6.2 並列化の単位

**「章」を独立単位として並列実行**できる。たとえば Part II の Ch04〜Ch11 は依存関係が薄いため、F1(調査)を **8 章ぶん同時に** 走らせて構わない。F2(執筆)は調査完了後にこれもまた並列で走らせる。

```
[並列] Ch04 調査 │ Ch05 調査 │ ... │ Ch11 調査     ← Explore × 8
                 ↓                ↓
[並列] Ch04 執筆 │ Ch05 執筆 │ ... │ Ch11 執筆     ← general-purpose × 8
                 ↓                ↓
[逐次] レビュー → 修正                            ← メイン Claude
```

### 6.3 サブエージェント呼び出し時のプロンプト雛形

調査エージェント向け(F1):

> ZoomacIt(/Users/tsubasa/git/github.com/07JP27/ZoomacIt)のコードベースで、Swift 機能 **「{機能名}」** が使われている箇所を全部リストアップしてほしい。各箇所について「ファイルパス:行番号」「使われ方の 1 行説明」「教材として引用するのに最も適しているか(Yes/No と理由)」を出してほしい。出力は markdown 表で、500 語以内。

執筆エージェント向け(F2):

> ZoomacIt 教材の Ch{N}「{章タイトル}」を執筆してほしい。テンプレートは learning-swift-plan.md の §3 を参照。前提: 学習者は Java 経験者。「チートシート部分」は表で簡潔に、「Swift 特有部分」は段落で丁寧に。実コード引用は「{ファイルパス:行番号}」を必ず明記。出力は完成 markdown ファイル(2000〜4000 語)。

### 6.4 メイン Claude の責務

- プラン全体(本ファイル)の維持・更新
- サブエージェントへのタスク分配と統合
- 章間の整合性チェック(用語ブレ、forward reference の妥当性)
- 最終的なディレクトリ構成と目次の編集

---

## 7. 出力ファイル構成

§10.1 に確定構成を記載(`learning-swift/` 独立ディレクトリ + `answers/` + `samples/`)。重複を避けるためここでは要点のみ:

- ルート: `learning-swift/`(リポジトリ直下)
- 4 つの Part をディレクトリ分割
- `answers/` にハンズオン解答例
- `samples/` に教材専用補助コード(Generics 章ほか)

---

## 8. 実装スケジュール(目安)

| マイルストーン | 内容 | 想定セッション数 |
|---|---|---|
| M1 | プラン承認 + 出力ディレクトリ確定 + Ch01〜03(導入)執筆 | 1 |
| M2 | Part II 前半(Ch04〜15)を 3 章ずつ並列執筆 + レビュー | 4 |
| M3 | Part II 後半(Ch16〜31)を 3 章ずつ並列執筆 + レビュー | 5 |
| M4 | Part III(Ch32〜37)応用編 | 2 |
| M5 | Part IV(Ch38〜42)ハンズオン + 動作確認 | 2 |
| M6 | 全体レビュー・用語統一・索引作成 | 1 |

**合計**: 約 15 セッション。並列化次第でさらに圧縮可能。

---

## 9. 品質基準(Definition of Done)

各章は以下を満たすこと:

- [ ] テンプレート(§3)の構造に従っている
- [ ] **実コード引用が最低 1 箇所**、ファイルパス + 行番号付き
- [ ] **Java 比較**が(該当章では)1 箇所以上明記されている
- [ ] **Swift 特有のポイント**が太字 or NOTE ブロックで強調されている
- [ ] コードスニペットがすべて Swift 6.0 でコンパイル可能(macOS 26 想定)
- [ ] 章末に「次に読む章」リンクがある
- [ ] 画像が必要な箇所(アーキ図など)は ASCII art または mermaid で代替

---

## 10. 決定事項(2026-05-09 合意)

執筆開始前のオープン論点について、以下のとおり決定。

| # | 論点 | 決定 | 補足 |
|---|---|---|---|
| 1 | 出力先 | **`learning-swift/` 独立ディレクトリ** | VitePress `docs/`(製品ドキュメント)とは混ぜない。GitHub 上で素の markdown として読む前提 |
| 2 | 言語 | **日本語のみ** | i18n は当面考えない。将来必要になれば後付け |
| 3 | Generics 章の補助サンプル | **可** | リポジトリ内に良い実例が薄いため、教材専用の最小コード例を別ファイルで作って良い。置き場所は §10.1 参照 |
| 4 | ハンズオン解答例の置き場所 | **`learning-swift/answers/` ディレクトリ** | 章内の折りたたみではなく、独立ファイルとして分離。学習者が答えを見ずに取り組めるようにする |
| 5 | VitePress 統合 | **対象外**(論点 1 の決定により消失) | — |

### 10.1 確定したディレクトリ構成

§7 の構成案を、上記決定に合わせて確定する:

```
learning-swift/
├── README.md                          # 入口・全体目次・読む順序
├── 00-prerequisites.md                # 環境構築チェックリスト
├── part1-welcome/
│   ├── 01-what-is-swift.md
│   ├── 02-environment.md
│   └── 03-swift-tour.md
├── part2-language-guide/
│   ├── 04-the-basics.md
│   ├── ...
│   └── 31-advanced-operators.md
├── part3-zoomacit-deep-dive/
│   ├── 32-appkit-vs-swiftui.md
│   ├── ...
│   └── 37-xctest.md
├── part4-handson/
│   ├── 38-add-pen-color.md
│   ├── 39-add-shape.md
│   ├── 40-add-hotkey.md
│   ├── 41-add-settings-tab.md
│   └── 42-magnifier-lens.md
├── answers/                           # 論点 4 の決定
│   ├── 38-add-pen-color/              # 各ハンズオン 1 ディレクトリ
│   │   ├── README.md                  # 解答の解説
│   │   └── diff.patch                 # 実コードへの差分(または完成コード)
│   ├── 39-add-shape/
│   ├── 40-add-hotkey/
│   ├── 41-add-settings-tab/
│   └── 42-magnifier-lens/
└── samples/                           # 論点 3 の決定。教材専用の補助コード
    └── ch26-generics/                 # Generics 章で使うミニサンプル
        └── *.swift
```

### 10.2 Generics 章(Ch26)の補助サンプル方針

リポジトリ本体に Generics の良い実例が薄いため、`learning-swift/samples/ch26-generics/` 配下に **教材専用の Swift ファイル** を置く。方針:

- **コンパイル可能な単独 `.swift` ファイル** とする(Xcode プロジェクトに組み込まない)
- 解説は章本文(`part2-language-guide/26-generics.md`)に書き、サンプルファイルは「補助参照」として位置づける
- 内容は `Stack<Element>` `Queue<T>` のような **Swift Standard Library で見るパターンのミニ再実装** を予定。ZoomacIt 本体の流儀から逸脱しない範囲で

### 10.3 ハンズオン解答例の運用方針

`learning-swift/answers/{章番号-スラッグ}/` 配下に以下を置く:

- `README.md` — 解答の解説(なぜそう書いたか、別解の議論)
- 完成コード or `diff.patch`(実プロジェクトへの差分)

学習者がハンズオン本文だけ読んで自力で取り組めるよう、本文側からは `answers/` への直接リンクは控えめにする(ハンズオン末尾の「解答を見る」セクションからのみリンク)。
