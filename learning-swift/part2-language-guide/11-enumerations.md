# 11. Enumerations

## この章で学ぶこと

- Swift の `enum` が Java の `enum` と「だいたい同じ」に見えて、実は **代数的データ型 (Algebraic Data Type)** であるという根本的な違いを理解する
- `raw values` / `CaseIterable` といった Java enum との対応物を素早く押さえる
- Swift enum 最大の武器である **associated values** を使い、`Result<Success, Failure>` のような型安全なデータ表現を書けるようになる
- enum がメソッドや computed property を持てること、`indirect` で再帰列挙が書けることを知る
- `switch` の **網羅性チェック (exhaustiveness check)** が enum と組み合わさってどれほど強力なリファクタの安全網になるかを体感する
- ZoomacIt の `PenColor` `FontWeightOption` `ShapeType` `BackgroundMode` を読み解く

> **NOTE**
> この章は **丁寧解説章** です。Java 経験者が Swift の enum を流し読みすると associated values の真価を取りこぼします。少し長い章ですが、ここを腹落ちさせると Swift で書ける設計の幅が一段広がります。

---

## Java enum との 3 大違い (まず結論)

Swift の `enum` を学ぶ前に、Java 経験者が押さえるべき相違点を 3 つだけ先に明示します。

| 観点 | Java の `enum` | Swift の `enum` |
| --- | --- | --- |
| **値の本質** | クラスのインスタンスの有限集合。各定数はオブジェクト | 値型。各 case は単なるタグ (rawValue は付随情報) |
| **付随データ** | フィールドを持てるが、**全 case で同じ型** | **case ごとに異なる型** の付随データを持てる (associated values) |
| **switch** | `default` 省略時の網羅性チェックは弱い | コンパイラが **網羅性を厳格にチェック**。case 追加時に既存 switch がビルドエラーになる |

特に 2 番目の **「case ごとに異なる型のデータを持てる」** という性質によって、Swift の enum は Java で言う `sealed interface` + `record` の代替に近い表現力を獲得しています。Java 17 の `sealed class` と `record` を組み合わせて初めて書ける表現が、Swift では enum 1 つで完結します。

3 番目の網羅性チェックは地味に見えますが、実際のリファクタでは **「case を追加したら、対応漏れの switch がすべて赤線になる」** という挙動が極めて強力です。テストを書かなくてもコンパイラが対応漏れを検出してくれます。

---

## 11.1 基本 — case の宣言

最も素朴な使い方は、Java の enum と完全に一対一対応します。

```swift
enum Direction {
    case north
    case south
    case east
    case west
}

let heading = Direction.north
```

複数の case を 1 行にまとめることもできます (慣習的にはこちらの方がよく使われます)。

```swift
enum Direction {
    case north, south, east, west
}
```

### 推論を活かした短縮記法

Swift では型推論が強力なので、文脈から enum 型が確定している場面では **型名を省略してドット始まりで書けます**。

```swift
let heading: Direction = .north         // 右辺の型が Direction と分かるので .north でよい
move(direction: .east)                  // 引数の型が Direction なので .east だけで通る
```

Java では常に `Direction.NORTH` と書く必要があったのに対し、Swift は `.north` の **leading dot 記法** で簡潔に書けます。一見ただのシンタックスシュガーですが、SwiftUI や AppKit の API は `Color.red` `NSColor.systemRed` のように enum 風の static プロパティを大量に提供しており、この記法のおかげで読みやすさが大きく変わります。

> **NOTE**
> Swift の case 名は **lowerCamelCase** が公式スタイルです。Java の `NORTH` のような UPPER_SNAKE_CASE ではありません。`PenColor.red` `Direction.north` のように小文字始まりにしてください。

### switch との組み合わせ

```swift
let direction: Direction = .north

switch direction {
case .north: print("北へ")
case .south: print("南へ")
case .east:  print("東へ")
case .west:  print("西へ")
}
```

ここで `default` を **書いていない** ことに注目してください。これが Swift の網羅性チェックの効果で、すべての case を列挙していればコンパイラが完全性を保証してくれます。詳細は最後のセクションで扱います。

---

## 11.2 Raw Values — 各 case にプリミティブ値を紐付ける

Java の enum で `enum Color { RED("red"), GREEN("green"); private final String code; ... }` のように **コンストラクタ + フィールド** で書くパターンに相当するのが、Swift の **raw values** です。

