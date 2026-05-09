# 26. Generics

## この章で学ぶこと

ジェネリクスは、**型を抽象化したコード** を書くための仕組みです。同じロジックを `Int` 用と `String` 用で書き分けるのではなく、「任意の型 `T` に対して動くコード」として一度だけ書き、利用側で具体的な型を当てはめます。Java を 5 年以上書いてきた読者にとって、概念そのものは目新しくないはずです。`List<E>`、`Map<K, V>`、`Comparable<T>` ── あれと同じ発想を Swift に翻訳します。

ただし、Java と Swift のジェネリクスには **決定的に異なる一点** があります。Java はコンパイル後に型パラメータ情報を捨てる **型消去 (type erasure)** を採用しているのに対し、Swift は **コンパイル時にも実行時にも型情報を完全に保持** します。この違いは API の表現力、性能、デバッグ体験すべてに波及します。本章ではそこを章の核心として扱います。

本章の構成は以下の通りです。

- ジェネリック関数の基本構文
- ジェネリックな型 (struct / class / enum)
- 型制約 (`<T: Equatable>` および `where` 句)
- protocol の associated type との連携
- ジェネリック関数の戻り値型
- Java のジェネリクスとの違い ── 型消去について
- Opaque Types (`some`) への橋渡し
- ジェネリクスと Protocol Extension の組み合わせ

ZoomacIt 本体には「自分で型パラメータを宣言した型」の良い実例が薄いため、本章では教材専用のサンプル (`samples/ch26-generics/`) を主軸に解説します。

---

## 1. ジェネリック関数の基本

最初の例は、Java のチュートリアルでもおなじみの「2 変数を入れ替える関数」です。型ごとに `swapInt`、`swapString`、`swapDouble` と書き分けるのは明らかに無駄なので、ジェネリクスで一本化します。

```swift
func swap<T>(_ a: inout T, _ b: inout T) {
    let temp = a
    a = b
    b = temp
}

var x = 1
var y = 2
swap(&x, &y)
print(x, y)  // 2 1

var s1 = "hello"
var s2 = "world"
swap(&s1, &s2)
print(s1, s2)  // world hello
```

注目点は 2 つです。

- 関数名の直後の `<T>` が **型パラメータ宣言** です。Java の `public static <T> void swap(T[] a, int i, int j)` と完全に同じ位置・同じ意味です。
- 関数本体の中では `T` をあたかも具体的な型のように扱えますが、コンパイラは「`T` に対して許される操作」を **使われ方から逆算** して制限します。例えば `T` 同士の比較 (`a < b`) はこの段階では書けません。なぜなら任意の `T` が比較可能とは限らないからです。比較を許したいなら、後述の **型制約** を付けます。

Swift コンパイラは呼び出しサイトを見て `T` に当てはまる型を推論します。`swap(&x, &y)` で `x` が `Int` なら、`T = Int` と決まります。明示的に書きたければ、関数呼び出しで `swap<Int>(&x, &y)` のように書くこともできますが、通常は推論に任せます。

---

## 2. ジェネリックな型

関数だけでなく、型そのものをジェネリックにできます。Apple の標準ライブラリでよく目にする `Array<Element>`、`Dictionary<Key, Value>`、`Optional<Wrapped>`、`Set<Element>` はすべてジェネリック型です。

自分で書く場合の最小例は、教材サンプルの `Stack<Element>` です。

```swift
struct Stack<Element> {
    private var storage: [Element] = []

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    mutating func push(_ element: Element) {
        storage.append(element)
    }

    mutating func pop() -> Element? {
        storage.popLast()
    }

    func peek() -> Element? {
        storage.last
    }
}
```

> 出典: `samples/ch26-generics/Stack.swift`

`struct Stack<Element>` の `<Element>` が型パラメータ宣言です。利用側では具体的な型を当てはめてインスタンス化します。

```swift
var intStack = Stack<Int>()
intStack.push(1)
intStack.push(2)
let top: Int? = intStack.pop()  // 戻り値も Element? = Int? として扱われる

var stringStack = Stack<String>()
stringStack.push("apple")
let topStr: String? = stringStack.pop()
```

`Stack<Int>` と `Stack<String>` は **完全に別の型** として扱われます。`Stack<Int>` を期待する関数に `Stack<String>` を渡すとコンパイルエラーになります。Java でも同じですが、Java の場合は実行時には両者の区別が消えるのに対し、Swift では実行時にも区別されます。ここは後で詳述します。

### 型パラメータの命名慣習

Swift コミュニティの命名慣習は次の通りです。

