# 19. Optional Chaining

## この章で学ぶこと

- Ch04 で導入した Optional の使いこなしとして、**Optional Chaining (`?.`)** を体系的に学ぶ
- `obj?.property`、`obj?.method()`、`obj?[key]` の各形式と、**「途中に `nil` があれば全体が `nil`」** という伝播ルール
- Optional な関数値・クロージャの呼び出し (`onZoomHotkey?()`)、Optional 経由の代入 (`self?.zoomController = nil`) という Swift 特有の表現
- `if let` / `guard let` との使い分け — **値を取り出して使うか、副作用なく連鎖させるか**
- 強制アンラップ `!` の危険性 (Ch04 の再確認)
- ZoomacIt の `AppDelegate` と `HotkeyManager` から、Optional Chaining が実コードでどう使われているかを読む

> **NOTE**
> この章は **丁寧解説章** です。Optional は Swift の型システムにおける中核機構であり、Optional Chaining はその表現力を最大限引き出す構文です。Java 8 以降の `Optional.map(...).orElse(...)` チェーンと意味的には近いですが、Swift のほうが構文的にはるかに簡潔で、なおかつ「副作用としてのメソッド呼び出し」「Optional への代入」といった Java の `Optional` API では表現しきれない領域までカバーします。**nil 安全プログラミングの真髄** がここにあります。

---

## 19.1 Optional の復習 (Ch04 から)

Optional Chaining に入る前に、Ch04 で導入した Optional の基本を簡単に復習しておきます。

### Optional 型 `T?`

Swift では「値があるかもしれないし、`nil` かもしれない」型を **`T?`** (= `Optional<T>`) で表現します。これは内部的には次の enum と等価です。

```swift
enum Optional<Wrapped> {
    case none           // nil
    case some(Wrapped)  // 値あり
}
```

```swift
var name: String?       // nil で初期化される
name = "Alice"          // .some("Alice") に
name = nil              // .none に戻せる
```

| 概念 | Java | Swift |
| --- | --- | --- |
| nil 許容型 | `String` (参照型は常に `null` 可) / `Optional<String>` | `String?` |
| 非 nil 型 | `@NonNull String` (アノテーション、強制力弱) | `String` (型システムで保証) |
| nil リテラル | `null` | `nil` |

Java では「すべての参照型が暗黙に `null` 可能」ですが、Swift では **`?` を付けない限り `nil` を代入できません**。これにより、`NullPointerException` 相当のクラッシュをコンパイル時に防げます。

### アンラップ手段の早見表

| 構文 | 用途 | 失敗時の挙動 |
| --- | --- | --- |
| `if let x = opt { ... }` | スコープ内で値を取り出して使う | `else` 節へ (なければスキップ) |
| `guard let x = opt else { return }` | 早期リターン | `else` で関数を抜ける |
| `opt ?? default` | デフォルト値で代替 | デフォルトを返す |
| `opt!` | **強制アンラップ** | **クラッシュ** (`fatalError`) |
| `opt?.foo` | **Optional Chaining** (この章) | **連鎖全体が `nil`** |

最後の **`?.` (Optional Chaining)** が本章の主役です。

---

## 19.2 Optional Chaining の基本

### 構文

Optional な値に対して `?.` を付けると、**「値があれば次の操作を行い、なければ `nil` を返す」** という意味になります。

```swift
class Person {
    var name: String
    var address: Address?
    init(name: String, address: Address? = nil) {
        self.name = name
        self.address = address
    }
}

class Address {
    var city: String
    init(city: String) { self.city = city }
}

let alice: Person? = Person(name: "Alice", address: Address(city: "Tokyo"))
let bob: Person? = Person(name: "Bob")  // address は nil

let city1 = alice?.address?.city  // Optional("Tokyo")
let city2 = bob?.address?.city    // nil
let city3: Person? = nil
let city4 = city3?.address?.city  // nil
```

ポイントは次の 2 点です。

1. **`?.` の左側が `nil` なら、それ以降はすべて評価されず、式全体が `nil` になる**
2. **連鎖の戻り値は常に Optional** — `city` プロパティ自体は `String` (非 Optional) なのに、`alice?.address?.city` の型は `String?` になる

### Java との対比

同じ処理を Java で書くと、ネストした `null` チェックか `Optional.map().orElse()` チェーンになります。

