# 17. Initialization

## この章で学ぶこと

- `init(...)` の基本構文と、Java のコンストラクタとの対応関係
- struct だけが受け取る特典 — **memberwise initializer** の自動生成
- 宣言時に **デフォルト値** を持たせて init 引数を省略する書きかた
- 失敗しうる初期化を表す **failable initializer** (`init?`)
- class 限定の **designated / convenience initializer** という二種類の init
- サブクラスに override を強制する **required initializer**
- Swift 独自の安全機構である **2 段階初期化 (two-phase initialization)** がなぜ必要か

> **NOTE**
> この章は **丁寧解説章** です。Java のコンストラクタと似ているのは表面だけで、Swift の init 体系には Java にない概念が複数含まれます。なかでも designated/convenience の区別と 2 段階初期化は、いきなり実コードを読むと混乱しやすいので、最初に丁寧に整理しておきます。
>
> なお、初期化の対になる **deinit (deinitialization)** は次章 Ch18 で扱います。

---

## 17.1 ひとことで

| 観点 | Java | Swift |
| --- | --- | --- |
| 名前 | クラス名と同じ (`Foo() { ... }`) | **`init` キーワード** 固定 |
| 戻り値 | なし (`void` でもない) | なし |
| this 呼び出し | `this(...)` | `self.init(...)` (convenience init から) |
| super 呼び出し | `super(...)` | `super.init(...)` |
| デフォルト引数 | なし (オーバーロードで疑似実現) | あり (`init(x: Int = 0)`) |
| 失敗できる | 例外を投げる | **`init?` で nil を返せる** |
| 自動生成 | レコードのみ | **struct は memberwise init が常に自動生成** |
| 区別 | コンストラクタは 1 種類 | **designated と convenience の 2 種類** (class のみ) |

最初に押さえてほしいのは、**Swift の init はキーワードが `init` 固定** であること、そして **struct と class でルールが大きく違う** ことです。struct は init を書かなくても勝手に作ってくれますが、class は初期化責任が継承の上下に分かれるため、ルールがやや厳しくなります。

---

## 17.2 基本 — `init` の最小形

最も基本的な init は、すべての stored property に値を代入するだけのものです。

```swift
struct Point {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

let p = Point(x: 1, y: 2)
```

Java と並べると差がよく分かります。

```java
// Java
class Point {
    final double x;
    final double y;
    Point(double x, double y) {
        this.x = x;
        this.y = y;
    }
}
```

差は次の二点です。

1. **メソッド名がクラス名ではなく `init` 固定** — 型名を変えても init 名を書き換える必要がありません。
2. **戻り値の表記がいっさいない** — Java も `void` を書きませんが、Swift はそもそも `func` キーワードすら使いません。`init` は専用の構文です。

呼び出し側も Java の `new Point(1, 2)` とは異なり、**`new` キーワードがありません**。`Point(x: 1, y: 2)` のように **型名を関数のように呼ぶ** だけです。

### 引数ラベルは省略できる

Swift の関数と同様、引数ラベルは `_` で抑制できます。

```swift
init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
}

let p = Point(1, 2)   // ラベルなしで呼べる
```

ただし init は呼び出し側で **型名 + 括弧** という最小情報しか露出しないため、ラベルを残しておくほうが意図が読み取りやすくなります。Apple 公式 API もほとんどの init でラベルを残しています。

---

## 17.3 memberwise initializer (struct 限定)

Swift の **struct** には、**自分で init を書かなければ全プロパティを引数に取る init が自動生成** されるという便利な仕組みがあります。これを memberwise initializer と呼びます。

```swift
struct Size {
    var width: Double
    var height: Double
    // init を一切書いていない
}

let s = Size(width: 100, height: 50)   // 自動生成された memberwise init
```

Java のレコード (`record Size(double width, double height) {}`) の感覚に近いですが、Swift の memberwise init は **通常の struct すべてに対して** 自動生成されます。レコードのような特別な宣言は不要です。

### 自動生成される条件

memberwise init は次の条件を満たすときに自動生成されます。

- struct であること (class では生成されない)
- **自分自身に `init` を一切定義していない** こと