| パラメータ名 | 用途 |
|------|------|
| `Element` | コレクションの要素型 (`Array<Element>`、`Set<Element>` など) |
| `Key` / `Value` | 辞書のキーと値 (`Dictionary<Key, Value>`) |
| `Wrapped` | 包む対象 (`Optional<Wrapped>`、`Result<Wrapped, Error>`) |
| `T`, `U`, `V` | 汎用、特に意味を伝える名前が思いつかないとき |

意味のある名前を付けるのが望ましく、汎用関数でない限り `T` は避ける方向です。Java の `<E>`、`<T>`、`<K, V>` の慣習とほぼ同じ感覚で読めます。

### 複数の型パラメータ

カンマ区切りで複数宣言できます。Apple 標準の `Dictionary` がそうです。

```swift
struct Pair<First, Second> {
    let first: First
    let second: Second
}

let pair = Pair(first: 42, second: "answer")  // Pair<Int, String> と推論される
```

---

## 3. 型制約 (Type Constraints)

「任意の `T`」では `T` に何ができるか不明なので、`==` や `<` を使えません。これを許すには、`T` に **プロトコル準拠** の制約を課します。Java の `<T extends Comparable<T>>` と同じ考え方です。

### 直接制約

最も簡潔な書き方です。型パラメータ名のすぐ後にコロンを置き、要求するプロトコルを記します。

```swift
func indexOf<T: Equatable>(_ value: T, in array: [T]) -> Int? {
    for (i, element) in array.enumerated() where element == value {
        return i
    }
    return nil
}

print(indexOf(3, in: [1, 2, 3, 4]) ?? -1)        // 2
print(indexOf("b", in: ["a", "b", "c"]) ?? -1)    // 1
```

`T: Equatable` により、関数本体で `element == value` という比較が許されます。`Equatable` に準拠していない型を渡そうとすればコンパイルエラーです。

### 複数制約と `where` 句

複数のプロトコルに同時に準拠させたい場合や、関連型 (associated type) に対しても制約を付けたい場合は `where` 句が役立ちます。

```swift
func minMax<T>(_ array: [T]) -> (min: T, max: T)?
where T: Comparable {
    guard let first = array.first else { return nil }
    var minV = first
    var maxV = first
    for element in array.dropFirst() {
        if element < minV { minV = element }
        if element > maxV { maxV = element }
    }
    return (minV, maxV)
}
```

直接制約と `where` 句は等価です。`<T: Comparable>` と書いても `<T> where T: Comparable` と書いても同じ意味になります。複合制約 (`Equatable & Hashable` のような) や、後述する associated type への制約が絡むときは `where` 句のほうが読みやすくなります。

```swift
func processBoth<T>(_ value: T) where T: Equatable & Hashable {
    // T は Equatable かつ Hashable
}
```

### 型制約付きジェネリック型

関数だけでなく、型宣言にも制約を付けられます。教材サンプルの `BinaryTree` がその例です。

```swift
final class BinaryTree<Element: Comparable> {
    // ...
    func insert(_ value: Element) { ... }
    func contains(_ value: Element) -> Bool { ... }
}
```

> 出典: `samples/ch26-generics/BinaryTree.swift`

二分探索木は要素を順序比較して左右に分配する必要があるため、`Element` が `Comparable` に準拠していないと意味をなしません。制約を宣言で固定することで、`BinaryTree<Int>` や `BinaryTree<String>` (どちらも `Comparable`) は許されますが、`BinaryTree<NotComparable>` のような無意味な特殊化はコンパイル時点で拒否されます。

```swift
let tree = BinaryTree<Int>()
[5, 3, 8, 1, 4, 7, 9].forEach { tree.insert($0) }
print(tree.inOrder())  // [1, 3, 4, 5, 7, 8, 9]

// struct NotComparable {}
// let invalid = BinaryTree<NotComparable>()  // コンパイルエラー
```

Java の `class TreeSet<E extends Comparable<E>>` と発想は同じですが、Swift の方が記述が短く、再帰的な型制約 (Java の `<E extends Comparable<E>>` のような自己参照) も `Comparable` という単純なプロトコル名で表現できます。

---

## 4. associated type との連携

Ch25 で学んだ通り、protocol は **associated type** によって「具体的な型は実装側が決める型メンバ」を宣言できます。これはジェネリクスと組み合わせると一気に表現力が増します。

最も典型的な例として、自作の `Container` プロトコルを見てみましょう。