```java
// Java: 古典的な null チェック
String city;
if (alice != null && alice.getAddress() != null) {
    city = alice.getAddress().getCity();
} else {
    city = null;
}

// Java 8+: Optional チェーン
String city = Optional.ofNullable(alice)
    .map(Person::getAddress)
    .map(Address::getCity)
    .orElse(null);
```

```swift
// Swift: Optional Chaining
let city = alice?.address?.city
```

| 観点 | Java `Optional.map()` | Swift `?.` |
| --- | --- | --- |
| 構文の長さ | 数行 | 1 行 |
| 連鎖の打ち切り | `map` が `Optional.empty()` を返した時点で以降スキップ | `nil` に当たった時点で以降スキップ |
| メソッド参照 | `Person::getAddress` のように毎回必要 | 不要 (`?.address` で十分) |
| 副作用呼び出し | `ifPresent(p -> p.doSomething())` | `obj?.doSomething()` (この章 19.3) |
| 代入 | 表現不可 (`Optional` は immutable view) | `obj?.x = 10` (この章 19.5) |

Swift の `?.` は **言語機能としてコンパイラが特別扱い** するため、Java の `Optional` API のようなランタイムオーバーヘッドもありません。

---

## 19.3 メソッド呼び出しのチェーン

`?.` はプロパティアクセスだけでなく、**メソッド呼び出し** にも使えます。

```swift
let trimmed = optionalString?.trimmingCharacters(in: .whitespaces)
// optionalString が nil なら trimmed も nil
// 値があれば trimming した結果の Optional<String>
```

戻り値が `Void` のメソッドでも問題なく使えます。**「対象が存在すれば呼び、なければ何もしない」** という非常に頻出のパターンを 1 行で書けます。

```swift
optionalLogger?.log("started")   // logger があればログ、なければスキップ
```

これが Java では `if (logger != null) logger.log("started");` か `Optional.ofNullable(logger).ifPresent(l -> l.log("started"));` になります。

### Optional な関数値・クロージャの呼び出し

Swift では **関数自体が Optional** になることもあります。例えばコールバック型のプロパティ。

```swift
class HotkeyManager {
    var onZoomHotkey: (() -> Void)?
}
```

`onZoomHotkey` の型は `(() -> Void)?` — 「`Void` を返す引数なし関数の Optional」です。これを呼ぶときは、

```swift
manager.onZoomHotkey?()
```

と書きます。`?` と `()` の組み合わせに見慣れないかもしれませんが、構文の意味を分解すると次のとおりです。

| 部分 | 意味 |
| --- | --- |
| `manager.onZoomHotkey` | クロージャを取り出す (型は `(() -> Void)?`) |
| `?` | `nil` ならここで打ち切り、`nil` を返す |
| `()` | 値があればクロージャを呼び出す |

これも Java の関数型インターフェースで書くと、

```java
Runnable cb = manager.onZoomHotkey;
if (cb != null) cb.run();
```

となります。Swift は **「Optional な関数値の安全な呼び出し」** を 1 行で表現できる設計になっています。これは ZoomacIt の `HotkeyManager` で実際に使われているパターンです (19.10 で読みます)。

---

## 19.4 Subscript のチェーン

Ch15 で学んだ subscript も Optional Chaining と組み合わせられます。`?` の位置に注意してください — **subscript の `[` の前に `?` を置きます**。

```swift
let dict: [String: [String]] = ["fruits": ["apple", "banana"]]
let firstFruit = dict["fruits"]?.first?.uppercased()
// dict["fruits"] が nil なら全体 nil
// dict["fruits"] が [] なら .first が nil → 全体 nil
// それ以外なら "APPLE"
```

Dictionary の subscript はもともと `Optional` を返すので、`dict["fruits"]` の型は `[String]?` です。それに対して `?.first` で連鎖し、さらに `String?` を返す `first` の結果を `?.uppercased()` で連鎖、最終的に `String?` が得られます。

```swift
// 配列要素アクセスとチェーンの組み合わせ
let nestedDict: [String: [Int]]? = ["scores": [10, 20, 30]]
let firstScore = nestedDict?["scores"]?[0]   // Optional(10)
```

`?[0]` のように **subscript の前に `?` を付ける** のがポイントです。`[0]?` ではありません (これは「subscript の戻り値を Optional として扱う」という別の意味になります)。

