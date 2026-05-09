# 09. Functions

## この章で学ぶこと

- 関数宣言の基本構文 `func name(...) -> ReturnType` を、Java のメソッドとの対応表で把握する
- Swift 特有の **引数ラベル(argument label)** を理解し、呼び出し側が文章のように読める API を設計できるようになる
- **デフォルト値**・**可変長引数**・**inout パラメータ**・**戻り値タプル** という、Java では別の手段で代用していた機能を Swift の流儀で書けるようになる
- Swift では関数も **第一級オブジェクト(first-class)** であり、変数に入れたり引数に渡せることを知る(詳細は次章 Closures)
- ZoomacIt の `ZoomMath` で実際に「引数ラベル付き関数」がどう設計されているかを読み解く

> **NOTE**
> この章は **ハイブリッド章** です。関数定義そのものは Java と概念的にほぼ同じなので表で素早く流します。一方で「引数ラベル」と「デフォルト値」は Swift の API 設計思想を体現する Swift 特有の機能であり、ここを理解するかどうかで Swift コードの読みやすさが大きく変わります。後半は段落で丁寧に扱います。

---

## 関数定義チートシート

Java のメソッドと Swift の関数は、書き方こそ違いますが意味的にはほぼ同じです。まず形式上の対応関係を一気に押さえます。

| やりたいこと             | Swift                                       | Java                                         |
| ------------------------ | ------------------------------------------- | -------------------------------------------- |
| 関数宣言                 | `func add(a: Int, b: Int) -> Int { ... }`   | `int add(int a, int b) { ... }`              |
| 戻り値なし               | `func log(message: String) { ... }`         | `void log(String message) { ... }`           |
| 戻り値なし(明示)         | `func log(message: String) -> Void { ... }` | (該当なし、`void` のみ)                      |
| 単一式の暗黙 return       | `func square(_ x: Int) -> Int { x * x }`    | (該当なし、必ず `return` が必要)             |
| 関数呼び出し             | `add(a: 1, b: 2)`                           | `add(1, 2)`                                  |
| オーバーロード           | シグネチャが違えば可                        | 同じくシグネチャが違えば可                   |
| 静的メソッド             | `static func ...`(型の中で)                 | `static T ...`                               |

戻り値の型は **`->`** に続けて書きます。戻り値がないときは `-> Void` と書くか、省略します。Swift の `Void` は要素を持たないタプル `()` の別名であり、`void` キーワードではない、というのが Java との小さな違いです。

関数本体が **単一の式** だけからなる場合、`return` は省略できます。`func square(_ x: Int) -> Int { x * x }` のように書けます。ゲッタ的な短い関数で多用される慣習で、Swift コードの簡潔さに寄与しています。

オーバーロードは Java と同じく「シグネチャが違えば共存可能」です。ただし Swift では後述する **引数ラベルもシグネチャの一部** として扱われます。引数の型が同じでもラベルが違えば別関数として共存できる、という Java にはない柔軟さがあります。

---

## 引数ラベル — Swift API 設計の核心

ここから先が、Java 経験者にとって最も新鮮な部分です。

Swift では関数のパラメータに **2 つの名前** を持たせられます。呼び出し側から見える **引数ラベル(argument label)** と、関数本体の中で使う **パラメータ名(parameter name)** です。

```swift
func move(from start: CGPoint, to end: CGPoint) {
    // 関数本体では start / end を使う
    let dx = end.x - start.x
    let dy = end.y - start.y
    // ...
}

// 呼び出し側はラベルを使う
move(from: origin, to: destination)
```

`from`・`to` が引数ラベル、`start`・`end` がパラメータ名です。呼び出し側は `move(from: origin, to: destination)` という、ほぼ英文のような自然な記述になります。これは Java のメソッド呼び出し `move(origin, destination)` では引数の意味が読み取れず、`move(/* from */ origin, /* to */ destination)` のようなコメントで補っていたのと対照的です。

### ラベルを書かないとどうなるか

ラベルを明示せずパラメータ名だけ書くと、**パラメータ名がそのままラベルとして使われます**。

```swift
func add(a: Int, b: Int) -> Int { a + b }
add(a: 1, b: 2)   // ラベルは a と b
```

これは Swift がデフォルトで「呼び出し側でも引数の意味が分かる」ことを優先する設計です。Java から来ると `add(1, 2)` と書きたくなりますが、それはコンパイルエラーになります。

### ラベルを省略する `_`

