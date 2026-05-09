# 25. Protocols

## この章で学ぶこと

**Protocol (プロトコル)** は、ある型が満たすべきメソッド・プロパティ・初期化子などの「要件 (requirement)」を宣言する仕組みです。Java の `interface` に概念的に最も近いものですが、Swift の protocol は次の 3 点で大きく拡張されています。

1. **struct / enum も protocol に適合できる** (Java の interface は class 限定)
2. **extension で既定実装 (default implementation) を提供できる**
3. **associated type (関連型) で抽象的な型パラメータを保持できる**

特に 2 つ目の **Protocol Extension** は、Swift コミュニティで「**Protocol-Oriented Programming (POP)**」という設計思想を生み出した中核機能です。Apple 自身が WWDC 2015 で「Swift is a protocol-oriented language」と宣言したことからも分かるとおり、protocol は Swift の存在意義のひとつと言ってよい言語機能です。Java で `interface` を「型契約」としてしか使ってこなかった人にとって、Swift の protocol は「型契約 + 共有実装の配布チャネル」へと役割を広げた、と捉えると理解が早まります。

本章では、protocol の基本構文から始めて、適合 (conformance)、要件の種類、Protocol Extension、where 句による条件付き準拠、associated type の概要、Protocol Composition、そして標準ライブラリで頻出する `Equatable` / `Hashable` / `Comparable` / `Codable` / `Sendable` / `CaseIterable` などを順に見ていきます。最後に Swift 5.7 で導入された existential `any` キーワードについても触れます。なお、associated type と generics の深い関係は次章 [26. Generics](./26-generics.md) で扱います。

---

## 基本構文

protocol の宣言は `protocol` キーワードから始まります。本体には「型がこの protocol に適合するために実装しなければならない要件」を列挙します。

```swift
protocol Drawable {
    var strokeWidth: Double { get }
    var color: String { get set }

    func draw()
    func area() -> Double
}
```

ここで宣言されているのは「Drawable 型は `strokeWidth` という読み取り専用 Double プロパティ、`color` という読み書き可能な String プロパティ、`draw()` と `area()` という 2 つのメソッドを持つ」という契約だけです。実装は一切ありません。Java の `interface` と見た目はとても近いので、Java 経験者は構文に戸惑うことはないでしょう。

### 命名規則

protocol 名は **「能力を表す名詞」**または **「〜able / 〜ible / 〜ing で終わる形容詞」** が標準です。これは Java の `Comparable`, `Iterable`, `Serializable` などと同じ感覚です。

```swift
protocol Renderable { ... }   // できることを名詞化
protocol Equatable { ... }    // できることを形容詞化
protocol DataSource { ... }   // 役割を名詞化
```

ZoomacIt のソースには独自定義の protocol はほぼ登場せず、AppKit / SwiftUI / 標準ライブラリの protocol に **適合する側** として頻繁に protocol を扱います。実務でもまず適合側から触れることが多いので、以降は「適合する」観点を重視して進めます。

---

## 適合 (Conformance)

ある型が protocol の要件をすべて実装することを **「protocol に適合する (conform to)」** と呼びます。型宣言のコロン `:` の後に protocol 名を書きます。

```swift
class Circle: Drawable {
    var strokeWidth: Double = 1.0
    var color: String = "red"

    func draw() { print("draw circle") }
    func area() -> Double { return 3.14 * 5 * 5 }
}
```

### 親クラスと protocol の同時指定

class が **親クラス** と **protocol** の両方を持つ場合、コロンの直後に「親クラスを 1 つだけ」、その後にカンマ区切りで「protocol を 0 個以上」書きます。Swift は単一継承なので、親クラスは必ず最初に書く必要があります。

```swift
class MyView: NSView, Drawable, Equatable {
    // NSView は親クラス、Drawable と Equatable は protocol
    static func == (lhs: MyView, rhs: MyView) -> Bool {
        return lhs === rhs
    }
    // ...
}
```

親クラスがないなら、コロンの直後にいきなり protocol を書きます。Java の `class Foo implements A, B` と違って `extends` / `implements` というキーワード分けはなく、すべてコロン 1 個で繋ぎます。

