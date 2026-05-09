# 07. Collection Types

## この章で学ぶこと

- Swift の 3 大コレクション **Array / Dictionary / Set** の基本操作を、Java の `List` / `Map` / `Set` との対応表で素早く把握する
- Swift コレクションが **すべて値型(struct)** であるという、Java と最も大きな差を理解する
- ZoomacIt の `Stroke` / `DrawingCanvasView` で `[CGPoint]` がどう使われているかを実コードで確認する

> **NOTE**
> この章は **チートシート章** です。ほとんどのトピックで「Java ならこう、Swift ならこう」という対応関係さえ押さえれば実用上は十分です。ただし最後の「**値型としての挙動**」だけは Swift 特有のテーマで、ここを誤解すると深刻なバグにつながるため丁寧に扱います。

---

## 全体像

Swift には標準コレクションが 3 種類あります。すべて Standard Library が提供する **ジェネリック struct** で、Java の `java.util.*` インターフェイス階層のような分岐は存在しません。

| Swift                    | リテラル                  | Java の相当物                     | 内部実装          |
| ------------------------ | ------------------------- | --------------------------------- | ----------------- |
| `Array<T>` / `[T]`       | `[1, 2, 3]`               | `List<T>` / `ArrayList<T>`        | 連続バッファ      |
| `Dictionary<K, V>` / `[K: V]` | `["a": 1, "b": 2]`     | `Map<K, V>` / `HashMap<K, V>`     | ハッシュテーブル  |
| `Set<T>`                 | `Set<Int>([1, 2, 3])`     | `Set<T>` / `HashSet<T>`           | ハッシュテーブル  |

Java とまず違うのは:

- **インターフェイスと実装が分かれていない**。`List<T>` を受け取って中身は `ArrayList` か `LinkedList` か……という構造はなく、`Array<T>` という具象 struct があるだけです。
- **すべて値型**。代入や引数渡しでコピーされます(後述)。
- **`null` ではなく `Optional`**。要素が存在しないことは `nil` で表現され、Swift の型システムはそれを強制します。

> **NOTE**
> `[T]` は `Array<T>` の、`[K: V]` は `Dictionary<K, V>` の **シンタックスシュガー** です。完全に等価で、好きな方を使えます。慣習としてはリテラル形式 `[T]` / `[K: V]` の方が圧倒的によく使われます。

---

## Array — `[T]`

Java の `List<T>` / `ArrayList<T>` に相当する、順序付きで重複を許すコレクションです。

### 宣言とリテラル

```swift
let primes: [Int] = [2, 3, 5, 7, 11]   // 型注釈あり
let names = ["Alice", "Bob", "Carol"]   // 型推論で [String] になる
var empty: [Double] = []                // 空配列
var emptyAlt = [Double]()               // 別解(ジェネリックイニシャライザ)
```

`let` 宣言は不変、`var` 宣言は可変です。**`let` で宣言した配列は要素を `append` できません**。Java の `final List` が変数の再代入のみを禁止し中身は変更できるのとは違い、Swift の `let` は **コレクション全体を不変** にします。これは Swift コレクションが値型だからこそ可能な設計です。

### よく使う操作と Java 対応表

| やりたいこと             | Swift                          | Java                             |
| ------------------------ | ------------------------------ | -------------------------------- |
| 要素数                   | `arr.count`                    | `list.size()`                    |
| 空判定                   | `arr.isEmpty`                  | `list.isEmpty()`                 |
| 末尾追加                 | `arr.append(x)`                | `list.add(x)`                    |
| 任意位置に挿入           | `arr.insert(x, at: 2)`         | `list.add(2, x)`                 |
| 添字アクセス             | `arr[0]`                       | `list.get(0)`                    |
| 要素更新                 | `arr[0] = y`                   | `list.set(0, y)`                 |
| 削除(インデックス)       | `arr.remove(at: 2)`            | `list.remove(2)`                 |
| 末尾削除                 | `arr.removeLast()`             | `list.removeLast()` (Java 21+)   |
| 全削除                   | `arr.removeAll()`              | `list.clear()`                   |
| 含むか                   | `arr.contains(x)`              | `list.contains(x)`               |
| インデックス検索         | `arr.firstIndex(of: x)`        | `list.indexOf(x)`                |
| 連結                     | `a + b` または `a.append(contentsOf: b)` | `a.addAll(b)`         |
| 反復                     | `for x in arr { ... }`         | `for (var x : list) { ... }`     |

### 添字アクセスは Optional ではない

