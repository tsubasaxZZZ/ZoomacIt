# 36. UserDefaults とシングルトン設定

## この章で学ぶこと

アプリケーションの設定値（ホットキー、ペンの色、フォントサイズなど）は、ユーザーが一度変更したらアプリを再起動しても保持される必要があります。macOS / iOS では、こうした「軽量で構造のない設定情報」を永続化する標準的な仕組みとして `UserDefaults` が用意されています。

ZoomacIt では、`UserDefaults` を直接アプリ全体から参照するのではなく、**`Settings` という名前のシングルトンクラスでラップ** して、型安全かつ読みやすいアクセスを提供しています。さらに SwiftUI 側からは property wrapper の `@AppStorage` を使い、設定 UI と永続化層を直接バインドしています。

この章では以下を順に解説します。

- `UserDefaults` とは何か、Java の Properties / Preferences API との対応
- シングルトンとして `Settings` を実装するパターン
- `UserDefaults.standard` の正体と保存先
- マジックストリングを排除するキー名の管理 (`enum Keys`)
- 計算プロパティで `enum` ↔ `String` の変換を閉じ込める型安全 API
- `register(defaults:)` によるデフォルト値の一括登録
- SwiftUI の `@AppStorage` を使った設定画面のバインディング
- 値変更を検知する Notification の扱い
- シングルトン採用の利点と注意点

ZoomacIt の `Settings.swift` は 350 行近い大きめのクラスですが、構造はきわめて整っています。「設定永続化を 1 ファイルで完結させる」サンプルとして読み進めてください。

---

## UserDefaults とは

`UserDefaults` は Foundation フレームワークが提供する、キー・バリュー型の永続化ストアです。アプリの設定や軽量なユーザー状態を保存する標準的な仕組みで、内部的には `plist`（XML ベースのバイナリフォーマット）にシリアライズされてディスクに書き込まれます。

Java に置き換えるとイメージしやすいでしょう。

| Java | Swift (macOS / iOS) |
| --- | --- |
| `java.util.Properties` + 手動でファイル I/O | `UserDefaults` |
| `java.util.prefs.Preferences` | `UserDefaults`（より近い） |
| `Properties.getProperty("key", "default")` | `UserDefaults.string(forKey: "key")` |
| `props.store(new FileOutputStream(...), null)` | 自動で永続化（明示 flush 不要） |

Java の `Preferences` API と同じく、**保存・読み込みのファイル I/O を意識せずに済む** のが最大の利点です。値を `set` した瞬間、メモリ上のキャッシュが更新され、適切なタイミングで OS がディスクに書き戻します。アプリ終了時や OS の都合で flush されるため、明示的に `synchronize()` を呼ぶ必要は通常ありません（`synchronize()` は現在では非推奨です）。

`UserDefaults` に保存できる型は限られています。

- プリミティブ: `Bool`, `Int`, `Double`, `Float`
- Foundation 型: `String`, `Data`, `Date`, `URL`, `Array`, `Dictionary`

カスタムの構造体や `enum` をそのまま保存することはできません。ZoomacIt では **`enum` の `rawValue: String` を保存し、読み出し時に再構築する** という素直なアプローチを取っています。後述します。

---

## シングルトン設計

`Settings` クラスはシングルトンとして実装されています。

