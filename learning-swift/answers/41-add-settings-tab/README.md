# Ch41 解答例: Advanced 設定タブの追加

このディレクトリは [Ch41. ハンズオン 4: 設定タブを 1 つ増やす](../../part4-handson/41-add-settings-tab.md) の解答例です。

実装は 3 ファイルにまたがります。

| ファイル | 種別 | 変更内容 |
| --- | --- | --- |
| `src/ZoomacIt/Models/Settings.swift` | 既存ファイル編集 | enum 追加、Keys 追加、register 追加、computed property 追加、reset 配列拡張 |
| `src/ZoomacIt/Settings/AdvancedTab.swift` | **新規作成** | Picker + Stepper + Form の SwiftUI View |
| `src/ZoomacIt/Settings/SettingsView.swift` | 既存ファイル編集 | TabView に AdvancedTab を追加 |

順を追って解説します。

---

## 1. Settings.swift の変更点

### 1-1. LogLevel enum の追加

`Settings.swift` の冒頭、`FontWeightOption` enum の **直後** に新しい enum を追加します。

```diff
 enum FontWeightOption: String, CaseIterable, Sendable {
     ...
 }

+/// Application log verbosity level, persisted as raw String.
+enum LogLevel: String, CaseIterable, Sendable {
+    case info, debug, verbose
+}
+
 /// Centralized settings manager backed by UserDefaults.
 final class Settings: @unchecked Sendable {
```

`String` raw type にしているのは UserDefaults に直接保存できる型は限られているからです。`Bool` / `Int` / `Double` / `String` / `Date` / `Data` / `URL`、およびそれらの配列・辞書のみが許可されており、独自 enum は **そのままでは保存できません**。`rawValue` を経由して `String` として永続化し、読み出し時に `LogLevel(rawValue:)` で復元する、というのが ZoomacIt の `Settings` で繰り返し採用されている定石です (`PenColor`、`FontWeightOption`、`BreakTimerBackground` も同じパターン)。

`CaseIterable` への適合は SwiftUI の `ForEach(LogLevel.allCases, id: \.self)` を成立させるために必要です。`Sendable` は Swift 6 の strict concurrency における「アクター越境を許可する」マーカーで、`@AppStorage` 経由で MainActor 隔離された `View` の中から触る上で警告を出さないために付けています。

### 1-2. Keys に 2 行追加

`enum Keys` (59 行目あたり) の Break Timer ブロックの **後ろ** に、次の 2 行を足します。

```diff
         static let breakTimerBackgroundFadeDarkness = "breakTimerBackgroundFadeDarkness"
+
+        // Advanced
+        static let logLevel = "logLevel"
+        static let strokeHistoryLimit = "strokeHistoryLimit"
     }
```

キー文字列の値は人間に分かるシンプルな名前で十分です。**重要なのはアプリのコード側でこの定数経由でしかアクセスしないこと** で、これによりタイポは存在しえなくなります。

### 1-3. registerDefaults() にデフォルト値追加

`registerDefaults()` メソッドの `defaults.register(defaults: [...])` の末尾に追記します。

```diff
             Keys.breakTimerBackgroundFadeDarkness: 0.6,
+
+            // Advanced
+            Keys.logLevel: LogLevel.info.rawValue,
+            Keys.strokeHistoryLimit: 30
         ])
```

ここで登録した値は **ユーザーが一度も設定 UI を触っていないときのフォールバック** として使われます。実際の plist ファイルには書き込まれず、初回起動時のメモリ上のデフォルトテーブルに置かれるだけです。`UserDefaults.standard.removeObject(forKey:)` を呼んでも、register された値は影響を受けず、次回 `string(forKey:)` で問い合わせると再度返ってきます。Reset 機能の挙動と直結する重要な仕様です。

### 1-4. 計算プロパティの追加

Break Timer セクションの直後に、新しい `MARK` で囲んだセクションを追加します。

```diff
     var breakTimerBackgroundFadeDarkness: CGFloat {
         get { CGFloat(defaults.double(forKey: Keys.breakTimerBackgroundFadeDarkness)) }
         set { defaults.set(Double(newValue), forKey: Keys.breakTimerBackgroundFadeDarkness) }
     }

+    // MARK: - Advanced
+
+    var logLevel: LogLevel {
+        get { LogLevel(rawValue: defaults.string(forKey: Keys.logLevel) ?? "") ?? .info }
+        set { defaults.set(newValue.rawValue, forKey: Keys.logLevel) }
+    }
+
+    var strokeHistoryLimit: Int {
+        get { defaults.integer(forKey: Keys.strokeHistoryLimit) }
+        set { defaults.set(newValue, forKey: Keys.strokeHistoryLimit) }
+    }
+
     // MARK: - Reset
```

