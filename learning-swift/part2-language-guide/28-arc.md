# 28. Automatic Reference Counting

## この章で学ぶこと

Swift のメモリ管理は **ARC (Automatic Reference Counting)** と呼ばれる仕組みに支えられています。Ch10 (Closures) で `[weak self]` を「循環参照を防ぐためのレシピ」として紹介しましたが、本章ではその裏側で何が起きているのか、なぜ `weak` や `unowned` が必要なのかを、Java の GC との対比を交えながら丁寧に解き明かします。

ARC は Swift プログラマが日常的に意識しなくても安全に動作するよう設計されていますが、**循環参照** (retain cycle) というひとつの落とし穴だけは自動では解消できません。クロージャや delegate を扱うコードでメモリリークを起こさないために、ARC の動作モデルと strong / weak / unowned の使い分けを身につけましょう。

本章を読み終えると、Ch10 で「呪文」のように覚えた `[weak self]` が、なぜ ZoomacIt の `AppDelegate` のいたるところに登場するのか、その必然性が見えるようになります。

---

## 28.1 ARC とは何か

**Automatic Reference Counting** は、その名のとおり「参照カウントの自動管理」を行う仕組みです。クラスインスタンスがいくつの場所から参照されているかをコンパイラが追跡し、参照が 1 つでも生きている間はインスタンスをメモリ上に残し、**最後の strong (強) 参照が消えた瞬間にメモリを解放** します。

重要なのは「**コンパイル時に**参照カウントを増減させるコードがコンパイラによって挿入される」という点です。Swift コンパイラはソースを解析し、変数の代入や関数の引数渡し、スコープ離脱など、参照カウントが変化するべき箇所を機械的に発見し、対応する `retain` / `release` 呼び出しを生成します。実行時には、その挿入済みコードがカウンタを単純にインクリメント / デクリメントするだけです。

```swift
class Person {
    let name: String
    init(name: String) {
        self.name = name
        print("\(name) を生成")
    }
    deinit {
        print("\(name) を解放")
    }
}

func demo() {
    let alice = Person(name: "Alice")  // refCount = 1
    let aliceRef = alice               // refCount = 2
    _ = aliceRef
    // demo() を抜けると alice, aliceRef がスコープから外れ refCount = 0 になり deinit が走る
}
```

`deinit` (Ch18 で学んだデイニシャライザ) はインスタンスの参照カウントが 0 になった瞬間に自動で呼び出されます。ARC が「最後の参照が消えた時点」を正確に把握しているからこそ、決定的なタイミングで `deinit` が実行されるわけです。

### ARC が対象とするのは「クラス」だけ

ARC は **参照型 (reference type)** のメモリ管理機構です。クラスインスタンスはヒープ上に確保され、複数の変数から共有されうるため参照カウントが必要になります。

一方、`struct` と `enum` は **値型 (value type)** で、代入や引数渡しのたびに値そのものがコピーされます。値型はスタックまたは外側オブジェクトの一部としてレイアウトされ、ARC のカウンタは存在しません。Ch12 (Structures and Classes) で「迷ったら struct」と推奨したのは、**ARC のオーバーヘッドも循環参照の心配もない**、というメモリ管理上のメリットも背景にあります。

```swift
struct Point { var x: Int; var y: Int }
// Point は値型 — ARC の対象外。コピーで複製され、寿命は所有者と共に終わる。

class Node { var value: Int = 0 }
// Node は参照型 — ARC が参照カウントで寿命を管理する。
```

クロージャは `struct` でも `class` でもありませんが、内部的には参照型として扱われ、ARC の管理下に置かれます。これが Ch10 で見た「クロージャに `self` を入れると強参照が発生する」問題の根源です。

---

## 28.2 Java GC との違い — 決定性と stop-the-world

Java の `Object` は世代別ガベージコレクタ (G1GC, ZGC など) によって管理されます。GC は「いつかどこかで」到達不能なオブジェクトをマーク&スイープし、まとめて回収します。プログラマは `new` するだけでよく、いつ回収が走るかは JVM 任せです。

