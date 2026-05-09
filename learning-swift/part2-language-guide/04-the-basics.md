# 04. The Basics(変数・型・Optional 入門)

## この章で学ぶこと

- Swift における変数・定数の宣言方法と、Java の `final` との対応関係
- 型推論がどこまで効き、どこで型注釈が必要になるか
- Swift の *Optional*(オプショナル) が言語レベルで提供する null 安全のしくみ
- 強制アンラップ `!` の意味と、それが推奨されない理由
- nil 合体演算子 `??` を用いたデフォルト値の与え方

前章 Ch03「Swift Tour」では、`let`・`var`・`struct` といった構文を駆け足で眺めた。本章ではそれらを体系的に説明し、特に Java から移ってきた読者がつまずきやすい Optional の概念を導入する。

---

## 1. チートシート(Java 経験者向け)

Swift の基本構文には、Java と同じ概念を別の綴りで表現したものが多い。まず対応関係を表にまとめる。コードの細部はあとで本文で深掘りする。

| 概念 | Java | Swift | 補足 |
|---|---|---|---|
| 可変変数 | `int x = 10;` | `var x = 10` | Swift ではセミコロン不要 |
| 不変変数 | `final int x = 10;` | `let x = 10` | `let` がデフォルトで推奨 |
| 型注釈 | `String s = "hi";` | `let s: String = "hi"` | コロンの後に型を書く |
| 型推論 | `var s = "hi";`(Java 10+) | `let s = "hi"` | Swift では関数戻り値・タプルにも効く |
| null を許す型 | `String s = null;` | `var s: String? = nil` | Swift では型自体が `?` で区別される |
| null チェック | `if (s != null) ...` | `if let s = s { ... }` | *Optional Binding* という構文 |
| デフォルト値 | `s != null ? s : "x"` | `s ?? "x"` | nil 合体演算子 |
| null セーフ呼び出し | `Optional<T>.map(...)` | `s?.count` | Optional Chaining(Ch19 で詳述) |
| 強制取り出し | `s.get()`(`Optional<T>`) | `s!` | クラッシュ要因。多用しない |
| 整数型 | `int` / `long` | `Int` / `Int64` | `Int` はプラットフォーム幅 |
| 浮動小数 | `double` | `Double` | リテラルの既定型は `Double` |
| 真偽値 | `boolean` | `Bool` | `true` / `false` |
| 文字列 | `String` | `String` | 値型(struct)である点が異なる |

> **NOTE** Swift の `String` は値型(`struct`)であり、代入やコピーで別の実体になる。Java の `String`(参照型・不変)とは設計が異なる。本章では深入りしないが、Ch09 で再訪する。

---

## 2. 解説本文

### 2.1 `let` がデフォルトという哲学

Swift では、変数を宣言するキーワードが二つある。`let` は *定数*(constant)を、`var` は *変数*(variable)を宣言する。

```swift
let maximumPenWidth = 50      // 一度束縛したら再代入できない
var currentPenWidth = 1       // 再代入できる

currentPenWidth = 5           // OK
// maximumPenWidth = 60       // コンパイルエラー
```

Java では再代入を禁じるために `final` を付ける必要があり、付け忘れる方が一般的だった。Swift はこれを反転させ、`let`(不変)を「短い綴り」に、`var`(可変)を「明示的な選択」にした。Apple 公式の『The Swift Programming Language』も「値が変更されないなら必ず `let` を使うこと」を推奨している。

なぜ「不変がデフォルト」なのか。理由は二つある。

第一に、*ローカル推論* が容易になる。`let` で宣言された値はそのスコープ内で絶対に変わらないため、コードを読む人は「あとで書き換えられているかもしれない」という疑いを持たなくてよい。

第二に、*並行処理の安全性* が高まる。Swift 6 では並行処理に関するチェックが強化されており、不変な値は複数のスレッドから同時にアクセスしても安全だと型システムが判定できる。`var` を選んだ瞬間、コンパイラは「本当に共有して良いのか」を問う追加のチェックを始める。