---

## 19.5 代入のチェーン

Optional Chaining の最も Swift らしい使い方の一つが、**代入** です。

```swift
class Container {
    var value: Int = 0
}

var c: Container? = Container()
c?.value = 10   // c が値を持っていれば .value に 10 を代入
c = nil
c?.value = 20   // c は nil なので、何も起きない (クラッシュしない)
```

`c?.value = 20` は次のセマンティクスを持ちます。

1. `c` が `nil` なら、右辺は **評価されず**、代入も行われない
2. `c` が値を持つなら、`c.value = 20` を実行する

これは Java で書くと、

```java
if (c != null) {
    c.value = 20;
}
```

の 1 行版です。さらに、**代入式全体の型は `Void?`** になります。`Void?` は `nil` か `()` のいずれかで、「代入が成功したかどうか」を判定するのに使えます。

```swift
if (c?.value = 20) != nil {
    // 代入が成功した (c が nil ではなかった)
}
```

実用ではここまで判定することは稀で、純粋に「あれば代入、なければスキップ」という副作用として使われることがほとんどです。ZoomacIt の `AppDelegate` でも `self?.zoomController = nil` のように頻繁に登場します (19.10 で確認します)。

---

## 19.6 `if let` / `guard let` との比較

Optional の扱いには大きく **2 系統の戦略** があります。

| 戦略 | 構文 | 用途 |
| --- | --- | --- |
| **値を取り出して使う** | `if let` / `guard let` | 取り出した値を複数行にわたって使いたい、複数の値を組み合わせたい |
| **連鎖して伝播させる** | `?.` (Optional Chaining) | 単一の式として nil 安全に処理を続けたい、副作用だけ起こしたい |

例えば、ユーザー名を取得して大文字化する処理を 2 通りで書くと、

```swift
// パターン A: Optional Chaining
let upper = user?.name.uppercased()  // String?

// パターン B: if let
if let user {
    let upper = user.name.uppercased()
    print(upper)
}
```

**A は値を変数として保持したい場合**、**B は値を使って何かしたい場合** に向きます。

### 使い分けの判断基準

- **1 行で完結する処理 → `?.`**
- **取り出した値を複数箇所で使う → `if let` / `guard let`**
- **`nil` だったら早期リターンしたい → `guard let`**
- **`nil` でもクラッシュさせず、ただ何もしないでほしい → `?.`**

Optional Chaining は **副作用なし** (= 失敗しても無言でスキップ) という性質があるため、ロギングやエラー処理を挟みたいときは `if let` / `guard let` のほうが適切です。

---

## 19.7 失敗を伝播する関数 (`func foo() -> String?`) への適用

Swift では **戻り値が Optional の関数** が普通に書けます。これは「処理が失敗したら `nil`、成功したら値」というシンプルな失敗表現です (詳細なエラー情報が必要なら Ch20 の `throws` を使います)。

```swift
struct UserRepository {
    func find(id: Int) -> User? {
        // ID に該当するユーザーがいなければ nil
    }
}

struct User {
    var name: String
    func displayName() -> String { name.capitalized }
}
```

このような関数の戻り値に対しても、Optional Chaining を続けて適用できます。

```swift
let repo = UserRepository()
let display = repo.find(id: 1)?.displayName()
// find が nil を返したら display も nil
// User が返ったら displayName() を呼んで Optional<String>
```

複数の Optional 関数をチェーンすることも可能です。

```swift
let upper = repo.find(id: 1)?.bestFriend?.displayName().uppercased()
```

この式は次の経路で評価されます。

1. `find(id: 1)` が `User?` を返す
2. `?.bestFriend` で `User?` のプロパティ `bestFriend: User?` にアクセス (連鎖が `nil` でも先に進める)
3. `?.displayName()` で `String` を返す
4. **`.uppercased()`** — ここは `?.` ではないことに注意

ポイント: **連鎖の途中で値が確定して非 Optional になったら、それ以降は通常の `.` で繋げる** ことができます。`displayName()` が `String` (非 Optional) を返すので、その後の `.uppercased()` には `?` は不要です。ただし式全体の型は依然として `String?` です — 連鎖の途中で一度でも `?.` を使えば、最終結果は必ず Optional になります。

---

## 19.8 強制アンラップ `!` の危険性 (再確認)