`logLevel` の getter は `defaults.string(forKey:)` が `nil` を返した場合に空文字 `""` をフォールバックとして渡し、`LogLevel(rawValue: "")` も `nil` になるので、最終的に `?? .info` でデフォルトに着地します。**3 段の `??` フォールバック** は冗長に見えますが、register が動かない極端なケース (ユニットテストや UserDefaults 破損時) でも必ず有効な値を返すための保険です。

`strokeHistoryLimit` 側はもっと簡潔です。`defaults.integer(forKey:)` はキーが存在しない場合に `0` を返す仕様ですが、register によって 30 が登録済みなので実際には問題になりません。

### 1-5. resetToDefaults() の allKeys 配列を拡張

```diff
             Keys.breakTimerSoundFile, Keys.breakTimerBackgroundFadeDarkness,
+            Keys.logLevel, Keys.strokeHistoryLimit
         ]
```

これを忘れると、ユーザーが「Reset to Defaults」ボタンを押しても Log Level / Stroke History Limit だけが残るので、テスト観点でぜひ手動確認してください。

---

## 2. AdvancedTab.swift の完成コード

新規ファイル `src/ZoomacIt/Settings/AdvancedTab.swift` の中身です。

```swift
import SwiftUI

/// Advanced settings tab: log verbosity and stroke history capacity.
struct AdvancedTab: View {

    @AppStorage(Settings.Keys.logLevel)
    private var logLevelRaw: String = LogLevel.info.rawValue

    @AppStorage(Settings.Keys.strokeHistoryLimit)
    private var strokeHistoryLimit: Int = 30

    /// Bridges the persisted `String` rawValue to a strongly-typed `LogLevel` for the Picker.
    private var logLevel: Binding<LogLevel> {
        Binding(
            get: { LogLevel(rawValue: logLevelRaw) ?? .info },
            set: { logLevelRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Logging") {
                Picker("Log Level", selection: logLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Drawing") {
                Stepper(
                    "History Limit: \(strokeHistoryLimit)",
                    value: $strokeHistoryLimit,
                    in: 5...100,
                    step: 5
                )
            }
        }
        .formStyle(.grouped)
    }
}
```

### 解説: @AppStorage と Binding ラップの二段構え

`@AppStorage` は **UserDefaults の特定キーと、SwiftUI の値を双方向バインドする** property wrapper です。`@AppStorage(Settings.Keys.logLevel)` を付けたプロパティの値を変更すると、自動的に `UserDefaults.standard.set(_:forKey:)` が呼ばれ、ディスクへ書き戻されます。逆に他箇所が `UserDefaults.standard.set(_:forKey:)` で書き換えると、SwiftUI 側に通知が飛んで再描画が走ります。

ところが `@AppStorage` がサポートしている型は `Bool` / `Int` / `Double` / `String` / `URL` / `Data` および **rawValue が `Int` または `String` の `RawRepresentable` 直接対応のみ** です。`LogLevel` も Swift 5.5 以降ならば `@AppStorage(Keys.logLevel) var level: LogLevel` と直接書ける場合がありますが、ZoomacIt では `DrawTab.swift` で確立されたパターン — **`String` で生で受けて、`Binding<EnumType>` に変換してから Picker に渡す** — を踏襲しています。

```swift
private var logLevel: Binding<LogLevel> {
    Binding(
        get: { LogLevel(rawValue: logLevelRaw) ?? .info },
        set: { logLevelRaw = $0.rawValue }
    )
}
```

この計算プロパティが「String と enum の橋渡し」を一手に引き受けます。`Binding(get:set:)` は SwiftUI が用意しているクロージャベースのコンストラクタで、`get` / `set` の両方を自分で書くことで、見かけ上の値型を変えずにバッキングストアだけを差し替えるテクニックです。Java の世界で言えば `Function<T, U>` と `BiConsumer<U, T>` を持った双方向アダプタを書く感覚に近いです。

### 解説: Picker と Stepper