ARC は、この「いつかどこか」を **コンパイル時に確定する** モデルです。表で違いを整理します。

| 観点 | Java GC | Swift ARC |
|------|---------|-----------|
| 解放タイミング | 不定 (GC スレッドの判断) | **決定的** (最後の strong 参照が外れた瞬間) |
| 検出方式 | 実行時にヒープ全体を走査 (mark & sweep / copying) | コンパイル時に retain/release を挿入 |
| Stop-the-world | あり (世代によっては短い / 長い) | **なし** |
| ヒープ走査コスト | あり (オブジェクト数に依存) | なし (カウンタ加減算のみ) |
| 循環参照 | GC が到達不能性で正しく回収 | **回収できない** (プログラマが weak で切る) |
| Finalize / `deinit` | `finalize()` のタイミング不定 (廃止予定) | `deinit` は解放時に決定的に呼ばれる |

ARC の最大の利点は **決定性** です。`deinit` が走るタイミングが確定しているため、ファイルハンドル・ロック・C 側で確保したリソースなどを `deinit` で安全に閉じられます。Java で `try-with-resources` や `AutoCloseable` が必要なケースの多くを、Swift では「クラスを抱えて `deinit` を書く」だけで解決できます。

一方の欠点は **循環参照を自動では検出できない** ことです。GC は到達不能なオブジェクト群を「島」ごと回収しますが、ARC はカウンタが 0 になるまで待つため、互いに参照し合うクラスは永久に解放されません。これが Ch10 から繰り返し登場する「retain cycle」の問題で、本章の中心テーマです。

> Java から来た方は **「ARC は GC のように勝手に循環を回収してくれない」** ことを最初に強く意識してください。コンパイラは weak / unowned の付け忘れを検知してくれません。

---

## 28.3 strong 参照 — デフォルトの参照種別

通常の変数宣言はすべて **strong (強) 参照** です。`var x: Person = ...` や `let y = somePerson` のように特別な指定なく書くと、その変数は対象インスタンスの参照カウントを +1 します。

```swift
class Person { let name: String; init(_ n: String) { name = n } }

var a: Person? = Person("Alice")  // refCount = 1
var b: Person? = a                // refCount = 2 (strong)
var c: Person? = a                // refCount = 3 (strong)

a = nil  // refCount = 2
b = nil  // refCount = 1
c = nil  // refCount = 0 → 解放
```

クラスのプロパティも同様です。

```swift
class Engine { /* ... */ }
class Car {
    var engine: Engine  // ← strong (デフォルト)
    init(engine: Engine) { self.engine = engine }
}
```

`Car` インスタンスは自身の `engine` プロパティ経由で `Engine` を strong に保持します。`Car` が解放されれば、その時点で `engine` への参照も 1 つ減ります。

ここまでは直感的ですが、**両方向に strong 参照を持たせると寿命が無限になる**、というのが次節のテーマです。

---

## 28.4 循環参照 (retain cycle) という落とし穴

クラス A がクラス B を strong に持ち、クラス B もクラス A を strong に持ったとします。両者の参照カウントは互いに 1 を維持し続け、外部からの参照がすべて消えても **どちらも 0 にならない** ため、永久に解放されません。これが **循環参照 (retain cycle)** で、Swift で起こりうる典型的なメモリリークの形です。

```swift
class Person {
    let name: String
    var apartment: Apartment?   // strong
    init(name: String) { self.name = name }
    deinit { print("\(name) 解放") }
}

class Apartment {
    let unit: String
    var tenant: Person?         // strong
    init(unit: String) { self.unit = unit }
    deinit { print("Apt \(unit) 解放") }
}

do {
    let alice = Person(name: "Alice")
    let apt = Apartment(unit: "4B")
    alice.apartment = apt
    apt.tenant = alice
}
// スコープを抜けても "Alice 解放" / "Apt 4B 解放" は **一度も出力されない**
```

