# 14. Methods

## この章で学ぶこと

- Swift のメソッド宣言が Java の `void name(...)` / 戻り値型先頭表記から **`func name(...) -> Returns`** に変わる、という形の違いを押さえる
- インスタンスメソッドにおける `self` が Java の `this` と同じ役割を果たすこと、そして暗黙的に省略できることを理解する
- Swift 特有の **`mutating` キーワード** が、なぜ struct (値型) においてのみ必要なのかを「値型の安全性」という観点から腹落ちする
- **`static func` と `class func` の違い** を理解し、サブクラスでオーバーライドさせたい型メソッドだけ `class func` を選択できるようになる
- Swift のメソッド呼び出しに現れる **引数ラベル** が、Apple API の流暢さ (`array.insert(value, at: index)`) を支えていることを再確認する
- ZoomacIt の `Settings` の static メソッド群、`PenColor.from(character:)`、`DrawingState.currentShapeType(modifiers:)` を実コードで読み解く

> **NOTE**
> この章は **ハイブリッド章** です。「インスタンスメソッド」「static メソッド」といった大枠は Java とほぼ同じです。本章で時間を割くのは Swift 特有の 3 点 — `mutating` / `static` vs `class` / 引数ラベル — に限定します。

---

## Java との対応 (まず結論)

| 観点 | Java | Swift |
| --- | --- | --- |
| インスタンスメソッド宣言 | `int compute(int x) { ... }` | `func compute(_ x: Int) -> Int { ... }` |
| 戻り値の位置 | メソッド名の **前** | `->` の **後ろ** |
| `void` の表記 | `void doSomething()` | `func doSomething()` (戻り値型を省略) |
| 自インスタンス参照 | `this` | `self` |
| 型に属するメソッド | `static` | `static func` または `class func` |
| 値型のミューテーション | (Java に値型なし) | **`mutating func`** が必須 |
| サブクラスで override 可能な型メソッド | `static` メソッドは原則隠蔽のみ | `class func` のみ override 可 |

骨格は Java とほぼ同じです。差分は **値型の存在** と **オーバーライド可能な型メソッド** に集約されます。

---

## 14.1 インスタンスメソッドの基本

最も素朴な書き方は、Ch09 で学んだトップレベル関数を型の中にそのまま入れただけです。

```swift
struct Counter {
    var count: Int = 0

    func describe() -> String {
        return "count = \(count)"
    }
}

let c = Counter(count: 3)
print(c.describe())  // "count = 3"
```

`func` キーワードがそのまま使え、戻り値型は `->` の後ろに書きます。Java と違い、戻り値が無いメソッドは `-> Void` を完全に省略できます (`-> Void` と明示しても等価です)。

### `self` は Java の `this` と同じ

メソッド本体の中では、自身のインスタンスを `self` で参照できます。Java の `this` と意味は完全に同じです。

```swift
struct Point {
    var x: Double
    var y: Double

    func distance(to other: Point) -> Double {
        let dx = self.x - other.x
        let dy = self.y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

Java と同じく、プロパティ名と引数名がぶつからない場合は `self.` を省略できます。

```swift
func distance(to other: Point) -> Double {
    let dx = x - other.x   // self.x の self を省略
    let dy = y - other.y
    return (dx * dx + dy * dy).squareRoot()
}
```

慣習として、Swift コミュニティでは **必要な時だけ `self.` を書く** のが好まれます。具体的には、引数名とプロパティ名が衝突するケース、クロージャの中でキャプチャを明示したいケース (Ch10 で扱いました)、イニシャライザでプロパティ初期化を行うケースの 3 つです。それ以外は省略するのが標準です。

---

## 14.2 `mutating` メソッド — Swift 最大の特徴

ここからが本章の本丸です。Swift には Java に存在しない概念として **値型 (struct, enum)** があります (Ch12 で詳述)。値型は **デフォルトで immutable** であり、メソッド内からプロパティを変更するには `mutating` キーワードを明示する必要があります。

### なぜ struct はデフォルト immutable なのか

そもそもなぜ Swift の struct はメソッドからのプロパティ変更を禁止するデフォルトを取っているのでしょうか。理由は **値型としての安全性を保証するため** です。

値型は代入やメソッド呼び出しのたびに **コピー** されます (実装上は Copy-on-Write で最適化されますが、意味論上はコピーです)。つまり、ある struct を変数に渡しても、呼び出し元の値は変わらないことが保証されます。これが値型の最大の強みです。

しかし、もしメソッドが自由にプロパティを書き換えられてしまうと、「このメソッドを呼ぶと自分の値も変わるのか、それとも変わらないのか」がコードを読む側からは判別できなくなります。Swift はそれを防ぐため、**プロパティを変更するメソッドには `mutating` を明示することを義務付け**、呼び出し元が「この呼び出しは状態変更を伴う」と一目で分かるようにしています。

### 構文

```swift
struct StrokeBuffer {
    var points: [CGPoint] = []