数学的に明らかな引数や、関数名で意味が完結している場合は、ラベルを **`_`** で省略できます。

```swift
func square(_ x: Int) -> Int { x * x }
square(5)   // ラベルなしで呼べる

func print(_ message: String) { ... }
print("hello")
```

Swift 標準ライブラリの `print(_:)` も、第 1 引数のラベルが `_` で省略されているため `print("hello")` と書けます。逆に言えば、Swift で `print(message: "hello")` のような呼び出しを見かけないのは、ライブラリ側があえて `_` を付けているからです。

### 設計指針 — Swift API Design Guidelines

Apple は公式に [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) を公開しており、引数ラベルの設計について明確な指針を示しています。要点をいくつか抜粋します。

- **第 1 引数のラベルは、関数名と組み合わせて文章になるように選ぶ**(例: `view.addSubview(_:)` の第 1 引数はラベル不要、なぜなら関数名で意味が完結しているから)
- **`from` / `to` / `at` / `with` / `for` / `by` などの前置詞ラベルを積極的に使う**(例: `move(from:to:)`、`insert(_:at:)`)
- **冗長な情報は型から推測できるなら省く**(例: `addSubview(view: NSView)` ではなく `addSubview(_:)`)

Java では「メソッド名にすべての情報を埋め込む」傾向(`moveFromAToB`)がありましたが、Swift では「関数名は最小限にして、ラベルで補う」のが慣習です。

---

## デフォルト値 — オーバーロードを書かなくて済む

Java では「省略可能な引数」を表現するためにオーバーロードを並べて書く必要がありました。

```java
// Java
String greet(String name) { return greet(name, "Hello"); }
String greet(String name, String greeting) { return greeting + ", " + name; }
```

Swift ではパラメータに **デフォルト値** を直接書けるため、1 つの関数で済みます。

```swift
func greet(name: String, greeting: String = "Hello") -> String {
    "\(greeting), \(name)"
}

greet(name: "Alice")                       // "Hello, Alice"
greet(name: "Bob", greeting: "Hi")         // "Hi, Bob"
```

デフォルト値を持つ引数は、呼び出し側で省略できます。複数のデフォルト引数があっても、ラベル付き呼び出しによって **任意の引数だけを指定** できるのが Swift の強みです。Java の可変長引数や Builder パターンで代用していたケースの多くが、Swift ではデフォルト値で素直に表現できます。

> **NOTE**
> デフォルト値はパラメータリストの末尾にある必要は **ありません**。途中のパラメータにもデフォルト値を持たせられます。ラベル付き呼び出しのおかげで「引数の順序」の制約が Java より緩いためです。ただし慣習としては「必須引数を先、デフォルト引数を後」に配置する方が読みやすいとされます。

---

## 可変長引数 — Java の varargs と同じ感覚

可変個の引数を受け取りたい場合は、型の後ろに **`...`** を付けます。

```swift
func sum(_ numbers: Int...) -> Int {
    numbers.reduce(0, +)
}

sum(1, 2, 3)           // 6
sum(1, 2, 3, 4, 5)     // 15
sum()                  // 0
```

関数本体では `numbers` は `[Int]` 型として扱われます。Java の `int... numbers` がメソッド内で `int[]` になるのと同じ発想です。

Swift 5.4 以降では **複数の可変長引数** を 1 つの関数に持たせることもできます(各々ラベルが必要)。Java よりわずかに柔軟ですが、実用上はそこまで多用しません。

---

## inout パラメータ — Java にはない概念

Swift の関数引数は **既定で不変(let)** です。つまり関数本体で引数の値を書き換えることはできません。

```swift
func increment(value: Int) {
    value += 1   // コンパイルエラー: value は let
}
```

Java では引数はローカル変数扱いで自由に書き換えられたので、ここで戸惑う Java エンジニアは多いです。Swift がこの設計を取るのは「引数の書き換えはバグの温床」と見なしているためで、書き換えたい場合は **明示的に `inout`** を付けます。

```swift
func swapValues(_ a: inout Int, _ b: inout Int) {
    let temp = a
    a = b
    b = temp
}

var x = 1
var y = 2
swapValues(&x, &y)   // 呼び出し側は & を付ける
// x == 2, y == 1
```

呼び出し側は引数の前に **`&`** を付ける必要があります。これは「この変数が書き換わる可能性がある」ことを呼び出し側にも視覚的に明示するための設計です。