```swift
class Foo: SomeProtocol { ... }              // 親クラスなし、protocol 1 つ
class Bar: SomeProtocol, AnotherProtocol { } // protocol 複数
```

### 実例: AppDelegate

ZoomacIt のエントリポイントで、この「親クラス + protocol」パターンが使われています。

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager { HotkeyManager.shared }
    // ...

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching")
        // ...
    }
}
```

> 引用元: src/ZoomacIt/App/AppDelegate.swift:3-19

ここで `NSObject` は親クラス、`NSApplicationDelegate` は protocol です。`NSApplicationDelegate` は AppKit が定める「アプリの起動・終了などのライフサイクル通知を受け取る型」が満たすべき契約で、`applicationDidFinishLaunching(_:)` などのメソッドを実装することで AppKit から通知を受け取れるようになります。

なぜ `NSObject` を継承しているかというと、AppKit / Foundation の多くの protocol は **Objective-C 互換** を要求するため、`NSObject` 由来のメッセージング基盤が必要だからです。SwiftUI 専用のコードならこの継承は不要ですが、AppKit の delegate protocol を採用するなら `NSObject` 継承が事実上必須となります。Java で言えば「`AbstractListener` を継承しつつ、独自の `EventListener` interface も実装する」パターンに似ています。

---

## struct / enum も protocol に適合できる (Swift 特有)

Java の `interface` は **class でしか実装できません**。`enum` が `interface` を実装することはできますが、`struct` や `record` (Java 14+) が `interface` を実装するケースは限定的でした。

Swift では **値型 (struct / enum)** も class とまったく対等に protocol に適合できます。これは単なる文法上の対称性ではなく、Swift が「値型を第一級市民として扱う」という設計思想の現れです。標準ライブラリの `Int`, `String`, `Array`, `Dictionary` などはすべて struct で実装され、`Equatable`, `Hashable`, `Comparable`, `Codable` といった多数の protocol に適合しています。

### enum + 複数 protocol の例: PenColor

ZoomacIt の `PenColor` は、enum でありながら 3 つの protocol に同時適合しています。

```swift
/// Available pen/text colors.
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink

    var nsColor: NSColor {
        switch self {
        case .red:    return .systemRed
        case .green:  return .systemGreen
        // ...
        }
    }

    static func from(character: String) -> PenColor? {
        switch character.uppercased() {
        case "R": return .red
        // ...
        default:  return nil
        }
    }
}
```

> 引用元: src/ZoomacIt/Models/DrawingState.swift:3-30

ここで `: String, Sendable, CaseIterable` は次のように読み解きます。

| 適合先 | 役割 |
|--------|------|
| `String` | enum の **raw value 型** を String と宣言 (これは特殊で、最初の項目が raw value 型として解釈される) |
| `Sendable` | 並行処理 (Swift Concurrency) で安全に `actor` 境界を超えられる型であることを表す protocol |
| `CaseIterable` | 全ケースを `PenColor.allCases` として配列で取得できることを表す protocol |

最初の `String` だけが特殊で、enum の場合は「**raw value 型 + 任意個の protocol**」という順序になります。それ以外はすべて protocol で、コンマ区切りで列挙できます。Java で同じことをしようとすると、enum に `Comparable<E>` などを実装するくらいしかできず、`Sendable` のような並行性タグや `CaseIterable` のような自動全列挙機能は言語機能として用意されていません。

`FontWeightOption` も同じパターンです。

```swift
/// Font weight options for text input, persistable as raw String.
enum FontWeightOption: String, CaseIterable, Sendable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    var nsFontWeight: NSFont.Weight { /* ... */ }
    var displayName: String { /* ... */ }
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:4-43

protocol の順序は `String, CaseIterable, Sendable` でも `String, Sendable, CaseIterable` でも同じ意味で、コンパイラは順不同で扱います。コーディング規約として揃えればよいでしょう。

### struct + protocol の例: SwiftUI View

SwiftUI の **View** は protocol です。SwiftUI のすべての画面・部品は struct でこの protocol に適合します。

```swift
import SwiftUI

/// Root settings view with tabs for each configuration category.
struct SettingsView: View {

    @State private var showResetAlert = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralTab()
                    .tabItem { Text("General") }
                DrawTab()
                    .tabItem { Text("Draw") }
                // ...
            }
            // ...
        }
    }
}
```

