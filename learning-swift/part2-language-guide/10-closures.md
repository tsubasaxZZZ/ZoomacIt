# 10. Closures

## この章で学ぶこと

*Closure* (クロージャ) とは、コードの一部を「値」として持ち回り、後から呼び出せるようにする仕組みです。Java 8 以降のラムダ式に近い概念ですが、Swift のクロージャは独自の進化を遂げており、特に **末尾クロージャ (trailing closure)**、**`@escaping` 属性**、**capture list (キャプチャリスト)** という三つの要素が初学者の壁になります。

この章では次の 6 つを順に学びます。

1. クロージャの基本構文と Java ラムダとの対比
2. 型推論による短縮形 (`$0`, `$1`)
3. 末尾クロージャ — Swift API の「読みやすさ」を生み出す糖衣構文
4. `@escaping` クロージャ — クロージャを保存する場面で必要
5. capture list `[weak self]` — 循環参照を防ぐ Swift 流の作法
6. `autoclosure` — 短く触れる程度

最後に ZoomacIt の `HotkeyManager` と `AppDelegate` を読み解き、なぜ `[weak self]` が必須なのかを理解します。

---

## 10.1 クロージャの基本構文

Swift のクロージャは次の形をとります。

```swift
{ (引数) -> 戻り値 in 本体 }
```

`in` キーワードを境に、左側がシグネチャ (引数と戻り値の型)、右側が処理本体です。Java のラムダ式

```java
// Java
(Integer x, Integer y) -> x + y
```

と比較すると、Swift は次のように書きます。

```swift
let add: (Int, Int) -> Int = { (x: Int, y: Int) -> Int in
    return x + y
}
add(3, 4)   // → 7
```

両者の対比を表にまとめます。

| 項目 | Java ラムダ | Swift クロージャ |
|------|-------------|-----------------|
| 区切り | `->` (引数とボディ) | `in` (シグネチャと本体) |
| シグネチャ位置 | ボディの前 | ボディの内側 (`{` の直後) |
| 戻り値型の表記 | 不可 (型推論のみ) | `-> 戻り値` で明示可能 |
| 関数型 | `Function<T,R>` 等のインタフェース | `(T) -> R` のファーストクラス型 |
| this/self の扱い | 自動キャプチャ | 明示的に `self.` が必要な場合あり |

**シグネチャをボディの内側に書く** という点が、Java から来た学習者がまず違和感を覚える箇所です。Swift では「`{` から `}` がクロージャ全体」という考え方を徹底しているため、引数や戻り値の宣言も `{` の中に収めています。

### 関数型は値である

クロージャは値なので、変数に入れたり、関数の引数に渡したり、関数の戻り値として返したりできます。

```swift
let greet: (String) -> String = { name in
    return "Hello, \(name)"
}

let message = greet("Swift")    // → "Hello, Swift"
```

`(String) -> String` は「`String` を 1 つ受け取り、`String` を返す関数型」です。Java の `Function<String, String>` に対応しますが、Swift では関数型がそのまま型として扱える (ファーストクラス) ため、ジェネリックインタフェースを介する必要がありません。

---

## 10.2 型推論による短縮形

Swift のコンパイラは文脈から型を強く推論できるため、クロージャの記述をどんどん短くできます。標準ライブラリの `sorted(by:)` を例に、段階的に短縮していきましょう。

```swift
let names = ["Alice", "Bob", "Charlie"]

// 1. フル形式
let sorted1 = names.sorted(by: { (a: String, b: String) -> Bool in
    return a < b
})

// 2. 引数型を省略 (sorted(by:) のシグネチャから推論)
let sorted2 = names.sorted(by: { a, b in
    return a < b
})

// 3. 単一式なら return も省略
let sorted3 = names.sorted(by: { a, b in a < b })

// 4. 省略引数 $0, $1 を使う
let sorted4 = names.sorted(by: { $0 < $1 })

// 5. 演算子そのものを関数として渡す (究極形)
let sorted5 = names.sorted(by: <)
```

### `$0`, `$1` の正体

クロージャ内で `$0`, `$1`, `$2` … と書くと、第 1, 第 2, 第 3 引数を順に指す *省略引数 (shorthand argument names)* として扱われます。引数名を宣言する手間が省ける一方で、何を指しているのかが文脈に強く依存するため、**引数が 1 つか 2 つで意味が自明な場合に限定** するのが慣習です。

```swift
// 自明: フィルタリング
[1, 2, 3, 4].filter { $0 > 2 }     // → [3, 4]

// 自明とは言いがたい: 名前を付けたほうが読みやすい
users.map { $0.profile.email.lowercased() }
// ↓ こう書くべき
users.map { user in user.profile.email.lowercased() }
```

