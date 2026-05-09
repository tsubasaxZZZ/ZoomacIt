# 16. Inheritance

## この章で学ぶこと

- クラス継承の基本構文 `class Sub: Super { ... }` を Java の `extends` と対比して整理する
- **`override` キーワードが必須** — Java の `@Override` (任意) との対照を理解する
- **`final`** によるサブクラス化 / オーバーライドの禁止と、ZoomacIt が積極的に採用している設計判断
- Swift には **暗黙のスーパークラスがない** こと (Java の `Object` 相当が無い)
- **計算プロパティ (computed property) も override 可能** であること
- ZoomacIt の `DrawingCanvasView`(NSView 継承) と `AppDelegate`(NSObject 継承) の実コードで NSView の override 群を読み解く

> **NOTE**
> この章は **チートシート + 言語固有解説のハイブリッド章** です。「サブクラスは親のメソッドを上書きする」という概念は Java と同じですが、`override` 必須・`final` の存在感・継承可能なのは class のみという 3 点が Swift 特有です。
>
> なお Swift では struct / enum は **継承できません**。値型に多態性を持たせたい場合は **protocol** を使います。詳細は Ch25 (Protocols) で扱います。

---

## 16.1 ひとことで

| 観点 | Java | Swift |
| --- | --- | --- |
| 継承の宣言 | `class Sub extends Super` | `class Sub: Super` |
| 多重継承 | 不可 (interface のみ複数実装可) | 不可 (protocol のみ複数準拠可) |
| オーバーライド | `@Override` は **任意** (推奨) | `override` キーワードは **必須** (言語仕様) |
| 継承禁止 | `final class` / `final method` | `final class` / `final func` |
| 暗黙のスーパークラス | `java.lang.Object` (universal base) | **なし** |
| 継承できる型 | class のみ | **class のみ** (struct / enum は不可) |
| 計算プロパティの override | (フィールドは override 不可、メソッドのみ) | **計算プロパティも override 可能** |

文法だけ見れば Java と非常に近いですが、**「書かないとコンパイラに怒られる」「書きすぎてもコンパイラに怒られる」** という双方向の厳格さが Swift の継承の特徴です。

---

## 16.2 継承の基本

### 宣言構文

スーパークラスの指定は **コロン** で行います。Java の `extends` キーワードは存在しません。

```swift
class Vehicle {
    var speed: Double = 0.0

    func describe() -> String {
        "Moving at \(speed) km/h"
    }
}

class Car: Vehicle {
    var numberOfWheels: Int = 4
}

let car = Car()
car.speed = 60.0
print(car.describe())   // "Moving at 60.0 km/h"
```

`Car` は `Vehicle` のプロパティ `speed` とメソッド `describe()` をそのまま受け継ぎます。Java の `extends Vehicle` と意味は同一です。

### 用語 (Swift 公式の呼び方)

| Swift | Java | 意味 |
| --- | --- | --- |
| superclass / base class | superclass | 親クラス |
| subclass | subclass | 子クラス |
| override | override | 親の実装を上書きすること |
| final class | final class | サブクラス化を禁止 |

呼称はほぼ同じで戸惑うことはありません。

### 多重継承は不可 (Java と同じ)

Swift も Java と同様、**クラスは 1 つしか継承できません**。複数の振る舞いを混ぜたいときは **protocol** を複数準拠することで対応します (Java の interface 多重実装に相当)。

```swift
class StatusBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    // NSObject を継承しつつ、複数の protocol に準拠
}
```

`NSObject` がスーパークラス、`NSMenuDelegate` と `NSWindowDelegate` は protocol 準拠です。**コロン以降の最初の型がスーパークラス、残りは protocol** というのが Swift の慣例です。順序は強制ではありませんが、可読性のため必ずこの順で書きます。

---

## 16.3 `override` キーワードは必須

Swift では、親クラスのメソッド・プロパティ・subscript を上書きするとき **必ず `override` キーワードを書かなければなりません**。これは推奨ではなく **言語仕様による強制** です。

### Java との対照