> 引用元: src/ZoomacIt/Settings/SettingsView.swift:1-19

`struct SettingsView: View` の 1 行が、Swift の protocol 設計思想を象徴しています。

- SwiftUI の View は **値型 (struct)** であることが推奨される (毎フレーム再生成されても安価なため)
- 適合の要件は「`var body: some View { get }` を実装すること」のみ
- 親クラスは存在しない (継承ではなく組み合わせで UI を構築する)

Java/Swing や Java/JavaFX が `extends JComponent` のような継承ベースだったのに対し、SwiftUI は「View protocol に適合する struct」という値型 + protocol の構成に振り切りました。これは Swift が protocol を中心に据えていなければ実現できなかった設計です。

---

## 要件の種類

protocol の本体に書ける要件は、大きく次の 4 種類です。

### 1. プロパティ要件 (Property Requirement)

`var` で宣言し、必ず `{ get }` または `{ get set }` を末尾につけます。型は推論されないので明示が必要です。

```swift
protocol Vehicle {
    var name: String { get }            // 読み取りのみ要求
    var speed: Double { get set }       // 読み書き両方を要求
    static var maxSpeed: Double { get } // type property も可
}
```

- `{ get }` は「読めること」のみを要求し、適合側で `let` または `var` で実装してよい
- `{ get set }` は「読み書き両方」を要求し、適合側は `var` でしか実装できない (`let` だと set が満たせない)

Java の interface には `default` メソッドを除いてフィールドを書けない (定数しか書けない) のと対照的に、Swift では「プロパティを持つ契約」を直接表現できます。

### 2. メソッド要件 (Method Requirement)

通常のメソッド宣言から `{ ... }` ブロックを削っただけの形です。

```swift
protocol Renderer {
    func render(into rect: CGRect)
    static func defaultRenderer() -> Renderer
    mutating func reset()  // 値型でも自己変更を許可するなら mutating を付ける
}
```

`mutating` は struct / enum 用のキーワードで、「自分自身のプロパティを変更するメソッド」であることを明示します。class の場合は `mutating` は不要ですが、protocol 側で `mutating` 付きで宣言してあれば class 側でも互換的に実装できます (class の側では `mutating` は省略します)。

### 3. 初期化子要件 (Initializer Requirement)

protocol は initializer の実装も要求できます。

```swift
protocol Configurable {
    init(config: [String: Any])
}

class MyService: Configurable {
    required init(config: [String: Any]) {  // class では required が必須
        // ...
    }
}
```

class が initializer requirement を満たす場合、`required` 修飾子を付ける必要があります。これは「サブクラスもこの initializer を必ず実装する」という保証で、protocol 適合の継承可能性を担保するためです。struct / enum には継承がないため `required` は不要です。

### 4. associated type 要件

「型」そのものをパラメータとして抽象化する要件です。詳細は後述します。

---

## Protocol Extension (Swift 特有・最重要)

ここからが Swift protocol の真骨頂です。**Protocol Extension** を使うと、protocol に対して **既定実装 (default implementation)** を後付けで提供できます。

```swift
protocol Greetable {
    var name: String { get }
    func greet()
}

extension Greetable {
    func greet() {
        print("Hello, \(name)!")
    }
}

struct User: Greetable {
    var name: String
    // greet() を実装しなくても良い -- 既定実装が使われる
}

User(name: "Alice").greet()  // => "Hello, Alice!"
```

`User` は `greet()` を一切実装していないにもかかわらず、Greetable に適合し、greet() を呼び出せます。これが既定実装の威力です。

### Java 8 default method との違い

Java 8 で `interface` に `default` メソッドが導入されたことで、Java も似たことができるようになりました。しかし Swift の Protocol Extension は次の点で Java の default method を上回ります。

| 観点 | Java default method | Swift Protocol Extension |
|------|---------------------|--------------------------|
| 既定実装の追加位置 | interface 本体内のみ | extension で別ファイルにも書ける (元の protocol に変更不要) |
| 標準ライブラリへの拡張 | 不可 (`java.util.List` を改造できない) | 可能 (`extension Collection` で全 Collection 型にメソッドを追加できる) |
| 条件付き既定実装 | 不可 | `where` 句で要素型などに条件を付けられる |
| 静的ディスパッチでの上書き | 完全に動的 | protocol 要件外のメソッドは静的ディスパッチ |