### 戻り値型の省略

最後の式が暗黙の戻り値となるルールも併用すると、クロージャは劇的に短くなります。Swift 5.1 以降、関数本体でも単一式なら `return` を省略できますが、クロージャでは以前から有効でした。

---

## 10.3 末尾クロージャ (trailing closure)

ここからが Swift 特有の世界です。**関数の最後の引数がクロージャである場合、その引数を `()` の外側に書ける** という糖衣構文を *末尾クロージャ* と呼びます。

```swift
// 通常の引数として渡す
let result1 = names.sorted(by: { $0 < $1 })

// 末尾クロージャに変形
let result2 = names.sorted { $0 < $1 }
```

クロージャが唯一の引数なら、`()` 自体も省略できます (`sorted()` → `sorted { ... }`)。これにより、Swift API は次のような **DSL (内部ドメイン特化言語) 風の見た目** を獲得しました。

```swift
let evens = (1...10).filter { $0.isMultiple(of: 2) }
                    .map    { $0 * $0 }
```

### multi-trailing closure (複数の末尾クロージャ)

Swift 5.3 で導入された機能で、最後の引数だけでなく、続く複数のクロージャ引数を末尾に並べられます。**1 つ目だけは引数ラベルを省略し、2 つ目以降はラベルを明示** します。

```swift
func animate(
    duration: TimeInterval,
    animations: () -> Void,
    completion: () -> Void
) { /* ... */ }

animate(duration: 0.3) {
    view.alpha = 0           // animations: ラベル省略
} completion: {
    view.removeFromSuperview()  // completion: ラベル必須
}
```

ラベルが必須になるのは、**どのクロージャがどの引数に対応するかをコンパイラと読み手の両方が一意に決める** ためです。Java のラムダ式にはこの構文がなく、Swift の DSL 表現力を支える特徴的な機能となっています。

---

## 10.4 `@escaping` クロージャ

ここが Swift 学習で最初に「どうしてこうなる?」と立ち止まる場所です。

### デフォルトは non-escaping

関数の引数として受け取ったクロージャは、デフォルトでは **その関数のスコープを抜ける前に呼び出されることが保証されている** 前提で扱われます。これを *non-escaping* と呼びます。

```swift
func executeNow(_ action: () -> Void) {
    action()      // 関数の中で同期的に呼ぶ → OK
}
```

non-escaping なクロージャは **プロパティに保存できず、別スレッドにディスパッチもできません**。コンパイラが「この関数を抜けたら使われない」と保証するためです。

### `@escaping` を付けると保存・遅延実行できる

クロージャを後から呼び出したい (プロパティに保存する、非同期処理に渡す) 場合は、`@escaping` を引数の型の前に付ける必要があります。

```swift
final class TaskQueue {
    private var pendingActions: [() -> Void] = []

    // クロージャをプロパティに保存するので @escaping が必須
    func enqueue(_ action: @escaping () -> Void) {
        pendingActions.append(action)
    }

    func runAll() {
        for action in pendingActions { action() }
        pendingActions.removeAll()
    }
}
```

### プロパティ宣言時の暗黙 @escaping

クロージャを **プロパティとして直接宣言する** 場合、そのクロージャは性質上 escape する (オブジェクトより長く生存する可能性がある) ため、`@escaping` は **書かないのが正解** です。むしろ書くと文法エラーになります。

```swift
final class HotkeyManager {
    var onZoomHotkey: (() -> Void)?     // 暗黙的に escape する
}
```

ZoomacIt の `HotkeyManager` がまさにこのパターンです。詳しくは後半の実コード読解で見ます。

### 何が嬉しいのか

`@escaping` を **デフォルトにしない** ことで、Swift は次のメリットを得ています。

- non-escaping のクロージャでは、内部で `self.` を省略できる (循環参照のリスクがないため)
- コンパイラが最適化しやすい (ヒープ割り当てを避けられる場合がある)
- 「このクロージャはあとで保持される」というシグナルが API 利用者に伝わる

---

## 10.5 capture list `[weak self]`

クロージャは、**自身が定義されたスコープにある変数を捕捉 (capture) する** という性質を持ちます。Java ラムダの「実質的に final なローカル変数を参照できる」ルールに似ていますが、Swift はもっと自由で、外側のオブジェクト (`self`) も参照できます。

```swift
final class Counter {
    var count = 0

    func makeIncrementer() -> () -> Int {
        return {
            self.count += 1     // 外側の self を捕捉
            return self.count
        }
    }
}
```

クロージャは `self` への **強参照 (strong reference)** を保持します。Swift は *ARC (Automatic Reference Counting)* によりオブジェクトの寿命を管理しているため、強参照が双方向に発生すると **循環参照 (retain cycle)** が起き、メモリリークの原因になります。