```swift
enum HTTPStatus: Int {
    case ok = 200
    case notFound = 404
    case serverError = 500
}

let status = HTTPStatus.notFound
print(status.rawValue)   // 404
```

raw value として使える型には制約があります。

- `String`、`Character`
- `Int` / `UInt` 系の整数型
- `Float` / `Double` などの浮動小数点型

`String` を raw type にすると、各 case 名がそのまま raw value として **暗黙に割り当てられます**。

```swift
enum Direction: String {
    case north, south, east, west
}

print(Direction.north.rawValue)   // "north" — 自動で case 名と同じ文字列
```

`Int` を raw type にすると、最初の case が 0 で順に増えていきます (任意の値を明示的に振ることも可能)。

```swift
enum Priority: Int {
    case low      // 0
    case medium   // 1
    case high     // 2
}
```

### Failable Initializer — raw value からの復元

raw value を持つ enum には、`init?(rawValue:)` という **failable initializer** が自動生成されます。文字列や整数から enum を復元したいとき、たとえば `UserDefaults` から読み出した文字列を enum に戻すような場面で使います。

```swift
let raw = "north"
let dir = Direction(rawValue: raw)   // Optional<Direction>
// dir は .north (Optional でラップされている)

let unknown = Direction(rawValue: "northwest")
// unknown は nil — マッチする case がないため失敗
```

返り値が `Optional` になっている点が重要です。raw value が不正なら `nil` を返すので、利用側は `if let` や `guard let`、あるいは nil 合体演算子 `??` で **必ず失敗の可能性を扱う** ことになります。Java で `Direction.valueOf("northwest")` が `IllegalArgumentException` を投げるのとは対照的に、Swift は型システムの中で失敗を表現します。

### 実コード読解 — `PenColor` の raw values

ZoomacIt の `PenColor` は `String` を raw type に持つ enum です ([`src/ZoomacIt/Models/DrawingState.swift`](../../src/ZoomacIt/Models/DrawingState.swift) の冒頭)。

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink
    // ...
}
```

そして `Settings.swift` で `UserDefaults` との読み書きに `rawValue` と `init?(rawValue:)` の両方が使われています。

```swift
var defaultPenColor: PenColor {
    get { PenColor(rawValue: defaults.string(forKey: Keys.defaultPenColor) ?? "") ?? .red }
    set { defaults.set(newValue.rawValue, forKey: Keys.defaultPenColor) }
}
```

- 保存時: `newValue.rawValue` で `String` に変換して `UserDefaults` に書き込む
- 読み出し時: `UserDefaults` から取り出した `String?` を `PenColor(rawValue:)` で復元
- 失敗時 (key が無い、不正な値が入っている、新バージョンで case が削除された) は `?? .red` でフォールバック

これは **永続化と enum を橋渡しする最も典型的なパターン** です。Java で `enum.name()` と `Enum.valueOf(...)` を組み合わせて永続化するパターンに対応し、しかも例外ではなく Optional で安全に扱えます。

---

## 11.3 CaseIterable — `.allCases` で全 case を取得する

Java の `EnumClass.values()` に相当するのが Swift の `CaseIterable` プロトコルです。`enum` 宣言に `: CaseIterable` を付けるだけで、`allCases` という静的プロパティが自動生成されます。

```swift
enum Direction: CaseIterable {
    case north, south, east, west
}

for d in Direction.allCases {
    print(d)
}
// 出力: north / south / east / west (宣言順)
```

raw value と組み合わせる場合は、両方を併記します (順番に厳密な決まりはありませんが、慣習的に raw type を先に書きます)。

```swift
enum PenColor: String, CaseIterable {
    case red, green, blue
}