`inout` は **参照渡し(call by reference)に近い** 振る舞いに見えますが、厳密には違います。意味論的には:

1. 関数呼び出し時に呼び出し側変数の **値をコピーして渡す**(借用)
2. 関数本体ではコピーされた値を自由に変更できる
3. 関数から戻る時点で、変更後の値を **呼び出し側変数に書き戻す**

この「借用 → 書き戻し」モデルは **copy-in copy-out** と呼ばれ、最適化次第で実際にはポインタ渡しに変換されることもありますが、意味論上はあくまで値のやり取りです。Java の参照型引数(オブジェクトは参照渡しに見える)とは別物だと理解しておきましょう。

> **NOTE**
> `inout` パラメータには **デフォルト値を持たせられません**。また、`let` で宣言した変数や定数式を `&` 付きで渡すことはできません(書き戻し先がないため)。

---

## 戻り値タプル — 軽量な複数戻り値

Java で「複数の値を返したい」とき、選択肢は次のいずれかでした。

- 専用クラス(または Java 16 以降は `record`)を定義する
- 配列や `Map` に詰めて返す(型安全性を犠牲にする)
- 引数として渡したオブジェクトに書き込む

Swift には **タプル** という言語機能があり、複数の値をまとめて 1 つの値として返せます(タプル自体は Ch04 で扱いました)。

```swift
func minMax(_ array: [Int]) -> (min: Int, max: Int)? {
    guard let first = array.first else { return nil }
    var currentMin = first
    var currentMax = first
    for value in array.dropFirst() {
        if value < currentMin { currentMin = value }
        if value > currentMax { currentMax = value }
    }
    return (currentMin, currentMax)
}

if let bounds = minMax([3, 1, 4, 1, 5, 9, 2, 6]) {
    print("min = \(bounds.min), max = \(bounds.max)")
    // min = 1, max = 9
}
```

戻り値型 `(min: Int, max: Int)` は **要素にラベルを付けたタプル** です。呼び出し側は `bounds.min` / `bounds.max` という名前でアクセスできます。Java の `record` よりはるかに軽量で、わざわざ型を定義するまでもない局所的な「2 値ペア」に最適です。

空配列の場合に何も返せないことを **`Optional`** で表現している点も注目してください(戻り値型の末尾の `?`)。Java で `null` を返すしかなかった場面が、Swift では型システムで明示されます。

ただし、3 つ以上の値をまとめて返したくなったら、**専用の struct を定義** することを検討してください。タプルは型名がないため、関数間で受け渡すと「このタプルが何を表しているのか」が読み手に伝わらなくなります。

---

## ファーストクラス関数 — 軽い予告

Swift では関数も **第一級オブジェクト** です。つまり関数を変数に代入したり、別の関数の引数や戻り値にできます。

```swift
func double(_ x: Int) -> Int { x * 2 }

let f: (Int) -> Int = double   // 関数を変数に入れる
f(5)                            // 10

let result = [1, 2, 3].map(double)
// [2, 4, 6]
```

`(Int) -> Int` という型は「Int を 1 つ受け取って Int を返す関数の型」を表します。Java 8 以降の `Function<Integer, Integer>` に相当しますが、Swift では言語組み込みの構文として `引数型 -> 戻り値型` で書けます。

Java の `java.util.function.*` インターフェイス(`Function`、`BiFunction`、`Consumer`、`Supplier`、`Predicate` ……)を毎回選ぶ必要はなく、Swift では **関数型はすべて統一された関数型構文** で表現されます。

このトピックは次章 **10. Closures** で本格的に扱います。クロージャは「名前のない関数」であり、関数とほぼ同じものとして扱えるため、Swift ではこの 2 つを連続して学ぶのが自然です。

---

## ZoomacIt 実コード読解 — `ZoomMath` の関数設計

ここまでの知識を、ZoomacIt のズーム計算ユーティリティ `ZoomMath` で実際に確認します。

> 引用元: src/ZoomacIt/Overlay/ZoomMath.swift:9-27

```swift
static func visibleContentsRect(
    zoomLevel: CGFloat,
    panCenter: CGPoint,
    imageSize: CGSize
) -> CGRect {
    let visibleWidth  = 1.0 / zoomLevel
    let visibleHeight = 1.0 / zoomLevel

    let normCenterX = panCenter.x / imageSize.width
    let normCenterY = panCenter.y / imageSize.height

    let originX = clamp(normCenterX - visibleWidth  * 0.5,
                        lower: 0, upper: 1 - visibleWidth)
    let originY = clamp(normCenterY - visibleHeight * 0.5,
                        lower: 0, upper: 1 - visibleHeight)

    return CGRect(x: originX, y: originY,
                  width: visibleWidth, height: visibleHeight)
}
```