```swift
protocol Container {
    associatedtype Item
    var count: Int { get }
    mutating func append(_ item: Item)
    subscript(i: Int) -> Item { get }
}
```

`Item` は実装側で決まります。例えば先ほどの `Stack` を `Container` に準拠させるなら、

```swift
extension Stack: Container {
    typealias Item = Element  // 通常は省略でき、コンパイラが推論する
    mutating func append(_ item: Element) { push(item) }
    subscript(i: Int) -> Element { storage[i] }
}
```

`typealias Item = Element` は、`append(_:)` のシグネチャから `Item == Element` と推論できるため、書かなくても通ります。

### associated type に制約を付ける

ジェネリック関数で「`Container` に準拠した何らかの型」を受け取りたいとき、associated type にも条件を付けたければ `where` 句を使います。Java のワイルドカード (`Container<? extends Number>`) に近い表現です。

```swift
func allItemsMatch<C1: Container, C2: Container>(
    _ a: C1,
    _ b: C2
) -> Bool
where C1.Item == C2.Item, C1.Item: Equatable {
    guard a.count == b.count else { return false }
    for i in 0..<a.count where a[i] != b[i] {
        return false
    }
    return true
}
```

ポイントは 3 つです。

- `C1`、`C2` はそれぞれ独立した `Container` ですが、`where C1.Item == C2.Item` で **要素型が同じ** ことを要求しています。
- さらに `C1.Item: Equatable` で、要素同士を `!=` で比較できることを保証しています。
- Java の `<C1 extends Container<E>, C2 extends Container<E>>` のような書き方より、関連型に対する制約を **後置で書ける** ぶん意図が読みやすくなります。

associated type は protocol 側で「未来の埋め込み枠」を空けておく仕組みであり、ジェネリック関数側で `where` 句を使ってその枠を縛る、というのが Swift のジェネリクスの典型パターンです。

---

## 5. ジェネリック関数の戻り値型

戻り値の型としても型パラメータを使えます。

```swift
func first<T>(of array: [T]) -> T? {
    array.isEmpty ? nil : array[0]
}

let n: Int? = first(of: [10, 20, 30])
let s: String? = first(of: ["a", "b", "c"])
```

呼び出し元の文脈や引数から `T` が推論されます。`first(of: [10, 20, 30])` であれば `T = Int` となり、戻り値は `Int?` になります。

### 引数と戻り値で別パラメータ

入力と出力で型を独立させることもできます。これは Java の `<T, R> R map(T input, Function<T, R> f)` と同じ発想です。

```swift
func map<Input, Output>(_ value: Input, transform: (Input) -> Output) -> Output {
    transform(value)
}

let length: Int = map("hello") { $0.count }       // String → Int
let doubled: Double = map(3) { Double($0) * 2.0 }  // Int → Double
```

Swift 標準ライブラリの `Sequence.map(_:)` も内部的には同じ構造で、`(Element) throws -> T` を受け取り `[T]` を返します。

---

## 6. Java のジェネリクスとの違い ── 型消去がないこと

ここが本章の核心です。Java を長く書いてきた読者ほど、ジェネリクスに対する暗黙の前提を Swift に持ち込みがちですが、設計が大きく異なります。

### Java の型消去 (type erasure)

Java のジェネリクスは、後方互換性のために **コンパイル時のみの仕組み** として導入されました。`List<String>` も `List<Integer>` も、コンパイル後のバイトコードでは単なる `List` (要素は `Object`) になります。これを **型消去** と呼びます。

そのため Java では次のような制限が生じます。

- `if (list instanceof List<String>)` は書けない (実行時には `List<Integer>` と区別不能)。
- `new T[10]` も `new T()` も書けない (実行時の `T` は不明)。
- 同じシグネチャでパラメータだけ違うオーバーロード (`void f(List<String>)` と `void f(List<Integer>)`) は **コンパイル不可**。
- リフレクションで型パラメータを取得するには、`TypeReference` 系のテクニックが必要。

### Swift は型情報を完全に保持する

Swift のジェネリクスは、コンパイル時にも実行時にも型情報を保持します。`Array<Int>` と `Array<String>` は実行時にも別の型として区別され、`is` / `as?` チェックが期待通りに働きます。

```swift
let intArray: Any = [1, 2, 3]
let strArray: Any = ["a", "b", "c"]

print(intArray is [Int])       // true
print(intArray is [String])    // false
print(strArray is [String])    // true
```

