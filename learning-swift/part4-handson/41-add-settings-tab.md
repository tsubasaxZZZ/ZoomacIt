# Ch41. ハンズオン 4: 設定タブを 1 つ増やす

## 課題概要

ZoomacIt の設定ウィンドウ (`SettingsView`) には現在 4 つのタブ — General / Draw / Zoom / Break Timer — が並んでいます。本ハンズオンでは、これらに加えて **「Advanced」(詳細設定)** タブを 1 つ新規追加します。

Advanced タブには次の 2 項目を配置します。

| 項目 | UI コントロール | 永続化型 |
| --- | --- | --- |
| Log Level | `Picker`（Info / Debug / Verbose の 3 段階） | `String`（enum の rawValue） |
| Stroke History Limit | `Stepper`（5〜100 段、刻み幅 5） | `Int` |

(オプション) 設定ファイルの保存先パス (`~/Library/Preferences/...`) を `Text` で読み取り専用表示する欄も追加できます。

これは ZoomacIt の機能を増やす実装ではありません。**SwiftUI で「ユーザー設定 UI を 1 枚増やす」一連の作業を体で覚えるための演習** です。Settings の 5 層 (Keys → enum → register → computed property → SwiftUI View) を一気通貫で書きます。

## 前提

このハンズオンに着手する前に、次の章を読んでおいてください。

| 章 | 押さえておきたいトピック |
| --- | --- |
| Ch12 Structures and Classes | `struct` を「軽量な値型のかたまり」として書く感覚。SwiftUI の `View` は基本すべて `struct` です |
| Ch25 Protocols | `View` プロトコルの存在と、適合 (`conformance`) する側に何が要求されるか |
| Ch27 Opaque Types | `var body: some View` の `some View` がなぜ必要か |
| Ch36 UserDefaults と @AppStorage | `Settings` シングルトンの構造と、SwiftUI の property wrapper による双方向バインディング |

特に Ch36 で読んだ `Settings.swift` の構造 — 「Keys → register → computed property」 — を実際に手で延長する演習なので、Ch36 の内容を頭に入れた状態で進めてください。

## 学習狙い

このハンズオンを終えると、次のことが手に馴染んだ状態になります。

1. **`struct` で SwiftUI View を組む感覚** — クラスではなく値型として宣言型 UI を記述する
2. **`@AppStorage` の使い分け** — `String` / `Int` / `Bool` / `Double` を直接、enum は rawValue 経由で
3. **`Binding` のラップパターン** — enum を `Picker` の `selection:` に渡すための変換層 (`DrawTab.swift` の `penColor` プロパティが手本)
4. **`Form` と `Section` で設定 UI をグループ化** する作法
5. **`TabView` に新しい `tabItem` を追加する** ときに変更すべきファイルと行
6. **xcodegen と project.yml** の関係 — 新規 `.swift` ファイルを追加した後にどうプロジェクトファイルへ反映するか

`@State` (一時的なメモリ内状態) と `@AppStorage` (UserDefaults に永続化) の違いも、書き比べてみると理解が深まります。

## ステップ

### Step 1. Settings.swift の Keys に 2 つ追加

`src/ZoomacIt/Models/Settings.swift` の `enum Keys` (59 行目あたり) は、UserDefaults のキー文字列を 1 箇所に集めるための名前空間です。Break Timer の最後 (90 行目あたり) に、次の 2 行を追加します。

```swift
// Advanced
static let logLevel = "logLevel"
static let strokeHistoryLimit = "strokeHistoryLimit"
```

ここで「マジックストリング」を直接 `@AppStorage("logLevel")` のように書かないのは、タイポを防ぎ、後でリネームしやすくするための設計判断です。Ch36 の冒頭で扱ったポイントを思い出してください。

### Step 2. LogLevel enum を Settings.swift に追加

`Settings.swift` の冒頭付近、`FontWeightOption` enum (5 行目あたり) の **すぐ下** あたりに、新しい enum を 1 つ宣言します。

