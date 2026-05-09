# 05. Basic Operators

## この章で学ぶこと

Swift の基本演算子は、Java とほぼ同じ記号・同じ優先順位で動作します。本章では Java との差分にだけ集中し、対応表で全体像を押さえたうえで、Swift 特有の演算子 (*範囲演算子*、*nil 合体演算子*、*識別演算子*、*オーバーフロー演算子*) のみを短く補足します。最後に ZoomacIt の `ZoomMath` で実際の使われ方を読み解きます。

## Java との対応表

ほとんどの演算子は記号も意味も Java と同一です。差分のある行は「Swift 固有の挙動」列に注記しています。

| カテゴリ | 演算子 | Java | Swift | Swift 固有の挙動 |
|---------|--------|------|-------|-----------------|
| 代入 | `=` | 値を返す (`a = b = 0` 可) | 値を返さない | `if (a = b)` のような誤記が **コンパイルエラー** になる |
| 算術 | `+ - * / %` | OK | OK | `%` は浮動小数点にも適用可。整数演算は **暗黙オーバーフロー時にトラップ** (後述) |
| 複合代入 | `+= -= *= /= %=` | OK | OK | こちらも値を返さない |
| 比較 | `== != < > <= >=` | OK | OK | 値型 (`struct`) は値の同値比較。クラスは別途 `===` を使う |
| 論理 | `&& \|\| !` | OK | OK | 短絡評価 (short-circuit) も同じ |
| 三項 | `cond ? a : b` | OK | OK | 同じ。可読性が落ちる場合は `if` 式を推奨 |
| 単項 | `+x -x` | OK | OK | 同じ |
| インクリメント | `++ --` | OK | **廃止 (Swift 3 で削除)** | `x += 1` を使う |
| ビット演算 | `& \| ^ ~ << >>` | OK | OK | 整数型ごとにオーバーロード |
| 範囲 | — | なし | `a..<b` `a...b` | Swift 固有 |
| nil 合体 | — | なし (`Optional.orElse`) | `a ?? b` | Swift 固有 |
| 識別 | 参照型の `==` | OK | `=== !==` | Swift では `==` と分離 |
| オーバーフロー | — | デフォルト挙動 | `&+ &- &*` | Swift 固有 |

> 本章で扱わない `try` `try?` `try!` `as` `as?` `as!` `is` などは、後続の章 (Error Handling, Type Casting) で扱います。

### 代入が値を返さない理由

Swift の `=` は *式 (expression)* ではなく *文 (statement)* に近く、評価結果を持ちません。これにより、Java や C で典型的な `if (flag = true)` の代入ミスを構文段階で防げます。

```swift
var a = 0
let b = 10
// if a = b { }   // コンパイルエラー: cannot convert value of type '()' to 'Bool'
if a == b { }     // OK
a = b             // 文として書く
```

### 整数除算とオーバーフロー

Java と同じく、整数同士の `/` は切り捨て、`%` は剰余です。違いは **オーバーフローした瞬間にランタイムトラップ (実行時エラー) する** 点です。

```swift
let big: Int8 = 120
// let overflow = big + 20  // Swift 6.0: 実行時クラッシュ
let safe = big &+ 20         // オーバーフローを許容して循環 (= -116)
```

サイレントに桁あふれする Java と異なり、Swift は **明示的に許可する場合のみ** `&+` `&-` `&*` を使います。

## Swift 特有の演算子

### 範囲演算子 (Range Operators)

ループや配列スライスのために、2 つの値で範囲を作ります。

| 記法 | 名称 | 含む値 |
|------|------|--------|
| `a...b` | *closed range operator* | a, a+1, ..., b (両端を含む) |
| `a..<b` | *half-open range operator* | a, a+1, ..., b-1 (b を含まない) |
| `a...` `...b` `..<b` | *one-sided range* | 片側だけ指定。配列スライスで頻出 |