逆に言えば、struct で独自の init を一つでも書くと **memberwise init は生成されません**。両方欲しいときは `extension` 内に独自 init を書くと、本体側の memberwise init が生き残ります。

```swift
struct Size {
    var width: Double
    var height: Double
}

extension Size {
    init(square side: Double) {
        self.width = side
        self.height = side
    }
}

Size(width: 1, height: 2)   // memberwise — 残っている
Size(square: 3)             // 独自
```

これは Swift で頻出する設計パターンなので覚えておいてください。

> **class には memberwise init は生成されません。**
> class は継承があるため、勝手に init を作ると親クラスとの整合性が取れません。class は **stored property すべてが宣言時にデフォルト値を持っているか、自分で `init` を書く** 必要があります。

---

## 17.4 デフォルト値で引数を省略する

Swift の init は通常の関数と同じく **デフォルト値** を持てます。Java はメソッド引数のデフォルト値を持たない言語なので、この機能はあるとないとで使い心地が大きく変わります。

```swift
struct Tea {
    var temperature: Double = 80
    var milk: Bool = false
}

let t1 = Tea()                       // 80 / false
let t2 = Tea(temperature: 60)        // 60 / false (milk は省略)
let t3 = Tea(milk: true)             // 80 / true (temperature は省略)
```

memberwise init は **デフォルト値を考慮した上で生成されます**。上の例では引数なし呼び出しから片方だけ指定までの全パターンが、追加コードなしで使えます。

Java で同じことをやろうとすると次のようになります。

```java
// Java — オーバーロードを大量に書く必要がある
class Tea {
    double temperature; boolean milk;
    Tea() { this(80, false); }
    Tea(double t) { this(t, false); }
    Tea(boolean m) { this(80, m); }
    Tea(double t, boolean m) { this.temperature = t; this.milk = m; }
}
```

Swift ではプロパティ宣言時に `=` を書くだけで済みます。**デフォルト値はもっとも使われる省力テクニックの一つ** なので、新しい型を作るときは「初期値が決まっているプロパティはデフォルト値を持たせる」と覚えておいてください。

---

## 17.5 failable initializer — `init?` で nil を返せる

Swift には **失敗しうる初期化** を表す `init?` という構文があります。失敗時には **nil を返す** ため、戻り値型は `Self?` になります。Java で言えば「コンストラクタが例外を投げる代わりに `null` を返せる」イメージです。

```swift
struct Percentage {
    let value: Int
    init?(value: Int) {
        guard (0...100).contains(value) else { return nil }
        self.value = value
    }
}

let ok = Percentage(value: 80)   // Optional(Percentage(value: 80))
let ng = Percentage(value: 200)  // nil
```

呼び出し側は **Optional として受け取る** ため、`if let` や `??` で処理する必要があります。これは型システムが「失敗しうる」ことを強制してくれる、Swift らしい安全機構です。

### enum の RawRepresentable は failable init を自動生成する

Ch11 *Enumerations* で扱った **raw value 付き enum** は、`init?(rawValue:)` という failable init を **コンパイラが自動生成** してくれます。生の文字列や整数から enum 値に変換する標準的な方法です。