参照関係を図にすると、互いに strong 矢印を出し合った輪が完成します。

```
[ 循環参照: メモリリーク ]

   外部参照消失後
        ↓
  ┌──────────┐  strong  ┌──────────────┐
  │  Person  │─────────▶│  Apartment   │
  │  (ref=1) │          │   (ref=1)    │
  │          │◀─────────│              │
  └──────────┘  strong  └──────────────┘

  どちらも refCount = 1 のまま 0 にならず、永久に生存。
  GC なら到達不能な「島」として回収できるが、ARC は回収不可。
```

Java の GC は外部から到達不能になった瞬間にこの島ごと回収しますが、**ARC はカウンタが 0 になるまで待つだけ** なので、回収は永久に行われません。プログラマ側が「片方を strong ではない参照種別に変える」必要があります。それが次節からの `weak` と `unowned` です。

---

## 28.5 weak 参照 — カウントを増やさず、解放時は自動で nil に

`weak` キーワードを付けて宣言された参照は、**参照カウントを増加させません**。さらに、対象インスタンスが解放されると、Swift ランタイムがその弱参照を **自動的に `nil`** に書き換えます。この「自動 nil 化」のため、`weak` 参照は必ず **Optional** 型にする必要があり、また **`var`** で宣言する必要があります (途中で nil に変わる可能性があるため `let` 不可)。

```swift
class Apartment {
    let unit: String
    weak var tenant: Person?    // ← weak
    init(unit: String) { self.unit = unit }
    deinit { print("Apt \(unit) 解放") }
}
```

これで先ほどの循環は解消されます。

```
[ weak で循環を断つ ]

  ┌──────────┐  strong  ┌──────────────┐
  │  Person  │─────────▶│  Apartment   │
  │          │          │              │
  │          │◀─ ─ ─ ─ ─│ tenant: weak │
  └──────────┘  weak    └──────────────┘
       (no count)

  Person を保持する外部参照が消えると refCount = 0 → 解放。
  Apartment.tenant は自動で nil に書き換わる。
```

`weak` 参照を使うべき典型場面:

- **対象の寿命が自分より短いかもしれない** とき
- **対象が突然解放されても、自分は安全に動作を続けたい** とき
- **delegate パターン** (28.8 で詳述)

ランタイムは `weak` 参照のリスト (side table) を内部で持ち、対象の `deinit` が走るタイミングで全弱参照を一括 nil 化します。これが「自動 nil」の正体で、Java の `WeakReference<T>` がプログラマに `get()` を毎回呼ばせるのとは対照的に、Swift では Optional Chaining (`tenant?.name`) でそのまま安全に書けます。

---

## 28.6 unowned 参照 — カウントを増やさず、Optional ではない

`unowned` (非所有) も参照カウントを増やしません。ただし `weak` と異なり **Optional ではなく**、解放後の自動 nil 化も行われません。**「対象は自分より長く生きる」とプログラマが保証する** ときに使います。

```swift
class Customer {
    let name: String
    var card: CreditCard?           // strong (Customer が CreditCard を所有)
    init(name: String) { self.name = name }
    deinit { print("\(name) 解放") }
}

class CreditCard {
    let number: String
    unowned let customer: Customer  // ← unowned (CreditCard は Customer 無しでは存在しない)
    init(number: String, customer: Customer) {
        self.number = number
        self.customer = customer
    }
    deinit { print("Card \(number) 解放") }
}
```

`CreditCard` は `Customer` がいてはじめて意味を持ち、Customer より長生きすることはありえません。このとき `customer` を `unowned` で宣言すると、循環は発生せず、かつ `customer.name` のように Optional Chaining 無しで直接アクセスできます。

注意点は **解放済みの unowned 参照にアクセスするとクラッシュする** ことです (Swift 標準の "safe unowned" では実行時エラーで停止、`unowned(unsafe)` ではダングリングポインタとなり未定義動作)。Java で言えば「null チェック無しに参照を触る」のと同じ危険性で、寿命の保証が崩れた瞬間に即死します。