Ch04 で触れたとおり、強制アンラップ `!` は **Optional から無理やり値を取り出す** 構文です。

```swift
let name: String? = nil
let n = name!   // 実行時クラッシュ: Fatal error: Unexpectedly found nil
```

Optional Chaining を学んだ今、強制アンラップの危険性が改めて見えてきます。

| 状況 | 推奨 | 非推奨 |
| --- | --- | --- |
| 値がないかもしれない | `?.` または `if let` | `!` |
| 値がないと続行不可能 | `guard let ... else { ... }` | `!` |
| デフォルトで埋めたい | `??` | `!` |
| **本当に絶対 nil でないと言える** | `!` (やむを得ない場合のみ) | — |

「本当に絶対 nil でない」と言えるのは、例えば次のようなごく限られたケースです。

- **直前で `nil` チェック済み** で、コンパイラがそれを追跡しきれない場合 (`if let` で済むことがほとんど)
- **`@IBOutlet`** など、フレームワーク側で初期化を保証している参照
- **リテラルから生成した URL/正規表現** のような、絶対に失敗しない初期化

それ以外で `!` を見たら、**ほぼコードレビューで指摘対象** と思ってよいでしょう。Optional Chaining と `if let` / `guard let` でほぼすべてのケースが書けます。

---

## 19.9 まとめ表 — Optional の扱い完全版

| やりたいこと | 書き方 | 例 |
| --- | --- | --- |
| プロパティアクセス | `obj?.prop` | `user?.name` |
| メソッド呼び出し | `obj?.method()` | `logger?.log("hi")` |
| Optional 関数の呼び出し | `obj.fn?()` または `obj?.fn?()` | `onZoom?()` |
| subscript | `obj?[key]` | `dict?["x"]` |
| 代入 | `obj?.prop = value` | `self?.controller = nil` |
| デフォルト値 | `opt ?? default` | `name ?? "Anon"` |
| 取り出して使う (1 ブロック) | `if let x = opt { ... }` | `if let user { print(user.name) }` |
| 取り出して使う (早期リターン) | `guard let x = opt else { return }` | `guard let user else { return }` |
| **絶対 nil でないと言い切る** | `opt!` (要注意) | `URL(string: "https://...")!` |

---

## 19.10 ZoomacIt の実コード読解

ここまでの構文がどう実プロジェクトで使われているか、ZoomacIt のソースから読んでみます。

### 例 1: `[weak self]` クロージャでの `self?.method()`

`AppDelegate` では、`StatusBarController` や `HotkeyManager` のコールバックを設定する際に **`[weak self]` キャプチャ** を使います。これにより `self` の型は `AppDelegate?` (Optional) になり、呼び出し側では必ず `?.` が必要になります。

```swift
statusBarController?.onPreferences = { [weak self] in
    self?.showPreferences()
}
hotkeyManager.onZoomHotkey = { [weak self] in
    self?.toggleStillZoomMode()
}
hotkeyManager.onDrawHotkey = { [weak self] in
    self?.toggleDrawMode()
}
hotkeyManager.onBreakHotkey = { [weak self] in
    self?.toggleBreakTimer()
}
```

> 引用元: src/ZoomacIt/App/AppDelegate.swift:22-33

ここでは 2 種類の Optional Chaining が連続しています。

1. **`statusBarController?.onPreferences = ...`** — 19.5 の **代入のチェーン**。`statusBarController` がまだ初期化されていなければ何もしない (実際にはこの直前で代入されているので必ず非 nil)
2. **`self?.showPreferences()`** — `[weak self]` で取った self は Optional なので、`?.` でメソッド呼び出し。クロージャ実行時にすでに `AppDelegate` が解放されていれば、何もせずスキップする

これは **強い循環参照を避けつつ、ライフサイクル後のクラッシュも防ぐ** Swift の典型的なイディオムです。Java で同じことをしようとすると `WeakReference<AppDelegate>` を使い、毎回 `get()` の結果を `null` チェックする冗長なコードになります。

### 例 2: Optional への代入 (`self?.zoomController = nil`)

`StillZoomWindowController` の `onDismiss` コールバックでも、Optional Chaining 経由の代入が使われています。