ZoomacIt の `PenColor` を例に見てみます (`src/ZoomacIt/Models/DrawingState.swift` 4-30 行付近)。

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink
    // ...
}
```

このように `: String` を付けるだけで、

```swift
let pen = PenColor(rawValue: "red")     // Optional(.red)
let bad = PenColor(rawValue: "purple")  // nil
```

という呼び出しが可能になります。`init?(rawValue:)` のシグネチャはコンパイラが裏側で生成しているもので、ZoomacIt のコード上に明示的な定義はありません。`Settings.swift` の中ではこの自動生成 init を使って UserDefaults から読み取った文字列を enum に戻しています (`src/ZoomacIt/Models/Settings.swift` 165 行付近)。

```swift
var defaultPenColor: PenColor {
    get { PenColor(rawValue: defaults.string(forKey: Keys.defaultPenColor) ?? "") ?? .red }
    set { defaults.set(newValue.rawValue, forKey: Keys.defaultPenColor) }
}
```

`PenColor(rawValue: ...)` が `PenColor?` を返すため、`?? .red` で安全なフォールバックを書いています。failable init + `??` は **永続化された文字列を型安全に戻す** ときの定番パターンです。

> **覚えること**
> 「raw value 付き enum は `init?(rawValue:)` がタダで付いてくる。Optional なので `??` でフォールバックを用意するのがお約束」

---

## 17.6 designated と convenience — class 限定の二種類の init

ここからが Java と最も違うところです。**class の init には designated と convenience の二種類** があります。struct には存在しない区別なので、まず概念を整理します。

| 種類 | 役割 | キーワード |
| --- | --- | --- |
| **designated initializer** | 「指定」イニシャライザ。**全 stored property を初期化し、必要なら親クラスの init を呼ぶ** 責任を負う | `init(...)` |
| **convenience initializer** | 「便利」イニシャライザ。**必ず同じクラスの designated init を呼ぶ** 薄いラッパ | `convenience init(...)` |

Java のコンストラクタチェーン (`this(...)` で別コンストラクタを呼ぶ、`super(...)` で親を呼ぶ) と発想は似ていますが、Swift では **「全プロパティを初期化する責任を持つ designated」と「それを呼ぶだけの convenience」を構文レベルで分けている** 点が決定的な違いです。

### 例で見る

```swift
class Coffee {
    let beanGram: Int
    let waterMl: Int

    // designated — 全 stored property を初期化
    init(beanGram: Int, waterMl: Int) {
        self.beanGram = beanGram
        self.waterMl = waterMl
    }

    // convenience — designated を呼ぶだけ
    convenience init(cups: Int) {
        self.init(beanGram: 12 * cups, waterMl: 180 * cups)
    }

    // convenience — convenience を経由してもよい
    convenience init() {
        self.init(cups: 1)
    }
}

let c1 = Coffee(beanGram: 24, waterMl: 360)  // designated
let c2 = Coffee(cups: 2)                     // convenience → designated
let c3 = Coffee()                            // convenience → convenience → designated
```

ルールは三つだけです。

1. **convenience init は同じクラスの別 init (designated でも convenience でも) を `self.init(...)` で必ず呼ばなければならない**
2. **convenience init から最終的に到達するのは必ず designated init** (循環してはいけない)
3. **designated init は親クラスがあれば `super.init(...)` を呼ばなければならない** (詳細は 17.8 で)

### なぜこの区別が要るのか

Java では「実質的な初期化処理を 1 個書いて、他のコンストラクタは `this(...)` で委譲する」という規約はありますが、コンパイラは強制しません。Swift は **規約をコンパイラが強制** します。これにより、

- **どの init を経由しても必ず全 stored property が初期化される**
- **継承時に親クラスの init が確実に呼ばれる**

という安全性が保証されます。クラス階層が複雑になっても初期化忘れが構造的に起きません。

---

## 17.7 required initializer — サブクラスにオーバーライドを強制する

`required` 修飾子の付いた init は、**サブクラスが必ずオーバーライドして実装しなければなりません**。

```swift
class Document {
    required init() {
        // ...
    }
}

class TextDocument: Document {
    required init() {        // override は不要だが required は付け直す
        super.init()
    }
}
```

代表例が **`NSCoder` 経由の init** です。AppKit / UIKit のビュークラスをサブクラス化すると、IDE が自動で次の init を要求してきます。

```swift
class MyView: NSView {

