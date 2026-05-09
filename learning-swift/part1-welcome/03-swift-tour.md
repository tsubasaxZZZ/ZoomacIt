# 03. A Swift Tour(ZoomacIt 版)

## この章で学ぶこと

- Swift の主要な構文要素を、ZoomacIt の最小コード(`main.swift` と `Stroke.swift`)から先取りで見る
- `import` / `let` / `var` / `enum` / `struct` / `init` といった基本構文の意味
- Part II 以降で深掘りする項目への索引

---

## ツアーの目的

この章は、Swift の主要な構文を **「広く浅く」** 一気通貫で見るためのツアーです。Apple 公式 *The Swift Programming Language* の冒頭に "A Swift Tour" という章があるのを参考にしていますが、本書ではそれを **ZoomacIt の実コード** で再構成します。

各機能の詳細な説明は Part II の各章に譲り、ここでは「Swift プログラムがどんな見た目をしているか」を体感することに集中します。

> **NOTE**
> ここで出てくる構文を完全に理解する必要はありません。「だいたいこういう感じ」という雰囲気をつかめば十分です。違和感があった部分は Part II の該当章で必ず深掘ります。

## ツアー 1: アプリの起点 — `main.swift`

ZoomacIt の起動はわずか 7 行で完結します。`main.swift` を見てみましょう。

> 引用元: `src/ZoomacIt/App/main.swift:1-7`

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
NSLog("[main] delegate set, calling app.run()")
app.run()
```

このたった 7 行に、Swift の重要な要素がいくつも詰まっています。順に見ていきます。

### `import AppKit`

Java の `import` 文とほぼ同じです。Apple の AppKit フレームワーク(macOS の GUI を提供するライブラリ)を読み込んでいます。Swift では Apple 公式フレームワークも、自作モジュールも、すべて `import` キーワードで統一して取り込みます。Java と違って `import com.example.foo.*` のような **ワイルドカード** はなく、モジュール単位での import が基本です。

### `let app = NSApplication.shared`

`let` は **再代入できない変数の宣言** です。Java の `final var` に相当しますが、Swift では `let` がデフォルトであり、再代入したいときだけ `var` を使うのが流儀です。

型注釈 `: NSApplication` を書いていないことに注目してください。これは **型推論** が効いており、右辺 `NSApplication.shared`(これは `static let` のシングルトンプロパティ)から型 `NSApplication` が自動で決まります。

### `let delegate = AppDelegate()`

`AppDelegate` クラスのインスタンスを生成しています。**`new` キーワードがない** のが Swift の特徴で、型名にカッコをつけるだけでインスタンス化できます。Java の `new AppDelegate()` を `AppDelegate()` と書くと考えてください。

### `app.delegate = delegate`

`NSApplication` が持つ `delegate` プロパティに、先ほど生成した `AppDelegate` インスタンスを設定しています。Java の Bean のセッタと同じ感覚で、Swift ではプロパティを直接代入できます(裏で `set` が呼ばれているわけではなく、**保存プロパティ(stored property)** への直接書き込みです)。

### `NSLog(...)` と `app.run()`

`NSLog` は Apple 標準のロギング関数で、Console.app に出力されます。`print` ではなく `NSLog` を使うのが macOS アプリの慣習です(タイムスタンプとプロセス名が自動で付くため)。

`app.run()` はメインイベントループを開始する呼び出しで、ここから抜けるのはアプリ終了時です。Java の Swing で言えば `EventQueue.invokeAndWait(...)` を呼んでイベントディスパッチスレッドを起動するのと似ていますが、Swift / AppKit では **メインスレッド上で同期的に永久ループ** に入ります。

> **NOTE**
> Swift には Java の `public static void main(String[] args)` に相当する明示的な `main` メソッドがありません。代わりに「**`main.swift` というファイル名のトップレベルコードがエントリポイントになる**」というルールがあります。`main.swift` 以外のファイルでは、トップレベルに文(statement)を書けません。

## ツアー 2: データ型を定義する — `Stroke.swift`

次は描画ストローク(画面に書く線)を表すデータ型 `Stroke` を見ます。これは ZoomacIt の Draw 機能で「確定された 1 本の線」を表す値です。

### Enum 部分

> 引用元: `src/ZoomacIt/Models/Stroke.swift:3-10`

```swift
/// The type of shape being drawn.
enum ShapeType: Sendable {
    case freehand
    case line
    case rectangle
    case ellipse
    case arrow
}
```

`enum ShapeType` は Java の `enum` と似ていますが、Swift の enum は **遥かに強力** です。ここでは単純な列挙(5 つのケース)ですが、Swift の enum には次のような Java にない機能があります(Part II の Ch11 で深掘り)。

- 各ケースに **付随値(associated values)** を持たせられる(例: `case error(message: String)`)
- 各ケースに **生の値(raw values)** を割り当てられる(例: `enum Color: String { case red = "red" }`)
- ケースに対する `switch` の **網羅性チェック** がコンパイル時に効く

`: Sendable` という部分は **プロトコル適合** の宣言で、Java の `implements Sendable` に相当します。`Sendable` は Swift 6 の並行性機構で「スレッド境界を越えて安全に渡せる型」であることを示します(Ch21 で深掘り)。

`///` で始まるコメントは **ドキュメンテーションコメント** で、Java の `/** */` に相当します。Xcode で `Option + クリック` するとここがツールチップに表示されます。

