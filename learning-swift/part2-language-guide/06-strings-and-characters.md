# 06. Strings and Characters

## この章で学ぶこと

- Java の `String` / `char` と、Swift の `String` / `Character` の対応関係(チートシート)
- Swift の **文字列補間(string interpolation)** `"\(...)"` の書き方と、Java の `String.format` / `MessageFormat` との違い
- `Character` が *拡張書記素クラスタ(extended grapheme cluster)* — つまり真の Unicode 1 文字 — であること
- `String.Index` が `Int` ではない理由と、その付き合いかた
- printf 互換の書式が必要なときの `String(format:)`
- ZoomacIt の `Settings.swift` と `BreakTimerState.swift` で実際に使われている文字列処理の読みかた

前章: [05. Basic Operators](./05-basic-operators.md) / 次章: [07. Collection Types](./07-collection-types.md)

---

## チートシート — Java と同じ感覚で書ける部分

まずは Java 経験者が「何も悩まずに書ける」部分から押さえます。`String` の基本操作は、Java とほぼ 1:1 で対応します。

| 操作 | Java | Swift |
|---|---|---|
| 文字列リテラル | `"hello"` | `"hello"` |
| 連結 | `"a" + "b"` | `"a" + "b"` |
| 連結代入 | `s += "x"` | `s += "x"` |
| 長さ | `s.length()` | `s.count` |
| 空判定 | `s.isEmpty()` | `s.isEmpty` |
| 等価比較 | `s.equals(t)` | `s == t` |
| 部分一致 | `s.contains("foo")` | `s.contains("foo")` |
| 大文字化 | `s.toUpperCase()` | `s.uppercased()` |
| 小文字化 | `s.toLowerCase()` | `s.lowercased()` |
| 前後の空白除去 | `s.strip()` | `s.trimmingCharacters(in: .whitespaces)` |

ここで一番重要なのは **`==` がそのまま値比較として動く** という点です。Java では `s1 == s2` は参照比較で、文字列の内容を比較するには `s1.equals(s2)` が必須でしたが、Swift では `==` をそのまま使って構いません。これは `String` が *値型(value type、後述)* であり、`Equatable` プロトコルを通じて構造的等価性が定義されているためです。

```swift
let a: String = "hello"
let b: String = "hel" + "lo"
print(a == b)        // true(Java の equals と同じ意味)
print(a.count)       // 5
print(a.isEmpty)     // false
print(a.uppercased())// "HELLO"
```

### Swift 特有の便利機能 — 複数行リテラル

Java 15 で *text blocks*(`"""..."""`)が入りましたが、Swift には登場時(2014)から複数行リテラルがあります。書きかたは Java の text block とほぼ同じですが、Swift のほうが少しだけ厳密です。

```swift
let usage = """
    ZoomacIt — macOS menu bar app
    Hotkeys:
      ⌃1: Zoom
      ⌃2: Draw
      ⌃3: Break Timer
    """
```

開始の `"""` の直後と、終了の `"""` の直前は **必ず改行** でなければなりません。閉じ `"""` の **インデント位置が共通プレフィックスとして剥がされる** ため、上の例では各行の先頭の空白が 4 つずつ削除され、`ZoomacIt — ...` から始まる文字列になります。

> **NOTE**
> Java の text block は最も浅いインデント行に合わせて自動で剥がしますが、Swift は **閉じ `"""` の位置** が基準です。閉じクォートを意図的にインデントすることでブロック全体のインデントを制御できる、と覚えてください。

複数行リテラル内では、行末バックスラッシュ `\` を書くとその改行を抑制できます。長い 1 行を視覚的に折りたたみたいときに便利です。

```swift
let oneLine = """
    very long but \
    actually a single line
    """