```java
// Java — @Override は付けなくても動く (推奨されているだけ)
class Animal {
    void speak() { System.out.println("..."); }
}
class Dog extends Animal {
    @Override                       // 任意 (付けると安全)
    void speak() { System.out.println("Woof"); }
}
```

```swift
// Swift — override は必須
class Animal {
    func speak() { print("...") }
}
class Dog: Animal {
    override func speak() {         // 必須 (省くとコンパイルエラー)
        print("Woof")
    }
}
```

### `override` を書き忘れたら

コンパイルエラーになります。

```
error: overriding declaration requires an 'override' keyword
```

### `override` を書きすぎたら

これも同様にエラーです。**親に存在しないメソッドに `override` を付けることもできません**。

```swift
class Cat: Animal {
    override func purr() { ... }   // ❌ Animal に purr() は無い
}
```

```
error: method does not override any method from its superclass
```

### なぜこの仕様か

Java の `@Override` は **付け忘れても動く** ため、親クラスのシグネチャ変更時に「オーバーライドのつもりが、別物の新メソッドになっていた」という事故が起こり得ます。Swift は両方向に強制することで、

- 上書きする意図を **明示的にコードへ刻む** (レビュー時に見落とさない)
- 親メソッドのシグネチャが変更されたら **即座にコンパイルが失敗する** (リネーム時に検知される)

という安全性を得ています。Java で `@Override` を必ず書くベストプラクティスを、言語側に組み込んだ形です。

### `super` の呼び出し

オーバーライドした上で親の実装も呼びたい場合は `super.メソッド名()` を使います。これは Java と完全に同じです。

```swift
class Dog: Animal {
    override func speak() {
        super.speak()       // 親の "..." も実行
        print("Woof")
    }
}
```

NSView などフレームワークのクラスを継承する際は、**多くの override で先頭または末尾に `super` 呼び出しが必須** になります (フレームワーク内部の状態管理がそこで走るため)。今回読む `DrawingCanvasView` ではフレームワークの状態に依存しない描画 / イベント処理がほとんどなので `super` を呼んでいませんが、`viewDidMoveToWindow()` など状態系を override する場合は `super` 呼び出しを忘れないようにしてください。

---

## 16.4 `final` — サブクラス化 / オーバーライドの禁止

`final` 修飾子は「これ以上拡張させない」ことを宣言します。Java の `final class` / `final method` と意味的に同じですが、**Swift では `final` をデフォルトで積極的に使う文化** があります。

### `final class` — クラス全体を継承不可に

```swift
final class DrawingCanvasView: NSView {
    // このクラスはもう誰にも継承されない
}
```

`DrawingCanvasView` を継承しようとすると、

```
error: inheritance from a final class 'DrawingCanvasView'
```

とコンパイルエラーになります。

### `final func` — メソッド単位でオーバーライドを禁止

クラス全体は継承可能なまま、特定のメソッドだけオーバーライドを禁じることもできます。

```swift
class Base {
    final func criticalLogic() { ... }   // サブクラスで上書き不可
    func customizable() { ... }          // サブクラスで上書き可
}
```

`final` は `var` (格納プロパティ) や計算プロパティにも付けられます。

### なぜ Swift では `final` を積極採用するのか

理由は 2 つあります。

1. **設計の明確化**
   「このクラスは継承される前提か、そうでないか」をコードに明示することで、将来の拡張時に意図せぬサブクラス化が起きるのを防ぎます。Java の世界では「継承を前提としないクラスは `final` にせよ」 (Effective Java 第 19 項) というベストプラクティスがありますが、Swift コミュニティはこれをより厳密に実践する傾向があります。

2. **最適化 — 静的ディスパッチ**
   通常のクラスメソッド呼び出しは **動的ディスパッチ** (vtable 経由) ですが、`final` を付けたメソッド / クラスは **静的ディスパッチ** (直接呼び出し) に最適化できます。コンパイラが「サブクラスで上書きされる可能性は無い」と確信できるためです。
   ホットパスで頻繁に呼ばれるメソッドでは、これがパフォーマンスに効きます。Swift コンパイラは Whole Module Optimization 時に sealed なクラスは自動で final 扱いしますが、**明示的に `final` を書くことで最適化を確実に発動させられる** のです。