```swift
for i in 0..<5 { print(i) }     // 0,1,2,3,4
for i in 1...5 { print(i) }     // 1,2,3,4,5

let names = ["A", "B", "C", "D"]
let tail = names[1...]          // ["B", "C", "D"]
```

Java の `IntStream.range(0, 5)` / `IntStream.rangeClosed(1, 5)` に相当しますが、こちらは言語組み込みの構文です。

### nil 合体演算子 (Nil-Coalescing Operator)

`a ?? b` は、`a` が `nil` でなければアンラップした値を、`nil` ならフォールバック値 `b` を返します。`a` は *Optional* 型でなければなりません。

```swift
let input: String? = nil
let value = input ?? "default"   // "default"

let length = (input ?? "").count // 0
```

Java の `Optional.orElse(b)` 相当ですが、構文が短く、`b` は **遅延評価ではない** 点に注意 (Java の `orElseGet` のような遅延評価が必要なら関数を別途分けます)。

### 識別演算子 (Identity Operators)

`===` `!==` は、2 つのクラスインスタンスが **同一の参照** を指すかを判定します。Java の `==` (参照比較) に相当します。Swift の `==` は同値比較 (`Equatable` プロトコル) のため、用途が分離されています。

```swift
class Box { var value = 0 }
let p = Box()
let q = p
let r = Box()

p === q   // true   (同一インスタンス)
p === r   // false  (別インスタンス)
p == r    // 別途 Equatable 適合が必要
```

構造体 (`struct`) や列挙型 (`enum`) は値型なので `===` は使えません (コンパイルエラー)。

### オーバーフロー演算子 (Overflow Operators)

整数オーバーフロー時に、デフォルトの `+ - *` はトラップしますが、**意図的に循環させたい場合** には `&+` `&-` `&*` を使います。ハッシュ計算や暗号系のビット演算で稀に登場する程度で、通常のアプリ開発で使うことはほぼありません。

```swift
let max = Int8.max          // 127
let wrap = max &+ 1         // -128 (循環)
```

## ZoomacIt 実コード読解

ZoomacIt の `ZoomMath` 列挙型は、ズーム計算のピュア関数群です。算術演算と `min` / `max` の合わせ技で *値の範囲を制限する* (clamp) パターンが頻出します。

### 算術演算と座標変換

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

> 引用元: src/ZoomacIt/Overlay/ZoomMath.swift:9-27

ここで使われているのは `/` `-` `*` のごく普通の算術演算だけですが、注目してほしいのは:

- **`CGFloat` どうしの算術**: Swift の演算子は型ごとにオーバーロードされており、`Int` と `CGFloat` を混ぜると **暗黙変換されず** コンパイルエラーになります (Java の自動拡大変換と異なります)。`1.0 / zoomLevel` の `1.0` が浮動小数点リテラルなので `CGFloat` 推論されます。
- **値の正規化**: `panCenter.x / imageSize.width` で `[0, 1]` に正規化し、加減算で原点を求めています。

### `min(max(...))` クランプパターン

```swift
/// Clamp a value to [lower, upper].
static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
    min(max(value, lower), upper)
}

/// Clamp zoom level to allowed range.
static func clampZoomLevel(_ level: CGFloat,
                           minimum: CGFloat = 1.0,
                           maximum: CGFloat = 8.0) -> CGFloat {
    clamp(level, lower: minimum, upper: maximum)
}
```

> 引用元: src/ZoomacIt/Overlay/ZoomMath.swift:44-54

Swift 標準ライブラリの `min` / `max` は演算子ではなくジェネリック関数ですが、比較演算子 `<` を使う `Comparable` プロトコル準拠の型なら何でも渡せます。`min(max(value, lower), upper)` は値を `[lower, upper]` の閉区間にクランプするイディオムで、Java でも `Math.min(Math.max(...), ...)` として頻出するため違和感はないでしょう。`clampZoomLevel` 側ではデフォルト引数 (`= 1.0`, `= 8.0`) で呼び出し側を簡潔にしています。

## 次に読む章

→ [06. Strings and Characters](./06-strings-and-characters.md)
