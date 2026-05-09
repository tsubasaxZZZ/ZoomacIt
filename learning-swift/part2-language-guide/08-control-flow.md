# 08. Control Flow

Swift の制御フローは、Java 経験者にとって大半が見覚えのある構文です。`if` / `while` / `for-in` / `break` / `continue` はほぼ Java と同じ感覚で書けます。一方で `switch` と `guard`、そして `for-in` の `where` 節は Swift 特有の表現力を持ちます。本章ではまず Java と共通する基本構文をチートシート形式で素早く振り返り、その後 Swift 独自の機能を段落で丁寧に掘り下げます。

## この章で学ぶこと

- `if` / `while` / `repeat-while` / `for-in` の基本構文 (Java との対応)
- `break` / `continue` と *labeled statement* (ラベル付き文)
- `switch` の **網羅性チェック** ― default を書かなくて済む理由
- `switch` の **パターンマッチ** ― `case let` / `where` / タプル / *associated values* (関連値) の取り出し
- **range マッチ** ― 範囲で分岐する書き方
- `guard` 文による **早期リターン**
- `for-in` の `where` 節による条件付き反復
- ZoomacIt の `DrawingState` と `DrawingCanvasView` における実例

> **NOTE**
> 本章は Swift 6.0 を前提とします。`switch` のパターンマッチ機能は Swift 初期から備わっていますが、本章で扱う範囲はすべて現行バージョンで安定して利用できます。

## Java と共通する制御フロー (チートシート)

以下の構文は Java とほぼ同じセマンティクスを持ちます。条件式に括弧 `()` が要らない点と、本体ブロックの `{}` が必須である点だけ覚えておけば困りません。

| 構文 | Swift | Java | 備考 |
|------|-------|------|------|
| `if` / `else` | `if x > 0 { ... } else { ... }` | `if (x > 0) { ... } else { ... }` | 条件の括弧は不要、波括弧は必須 |
| `while` | `while x > 0 { ... }` | `while (x > 0) { ... }` | 同上 |
| `repeat-while` | `repeat { ... } while x > 0` | `do { ... } while (x > 0);` | キーワードが `do` ではなく `repeat` |
| `for-in` (拡張 for) | `for item in items { ... }` | `for (var item : items) { ... }` | `Sequence` プロトコルに準拠する任意の値を反復可能 |
| 範囲反復 | `for i in 0..<10 { ... }` | `for (int i = 0; i < 10; i++) { ... }` | 半開区間 `..<` と閉区間 `...` を使い分ける |
| `break` | `break` | `break;` | セミコロン不要 |
| `continue` | `continue` | `continue;` | 同上 |
| ラベル付き文 | `outer: for ... { break outer }` | `outer: for (...) { break outer; }` | 構文ほぼ同一 |

> **NOTE**
> Swift には C 形式の三項 `for (init; cond; update)` ループが存在しません。Swift 3 で削除されました。インデックスが必要なら `for i in 0..<n` か、`for (i, v) in array.enumerated()` を使います。

`repeat-while` は Java の `do-while` と同じく「最低 1 回は本体を実行する」ループですが、キーワードが異なる点は要注意です。Java からの移植中に `do { ... } while ...` と書いてしまうとコンパイルエラーになります (Swift の `do` は後述の `try`/`catch` 用)。

ラベル付き文も Java と同じ感覚で使えます。多重ループを一気に脱出したい場合に有効です。

```swift
search: for row in matrix {
    for value in row {
        if value == target {
            print("Found")
            break search   // 外側のループまで一気に脱出
        }
    }
}
```

## switch の網羅性チェック

ここからが Swift 独自の世界です。Swift の `switch` は **すべての可能なケースを網羅していなければコンパイルエラー** になります。これを *exhaustiveness check* (網羅性検査) と呼び、コンパイラが「ケース漏れ」を実行時ではなくビルド時に検出してくれます。

代表例が enum を分岐する `switch` です。enum のすべてのケースを列挙すれば `default` 句は不要であり、むしろ書かないほうが安全です。なぜなら、後で enum に新しいケースを追加したときに `default` で握りつぶされてしまうのを防げるからです。