### ZoomacIt の方針

ZoomacIt のコードでは、自分で定義するクラスはほぼすべて `final class` になっています。今回読む 2 つのクラスもどちらも final です。

```swift
final class DrawingCanvasView: NSView { ... }
final class AppDelegate: NSObject, NSApplicationDelegate { ... }
```

これは「**継承は使わず、必要な拡張は composition (合成) で行う**」という設計判断の表れです。Swift では struct + protocol で抽象化するのが標準的な手法であり、クラスを継承させる場面はフレームワーク側 (NSView, NSObject) との接続点だけに留める、という思想です。

---

## 16.5 暗黙のスーパークラスは無い

Java では、明示的に `extends` を書かないクラスは自動的に `java.lang.Object` を継承します。`equals()` / `hashCode()` / `toString()` などはすべての参照型で使えます。

Swift には **このような universal base class はありません**。

```swift
class Foo {
    // 何も継承していない (= ルートクラス)
}
```

`Foo` には `description` も `hash` も自動では生えません。`==` も `Equatable` に準拠しなければ使えません。

### NSObject はあくまで AppKit/UIKit との接続用

Cocoa / AppKit / UIKit と協調するクラスでは、Objective-C 互換の基底クラスとして `NSObject` を継承します。これは「Object 相当」なのではなく、**KVO (Key-Value Observing)、target-action、NSNotification、selector ベースの API などで Objective-C ランタイムが必要だから** という具体的な理由による継承です。

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    // NSApplicationDelegate プロトコルの一部メソッドが
    // selector ベースで呼ばれるため、NSObject 継承が必要
}
```

純粋な Swift コードでは、**NSObject を継承する必要はありません**。「とりあえず親クラスを書く」という Java 的な発想を Swift に持ち込むのは避け、必要が生じたときだけ NSObject や AppKit のクラスを継承する、というスタンスが推奨されます。

---

## 16.6 計算プロパティのオーバーライド

Java では `private final int field` のような **インスタンスフィールドは override できません** (隠蔽 (shadowing) になるだけ)。Swift では計算プロパティであれば override 可能です。**格納プロパティ (stored property) は override できません** が、**計算プロパティ (computed property) はメソッドと同じ感覚で override できる** 点が便利です。

```swift
class Vehicle {
    var description: String {
        "A vehicle with speed \(speed)"
    }
    var speed: Double = 0.0
}

class Car: Vehicle {
    override var description: String {
        super.description + " (Car)"
    }
}
```

### getter のみのプロパティを setter 付きに上書きできる

親では read-only (getter のみ) でも、サブクラスで read-write (getter + setter) に「拡張」する形で override できます。逆方向 (read-write → read-only) はできません。

```swift
class Base {
    var value: Int { 42 }   // get only
}

class Sub: Base {
    private var stored: Int = 0
    override var value: Int {
        get { stored == 0 ? 42 : stored }
        set { stored = newValue }     // setter を追加
    }
}
```

NSView の `acceptsFirstResponder` プロパティ (read-only) を `DrawingCanvasView` が override しているのが、まさにこのパターンの実例です (後述)。

### プロパティオブザーバの追加

`willSet` / `didSet` も override で追加できます。継承元が計算プロパティの場合は付けられないなどの制約はありますが、「親で定義された格納プロパティに、子で監視を仕掛ける」用途で有用です。

```swift
class Counter {
    var count: Int = 0
}