PenColor.allCases.map(\.rawValue)   // ["red", "green", "blue"]
```

設定画面のドロップダウンや列挙したいテストケースなど、**「全 case を 1 個ずつ処理したい」** 場面で頻繁に使います。

### 実コード読解 — `PenColor` `FontWeightOption`

ZoomacIt では `PenColor` も `FontWeightOption` も `CaseIterable` に適合しています。Settings 画面のピッカーで全 case を一覧表示するために `.allCases` を回しています。`FontWeightOption` ([`src/ZoomacIt/Models/Settings.swift`](../../src/ZoomacIt/Models/Settings.swift)) は 9 ケースもあるので、手書きで配列を作るより `CaseIterable` の方が圧倒的に保守的です。

```swift
enum FontWeightOption: String, CaseIterable, Sendable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black
    // ...
}
```

case を 1 つ増やしただけで、Settings 画面のドロップダウンに自動的に項目が追加されます。これは Java で `values()` を使うのと同じ感覚ですが、Swift は **コンパイラが自動合成する** という点が異なります (Java は実行時に内部配列を返す)。

> **NOTE**
> `Sendable` も後の章 (並行処理) で扱うプロトコルです。「他のスレッドに値を渡しても安全」というマーカーで、Swift 6 では概ねデフォルトで要求されます。enum は値型かつ全 case のデータが Sendable なら自動で Sendable に適合します。

---

## 11.4 Associated Values — Swift enum の真価

ここからが本章の核心です。Swift の enum は **case ごとに異なる型のデータを付随させる** ことができます。これを **associated values (関連値)** と呼びます。

### 文法

```swift
enum NetworkResult {
    case success(Data)
    case failure(Error)
    case cancelled
}
```

- `.success` は `Data` 型の値を 1 つ持つ
- `.failure` は `Error` 型の値を 1 つ持つ
- `.cancelled` は何も持たない

それぞれの case が **タグ付きの異なる構造** を取れるわけです。これが「Swift enum は代数的データ型」と言われる所以で、関数型言語 (Haskell の `data` / Rust の `enum` / OCaml の variant) でおなじみの概念を Swift も採用しています。

Java で同じことを表現しようとすると、`sealed interface NetworkResult permits Success, Failure, Cancelled` を宣言し、それぞれを `record Success(byte[] data)` `record Failure(Throwable error)` のように個別の型として定義する必要があります。Swift ではこれを enum 1 つで書ききれます。

### 値の構築

```swift
let r1: NetworkResult = .success(Data([0x48, 0x69]))
let r2: NetworkResult = .failure(URLError(.timedOut))
let r3: NetworkResult = .cancelled
```

### 値の取り出し — `switch` での pattern matching

associated values は `switch` の case パターンで `let` を使って **束縛 (bind)** します。

```swift
func describe(_ result: NetworkResult) {
    switch result {
    case .success(let data):
        print("受信 \(data.count) バイト")
    case .failure(let error):
        print("失敗: \(error.localizedDescription)")
    case .cancelled:
        print("キャンセル")
    }
}
```

`case .success(let data):` の `let data` 部分が、`.success(Data(...))` の中身を `data` という名前で取り出している箇所です。Java 21 の `switch` パターンマッチングで `case Success(byte[] data) -> ...` と書くのとほぼ同じ感覚ですが、Swift は 2014 年 (Swift 1.0) から最初の言語機能として備えていました。

### 複数の関連値とラベル

1 つの case に複数の値を持たせることも、各値にラベルを付けることもできます。

```swift
enum InventoryEvent {
    case added(productID: String, quantity: Int)
    case removed(productID: String, reason: String)
    case priceChanged(productID: String, oldPrice: Decimal, newPrice: Decimal)
}

let event: InventoryEvent = .priceChanged(
    productID: "ABC-123",
    oldPrice: 1000,
    newPrice: 1200
)

switch event {
case .added(let id, let qty):
    print("\(id) を \(qty) 個追加")
case .removed(let id, let reason):
    print("\(id) を削除 (理由: \(reason))")
case .priceChanged(let id, _, let newPrice):
    print("\(id) の新価格: \(newPrice)")
}
```

ラベルは省略しても動きますが、構築側 (`InventoryEvent.priceChanged(productID:oldPrice:newPrice:)`) の可読性が大きく上がるので、引数が 2 つ以上のときは付けることを強く推奨します。

`switch` 側で値を捨てたい場合は `_` を使います (`.priceChanged(let id, _, let newPrice)` の `_` が `oldPrice` を捨てている箇所)。

### `let` を 1 個にまとめる短縮記法

各引数ごとに `let` を書く代わりに、case パターン全体に `let` を 1 つだけ書くこともできます。

```swift
case let .added(id, qty):       // .added(let id, let qty) と等価
    print("\(id) を \(qty) 個追加")
```

慣習的にはどちらでも構いません。引数が多いときに `case let .foo(a, b, c, d):` のほうがすっきり書けます。

### 標準ライブラリの `Result<Success, Failure>` と `Optional<Wrapped>`

associated values の威力を最も体現しているのが、Swift 標準ライブラリの 2 つの enum です。

```swift
// 概念上はおおむねこう定義されている
enum Optional<Wrapped> {
    case none
    case some(Wrapped)
}