    // 状態を変更しないメソッドは普通の func
    func count() -> Int {
        return points.count
    }

    // 状態を変更するメソッドは mutating func
    mutating func add(point: CGPoint) {
        points.append(point)
    }

    mutating func clear() {
        points.removeAll()
    }
}
```

呼び出し側は意識せず普通に書けます。

```swift
var buffer = StrokeBuffer()
buffer.add(point: CGPoint(x: 0, y: 0))
buffer.add(point: CGPoint(x: 10, y: 5))
print(buffer.count())  // 2
```

### `let` で束縛したインスタンスでは mutating メソッドを呼べない

ここが値型ならではの厳格さです。`let` で束縛されたインスタンスは丸ごと immutable とみなされ、`mutating` メソッドの呼び出し自体がコンパイルエラーになります。

```swift
let buffer = StrokeBuffer()
buffer.add(point: .zero)
// error: cannot use mutating member on immutable value: 'buffer' is a 'let' constant
```

これは `buffer.points = [...]` のような直接代入が `let` で禁止されるのと同じ理屈です。`mutating` メソッドは「内部的に `self` を書き換える宣言」なので、`let` のインスタンスに対しては適用できません。修正するには `var` に変更します。

```swift
var buffer = StrokeBuffer()
buffer.add(point: .zero)  // OK
```

Java しか経験がないとこの挙動は新鮮です。Java では `final` 変数に束縛しても、参照先のオブジェクトのメソッドは自由に呼べます (`final List<String> list = ...; list.add("x");` は合法)。Swift の値型は **束縛の不変性が中身の不変性まで波及する** という、より強い保証を持っているわけです。

### enum でも mutating は使える

`mutating` は struct だけでなく enum でも有効です。enum のメソッド内で `self` 自体を別の case に切り替えることもできます。

```swift
enum Toggle {
    case on
    case off

    mutating func flip() {
        self = (self == .on) ? .off : .on
    }
}

var t = Toggle.off
t.flip()  // t == .on
```

### class には `mutating` が要らない (= 書けない)

class は参照型 (Java のクラスと同じ) なので、メソッドからプロパティを書き換えることに何の制約もありません。`mutating` キーワードは class では使えませんし、書く必要もありません。

ZoomacIt の `DrawingState` は `final class` として宣言されており、`increasePenWidth()` / `decreasePenWidth()` のようなプロパティを書き換えるメソッドにも `mutating` は付いていません。

```swift
final class DrawingState {
    var penWidth: CGFloat = Settings.shared.defaultPenWidth

    /// Increase pen width (capped at 50).
    func increasePenWidth() {
        penWidth = min(penWidth + 1.0, 50.0)
    }

    /// Decrease pen width (minimum 1).
    func decreasePenWidth() {
        penWidth = max(penWidth - 1.0, 1.0)
    }
}
```

class の場合、`let state = DrawingState()` のように `let` で束縛しても、`state.increasePenWidth()` は問題なく呼べます。`let` が制約するのは「`state` という変数を別のインスタンスに差し替えること」だけで、参照先のオブジェクトの中身までは縛らない、という Java と同じ挙動です。

---

## 14.3 型メソッド — `static func` と `class func`

型自体に紐付くメソッド (Java で言う static メソッド) は、Swift では **`static func`** または **`class func`** で宣言します。

### `static func` (struct / enum / class すべてで使える)

最もよく使うのは `static func` です。Java の `public static` メソッドとほぼ同じ感覚で書けます。

```swift
struct MathUtil {
    static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        return Swift.max(min, Swift.min(max, value))
    }
}