ZoomacIt の `PenColor` enum には `nsColor` という *computed property* (計算プロパティ) があり、自身のケースに応じて `NSColor` を返します。

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink

    var nsColor: NSColor {
        switch self {
        case .red:    return .systemRed
        case .green:  return .systemGreen
        case .blue:   return .systemBlue
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .pink:   return .systemPink
        }
    }
}
```

> 引用元: src/ZoomacIt/Models/DrawingState.swift:4-16

ここに `default:` 句がないことに注目してください。6 ケースをすべて列挙しているため、`default` を書く必要がないどころか、書くと「ケース追加時に新しい色が暗黙のうちに既存色にフォールバックしてしまう」リスクが生じます。

試しに `case .pink:` の行を 1 行削除してビルドしてみると、コンパイラは次のような診断メッセージを出します。

```
error: switch must be exhaustive
  switch self {
  ^
note: add missing case: '.pink'
```

これは Swift 6 で実装されている網羅性検査の効果で、Java の `switch` (デフォルトでは網羅性を要求しない) と決定的に違う点です。Java 21 の `switch` 式でも `sealed` 型に対する網羅性検査がありますが、Swift の enum ではあらゆる enum で標準的に行われます。

### default が必要な場合

入力が enum ではなく文字列や整数のように「値の集合が事実上無限」な場合は、もちろん `default` が必要です。同じく `PenColor` 内にある、キャラクタからの色解決メソッドがそのパターンです。

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

> 引用元: src/ZoomacIt/Models/DrawingState.swift:19-29

`String` を分岐するため、未知の文字に備えて `default: return nil` でフォールバックしています。戻り値型が `PenColor?` (Optional) なのは、まさに「該当なし」を表現するためです。

### fallthrough は明示

Java の `switch` 文ではケース末尾に `break` を書き忘れるとフォールスルー (次のケースに継続実行) してしまいます。Swift はこれを反転させており、**各ケースは自動で抜ける** ので `break` は不要です。逆にフォールスルーしたい場合は `fallthrough` キーワードを明示します。

```swift
let value = 1
switch value {
case 1:
    print("one")
    fallthrough     // 明示的に次のケースへ
case 2:
    print("also two")
default:
    break
}
// 出力:
// one
// also two
```

ただし `fallthrough` は Swift では使う場面がかなり限られます。後述するパターンマッチや複数ラベル (`case 1, 2, 3:`) で要件をほぼ満たせるためです。

## switch のパターンマッチ

Swift の `switch` は単なる値の分岐ではなく、強力な *pattern matching* (パターンマッチ) を備えています。Java 21 のパターンマッチング `switch` 式と比較しても、機能が豊富です。

### 範囲マッチ (range matching)

`case` には値だけでなく **範囲** (`Range` / `ClosedRange`) を書けます。

```swift
let score = 73
switch score {
case 0..<60:        print("Fail")
case 60..<80:       print("Pass")
case 80...100:      print("Excellent")
default:            print("Out of range")
}
```

`0..<60` は半開区間 `[0, 60)`、`80...100` は閉区間 `[80, 100]` です。Java で同じことを書こうとすると `if`/`else if` を連ねるしかありませんが、Swift では網羅性検査の恩恵を受けながら可読性高く表現できます。

### タプル分解とワイルドカード

`switch` の対象はタプルにもできます。各要素に対して値・範囲・ワイルドカード `_` を組み合わせられます。

```swift
let point = (x: 0, y: 5)
switch point {
case (0, 0):
    print("Origin")
case (_, 0):
    print("On x-axis")
case (0, _):
    print("On y-axis")
case (-2...2, -2...2):
    print("Near origin")
default:
    print("Far away")
}
```

`_` は「何でもよい (値を捨てる)」というワイルドカードパターンで、`for` ループの索引が要らない場合などにも使います。

### 値バインディング — case let

マッチした値を新しい定数として束縛するには `case let` を使います。タプルや enum の関連値を取り出すのに頻出します。

```swift
let point = (x: 3, y: 0)
switch point {
case (let x, 0):
    print("On x-axis at \(x)")
case (0, let y):
    print("On y-axis at \(y)")
case let (x, y):
    print("Somewhere at (\(x), \(y))")
}
```

最後の `case let (x, y):` は *catch-all* (任意の値にマッチする) パターンとなるため、これがあれば `default` は不要です。

### where 節による絞り込み

ケースに追加条件を付けたいときは `where` 節を使います。

```swift
let point = (x: 3, y: 3)
switch point {
case let (x, y) where x == y:
    print("On the line y = x")
case let (x, y) where x == -y:
    print("On the line y = -x")
case let (x, y):
    print("At (\(x), \(y))")
}
```

これも Java の `case ... when ...` (Java 21) に近い書き方ですが、Swift では古くからこの形をサポートしています。

### enum の関連値の取り出し

enum が値を持つ場合 (associated values)、`switch` でその値を取り出して処理できます。詳しくは Ch11 で扱いますが、構文だけ先取りしておきます。

```swift
enum Result {
    case success(Int)
    case failure(message: String)
}

let r: Result = .failure(message: "timeout")
switch r {
case .success(let value):
    print("OK: \(value)")
case .failure(let message):
    print("NG: \(message)")
}
```

### ZoomacIt 実例 — ShapeType の網羅分岐

ZoomacIt の `DrawingCanvasView` では、ドラッグ中にその時点での `ShapeType` を判定して描画処理を分岐します。`ShapeType` は `freehand` / `line` / `rectangle` / `ellipse` / `arrow` の 5 ケースを持つ enum で、`switch` で全分岐を行います。

```swift
switch shapeType {
case .freehand:
    freehandPoints.append(currentPoint)
    activeFreehand = FreehandRenderer.smoothedPath(from: freehandPoints)
    previewLayer = nil

case .line:
    previewLayer = ShapeRenderer.linePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .rectangle:
    previewLayer = ShapeRenderer.rectanglePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .ellipse:
    previewLayer = ShapeRenderer.ellipsePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .arrow:
    previewLayer = ShapeRenderer.arrowPath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil
}
```

> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:159-180

ここでも `default:` がないことが重要です。将来 `ShapeType` に `.cloud` のような新しい形を追加した瞬間、コンパイラは「`switch` が網羅されていない」とエラーを出して、追従漏れを未然に防いでくれます。同じビューの `compositeStrokeOntoFinished(...)` 内 (`src/ZoomacIt/Draw/DrawingCanvasView.swift:377-389`) でも同じ網羅分岐が現れ、両者を同期して更新する必要があることがコンパイラによって保証されます。

## guard 文 ― 早期リターンを意図明確に

`guard` は Swift 特有の制御フロー文で、「条件が満たされなかった場合に **必ず現在のスコープを抜ける**」ことを宣言します。`if` を反転させた `if !condition { return }` と同じ意味になりますが、`guard` のほうが意図がコード上で明示されるため、防御的プログラミングのスタイルとして好まれます。

基本形は次のとおりです。

```swift
guard condition else {
    // ここで return / throw / break / continue / fatalError のいずれかが必須
    return
}
// 以降のコードでは condition が真であることが保証される
```

`else` ブロックの中では、現在のスコープを抜ける何らかの文 (`return`, `throw`, `break`, `continue`, `fatalError(...)` など) を必ず書く必要があります。これを書き忘れるとコンパイルエラーになります。

### guard let による Optional のアンラップ

`guard` がもっとも輝くのは Optional のアンラップです。`guard let` は「Optional が `nil` だったら早期リターン、そうでなければアンラップした値を後続のスコープで使える」というイディオムを 1 行で表現します。

ZoomacIt の `StatusBarController` の例を見てみましょう。メニューバーアイコンを設定する処理で、`statusItem?.button` (Optional) が `nil` だった場合は何もできないため早期リターンしています。

```swift
private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    NSLog("[StatusBar] statusItem created: %@", statusItem != nil ? "yes" : "no")

    guard let button = statusItem?.button else {
        NSLog("[StatusBar] ERROR: button is nil")
        return
    }

    // 以降、button は非 Optional として安全に使える
    if let image = NSImage(named: "MenuBarIcon") {
        image.isTemplate = true
        button.image = image
        ...
    }
}
```

> 引用元: src/ZoomacIt/App/StatusBarController.swift:33-58

`guard let button = ...` でアンラップした `button` は、**`guard` 文のあと、関数の終わりまでスコープを持ちます**。これは `if let` との大きな違いです。`if let` で束縛した定数はその `if` ブロック内でしか使えませんが、`guard let` の束縛は外側のスコープに「漏れる」のです。

これにより、`guard let` を関数の冒頭で並べてピラミッド状のネストを排除できます。Java の典型的な防御コード:

```java
// Java
if (x == null) return;
if (y == null) return;
if (z == null) return;
// 本処理
```

の Swift 版が以下です。

```swift
guard let x = optionalX else { return }
guard let y = optionalY else { return }
guard let z = optionalZ else { return }
// 本処理: x, y, z はすべて非 Optional
```

複数の Optional をまとめてアンラップすることもできます。

```swift
guard let x = optionalX, let y = optionalY, let z = optionalZ else {
    return
}
```

### guard と if let の使い分け

実用的なガイドラインとしては次のように使い分けます。

| 状況 | 選ぶべき構文 |
|------|------|
| 条件不成立時に処理を続行する選択肢がない (=早期リターンしたい) | `guard let` |
| 条件成立時にだけ何かをし、不成立時には何もしないで処理を続ける | `if let` |

ZoomacIt の C コールバック (`hotKeyEventHandler`) でも `guard` が使われています。`event` と `userData` が両方とも非 nil でなければハンドラとしては意味がないので、片方でも nil なら `eventNotHandledErr` を返して即座に抜けます。

```swift
private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKeyEvent(event)

    return noErr
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:187-200