enum Result<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}
```

`Optional` ですら enum で実装されています。`nil` は `.none`、`x` は `.some(x)` の別名です。Swift の `?` `!` `if let` などの構文はすべて、この enum 上の糖衣構文だと考えると見通しがよくなります。

`Result` は非同期処理のコールバック値などで広く使われ、成功と失敗をひとつの値型で安全に運べます。

```swift
func fetchUser(id: String, completion: (Result<User, Error>) -> Void) { /* ... */ }

fetchUser(id: "alice") { result in
    switch result {
    case .success(let user): print("Hello \(user.name)")
    case .failure(let err):  print("Error: \(err)")
    }
}
```

> **NOTE**
> ZoomacIt のコードベースでは associated values を持つ独自 enum はまだ登場しません (シンプルな状態遷移にしか enum を使っていないため)。実例は教材専用の `NetworkResult` `InventoryEvent` で押さえてください。実プロジェクトで設計力を発揮し始めると、まずここに enum を入れたくなります。

---

## 11.5 enum 内のメソッドと Computed Property

Java の enum と同じように、Swift の enum も **メソッドや計算プロパティを持てます**。これは「enum は単なる定数の集合」という素朴な見方を捨てる必要があるポイントです。

### 構文

```swift
enum Direction {
    case north, south, east, west

    /// 反対方向を返す
    func opposite() -> Direction {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east:  return .west
        case .west:  return .east
        }
    }

    /// 角度 (時計回り、北を 0 とする)
    var degrees: Double {
        switch self {
        case .north: return 0
        case .east:  return 90
        case .south: return 180
        case .west:  return 270
        }
    }
}

let heading: Direction = .north
print(heading.opposite())   // south
print(heading.degrees)      // 0.0
```

メソッド/プロパティの中では `self` で **「自分はどの case か」** を参照できます。`self` は enum 値そのもので、`switch self` で分岐するのが定石です。

### 実コード読解 — `PenColor.nsColor` と `FontWeightOption.nsFontWeight`

ZoomacIt の `PenColor` には `nsColor` という computed property が定義されています。enum case を **AppKit の `NSColor` に変換する責務** を enum 自身が担っているわけです。

```swift
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
```

これがなぜ良い設計かを考えてみてください。`PenColor` を使う側 (描画コード、設定画面、Break Timer) は、自分で `if color == .red { ... } else if color == .green { ... }` と分岐する必要がありません。`color.nsColor` と書くだけで適切な `NSColor` が手に入ります。**enum 自身が変換ロジックを所有している** からこそ、新しい色を追加するときも `PenColor` の中だけを編集すれば済みます。

同じパターンが `FontWeightOption.nsFontWeight` と `FontWeightOption.displayName` でも使われています。9 ケースそれぞれを `NSFont.Weight` と人間可読な表示名に変換しています。

### `static func` も書ける

case を作るためのファクトリも `static func` で書けます。`PenColor.from(character:)` がその例です。

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

キーボードショートカット (`R` キーで赤、`G` キーで緑) の処理を enum 自身に集約しています。返り値が `Optional` なのは、対応しないキーが押された場合を表現するためです。`init?(rawValue:)` と精神的には同じパターンですが、こちらは独自の変換ロジックなので static func として書いています。

---

## 11.6 indirect — 再帰列挙

enum の各 case は通常、メモリレイアウト上 **固定サイズ** で確保されます。これが原因で、associated value に「自分自身の型」を含めようとすると問題が起きます (無限サイズになってしまう)。これを解決するキーワードが **`indirect`** です。

二分木をモデル化する古典的な例で確認しましょう。

```swift
indirect enum BinaryTree<T> {
    case leaf
    case node(value: T, left: BinaryTree<T>, right: BinaryTree<T>)
}