さらに Swift は、必要に応じて **型ごとに最適化されたコード** を生成します (specialization)。`Array<Int>` 用と `Array<String>` 用で別々の機械語が出力されることがあり、ボクシング/アンボクシングのコストが発生しません。Java では `List<Integer>` の各要素は内部的に `Integer` オブジェクト (参照型) としてヒープに置かれますが、Swift では `Array<Int>` の要素は `Int` の値としてインライン格納されます。

### コードレベルで何が変わるか

実例を 2 つ挙げます。

**(1) ジェネリック型での `T` 由来の比較**

Java では、ジェネリックメソッドの中で `T.class` に相当するものを取れません。Swift では `T.self` (型のメタタイプ) や `type(of:)` がそのまま使えます。

```swift
func describeType<T>(_ value: T) {
    print("type =", type(of: value))   // 実行時の具体的な型を取得
}
describeType(42)         // type = Int
describeType("hello")    // type = String
describeType([1, 2, 3])  // type = Array<Int>
```

**(2) ジェネリック関数のオーバーロード**

Swift では型パラメータの違いがそのまま別シグネチャとして認識されます。

```swift
func process(_ items: [Int])    { print("Int array:", items) }
func process(_ items: [String]) { print("String array:", items) }

process([1, 2, 3])         // Int array: [1, 2, 3]
process(["a", "b", "c"])   // String array: ["a", "b", "c"]
```

Java では `void process(List<Integer>)` と `void process(List<String>)` は同じ消去後シグネチャ `void process(List)` になり、コンパイルエラーです。Swift ではそのまま通ります。

### 設計上の含意

この違いは、API の設計姿勢にも影響します。Swift では「ジェネリック型をプロトコルで扱う」場面でも、Java の `?` ワイルドカードのような曖昧さに頼る必要が少なく、型パラメータを直接持ち運べます。次節の Opaque Types (`some`) や、Ch25 で触れた `any` キーワードによる existential 型は、この強い型保持を前提とした道具立てです。

---

## 7. Opaque Types (`some`) への橋渡し

ジェネリクスを学んだ直後の自然な疑問として、「戻り値で『何らかの Sequence を返す』のように、具体的な型を隠したい場合はどう書くのか?」があります。

Swift にはそのための専用構文 `some` があります。

```swift
func makeNumbers() -> some Collection {
    return [1, 2, 3, 4, 5]
}

let numbers = makeNumbers()
print(numbers.count)  // 5
```

`some Collection` は「具体的な型は隠すが、コンパイル時には 1 つの型に決まっている」という宣言です。Java の `List<? extends Number>` (ワイルドカード) と似て見えますが、`some` は **戻り値の側で実装を隠蔽するための仕組み** であり、より制約が強く、より最適化に有利です。

詳細は次章 Ch27 で扱います。本章では「ジェネリクスの兄弟概念として `some` がある」とだけ覚えておいてください。

---

## 8. Generics と Protocol Extension の組み合わせ

最後のトピックは、ジェネリクスの真価が発揮される **条件付き拡張 (constrained extension)** です。プロトコルや型パラメータに条件を付けて拡張を書けるため、「特定の要素型のときだけ生えるメソッド」を表現できます。

### 標準ライブラリの実例

`Array` はジェネリック型 `Array<Element>` ですが、`Element` が `Numeric` (数値) のときだけ和を計算できる、というのは自然な発想です。Swift ではこれを `extension where` で書けます。

```swift
extension Array where Element: Numeric {
    var sum: Element {
        reduce(0, +)
    }
}

print([1, 2, 3, 4].sum)        // 10  ([Int])
print([1.5, 2.5, 3.0].sum)     // 7.0 ([Double])

// print(["a", "b"].sum)        // コンパイルエラー: String は Numeric ではない
```

`[Int]` と `[Double]` には `sum` プロパティが生え、`[String]` には生えない ── というのが、`extension Array where Element: Numeric` の正確な意味です。Java で同じ表現をしようとすると、ユーティリティクラス (`NumericArrayUtils.sum(List<? extends Number> list)`) を別途用意する必要があり、構文がぎこちなくなります。Swift では型本来のメンバとして自然に追加できます。

### 自作型でも同じ

教材サンプルの `Stack` に対しても、要素型に応じて条件付き拡張を書けます。

```swift
extension Stack where Element: Equatable {
    func contains(_ value: Element) -> Bool {
        // 内部 storage を直接見られないので、概念のみ示す
        var copy = self
        while let top = copy.pop() where top == value {
            return true
        }
        return false
    }
}
```

`Stack<Int>` には `contains(_:)` が生えますが、`Equatable` でない型を要素にした `Stack` には生えません。

### protocol への条件付き拡張

