# 24. Extensions

## この章で学ぶこと

Swift の **extension (拡張)** は、既存の型に対して後付けで機能を追加する仕組みです。自分が書いた型はもちろん、標準ライブラリの `String` や `Array`、Apple フレームワークの `NSScreen` や `CGContext` といった「ソースコードに手を入れられない型」に対しても、メソッド・computed property・イニシャライザ・protocol 適合などを後から差し込めます。

Java にはこれに相当する言語機能がありません。Java で「`String` に `isBlank()` のような便利メソッドを生やしたい」と思ったら、`StringUtils.isBlank(s)` のような static utility クラスを書くか、`String` を継承した別クラスを作る (`String` は final なので不可) しかありませんでした。Swift ではそれを `s.isBlank` のように **元の型のメンバとして自然に呼び出せる** 形で実現できます。

本章では extension の基本構文、何が追加できて何ができないか、protocol 適合の追加、機能別ファイル分割、Apple フレームワーク拡張の定石パターンを順に見ていきます。最後に ZoomacIt で実際に使われている 3 つの extension を読み解きます。なお、protocol そのものの詳細は次章 [25. Protocols](./25-protocols.md) で扱うため、本章では「extension で protocol 適合を追加できる」という事実のみに留めます。

---

## 基本構文

extension は `extension` キーワードに続けて、拡張対象の型名と中括弧で囲んだメンバ定義で構成されます。

```swift
extension SomeType {
    // 追加するメソッド・computed property・イニシャライザ などをここに書く
}
```

宣言場所は同じモジュール内であれば任意のファイルで構いません。複数のファイルに同じ型の extension を分散させても、コンパイラが集約して 1 つの型として扱います。

たとえば `Int` に「2 乗を返す」computed property を追加するには次のように書きます。

```swift
extension Int {
    var squared: Int {
        self * self
    }
}

let n = 7
print(n.squared)  // 49
```

`squared` はあたかも `Int` 本来のプロパティであるかのように、ドット記法で呼び出せます。これが extension の中核的な体験です。

`String` にメソッドを生やすこともできます。

```swift
extension String {
    func truncated(to length: Int) -> String {
        guard count > length else { return self }
        return String(prefix(length)) + "…"
    }
}

let title = "ZoomacIt - macOS Menu Bar App"
print(title.truncated(to: 10))  // "ZoomacIt -…"
```

extension は **元の型のソースコードに何も手を入れません**。にもかかわらず、`String` のインスタンスから直接 `truncated(to:)` を呼び出せます。これが Java の `StringUtils.truncate(s, 10)` との決定的な違いです。

---

## Java との対比

Java で既存型を「拡張する」手段は、歴史的に次の 2 つに限られていました。

| アプローチ | 例 | 制約 |
|---|---|---|
| **継承 (subclassing)** | `class MyString extends String` | `String` は `final` なので不可。`final` でない型でも、新しいインスタンスを作る箇所すべてで `MyString` に置き換える必要がある |
| **static utility メソッド** | `StringUtils.isBlank(s)` (Apache Commons Lang) | 呼び出し側が `s.isBlank()` ではなく `StringUtils.isBlank(s)` という外部関数呼び出しになる。IDE 補完にも出にくい |

Java 8 で `default` メソッドが入り、interface に実装を持たせて既存クラスに混ぜる余地は広がりましたが、それでも「対象クラス側で `implements` を宣言する」必要があるため、ライブラリ提供型に後付けはできません。

Swift の extension はこの両方の制約を取り払います。

```swift
// Java 風 (utility 関数)
// String result = StringUtils.truncate(title, 10);

// Swift (extension で生やす)
let result = title.truncated(to: 10)
```

呼び出し側のコードは、その型に最初から組み込まれているメソッドと完全に区別がつきません。ドキュメントツール (Quick Help) や Xcode の補完候補にも、本来のメソッドと同列に並びます。

> Apache Commons Lang の `StringUtils.isEmpty(s)` を毎度書いていた感覚が、Swift では `s.isEmpty` に変わる。これが extension の体験を一言で言い表したものです。

---

## extension で追加できるもの

extension では以下のメンバを既存型に追加できます。

1. **Computed property** (instance / static / type) — 値の計算結果を返すプロパティ
2. **Instance method / type method** — 通常のメソッド
3. **Initializer** — 新しい初期化方法 (struct の場合は memberwise initializer を温存できる利点あり)
4. **Subscript** — `instance[key]` 構文
5. **Nested type** — 章 23 で見たネスト型
6. **Protocol 適合** — `extension Foo: SomeProtocol` の形

簡単な例で網羅すると次のようになります。

