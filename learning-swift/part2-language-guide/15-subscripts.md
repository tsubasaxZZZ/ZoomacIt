# 15. Subscripts

## この章で学ぶこと

- 配列・Dictionary の標準 subscript の挙動を Java と比較して整理する
- **String の subscript は `Int` で添字できない** という Swift 特有の制約 (Ch06 で予告した forward reference の回収)
- `subscript` キーワードで **任意の型に添字演算子を定義できる** こと
- read-only / read-write の使い分け、複数引数 subscript の書きかた
- ZoomacIt の Dictionary subscript 実例を読む

> **NOTE**
> この章は **チートシート章** です。配列の添字や Map.get と同じ感覚で読み流して構いません。ただし String の subscript 制約と「自作できる」点だけは押さえておいてください。

---

## 15.1 ひとことで

| 言語 | 添字 `x[i]` を定義できる対象 |
| --- | --- |
| Java | 配列のみ (組み込み)。Map など他のコレクションはメソッド呼び出し (`map.get(k)`) |
| Swift | **任意の型** に `subscript` を定義できる。配列・Dictionary・String・自作型すべてに統一構文 |

Swift の `subscript` は **構文糖衣ではなく、メソッドの一種** です。型に対して `subscript(...) -> T { get set }` を定義すると、`instance[args]` という構文でその型を呼び出せるようになります。

---

## 15.2 配列の subscript — Java と同じ

`Array<Element>` の subscript は `Int` を取り、要素を返します。Java の配列とほぼ同じ挙動です。

```swift
var nums = [10, 20, 30]
let first = nums[0]   // 10
nums[1] = 99          // [10, 99, 30]
```

| 観点 | Java `int[]` | Swift `Array<Int>` |
| --- | --- | --- |
| 範囲外アクセス | `ArrayIndexOutOfBoundsException` | **実行時クラッシュ** (`fatalError`) |
| 戻り値 | `int` (非 Optional) | `Int` (非 Optional) |
| 書き換え | `arr[i] = x` | `arr[i] = x` (`var` の場合のみ) |

範囲外アクセスは **Optional を返すのではなく落ちる** 点に注意。安全に取り出したいときは `nums.first` (Optional) や `nums.indices.contains(i)` で事前確認します。

---

## 15.3 Dictionary の subscript — Optional を返す

Swift の `Dictionary` の subscript は **常に Optional を返す** のが特徴です (Ch07 で既出)。

```swift
let scores: [String: Int] = ["alice": 90, "bob": 80]
let s1 = scores["alice"]    // Optional(90)
let s2 = scores["charlie"]  // nil
```

Java の `Map.get` と意味的には同じですが、Swift では型システムが Optional を強制するため、**取り出した値をそのまま使うことはできず、必ずアンラップが必要** です。

```swift
let s = scores["alice", default: 0]   // 90 (キーがなければ 0)
if let s = scores["bob"] { print(s) } // optional binding
```

書き込みも subscript で行います。`nil` を代入するとそのキーを削除します。

```swift
var dict: [String: Int] = [:]
dict["alice"] = 90
dict["alice"] = nil   // 削除
```

| 操作 | Java `Map<String, Integer>` | Swift `[String: Int]` |
| --- | --- | --- |
| 取得 | `map.get("k")` (`null` あり) | `dict["k"]` (`Int?`) |
| デフォルト付き取得 | `map.getOrDefault("k", 0)` | `dict["k", default: 0]` |
| 追加・更新 | `map.put("k", 1)` | `dict["k"] = 1` |
| 削除 | `map.remove("k")` | `dict["k"] = nil` |

---

## 15.4 String の subscript — `Int` で添字できない

Ch06 *Strings and Characters* で **forward reference** していた話題をここで回収します。

Swift の `String` は **`Int` で添字アクセスできません**。

```swift
let s = "hello"
// let c = s[0]   // コンパイルエラー
```

理由は Unicode 安全のためです。Swift の `String` は **拡張書記素クラスタ (extended grapheme cluster)** を 1 文字として扱うため、`String` 内部の UTF-8 バイトオフセットと「人間にとっての N 文字目」は一般に一致しません。`Int` 添字を許してしまうと、絵文字や合成文字を含む文字列で「想定と違う場所が切れる」事故が起きやすくなります。

代わりに `String.Index` を使います。

```swift
let s = "hello"
let c = s[s.startIndex]                          // "h"
let i = s.index(s.startIndex, offsetBy: 1)
let c2 = s[i]                                    // "e"
```

ただし実務で `String.Index` を直接いじる場面は稀で、たいてい以下の高水準 API で済みます。

| やりたいこと | 推奨 API |
| --- | --- |
| 先頭 1 文字 | `s.first` (`Character?`) |
| 末尾 1 文字 | `s.last` (`Character?`) |
| 先頭 N 文字 | `s.prefix(N)` |
| 末尾 N 文字 | `s.suffix(N)` |
| 先頭 1 文字を捨てる | `s.dropFirst()` |
| 含む / 始まる / 終わる | `s.contains` / `s.hasPrefix` / `s.hasSuffix` |
| 範囲取得 (`Range<Index>`) | `s[s.startIndex..<i]` |

```swift
let s = "hello"
s.first             // Optional("h")
s.prefix(3)         // "hel"
s.dropFirst()       // "ello"
s.hasPrefix("he")   // true
```

> **覚えること**
> 「Swift の `String` は `Int` 添字できない。`first` / `prefix` / `dropFirst` で済ませ、どうしても必要なときだけ `String.Index` を使う」 — これだけ覚えておけば十分です。