> **NOTE** 「とりあえず `var` で書いて、最後に `let` に直す」というスタイルは Swift では非推奨である。Xcode は再代入されない `var` に対して警告を出し、`let` への変更を提案する。最初から `let` で書くほうが摩擦が少ない。

### 2.2 型推論の射程

Swift の *型推論*(type inference) は、変数の初期値から型を自動的に導く機能である。

```swift
let title = "ZoomacIt"        // String と推論される
let count = 42                // Int と推論される
let ratio = 3.14              // Double と推論される
let isActive = true           // Bool と推論される
```

ここまでは Java 10 以降の `var` と同じに見える。しかし Swift の型推論は、ローカル変数の宣言に留まらず、より広い範囲に効く。

**関数の戻り値型** は引数と本体から推論される(ただし関数定義そのものでは戻り値型を書く必要がある)。**クロージャ**(Java のラムダに相当) では、コンテキストから引数型・戻り値型がほぼ全て推論される。

```swift
let numbers = [1, 2, 3]
let doubled = numbers.map { $0 * 2 }   // [Int] と推論される
```

**タプル**(複数の値を一つにまとめた軽量な型) もそのままの形で推論される。

```swift
let point = (x: 10, y: 20)             // (x: Int, y: Int) と推論される
let dx = point.x                       // Int
```

一方、型注釈を *書くべき* 場面もある。

- 初期値が無い、または初期化を後回しにする場合
- リテラルの既定型と異なる型を使いたい場合(例: `Double` ではなく `CGFloat` を使う)
- API の境界(public な関数のシグネチャ)で意図を明示したい場合

```swift
var penWidth: CGFloat = 1.0           // Double ではなく CGFloat を意図
let unresolved: String                // 後で代入する。型注釈は必須
```

> **NOTE** 数値リテラルの既定型は、整数なら `Int`、小数なら `Double` である。AppKit / SwiftUI では座標やサイズに `CGFloat` を用いることが多いため、ZoomacIt のソースには `CGFloat = 1.0` のような型注釈付き宣言が頻出する。

### 2.3 Optional —— 型システムによる null 安全

ここからが、Java からの移行で最も丁寧に学ぶべき箇所である。

Swift では、ある型の値を **nil(Java の null に相当)にできるかどうか** を、型そのもので区別する。値があるかもしれないし無いかもしれない、という型を *Optional*(オプショナル) と呼び、型名の後ろに `?` を付けて表す。

```swift
var name: String = "Sam"        // 必ず String が入る。nil 不可
var nickname: String? = nil     // String? は nil もしくは String を保持する
nickname = "Sammy"              // OK
```

`String` と `String?` は、**型として別物** である。`String?` を `String` の引数として渡すことはできない。コンパイル段階でエラーになる。

```swift
func greet(_ s: String) { print("Hi, \(s)") }
greet(nickname)                 // コンパイルエラー: String? を String に渡している
```

これが Swift の null 安全の核心である。NullPointerException は実行時に初めて顔を出すが、Swift では「nil かもしれない値を、nil 不可な場所に渡そうとした」時点でコンパイラが拒絶する。

#### Java の `Optional<T>` との違い

Java 8 で導入された `Optional<T>` は、ライブラリで提供されるラッパークラスである。一方、Swift の Optional は **言語と型システムに組み込まれた機能** である。違いを整理する。

| 観点 | Java `Optional<T>` | Swift `T?` |
|---|---|---|
| 提供者 | 標準ライブラリ | 言語そのもの |
| nil の表現 | `Optional.empty()` | `nil` キーワード |
| null 不許容の保証 | なし(`String` でも null を入れられる) | あり(`String` には絶対に nil が入らない) |
| 値の取り出し | `get()`、`orElse()` 等のメソッド | `if let`、`??`、`!` 等の言語構文 |
| 普及度 | 戻り値の一部で使用される程度 | あらゆる API で標準的に使われる |