特に **「他人が定義した protocol に対して、後から既定実装を足せる」** という性質は、Java では絶対に不可能なことです。Swift では `extension Sequence { func myCustomReduce() { ... } }` のように、Apple の標準 protocol に対して自分のメソッドを追加できます。これにより「ライブラリの機能をユーザー側で拡張する」という横方向の拡張が可能になり、Swift コミュニティでは「protocol-oriented programming」と呼ばれる設計様式が定着しました。

### 既定実装 + 上書き

既定実装は、適合側で独自実装すれば上書きされます。

```swift
struct VipUser: Greetable {
    var name: String
    func greet() {
        print("Welcome back, esteemed \(name)!")  // 既定実装を上書き
    }
}
```

ここで注意すべきは、**protocol で要件として宣言されているメソッド** と、**extension にしか書かれていないメソッド** で挙動が異なる点です。

```swift
protocol P {
    func required()    // 要件として宣言
}

extension P {
    func required() { print("default required") }
    func extra()      { print("default extra") }    // 要件外
}

struct S: P {
    func required() { print("S required") }
    func extra()    { print("S extra") }
}

let p: P = S()
p.required()  // => "S required"  (動的ディスパッチ)
p.extra()     // => "default extra" (静的ディスパッチ; protocol 要件にないため)
```

この挙動は Swift 初学者がつまずきがちな箇所です。**protocol で宣言された要件は動的ディスパッチ、extension にしか書かれていないメソッドは静的ディスパッチ** と覚えておきましょう。意図せず既定実装が呼ばれてしまうのを避けるには、上書きしたいメソッドは必ず protocol 本体に要件として宣言します。

### Protocol Extension の典型用途

- **共通ロジックの集約** — 複数の適合型が同じ実装を共有する場合に重複を排除
- **ミックスイン的な機能注入** — 「この protocol に適合した型は自動的に〜できる」を実現
- **標準ライブラリへの後付け機能追加** — `extension Collection where Element: Numeric { var sum: ... }` のような拡張

ZoomacIt のソース内には独自 protocol への extension は登場しませんが、SwiftUI の `View` には膨大な protocol extension (`.padding()`, `.frame()`, `.onAppear()` など) が定義されており、これらすべてが Protocol Extension の応用例です。`SettingsView` の `.tabItem { ... }` や `.frame(minWidth: 480, minHeight: 320)` も、すべて `extension View { ... }` で提供されています。

---

## Where 句による条件付き準拠

protocol extension に `where` 句を付けることで、「適合型が特定の条件を満たすときだけ既定実装を提供する」ことができます。

```swift
extension Array where Element: Equatable {
    func containsDuplicates() -> Bool {
        for (i, a) in enumerated() {
            for b in self[(i+1)...] {
                if a == b { return true }
            }
        }
        return false
    }
}

[1, 2, 3].containsDuplicates()      // OK -- Int は Equatable
[1, 2, 2].containsDuplicates()      // OK
// 仮に Equatable でない型の Array に対しては、このメソッドは見えない
```

`where Element: Equatable` は「Element が Equatable に適合する場合に限り、この extension を適用する」という意味です。Java で言えば「`<E extends Comparable<E>> void method()`」のような型境界に近い概念ですが、Swift の where 句はメソッド単位ではなく **extension 全体** に適用できる点で表現力が高くなっています。

ある型が条件を満たすときに自動的にある protocol への適合を獲得する **「Conditional Conformance (条件付き準拠)」** という機能もあります。

```swift
extension Array: Equatable where Element: Equatable {
    // Element が Equatable なら Array<Element> も自動的に Equatable
}
```

これにより `[1, 2, 3] == [1, 2, 3]` のような比較が、Element が Equatable のときだけ可能になります。標準ライブラリの多くの protocol 適合は条件付き準拠で実現されています。

---

## Associated Type の概要

protocol の中で「型そのものを抽象化したい」場面があります。たとえば「何かを保持できるコンテナ」の抽象を作りたいとき、何の型を保持するのかは適合側が決めるべきです。