> 迷ったら `weak` を選ぶのが鉄則です。`unowned` は性能上のメリット (Optional 展開コストとサイドテーブル管理コストの省略) はありますが、設計ミスがクラッシュとして表面化するため、**寿命関係が型レベルで明白なペアにのみ** 使ってください。

`weak` と `unowned` の比較を表にまとめます。

| 項目 | `weak` | `unowned` |
|------|--------|-----------|
| 参照カウント | 増やさない | 増やさない |
| 対象解放後 | 自動で `nil` に | 解放されるとアクセスでクラッシュ (safe) / 未定義動作 (unsafe) |
| 型 | 必ず Optional (`Person?`) | Optional ではない (`Person`) |
| 宣言キーワード | `var` のみ | `let` / `var` どちらも可 |
| 用途 | 寿命関係が読めない、対象が先に死ぬ可能性あり | 対象が必ず自分より長く生きる |

---

## 28.7 クロージャの capture list — Ch10 の回収

Ch10 で「呪文」として紹介した `[weak self]` の正体を、ARC の観点から完全に明らかにします。

クロージャは **自身が定義されたスコープの変数を捕捉 (capture) する** 性質を持ち、`self` を捕捉するとデフォルトで `self` への strong 参照を 1 持ちます。クロージャ自身もインスタンスとしてヒープに置かれ、誰かのプロパティとして保存されると、そこに strong 参照が集まります。

ここで以下のような構図ができると循環します。

```
[ クロージャによる循環参照 ]

  ┌────────────────┐  stores  ┌──────────────────┐
  │   self (A)     │─────────▶│ closure          │
  │                │  strong  │ (captures self)  │
  │                │◀─────────│                  │
  └────────────────┘  strong  └──────────────────┘
```

`A` が `closure` を保持し、`closure` が `A` を strong に捕捉している ── 28.4 で見た A↔B の循環と同じ形です。これを切るのが **capture list** で、クロージャの `{` 直後に `[weak self]` または `[unowned self]` を書きます。

```swift
let closure = { [weak self] in
    self?.doSomething()  // self は Self? になり、解放済みなら nil
}
```

```swift
let closure = { [unowned self] in
    self.doSomething()   // self は非 Optional、解放済みならクラッシュ
}
```

判断基準は 28.6 までと同じです。**クロージャ実行時に self が生きている保証** が型レベルで読み取れない限り `weak`、保証できる短命なクロージャ (例: `UIView.animate { ... }` のような同期的アニメーションブロック) なら `unowned`、というのが目安です。Apple のドキュメントもこの順序で推奨しています。

ZoomacIt の `AppDelegate` を見てみましょう。

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSLog("[AppDelegate] applicationDidFinishLaunching")

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

> 引用元: src/ZoomacIt/App/AppDelegate.swift:18-35

参照関係を辿ると、なぜ `[weak self]` が必須かが明確になります。

1. `HotkeyManager` は `HotkeyManager.shared` の **シングルトン** で、アプリ起動から終了まで生存する
2. `hotkeyManager.onZoomHotkey` プロパティはクロージャを **strong に保持** する
3. クロージャは内部で `self` (= `AppDelegate`) を呼び出す必要がある
4. もし `[weak self]` を書かなければ、**シングルトン → クロージャ → AppDelegate** という strong の鎖ができ、AppDelegate は永久に解放されない (= シングルトンが死なない以上、AppDelegate も死なない)

`AppDelegate` はアプリ終了とともに解放されるべきオブジェクトです。シングルトンに strong で握られてしまうと、本来の寿命管理が壊れます。`[weak self]` を入れることで `HotkeyManager` から `AppDelegate` への参照を弱参照に変え、寿命の方向を「`AppDelegate` → `HotkeyManager` の片方向のみ」に整えています。

Zoom コントローラのコールバック設定も同じ構図です。