class LoggingCounter: Counter {
    override var count: Int {
        didSet { print("count changed to \(count)") }
    }
}
```

---

## 16.7 オーバーライド禁止の方法

オーバーライドを **禁じる** ための手段は次の 2 つです。

### メソッド単位

```swift
class Base {
    final func criticalLogic() { ... }
}
```

サブクラス側で `override func criticalLogic()` と書くと、

```
error: instance method overrides a 'final' instance method
```

になります。

### クラス単位

```swift
final class Base {
    func anything() { ... }
}
```

クラス全体が `final` であれば、サブクラスを作ること自体が禁止されるため、当然オーバーライドもできません。

### どちらを選ぶか

- **クラスごと拡張不可で良い** (= ZoomacIt の方針) → `final class` でクラス丸ごと封印
- **継承は許すが、特定メソッドだけは固定したい** → `final func` でメソッド単位

通常は `final class` の方がシンプルで、必要になってから `final` を外す方が安全です。これは「クラスは初期値で final、必要が生じたら開放する」という Swift コミュニティの一般的な指針 (Sealed by default) でもあります。

---

## 16.8 ZoomacIt 実コード読解 — `DrawingCanvasView`

ここまでの内容を、ZoomacIt の `DrawingCanvasView` で総ざらいします。このクラスは描画モードのキャンバスを実現する `NSView` のサブクラスで、**override の使い方の見本市** のような存在です。

### 宣言部 (`src/ZoomacIt/Draw/DrawingCanvasView.swift:12`)

```swift
/// The main NSView subclass that implements the 3-layer compositing architecture
/// for Draw mode rendering.
final class DrawingCanvasView: NSView {
    // ...
}
```

3 つの観察点があります。

1. **`final class`** — このクラスはサブクラス化されない。ZoomacIt が自前のクラスをほぼすべて `final` にしているのは前述のとおり。
2. **`: NSView`** — AppKit のビュークラスを継承。これにより、画面に描画する能力 (`draw(_:)`)、マウス・キーボードイベントの受信、ウィンドウ階層への組み込みなどが手に入る。
3. **コロン記法** — Java の `extends NSView` ではなく、コロン 1 つで継承を表現。

### override 群の俯瞰

`DrawingCanvasView` は NSView の以下のメソッド / プロパティを override しています。

| 行 | override 対象 | 役割 |
| --- | --- | --- |
| 65 | `resetCursorRects()` | カーソルを十字 (crosshair) に変更 |
| 71 | `draw(_ dirtyRect: NSRect)` | 3 層 (background / finished / preview / freehand) を描画 |
| 133 | `mouseDown(with: NSEvent)` | ドラッグ開始位置を記録、フリーハンドパスを初期化 |
| 151 | `mouseDragged(with: NSEvent)` | 修飾キーで形状を判定し、preview / freehand を更新 |
| 185 | `mouseUp(with: NSEvent)` | ストロークを finishedLayer にラスタライズ、Undo 記録 |
| 210 | `rightMouseDown(with: NSEvent)` | 右クリックで描画モードを抜ける |
| 221 | `acceptsFirstResponder` (computed property) | キー入力を受けるため `true` を返す |
| 223 | `keyDown(with: NSEvent)` | 色キー (R/G/B…)、Escape、Undo (⌘Z)、Save (⌘S) などを処理 |
| 305 | `keyUp(with: NSEvent)` | Tab キーの押下解除を検知 |
| 312 | `flagsChanged(with: NSEvent)` | ドラッグ中の修飾キー変化で形状種別を更新 |
| 323 | `scrollWheel(with: NSEvent)` | ⌃+スクロールでペン幅を変更 |

ここで起きていることを言葉にすると、

- **`draw(_:)` を override しているから、画面に何か描ける**。NSView は「自身を描くタイミング」を `draw(_:)` の呼び出しで子クラスに委譲している。子は `super.draw(_:)` を呼ばずに、自分の好きな描画を行う。
- **`mouseDown` / `mouseDragged` / `mouseUp` / `rightMouseDown` を override しているから、マウス入力を扱える**。NSView のデフォルト実装は何もしない (もしくはイベントを次のレスポンダへパス) ので、子で受けて初めて意味のある動作になる。
- **`keyDown` / `keyUp` / `flagsChanged` を override しているから、キーボードを扱える**。ただしキーボードイベントを受けるには、後述の `acceptsFirstResponder` を `true` にする必要がある。

これがまさに「**継承 = 親フレームワークが用意した拡張点 (extension point) を埋めること**」のパターンです。NSView は「描画したいなら `draw(_:)` を override せよ」「マウスを扱いたいなら `mouseDown` を override せよ」というプロトコル (ここでは口語的な意味) を提供しており、サブクラスはそれに応えます。

### 各 override の中身を少し細かく

#### `draw(_:)` (`:71`)

```swift
override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    // 1. Draw background (captured screen or whiteboard/blackboard)
    drawBackground(in: context)

    // 2. Draw finishedLayer (all confirmed strokes)
    if let finished = finishedLayer {
        context.draw(finished, in: bounds)
    }

    // 3. Draw previewLayer (shape being dragged)
    if let preview = previewLayer { /* ... */ }

    // 4. Draw activeFreehand (freehand path being drawn)
    if let freehand = activeFreehand { /* ... */ }
}
```

NSView は描画が必要なタイミングで `draw(_:)` を呼びます。`super.draw(_:)` を呼んでいないのは、**NSView のデフォルト描画 (= 透明) を完全に置き換えたい** からです。フレームワーク側の状態管理に依存する override では `super` 呼び出しが必須ですが、`draw(_:)` のように「描く内容そのものを差し替える」用途では呼ばないのが普通です。

#### `mouseDown(with:)` (`:133`)

```swift
override func mouseDown(with event: NSEvent) {
    if drawingState.isTextMode {
        handleTextModeClick(event)
        return
    }

    let point = convert(event.locationInWindow, from: nil)
    dragOrigin = point
    freehandPoints = [point]
    isDragging = true

    activeFreehand = NSBezierPath()
    activeFreehand?.move(to: point)
    previewLayer = nil
}
```

NSView のデフォルトの `mouseDown(with:)` は (粗く言えば) 「次のレスポンダへイベントを渡す」だけです。`override` してドラッグ開始の状態を記録することで、初めて「マウスを押し下げたらストロークが始まる」という挙動になります。

#### `acceptsFirstResponder` (`:221`)

```swift
override var acceptsFirstResponder: Bool { true }
```

これが **計算プロパティの override** の実例です。NSView の親クラスである NSResponder は `acceptsFirstResponder` を `false` で返します。`DrawingCanvasView` では `true` に上書きすることで、ウィンドウのファーストレスポンダになる資格を持ち、キーイベント (`keyDown` / `keyUp`) を受け取れるようになります。

「メソッドではなくプロパティを override している」点に注目してください。Java では `getAcceptsFirstResponder()` のようなゲッターメソッドを上書きする形になりますが、Swift では `var プロパティ名: 型 { ... }` という構文で、より自然に書けます。

#### `flagsChanged(with:)` (`:312`)

```swift
override func flagsChanged(with event: NSEvent) {
    // Modifier changes during drag cause shape type to update.
    if isDragging {
        mouseDragged(with: event)
    }
}
```

修飾キー (Shift / Control など) の変化を捕まえる NSResponder のフックです。これを override しているおかげで、「ドラッグ中に Shift を押したら直線、離したら自由曲線」のようなライブな形状切り替えが実現できています。

### `init` と `required init?`

少し脇道ですが、初期化部分にも継承固有の話題があります。

```swift
init(frame: NSRect, backgroundImage: CGImage?) {
    self.backgroundImage = backgroundImage
    super.init(frame: frame)
    wantsLayer = false
}