```swift
/// Centralized settings manager backed by UserDefaults.
/// Thread-safe (UserDefaults is thread-safe).
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }
    // ...
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:45-55

Java 経験者から見ると、これは典型的な「Eager initialization の Singleton パターン」です。

```java
// Java での等価実装
public final class Settings {
    public static final Settings SHARED = new Settings();
    private Settings() { /* ... */ }
}
```

ただし Swift では、`static let` の右辺が **遅延かつスレッドセーフに 1 度だけ評価される** ことが言語仕様で保証されています。Java で必要だった `synchronized` ブロックや double-checked locking、`enum`-based singleton といったテクニックは一切不要です。

ポイントを整理しましょう。

1. **`final class`** — サブクラス化を禁止。シングルトンの不変性を保証する基本。
2. **`static let shared`** — クラスメソッドではなくプロパティとして公開。Apple のフレームワークでは `URLSession.shared`、`NotificationCenter.default`、`FileManager.default` など同じ命名規約が定着しています。
3. **`private init()`** — 外部からの `Settings()` 呼び出しを禁止。アクセスは必ず `Settings.shared` 経由。
4. **`@unchecked Sendable`** — Swift 6 の strict concurrency 下で `static let shared` が型のコンパイルを通すために必要。`UserDefaults` 自身がスレッドセーフなので、`@unchecked` でコンパイラのチェックをすり抜けても安全です。

`@unchecked Sendable` という宣言は「私が責任を持って安全だと保証するので、コンパイラのチェックをスキップしてください」という意思表示です。`UserDefaults.standard` は Apple のドキュメントで明示的にスレッドセーフと書かれており、ZoomacIt の `Settings` クラスは内部状態を `defaults` 以外に持たないため、複数スレッドからの同時アクセスでも問題が起きません。一方で、可変ストアを別途持つようなクラスでは安易に `@unchecked Sendable` を使うべきではない、という注意点はあります。

---

## `UserDefaults.standard`

`Settings` クラスは内部で `UserDefaults.standard` を保持しています。

```swift
private let defaults = UserDefaults.standard
```

これは「アプリのデフォルトドメイン」と呼ばれる、**bundle identifier に紐づく永続ストア** です。たとえば ZoomacIt の bundle identifier が `com.example.ZoomacIt` であれば、保存先は次のパスになります。

```
~/Library/Preferences/com.example.ZoomacIt.plist
```

このファイルは XML プロパティリストで、`defaults read com.example.ZoomacIt` というターミナルコマンドで中身を確認できます。デバッグ時には便利なテクニックなので覚えておきましょう。

`UserDefaults` には `standard` 以外にも、`init(suiteName:)` で App Group や任意のドメインを指定するオーバーロードがあります。ZoomacIt は単一プロセスのアプリなので `standard` のみで十分です。

Java の `Preferences.userNodeForPackage(MyApp.class)` がパッケージ単位で領域を分けるのと同じ発想で、bundle 単位に独立した名前空間が用意されている、と理解してください。

---

## キー名の管理

`UserDefaults` のすべての操作はキー（`String`）を介して行われます。これをコード中に直書きすると、いわゆる **マジックストリング** が散乱し、タイプミスでバグを生み出す温床になります。Java で `Map<String, Object>` を雑に使ったときと同じ問題です。

ZoomacIt では `Settings.Keys` というネストした `enum` でキー名を一括管理しています。

```swift
// MARK: - Keys

enum Keys {
    // Hotkeys
    static let zoomHotkeyKeyCode = "hotkeyZoomKeyCode"
    static let zoomHotkeyModifiers = "hotkeyZoomModifiers"
    static let drawHotkeyKeyCode = "hotkeyDrawKeyCode"
    static let drawHotkeyModifiers = "hotkeyDrawModifiers"
    static let breakHotkeyKeyCode = "hotkeyBreakKeyCode"
    static let breakHotkeyModifiers = "hotkeyBreakModifiers"

    // Draw
    static let defaultPenColor = "drawDefaultPenColor"
    static let defaultPenWidth = "drawDefaultPenWidth"
    static let highlighterOpacity = "drawHighlighterOpacity"
    static let highlighterWidthMultiplier = "drawHighlighterWidthMultiplier"

    // Text
    static let defaultFontSize = "textDefaultFontSize"
    static let fontWeight = "textFontWeight"

    // Zoom
    static let defaultZoomLevel = "zoomDefaultLevel"
    static let zoomAnimationEnabled = "zoomAnimationEnabled"