```swift
enum LogLevel: String, CaseIterable, Sendable {
    case info, debug, verbose
}
```

`String` raw type、`CaseIterable`、`Sendable` の 3 つに適合させる理由は次の通りです。

- `String` raw type — `UserDefaults` には `String` で保存する。`enum LogLevel: String` と書くと `info.rawValue == "info"` が自動生成される
- `CaseIterable` — `LogLevel.allCases` を `Picker` の `ForEach` に渡せるようにする
- `Sendable` — Swift 6 の strict concurrency 環境下で、複数アクターをまたいで値を渡せることをコンパイラに約束する

これは `PenColor` (`DrawingState.swift`) と `FontWeightOption` (`Settings.swift`) で確立されたパターンの繰り返しです。

### Step 3. registerDefaults() にデフォルト値を追加

同じく `Settings.swift` の `registerDefaults()` メソッド (95 行目あたり) の `defaults.register(defaults: [...])` 配列の末尾に、次の 2 行を追加します。

```swift
// Advanced
Keys.logLevel: LogLevel.info.rawValue,
Keys.strokeHistoryLimit: 30
```

`register(defaults:)` の役割は **「ユーザーが一度も変更していないキーに対する暗黙のデフォルト」** を登録することです。実際の plist ファイルには書き込まれず、`UserDefaults.standard.string(forKey:)` で読み出した時にフォールバックとして返されます。Ch36 の「register vs set の違い」を確認しておくと安心です。

### Step 4. 計算プロパティを Settings.swift に追加

`Settings.swift` の Break Timer セクションの後 (250 行目あたり) に、新しい `MARK` 区切りで次のプロパティを追加します。

```swift
// MARK: - Advanced

var logLevel: LogLevel {
    get { LogLevel(rawValue: defaults.string(forKey: Keys.logLevel) ?? "") ?? .info }
    set { defaults.set(newValue.rawValue, forKey: Keys.logLevel) }
}

var strokeHistoryLimit: Int {
    get { defaults.integer(forKey: Keys.strokeHistoryLimit) }
    set { defaults.set(newValue, forKey: Keys.strokeHistoryLimit) }
}
```

これによって、SwiftUI 経由ではなく非 SwiftUI なコード (例: `StrokeManager` の中) からも `Settings.shared.strokeHistoryLimit` のように型安全にアクセスできます。`@AppStorage` だけで済ませるとこの「アプリ内部からのアクセス層」が無くなることを覚えておいてください。

合わせて、`resetToDefaults()` (255 行目あたり) の `allKeys` 配列にも、新しい 2 つのキーを追加しておきます。これを忘れると "Reset to Defaults" ボタンを押しても Advanced タブの値だけが残ってしまうバグになります。

### Step 5. AdvancedTab.swift を新規作成

`src/ZoomacIt/Settings/AdvancedTab.swift` を新規ファイルとして作成します。骨格は `ZoomTab.swift` (シンプル) と `DrawTab.swift` (Picker のバインディング) を組み合わせた形です。

完成形は解答例を参照してください。書く順序の目安は次のとおりです。

1. `import SwiftUI`
2. `struct AdvancedTab: View { ... }` を宣言
3. `@AppStorage` プロパティを 2 つ宣言 (`logLevelRaw: String`, `strokeHistoryLimit: Int`)
4. enum 型 `Settings.LogLevel` と `String` を行き来する `Binding<Settings.LogLevel>` を計算プロパティで作る
5. `var body: some View` の中で `Form` → `Section` → `Picker` / `Stepper` を組む
6. `.formStyle(.grouped)` を適用

`DrawTab.swift` の 13–18 行目 `private var penColor: Binding<PenColor>` がそのままお手本になります。「`@AppStorage` で保存している `String` 値を、UI 側では強い型 `enum` として扱いたい」という二段構えのバインディングはこのパターンが定石です。

### Step 6. SettingsView.swift の TabView に Advanced を追加