### Struct 部分

> 引用元: `src/ZoomacIt/Models/Stroke.swift:12-52`

```swift
/// Represents a single confirmed drawing stroke.
struct Stroke {
    /// Raw points collected during freehand drawing.
    var points: [CGPoint]

    /// Starting point (used for shape rendering).
    var startPoint: CGPoint

    /// Ending point (used for shape rendering).
    var endPoint: CGPoint

    /// The stroke color.
    var color: NSColor

    /// The line width in points.
    var lineWidth: CGFloat

    /// The shape type.
    var shapeType: ShapeType

    /// Whether the stroke uses highlighter (semi-transparent) mode.
    var isHighlighter: Bool

    init(
        points: [CGPoint] = [],
        startPoint: CGPoint = .zero,
        endPoint: CGPoint = .zero,
        color: NSColor = .red,
        lineWidth: CGFloat = 3.0,
        shapeType: ShapeType = .freehand,
        isHighlighter: Bool = false
    ) {
        self.points = points
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.shapeType = shapeType
        self.isHighlighter = isHighlighter
    }
}
```

ここに Swift の重要な要素が集約されています。一つずつ見ていきます。

#### `struct Stroke`

`struct` は Swift で **値型(value type)** を定義するキーワードです。Java はクラスしかありませんが、Swift では struct と class を **明確に使い分けます**。

- **struct(値型)**: 代入やメソッド呼び出しで **コピー** される。同じ値を持つインスタンスは「等しい」
- **class(参照型)**: 同じインスタンスは **参照を共有** する。Java のクラスと同じ挙動

`Stroke` は描画データという「値そのもの」を表すので struct がふさわしく、複数の View に渡しても各々が独立したコピーを持ちます。一方、`DrawingState`(描画モードの状態管理)は class で、複数の View が **同じ状態オブジェクトを参照** する必要があるため class です。この使い分けは Swift プログラミングの最重要トピックの一つで、Ch12 で深掘りします。

#### プロパティ宣言

```swift
var points: [CGPoint]
```

`var` は変更可能なプロパティ、`let` なら不変プロパティです。`: [CGPoint]` は型注釈で、`[T]` は `Array<T>` の糖衣構文です。Java で言えば `List<CGPoint> points` に相当します。

`CGPoint` は Apple Foundation の構造体で `(x: CGFloat, y: CGFloat)` の 2 次元座標を表します。`NSColor` は AppKit の色オブジェクト、`CGFloat` は `Double` のプラットフォーム別エイリアスです。

