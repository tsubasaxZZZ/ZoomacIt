# 31. Advanced Operators

## この章で学ぶこと

Part II の最終章です。これまで Ch05 で扱った算術・比較などの基本演算子に加え、Swift には **ビット演算子**、**オーバーフロー演算子**、**演算子のオーバーロード**、そして **カスタム演算子** といった「上級」機能が揃っています。

これらは日常コードで頻繁に書くものではありませんが、Apple のフレームワークを読むうえで避けて通れません。たとえば `NSEvent.ModifierFlags` のような **OptionSet** 型は内部的にビットマスクで実装されており、`[.shift, .control]` という配列リテラルで複数フラグを表現します。Carbon API と橋渡しする箇所では `|=` や `& != 0` といった C 言語譲りのビット演算が今でも生きています。

この章は **チートシート章** です。各機能の定義と最低限の使用例、そして ZoomacIt 内での実例を素早く確認することを目的とします。Java 出身の方には大半が見覚えのある内容なので、**Swift 固有の差分** (`OptionSet`、`&+` 系、`precedencegroup`) に重点を置いて読み進めてください。

---

## ビット演算子 — Java とほぼ同じ

Swift の整数型 (`Int`、`UInt32`、`UInt8` など) は、Java と同じビット演算子を提供します。

| 演算子 | 意味 | 例 |
|--------|------|----|
| `&` | AND | `0b1100 & 0b1010 == 0b1000` |
| `\|` | OR | `0b1100 \| 0b1010 == 0b1110` |
| `^` | XOR | `0b1100 ^ 0b1010 == 0b0110` |
| `~` | NOT (ビット反転) | `~UInt8(0b00001111) == 0b11110000` |
| `<<` | 左シフト | `1 << 3 == 8` |
| `>>` | 右シフト | `16 >> 2 == 4` |

```swift
let mask: UInt8  = 0b0000_1111
let value: UInt8 = 0b1010_1010
let lowNibble = value & mask          // 0b0000_1010 == 10
let merged    = value | 0b0100_0000   // 0b1110_1010
let toggled   = value ^ 0b1111_0000   // 0b0101_1010
```

数値リテラル中の `_` は桁区切りです (Ch05 を参照)。8 ビットや 32 ビットのフラグを読み解くときには必ず使うようにすると可読性が上がります。

### 符号付き整数の右シフトに注意

`Int` のような符号付き整数では、右シフトは **算術シフト** (符号ビットで詰める) になります。`UInt` のような符号なし整数では **論理シフト** (0 で詰める) です。Java の `>>` と `>>>` の違いに相当しますが、Swift では型側で挙動が決まるため演算子は `>>` の 1 つだけです。

---

## オーバーフロー演算子 — `&+ &- &*`

Swift は既定では整数オーバーフローをランタイムエラーにします。

```swift
let max = Int.max
let bad = max + 1   // ランタイムクラッシュ
```

これは Java と異なる Swift の **安全側の設計** です。意図的にラップアラウンド (Java のような巻き戻し) を許可したい場合は、専用の **オーバーフロー演算子** を使います。

```swift
let max = UInt8.max          // 255
let wrapped = max &+ 1       // 0 にラップ
let neg     = UInt8.min &- 1 // 255 にラップ
let big     = UInt8(200) &* 2 // 144 (= 400 mod 256)
```

ハッシュ計算、暗号、CRC、PRNG、ピクセル演算など **ビット精度で巻き戻しを期待するアルゴリズム** にだけ使ってください。通常の業務ロジックで使うとバグの温床になります。

---

## OptionSet — Apple 流のビットマスク表現

ここからが本章の主役です。Cocoa/AppKit の API には「複数のフラグを 1 引数で渡す」インターフェースが多数あります。代表例が `NSEvent.ModifierFlags` (修飾キーの集合) です。

### 配列リテラルで複数フラグを表現

`OptionSet` プロトコルに準拠した型は、`Set` のような操作 (`contains`, `insert`, `remove`, `union`, `intersection`) を提供しつつ、**配列リテラルで初期化** できる特徴を持ちます。

```swift
let mods: NSEvent.ModifierFlags = [.shift, .control]
mods.contains(.shift)   // true
mods.contains(.command) // false
```

### ZoomacIt 実例 — 修飾キーから図形タイプを決定

Draw モードでドラッグ中に押されている修飾キーで描画する図形の種類を切り替えます。`NSEvent.ModifierFlags` の `contains(_:)` がそのまま使えます。