`src/ZoomacIt/Settings/SettingsView.swift` の `TabView` (10 行目) の中に、4 番目のタブ `BreakTimerTab` の後ろに 1 ブロック追加します。

```swift
AdvancedTab()
    .tabItem { Text("Advanced") }
```

なお既存タブは `Text("...")` だけで `tabItem` を作っていますが、本ハンズオンでは見栄えを少し良くするため `Label("Advanced", systemImage: "gearshape.2")` を使ってもかまいません (SF Symbols)。両方の書き方をコメントで示しておくのも良い練習です。

### Step 7. xcodegen でプロジェクトを再生成

ZoomacIt の `.xcodeproj` は xcodegen が `src/project.yml` から生成しています。`project.yml` の `sources:` は `path: ZoomacIt` というディレクトリ指定で書かれているので、**ディレクトリの中に新規ファイルを置けば自動的に拾われる** 設計です。それでも安全のために、新規ファイル追加の直後は次のコマンドで再生成しておきます。

```bash
make generate
```

これを忘れると、`.swift` ファイルがディスクに存在するのに Xcode のターゲットメンバーシップに含まれず、ビルド対象から漏れる事故が起きえます。

### Step 8. ビルドと動作確認

```bash
make build
make run
```

ビルドが通ったらメニューバーから "Settings…" を開き、Advanced タブが追加されていることを目視確認します。

## 動作確認

次の 4 点が満たされていれば合格です。

- [ ] `make build` がエラー・警告なく通る
- [ ] 設定ウィンドウを開くと **Advanced** タブが表示されている
- [ ] Log Level の Picker を変更すると、アプリを再起動しても変更が保持される
- [ ] Stroke History Limit の Stepper で値を増減でき、これも再起動後も保持される

UserDefaults への保存を直接確認したい場合、ターミナルから次のコマンドが使えます。

```bash
defaults read com.x07jp27.ZoomacIt logLevel
defaults read com.x07jp27.ZoomacIt strokeHistoryLimit
```

(`com.x07jp27.ZoomacIt` は `Info.plist` の `CFBundleIdentifier` を確認してください)

## 解答例

`learning-swift/answers/41-add-settings-tab/` にあります。`Settings.swift` への diff、`AdvancedTab.swift` の完成コード、`SettingsView.swift` への diff の 3 つに分けて掲載しています。

実装に詰まったら見てかまいませんが、まずは `DrawTab.swift` の `penColor: Binding<PenColor>` をなぞって自力で書き上げることをおすすめします。SwiftUI の双方向バインディングは「コードを写経して動かす」のが最短ルートです。

## さらにチャレンジ

慣れてきたら次の応用に進んでみてください。

1. **ログレベルを実際に NSLog に反映させる**
   ZoomacIt 内の `NSLog(...)` 呼び出しのうち冗長なものを `if Settings.shared.logLevel == .verbose { NSLog(...) }` などでガードする。`func vlog(_ message: String, level: LogLevel)` のようなヘルパーを `Utilities/` に切り出すと綺麗にまとまります。
2. **Stroke History Limit を StrokeManager に反映**
   `src/ZoomacIt/Draw/StrokeManager.swift` を読み、ハードコードされている履歴段数 (現在 30) を `Settings.shared.strokeHistoryLimit` に置き換える。テスト (`StrokeManagerTests.swift`) を更新するところまでがゴールです。
3. **Color Picker を追加**
   SwiftUI の `ColorPicker` は `NSColor` を直接扱えないので、`PenColor` enum を経由して保存するか、別途 `Codable` な `RGBA` 構造体を用意する必要があります。Ch36 で扱った「`UserDefaults` に保存できる型の制約」を踏まえて設計してみてください。
4. **設定ファイルパスを Text で表示**
   `~/Library/Preferences/com.x07jp27.ZoomacIt.plist` のパスを `Text` で読み取り専用表示。`FileManager` と `URL` のおさらいになります。

## 次に読む章

→ [42. 卒業課題: Magnifier Lens 機能](./42-magnifier-lens.md)