---

## 15.5 自作 subscript — 自分の型に添字を定義する

Swift では `subscript` キーワードで **任意の型に添字演算子を定義できます**。Java にはこの機能がなく、`get(i)` のようなメソッドを書くしかありません。

### 構文

```swift
struct Wordbook {
    private var words: [String: String] = [:]

    subscript(key: String) -> String? {
        get { words[key] }
        set { words[key] = newValue }
    }
}

var wb = Wordbook()
wb["swift"] = "fast"     // set 側
print(wb["swift"] as Any) // get 側
```

`subscript` の構文は computed property (Ch10 / Ch12 で既出) とほぼ同じで、**仮引数を取れる computed property** と理解すると腹落ちしやすいです。

### read-only subscript

`set` を省略すると read-only になります。`get` だけのときは `get { ... }` を省いてブロック直書きできます (computed property と同じ)。

```swift
struct Squares {
    subscript(n: Int) -> Int {
        n * n
    }
}

let sq = Squares()
sq[5]   // 25
```

### 複数引数 subscript

仮引数は **複数取れます**。2 次元配列のような型に自然な構文を与えられます。

```swift
struct Matrix {
    let rows: Int
    let cols: Int
    private var grid: [Double]

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.grid = Array(repeating: 0.0, count: rows * cols)
    }

    subscript(row: Int, col: Int) -> Double {
        get { grid[row * cols + col] }
        set { grid[row * cols + col] = newValue }
    }
}

var m = Matrix(rows: 3, cols: 3)
m[1, 2] = 4.5
print(m[1, 2])   // 4.5
```

### 引数ラベル付き subscript

通常の関数と同じように **引数ラベル** も付けられます。意味が分かりにくいときはラベルで補強します。

```swift
subscript(row r: Int, col c: Int) -> Double { ... }
m[row: 1, col: 2]
```

### static subscript

型自身に対する subscript も `static subscript` で定義できます (使用頻度は低い)。

---

## 15.6 ZoomacIt 実コード — Dictionary subscript

ZoomacIt 自体に自作 `subscript` は登場しませんが、**Dictionary の標準 subscript** はキーコード変換テーブルの中核として使われています。

`src/ZoomacIt/Models/Settings.swift` (288 行付近) からの抜粋です。

```swift
private static let keyCodeDisplayNames: [Int: String] = [
    kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
    // ...
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
    kVK_Delete: "⌫", kVK_Escape: "⎋",
    kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    // ...
]

/// Converts a Carbon virtual key code to a display string.
static func keyCodeToString(_ keyCode: UInt32) -> String {
    keyCodeDisplayNames[Int(keyCode)] ?? "Key\(keyCode)"
}
```

`keyCodeDisplayNames[Int(keyCode)]` が Dictionary subscript で、戻り値は `String?` です。**辞書に存在しないキーが来たら `nil`** が返るので、`??` 演算子でフォールバック文字列 `"Key\(keyCode)"` を返しています。

Java で書けば次のような形ですが、Swift の方が 1 行で簡潔に書けることが見て取れます。

```java
return keyCodeDisplayNames.getOrDefault((int)keyCode, "Key" + keyCode);
```

### おまけ: UserDefaults も subscript 的 API

同ファイルでは `UserDefaults` への保存に `defaults.set(value, forKey: key)` という **メソッド呼び出し API** を使っています。

```swift
set { defaults.set(Int(newValue), forKey: Keys.zoomHotkeyKeyCode) }
```

`UserDefaults` は subscript ではなくメソッド形式ですが、**「キーで値を出し入れする」という意味では Dictionary と同じ役割** を果たしています。Foundation の歴史的経緯で subscript 化されていないだけで、Swift で自作するなら subscript で書く設計もあり得ます。

---

## 15.7 ハンズオン (任意)

1. **Wordbook を実装する**
   `[String: String]` をラップした `Wordbook` 型を作り、`wb["key"]` で getter/setter が動くことを確認してください。
2. **2 次元 Matrix の境界チェック**
   上記 `Matrix` の subscript に `precondition(0 <= row && row < rows)` を追加し、範囲外アクセスでクラッシュメッセージが出ることを確認してください。
3. **String の prefix を試す**
   絵文字を含む文字列 (例: `"hello👨‍👩‍👧"`) に対して `prefix(6)` と `count` がどう振る舞うかを観察してみてください。`Int` 添字が禁じられている理由が体感できます。

---

## まとめ

- 配列の subscript は Java と同じ。範囲外は **クラッシュ** (Optional ではない)
- Dictionary の subscript は **Optional を返す**。`dict[k] = nil` で削除
- String は **`Int` 添字不可**。`first` / `prefix` / `dropFirst` で済ませ、必要なら `String.Index`
- `subscript` キーワードで **任意の型に添字演算子を定義可能**。read-only / read-write / 複数引数 / 引数ラベル / static まで対応
- ZoomacIt では `keyCodeDisplayNames[Int(keyCode)] ?? "Key\(keyCode)"` のように Dictionary subscript + `??` がキーコード変換の中核

「`get(i)` メソッドを生やす代わりに subscript を生やす」という選択肢を持つだけで、コレクション風 API の読みやすさが一段上がります。コレクションを内部に持つ型を作ったら、まず subscript を検討してみてください。

## 次に読む章

→ [16. Inheritance](../part2-language-guide/16-inheritance.md)