```swift
protocol Container {
    associatedtype Item
    var count: Int { get }
    mutating func append(_ item: Item)
    subscript(i: Int) -> Item { get }
}

struct IntStack: Container {
    typealias Item = Int   // 明示することもできる (省略可能)
    var items: [Int] = []
    var count: Int { items.count }
    mutating func append(_ item: Int) { items.append(item) }
    subscript(i: Int) -> Int { items[i] }
}
```

`associatedtype Item` は「Container に適合する型が決める、保持要素の型のプレースホルダ」です。`IntStack` では `Item = Int` と決まっています。`typealias Item = Int` は省略しても、append のシグネチャから Swift が型推論で決定してくれます。

これは Java の **ジェネリック interface (`interface Container<T>`)** に対応する機能ですが、Swift では `protocol Container<Item>` ではなく `associatedtype` キーワードで宣言する点が異なります (なお Swift 5.7 以降は `protocol Container<Item>` という primary associated type 構文も追加されていますが、本書では associatedtype による従来形を基本とします)。

associated type を持つ protocol は「**PAT (Protocol with Associated Type)**」と呼ばれ、変数の型として直接使うには制約があります。これについては次節と次章で扱います。Generics との深い関係や具体的な使いこなしは [26. Generics](./26-generics.md) で詳しく掘り下げますので、ここではキーワードと役割だけを押さえてください。

---

## Protocol Composition

「2 つ以上の protocol に同時適合する型を引数に取りたい」場合、`&` で protocol を合成できます。

```swift
protocol Named {
    var name: String { get }
}

protocol Aged {
    var age: Int { get }
}

func greet(_ person: Named & Aged) {
    print("Hello, \(person.name), age \(person.age)")
}
```

`Named & Aged` は「Named にも Aged にも適合した型」を表します。Java で言えば「`<T extends Named & Aged>`」と書く境界宣言に対応しますが、Swift の方は **その場限りの匿名型** として直接使えるので簡潔です。

class を含めることもできます (ただし class は最大 1 つ)。

```swift
func handle(_ view: NSView & Drawable) {
    // NSView (またはサブクラス) かつ Drawable に適合
}
```

Protocol Composition は、**型エイリアス** にして名前を付けることもよく行われます。

```swift
typealias Identifiable = Named & Aged
func register(_ x: Identifiable) { ... }
```

---

## 標準ライブラリで頻出する Protocol

Swift 標準ライブラリには、適合するだけで便利な機能が手に入る protocol が多数あります。代表的なものを 1 行ずつまとめます。

| Protocol | 役割 (1 行説明) |
|----------|------------------|
| `Equatable` | `==` / `!=` 比較が可能になる。要件は `static func == (lhs:rhs:) -> Bool` のみ |
| `Hashable` | Set / Dictionary のキーに使える。Equatable を継承し、`hash(into:)` を要求 |
| `Comparable` | `<`, `<=`, `>`, `>=` が使える。ソート可能になる。Equatable を継承 |
| `Codable` | JSON などへのエンコード/デコードを自動生成。`Encodable & Decodable` の typealias |
| `Sendable` | 並行処理で actor 境界を安全に超えられる型であるという**マーカー**。データ競合を型検査で防ぐ |
| `CaseIterable` | enum の全ケースを `Type.allCases` で取得可能にする。コンパイラが自動生成 |
| `Identifiable` | `var id: ID { get }` を要求。SwiftUI の List / ForEach で使用 |
| `Sequence` | `for-in` で反復可能な型。Iterator を提供する |
| `Collection` | サブスクリプトとインデックスでアクセス可能な Sequence。Array / String / Dictionary が適合 |
| `Error` | `throw` で投げられる型。中身の要件は空 (マーカー protocol) |

これらの多くは Swift コンパイラが **自動合成** してくれます。たとえば struct のすべての保存プロパティが Equatable なら、`struct Foo: Equatable { ... }` と書くだけで `==` の実装は自動生成されます。Java で `equals()` / `hashCode()` を毎回手書きする (あるいは Lombok / record に頼る) のと比べ、Swift の体験は劇的に簡潔です。

### Sendable の特殊事情: `@unchecked Sendable`