```swift
struct Point {
    var x: Double
    var y: Double
}

extension Point {
    // 1. Computed property
    var magnitude: Double {
        (x * x + y * y).squareRoot()
    }

    // 2. Method
    func translated(dx: Double, dy: Double) -> Point {
        Point(x: x + dx, y: y + dy)
    }

    // 3. Initializer (元の memberwise init を残したまま追加できる)
    init(polar radius: Double, angle: Double) {
        self.x = radius * Foundation.cos(angle)
        self.y = radius * Foundation.sin(angle)
    }

    // 4. Subscript
    subscript(axis: String) -> Double? {
        switch axis {
        case "x": return x
        case "y": return y
        default: return nil
        }
    }

    // 5. Nested type
    enum Quadrant {
        case first, second, third, fourth
    }
}
```

特に **3 番目の initializer 追加** は Swift 特有の重要な性質を持ちます。struct に独自 init を本体内に書くと、自動生成される memberwise initializer が失われますが、extension で init を追加した場合は memberwise initializer が温存されます。これは「struct を簡潔に保ちつつ、便利な初期化口を追加する」用途で頻繁に使われるテクニックです。

---

## extension で追加できないもの

一方、extension には次の 2 つの明確な禁止事項があります。

### 1. Stored property は追加できない

```swift
extension Int {
    var cache: String = ""  // コンパイルエラー
}
```

理由は、stored property を追加すると **その型のメモリレイアウトが変わってしまう** からです。`Int` は 8 バイトという固定サイズで世界中のコードがレイアウトを前提に動いており、誰かが extension で stored property を追加した瞬間にバイナリ互換性が壊れます。これは Swift というよりプログラミング言語設計上の必然的な制約です。

回避策は computed property を使うことです。どうしても状態を持ちたい場合は、Objective-C 由来の Associated Object を使う裏技もありますが、AppKit / SwiftUI のモダンコードではほぼ使いません。

### 2. 既存メンバの override はできない

```swift
extension String {
    func uppercased() -> String {  // 元の uppercased() を上書き不可
        return "OVERRIDDEN"
    }
}
```

これも禁止されています。extension は **既存機能の拡張** であって **置き換え** ではありません。同名のメソッドを書くと、Swift 6 ではコンパイルエラーまたは曖昧解決の警告になります。挙動を変えたければサブクラス化 (class の場合) や独自型でラップしてください。

| できる | できない |
|---|---|
| Computed property | Stored property |
| Method (新規) | Method の override |
| Initializer (convenience 相当) | Designated initializer の差し替え (class の場合) |
| Subscript | 既存 subscript の上書き |
| Protocol 適合の追加 | 既存 protocol 適合の置き換え |

---

## Protocol 適合の追加

extension のもっとも強力な使い道のひとつが、**既存型に protocol 適合を後付けする** ことです。構文は `extension SomeType: SomeProtocol { ... }` です。

```swift
protocol Describable {
    var description: String { get }
}

extension Int: Describable {
    var description: String {
        "整数値: \(self)"
    }
}

let n: Describable = 42
print(n.description)  // "整数値: 42"
```

`Int` は標準ライブラリの型でソースに触れられませんが、それでも `Describable` への適合を後から差し込めます。これにより「自分が定義した protocol に、他人が作った型を後で適合させる」ことが可能になります。Java の interface ではクラス側で `implements` を書く必要があるため、この芸当はできませんでした。

ZoomacIt の実コードでも、`Notification.Name` (Apple のフレームワーク型) に対して static let を生やすために extension を多用しています (後述)。protocol 適合の話の詳細と protocol 自体の設計指針は、次章 [25. Protocols](./25-protocols.md) で改めて扱います。

---

## 機能別ファイル分割

extension はもうひとつ重要な使い方があります。**1 つの自作型を、機能カテゴリごとに複数の extension に分割して書く** というスタイルです。

```swift
// MyClass.swift
class MyClass {
    var name: String
    init(name: String) { self.name = name }
}

// MyClass+Validation.swift
extension MyClass {
    func validate() -> Bool { /* ... */ }
    func sanitize() { /* ... */ }
}

// MyClass+Networking.swift
extension MyClass {
    func fetch() async throws -> Data { /* ... */ }
    func upload(_ data: Data) async throws { /* ... */ }
}
```

クラス本体には核となるプロパティと初期化のみを書き、ビジネスロジックや I/O は別ファイルの extension に追い出します。これにより以下の利点が得られます。

- **1 ファイル 1 関心事**: 巨大なクラスを論理的なブロックに分割できる (Java の「partial class が欲しい」感覚に近い)
- **diff の局所化**: ネットワーク機能を変えるときに validation のコードが diff に紛れない
- **読みやすい目次**: ファイルツリーを見れば機能区分が一目でわかる

ファイル名規約として **`Type+Description.swift`** という命名が Apple コミュニティで定着しています。`+` の後ろに「何を追加した extension か」を簡潔に書きます。