    init(title: String) {
        // ...
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

`NSView.init?(coder:)` が `required` で宣言されているため、サブクラス側でも実装が必須になります。Storyboard / XIB から復元されないアプリ (ZoomacIt のように完全コードベースで UI を組む場合) では、上記のように `fatalError("...")` を書いておくのが慣例です。

> **Java との対比**
> Java には抽象メソッド (`abstract`) でメソッドの実装強制はできますが、コンストラクタの実装強制はできません。Swift の `required init` は **コンストラクタ自体を抽象化できる** 仕組み、と捉えると分かりやすいです。

---

## 17.8 2 段階初期化 — Swift 独自の安全機構

class の init には **2 段階初期化 (two-phase initialization)** という Swift 独自のルールがあります。

### 仕組み

| フェーズ | 何をする | 制約 |
| --- | --- | --- |
| **Phase 1** | このクラスと祖先すべての **stored property に値を入れる** | この間は **自分自身のメソッド呼び出し / プロパティ参照 / `self` の関数引数渡しが禁止** |
| **Phase 2** | `super.init` 完了後、**`self` を自由に使ってカスタマイズ** できる | 通常の Swift コードと同じ |

実際のコードに即すと、designated init の中身は次の順序で書くことが要求されます。

```swift
class Animal {
    let species: String
    init(species: String) { self.species = species }
}

class Dog: Animal {
    let name: String

    init(name: String, species: String) {
        // === Phase 1 ===
        self.name = name              // 1. 自分の stored property を全部入れる
        super.init(species: species)  // 2. 親クラスの init を呼ぶ
        // === Phase 2 ===
        self.bark()                   // 3. ここから self が使える
    }

    func bark() { print("Woof") }
}
```

順序を逆にすると **コンパイルエラー** になります。`self.bark()` を `super.init` より前に書いた瞬間、コンパイラが拒否します。

### なぜこの仕組みが必要か

ひとことで言えば **「half-initialized オブジェクトを誰にも触らせないため」** です。Java では親コンストラクタが終わる前にサブクラスのメソッドが呼ばれて、未初期化のフィールドにアクセスしてしまう (いわゆる「コンストラクタ内 virtual call 問題」) という古典的な落とし穴があります。Swift は init の構文ルール自体でこれを防いでおり、「初期化途中のインスタンスが外部に漏れる」ことが構造的に起きないよう設計されています。

詳細なルール (override 時の inheritance / safety check 4 項目など) は深い話になるので、本書ではこれ以上踏み込みません。**「自分のプロパティ → super.init → カスタマイズ」の順番だけは死守する** と覚えておけば、実コードで困ることはまずありません。

---

## 17.9 ZoomacIt 実コード読解

### 例 1: 全引数にデフォルト値を持つ struct init — `Stroke`

`src/ZoomacIt/Models/Stroke.swift` 35-51 行付近を見てみます。

```swift
struct Stroke {
    var points: [CGPoint]
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var shapeType: ShapeType
    var isHighlighter: Bool

    init(
        points: [CGPoint] = [],
        startPoint: CGPoint = .zero,
        endPoint: CGPoint = .zero,
        color: NSColor = .red,
        lineWidth: CGFloat = 3.0,
        shapeType: ShapeType = .freehand,
        isHighlighter: Bool = false
    ) {
        self.points = points
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.shapeType = shapeType
        self.isHighlighter = isHighlighter
    }
}
```

ここで一つ疑問が浮かぶはずです。**`Stroke` は struct なのだから memberwise init が自動生成されるのでは？ なぜ明示的に init を書いているのか？**

答えは **「全引数にデフォルト値を与えたかったから」** です。memberwise init はプロパティの宣言にデフォルト値があればそれを尊重しますが、`Stroke` の各プロパティは `var points: [CGPoint]` のように **デフォルト値を持たない宣言** になっています (実装上、別の場所で個別の値を指定したいケースがあるためデフォルト値を宣言時に書いていません)。

そこで明示的な init で **すべての引数にデフォルト値を与える** ことで、

```swift
Stroke()                                  // 全部デフォルト
Stroke(color: .blue)                      // 色だけ指定
Stroke(points: pts, shapeType: .line)     // 必要な分だけ指定
```

という呼び出しを可能にしています。「memberwise を捨ててでも、デフォルト値付き init の柔軟さを取った」設計判断です。struct でも独自 init を書く場面があるという良い例です。

### 例 2: シングルトン用の private init — `Settings`

`src/ZoomacIt/Models/Settings.swift` 47-55 行付近です。

```swift
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }
    // ...
}
```

`init` に **`private` が付いている** のがポイントです。Swift では init もアクセス修飾子で制限でき、`private init` を使うと **クラス外から `Settings()` を呼ぶことができなくなります**。

呼び出せるのは同ファイル内の `static let shared = Settings()` だけ。これにより **シングルトン (常に同じインスタンスを使う設計)** を強制しています。Java でも `private` コンストラクタ + `static getInstance()` で同じことをやりますが、Swift では `static let` でスレッドセーフな遅延初期化が言語レベルで保証されているため、コードがずっと短くなります。

init の中では `registerDefaults()` を呼んで UserDefaults に既定値を登録しています。「**初期化時に一度だけ実行したい処理を init に書く**」という、Java と同じ感覚で素直に使えるパターンです。

### 例 3: failable init を消費する — `defaultPenColor` ゲッター

`src/ZoomacIt/Models/Settings.swift` 164-167 行付近にも、failable init を呼び出しているコードがあります。

```swift
var defaultPenColor: PenColor {
    get { PenColor(rawValue: defaults.string(forKey: Keys.defaultPenColor) ?? "") ?? .red }
    set { defaults.set(newValue.rawValue, forKey: Keys.defaultPenColor) }
}
```

`PenColor(rawValue:)` は **enum 自動生成の failable init** で `PenColor?` を返します。UserDefaults に保存された文字列 (`"red"` / `"green"` / ...) を enum に戻したいわけですが、

- そもそもキーが未保存 → `defaults.string(...)` が `nil` → `?? ""` で空文字に
- 値が enum case にない不正な文字列 → `init?(rawValue:)` が `nil` → `?? .red` で赤にフォールバック

という二段の `??` で **どんな値が入っていても確実に `PenColor` 型を返す** ように作られています。failable init を Optional として受け取り、`??` で安全な既定値に倒す — `Settings` 全体で繰り返し使われている基本テクニックです。

---

## 17.10 ハンズオン (任意)

1. **memberwise init が消える条件を試す**
   - 独自 init を持たない struct を書き、memberwise init で生成できることを確認
   - 同じ struct に `init(square:)` のような独自 init を **本体に** 追加し、memberwise init が呼べなくなることを確認
   - 独自 init を **`extension` に** 移すと memberwise init が復活することを確認
2. **failable init を書く**
   - Email アドレスのような単純な妥当性チェック (`@` を含むか) を行う `EmailAddress` struct を `init?` で書く
   - `?? EmailAddress(unchecked: "noreply@example.com")` のようなフォールバックを試す
3. **convenience init を書く**
   - `Coffee` クラスを上の例どおりに作り、`Coffee(cups: 2)` が designated init に到達することをデバッガで追う
   - `convenience init` の中で `self.beanGram = ...` のように直接 stored property を触ろうとするとコンパイルエラーになることを確認 (convenience init は必ず `self.init(...)` 経由でしか初期化できない)
4. **2 段階初期化の制約を体感する**
   - `Dog` クラスの `init` で `super.init` の **前に** `self.bark()` を書いてみる
   - エラーメッセージ ("self used before super.init call" 系) を読む

---

## まとめ

- Swift の init はキーワードが **`init` 固定**。`new` も型名重複もない
- struct には **memberwise init が自動生成** される。独自 init を本体に書くと消える (extension なら共存)
- プロパティ宣言時のデフォルト値で **init 引数を省略** できる
- 失敗しうる初期化は **`init?`** で nil を返す。enum の `init?(rawValue:)` が代表例
- class の init は **designated (本物) と convenience (薄いラッパ)** の二種類。`self.init` / `super.init` の呼び出し規約をコンパイラが強制する
- **`required init`** はサブクラスに実装を強制する。`init?(coder:)` がよく出てくる
- class の init は **2 段階初期化** に従う。「自分のプロパティ → `super.init` → 後処理」の順を守るだけで OK

Java から来た人にとって最初の壁は「なぜ init が二種類あるのか」「なぜ順番がうるさいのか」だと思います。どちらも **half-initialized オブジェクトを存在させない** ための仕組み、と覚えてください。一度この設計思想に慣れると、Java での「コンストラクタで親の virtual メソッドを呼んでハマる」ような事故が起きないことのありがたみが分かるはずです。

## 次に読む章

→ [18. Deinitialization](./18-deinitialization.md)