// → "very long but actually a single line"
```

---

## Swift 特有の主役 — 文字列補間

ここからが本章のいちばん大事な部分です。Swift で文字列を組み立てるとき、**文字列補間(string interpolation)** という構文をきわめて頻繁に使います。Java の `String.format` や `MessageFormat`、あるいは `+` による連結のかわりに、リテラルの中に直接式を埋め込めるしくみです。

書きかたは `\(...)` のひとつだけです。リテラル中で `\(` から `)` までを書くと、その中の式が評価され、結果が文字列に変換されて差し込まれます。

```swift
let name = "Alice"
let count = 42
let message = "Hello, \(name)! You have \(count) messages."
// → "Hello, Alice! You have 42 messages."
```

### Java との比較

| 目的 | Java | Swift(補間) |
|---|---|---|
| 名前を埋める | `String.format("Hello, %s!", name)` | `"Hello, \(name)!"` |
| 数値を埋める | `String.format("count=%d", n)` | `"count=\(n)"` |
| 計算結果を埋める | `"sum=" + (a + b)` | `"sum=\(a + b)"` |
| 三項演算 | `"state=" + (ok ? "OK" : "NG")` | `"state=\(ok ? "OK" : "NG")"` |

Java の `%s` / `%d` のような **書式指定子は不要** です。Swift コンパイラは、`\(...)` の中にある式の型を見て、`String(describing:)` 相当の変換を自動で挿入します。`Int` でも `Double` でも `enum` でも、`CustomStringConvertible` に準拠していれば(していなくても、デフォルトの記述で)そのまま埋められます。

```swift
struct Point { let x: Int; let y: Int }
let p = Point(x: 3, y: 5)
print("p = \(p)")  // "p = Point(x: 3, y: 5)"
```

### 補間の中ではほぼ何でも書ける

`\(...)` の中身は **任意の式** です。関数呼び出し、三項演算、メソッドチェーンなどそのまま書けます。

```swift
let scores = [10, 20, 30]
let summary = "max=\(scores.max() ?? 0), count=\(scores.count)"
// → "max=30, count=3"
```

ただし、補間が深くネストすると読みにくくなるので、複雑な式はいったん `let` で名前をつけてから埋めるのが慣習です。

> **NOTE**
> Swift 5 から *ExpressibleByStringInterpolation* プロトコルを使って、補間の挙動を型ごとにカスタマイズできるようになりました。たとえばログ出力で機密情報を `"<redacted>"` に置き換える、といった応用ができます。本書では立ち入りませんが、Apple 公式のロギング API `os.Logger` がこのしくみを利用しています。

### printf 互換が必要なときは `String(format:)`

文字列補間は便利ですが、**ゼロパディングや小数点の桁数指定** といった「Java の `%02d` 相当」のことはできません。そのときは `Foundation` の `String(format:)` イニシャライザを使います。シグネチャは printf 互換で、Java の `String.format` と書式指定子も同じです。

```swift
import Foundation

let h = 9
let m = 5
let clock = String(format: "%02d:%02d", h, m)  // "09:05"

let pi = 3.14159
let s = String(format: "%.2f", pi)             // "3.14"
```

ZoomacIt にもまさにこのパターンが登場します。あとで実コードを読みます。

---

## Character 型 — 「真の 1 文字」

ここが Java からの転入組が **最初に驚く** ポイントです。Swift の `Character` は、Java の `char` とは似て非なるものです。

### Java の `char` は UTF-16 コードユニット 1 個

Java の `char` は 16 ビット固定で、UTF-16 のコードユニットを 1 個保持します。これは BMP(基本多言語面)の文字なら 1 個で表せますが、絵文字や歴史的文字など BMP 外の文字は **サロゲートペア** という 2 個の `char` で表現されます。さらに合成文字(基底文字 + 結合濁点など)も 1 文字を 2 コードポイント以上で表します。

```java
// Java
String s = "👨‍👩‍👧"; // 家族(絵文字、ZWJ シーケンス)
System.out.println(s.length()); // 8(コードユニット数)
System.out.println(s.charAt(0)); // 高サロゲート(意味のある文字ではない)
```

「文字数」と人間が思うものと、`length()` の値も `charAt(i)` も **一致しません**。

### Swift の `Character` は拡張書記素クラスタ

Swift の `Character` 型は *拡張書記素クラスタ(extended grapheme cluster)* を 1 つ表します。これは Unicode 標準が定義する **「人間が 1 文字と認識する単位」** です。

- `"a"` → 1 Character
- `"é"`(`e` + 結合アキュート U+0301)→ 1 Character
- `"👨‍👩‍👧"`(ZWJ で結合された家族絵文字)→ 1 Character
- `"🇯🇵"`(地域指示子 2 個)→ 1 Character

このため、`String.count` は **そのまま「人間が見たときの文字数」** を返します。

```swift
let family = "👨‍👩‍👧"
print(family.count)  // 1(Java では 8)