| ファイル名 | 中身 |
|---|---|
| `String+Truncation.swift` | `String` に truncation 系メソッドを追加 |
| `MyClass+Validation.swift` | `MyClass` に validation 関連メソッドを追加 |
| `UIColor+Hex.swift` | `UIColor` に hex 文字列対応の init を追加 |

ZoomacIt も `CGContext+Extensions.swift` / `NSScreen+Extensions.swift` という命名でこの規約に従っています。

---

## Apple フレームワーク拡張の定石: Notification.Name

Apple フレームワーク型を extension で拡張する用途で、もっとも頻出するパターンが **`Notification.Name` への static let 追加** です。

`NotificationCenter` で通知を投げる際、通知名は `Notification.Name` 型で表現します。文字列リテラルを直接書くとタイポに弱く、grep もしにくいので、static let で名前空間に集約するのが定石です。

```swift
extension Notification.Name {
    static let userDidLogin = Notification.Name("userDidLogin")
    static let userDidLogout = Notification.Name("userDidLogout")
}

// 投げる側
NotificationCenter.default.post(name: .userDidLogin, object: nil)

// 受ける側
NotificationCenter.default.addObserver(
    forName: .userDidLogin,
    object: nil,
    queue: .main
) { _ in /* ... */ }
```

`.userDidLogin` というドット記法は Swift の型推論によって `Notification.Name.userDidLogin` に解決されます。これにより通知名が型システムで管理され、Xcode の補完にも出るようになります。

---

## ZoomacIt 実コード読解

ここからは ZoomacIt の実コードを 3 つ読み解き、extension の典型的な使い方を体感します。3 例とも「Apple のフレームワーク型に対して utility を後付けする」というパターンで、ファイル名規約も `Type+Extensions.swift` に従っています。

### 例 1: `CGContext` にビットマップコンテキスト生成のファクトリを追加

`CGContext` は Core Graphics の描画コンテキストで、Apple のフレームワーク型です。ZoomacIt の Draw レイヤーでは「現在のスクリーンサイズに合わせた RGBA ビットマップコンテキスト」を頻繁に生成する必要がありますが、生の `CGContext.init` 呼び出しは引数が多く、毎回書くのは煩雑です。そこで static method を extension で追加しています。

```swift
import CoreGraphics
import AppKit

extension CGContext {

    /// Creates an RGBA bitmap context matching the given size, suitable for
    /// compositing drawing strokes.
    static func createBitmapContext(size: CGSize) -> CGContext? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
    }
}
```

> 引用元: src/ZoomacIt/Utilities/CGContext+Extensions.swift:1-26

このコードのポイントは次の 3 点です。

- **対象は Apple のフレームワーク型** (`CGContext`)。ソースには触れられないが extension で拡張できる
- **追加しているのは static method** (`static func`)。インスタンスメソッドではなく型レベルのファクトリとして提供
- **呼び出し側は `CGContext.createBitmapContext(size: ...)` という極めて自然な書き味**になる

呼び出し例は次のようになります。

```swift
guard let ctx = CGContext.createBitmapContext(size: screen.pixelSize) else {
    return
}
```

もし extension がなければ、毎回 `CGContext(data: nil, width: ..., height: ..., bitsPerComponent: 8, ...)` という長大な初期化を Draw レイヤーの複数箇所で繰り返すことになります。extension により、ZoomacIt 固有の「ビットマップ生成方針」を 1 箇所に閉じ込められています。

### 例 2: `NSScreen` にユーティリティプロパティ群を追加

`NSScreen` は AppKit のスクリーン (ディスプレイ) を表すクラスです。ZoomacIt は複数ディスプレイ環境を前提としており、「マウスが今どのスクリーンにあるか」「Retina スケールを考慮したピクセルサイズはいくつか」を頻繁に取得します。これらは `NSScreen` 本来の API を組み合わせれば取得できますが、毎回書くのは冗長です。そこで extension で 1 つの static property と 2 つの instance computed property を追加しています。

```swift
import AppKit

extension NSScreen {

    /// Returns the screen that contains the mouse cursor.
    static var screenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    /// The display's backing scale factor (Retina = 2.0, standard = 1.0).
    var displayScaleFactor: CGFloat {
        backingScaleFactor
    }

    /// The pixel dimensions of the screen (accounting for Retina scaling).
    var pixelSize: CGSize {
        CGSize(
            width: frame.width * backingScaleFactor,
            height: frame.height * backingScaleFactor
        )
    }
}
```

> 引用元: src/ZoomacIt/Utilities/NSScreen+Extensions.swift:1-25

ここで注目すべきは次の点です。