#### `init` — イニシャライザ

```swift
init(
    points: [CGPoint] = [],
    color: NSColor = .red,
    ...
) {
    self.points = points
    ...
}
```

Swift のコンストラクタは `init` という名前で、`new` キーワードはありません。引数に `= []` のような **デフォルト値** を持たせられるのが特徴で、Java のコンストラクタオーバーロード(複数の `Stroke(...)` を書き分ける)を大幅に簡潔化できます。

`= .red` の `.red` は **省略形** で、`NSColor.red` の `NSColor.` 部分を文脈から推論しています(プロパティの型が `NSColor` なので、`.red` だけで `NSColor.red` だと判断される)。これは Swift 全般で多用される糖衣構文です。

`self.points = points` は Java と同じ意味で、引数 `points` をプロパティ `self.points` に格納しています。

> **NOTE**
> 実は struct には **自動生成イニシャライザ(memberwise initializer)** という便利機能があり、`init(...)` を書かなくてもプロパティ全部を引数に取るイニシャライザが自動で作られます。`Stroke` で明示的に `init` を書いているのは、**全引数にデフォルト値を与えるため**(自動生成版にはデフォルト値が付かない)です。詳細は Ch17 で扱います。

## ツアーで見えた Swift の特徴

ここまでわずか 60 行に満たないコードを読みましたが、Swift の主要な特徴が見えてきました。

| 特徴 | 該当箇所 | Java との対比 | 詳細章 |
|---|---|---|---|
| `let` がデフォルト | `let app = ...` | `final` をデフォルトにした感覚 | Ch04 |
| 型推論 | `let app = NSApplication.shared` | Java の `var` より強力 | Ch04 |
| `new` 不要 | `AppDelegate()` | コンストラクタ呼び出しがシンプル | Ch04, Ch17 |
| 値型と参照型 | `struct Stroke` | Java にはない概念 | Ch12 |
| `enum` の強力さ | `enum ShapeType: Sendable` | Java の enum を超える | Ch11 |
| ドキュメンテーション | `///` コメント | Java の `/** */` 相当 | Ch04 |
| プロパティ直接アクセス | `app.delegate = delegate` | getter/setter を書かない | Ch13 |
| デフォルト引数値 | `points: [CGPoint] = []` | Java のコンストラクタオーバーロード代替 | Ch09, Ch17 |
| プロトコル適合 | `: Sendable` | `implements` 相当 | Ch25 |
| 文字列補間 | (未登場) | `"hello \(name)"` の形 | Ch06 |
| クロージャ | (未登場) | Java のラムダの拡張版 | Ch10 |
| Optional | (未登場) | null 安全を型システムで | Ch04, Ch19 |
| async/await | (未登場) | Swift 6 の並行性 | Ch21 |

このうち下半分の項目(クロージャ、Optional、async/await)は **Swift で最も重要だが Java と挙動が違う** ものです。Part II で順に深掘ります。

## ハンズオン(任意): ストロークの初期値を変えてみる

学習体験として、`Stroke.swift` のデフォルト値を変えてビルドしてみましょう。所要時間 5 分。

1. `src/ZoomacIt/Models/Stroke.swift` の `init` で、`color: NSColor = .red` を `color: NSColor = .blue` に変更
2. `make build` でビルド成功を確認
3. もとに戻して再ビルド

これだけで「Swift コードを編集してビルド成功させる」という最小サイクルを体験できます。Ch04 以降は、より意味のある変更で実践していきます。

> **NOTE**
> `make build` がエラーになった場合は、エラーメッセージのファイル名・行番号を確認してください。Swift のエラーメッセージは Java と同様に詳細で、多くの場合「ここをこう直すべき」という Fix-it の提案も付きます。

---

## 次に読む章

→ Part II - [04. The Basics(変数・型・Optional 入門)](../part2-language-guide/04-the-basics.md)