### 図: 循環参照の発生と解消

```
[ 循環参照あり: メモリリーク ]

  AppDelegate ◀──────── strong ────────┐
       │                                │
       │ holds                          │
       ▼                                │
  HotkeyManager.onZoomHotkey            │
       │                                │
       │ closure captures self          │
       └──── strong ────────────────────┘

  → どちらも参照カウント > 0 のまま、永遠に解放されない


[ [weak self] あり: 安全 ]

  AppDelegate ◀──────── strong ────────┐
       │                                │
       │ holds                          │
       ▼                                │
  HotkeyManager.onZoomHotkey            │
       │                                │
       │ closure captures self weakly   │
       └──── weak (no count) ───────────┘

  → AppDelegate が解放されると self は nil になり、循環が断ち切られる
```

### capture list の文法

クロージャの先頭に `[ ... ]` を書き、その中で捕捉の仕方を宣言します。

```swift
hotkeyManager.onZoomHotkey = { [weak self] in
    self?.toggleStillZoomMode()
}
```

`[weak self]` と書くと、クロージャ内の `self` は **`Optional` (`Self?`)** になります。元のオブジェクトが解放されていれば `nil` になるため、`self?.` の Optional Chaining で安全に呼び出します。

### `weak` と `unowned` の違い

|  | `weak` | `unowned` |
|---|--------|-----------|
| 型 | Optional (`Self?`) | 非 Optional (`Self`) |
| 解放後アクセス | `nil` を返す (安全) | クラッシュする (`EXC_BAD_ACCESS`) |
| 想定する関係 | 親が先に死ぬ可能性がある | 親が必ず先に死ぬ / 同時に死ぬ |

迷ったら `weak` を選ぶのが安全策です。`unowned` は Java の生の参照に近く、解放済みオブジェクトへのアクセスが未定義動作になります。**ARC の仕組みと使い分けの詳細は Ch28 (Automatic Reference Counting) で深掘りします** ので、本章では「循環参照を防ぐために `[weak self]` と書く」というレシピを覚えてください。

---

## 10.6 autoclosure

`@autoclosure` 属性を引数に付けると、**呼び出し側の式が自動的にクロージャでくるまれて遅延評価** されます。標準ライブラリの `assert(_:_:)` や `??` 演算子で使われています。

```swift
// 標準ライブラリ風の宣言
func myAssert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("Assertion failed: \(message)")
    }
}

myAssert(x > 0, "x must be positive")
//        ^^^^^
// 呼び出し側は普通の式に見えるが、内部では { x > 0 } として遅延評価される
```

メリットは「`condition` が偽でなければ評価コストを払わない」こと。デメリットは「呼び出し側のコードが副作用を伴う場合に評価タイミングが分かりにくい」ことです。**自分のコードで多用するものではなく、API 設計者が DSL ライクな見た目を作りたいときに使う道具** だと理解しておけば十分です。

---

## 10.7 ZoomacIt 実コード読解

ここまでの知識で、ZoomacIt の中核設計を読み解きましょう。

### クロージャプロパティによるコールバック設計

`HotkeyManager` は Carbon の `RegisterEventHotKey` API でグローバルホットキーを登録するクラスですが、**「キーが押されたら何をするか」は呼び出し元 (AppDelegate) が決める** という設計になっています。これをクロージャプロパティで実現しています。

```swift
// src/ZoomacIt/Core/HotkeyManager.swift:11, 14, 17
final class HotkeyManager: @unchecked Sendable {
    /// Called when the Draw hotkey (⌃2) is triggered.
    var onDrawHotkey: (() -> Void)?

    /// Called when the Still Zoom hotkey (⌃1) is triggered.
    var onZoomHotkey: (() -> Void)?

    /// Called when the Break Timer hotkey (⌃3) is triggered.
    var onBreakHotkey: (() -> Void)?
    // ...
}
```

注目点は次の 3 つです。

- **型は `(() -> Void)?`** — 「引数なし、戻り値なしのクロージャ」を Optional で持つ
- **`@escaping` は書かれていない** — プロパティ宣言時のクロージャ型は暗黙的に escape する扱い
- **登録パターン** — Java の `EventListener` インタフェース実装より圧倒的に短い

### AppDelegate 側の登録: `[weak self]` の出番

`AppDelegate` はアプリ起動時に、上記コールバックに自分のメソッドを差し込みます。

```swift
// src/ZoomacIt/App/AppDelegate.swift:22-33
func applicationDidFinishLaunching(_ notification: Notification) {
    statusBarController = StatusBarController()
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
    hotkeyManager.start()
}
```