let café = "café"
print(café.count)    // 4
```

```swift
for ch in "Hi🇯🇵" {
    print(ch)
}
// H
// i
// 🇯🇵
```

`for ch in someString` の `ch` の型は `Character` です。1 つの `Character` を `String` に変換するには `String(ch)`、逆に 1 文字だけの `String` から `Character` を取り出すには `someString.first` などを使います(`first` は `Character?` を返します。Optional は Ch04 を参照)。

> **NOTE**
> 内部的には、Swift の `String` は UTF-8 で保持されており(Swift 5 で確定)、`Character` は必要に応じてその UTF-8 列を区切ります。同じ「é」でも、合成済み(U+00E9)と分解形(U+0065 + U+0301)の 2 通りの表現がありえますが、Swift の `==` は正規化等価(canonical equivalence)で比較するため、両者は等しいと判定されます。

### `String.Index` が `Int` でない理由

ここが 2 つめのつまずきポイントです。Swift で **`s[0]` のような直接インデックスはコンパイルエラー** になります。

```swift
let s = "hello"
let c = s[0]  // ❌ コンパイルエラー
```

理由は単純で、`String` が UTF-8 のバイト列で内部表現されており、しかも 1 文字が可変バイト長(1〜4 バイト)であるため、**「i 番目の文字」を O(1) で取り出すことが原理的にできない** からです。Java の `charAt(i)` のような API を提供してしまうと、UTF-16 単位の `i` を渡すことになり、Swift が大事にしている「拡張書記素クラスタ単位での 1 文字」というモデルが崩れます。

代わりに Swift では、`String.Index` という **不透明な型のインデックス** を使います。

```swift
let s = "hello"
let i = s.index(s.startIndex, offsetBy: 1)
print(s[i])  // "e"
```

`startIndex` と `endIndex` は型 `String.Index` を返します。`index(_:offsetBy:)` で前後に動かし、`s[i]` のように添字アクセスして初めて 1 文字を取り出せます。

> **NOTE**
> 「これって不便じゃないか?」というのは正しい違和感です。実務では `String.Index` を直接いじることは稀で、たいてい `contains` / `hasPrefix` / `replacingOccurrences` / `split` / 正規表現といった高水準 API で済みます。`String.Index` の出番は Ch15 *Subscripts* で再訪します。本章では「`Int` で添字できないのは Unicode 安全のため」とだけ覚えれば十分です。

---

## ZoomacIt の実コードを読む

ここまでの知識を使って、ZoomacIt のコードを実際に読みます。引用箇所はすべて Swift 6.0 でビルドされている本物のコードです。

### 例 1: ホットキーの表示文字列を「組み立て」で作る

`Settings.swift` には、ユーザーが設定したホットキーを `⌃⇧A` のような表示文字列に変換する関数があります。

> 引用元: `src/ZoomacIt/Models/Settings.swift:278-286`

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

注目ポイントを 3 つ。

1. **`var parts = ""`** で空文字列を `var`(再代入可)で確保しています。`String` は値型なのでこれで普通の可変ローカルが手に入ります(Java の `StringBuilder` を持ち出すまでもない)。
2. **`parts += "⌃"`** という連結代入を 4 回行っています。`⌃ ⌥ ⇧ ⌘` はすべて Unicode の修飾キー記号(U+2303 など)で、Java で書くなら `"⌃"` のようなエスケープが必要ですが、Swift のソースコードは UTF-8 で保存されているため **そのまま書けます**。
3. **キーコードを `keyCodeToString` で文字列に変換** したものを最後に連結しています。

Java で同等のコードを書くと `StringBuilder` を回すか `Stream` でジョインすることになりますが、Swift では `String` への `+=` がそのまま使えるのでこの素朴さで OK です。

そしてその `keyCodeToString` の中身 — ここに **本章で押さえた文字列補間** が登場します。

> 引用元: `src/ZoomacIt/Models/Settings.swift:314-316`

```swift
static func keyCodeToString(_ keyCode: UInt32) -> String {
    keyCodeDisplayNames[Int(keyCode)] ?? "Key\(keyCode)"
}
```

`keyCodeDisplayNames` は `[Int: String]` の辞書で、A〜Z や F1〜F12 などはあらかじめ表示文字を定義しています(Ch07 で扱う `Dictionary` 型です)。**辞書に該当キーがない場合のフォールバックとして `"Key\(keyCode)"`** を返しています。

ここで `\(keyCode)` の中の `keyCode` は `UInt32` 型ですが、書式指定子なしでそのまま文字列に変換されます。Java なら `"Key" + keyCode` と書くか、`String.format("Key%d", keyCode)` と書くところを、Swift では補間で素直に書けます。

### 例 2: タイマー時刻のゼロパディング — `String(format:)`

文字列補間で書けない代表例が **ゼロパディング** です。`BreakTimerState.swift` のフォーマッタが、まさにそれです。

> 引用元: `src/ZoomacIt/Models/BreakTimerState.swift:124-128`

```swift
var formattedTime: String {
    let minutes = remainingSeconds / 60
    let seconds = remainingSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
```

`remainingSeconds` が `65` なら `minutes = 1`、`seconds = 5` で、出力は `"1:05"` になります。`%02d` という指定子のおかげで秒は必ず 2 桁にゼロパディングされます。これを文字列補間 `"\(minutes):\(seconds)"` だけで書くと `"1:5"` になり、時計表示としては不適切です。

> **NOTE**
> Swift で「文字列補間と `String(format:)` のどちらを使うか」の経験則は、**書式指定子(`%02d`、`%.3f` など)が必要なら `String(format:)`、それ以外は補間**、です。`String(format:)` は `Foundation` をインポートしている必要があります(本ファイルは `import AppKit` 経由で `Foundation` も入ります)。

経過時間のほうも同じパターンです。

> 引用元: `src/ZoomacIt/Models/BreakTimerState.swift:131-135`

```swift
var formattedElapsed: String {
    let minutes = elapsedSinceExpiration / 60
    let seconds = elapsedSinceExpiration % 60
    return String(format: "(%d:%02d)", minutes, seconds)
}
```

書式リテラルの中にカッコ `( )` を直接書き込んでいる点に注目してください。`String(format:)` の第 1 引数はあくまで **書式文字列としての普通の `String`** なので、リテラル文字はそのまま書けます。

### 例 3: 通知名の組み立て

末尾近くにある `Notification.Name` の定義も、文字列を扱う良い例です。

> 引用元: `src/ZoomacIt/Models/Settings.swift:346-349`

```swift
extension Notification.Name {
    static let settingsDidReset = Notification.Name("settingsDidReset")
    static let hotkeysDidChange = Notification.Name("hotkeysDidChange")
}
```

`Notification.Name` は内部的に `String` を持つラッパー型(*RawRepresentable*)です。文字列リテラルを渡してインスタンス化していますが、ここに補間を入れることもできます。Java の `Object` ベースのイベント名と違って **コンパイル時に文字列をチェック** してくれるわけではない点は同じですが、`extension` で `static let` として束ねておくことで、タイプセーフな入口を作れます。これは Swift 流の慣習です(Ch24 *Extensions* で詳述します)。

---

## ハンズオン(任意)

学んだことを試すなら、`BreakTimerState.formattedTime` を改造して **時間 (`H:MM:SS`)** にも対応させてみてください。

ヒント:

- `remainingSeconds` を `3600`(1 時間)で割って時間部を求める
- 1 時間未満のときは従来どおり `"M:SS"` を返す
- 1 時間以上のときは `String(format: "%d:%02d:%02d", h, m, s)` を返す
- 既存テスト `BreakTimerStateTests.swift` に新しいケースを足す

書き終えたら `make test` でテストが通るか確認しましょう。

---

## まとめ — 章末 Notes

- `String` は **値型(struct)** です。代入やメソッド引数渡しは値のコピー的な意味論で扱われ、参照を共有する Java の `String` とはここが違います(ただし内部的には *copy-on-write* 最適化が効くので大量コピーで遅くなることは普通ない)。値型と参照型の話は Ch12 *Structures and Classes* で深く扱います。
- `Character` は拡張書記素クラスタ。`String.count` は人間が「これで 1 文字」と感じる単位を数えます。
- 直接 `s[0]` できないのは Unicode 安全のため。代わりに `String.Index` を使います — ただし詳細は **Ch15 *Subscripts* に forward reference**。実務では高水準 API で済むことがほとんどです。
- 文字列補間 `\(...)` は最初に習得すべき道具。`String(format:)` はゼロパディングや小数桁制御が必要なときだけ使う、と区別すれば迷いません。

## 次に読む章

→ [07. Collection Types](./07-collection-types.md)

ここまでで「単一の値」を表現する型(数値、Bool、String、Character)を一通り見ました。次章では **配列・辞書・Set** という、複数の値をまとめる型を扱います。`String` の `count` や `contains` で得た感覚は、`Array.count` / `Array.contains` でもそのまま通用します。