`Picker("Log Level", selection: logLevel) { ... }` の `selection:` には `Binding<LogLevel>` を渡します。中の `ForEach` で `LogLevel.allCases` を回し、各要素に `.tag(level)` を付けて Picker が「どの選択肢が現在値か」を識別できるようにします。`tag` の値の型は `selection` の値型と完全一致が必要 (`LogLevel`)。

`.pickerStyle(.menu)` を指定しているのはプルダウンメニュー形式にするためです。指定しない場合の挙動は環境依存で、macOS Settings 風の Form コンテキストでは radio 風になることもあります。明示するのが無難です。

`Stepper` は `value:` に `$strokeHistoryLimit` を渡すだけで動きます。`$` は `@AppStorage` が自動生成する projected value (`Binding<Int>`) を取り出す記法で、Java で言うと「getter/setter ペアの参照を 1 つの式で渡す」のに似ています。`in: 5...100` で範囲を絞り、`step: 5` で増減幅を指定します。

### 解説: なぜ `LogLevel` は `Settings.LogLevel` ではなく `LogLevel` ?

`PenColor` や `FontWeightOption` がトップレベルの enum として `Settings.swift` に置かれているのと同じ理由で、`LogLevel` もトップレベルに置きました。`Settings` クラスの内側に nested type として置く設計もあり得ますが、その場合は呼び出し側がすべて `Settings.LogLevel.info` のように長い修飾名になります。ZoomacIt ではトップレベル配置を一貫して採用しているので、本ハンズオンもそれに揃えています。

ただし設計の選択肢として nested type 版を理解しておく価値はあります。Ch23 (Nested Types) の応用として「設定固有の型は Settings の内部に閉じ込める」ポリシーは妥当な判断です。

### 解説: @State との違い

`@AppStorage` は **永続化される** のに対し、`@State` は **そのビューのライフサイクル中だけメモリに保持** されます。設定ウィンドウを閉じて再度開いた時、`@State` で持っていた値はリセットされ、`@AppStorage` で持っていた値は引き継がれます。

「再起動を跨いで保持されるべきか」が判断基準です。本ハンズオンの 2 項目はどちらも保持されるべきユーザー設定なので `@AppStorage` 一択です。GeneralTab.swift の `launchAtLogin: Bool` が `@State` になっているのは、これは UserDefaults ではなく `SMAppService.mainApp.status` から都度問い合わせる値だからです。`@State` は「ビューが画面上に存在する間だけ覚えておきたい揮発状態」の保管所と理解してください。

### 解説: `var body: some View` の `some View`

Ch27 (Opaque Types) で扱ったとおり、`some View` は **「具体的な型は実装者しか知らないが、`View` プロトコルに適合する 1 つの具体型を返す」** という宣言です。`Form { Section { ... Picker { ... } ... Stepper { ... } } }` の組み合わせは、SwiftUI 内部では巨大なジェネリックの入れ子型 (`Form<TupleView<(Section<...>, Section<...>)>>` のようなもの) になります。これを呼び出し側に晒すのは可読性も実用性も最悪なので、`some View` で隠蔽しているわけです。

Java で考えるなら「return type は `Iterable<String>` (interface) としか書かないが、実装は `ArrayList<String>` でも `Stream` をまとめた CustomCollection でも構わない」という抽象化に近いですが、SwiftUI の場合は **コンパイル時にその具体型を 1 つに決め打ちできる** (型推論時点で確定) という点が異なります。これがランタイムオーバーヘッド無しで宣言型 UI を成立させている肝です。

### `.formStyle(.grouped)`

macOS の System Settings 風の見た目 (角丸グレー背景の中に各セクションが並ぶスタイル) を適用します。これを書かないと、フラットなリスト風の表示になります。Tab 全体で見た目を揃えるため、`GeneralTab` / `DrawTab` / `ZoomTab` / `BreakTimerTab` すべてが `.formStyle(.grouped)` を採用しているので、Advanced タブもこれに合わせます。

`.padding()` や `.frame(width: ..., height: ...)` を追加するかは好みです。`SettingsView` の親 `VStack` 側で `.frame(minWidth: 480, minHeight: 320)` がすでに指定されているので、各 Tab 側の `.frame()` は不要 — 余計に書くと逆に親のサイズ指定と競合してレイアウトが歪むことがあります。

---

## 3. SettingsView.swift の変更点