let tree: BinaryTree<Int> = .node(
    value: 1,
    left: .node(value: 2, left: .leaf, right: .leaf),
    right: .node(value: 3, left: .leaf, right: .leaf)
)
```

`indirect` を付けると、Swift は自分自身を含む case を **間接 (ヒープ参照) として扱う** ようになり、無限再帰を回避します。enum 全体に付ける書き方と、特定 case にだけ付ける書き方があります。

```swift
enum Expression {
    case number(Int)
    indirect case add(Expression, Expression)   // この case だけ indirect
    indirect case multiply(Expression, Expression)
}
```

実プロジェクトでは式木、構文木、リンクリストなど **木やリスト構造のモデル化** で使います。ZoomacIt では出てきません。「そういう機能がある」と覚えておくだけで十分です。

---

## 11.7 switch との相性 — 網羅性チェックという安全網

Swift の `switch` は enum と組み合わさると **コンパイラがすべての case を網羅していることを保証** します。これを exhaustiveness check と呼びます。

```swift
enum Direction {
    case north, south, east, west
}

func describe(_ d: Direction) -> String {
    switch d {
    case .north: return "北"
    case .south: return "南"
    case .east:  return "東"
    // case .west が無い → コンパイルエラー!
    }
}
// error: switch must be exhaustive
//   missing case '.west'
```

すべての case を列挙していれば `default` は不要です。逆に **`default` を書かない方が良い場面が圧倒的に多い** のが Swift の流儀です。理由を次に説明します。

### case 追加が壊れない (コンパイル時に検出される)

たとえば `PenColor` に `purple` を追加したとしましょう。

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink, purple   // ← 追加
    // ...
}
```

この瞬間、リポジトリ内の **`PenColor` を switch しているすべての場所** がコンパイルエラーになります。`PenColor.nsColor` の `switch self` がエラーになり、`PenColor.from(character:)` の `switch` もエラーになり、もし他のファイルで `switch color` していればそれも全部エラーになります。

これは **退屈な作業のように見えて、実は強烈な安全網** です。Java の enum で `default:` で既存ケースを処理していると、新しい case を追加しても既存コードはコンパイルが通ってしまい、実行時に `default` 経由で意図しない挙動になります。Swift は network・テスト・本番投入を待たずに **コンパイラが対応漏れを全部教えてくれる** わけです。

### `default` を書くべき / 書かないべき

| 場面 | おすすめ |
| --- | --- |
| 自分が所有する enum をすべて分岐する | `default` を **書かない**。case 追加時にコンパイラに教えてほしいから |
| 一部 case だけ処理し、他はまとめて無視 | `default` を **書く** か、`@unknown default` を使う |
| 他モジュール (フレームワーク) の enum を switch | `@unknown default` を **必ず** 書く (将来 case が増える可能性に備える) |

```swift
// 推奨されない: case 追加時に気付けない
switch color {
case .red:   return .systemRed
default:     return .black     // ← .green を追加してもここに落ちて気付かない
}

// 推奨: 全 case 列挙
switch color {
case .red:    return .systemRed
case .green:  return .systemGreen
case .blue:   return .systemBlue
// 以下略
}
```

### `if case let` — 1 個の case だけ取り出したいとき

`switch` で全 case を書くほどではなく、特定の 1 case だけマッチさせたいときは `if case let` が便利です。

```swift
let result: NetworkResult = .success(Data([0x01]))

if case let .success(data) = result {
    print("受信 \(data.count) バイト")
}
// .failure や .cancelled の場合は何もしない
```

`for case let` で配列から特定 case だけ抜き出すこともできます。

```swift
let results: [NetworkResult] = [.success(Data()), .failure(MyError.x), .cancelled]

for case let .failure(error) in results {
    print("失敗: \(error)")
}
// .failure ケースだけが反復される
```

これらの構文は **associated values と switch のフル網羅性チェックの中間** に位置する道具です。

---

## 11.8 ZoomacIt の enum を読み解く

最後に、ZoomacIt の enum 4 種を本章で学んだ語彙で整理します。