Array の `arr[i]` は **直接 `T` を返します**。インデックスが範囲外なら **実行時エラー(クラッシュ)** です。Java の `IndexOutOfBoundsException` と挙動は同じですが、Swift では `try/catch` で受けられない **fatal error** になる点に注意してください。

安全に取り出したい場合は `first` / `last` を使うか、自分で範囲チェックします。

```swift
let xs = [10, 20, 30]
let head: Int? = xs.first      // Optional<Int>(10)
let safe = xs.indices.contains(5) ? xs[5] : nil
```

### Array の関数型操作

`map` / `filter` / `reduce` は Java Stream 相当ですが、Swift では Array が直接これらのメソッドを持ちます(中間ストリームを作らない)。

```swift
let numbers = [1, 2, 3, 4, 5]
let doubled = numbers.map { $0 * 2 }            // [2, 4, 6, 8, 10]
let evens = numbers.filter { $0 % 2 == 0 }       // [2, 4]
let sum = numbers.reduce(0, +)                   // 15
```

`{ $0 * 2 }` はクロージャ(ラムダ)です。詳しくは Ch12 で扱います。

---

## Dictionary — `[K: V]`

Java の `Map<K, V>` / `HashMap<K, V>` に相当する、キーから値への対応を保持するコレクションです。

### 宣言とリテラル

```swift
let scores: [String: Int] = ["Alice": 90, "Bob": 75]
var empty: [String: Int] = [:]              // 空辞書(`[]` ではなく `[:]` に注意)
var emptyAlt = [String: Int]()
```

キー型は `Hashable` プロトコルに適合している必要があります。`String` / `Int` / `Double` などの基本型はすべて適合済みです。

### 添字アクセスは Optional を返す(Swift 特有)

ここが **Java との最大の違い** です。Dictionary の添字アクセス `dict[key]` は **常に `V?`(Optional)** を返します。

```swift
let scores = ["Alice": 90, "Bob": 75]
let alice: Int? = scores["Alice"]   // Optional(90)
let dave:  Int? = scores["Dave"]    // nil
```

Java の `map.get(key)` は値が存在しなければ `null` を返し、それを呼び出し側が忘れるとぬるぽに直結します。Swift は **「キーがないかもしれない」という事実を型で表現** することでこの事故を防ぎます。値を取り出すには Optional を unwrap する必要があり、コンパイラが unwrap 忘れを検出してくれます。

```swift
if let score = scores["Alice"] {
    print("Alice scored \(score)")     // Optional binding で安全に取り出す
}
```

### 代入と削除

```swift
var scores = ["Alice": 90]
scores["Bob"] = 75      // 追加
scores["Alice"] = 100   // 更新
scores["Alice"] = nil   // 削除(`nil` 代入が remove)
scores.removeValue(forKey: "Bob")   // 明示的な削除メソッド
```

`scores["key"] = nil` で削除できるのは Swift 特有のイディオムです。`Optional<V>` を返す添字に `nil` を代入することが「そのエントリを消す」と定義されています。

### よく使う操作

| やりたいこと             | Swift                                      | Java                              |
| ------------------------ | ------------------------------------------ | --------------------------------- |
| サイズ                   | `dict.count`                               | `map.size()`                      |
| キー存在チェック         | `dict["k"] != nil`                         | `map.containsKey("k")`            |
| デフォルト値付き取得     | `dict["k", default: 0]`                    | `map.getOrDefault("k", 0)`        |
| キー一覧                 | `dict.keys`                                | `map.keySet()`                    |
| 値一覧                   | `dict.values`                              | `map.values()`                    |
| 反復                     | `for (k, v) in dict { ... }`               | `for (var e : map.entrySet())`    |

### 反復順序は不定

Java の `HashMap` と同様、`Dictionary` は **要素の順序を保証しません**。挿入順を保ちたい場合は標準ライブラリには専用型がないため、自前で `[(K, V)]` の Array を併用するか、`OrderedDictionary`(swift-collections パッケージ)を使う必要があります。

---

## Set — `Set<T>`

Java の `Set<T>` / `HashSet<T>` に相当する、重複なし・順序なしのコレクションです。

### 宣言とリテラル

```swift
let primes: Set<Int> = [2, 3, 5, 7, 11]
let colors = Set<String>(["red", "green", "blue"])
let tagsAlt: Set<String> = ["swift", "macos"]   // 型注釈で [T] リテラルから Set 推論
```

注意点として、**Set 専用のリテラル構文はありません**。`[1, 2, 3]` だけ書くとデフォルトで `Array<Int>` に推論されます。Set にしたい場合は型注釈 `: Set<Int>` か、`as Set<Int>` キャスト、あるいは `Set<Int>([1, 2, 3])` イニシャライザを使います。