```swift
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

> 引用元: src/ZoomacIt/Models/DrawingState.swift:68-83

`OptionSet` のおかげで、ビットマスクであることを意識せずに **集合演算の API** で書けています。これが Swift らしいラップ方式です。

### OptionSet を自作する

自作するには `OptionSet` に準拠し、`rawValue` を `Int` などのビット幅のある整数型にし、各ケースを **2 のべき乗** で定義します。

```swift
struct DrawCapability: OptionSet {
    let rawValue: UInt8

    static let freehand  = DrawCapability(rawValue: 1 << 0) // 0b0000_0001
    static let line      = DrawCapability(rawValue: 1 << 1) // 0b0000_0010
    static let rectangle = DrawCapability(rawValue: 1 << 2) // 0b0000_0100
    static let ellipse   = DrawCapability(rawValue: 1 << 3) // 0b0000_1000
    static let arrow     = DrawCapability(rawValue: 1 << 4) // 0b0001_0000

    static let shapes: DrawCapability = [.line, .rectangle, .ellipse, .arrow]
    static let all:    DrawCapability = [.freehand, .shapes]
}

let caps: DrawCapability = [.freehand, .line]
caps.contains(.line)      // true
caps.intersection(.shapes) // [.line]
```

`Set` と違うのは、**裏では 1 個の整数値** であることです。コピーが軽く、API 境界 (Carbon、C ライブラリ) との橋渡しに最適です。

### Carbon と橋渡しするときは生のビット演算が必要

`OptionSet` で抽象化されていない C 由来の API (Carbon の `controlKey`、`shiftKey` など) を扱うときは、生のビット演算で読み解く必要があります。ZoomacIt では Carbon の `RegisterEventHotKey` API に渡すために変換ユーティリティを持っています。

```swift
/// Converts Carbon modifier flags to NSEvent.ModifierFlags.
static func carbonToNSEventModifiers(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
    var flags = NSEvent.ModifierFlags()
    if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if carbonModifiers & UInt32(optionKey)  != 0 { flags.insert(.option) }
    if carbonModifiers & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
    if carbonModifiers & UInt32(cmdKey)     != 0 { flags.insert(.command) }
    return flags
}

/// Converts NSEvent.ModifierFlags to Carbon modifier flags.
static func nsEventToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    if flags.contains(.option)  { carbon |= UInt32(optionKey) }
    if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    return carbon
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:324-341

`& != 0` で立っているビットを検査し、`|=` でビットを立てる典型的な C スタイルです。Swift 内部で完結する処理なら `OptionSet` の `contains`/`insert` を使い、外部 API との境界でだけ生のビット演算に降りる、というのが健全な使い分けです。

---

## 演算子のオーバーロード

Swift では、既存演算子 (`+`、`-`、`==`、`<` など) を **独自型に拡張** できます。Java では不可能ですが、C++ の operator overloading や Kotlin の `operator fun plus` に相当します。

`extension` 内で `static func` として定義します。

```swift
struct Vector2D {
    var x: Double
    var y: Double
}

extension Vector2D {
    static func + (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static prefix func - (v: Vector2D) -> Vector2D {
        Vector2D(x: -v.x, y: -v.y)
    }

    static func += (lhs: inout Vector2D, rhs: Vector2D) {
        lhs = lhs + rhs
    }
}

let a = Vector2D(x: 1, y: 2)
let b = Vector2D(x: 3, y: 4)
let c = a + b           // (4, 6)
let d = -a              // (-1, -2)
var e = a; e += b       // (4, 6)
```

修飾子の意味:

- `static func +` は **infix** (中置) 演算子の既定形
- `static prefix func -` は **prefix** (前置) — `-a`
- `static postfix func ...` は **postfix** (後置)

### 等価比較とハッシュ — `Equatable` / `Hashable` でほぼ自動

`==` を独自型に提供したいだけなら、自分で書くより `Equatable` 準拠で済ませるのが定石です (Ch12 で扱いました)。プロパティが全て `Equatable` ならコンパイラが `==` を合成してくれます。

```swift
struct Point: Equatable {
    let x: Int
    let y: Int
}
// Point(x:1, y:2) == Point(x:1, y:2) → true (自動)
```

`Comparable` も同様で、`<` を 1 つ書くか合成に任せるかで `>`, `<=`, `>=` まで揃います。**演算子オーバーロードを手書きする前に、準拠だけで済まないかを確認してください。**

---

## カスタム演算子

Swift では既存演算子の拡張だけでなく、**まったく新しい演算子** を定義できます。記号の組み合わせで自由に名付けられます。

```swift
infix operator ** : MultiplicationPrecedence

func ** (base: Double, exponent: Double) -> Double {
    pow(base, exponent)
}

let p = 2.0 ** 10.0   // 1024.0
```

宣言は 2 段階です。

1. `infix operator ** : MultiplicationPrecedence` — 演算子の **トークン** と **優先順位グループ** をファイルスコープで宣言
2. `func ** (...)` — 実装本体