要するに Java の `Optional<T>` は「null を回避するための任意のイディオム」だが、Swift の `T?` は「言語が強制する設計」である。

#### Optional の値を取り出す三つの方法

`String?` から実際の `String` を取り出す方法は、主に三つある。

**(1) Optional Binding(`if let`)** —— もっとも安全で推奨される方法。

```swift
let nickname: String? = readNickname()
if let nickname = nickname {
    print("Hello, \(nickname)")     // ここでは nickname は String 型
} else {
    print("No nickname set")
}
```

`if let` は、Optional に値があれば中身を取り出して新しい定数に束縛し、無ければ `else` ブロックに進む。Swift 5.7 以降は同名で短縮できる。

```swift
if let nickname {                   // 右辺省略形
    print("Hello, \(nickname)")
}
```

**(2) nil 合体演算子(`??`)** —— 「nil ならこの値を使う」というデフォルト値の与え方。

```swift
let displayName = nickname ?? "Anonymous"   // String 型
```

これは Java の `Objects.requireNonNullElse(nickname, "Anonymous")` や、`Optional.orElse("Anonymous")` に相当する。

**(3) 強制アンラップ(`!`)** —— 「絶対に nil ではない」と開発者が断言する書き方。

```swift
let nickname: String? = "Sam"
let s = nickname!                   // String 型
print(s.count)
```

しかし、もし `nickname` が `nil` だったら、このプログラムは **その場でクラッシュする**(実行時エラー: `Unexpectedly found nil while unwrapping an Optional value`)。Java の `NullPointerException` と本質的に同じ事故が起きる。

> **NOTE** 強制アンラップ `!` は、Swift の null 安全をわざわざ無効にする操作だと考えてよい。「nil でないことが論理的に保証されているが、型システムには表現しきれない」という限定的な場面でのみ使う。学習段階では、`!` を書いた瞬間に「本当にここで `if let` や `??` ではダメか」と立ち止まることを習慣にしてほしい。

なお、宣言時に `String!` のように書く *Implicitly Unwrapped Optional*(暗黙アンラップ) という形式もあるが、これは古い Objective-C ブリッジのために残された機能であり、新しいコードでは原則使わない。本書でも Ch19 まで触れない。

---

## 3. ZoomacIt の実コードを読む

実際のコードベースで、ここまでの概念がどのように使われているかを観察する。題材は `DrawingState` クラスで、ペンの色や太さといった「描画状態」を保持するモデルである。

> 引用元: src/ZoomacIt/Models/DrawingState.swift:32-39

```swift
/// Mutable drawing state that drives the rendering.
final class DrawingState {

    // MARK: - Pen Properties

    var activeColor: PenColor = Settings.shared.defaultPenColor
    var penWidth: CGFloat = Settings.shared.defaultPenWidth
    var isHighlighterMode: Bool = false
```

ここで観察すべき点を三つ挙げる。

第一に、`final class DrawingState` の `final` は **継承を禁止する** Java と同じ意味のキーワードである。Swift では「継承される可能性のないクラス」をコンパイラが最適化できるため、明示的に `final` を付ける慣習がある。Java の `final` 変数とは別物なので注意してほしい(変数の不変性は `let` で表す)。

第二に、三つのプロパティ宣言はすべて `var` である。`activeColor` も `penWidth` も `isHighlighterMode` も、ユーザー操作によって描画中に変化するため可変でなければならない。`var` を選ぶのはこのような正当な理由がある時に限る。

第三に、それぞれの宣言は型注釈と初期値を併記している。`PenColor` は同じファイル冒頭で定義された列挙型、`CGFloat` は AppKit 由来の浮動小数型、`Bool` は真偽値である。`Bool` はリテラル `false` から推論できるため、本来 `: Bool` を省略してもよいが、AppKit のプロパティと並べたときの可読性を優先して明示している。これは「型推論できるからといって、必ず省略するのが正解とは限らない」という良い実例である。