ここで **なぜ `[weak self]` を書かなければならないか** を、参照関係を辿って確認します。

1. `AppDelegate` は `HotkeyManager.shared` を `hotkeyManager` プロパティ経由で参照する (シングルトンなので強参照)
2. `AppDelegate` が `hotkeyManager.onZoomHotkey = { ... }` でクロージャを代入する
3. そのクロージャが `self.toggleStillZoomMode()` を呼ぶため、**クロージャは `self` (= AppDelegate) を捕捉** する
4. `HotkeyManager.shared` はアプリ生存中ずっと存在するシングルトン
5. もし `[weak self]` を書かなかったら、**シングルトン → クロージャ → AppDelegate** という強参照の鎖ができ、AppDelegate は永久に解放されない

`AppDelegate` は通常アプリと寿命を共にするので「解放されなくても困らない」と思うかもしれません。しかし、

- ユニットテスト時には複数回生成・破棄される可能性がある
- 将来 `HotkeyManager` を `AppDelegate` 以外でも使うリファクタリングをしたとき安全
- **「クロージャに self を入れたら `[weak self]` を書く」を機械的なルールにしておくほうが事故が起きない**

という理由で、ZoomacIt では一貫して `[weak self]` を書いています。

### ZoomController のコールバック群でも同じパターン

Zoom 関連のコールバックも同じ作法で書かれています。

```swift
// src/ZoomacIt/App/AppDelegate.swift:113, 117, 131
private func setupZoomCallbacks(_ controller: StillZoomWindowController) {
    controller.onDismiss = { [weak self] in
        NSLog("[AppDelegate] Zoom onDismiss callback")
        self?.zoomController = nil
    }
    controller.onEnterDrawMode = { [weak self] snapshot in
        guard let self else { return }
        // ... 複数行の処理 ...
        self.presentDrawMode(backgroundImage: snapshot)
    }
    controller.onShowFailed = { [weak self] in
        self?.zoomController = nil
    }
}
```

注目してほしいのは `onEnterDrawMode` の `guard let self else { return }` です。クロージャ内で `self` を何度も使う場合、毎回 `self?.` と書くのは煩雑なので、**先頭で `guard let self` により `self` を一時的に non-Optional に昇格** させるテクニックがよく使われます (Swift 5.7 以降は `guard let self else` と簡潔に書けます)。

### HotkeyManager 内部の `[weak self]`

クロージャを保持する側 (`HotkeyManager`) でも、自分自身を捕捉する場面では `[weak self]` を使っています。

```swift
// src/ZoomacIt/Core/HotkeyManager.swift:170-181
if hotKeyID.id == zoomHotKeyID {
    DispatchQueue.main.async { [weak self] in
        self?.onZoomHotkey?()
    }
}
```

ここでクロージャを捕捉するのは `DispatchQueue.main` (グローバルなディスパッチキュー) です。シングルトンが対象なので解放されることは事実上ないものの、**「self を捕捉するなら weak」** というルールを徹底することでコードレビュー時の判断負荷を下げています。

---

## 10.8 ハンズオン (任意)

実際に手を動かして理解を深めたい場合、次の課題に挑戦してみてください。

1. **末尾クロージャの書き換え** — `[1, 2, 3, 4, 5].reduce(0, { $0 + $1 })` を末尾クロージャ + 演算子参照で書き直す (`reduce(0, +)` まで縮められます)
2. **コールバックパターン** — 簡単な `Timer` ラッパークラスを書き、`onTick: (() -> Void)?` プロパティを持たせる。利用側で `[weak self]` を付けてコールバックを設定する
3. **循環参照の体感** — 上の課題で `[weak self]` を **わざと外し**、`deinit` にログを仕込んで「解放されない」ことを確認する

---

## 10.9 この章のまとめ

| 概念 | 一言まとめ |
|------|-----------|
| 基本構文 | `{ (引数) -> 戻り値 in 本体 }` — シグネチャは `{` の内側 |
| 短縮形 | 型推論と `$0`, `$1` でどこまでも短くできる |
| 末尾クロージャ | 最後のクロージャ引数を `()` の外に出せる Swift の特権 |
| `@escaping` | 関数を抜けた後に呼ばれるクロージャに必要。プロパティでは暗黙 |
| `[weak self]` | 循環参照を防ぐ Swift 流の作法。詳細な ARC は Ch28 |
| `@autoclosure` | 式を遅延評価したい API 設計者向けの道具 |

クロージャは Swift API の **読みやすさと表現力の源泉** です。`[weak self]` を書く習慣だけは早めに身につけ、メモリ管理の詳細は Ch28 で改めて深掘りしましょう。

## 次に読む章

→ [11. Enumerations](./11-enumerations.md)