```swift
private func setupZoomCallbacks(_ controller: StillZoomWindowController) {
    controller.onDismiss = { [weak self] in
        NSLog("[AppDelegate] Zoom onDismiss callback")
        self?.zoomController = nil
    }
    controller.onEnterDrawMode = { [weak self] snapshot in
        guard let self else { return }
        // ...
    }
    controller.onShowFailed = { [weak self] in
        NSLog("[AppDelegate] Zoom show failed (permission denied?)")
        self?.zoomController = nil
    }
}
```

> 引用元: src/ZoomacIt/App/AppDelegate.swift:112-135

ここでは `AppDelegate` が `zoomController` を strong に保持しており、`zoomController` がコールバックとして `[weak self]` 付きクロージャを保持しています。`weak` がなければ「AppDelegate → zoomController → クロージャ → AppDelegate」という循環ができ、Zoom モードを終了しても `AppDelegate` も `zoomController` も解放されません。`onDismiss` の中で `self?.zoomController = nil` を実行する必要があるため `self` への参照は必要、しかし循環は避けたい ── まさに `[weak self]` の出番です。

`DrawingCanvasView` でも同じパターンが使われています。

```swift
private func enterTextMode() {
    drawingState.isTextMode = true
    let controller = TextInputController(canvasView: self, drawingState: drawingState)
    controller.onCommit = { [weak self] in
        self?.commitText()
    }
    textInputController = controller
}
```

> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:411-418

`DrawingCanvasView` が `textInputController` を strong に持ち、`textInputController.onCommit` がクロージャを strong に持つ ── ここでも双方向に strong が走ると循環するため、`[weak self]` で断ち切っています。

ZoomacIt が「クロージャに self を入れたら必ず `[weak self]`」を機械的なルールにしている理由は明快です。**判断ミスのコストが大きい (リークは目で見えにくい)** 一方、**`[weak self]` を書きすぎても害が少ない (せいぜい Optional Chaining が増える程度)** からです。Swift プロジェクトの作法として、この防御的スタイルは強く推奨されます。

---

## 28.8 delegate パターンと weak

Apple フレームワーク全体で頻出する **delegate パターン** は、ある object の振る舞いの一部を別の object に委譲するための慣習です。委譲先 (delegate) は protocol を通じて通知を受け取ります。

```swift
protocol TextFieldDelegate: AnyObject {
    func textFieldDidEndEditing(_ field: TextField)
}

class TextField {
    weak var delegate: TextFieldDelegate?    // ← なぜ weak?
    // ...
}
```

`weak` にする理由は、**所有関係の方向** にあります。

- delegate は通常、`TextField` を画面に配置している側 (例: `ViewController`) であり、**`ViewController` が `TextField` を所有する** 関係
- もし `TextField.delegate` が strong なら、「`ViewController` → `TextField` → `delegate (= ViewController)`」という循環が生まれる
- ViewController は画面遷移で破棄されるべきオブジェクトなので、circular reference は致命的

そのため Apple のフレームワーク (UIKit / AppKit / Foundation) はほぼ例外なく `weak var delegate: ...?` の形を取ります。protocol 側に `: AnyObject` (または `: class`) を付けるのは、`weak` がクラス型にしか適用できないため、protocol の準拠を class 限定にする必要があるからです。

ZoomacIt の `TextInputController` でも同じパターンが使われています。

```swift
final class TextInputController: NSObject, NSTextViewDelegate {
    private weak var canvasView: NSView?
    // ...
}
```

> 引用元: src/ZoomacIt/Draw/TextInputController.swift:1-10

`canvasView` は `DrawingCanvasView` のインスタンスで、所有関係としては「`DrawingCanvasView` が `TextInputController` を保持する」方向です (`textInputController = controller` のあのコードです)。逆向きの参照を strong にすると即循環するため、`weak` で逃がしています。NSTextView の `delegate` プロパティも同じ理由で `weak` 宣言です。

「**所有していない参照は weak**」 ── これが delegate パターンの根底にある原則で、ARC の正しい使い方そのものです。