`prefix operator` / `postfix operator` も同様に書けます。優先順位グループは前置・後置には付けません。

### 推奨されないケースが大半

カスタム演算子は強力ですが、**Swift コミュニティの慣習として、業務コードでは推奨されません**。理由は明確です。

- **可読性が低下する** — 記号の意味は呼び出し側からはわからない。`**` が累乗なのか XOR なのか、推測できない
- **検索性が悪い** — 関数名なら grep できるが、`**` のような記号は検索が難しい
- **チームに学習コストを強いる** — Apple SDK の慣用句 (`?.`、`??`、`...`) と紛れる

実用的な目安は次のとおりです。

- **数学/物理ライブラリ** で記号が業界標準として確立している場合 (例: ベクトルのドット積 `·`、外積 `×`) は許容される
- **自分のアプリのドメイン** に新しい記号を導入する正当な理由はまずない。**普通の関数 / メソッドにしてください**

ZoomacIt にカスタム演算子はありません。これは健全な選択です。

---

## 優先順位グループ — `precedencegroup`

カスタム演算子に新しい優先順位を持たせたいときは `precedencegroup` を宣言します。

```swift
precedencegroup ForwardApplicationPrecedence {
    associativity: left
    higherThan: AssignmentPrecedence
    lowerThan: TernaryPrecedence
}

infix operator |> : ForwardApplicationPrecedence

func |> <T, U>(value: T, transform: (T) -> U) -> U {
    transform(value)
}

let result = 5 |> { $0 * 2 } |> { $0 + 1 }   // 11
```

宣言できる属性:

| 属性 | 意味 |
|------|------|
| `associativity` | `left` / `right` / `none` (連続適用時の結合方向) |
| `higherThan` | この優先順位より高い既存グループ |
| `lowerThan` | この優先順位より低い既存グループ |
| `assignment` | `true` にすると optional chaining 越しの代入として扱われる |

標準ライブラリには `AssignmentPrecedence`、`TernaryPrecedence`、`LogicalDisjunctionPrecedence`、`ComparisonPrecedence`、`AdditionPrecedence`、`MultiplicationPrecedence`、`BitwiseShiftPrecedence` などのグループが既に用意されています。**ほとんどの場合、既存グループを `infix operator` の宣言に指定すれば足り、`precedencegroup` を新たに書く機会はまずありません。**

---

## ZoomacIt 実コード読解 — 修飾キー判定の流れ

本章で扱った概念がアプリ内でどうつながっているかを最後にまとめます。

1. **OS から届く** — マウスドラッグ時、AppKit が `NSEvent` を配信し、`event.modifierFlags` で `NSEvent.ModifierFlags` (OptionSet) が取れる
2. **ZoomacIt が解釈** — `DrawingState.currentShapeType(modifiers:)` が `.contains(.shift)` などで図形タイプを決める (`DrawingState.swift:68-83`)
3. **Carbon との変換** — ホットキー登録時のみ、`Settings.nsEventToCarbonModifiers(_:)` で `|=` を使ったビット演算で `UInt32` に変換する (`Settings.swift:324-341`)
4. **表示用文字列化** — `Settings.hotkeyDisplayString(keyCode:modifiers:)` が `& != 0` で各ビットを検査し、`⌃` `⌥` `⇧` `⌘` を組み立てる (`Settings.swift:278-286`)

`OptionSet` の高水準 API が使える内側ではそれで完結させ、C 由来 API との境界でだけ生のビット演算に降りる、という二段構えになっています。

---

## ハンズオン (任意)

余力があれば、自前の `OptionSet` を 1 つ定義してみてください。

- `struct LogLevel: OptionSet` を作り、`.debug`, `.info`, `.warning`, `.error` をビット位置で定義する
- `static let verbose: LogLevel = [.debug, .info]` のような複合エイリアスを用意する
- `func log(_ message: String, level: LogLevel)` を作り、内部で `level.contains(.error)` で出力先を分岐する

これで `OptionSet` が **Set 風 API + 整数 1 個分のメモリ** の二重性を持っていることが体感できます。

---

## 次に読む章

これで Part II — Swift 言語ガイドは完了です。Java と Swift の言語機能の差分を一通り押さえました。

次は ZoomacIt のアーキテクチャを実コードベースで深掘りする Part III に進みます。最初のテーマは、本アプリが採用している **AppKit と SwiftUI の混在戦略** です。なぜメニューバーは AppKit で、設定画面だけ SwiftUI なのか — その理由と境界の作り方を読み解きます。

→ Part III - [32. AppKit と SwiftUI の混在](../part3-zoomacit-deep-dive/32-appkit-vs-swiftui.md)