ジェネリクスとプロトコル拡張の交差点では、「associated type に条件を付けてプロトコルを拡張する」という技も使えます。

```swift
protocol Container {
    associatedtype Item
    var count: Int { get }
    subscript(i: Int) -> Item { get }
}

extension Container where Item: Equatable {
    func startsWith(_ value: Item) -> Bool {
        count > 0 && self[0] == value
    }
}
```

`Container` プロトコルに準拠した型のうち、`Item` が `Equatable` であるものだけに `startsWith(_:)` が生えます。Java では実現が難しい、Swift 独自の表現力です。

---

## 9. ZoomacIt 本体での利用例 (軽く)

冒頭で述べた通り、ZoomacIt 本体には自分で型パラメータを宣言した型はほとんど登場しません。ジェネリクスは主に **標準ライブラリの利用側** として現れます。

```swift
// src/ZoomacIt/Models/Stroke.swift
var points: [CGPoint]
var startPoint: CGPoint
var endPoint: CGPoint
```

`[CGPoint]` は `Array<CGPoint>` の略記です。`Array` がジェネリック型である恩恵を、`Element = CGPoint` と特殊化された形で受けています。`Array<Element>` の `append(_:)` や `removeLast()` は、要素型に依存しない一般的なロジックとしてジェネリクスで実装され、コンパイル時に `CGPoint` 用に最適化されます。

同様に、`Settings` クラスでは `Optional<T>` (オプショナル) や `Dictionary<String, Any>` 相当の API も間接的に利用しています。これらはすべてジェネリクスの恩恵です。「自分でジェネリック型を作るシーン」は実務でも頻度は低いですが、**標準ライブラリを正しく読み解く** ためには本章の知識が必須となります。

---

## 補助サンプルの紹介

本章で参照した教材サンプルは `samples/ch26-generics/` にあります。

| ファイル | 内容 |
|---------|-----|
| `Stack.swift` | 基本的なジェネリック型 (`struct Stack<Element>`) |
| `Queue.swift` | 別の型パラメータ命名 (`struct Queue<T>`) を採用したサンプル |
| `BinaryTree.swift` | `Comparable` 制約付きジェネリック型 (`class BinaryTree<Element: Comparable>`) |
| `README.md` | サンプルの目的、コンパイル方法、本章との対応表 |

各ファイルは末尾に `// MARK: - Demo` セクションを持ち、単独で実行できます。

```bash
cd learning-swift/samples/ch26-generics
swift Stack.swift       # Stack<Int> と Stack<String> の動作確認
swift Queue.swift       # Queue<String> の動作確認
swift BinaryTree.swift  // 二分探索木の挿入 / 検索 / 中順走査
```

---

## ハンズオン (任意)

1. `Stack.swift` を開き、`extension Stack where Element: Equatable` を書いて `contains(_:)` メソッドを追加してください。`Stack<Int>` で動作することと、`Equatable` でない自作型を要素にした `Stack` には `contains` が呼べないことをコンパイラのエラーで確認します。
2. `Queue.swift` の型パラメータ名を `T` から `Element` に置換し、Demo セクションがそのまま動くことを確認してください。型パラメータ名の変更は **宣言と本体の中だけの問題** で、外から見たシグネチャは変わらないことを体感する練習です。
3. `BinaryTree.swift` に `count` プロパティ (要素数) を追加してください。`inOrder()` の実装を参考に再帰で書けます。
4. 標準ライブラリの `Array.contains(_:)` のシグネチャを Quick Help で確認し、`Element: Equatable` という制約が付いていることを発見してください。これは本章で学んだ「条件付き拡張」の典型例です。

---

## まとめ

- ジェネリクスは **型を抽象化する** 仕組み。関数 (`func swap<T>`) にも型 (`struct Stack<Element>`) にも使える。
- 型パラメータには **型制約** を付けられる。`<T: Equatable>` または `<T> where T: Equatable`。
- protocol の **associated type** はジェネリック関数の `where` 句で縛れる (`where C1.Item == C2.Item`)。
- Java の **型消去** とは異なり、Swift は実行時にも型情報を保持する。`Array<Int>` と `Array<String>` は別の型として扱われ、specialization により最適化される。
- `some` (Opaque Type) は次章で深掘りする。「具体的な型を隠して 1 つに固定する」専用構文。
- **条件付き拡張** (`extension Array where Element: Numeric`) はジェネリクスの真価。Java では模倣が難しい Swift 独自の表現力。

## 次に読む章

→ [27. Opaque Types](./27-opaque-types.md)