ここでは Swift 5.7 以降で導入された **省略記法** `guard let event, let userData` (右辺を省略すると同名の Optional をそのままアンラップする) が使われています。`guard let event = event, let userData = userData` と書くのと等価です。

## for-in の応用

`for-in` 自体は Java の拡張 for と同じ用途ですが、Swift 特有のオプションがいくつかあります。

### where 節による条件付き反復

ループ本体の冒頭で `if condition { continue }` と書く代わりに、`for-in` 自体に `where` 節を付けられます。

```swift
let numbers = [-3, -1, 0, 2, 5, 8]
for n in numbers where n > 0 {
    print(n)
}
// 出力:
// 2
// 5
// 8
```

これは次のコードと等価ですが、意図がはるかに明確です。

```swift
for n in numbers {
    guard n > 0 else { continue }
    print(n)
}
```

### 範囲とストライド

`0..<n` (半開区間) や `0...n` (閉区間) のほか、`stride(from:to:by:)` を使えば任意の刻み幅で反復できます。

```swift
for i in stride(from: 0, to: 10, by: 2) {
    print(i)   // 0, 2, 4, 6, 8
}
```

### enumerated と zip

インデックスが欲しい場合は `enumerated()`、2 つの配列を同時に走査したい場合は `zip` を使います。

```swift
let names = ["Alice", "Bob"]
for (i, name) in names.enumerated() {
    print("\(i): \(name)")
}

let scores = [90, 85]
for (name, score) in zip(names, scores) {
    print("\(name) = \(score)")
}
```

これらは Ch07 で扱った `Sequence` プロトコルの一般機能で、配列・辞書・Set など多くのコレクションで使えます。

## まとめ

- 基本ループ (`if` / `while` / `for-in` / `break` / `continue`) は Java とほぼ同じ。条件式の括弧は不要、波括弧は必須。
- `repeat-while` のキーワードに注意 (`do-while` ではない)。
- `switch` は **網羅性検査** により、enum の全ケース対応をビルド時に保証する。`default` を書かないことが多い。
- `switch` は強力な **パターンマッチ** を持つ。`case let`、`where` 節、タプル分解、範囲マッチ、enum の関連値取り出しまで一気通貫で表現できる。
- `guard` は早期リターンのための専用構文で、Optional のアンラップとセットで使うとネストを大幅に減らせる。`guard let` で束縛した値は **外側のスコープに漏れる** のが `if let` との違い。
- `for-in` の `where` 節で、フィルタリングを 1 行で表現できる。

## 次に読む章

→ [09. Functions](./09-functions.md)