---

## 28.9 strong / weak / unowned 使い分けフロー

最後に、3 種類の参照の選び方をフローチャート形式で整理します。

```
   参照を宣言したい
         │
         ▼
  ┌────────────────────────────────────┐
  │ 自分がそのオブジェクトを「所有」する │
  │ (= 自分が解放されたら相手も解放され │
  │  て構わない関係)                    │
  └────────────────┬───────────────────┘
            yes    │    no
       ┌───────────┴───────────────┐
       ▼                           ▼
   ┌────────┐         ┌────────────────────────┐
   │ strong │         │ 相手の方が必ず長く生きる │
   │ (デフォ) │         │ と型レベルで保証できる   │
   └────────┘         └──────┬─────────────────┘
                       yes   │   no / 不明
                      ┌──────┴──────┐
                      ▼             ▼
                  ┌─────────┐   ┌──────┐
                  │ unowned │   │ weak │
                  └─────────┘   └──────┘
```

判断軸を表にもまとめます。

| 状況 | 選ぶべき参照 | 理由 |
|------|--------------|------|
| プロパティで子オブジェクトを保持 | `strong` | 所有関係。子は親と運命を共にする |
| delegate プロパティ | `weak` | 委譲元と委譲先の循環防止。所有していない |
| クロージャから `self` を呼ぶ (escaping) | `weak` | 寿命の前後関係が読めないので安全側 |
| クロージャから `self` を呼ぶ (短命・自分が確実に生存) | `unowned` | Optional 展開を省ける |
| 親への back-reference (子から親へ) | `weak` | 親と子で相互 strong を避ける |
| 必須の依存 (CreditCard → Customer 型) | `unowned` | 相手不在では存在しえないので保証可能 |
| 観察者 / observer リスト | `weak` (の配列ラッパ) | 観察対象の解放で自動的に弱参照が nil 化 |

迷ったら `weak`、というのが現代 Swift の標準的なスタイルです。`unowned` の性能メリットはほとんどのアプリでは無視できる範囲で、設計ミスがクラッシュとして跳ね返るリスクの方がはるかに大きいためです。

---

## 28.10 ZoomacIt の実コード読解

ARC の知識を元に、ZoomacIt の参照設計をもう一度俯瞰してみましょう。

```
[ ZoomacIt の主要オブジェクト寿命図 ]

   NSApplication (永続)
        │ delegate (strong)
        ▼
  ┌──────────────┐
  │ AppDelegate  │ ←─────────────── (永続。アプリ終了まで生存)
  └──────┬───────┘
         │ strong プロパティ
         ├─▶ statusBarController (StatusBarController)
         ├─▶ overlayController   (OverlayWindowController?)
         ├─▶ zoomController      (StillZoomWindowController?)
         ├─▶ breakTimerController(BreakTimerWindowController?)
         └─▶ settingsWindowController

  HotkeyManager.shared (シングルトン)
         │ onZoomHotkey: { [weak self in AppDelegate] ... }
         │ onDrawHotkey: { [weak self in AppDelegate] ... }
         │ onBreakHotkey: { [weak self in AppDelegate] ... }
         ▼
  クロージャは AppDelegate を weak で参照
  → AppDelegate → HotkeyManager の単方向 strong に整理される
```

`AppDelegate` は子コントローラ群を strong で保持する **所有者** であり、子側からのコールバック (クロージャ) はすべて `[weak self]` で逆向きを断ち切っている、という綺麗なツリー構造になっています。これにより:

- **モード切替**: ⌃2 でドローモードを終了すると `overlayController = nil` で参照カウントが 0 になり、`OverlayWindowController` の `deinit` が即座に走ってリソースが解放される
- **シングルトンとの分離**: `HotkeyManager.shared` がアプリ終了まで生きていても、内部のクロージャは `AppDelegate` を弱参照しているため、`AppDelegate` の寿命はシングルトンに引きずられない
- **コールバックの安全性**: `self?.zoomController = nil` のように、解放後に呼ばれる可能性のあるコールバックでも Optional Chaining で安全に no-op になる