let v = MathUtil.clamp(120, min: 0, max: 100)  // 100
```

ZoomacIt では `Settings` の Display Utilities セクションが典型的な使用例です。Carbon API のキーコードを人間可読な文字列に変換するロジックは、状態を持たないただの変換処理なので、すべて `static func` として宣言されています。

```swift
// src/ZoomacIt/Models/Settings.swift
final class Settings {
    /// Converts a Carbon key code and modifier mask to a human-readable shortcut string.
    static func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        parts += keyCodeToString(keyCode)
        return parts
    }

    static func keyCodeToString(_ keyCode: UInt32) -> String { /* ... */ }
    static func keyCodeToMenuCharacter(_ keyCode: UInt32) -> String { /* ... */ }
    static func carbonToNSEventModifiers(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags { /* ... */ }
    static func nsEventToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 { /* ... */ }
}
```

呼び出しは Java と同じ「型名 + ドット」の形式です。

```swift
let label = Settings.hotkeyDisplayString(keyCode: 18, modifiers: 0x1000)
// "⌃1"
```

### enum 内の static メソッド

`static func` は enum でも使えます。ZoomacIt の `PenColor` には、ホットキーで押された文字 (`R`, `G`, `B`, ...) を `PenColor` に変換するファクトリ的な static メソッドが定義されています。

```swift
// src/ZoomacIt/Models/DrawingState.swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink

    /// Map from key character to pen color.
    static func from(character: String) -> PenColor? {
        switch character.uppercased() {
        case "R": return .red
        case "G": return .green
        case "B": return .blue
        case "O": return .orange
        case "Y": return .yellow
        case "P": return .pink
        default:  return nil
        }
    }
}
```

呼び出し側は `PenColor.from(character: "r")` のように使い、`Optional<PenColor>` を受け取ります。

```swift
if let color = PenColor.from(character: pressedKey) {
    drawingState.activeColor = color
}
```

このように、Swift では Java の「`MyEnum.valueOf(...)` だと例外になる、自前で安全な変換用メソッドを生やしたい」というケースを enum 自身に static method として持たせることが慣習化しています。

### `class func` — オーバーライド可能な型メソッド (class 限定)

ここが Swift 特有のもう 1 つの論点です。`static func` で宣言された型メソッドは、**サブクラスから override できません**。これは struct / enum / class すべてに共通する挙動です。

サブクラスでオーバーライドさせたい型メソッドを class に持たせたい場合は、`static func` の代わりに **`class func`** を使います。

```swift
class Logger {
    class func prefix() -> String {
        return "[BASE]"
    }

    func log(_ message: String) {
        print("\(Self.prefix()) \(message)")
    }
}

class DebugLogger: Logger {
    override class func prefix() -> String {
        return "[DEBUG]"
    }
}