### `PenColor` ([`src/ZoomacIt/Models/DrawingState.swift`](../../src/ZoomacIt/Models/DrawingState.swift))

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink

    var nsColor: NSColor { /* AppKit 色への変換 */ }
    static func from(character: String) -> PenColor? { /* キー文字からの構築 */ }
}
```

ここまでの学習要素がすべて入っています。

- **raw values** (`String`): UserDefaults に保存
- **CaseIterable**: Settings 画面のピッカーで `.allCases` を反復
- **Sendable**: Swift 6 並行処理での値の安全な受け渡し
- **computed property**: enum 自身が AppKit 表現への変換責務を持つ
- **static factory**: キー入力からの構築を enum に集約

### `FontWeightOption` ([`src/ZoomacIt/Models/Settings.swift`](../../src/ZoomacIt/Models/Settings.swift))

`PenColor` と構造はほぼ同じで、**case が 9 個に増えた** のと **`displayName` で人間可読な表示名を持っている** のが違いです。設定画面で「Ultra Light」「Semibold」のように表示する文字列が enum 内にあるおかげで、UI 側のコードが分岐ロジックを持たずに済みます。

### `ShapeType` ([`src/ZoomacIt/Models/Stroke.swift`](../../src/ZoomacIt/Models/Stroke.swift))

```swift
enum ShapeType: Sendable {
    case freehand
    case line
    case rectangle
    case ellipse
    case arrow
}
```

**最もシンプルな enum** です。raw values も associated values もありません。「描画中のシェイプ種別」というドメイン概念をそのまま型にしている例で、Java の素朴な enum 用法と同じです。

ただし `Stroke` 構造体の中で `shapeType: ShapeType` というフィールドとして使われており、後段の描画コードでは `switch stroke.shapeType` で網羅的に分岐されます (`Draw/` 配下のレンダラ実装)。case が 1 つ増えれば描画パイプライン全体がコンパイルエラーになり、実装漏れがコンパイル時点で全部洗い出されます。

### `BackgroundMode` (nested enum)

```swift
final class DrawingState {
    // ...
    enum BackgroundMode {
        case transparent
        case whiteboard
        case blackboard
    }
    var backgroundMode: BackgroundMode = .transparent
}
```

`DrawingState` クラスの **内部に入れ子で定義された enum** です。Swift では型を別の型の中に入れ子で宣言でき、利用側からは `DrawingState.BackgroundMode` という名前空間付きで参照されます。

「`DrawingState` の中だけで意味を持つ概念」を **スコープを絞って表現する** のがこのパターンの目的です。Java で `static enum` を内部に書くのと同じ発想ですが、Swift では値型・参照型を問わず自由に nest できます。

> **NOTE**
> `Settings.Keys` も似た構造の入れ子型ですが、こちらは enum を **case を持たない名前空間** として使っています。`enum Keys { static let zoomHotkey = ... }` のように case を 1 つも持たない enum はインスタンス化できないため、Swift では「定数の入れ物」として頻出するイディオムです。Java の `final class Keys { private Keys() {} ... }` の代わりです。

---

## ハンズオン (任意)

時間に余裕があれば、以下を試して associated values と網羅性チェックを体感してください。

1. **`Result<Success, Failure>` を素手で実装してみる**
   ```swift
   enum MyResult<S, F: Error> {
       case ok(S)
       case ng(F)
   }
   ```
   `MyResult<Int, URLError>` を作り、`switch` で値を取り出すコードを書いて Playground で実行してみてください。

2. **`PenColor` に新しい色 `purple` を追加してみる**
   `src/ZoomacIt/Models/DrawingState.swift` で `case purple` を追加すると、`nsColor` の switch が網羅性違反でコンパイルエラーになります。実際にエラーがどこで出るか観察し、修正してください。`from(character:)` のほうは `default: return nil` があるので **エラーにならない** ことも確認しましょう。`default` を書くか書かないかで安全網の効き方が変わる、その違いを肌で感じることが目的です。

3. **入れ子型を作ってみる**
   `DrawingState.BackgroundMode` のように、自作のクラスや struct の中に enum を入れ子で定義してみてください。スコープを絞ると名前衝突を避けつつ意味のある型階層が作れます。

---

## まとめ

- Swift の enum は **値型** で、case 名は lowerCamelCase
- **raw values** で `String` `Int` などのプリミティブを各 case に紐付け、`init?(rawValue:)` で復元できる
- **CaseIterable** で `.allCases` が自動生成される (Java の `values()` 相当)
- **associated values** が Swift enum の真価。case ごとに異なる型のデータを持ち、代数的データ型として機能する
- enum は **メソッドや computed property** を持てる。変換ロジックを enum 自身に集約すると保守性が大きく上がる
- **`indirect`** で再帰列挙が書ける (木構造などに使う)
- `switch` の **網羅性チェック** が最強のリファクタ安全網。`default` は安易に書かないこと

Java の enum を「便利な定数」程度にしか使ってこなかった人は、Swift の enum を **「ドメインの状態を型として表現する第一の道具」** として位置づけ直してください。次章で学ぶ struct/class と並んで、Swift の設計力の中心はこの 3 つに集約されます。

## 次に読む章

→ [12. Structures and Classes](./12-structures-and-classes.md)