@available(*, unavailable)
required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
}
```

`super.init(frame:)` を呼んでいるのは、親クラスの初期化を完了させる必須の手順です。`required init?(coder:)` は NSCoding プロトコル経由で呼ばれる初期化子で、サブクラスでも実装が義務付けられている (= `required`) ため、ここでは「使わない」ことを `@available(*, unavailable)` と `fatalError` で宣言しています。

イニシャライザの継承ルールは独特なので、Ch17 (Initialization) で改めて扱います。

---

## 16.9 ZoomacIt 実コード読解 — `AppDelegate` と NSObject 継承

もう 1 つ、`src/ZoomacIt/App/AppDelegate.swift:4` を読みます。

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // ...
}
```

ここで観察すべきは次の点です。

1. **`NSObject` の継承**
   AppKit に `NSApplicationDelegate` として登録されるクラスは、Objective-C ランタイム経由で呼ばれる必要があるため NSObject を継承します。「アプリのライフサイクルメソッド (`applicationDidFinishLaunching` 等) は selector ベースで Objective-C 側から発火される」という事情です。
2. **`NSApplicationDelegate` への準拠**
   `NSObject,` の後ろに来るのは protocol です。Swift では「スーパークラス、続いて protocol 群」の順で書くのが慣習になっています。
3. **`final class`**
   ここでも `final`。サブクラス化される予定が一切ないので封印されています。