`Sendable` は中身のないマーカー protocol ですが、コンパイラが「本当にこの型は並行処理で安全か」を厳密にチェックします。値型なら基本的に自動で適合できますが、参照型 (class) では「内部状態が並行アクセスから保護されているか」を Swift がデフォルトでは判断できません。

そこで「私が責任を持つから、コンパイラのチェックはスキップしてくれ」と宣言する手段が `@unchecked Sendable` です。ZoomacIt の `Settings` クラスがこれを使っています。

```swift
/// Centralized settings manager backed by UserDefaults.
/// Thread-safe (UserDefaults is thread-safe).
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }
    // ...
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:45-55

ここでは「内部で使う `UserDefaults.standard` 自体がスレッドセーフなので、Settings 全体としてもスレッドセーフである」というコメント付きの根拠のもと、`@unchecked Sendable` で適合させています。`@unchecked` は強力ですが、安全性の保証を**コンパイラから人間に移譲する**ものなので、根拠を必ずコメントとして残すことが慣例です。Java で `synchronized` を付け忘れたときに発生する問題を、Swift は **コンパイル時に検出する**側に振り切った結果、こうした逃げ道が必要になっている、と捉えるとよいでしょう。

並行性と Sendable の詳細は [21. Concurrency](./21-concurrency.md) を参照してください。

---

## Existential `any` と PAT の制約 (軽く)

Swift 5.7 から、protocol を「変数の型」として使う際に `any` キーワードを付けることが推奨されるようになりました。

```swift
let drawables: [any Drawable] = [Circle(), Rectangle()]
```

`any Drawable` は **existential type (存在型)** と呼ばれ、「Drawable に適合する何らかの具体型を内部に隠し持つ箱」を表します。Java の `List<Drawable>` のような感覚に近いものです。

`any` を付けない裸の `Drawable` も従来は同義に動作しましたが、Swift 5.7 以降は `any` を明示することで、

- 「**存在型として使っている (= 動的ディスパッチが入る)**」
- 「ジェネリック制約として使っている (= 静的に解決される)」

の意図の違いを書き手が表現できるようになりました。これは性能・最適化に直結する区別です。

associated type を持つ protocol (PAT) は、長らく裸の型として使うことができませんでした (`let c: Container` はエラー)。Swift 5.7 以降は `let c: any Container` と書けば PAT も existential として保持できるようになりましたが、`Item` の型情報は隠されてしまうため、操作には制限があります。

```swift
let c: any Container = IntStack()  // OK (Swift 5.7+)
// c.append(1) は型 Item が隠されているので直接は呼べない (open existential が必要)
```

この領域は [26. Generics](./26-generics.md) で詳しく扱います。本章では「PAT は existential として持つと制約がある。だから多くの場合、PAT はジェネリック関数の制約として使う」とだけ覚えておけば十分です。

---

## ZoomacIt の実コード読解

ここまで学んだことを踏まえて、ZoomacIt のコードを読み解いてみましょう。

### 1. `final class AppDelegate: NSObject, NSApplicationDelegate`

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ...
    }
}
```

> 引用元: src/ZoomacIt/App/AppDelegate.swift:3-19

- `@MainActor` — クラス全体をメインスレッドに固定する属性 (Concurrency 章参照)
- `final` — このクラスはサブクラス化禁止
- `: NSObject` — 親クラス (Objective-C 互換のため必須)
- `, NSApplicationDelegate` — protocol 適合

`NSApplicationDelegate` は「optional な要件」を多数含む protocol で、適合側はそのうち必要なものだけ実装すればよくなっています。これは Objective-C 由来の protocol 機能で、純 Swift の protocol では (現状) optional 要件を持てません (`@objc optional` で擬似的に表現はできますが、Objective-C ランタイム前提となります)。