### 集合演算

`Set` は数学的な集合演算を備えています。

```swift
let a: Set = [1, 2, 3, 4]
let b: Set = [3, 4, 5, 6]

let u = a.union(b)              // [1, 2, 3, 4, 5, 6]
let i = a.intersection(b)       // [3, 4]
let d = a.subtracting(b)        // [1, 2]
let s = a.symmetricDifference(b)// [1, 2, 5, 6]
```

| やりたいこと   | Swift                       | Java(Java 21 以降)               |
| -------------- | --------------------------- | --------------------------------- |
| 追加           | `set.insert(x)`             | `set.add(x)`                      |
| 削除           | `set.remove(x)`             | `set.remove(x)`                   |
| 含むか         | `set.contains(x)`           | `set.contains(x)`                 |
| 要素数         | `set.count`                 | `set.size()`                      |

要素型は **`Hashable`** に適合している必要があります(Dictionary のキーと同条件)。

---

## 値型としての挙動(Swift 特有・最重要)

ここまでが「対応表で一気に流せる」内容でした。最後の節は **段落で丁寧に説明します**。Java から来た読者が最も間違えやすいポイントだからです。

### Java と何が違うのか

Java では `List` も `Map` も **参照型(reference type)** です。

```java
// Java
List<Integer> a = new ArrayList<>(List.of(1, 2, 3));
List<Integer> b = a;        // 参照のコピー(同じ ArrayList を指す)
b.add(4);
System.out.println(a);      // [1, 2, 3, 4] ← a も変わる
```

`b = a` は ArrayList オブジェクト本体ではなく、その **参照** をコピーするだけです。`a` と `b` は同じ実体を指すため、片方を変更するともう片方からも見えます。

Swift の Array / Dictionary / Set は **すべて struct(値型)** です。代入や引数渡しのたびに **論理的にはコピーが作られます**。

```swift
// Swift
let a = [1, 2, 3]
var b = a       // ここで「論理的に」コピー
b.append(4)
print(a)        // [1, 2, 3]   ← a は変わらない
print(b)        // [1, 2, 3, 4]
```

`b = a` の時点で `b` は `a` から独立した別のコレクションとして振る舞います。`b.append(4)` は `b` だけを変更し、`a` は元のままです。Java の感覚で「片方を変えれば両方変わる」と期待してコードを書くと、変更が反映されずバグになります。

これは Dictionary でも Set でも完全に同じです。

```swift
var d1 = ["a": 1]
var d2 = d1
d2["b"] = 2
print(d1)   // ["a": 1]
print(d2)   // ["a": 1, "b": 2]
```

### `let` がコレクション全体を凍結する理由

値型であることのもう一つの帰結は、`let` で宣言すると **要素も含めて完全に不変** になることです。

```swift
let xs = [1, 2, 3]
xs.append(4)       // コンパイルエラー: cannot use mutating member on immutable value
```

`xs` という変数自体が値そのものを保持しているため、`xs` を変えられないということは中身も変えられないことと同値です。これは Java の `final List` が「変数の再代入は禁止だが list.add() は呼べる」のとはっきり異なる挙動です。「不変にしたいなら `let` 1 つでよい」と理解してください。

### Copy-on-Write — パフォーマンスの心配は不要

「代入のたびにコピーされるなら、巨大な配列を引数渡ししたら遅いのでは?」という疑問は当然ですが、実用上は問題になりません。Swift コレクションは **Copy-on-Write(CoW、書き込み時複製)** という最適化で実装されており、変更が発生しない限り内部のバッファは共有されます。代入の瞬間はポインタのコピーと等価なコストしかかかりません。

CoW の詳細(`isKnownUniquelyReferenced` など)は Ch24「ARC とメモリ管理」で扱います。ここでは「**値型のセマンティクスを保ったまま、性能は参照型並み**」とだけ覚えておけば十分です。

### 関数引数の挙動

関数にコレクションを渡したとき、関数内部で `var` パラメータとして変更しても、呼び出し側には影響しません。

```swift
func appendOne(to numbers: [Int]) -> [Int] {
    var copy = numbers
    copy.append(1)
    return copy
}

let original = [1, 2, 3]
let result = appendOne(to: original)
print(original)  // [1, 2, 3]
print(result)    // [1, 2, 3, 1]
```

呼び出し側の値を本当に書き換えたい場合は `inout` パラメータを使います。詳細は Ch10「関数」で扱います。

---

## ZoomacIt 実コード読解 — `[CGPoint]` の使われ方