次に、Optional の利用例を見る。`DrawingState` には Tab キーが押されているかを保持するフラグがある。

> 引用元: src/ZoomacIt/Models/DrawingState.swift:47-48

```swift
/// Tab key must be tracked via keyDown/keyUp since it's not a modifier flag.
var isTabHeld: Bool = false
```

ここでは「押されている / 押されていない」の二値で十分なので、`Bool` を使っており Optional は使われていない。**Optional は「値が無い状態」が意味を持つ場合だけに使う** という設計判断の好例である。「押されていない = false」のように既定値で表せるなら、Optional にする必要は無い。

最後に、計算プロパティ(*computed property*) の例を見る。

> 引用元: src/ZoomacIt/Models/DrawingState.swift:61-65

```swift
/// The NSColor to use for drawing, applying highlighter alpha if needed.
var currentNSColor: NSColor {
    let base = activeColor.nsColor
    return isHighlighterMode ? base.withAlphaComponent(Settings.shared.highlighterOpacity) : base
}
```

`currentNSColor` は値を保持せず、参照されるたびに `activeColor` と `isHighlighterMode` から計算して返す *計算プロパティ* である。Java で言えば getter のみのフィールド風メソッドにあたる。本章のテーマに関係する箇所だけ取り上げると次のとおり。

- `let base = activeColor.nsColor` —— 計算途中の中間値は **`let`** で宣言されている。再代入の予定が無いなら `let` を使う、という原則どおりである。
- 戻り値型は `NSColor`(非 Optional)。「マーカーモードかどうかに関わらず、必ず色は決まる」という意味が型に表れている。もし「色が未設定の状態もありうる」なら `NSColor?` になっただろう。

このように、Swift では **型を見るだけで「nil になりうるか」「再代入されるか」が分かる**。コードレビューや読解のコストが大きく下がる。

---

## 4. ハンズオン

ここまでの内容を手で確かめるため、Xcode の *Playground* を使った 10 分程度の練習問題を一つ用意した。Playground は使い捨ての Swift 実験場で、Xcode の `File > New > Playground...` から作成できる。

### 課題: ペン色のキー入力解決

ZoomacIt の `PenColor` 列挙型には、キー文字(`"R"`, `"G"`, ...)から色を引く `from(character:)` というメソッドがある。これをミニチュア版として再現し、Optional の取り扱いを練習する。

次のスケルトンを Playground に貼り付け、`TODO` を埋めて完成させてほしい。

```swift
enum Color {
    case red, green, blue
}

func color(from key: String) -> Color? {
    switch key.uppercased() {
    case "R": return .red
    case "G": return .green
    case "B": return .blue
    default:  return nil
    }
}

// TODO 1: "R" を渡したときの結果を Optional Binding で取り出し、
//         値があればその色名を、無ければ "unknown" を出力する

// TODO 2: "X"(対応しないキー)を渡したときの結果に、
//         nil 合体演算子で .red をデフォルトとして与え、定数に代入する

// TODO 3: "G" を渡したときの結果を強制アンラップ(!)で取り出してみる。
//         そのうえで、入力を "X" に変えるとどうなるか確認する
```

期待される観察結果は次のとおり。

- **TODO 1** では、`if let` を使うことで「nil の可能性がある値」を「nil でない値」へ安全に変換できる。
- **TODO 2** の結果の型は `Color`(非 Optional)である。`??` でデフォルトを与えると、Optional の `?` が外れる。
- **TODO 3** で `"X"` を渡すと、Playground は `Fatal error: Unexpectedly found nil while unwrapping an Optional value` で停止する。これが強制アンラップの危険性そのものである。

仕上げに、自分で書いた `!` を `??` か `if let` に書き換えてみてほしい。同じ動作が、より安全に表現できることが体感できる。

---

## 次に読む章

→ [05. Basic Operators](./05-basic-operators.md)