Logger().log("hello")        // [BASE] hello
DebugLogger().log("world")   // [DEBUG] world
```

| キーワード | 使える型 | サブクラスで override |
| --- | --- | --- |
| `static func` | struct / enum / class | **不可** |
| `class func` | **class のみ** | 可 (final 指定で禁止可) |

実用上は **「迷ったら `static func` を使う」** で十分です。`class func` が要るのは、フレームワーク的に「テンプレートメソッドパターンを型レベルで実現したい」「サブクラスごとに違う設定値を返させたい」という、限定的な設計を取るときだけです。ZoomacIt のコードベースでは `class func` は登場しません — 状態を持たない純粋なユーティリティはすべて `static func` で十分だからです。

なお、Swift には `static` を override 可能にする「もう 1 つの書き方」として `static final` の対義として `class` がある、と理解するのが分かりやすいです。`class func` は事実上 **「override 可能な static func」** と読み替えられます。`final class func` と書けば、それ以上の override を禁止できます。

---

## 14.4 引数ラベル — 流暢な API デザイン

Ch09 で学んだ関数の **引数ラベル** は、メソッドにもそのまま適用されます。これは Apple のフレームワーク API が「英文として読み下せる」スタイルになっている根拠でもあります。

### Apple API の典型例

```swift
var array = [1, 2, 4, 5]
array.insert(3, at: 2)            // "insert 3 at 2"
array.remove(at: 0)               // "remove at 0"
array.replaceSubrange(1...2, with: [9, 9])
```

最初の引数は `_` でラベルを省略し (`insert` の主目的語)、2 番目以降に `at:` `with:` などの **前置詞ラベル** を付けます。これにより `array.insert(3, at: 2)` が「3 を 2 の位置に挿入する」と英文として読めます。

### ZoomacIt の例

`DrawingState` のインスタンスメソッドにも、同じ流儀のラベルが見られます。

```swift
// src/ZoomacIt/Models/DrawingState.swift
func currentShapeType(modifiers: NSEvent.ModifierFlags) -> ShapeType {
    let hasShift = modifiers.contains(.shift)
    let hasControl = modifiers.contains(.control)

    if isTabHeld {
        return .ellipse
    } else if hasShift && hasControl {
        return .arrow
    } else if hasShift {
        return .line
    } else if hasControl {
        return .rectangle
    } else {
        return .freehand
    }
}
```

呼び出しは `state.currentShapeType(modifiers: event.modifierFlags)` となり、「modifiers に基づいて現在の shape type を返す」という意図がコード上に表れます。

`PenColor.from(character:)` も同じ思想です。`PenColor.from("R")` ではなく `PenColor.from(character: "R")` と書かせることで、「文字列から PenColor を作る」ことが呼び出し側で明示されます。

### Java とのスタイル差

Java では `array.insert(2, 3)` のように引数の意味は変数名やオーバーロードで表現するか、Builder パターンで補うのが一般的でした。Swift の引数ラベルは、これを言語機能のレベルで一段階優雅に解決した仕組み、と捉えると馴染みやすいです。

ラベル設計の一般原則は Ch09 にまとまっていますが、メソッドを書くときの実務的なガイドラインだけ再掲します。

- 第 1 引数は **メソッド名と一体で読める** ようにラベルを省略 (`array.append(x)`, `set.contains(x)`)
- 第 2 引数以降は **前置詞ラベル** を付ける (`at:`, `with:`, `from:`, `to:`, `for:`)
- ラベルが意味を持たない場合 (純粋な数学関数など) は `_` で省略する

---

## 14.5 ZoomacIt 実コード読解

`Settings` と `DrawingState` から、メソッド設計の「使い分け」を読み取ります。

### `Settings.hotkeyDisplayString(...)` — 純粋な変換は static

ホットキー設定の表示文字列生成は、入力 (キーコード + 修飾子) のみから出力 (`"⌃1"` のような文字列) が決まる、副作用も状態依存もない処理です。このような純粋関数は、インスタンスにぶら下げる必然性がありません。Swift では迷わず `static func` にします。

```swift
static func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
    var parts = ""
    if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
    parts += keyCodeToString(keyCode)
    return parts
}
```

別の static メソッド `keyCodeToString(_:)` を、同じ `Settings` 型内から `Settings.` を付けずに呼んでいる点にも注目してください。同じ型のスコープ内では、static メソッドの相互呼び出しに型名修飾は不要です (Java と同様)。

### `PenColor.from(character:)` — enum のファクトリは static

文字列を enum に変換する処理は、論理的には `PenColor` に属するものの、特定のインスタンスとは関係ありません。こうしたファクトリ的な処理を **enum 自身の static メソッド** として置く設計は、Swift の標準ライブラリでも `URL(string:)` などの failable initializer と双璧をなすパターンです。

```swift
static func from(character: String) -> PenColor? {
    switch character.uppercased() {
    case "R": return .red
    case "G": return .green
    case "B": return .blue
    case "O": return .orange
    case "Y": return .yellow
    case "P": return .pink
    default:  return nil
    }
}
```

戻り値が `PenColor?` (Optional) になっている点も Swift らしい設計です。Java の `valueOf` のように例外を投げるのではなく、変換不能を `nil` で表現します。詳細は Ch16 (Optionals) で扱います。

### `DrawingState.currentShapeType(modifiers:)` — 純粋関数的な instance method

このメソッドは引数 `modifiers` と自身のプロパティ `isTabHeld` を見て、対応する `ShapeType` を返します。状態は読みますが書き換えはしないため、`mutating` は不要です (そもそも `DrawingState` は class なので `mutating` という選択肢自体がありません)。

`if isTabHeld` の部分が「インスタンス状態を参照している」唯一の箇所で、これがあるからこそインスタンスメソッドにする価値があります。もし完全に引数だけで決まるロジックだったら、`static func currentShapeType(modifiers:tabHeld:)` の方が筋が良くなります。

### `DrawingState.increasePenWidth()` — 状態を変更する instance method

```swift
func increasePenWidth() {
    penWidth = min(penWidth + 1.0, 50.0)
}
```

プロパティ `penWidth` を書き換える典型的な instance method です。`DrawingState` は `final class` なので `mutating` は不要 — もしこれを `struct DrawingState` に書き換えると、両方のメソッドに `mutating` を付ける必要が出てきます。

```swift
// もし struct だったら...
struct DrawingState {
    var penWidth: CGFloat = 1.0