特に注目すべきは、`onEnterDrawMode` で書かれている次の処理です。

```swift
controller.onEnterDrawMode = { [weak self] snapshot in
    guard let self else { return }
    NSLog("[AppDelegate] Zoom -> Draw transition")
    let zoom = self.zoomController
    self.zoomSourceForDrawReturn = zoom?.sourceImage
    let savedPan = zoom?.panCenter
    let savedZoom = zoom?.zoomLevel
    zoom?.dismiss()
    self.zoomPanCenterForDrawReturn = savedPan
    self.zoomLevelForDrawReturn = savedZoom
    self.zoomController = nil
    self.presentDrawMode(backgroundImage: snapshot)
}
```

> 引用元: src/ZoomacIt/App/AppDelegate.swift:117-130

`guard let self else { return }` で `self` を一旦 strong に昇格させ、以降のクロージャ本体内では非 Optional の `self` として扱っています。これは Swift 5.7 以降で導入された省略記法 (`guard let self = self` の `= self` を省ける) で、ZoomacIt のような Swift 6 プロジェクトでは標準的なスタイルです。クロージャ実行中に AppDelegate が消えると以降の処理が破綻するため、開始時点で生存確認 → strong 昇格、という流れになっています。

`weak` 参照の効果と、開始時点での strong 昇格による安全性 ── ARC の機微を上手に使い分けた、教科書的に良い設計です。

---

## 28.11 ハンズオン (任意)

以下を Xcode の Playground または Swift コマンドで試してみてください。

1. `class Person` と `class Apartment` を 28.4 のコードのまま定義し、`do { ... }` ブロックでそれぞれ生成・相互参照させる。`deinit` のログが出ない (= リーク発生) ことを確認する。
2. `Apartment.tenant` の宣言を `weak var tenant: Person?` に変える。再実行して `deinit` ログが出ることを確認する。
3. クロージャ版を作る: `class Counter { var increment: (() -> Void)? = nil; deinit { print("解放") } }` を定義し、`counter.increment = { print(counter.value) }` のように self キャプチャを起こしてリークを再現する。
4. キャプチャを `[weak self]` に書き換えてリークが解消することを確認する。さらに `self?` を `if let self { ... }` で受け直す書き方も試す。
5. `unowned` に書き換えた場合、外部参照を切ったあとにクロージャを呼ぶとどうなるかを試す (クラッシュする)。

ARC の挙動が「コードのどの行でカウンタが動いているか」を意識できるようになると、メモリリークの予測が驚くほど正確になります。

---

## まとめ

- **ARC** はコンパイル時に `retain` / `release` を自動挿入する参照カウント方式。最後の strong 参照が消えた瞬間に解放される。
- **Java GC との違い**: ARC は決定的タイミング・stop-the-world なし・ヒープ走査なし、ただし循環参照の自動回収は **しない**。
- **strong** はデフォルトで参照カウントを +1。**所有者** が持つ。
- **循環参照** はクラス同士が双方向に strong を持つと発生し、ARC では永久に解放されない。
- **`weak`** は参照カウントを増やさず、解放時に自動で nil になる。Optional / `var` 必須。
- **`unowned`** は参照カウントを増やさず、Optional ではない。寿命の保証が崩れるとクラッシュ。
- **クロージャの capture list** (`[weak self]` / `[unowned self]`) でクロージャ→self の strong を切る。迷ったら `weak`。
- **delegate パターン** が `weak var delegate` であるのは、所有関係が逆向きで循環を避けるため。
- struct / enum (値型) は ARC の対象外で、循環参照の問題自体が発生しない。
- ZoomacIt は AppDelegate を頂点とする所有ツリーを構築し、コールバック方向はすべて `[weak self]` で断ち切るスタイルを徹底している。

---

## 次に読む章

→ [29. Memory Safety](./29-memory-safety.md)