### 2. `enum PenColor: String, Sendable, CaseIterable`

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink
    // ...
}
```

> 引用元: src/ZoomacIt/Models/DrawingState.swift:4-30

このたった 1 行から、Swift コンパイラが次のすべてを保証 / 自動生成してくれます。

- `String` raw value (`PenColor.red.rawValue == "red"`) と、`PenColor(rawValue: "red")` での復元
- `Sendable` 適合 → actor 境界を超えても安全 (値型 enum なので自動で OK)
- `CaseIterable` 適合 → `PenColor.allCases == [.red, .green, .blue, .orange, .yellow, .pink]`

Java で同じ機能を持たせるには、各 case ごとにフィールドとコンストラクタ、`values()` (これは元から自動)、`fromString()` の手書き、そして並行性は別途同期で守る、というかなりの手間がかかります。Swift の protocol-driven な自動合成がいかに強力か分かるはずです。

### 3. `struct SettingsView: View`

```swift
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) { /* ... */ }
    }
}
```

> 引用元: src/ZoomacIt/Settings/SettingsView.swift:4-19

`View` protocol の唯一の要件は `var body: some View { get }` です。`some View` は **opaque type (不透明型)** で、「具体的な型は隠されているが、何らかの View に適合した単一の型である」ことを表します。これも Swift 5.1 以降に導入された protocol 関連機能です。

`SettingsView` 自体は何も継承していません。SwiftUI のすべての画面構成は **「View protocol に適合した struct の合成」** で行われ、継承関係は登場しません。これは Java/JavaFX や AppKit (NSView を継承して使う) と対照的な設計で、Apple が protocol-oriented programming を本気で実践したらこうなる、というショーケースです。

### 4. `final class Settings: @unchecked Sendable`

```swift
final class Settings: @unchecked Sendable {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    private init() { registerDefaults() }
    // ...
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:47-55

- `final class` — サブクラス化禁止の参照型
- `@unchecked Sendable` — Sendable 適合だが、コンパイラ検査をオプトアウト
- `static let shared` + `private init()` — シングルトンパターン

「シングルトンを並行コードに渡せるようにしたいが、Settings は class なので Swift コンパイラは Sendable を自動付与しない。内部の `UserDefaults` がスレッドセーフであることを根拠に `@unchecked` で適合させる」という典型パターンです。Java の `enum` シングルトンが (たまたま) スレッドセーフになるのとは対照的に、Swift では「並行性安全の根拠を **意図して明示する**」設計になっています。

---

## ハンズオン (任意)

理解を確かめたい人向けの練習問題を 3 つ示します。手元の Swift Playground や `swift run` で試してみてください。

1. **既定実装の効果を体感する**

   ```swift
   protocol Animal {
       var name: String { get }
       func describe()
   }
   extension Animal {
       func describe() { print("\(name) is an animal.") }
   }

   struct Dog: Animal { var name: String }
   struct Cat: Animal {
       var name: String
       func describe() { print("\(name) says meow.") }
   }
   ```

   `Dog(name: "Pochi").describe()` と `Cat(name: "Tama").describe()` の出力を予想 → 実行して確認。

2. **静的ディスパッチの罠**

   protocol 本体に宣言されたメソッドと、extension にしか書かれていないメソッドで、上書きの効きが違うことを確認してください (本章の「既定実装 + 上書き」節のサンプルを Playground で動かすのが最短です)。

3. **複数 protocol への適合**

   独自 struct を作り、`Equatable`, `Hashable`, `CustomStringConvertible` の 3 つに適合させてみてください。`==` と `hash(into:)` は自動合成、`description` は手書きが必要です。`print(myStruct)` と `Set([myStruct])` の動作を確認。

---

## まとめ

- protocol は Java の interface 相当だが、Swift では struct / enum も適合できる
- 親クラスと protocol を併用するときは、コロンの後に親クラス → protocol の順で書く
- 要件にはプロパティ・メソッド・初期化子・associated type の 4 種がある
- **Protocol Extension** で既定実装を提供できる。これが Swift 最大の特徴
- `where` 句で条件付き既定実装 / 条件付き準拠を表現できる
- associated type で型そのものを抽象化できる (詳細は次章)
- `&` で protocol を合成できる (Protocol Composition)
- 標準 protocol は適合するだけで強力な機能を獲得できる (`Equatable`, `Hashable`, `Codable`, `Sendable`, `CaseIterable` など)
- Swift 5.7+ では `any P` という existential 表現で protocol を変数型として使う

Java の interface を **「型契約」** として理解していた人は、Swift では protocol を **「型契約 + 共有実装の配布チャネル + 抽象化の中心」** として捉え直す必要があります。これに馴染めば、Swift の標準ライブラリも SwiftUI も、急速に読みやすくなるはずです。

## 次に読む章

→ [26. Generics](./26-generics.md)