注目ポイント:

1. **すべての引数にラベルが付いている**。`visibleContentsRect(zoomLevel:panCenter:imageSize:)` という呼び出し形式で、3 つの引数の意味が呼び出し側からも明確に読み取れます。`_` でラベルを省略していないのは、引数の意味が型(`CGFloat`、`CGPoint`、`CGSize`)だけからは伝わらないためです。
2. **`static func`**。Java の `static` メソッドと同じく、インスタンスを作らずに `ZoomMath.visibleContentsRect(...)` の形で呼び出せます。`ZoomMath` 自体が `enum` で宣言されている(インスタンス化されないことが保証される)のは Swift のユーティリティ型の典型的なパターンです。
3. **戻り値型 `CGRect`**。`Void` ではない普通の関数で、`->` 以降に戻り値型を書きます。

次に、ラベル省略と名前付き引数を **混在** させた例を見ます。

> 引用元: src/ZoomacIt/Overlay/ZoomMath.swift:50-54

```swift
static func clampZoomLevel(_ level: CGFloat,
                           minimum: CGFloat = 1.0,
                           maximum: CGFloat = 8.0) -> CGFloat {
    clamp(level, lower: minimum, upper: maximum)
}
```

ここには本章で学んだほぼすべての要素が詰まっています。

- **第 1 引数のラベルが `_`** で省略されている。関数名 `clampZoomLevel` だけで「ズームレベルをクランプする」と意味が通るため、第 1 引数の名前を冗長に書かない設計です。呼び出し側は `clampZoomLevel(2.5)` と書けます。
- **第 2・第 3 引数にはラベル `minimum` / `maximum` が付いている**。これらは「省略可能な微調整」だと示すための明示的なラベルです。
- **デフォルト値 `1.0` と `8.0`** が設定されている。多くの場面では `clampZoomLevel(level)` だけで呼べ、特殊な範囲を指定したいときだけ `clampZoomLevel(2.5, minimum: 1.5, maximum: 4.0)` のように上書きできます。
- **単一式の暗黙 return**。本体は `clamp(level, lower: minimum, upper: maximum)` の 1 行のみで、`return` キーワードがありません。

この 1 関数だけで「ラベル省略・名前付き引数・デフォルト値・単一式 return」という Swift 関数設計の主要要素を網羅していることが分かります。

呼び出し例を比較してみましょう。

```swift
// 既定の範囲(1.0〜8.0)で十分な場合
let safe = ZoomMath.clampZoomLevel(userInput)

// 一時的に上限を 4.0 に絞りたい場合
let restricted = ZoomMath.clampZoomLevel(userInput, maximum: 4.0)

// 両端を変えたい場合
let custom = ZoomMath.clampZoomLevel(userInput, minimum: 0.5, maximum: 2.0)
```

Java で同じ柔軟性を得ようとすると、3 つのオーバーロード(引数 1 個、2 個、3 個)を並べる必要があったはずです。Swift ではデフォルト値とラベル付き呼び出しの組み合わせで、1 関数だけで同等の使い勝手を提供できます。

---

## ハンズオン(任意)

以下は学習用の練習課題です。手を動かして確かめたい場合に取り組んでください。

1. `func format(date: Date, style: String = "short", locale: String = "ja_JP") -> String` というシグネチャの関数を宣言し、Java の同等メソッドだとオーバーロードがいくつ必要になるかを考えてみてください
2. `func divide(_ a: Int, by b: Int) -> (quotient: Int, remainder: Int)?` を実装してください。`b == 0` のときは `nil` を返します。タプルラベル `quotient` / `remainder` で呼び出し側がどう書けるかを確認してください
3. `swapValues(_:_:)` を `inout` を使わずに書こうとするとどうなるかを試し、なぜ Swift がこの機能を持っているかを体感してください

---

## 次に読む章

→ [10. Closures](./10-closures.md)

関数を「名前のない値」として扱う **クロージャ** を学びます。`map` / `filter` / `reduce` のようなコレクション操作で多用され、Swift コードの簡潔さの中核を担う機能です。本章で軽く触れたファーストクラス関数の話題も、次章で本格的に展開します。