    mutating func increasePenWidth() {
        penWidth = min(penWidth + 1.0, 50.0)
    }

    mutating func decreasePenWidth() {
        penWidth = max(penWidth - 1.0, 1.0)
    }
}
```

ZoomacIt が `DrawingState` を class にしている理由はいくつかありますが、一つには **複数のビュー (キャンバス, ツールバー, 設定パネル) が同じ状態を共有したい** という要件があり、参照型の方が自然だからです。値型と参照型の使い分けは Ch12 で詳しく扱います。

---

## 14.6 ハンズオン (任意)

学んだ内容を手を動かして確認するための小課題です。

### 課題 1: struct + mutating

`Counter` という struct を定義し、以下を満たしてください。

- `var value: Int = 0` プロパティを持つ
- `mutating func increment()` で `value` を 1 増やす
- `mutating func reset()` で `value` を 0 に戻す
- `func describe() -> String` で `"value = N"` を返す (mutating ではない)

`var c = Counter()` で作って `increment()` を 3 回呼び、`describe()` で `"value = 3"` が返ることを確認してください。次に `let frozen = Counter()` で作って `frozen.increment()` を呼ぼうとし、コンパイルエラーが出ることを確認してください。

### 課題 2: enum の static メソッド

`Direction` enum を定義し、`static func from(character: String) -> Direction?` を実装してください。`"N"` `"S"` `"E"` `"W"` をそれぞれ `.north` `.south` `.east` `.west` に変換し、それ以外は `nil` を返します。`PenColor.from(character:)` のパターンの再現です。

### 課題 3: static vs class

class `Greeter` を定義し、`static func greeting() -> String` で `"Hello"` を返してください。次にサブクラス `LoudGreeter: Greeter` を作り、`override static func greeting() ...` で `"HELLO!"` を返そうとして、コンパイルエラーになることを確認してください。`static` を `class` に変えると override できるようになります。

---

## まとめ

- Swift のメソッド宣言は `func name(...) -> ReturnType` の 1 形式で、戻り値型は名前の **後** に来る
- `self` は Java の `this` と同じ。慣習として、衝突しない限り省略する
- struct (値型) のプロパティを変更するメソッドは **`mutating func`** で明示する。これは「呼び出すと自分の値が変わる」ことを呼び出し側に知らせるための仕組みで、`let` で束縛されたインスタンスでは呼び出せない
- 値型がデフォルト immutable なのは、コピー前提の値型として **「メソッド呼び出しが状態変更を伴うか」を読みやすくする** ため
- 型メソッドは **`static func`** が基本。class に限り、サブクラスで override させたいときだけ **`class func`** を選ぶ
- 引数ラベルは関数と同じく Swift API の流暢さを支える根幹。第 1 引数はメソッド名と一体で読めるようにラベル省略、第 2 引数以降は前置詞ラベルを付ける、が定石
- ZoomacIt では純粋な変換ロジックは `Settings` の `static func`、enum のファクトリは `PenColor.from(character:)`、状態を読むだけ / 書き換えるロジックは `DrawingState` の通常 `func` (class なので `mutating` 不要) と、明確な使い分けが見られる

## 次に読む章

→ [15. Subscripts](./15-subscripts.md)