```swift
controller.onDismiss = { [weak self] in
    NSLog("[AppDelegate] Zoom onDismiss callback")
    self?.zoomController = nil
}
// ...
controller.onShowFailed = { [weak self] in
    NSLog("[AppDelegate] Zoom show failed (permission denied?)")
    self?.zoomController = nil
}
```

> 引用元: src/ZoomacIt/App/AppDelegate.swift:113-115, 131-133

`self?.zoomController = nil` は次の意味を持ちます。

- `self` (= `AppDelegate?`) が解放済み (`nil`) なら、**右辺の `nil` も評価されず**、何も起こらない
- `self` が生きていれば、`self.zoomController = nil` を実行する

これを Java で書くと、

```java
WeakReference<AppDelegate> weakSelf = ...;
controller.onDismiss = () -> {
    AppDelegate s = weakSelf.get();
    if (s != null) {
        s.zoomController = null;
    }
};
```

となり、ボイラープレートが目立ちます。Swift では `self?.zoomController = nil` の **1 行** で書けます。

### 例 3: Optional クロージャの呼び出し (`onZoomHotkey?()`)

`HotkeyManager` の中核は、Carbon イベントを受け取って **登録されたクロージャを呼び出す** 部分です。クロージャは `var onZoomHotkey: (() -> Void)?` と Optional で宣言されているため、呼ぶ際には必ず `?.` (正確には `?()`) が必要です。

```swift
if hotKeyID.id == zoomHotKeyID {
    DispatchQueue.main.async { [weak self] in
        self?.onZoomHotkey?()
    }
} else if hotKeyID.id == drawHotKeyID {
    DispatchQueue.main.async { [weak self] in
        self?.onDrawHotkey?()
    }
} else if hotKeyID.id == breakHotKeyID {
    DispatchQueue.main.async { [weak self] in
        self?.onBreakHotkey?()
    }
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:169-181

`self?.onZoomHotkey?()` には Optional Chaining が **2 段** 入っています。

| 部分 | 意味 |
| --- | --- |
| `self?` | `[weak self]` で取った Optional な self。解放済みなら以降スキップ |
| `.onZoomHotkey?` | クロージャプロパティ `(() -> Void)?` を取り出し、未登録なら以降スキップ |
| `()` | 取り出したクロージャを呼び出す |

つまりこの 1 行は、**「`AppDelegate` がまだ生きていて、かつコールバックも登録されているなら、それを呼ぶ。さもなければ何もしない」** という処理を完全に表現しています。Java で素朴に書くと、

```java
AppDelegate s = weakSelf.get();
if (s != null) {
    Runnable cb = s.onZoomHotkey;
    if (cb != null) {
        cb.run();
    }
}
```

の **6 行** が、Swift では **1 行** に凝縮されます。Optional Chaining の真価がもっとも際立つ例です。

---

## 19.11 ハンズオン (任意)

以下を REPL (`swift` コマンド) や Xcode Playground で試してみてください。

### 演習 1: チェーンの伝播

```swift
class Node {
    var value: Int
    var next: Node?
    init(_ v: Int, next: Node? = nil) {
        self.value = v
        self.next = next
    }
}

let chain = Node(1, next: Node(2, next: Node(3)))
print(chain.next?.next?.value as Any)        // ?
print(chain.next?.next?.next?.value as Any)  // ?
```

→ 1 つ目は `Optional(3)`、2 つ目は `nil`。連鎖の最後の `next` が `nil` なので全体が `nil` になります。

### 演習 2: Optional クロージャ

```swift
class Button {
    var onClick: (() -> Void)?
}

let b = Button()
b.onClick?()                          // 何も起きない (nil なのでスキップ)
b.onClick = { print("clicked!") }
b.onClick?()                          // "clicked!"
```

### 演習 3: 代入チェーンの戻り値

```swift
var c: Container? = Container()
let result1: Void? = (c?.value = 10)  // 成功 → ()
c = nil
let result2: Void? = (c?.value = 20)  // 失敗 → nil
print(result1 != nil, result2 != nil) // true false
```

代入式全体の型が `Void?` であることを実感できます。

---

## 次に読む章

→ [20. Error Handling](./20-error-handling.md)

Optional Chaining は **「失敗 = `nil`」** という最小限の表現です。次章では **失敗の理由を型で伝える** ための仕組み、`throws` / `try` / `Result` を扱います。Java の checked exception との対比で読むと、Swift のエラー処理設計の意図がよく見えてきます。