Draw 機能では「フリーハンドで描いた線」が連続した点列として扱われます。実際に `[CGPoint]`(`Array<CGPoint>`)が登場する箇所を見てみましょう。

### `Stroke` の保存プロパティ

確定された 1 本のストロークを表す `Stroke` 構造体は、点列を Array で保持しています。

> 引用元: `src/ZoomacIt/Models/Stroke.swift:13-16`

```swift
struct Stroke {
    /// Raw points collected during freehand drawing.
    var points: [CGPoint]
```

`var points: [CGPoint]` は「`CGPoint` の Array を保持する可変プロパティ」です。型注釈 `[CGPoint]` は `Array<CGPoint>` のシンタックスシュガーで、`Stroke` が値型(struct)なので `points` 配列もこの構造体の値の一部として「埋め込み」で保持されます。

イニシャライザではデフォルト値として **空配列** が指定されています。

> 引用元: `src/ZoomacIt/Models/Stroke.swift:35-44`

```swift
init(
    points: [CGPoint] = [],
    startPoint: CGPoint = .zero,
    endPoint: CGPoint = .zero,
    ...
) {
    self.points = points
    ...
}
```

Java で言えば `new ArrayList<>()` を渡しているのと意味的には同じですが、Swift では `[]` という空配列リテラル 1 つで完結します。型は文脈(パラメータ宣言の `[CGPoint]`)から推論されます。

### ドラッグ中の点を蓄積する

実際に点を集めているのは `DrawingCanvasView` です。マウスドラッグ中、毎フレームの座標を Array に追加していきます。

> 引用元: `src/ZoomacIt/Draw/DrawingCanvasView.swift:42-44`

```swift
private var dragOrigin: CGPoint = .zero
private var freehandPoints: [CGPoint] = []
private var isDragging: Bool = false
```

`freehandPoints` は `private var` で宣言された **可変な空配列** です。Java の `private List<Point> freehandPoints = new ArrayList<>();` に相当しますが、Swift では:

- `new ArrayList<>()` のような明示的なインスタンス生成が不要(`[]` リテラルで済む)
- 値型なのでこのフィールド自体が配列の本体を保持する(別オブジェクトへの参照ではない)

ドラッグが終わった瞬間に `freehandPoints` は `Stroke(points: freehandPoints, ...)` という形で `Stroke` に **コピーされ** て確定ストロークとして保存され、自身は `removeAll()` で空に戻されます。値型のセマンティクスにより、Stroke が保持する `points` と `freehandPoints` は完全に独立したライフサイクルを持つことが保証されます。

> **NOTE**
> CoW のおかげで、`Stroke(points: freehandPoints, ...)` の時点で巨大な点列がディープコピーされるわけではありません。両者が同じバッファを共有したまま、最初に `freehandPoints.removeAll()` のような変更が走った時点で初めてコピーが発生します。

---

## ハンズオン(任意)

Xcode の Playground またはコマンドラインで以下を実行してみてください。値型の挙動が体感できます。

```swift
import Foundation

// 1. Array の独立性
var a = [1, 2, 3]
var b = a
b.append(4)
print("a = \(a)")  // [1, 2, 3]
print("b = \(b)")  // [1, 2, 3, 4]

// 2. Dictionary の Optional アクセス
let scores = ["Alice": 90, "Bob": 75]
print(scores["Alice"] as Any)        // Optional(90)
print(scores["Carol"] as Any)        // nil
print(scores["Carol", default: 0])   // 0

// 3. Set の集合演算
let evens: Set = [2, 4, 6, 8]
let small: Set = [1, 2, 3, 4]
print(evens.intersection(small))     // [2, 4]
```

Java で同じことをしようとすると、Array の独立性確認には `new ArrayList<>(a)` のディープコピー、Dictionary の Optional アクセスには `Optional.ofNullable(map.get("Carol"))` のような書き換えが必要だったはずです。Swift では言語レベルでこれらが組み込まれていることを実感してください。

---

## まとめ

- Array / Dictionary / Set はすべて **ジェネリック struct(値型)**。`[T]` / `[K: V]` / `Set<T>` で書く
- Array の添字アクセスは **直接 `T`**(範囲外でクラッシュ)、Dictionary の添字アクセスは **`V?`**(キー欠損で `nil`)
- `let` で宣言したコレクションは **要素まで含めて完全に不変**
- 代入はコピー、ただし Copy-on-Write で実体コピーは遅延される — 性能上の不安は不要
- ZoomacIt では `[CGPoint]` がストロークの点列保持と、ドラッグ中の中間バッファの両方に使われている

## 次に読む章

→ [08. Control Flow](./08-control-flow.md)