- **`screenContainingMouse` は `static var`**: `NSScreen.screenContainingMouse` のように型から直接呼び出せる。インスタンスを持たずに呼ぶ必要があるため static にしている
- **`displayScaleFactor` と `pixelSize` は instance computed property**: 特定の `NSScreen` インスタンスに対して `screen.pixelSize` のようにドット記法で呼べる
- **stored property は一切使っていない**: 前述のとおり extension で stored property は追加できないので、すべて計算結果として返す

呼び出し側のコードは次のように非常に読みやすくなります。

```swift
guard let screen = NSScreen.screenContainingMouse else { return }
let size = screen.pixelSize
let scale = screen.displayScaleFactor
```

これらが extension でなく自由関数 (`getScreenContainingMouse()` のような) だったら、コードのあちこちでドット記法と関数呼び出しが混在し、可読性が落ちていたはずです。

### 例 3: `Notification.Name` に通知名を集約

3 つ目は Apple フレームワーク拡張の定石、`Notification.Name` への static let 追加です。`Settings.swift` の末尾にこの extension が置かれています。

```swift
// MARK: - Notification

extension Notification.Name {
    static let settingsDidReset = Notification.Name("settingsDidReset")
    static let hotkeysDidChange = Notification.Name("hotkeysDidChange")
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:344-349

このコードでは `Notification.Name` という Foundation の型に、ZoomacIt 固有の通知名 2 つ (`settingsDidReset`, `hotkeysDidChange`) を static let として追加しています。

呼び出し側はドット記法で通知名を指定できます。

```swift
// 投げる側
NotificationCenter.default.post(name: .settingsDidReset, object: nil)

// 受ける側
NotificationCenter.default.addObserver(
    forName: .hotkeysDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.reloadHotkeys()
}
```

`.settingsDidReset` は文脈から `Notification.Name.settingsDidReset` に解決されます。文字列リテラルが 1 箇所に集約されているので、

- **タイポが防げる**: `"settingsDidReset"` を 2 度書く機会がない
- **Xcode の補完が効く**: `.s` まで打てば候補が出る
- **grep / 名前変更が容易**: `settingsDidReset` で全文検索すれば、定義と参照がすべて見つかる

という 3 つの恩恵が得られます。`MARK: - Notification` というコメントで区切られているのも、ファイル内の論理ブロックを明示する Apple 流の慣習です。

### 3 例から見えるパターン

3 例に共通するのは、**「対象が Apple フレームワーク型」「追加するのは utility 的な小さなメンバ」「ファイル名は `Type+Extensions.swift` 規約」** という 3 点です。これは Swift / AppKit プロジェクトで extension を使う際の王道パターンであり、ZoomacIt はそれを忠実になぞっています。

なお `Notification.Name` の extension だけは独立ファイルではなく `Settings.swift` の末尾に同居しています。これは「通知名は `Settings` のリセット・更新と論理的に強く結びついている」ためで、無理にファイルを分けるよりは関連コードを近くに置く判断が優先されています。ファイル分割は必須ではなく、設計判断であることが分かります。

---

## ハンズオン (任意)

学習を定着させたい方は、次の課題に取り組んでみてください。

1. **`Double` に `radians` プロパティを追加する**: 度数を渡したら radian を返す computed property を extension で書く (`90.0.radians == .pi / 2`)
2. **`Array` に `safe` subscript を追加する**: 範囲外アクセスで crash せず `nil` を返す `subscript(safe index: Int) -> Element?` を実装する
3. **`Notification.Name` に独自通知名を 1 つ追加する**: `.userDidUpdateProfile` のような名前を定義し、`post` / `addObserver` の両方を試す
4. **既存の自作型を機能別に分割する**: 100 行以上ある自作クラスを `Foo.swift` / `Foo+Validation.swift` / `Foo+Persistence.swift` に分割してみる

`extension` で追加した API が、本来のメンバと完全に同じ書き味で呼び出せることを体感できれば成功です。

---

## まとめ

extension は Swift の中でもっとも「Java からの移植時に新鮮な驚きを与える」機能の 1 つです。これまで static utility クラスや継承で何とかしていた拡張が、`s.isEmpty` のような自然なメンバ呼び出しに変わります。

押さえるべき要点を再掲します。

- **構文は `extension SomeType { ... }`**。自作・標準ライブラリ・Apple フレームワーク、すべてに使える
- **追加できる**: computed property、method、initializer、subscript、nested type、protocol 適合
- **追加できない**: stored property、既存メンバの override
- **protocol 適合の後付け**は extension の最強の使い道のひとつ (詳細は次章)
- **ファイル分割**で 1 つの型を機能別に整理できる。命名規約は `Type+Description.swift`
- **`Notification.Name` への static let 追加**は Apple FW 拡張の定石

---

## 次に読む章

→ [25. Protocols](./25-protocols.md)