`src/ZoomacIt/Settings/SettingsView.swift` の `TabView { ... }` ブロック (10 行目あたり) に 1 タブを追加します。

```diff
             TabView {
                 GeneralTab()
                     .tabItem { Text("General") }
                 DrawTab()
                     .tabItem { Text("Draw") }
                 ZoomTab()
                     .tabItem { Text("Zoom") }
                 BreakTimerTab()
                     .tabItem { Text("Break Timer") }
+                AdvancedTab()
+                    .tabItem { Text("Advanced") }
             }
```

`tabItem` を SF Symbol 付きにしたいなら次のように書けます。

```swift
AdvancedTab()
    .tabItem { Label("Advanced", systemImage: "gearshape.2") }
```

ただし他のタブが `Text` のみなので、混ぜると見た目に統一感が無くなります。プロジェクトの既存スタイルに合わせるのがプロの流儀です。本解答では既存に合わせて `Text("Advanced")` を採用しました。

`TabView` 自体は宣言的に書かれており、order 依存の挙動は無いので、追加位置 (BreakTimerTab の前か後ろか) は機能的に等価です。ただしユーザーが目にする順番に意味があるので、「General → ドメイン別 (Draw / Zoom / BreakTimer) → Advanced」と「重要度・頻度の高い順、最後に詳細設定」という UX 上の慣習に沿わせています。

---

## 4. プロジェクトファイル再生成

新しい `.swift` ファイルを追加した後は次を実行します。

```bash
make generate
```

これは `xcodegen generate` を `src/project.yml` に対して呼び出すラッパーです (`Makefile` 参照)。ZoomacIt の `project.yml` の sources 指定は `path: ZoomacIt` (ディレクトリ全体) になっているので、ディスク上に存在する `.swift` ファイルは自動的にターゲットメンバーとして取り込まれます — 個別に `Sources/Settings/AdvancedTab.swift` のような行を増やす必要はありません。

```yaml
targets:
  ZoomacIt:
    type: application
    platform: macOS
    sources:
      - path: ZoomacIt
```

ただし xcodegen が完全に冪等とは限らないので、新規ファイル追加 → ビルド失敗 → 「ファイルが見つからない」というエラーが出たら、まず `make generate` を疑ってください。これは macOS の Xcode プロジェクト管理で初学者が一度はハマるポイントです。

---

## 5. 動作確認の流れ

```bash
make generate     # project.xcodeproj を再生成 (新規ファイル取り込み)
make build        # Debug ビルド
make test         # 既存テストが回帰していないか確認
make run          # アプリ起動
```

メニューバーの ZoomacIt アイコンから "Settings…" を開き、Advanced タブが追加されていることを目視確認します。Picker と Stepper を操作して値を変えたあと、設定ウィンドウを閉じてから再度開き、値が保持されていれば永続化に成功しています。

UserDefaults を直接覗きたいときは:

```bash
defaults read com.x07jp27.ZoomacIt logLevel
defaults read com.x07jp27.ZoomacIt strokeHistoryLimit
```

「Reset to Defaults」ボタンを押した時に Advanced タブの値も初期値に戻ることを確認すれば、`resetToDefaults()` の `allKeys` 配列拡張も正しく機能していることが分かります。

---

## 6. このハンズオンで押さえるポイント

| ポイント | 該当ステップ | 元になる章 |
| --- | --- | --- |
| `struct` で SwiftUI View を定義する | Step 5 | Ch12 / Ch25 |
| `View` プロトコルへの適合 (`var body: some View`) | Step 5 | Ch25 / Ch27 |
| `@AppStorage` で UserDefaults と双方向バインド | Step 5 | Ch36 |
| enum を rawValue 経由で永続化する 5 層構成 | Step 1〜4 | Ch36 |
| `Binding(get:set:)` で型変換アダプタを書く | Step 5 | (Ch36 応用) |
| `TabView` / `Form` / `Section` の SwiftUI コンテナ | Step 5〜6 | (本章で初出) |
| xcodegen と sources ディレクトリ自動取り込み | Step 7 | Ch31 (Build & Tooling) |

これらをすべて自力で書き切れるようになれば、ZoomacIt の Settings に新しい項目を追加するのは 5 分の作業になります。Magnifier Lens (Ch42 卒業課題) でも、新機能の有効/無効トグルや表示倍率設定を Advanced タブまたは新規タブに置くことになるので、本ハンズオンで身につけた手順がそのまま活きてきます。