    // Break Timer
    static let breakTimerDefaultDuration = "breakTimerDefaultDuration"
    // ... 以下略
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:57-91

ここで使われている `enum Keys` は、Ch23 で扱った **nested type** の典型的な応用例です。`Settings` の責務に強く結びついた識別子なので、トップレベルではなく `Settings` の内側に置く。これにより呼び出し側のコードは `Settings.Keys.zoomHotkeyKeyCode` という、誰が見ても意図が読み取れる表現になります。

「ケースを持たない `enum`」を名前空間として使うのは Swift の常套手段です。`struct` でも同じことができますが、`enum` は **インスタンス化できない** ため「これは値を持つ型ではなく、純粋な名前空間です」という意図が型システムレベルで明確になります。Java で言えば `final class Keys { private Keys() {} static final String FOO = "foo"; }` を書くより、エルゴノミクスが上です。

カテゴリごとにコメントで区切られている点にも注目してください。`Settings` は 22 種類の設定値を扱う大所帯ですが、`Hotkeys` / `Draw` / `Text` / `Zoom` / `Break Timer` という機能カテゴリで視覚的にグルーピングされており、追加変更時の見通しがよくなっています。

---

## 計算プロパティで型安全な API

`UserDefaults` の生 API はとてもプリミティブです。

```swift
defaults.string(forKey: "drawDefaultPenColor")  // String?
defaults.integer(forKey: "hotkeyZoomKeyCode")   // Int (キーがなければ 0)
defaults.bool(forKey: "zoomAnimationEnabled")   // Bool (キーがなければ false)
defaults.set("red", forKey: "drawDefaultPenColor")
```

これを呼び出し側の各所で書くと、

- 文字列キーがマジックストリング化する
- `String?` を毎回 nil チェックして `enum` に変換する処理が散らばる
- 「キーがなければ 0」という意外な挙動でバグを生む

という問題が発生します。`Settings` クラスはこれを **計算プロパティ（computed property）** に閉じ込めることで解決しています。

代表例として、ペンの既定色を扱うプロパティを見てみましょう。

```swift
var defaultPenColor: PenColor {
    get { PenColor(rawValue: defaults.string(forKey: Keys.defaultPenColor) ?? "") ?? .red }
    set { defaults.set(newValue.rawValue, forKey: Keys.defaultPenColor) }
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:164-167

このたった 4 行に、設計上の重要な仕事が複数詰め込まれています。

1. **キー名は `Keys.defaultPenColor` に集約** — マジックストリング排除
2. **`defaults.string(forKey:) ?? ""` でフォールバック** — nil 安全
3. **`PenColor(rawValue:) ?? .red` で 2 段階のデフォルト** — 不正な値が保存されていても `.red` に倒す
4. **setter は `newValue.rawValue` で `String` に変換** — `enum` の永続化を 1 行で完結

呼び出し側はこう書けます。

```swift
// 読み取り
let color = Settings.shared.defaultPenColor   // PenColor 型

// 書き込み
Settings.shared.defaultPenColor = .blue
```

Java 経験者には、これは **「Lombok の `@Getter @Setter` と Properties ファイル I/O を 1 つの計算プロパティに合体させたもの」** と説明するのが一番わかりやすいでしょう。フィールド宣言だけで `get` / `set` が生え、内部で永続化まで完結する。Swift の計算プロパティは Java の getter / setter メソッド呼び出しの構文糖ではなく、**プロパティアクセスの構文そのものをカスタマイズできる仕組み** です。

数値型のプロパティも同じパターンで実装されています。

```swift
var defaultPenWidth: CGFloat {
    get { CGFloat(defaults.double(forKey: Keys.defaultPenWidth)) }
    set { defaults.set(Double(newValue), forKey: Keys.defaultPenWidth) }
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:169-172

`UserDefaults` は `Double` しか扱えないので、外部に公開する `CGFloat` との変換をプロパティ内で済ませています。呼び出し側は `CGFloat` で受け取れるので、AppKit / Core Graphics API にそのまま渡せます。

このパターンの真価は、後から実装を変えやすいことにあります。たとえば「ペンの色を iCloud 同期したい」と言われたら、`defaults` を `NSUbiquitousKeyValueStore` に差し替えるだけでよく、呼び出し側のコードは 1 行も変える必要がありません。これが **抽象境界としての計算プロパティ** の威力です。

---

## デフォルト値登録

新規インストール直後、`UserDefaults` には何も保存されていません。このとき `defaults.string(forKey: "...")` は `nil`、`defaults.integer(forKey: "...")` は `0` を返します。「ペン色が未指定なら `.red` を返す」というロジックを各プロパティに書いてもよいのですが、ZoomacIt はもう一段スマートな方法を取っています。それが `register(defaults:)` です。

```swift
// MARK: - Register Defaults

func registerDefaults() {
    defaults.register(defaults: [
        // Hotkeys
        Keys.zoomHotkeyKeyCode: Int(kVK_ANSI_1),
        Keys.zoomHotkeyModifiers: Int(controlKey),
        Keys.drawHotkeyKeyCode: Int(kVK_ANSI_2),
        Keys.drawHotkeyModifiers: Int(controlKey),
        Keys.breakHotkeyKeyCode: Int(kVK_ANSI_3),
        Keys.breakHotkeyModifiers: Int(controlKey),

        // Draw
        Keys.defaultPenColor: PenColor.red.rawValue,
        Keys.defaultPenWidth: 3.0,
        Keys.highlighterOpacity: 0.35,
        Keys.highlighterWidthMultiplier: 4.0,

        // Text
        Keys.defaultFontSize: 24.0,
        Keys.fontWeight: FontWeightOption.medium.rawValue,

        // Zoom
        Keys.defaultZoomLevel: 2.0,
        Keys.zoomAnimationEnabled: true,

        // Break Timer
        Keys.breakTimerDefaultDuration: 600,
        Keys.breakTimerColor: PenColor.red.rawValue,
        Keys.breakTimerOpacity: 1.0,
        Keys.breakTimerBackground: BreakTimerBackground.black.rawValue,
        Keys.breakTimerShowElapsed: true,
        Keys.breakTimerPlaySound: false,
        Keys.breakTimerBackgroundFadeDarkness: 0.6
    ])
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:93-128

`register(defaults:)` は **「ユーザーが値を保存していないキーに対するフォールバック値」** を一括登録するメソッドです。重要なのは、これらの値が **plist には書き込まれない** ことです。あくまで「読み出し時に、保存値がなければこの値を返す」というメモリ内のシャドウマップとして機能します。

つまり `UserDefaults` は、内部的に次のような優先順位で値を解決します。

1. ユーザーが明示的に保存した値（plist に書き込み済み）
2. `register(defaults:)` で登録されたデフォルト値
3. それもなければ、型ごとのゼロ値（`Int → 0`, `String → nil`, `Bool → false` など）

このおかげで、たとえ `defaultPenColor` のプロパティ定義が `?? .red` を持っていなくても、`registerDefaults()` 経由で `PenColor.red.rawValue` が拾われます。「2 段構えのデフォルト」と先ほど呼んだ理由はここにあります。アプリ起動直後 `private init()` が `registerDefaults()` を呼び出すため、初回利用時から「壊れた」設定状態にならないことが保証されます。

Java 経験者には、`Properties.getProperty(key, defaultValue)` の `defaultValue` を、各キーごとにアプリ起動時に一括登録しておく仕組み、と説明できます。

---

## SwiftUI の `@AppStorage`

ここまで紹介した `Settings` シングルトンは、AppKit ベースのコードや内部ロジックから設定値にアクセスする際に使われます。一方で、設定画面そのものは SwiftUI で書かれており、SwiftUI には **`@AppStorage`** という、`UserDefaults` と直接バインドする property wrapper が用意されています。

`GeneralTab.swift` を見てみましょう。

```swift
struct GeneralTab: View {

    @AppStorage(Settings.Keys.zoomHotkeyKeyCode) private var zoomKeyCode: Int = Int(kVK_ANSI_1)
    @AppStorage(Settings.Keys.zoomHotkeyModifiers) private var zoomModifiers: Int = Int(controlKey)
    @AppStorage(Settings.Keys.drawHotkeyKeyCode) private var drawKeyCode: Int = Int(kVK_ANSI_2)
    @AppStorage(Settings.Keys.drawHotkeyModifiers) private var drawModifiers: Int = Int(controlKey)
    @AppStorage(Settings.Keys.breakHotkeyKeyCode) private var breakKeyCode: Int = Int(kVK_ANSI_3)
    @AppStorage(Settings.Keys.breakHotkeyModifiers) private var breakModifiers: Int = Int(controlKey)
```

> 引用元: src/ZoomacIt/Settings/GeneralTab.swift:6-13

`@AppStorage` の宣言だけで、以下のすべてが自動化されます。

1. 初期化時に `UserDefaults.standard` から該当キーの値を読み込む（なければ右辺のデフォルト値）
2. プロパティへの代入時に `UserDefaults` へ書き込む
3. **`UserDefaults` の値が外部から変更されたら、SwiftUI のビューが自動再描画される**

3 番目が `@AppStorage` の真骨頂です。たとえば `Settings.shared.zoomHotkeyKeyCode = ...` と AppKit 側のコードから書き換えたとしても、SwiftUI の設定画面が開いていればテキストフィールドの表示が即座に更新されます。逆に、設定画面で値を変えれば、それを購読している他のビューも追随します。ビューと永続化層が同じ `UserDefaults` を介して同期する、という単純で強力なモデルです。

`Settings.Keys.zoomHotkeyKeyCode` を `@AppStorage` の引数に渡している点に注目してください。**シングルトン側が定義したキー定数を、SwiftUI 側がそのまま流用しています。** これにより、シングルトンの計算プロパティと SwiftUI の `@AppStorage` が **同じキーを指していることがコンパイル時に保証** されます。仮にキー名を変更しても、`Keys.zoomHotkeyKeyCode` をリネームすれば両側に伝播するので、片方を更新し忘れる事故が起きません。

`@AppStorage` がサポートする型は `UserDefaults` がサポートする型に近いですが、`String` の `rawValue` を持つ `enum` も `RawRepresentable` 制約経由で直接扱えます。たとえばペン色の `enum PenColor: String` なら、

```swift
@AppStorage(Settings.Keys.defaultPenColor) private var penColor: PenColor = .red
```

と書くだけで動きます。`Settings` の計算プロパティと役割が重なる部分もありますが、SwiftUI 内部で使うときは `@AppStorage` の方が宣言的で短く書けるため、両者が共存しています。

設定値の変更に応じて副作用を実行したい場合は、`onChange` モディファイアと組み合わせます。

```swift
.onChange(of: zoomKeyCode) { _, _ in reregisterHotkeys() }
.onChange(of: zoomModifiers) { _, _ in reregisterHotkeys() }
```

> 引用元: src/ZoomacIt/Settings/GeneralTab.swift:30-31

`@AppStorage` プロパティが書き換わる → `UserDefaults` に保存される → `onChange` が発火 → ホットキーを再登録、という連鎖が成立します。設定 UI から永続化、副作用の発火までが、ほぼ宣言的に書けてしまうのが SwiftUI のすごみです。

---

## Notification での変更通知

`UserDefaults` 自身も値の変更を通知してくれます。

```swift
NotificationCenter.default.addObserver(
    forName: UserDefaults.didChangeNotification,
    object: nil,
    queue: .main
) { _ in
    // 値が更新された
}
```

ただしこの通知は「何かが変わった」としか教えてくれず、どのキーが変わったかは分かりません。粒度の細かい通知が欲しい場面では、ZoomacIt のように **独自の Notification 名を定義する** 方が扱いやすいです。

```swift
// MARK: - Notification

extension Notification.Name {
    static let settingsDidReset = Notification.Name("settingsDidReset")
    static let hotkeysDidChange = Notification.Name("hotkeysDidChange")
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:344-349

`Notification.Name` を `extension` で拡張し、ドット記法で参照可能なシンボル（`.settingsDidReset` など）として公開しています。型推論が効くため、購読側・送信側ともに `.settingsDidReset` というドット記法だけで参照できます。これは **Notification 名のタイポを防ぐイディオム** で、Swift の AppKit / SwiftUI コードで広く使われます。

実際の発火は `Settings.resetToDefaults()` の中で行われています。

```swift
NotificationCenter.default.post(name: .settingsDidReset, object: nil)
```

「設定を初期化した」というセマンティクスを伝えたい場面では、`UserDefaults.didChangeNotification` よりこの専用通知のほうが意図が明確で、購読側も「リセットされたとき」だけに反応する処理を書けます。

ホットキー変更時には `.hotkeysDidChange` 通知も発火されます（`GeneralTab` の `reregisterHotkeys()` 内）。`StatusBarController` がこれを購読してメニュー上のショートカット表示を更新する、という流れです。

---

## シングルトンの注意点

最後に、シングルトン採用時のトレードオフを正直に整理しておきます。これは Swift / Java を問わず、ソフトウェア設計の普遍的なテーマです。

### 利点

- **アクセスが簡潔** — `Settings.shared.defaultPenColor` でどこからでも読める
- **インスタンス管理が不要** — DI コンテナや受け渡しコードが要らない
- **状態の一貫性が保証される** — 1 つしか存在しないため、設定値が分散するリスクがない
- **`UserDefaults` 自体がシングルトン的** — 永続層と整合性がある

### 欠点

- **テストしにくい** — モックを差し替えられず、テスト間で状態が漏れる
- **暗黙の依存** — `Settings.shared` に依存するクラスは、クラス図の依存矢印に現れない
- **並行性の責務を自分で持つ** — `@unchecked Sendable` で安全性を「宣言」する以上、本当に安全か検証する責任は実装者側

### ZoomacIt が選んだ折衷案

ZoomacIt の `Settings` は内部状態として `UserDefaults.standard` のみを参照するステートレスなラッパーです。並行性の問題は `UserDefaults` 側に委譲され、インスタンス自体は値を持ちません。このため `@unchecked Sendable` が安全に成立します。

テスト容易性については、テストコードが `UserDefaults` の特定のキーに直接アクセスしてセットアップする、というアプローチが現実的です。`Settings` をプロトコル化して DI する設計も可能ですが、設定値という性質上「アプリ全体で 1 つ」の運用が自然なため、過剰設計を避けてシンプルな現状の構造が選ばれています。

Java 経験者にとっては「テスト時は `@MockBean` で置き換え可能な Spring の `@Component` シングルトン」と比べて、Swift 標準のシングルトンは差し替え機構が貧弱に感じるかもしれません。これは事実なので、テストが極めて重要なドメインロジックには `protocol` + DI を使う、設定永続化のような周辺関心事はシンプルなシングルトンで済ませる、というメリハリを意識するとよいでしょう。

---

## ZoomacIt 実コード読解

ここまでの内容を踏まえて、`Settings.swift` の構造を上から下まで眺め直してみます。

1. **`enum FontWeightOption`** （5-43 行）— `String` raw value を持つ `enum`。`UserDefaults` に `rawValue` を保存し、`nsFontWeight` で AppKit の `NSFont.Weight` に変換する。Settings ファイルに置かれているのは「永続化される列挙型は永続化層と一緒に管理する」という設計判断の表れ。
2. **`final class Settings: @unchecked Sendable`** （47-55 行）— シングルトン本体の宣言。`static let shared`、`private init()`、`registerDefaults()` の自動呼び出し。
3. **`enum Keys`** （57-91 行）— 22 個のキーをカテゴリ別に名前空間化。
4. **`registerDefaults()`** （93-128 行）— アプリ起動時に呼ばれ、未保存キーのフォールバック値を一括登録。
5. **計算プロパティ群** （130-251 行）— `Hotkeys` / `Draw` / `Text` / `Zoom` / `Break Timer` の各カテゴリで、`get` / `set` ペアの計算プロパティを定義。`enum`、`CGFloat`、`URL?` といった型をプロパティ内で `UserDefaults` の対応型に変換。
6. **`resetToDefaults()`** （253-273 行）— 全キーを削除して `register(defaults:)` の値に戻す。完了後に `.settingsDidReset` を post。
7. **静的ユーティリティ** （275-341 行）— `hotkeyDisplayString` などの key code 表示変換。設定値そのものではないが、設定 UI から呼ばれるため同居している。
8. **`extension Notification.Name`** （344-349 行）— 独自 Notification 名の定義。

設定永続化に関する責務が **1 ファイル・1 クラス** にすべて閉じ込められており、Settings タブを追加・修正する際にここだけ見ればよい構造になっています。「凝集度の高い設計」の良いお手本です。

---

## ハンズオン（任意）

理解を深めるために、以下を試してみてください。

1. **`defaults` コマンドで実体を覗く**
   ターミナルで以下を実行し、ZoomacIt が書き込んでいる plist の中身を確認します。

   ```bash
   defaults read com.example.ZoomacIt
   ```

   設定タブで値を変えた直後・アプリ再起動後など、タイミングを変えて何度か叩くと、永続化のタイミングが体感できます。

2. **新しい設定値を 1 つ追加する**
   - `Settings.Keys` に新しいキー定数を追加
   - `registerDefaults()` にデフォルト値を登録
   - 計算プロパティを定義
   - SwiftUI 設定画面で `@AppStorage` を使ってバインド

   このサイクルを 1 周することで、永続化レイヤーと UI が `Keys` を介して接続される構造が腑に落ちます。

3. **`@AppStorage` と `Settings.shared` のどちらを使うか考える**
   実装中の SwiftUI ビューから設定値にアクセスするとき、`@AppStorage` を使うべきか、`Settings.shared.foo` を使うべきか。「ビューがその値の変化に応じて再描画されるべきか？」という問いを基準に判断するのが原則です。

---

## 次に読む章

→ [37. XCTest による単体テスト](./37-xctest.md)