ここでは NSObject の override は行っていません。NSObject 自体は基底クラスとして「Objective-C ランタイム互換性」を提供するために継承されているだけで、振る舞いの上書きは目的ではないからです。

---

## 16.10 まとめると、何が Swift 流か

| ポイント | Swift 流 |
| --- | --- |
| `override` | **必須キーワード**。書かなければエラー、書きすぎてもエラー |
| `final` | **積極的に使う**。デフォルト sealed の発想 |
| 継承可能な型 | **class のみ**。struct / enum は protocol で抽象化 |
| 暗黙のスーパークラス | **無い**。NSObject は AppKit 連携用の手段 |
| 計算プロパティ | **override 可能**。getter only → read-write の拡張も可 |
| プロパティオブザーバ | **override で追加可能** (`willSet` / `didSet`) |
| 多重継承 | **不可**。protocol 多重準拠で代用 |

ZoomacIt の `DrawingCanvasView` は、これらの仕組みを「NSView (フレームワーク) を継承して、描画とイベントを引き受ける」というオーソドックスな形で活用しています。一方、自分のドメインで新しい階層を作る場合は、まず class 継承ではなく **struct + protocol** を検討するのが Swift らしい選択です (Ch25 で扱います)。

---

## 16.11 ハンズオン (任意)

1. **`override` を抜いてみる**
   手元のサンプルクラスで `override func` の `override` を消してビルドし、エラーメッセージを観察してください。逆に親に存在しない名前に `override` を付けた場合のエラーも見ておきます。
2. **`final class` を継承してみる**
   `final class A {}` を作り、`class B: A {}` を書こうとすると何が起きるかを確認します。
3. **計算プロパティを上書きする**
   `Vehicle.description` (getter only) を `Car` 側で `get` + `set` 付きの計算プロパティに override し、setter からは何か別のフィールドへ書き込む実装を試してください。
4. **`DrawingCanvasView` を読み込む**
   `src/ZoomacIt/Draw/DrawingCanvasView.swift` を頭から末尾まで開いて、`override` が付いている箇所を全部マークしてみてください。NSView がどんな拡張点を提供しているかが体感できます。

---

## まとめ

- Swift の継承は `class Sub: Super` というコロン記法。Java の `extends` と概念は同じ
- **`override` は必須**。書き忘れも書きすぎもエラー — Java の `@Override` (任意) を言語必須化したもの
- **`final`** はクラス全体 / メソッド単位で指定可能。ZoomacIt のようにデフォルトで `final class` にする文化が一般的。設計の明示と静的ディスパッチによる最適化の両得
- Swift には **暗黙のスーパークラスが無い**。NSObject 継承は AppKit / Objective-C 連携の手段であって基底ではない
- **計算プロパティも override できる**。getter only → read-write の拡張も可能
- 継承できるのは class のみ。struct / enum の多態性は protocol で実現する (Ch25 へ続く)
- ZoomacIt の `DrawingCanvasView` は、NSView の `draw(_:)` / マウス / キーボード / カーソルの override 群によって描画キャンバスを実装している。`final class : NSView` という典型的な「フレームワーク拡張のための継承」の見本

「継承の構文を覚える」よりも、「**override 必須・final 積極利用・基底クラス不在・class 限定** という 4 つの違いを腹に入れる」ことが、Swift の継承を Java から移行する上での要点です。

## 次に読む章

→ [17. Initialization](./17-initialization.md)
