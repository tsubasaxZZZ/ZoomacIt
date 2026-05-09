# 12. Structures and Classes

Swift には、データと振る舞いをひとつの型にまとめるための仕組みとして、構造体 (`struct`) と クラス (`class`) の二つが用意されています。Java から来た読者にとって、この二つの存在こそが Swift で最初に直面する**最大の概念差**となります。Java では「クラスがすべて」であり、`int` などのプリミティブ型を除けば、すべてが参照型として振る舞います。これに対して Swift では、`struct` と `class` は文法上ほとんど同じ機能を持ちながら、**値型 (value type) と参照型 (reference type) という根本的に異なる意味論**で動作します。

この違いを理解することは、Swift で正しく動くコードを書くための前提条件です。コピーされるべきデータをクラスにしてしまうと、思わぬ場所でデータが書き換わるバグを生みます。逆に共有されるべき状態を構造体にしてしまうと、変更が他の場所に伝わらず「なぜか反映されない」という現象に悩まされます。

本章は、本書のなかでもとくに丁寧に書かれた章のひとつです。Swift コミュニティの規範、メモリ上での挙動の違い、ZoomacIt の実コードにおける使い分けまで、具体例を交えて掘り下げていきます。

## この章で学ぶこと

- `struct` と `class` の共通点 (プロパティ、メソッド、イニシャライザ、サブスクリプト、拡張、プロトコル適合)
- 値型と参照型の違いを、代入・関数引数・コレクション格納の三つの場面で観察する
- `===` による同一性比較 (identity) と、なぜ `struct` には identity がないのか
- クラス継承と、`struct` がクラス継承を持たない理由
- `deinit` がクラスにのみ存在する理由
- ARC (Automatic Reference Counting) の対象となるのはクラスインスタンスだけであること
- 「`struct` を優先、`class` は理由があるとき」という Swift コミュニティの規範
- ZoomacIt のなかで「なぜ `Stroke` は `struct` で `DrawingState` は `class` なのか」という設計判断の読み解き

## 1. 共通点 — Java 経験者が安心できる土台

`struct` と `class` は、Swift のなかで多くの機能を共有しています。表面的には、宣言キーワードを `struct` から `class` に置き換えるだけで動くケースも珍しくありません。具体的には、両者ともに次のことができます。

| 機能 | struct | class |
|------|--------|-------|
| プロパティ (格納/算出) を持つ | はい | はい |
| メソッド (インスタンス/型) を持つ | はい | はい |
| イニシャライザを定義する | はい | はい |
| サブスクリプトを定義する | はい | はい |
| `extension` で機能を追加する | はい | はい |
| プロトコルに適合する | はい | はい |
| ジェネリクスを使う | はい | はい |

つまり、構造体だからといってメソッドが書けないわけではなく、構造体だからといってプロトコルに適合できないわけでもありません。Swift の `struct` は、Java の `record` (Java 14 以降) よりもはるかに自由度が高く、**メソッドも持てれば、計算プロパティも持てれば、プロトコルにも適合できる**「フル機能の値型」です。Java の `record` を「不変なデータホルダー」程度に捉えていると、Swift の `struct` の表現力を見誤ります。

Swift で `struct` か `class` かを選ぶときに「どちらでもできること」のリストを気にする必要はほとんどありません。問題は常に、**コピー意味論か参照意味論か**という一点に集約されます。

## 2. 決定的な違い — 値型 (struct) と参照型 (class)

Swift で `struct` のインスタンスを別の変数に代入したり、関数の引数として渡したり、配列の要素として格納したりすると、**そのたびに値はコピーされます**。コピー後の値は元の値とは独立しており、片方を変更してももう片方には影響しません。

一方、`class` のインスタンスを同じように扱うと、**コピーされるのは参照だけ**です。複数の変数が同じインスタンスを指すことになり、片方を通じて変更すれば、もう片方からも変更後の状態が見えます。これは Java のオブジェクトと同じ挙動です。

### 2.1. struct のコピー意味論を実演する

ZoomacIt の `Stroke` 構造体を題材に、コピー意味論を観察してみましょう。

```swift
import AppKit

struct Stroke {
    var color: NSColor
    var lineWidth: CGFloat
}

var a = Stroke(color: .red, lineWidth: 3.0)
var b = a            // ここで a の内容が b にコピーされる
b.color = .blue      // b だけが青になる
b.lineWidth = 10.0   // b だけが太くなる

print(a.color)       // sRGB IEC61966-2.1 colorspace 1 0 0 1 (赤のまま)
print(a.lineWidth)   // 3.0 (元のまま)
print(b.color)       // sRGB IEC61966-2.1 colorspace 0 0 1 1 (青)
print(b.lineWidth)   // 10.0
```

代入文 `var b = a` の時点で、`a` のフィールドはすべて `b` にコピーされます。以降、`a` と `b` は独立した二つの値であり、片方を変更しても他方には伝播しません。これは関数の引数として渡したときも同じです。

```swift
func makeBlue(_ stroke: Stroke) {
    var local = stroke
    local.color = .blue   // 関数内のローカルコピーを変更
    // 呼び出し元には影響しない
}

var original = Stroke(color: .red, lineWidth: 3.0)
makeBlue(original)
print(original.color)    // 依然として赤
```

Java で同じことを書くと、`stroke` は参照渡しになるため、関数の中で `stroke.color = ...` と書けば呼び出し元のオブジェクトも書き換わります。Swift の `struct` ではこれが起こりません。**意図せず他人のデータを書き換えてしまう事故が原理的に発生しない**のが、値型の最大の安心感です。

なお、関数の引数として渡された `struct` はデフォルトで**変更不可 (`let` 相当)** です。関数の中で書き換えたい場合は、上の例のように `var local = stroke` のようにローカル変数として受け直す必要があります。

### 2.2. class の参照意味論を実演する

同じことを `class` で試すと、結果はまったく異なります。ZoomacIt の `DrawingState` クラスを題材にしましょう。

```swift
final class DrawingState {
    var penWidth: CGFloat = 3.0
    var activeColor: PenColor = .red
}

let s1 = DrawingState()
let s2 = s1            // ここでコピーされるのは「参照」だけ
s2.penWidth = 10.0     // s2 を通じて変更
s2.activeColor = .blue

print(s1.penWidth)     // 10.0 (s1 からも変更が見える)
print(s1.activeColor)  // blue
```

`let s2 = s1` は、`s1` が指しているインスタンスへの参照を `s2` にコピーしているだけです。`s1` と `s2` は同じひとつのインスタンスを指しているため、`s2` を通じた変更は `s1` から観測できます。

ここでもうひとつ、Java から来た読者を驚かせるポイントがあります。**`s1` と `s2` は `let` で宣言されている**にもかかわらず、その先のプロパティ `penWidth` を書き換えられている点です。

`let` が固定するのは「`s2` という変数がどのインスタンスを指すか」だけであり、指し示されているインスタンスの中身までは固定しません。これは Java で `final DrawingState s2 = s1;` と書いたときに、`s2` の参照先を変えられないだけで `s2.penWidth = 10` は書ける、というのと同じ理屈です。

### 2.3. 代入・引数・コレクション — どこでコピーされるか

値型と参照型の違いが効いてくる典型的な場面を整理しておきます。

| 場面 | struct (値型) | class (参照型) |
|------|--------------|---------------|
| 別の変数に代入 (`let b = a`) | 全フィールドがコピーされる | 参照だけがコピーされる |
| 関数の引数として渡す | コピーされ、関数内では `let` 相当で受け取る | 参照が渡され、関数内で変更すれば呼び出し元にも反映 |
| 配列に入れて取り出す | 取り出すたびにコピー | 参照を共有 |
| 辞書の値として保存 | 保存時・取得時にコピー | 参照を共有 |
| `Optional` でラップ | 中身ごとコピー | 参照だけコピー |

このため、Swift で「配列の要素を変更したつもりが反映されない」と悩むケースの多くは、`struct` を配列に入れていることが原因です。

```swift
struct Stroke { var color: NSColor }
var strokes = [Stroke(color: .red)]
strokes[0].color = .blue   // これは動く: 添字経由の代入は元の配列を書き換える

for var stroke in strokes {
    stroke.color = .green  // これは効かない: ループ変数はコピー
}
print(strokes[0].color)    // 依然として青
```

Swift コンパイラは、`subscript` 経由の代入については元の配列のメモリを直接書き換える最適化を行うため、`strokes[0].color = .blue` は動きます。一方、`for var stroke in strokes` で取り出した `stroke` はコピーであり、それを変更しても元の配列には影響しません。値型を扱う際には、**「いつコピーが発生したか」**を常に意識する必要があります。

### 2.4. パフォーマンスは心配しなくてよい

「すべて値渡しならパフォーマンスが悪いのでは」と感じるのは自然な疑問です。実際、Swift コンパイラと標準ライブラリは、値型を効率よく扱うために多くの工夫をしています。

- 小さな `struct` (CPU レジスタに収まるサイズ) はそのまま値で渡され、関数呼び出しのオーバーヘッドはほぼゼロです。
- 大きな `struct` (`Array`、`Dictionary`、`String` など) は内部にバッファへの参照を持ち、**コピーオンライト (copy-on-write)** で実装されています。代入しただけではバッファは複製されず、書き込みが発生したときにはじめて複製されます。
- ジェネリクスや関数引数では、コンパイラが状況を解析して可能な限りコピーを省略します。

つまり、`struct` を選んだからといって自動的に遅くなるわけではありません。「意味論で選び、必要なときだけパフォーマンスを測定する」のが Swift の流儀です。

## 3. identity (同一性) — `===` は class だけ

参照型のインスタンスは、メモリ上で唯一のアドレスを持っています。そのため、二つの参照が**同じインスタンス**を指しているかどうかを比較できます。これを identity (同一性) と呼び、Swift では `===` (および `!==`) 演算子で確認します。

```swift
let s1 = DrawingState()
let s2 = s1
let s3 = DrawingState()

print(s1 === s2)   // true: 同じインスタンス
print(s1 === s3)   // false: 別のインスタンス
print(s1 == s2)    // これは Equatable に適合していなければコンパイルエラー
```

ここで重要なのは、`==` (等価) と `===` (同一) は別の概念だという点です。

- `==` は「内容が等しいか」を比較する。`Equatable` プロトコルへの適合が必要。
- `===` は「同じインスタンスを指しているか」を比較する。クラスインスタンスでのみ使える。

Java の `equals` と `==` の関係に似ていますが、Java の `==` (参照比較) が Swift の `===` に相当し、Java の `equals` が Swift の `==` に相当する、と覚えておくとよいでしょう。

そして、**`struct` には identity という概念そのものがありません**。`struct` の値はコピーされうるので、「これとあれは同じインスタンス」という問いが意味を持たないのです。次のコードはコンパイルエラーになります。

```swift
let a = Stroke(color: .red, lineWidth: 3.0)
let b = a
print(a === b)
// Error: Cannot convert value of type 'Stroke' to expected argument type 'AnyObject'
```

「2 つの `Stroke` が同じか」を判定したいなら、`Equatable` に適合させて `==` で比較するべきです。

## 4. 継承 — class だけが持つ機能

Swift の `class` は、ほかのクラスを継承できます。これは Java のクラス継承とほぼ同じ仕組みです。

```swift
class Animal {
    func speak() { print("...") }
}

class Dog: Animal {
    override func speak() { print("Woof!") }
}
```

一方、**`struct` はクラス継承できません**。`struct` 同士で継承関係を作ることもできません。`struct` で「共通の振る舞いを束ねたい」場合は、プロトコルへの適合と `extension` を組み合わせます (詳細は Ch20-22 で扱います)。

クラス継承を多用するか避けるかは、Swift コミュニティのなかでも議論があるテーマです。AppKit や UIKit は `NSView`、`NSWindow`、`NSWindowController` といった継承前提の API を持っているため、これらと統合するクラスは継承を使う必要があります。一方、ビジネスロジックの世界では「継承よりプロトコル合成 (Protocol-Oriented Programming)」という方針が推奨されることが多く、`struct` + プロトコルでの設計が好まれます。

Swift で継承を選ぶときは、**「ほかに方法がないか」**を一度立ち止まって考える価値があります。プロトコルと `extension` で同じことが達成できるなら、そのほうが多くの場合シンプルです。

## 5. deinit — class だけが持てる解放処理

`class` では、インスタンスが解放される直前に呼ばれる特別なメソッド `deinit` を定義できます。Java の `finalize()` に近い役割ですが、Swift の `deinit` は ARC によって**決定論的に**呼ばれるため、`finalize` よりはるかに信頼できます (Java の `finalize` は GC 任せで、いつ呼ばれるか保証されません)。

```swift
final class TemporaryFile {
    let path: String

    init(path: String) {
        self.path = path
        NSLog("[TemporaryFile] created at \(path)")
    }

    deinit {
        NSLog("[TemporaryFile] deleted at \(path)")
        try? FileManager.default.removeItem(atPath: path)
    }
}
```

このように、リソース解放やログ出力など、インスタンスのライフサイクル終了時に必ず実行したい処理を `deinit` に書きます。

`struct` には `deinit` がありません。なぜなら、値型はコピーされて流通するため、「いつ解放されるか」を一意に決められないからです。値型を使うリソースで、終了処理が必要なものは別の手段 (`defer`、関数のスコープ、明示的な `close()` メソッドなど) で扱います。

## 6. ARC — クラスインスタンスのみ参照カウント管理

クラスインスタンスは、**ARC (Automatic Reference Counting)** によってメモリ管理されます。ARC は、各インスタンスへの強い参照の数を追跡し、強い参照がゼロになった時点でインスタンスを解放します。Java の GC とは違って、解放のタイミングは決定論的です (どこかで `nil` になった瞬間に `deinit` が走る)。

`struct` は ARC の管理対象ではありません。値型は基本的にスタック上 (または親オブジェクトの一部として) に格納され、スコープを抜ける時点で自動的に消えます。

ARC には**強参照循環 (retain cycle)** という落とし穴があり、`weak` や `unowned` といったキーワードを使って回避する必要があります。これは別途 Ch28 で詳しく扱いますが、現時点では「クラスは ARC で管理される、循環参照には注意が必要」という事実だけ覚えておけば十分です。

## 7. どちらを選ぶか — Swift コミュニティの規範

Swift コミュニティ、および Apple の公式ガイドラインが推奨する基本方針は明快です。

> **デフォルトで `struct` を選び、`class` は理由があるときに使う。**

これは Java 経験者にとってかなり違和感のある指針です。Java では「とにかくクラスから始める」のが常識でした。Swift ではむしろ逆で、「とりあえず `struct` で書いてみて、本当に `class` が必要かどうかを考える」というスタンスが規範です。

`class` を選ぶべき具体的な理由は、おおむね次の五つに整理できます。

1. **identity が必要なとき** — 「これとあれは同じインスタンス」という同一性が意味を持つとき。たとえば「現在のセッション」「ログイン中のユーザー」など、唯一性を持つオブジェクト。
2. **AppKit / UIKit の継承が必要なとき** — `NSView`、`NSWindow`、`NSWindowController`、`NSDocument` などを継承する型は class であるしかありません。
3. **`deinit` が必要なとき** — ファイルハンドル、ネットワーク接続、Carbon API のハンドルなど、明示的な解放処理が必要なリソース。
4. **Objective-C 互換が必要なとき** — `@objc` でブリッジしたい型、KVO の対象としたい型など。
5. **大きな状態を共有したいとき** — 複数の View / Controller が「同じ状態」を見て、誰かが変更したら全員に反映されてほしい状況。

これらに当てはまらないなら、`struct` で十分です。とくに「データを表す型」「計算結果を返す型」「設定値の集合」のようなものは、迷わず `struct` を選びます。

### 7.1. 決定フローチャート

```
新しい型を定義する
        │
        ▼
identity (同一性) が意味を持つか?
        │
   ┌────┴────┐
   はい     いいえ
   │          │
   ▼          ▼
 class    AppKit/UIKit を継承する必要があるか?
            │
       ┌────┴────┐
       はい     いいえ
       │          │
       ▼          ▼
     class    deinit / Obj-C 互換 / 共有状態が必要か?
                  │
             ┌────┴────┐
             はい     いいえ
             │          │
             ▼          ▼
           class      struct
```

迷ったら `struct` を選ぶ、というのが Swift 流の出発点です。

## 8. ZoomacIt の使い分け — Stroke と DrawingState

ここまでの理論を、ZoomacIt の実コードで確かめます。本プロジェクトには「`struct` と `class` の使い分け」がはっきり現れる対比があります。`Stroke` は `struct`、`DrawingState` は `class` です。なぜでしょうか。

### 8.1. なぜ `Stroke` は `struct` なのか

ZoomacIt の `Stroke` は、ユーザーが描いたストロークひとつひとつを表す型です。

```swift
// src/ZoomacIt/Models/Stroke.swift
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
        // ...
    }
}
```

`Stroke` は「点のリスト・色・太さ・形状」が等しければ同じストロークだと言える、純粋なデータです。識別子 (ID) を持たず、「これとあれは同じインスタンス」という問いが意味を持ちません。**識別ではなく内容で語られる存在**であり、これは値型の典型です。

さらに、`Stroke` を `struct` にすることで、いくつかの実装上のメリットが生まれます。

- **複数のレイヤーに渡しても安全**: `Stroke` は `DrawingCanvasView` の `previewLayer` (描画中のプレビュー) や `finishedLayer` (確定済みレイヤーのラスタライズ元) など、複数の場所に渡されます。値型ならコピーが流通するため、片方を書き換えてももう片方に影響しません。「描画中のプレビューが、いつの間にか確定済みレイヤーの色を変えてしまう」といった事故が原理的に起こりません。
- **配列に格納しても自然**: 確定済みストロークは `[Stroke]` として保持されます。配列の要素として `struct` を入れる場合、各要素は独立した値として扱われます。後から `strokes[3].color = .blue` のように一部だけを書き換える操作も自然に書けます。
- **スレッド境界を越えて渡しやすい**: 値型はコピーされて渡るため、Swift 6 の strict concurrency のもとでもデータレースを起こしません (型自体が `Sendable` 準拠であれば)。`Stroke` のフィールドは基本的に値型ばかりで、`Sendable` 化への道もスムーズです。

`Stroke` を `class` にすると、これらの利点がすべて失われます。プレビュー用の `Stroke` と確定済みの `Stroke` が同じインスタンスを指してしまえば、片方を変更したつもりでもう片方の見た目を壊すバグが容易に生まれます。値であるべきものを参照型にしてしまうと、「いつ・誰がこのインスタンスを書き換えるか」を常に追跡する必要が出てきて、コードの理解コストが跳ね上がります。

### 8.2. なぜ `DrawingState` は `class` なのか

対照的に、`DrawingState` は `class` で宣言されています。

```swift
// src/ZoomacIt/Models/DrawingState.swift
final class DrawingState {

    // MARK: - Pen Properties

    var activeColor: PenColor = Settings.shared.defaultPenColor
    var penWidth: CGFloat = Settings.shared.defaultPenWidth
    var isHighlighterMode: Bool = false

    // ...
}
```

`DrawingState` は「現在のペン色は何か」「いまハイライターモードか」「Tab キーが押されているか」「背景は何か」といった、**Draw 機能全体で共有される可変状態**を保持します。複数の View / Controller が同じ `DrawingState` インスタンスを参照し、誰か一人が状態を変更すれば、参照している全員にその変更が見える必要があります。

これを `struct` で実現することは原理的に不可能です。`struct DrawingState` を作って `DrawingCanvasView` に渡しても、それはコピーされてしまいます。`DrawingCanvasView` がコピーを書き換えても、それは元の `DrawingState` には伝わりません。「ペンの色を変えたつもりが、なぜか描画には反映されない」という最悪のバグが生まれるでしょう。

参照型のクラスにすることで、`DrawingState` のインスタンスは「Draw 機能における唯一の真実 (single source of truth)」として機能できます。ペン色を変える、ハイライターモードに切り替える、ペン幅を増減する — どこでこれらの操作をしても、同じインスタンスを参照しているすべての場所に変更が伝わります。

### 8.3. なぜ `final class` なのか

`DrawingState` の宣言には `final` キーワードがついています。`final` は「このクラスを継承禁止にする」という宣言です。

```swift
final class DrawingState { ... }
```

これにより、誰かが `class CustomDrawingState: DrawingState` のようにサブクラス化することを防げます。なぜそうしているのか、二つの理由があります。

1. **設計意図の明示** — `DrawingState` は ZoomacIt の Draw 機能専用の状態管理クラスであり、サブクラスで拡張する設計を想定していません。`final` を付けることで、その意図がコードを読む人に明確に伝わります。
2. **パフォーマンス** — `final` クラスのメソッド呼び出しは、コンパイラが**静的ディスパッチ**できます。継承可能なクラスのメソッドは仮想関数テーブル経由 (動的ディスパッチ) になりますが、`final` ならその間接化が省けます。Draw のホットパスで呼ばれるメソッドの最適化に効きます。

「class を選ぶ理由はあるが、継承させる必要はない」というケースでは、`final class` がよい選択です。実際、Swift コミュニティでは「迷ったら `final class` を付ける」というガイドラインがしばしば語られます。

### 8.4. 対比をまとめる

| | Stroke | DrawingState |
|---|--------|--------------|
| 種類 | `struct` | `final class` |
| 意味論 | 値 (コピーされる) | 参照 (共有される) |
| identity を持つか | 持たない (内容で同一性を判定) | 持つ (`===` で比較可能) |
| 何を表すか | 描画されたストロークそのもの | Draw 機能の現在の状態 |
| 流通の様子 | 各レイヤー・配列にコピーで配られる | 唯一のインスタンスが共有される |
| 変更の伝播 | 起こらない (各コピーは独立) | すべての参照元に反映される |
| ライフサイクル | スコープに従って自動消滅 | ARC で管理 (今回は AppDelegate が保持) |
| 継承 | 不可 | `final` で禁止 |

この対比は、Swift における `struct` と `class` の使い分けの教科書的な例になっています。本プロジェクトを読み進めるなかで、新しい型に出会ったら「これは値か、共有される状態か」と問う習慣をつけてください。

## 9. Java との対比表

最後に、Java 経験者向けに、Java と Swift の型概念の対応関係をまとめておきます。

| 概念 | Java | Swift |
|------|------|-------|
| 参照型のオブジェクト | `class` | `class` |
| 値として扱われるデータ | `record` (Java 14+) または プリミティブ | `struct` |
| プリミティブ型 | `int`, `double` など | `Int`, `Double` も `struct` |
| 等価比較 | `equals()` | `==` (`Equatable`) |
| 同一性比較 | `==` (参照比較) | `===` (クラスインスタンスのみ) |
| 不変参照 | `final 変数` | `let` |
| 継承禁止 | `final class` | `final class` |
| メモリ管理 | GC | ARC (クラスインスタンスのみ) |
| 解放処理 | `finalize()` (非推奨) | `deinit` (決定論的) |

注目すべき点は、Swift では**プリミティブ型に相当するものまでが `struct` として実装されている**ことです。`Int`、`Double`、`Bool`、`String`、`Array`、`Dictionary` — これらはすべて `struct` であり、値型として動きます。Java で「`int` は値、`Integer` は参照」と分かれていた区別が、Swift では「`Int` ひとつで完結する」シンプルさになっています。

また、Java の `record` と Swift の `struct` を比べると、`record` は「不変なデータホルダー」に特化した機能を持ちますが、メソッド定義などはあまり書きません。Swift の `struct` は、メソッド・計算プロパティ・プロトコル適合・ジェネリクスなど、`class` で書けることのほとんどが書けます。Swift の `struct` のほうがはるかに表現力が高い、ということを覚えておいてください。

## 10. ハンズオン (任意)

理解を確かめるための練習問題を用意しました。Playground または `swift` REPL で試してみてください。

### 課題 1: 値型の独立性を観察する

```swift
struct Point2D {
    var x: Double
    var y: Double
}

var p1 = Point2D(x: 1.0, y: 2.0)
var p2 = p1
p2.x = 100.0

// ここで p1.x の値は何になるか? 予想してから print してみる
print(p1.x)
print(p2.x)
```

### 課題 2: 参照型の共有を観察する

```swift
final class Counter {
    var value: Int = 0
}

let c1 = Counter()
let c2 = c1
c2.value = 42

// ここで c1.value の値は何になるか?
print(c1.value)
print(c1 === c2)  // true / false ?
```

### 課題 3: Stroke を struct から class に変えると何が起こるか

`Stroke` 構造体を `class` に書き換え、配列に複数入れたあとでひとつだけ書き換えるコードを書いてみてください。期待通りに動くでしょうか。動きがどう変わるか観察し、なぜ ZoomacIt が `Stroke` を `struct` のままにしているのかを実感してください。

## まとめ

- `struct` と `class` は、プロパティ・メソッド・プロトコル適合といった大半の機能を共有する。表面上の違いは少ない。
- 決定的な違いは**値型 (struct) と参照型 (class) の意味論**である。代入・引数・コレクション格納の場面で挙動が変わる。
- `===` による identity は class のみが持つ。`struct` には identity の概念がない。
- 継承、`deinit`、ARC は class のみの機能。
- Swift コミュニティの規範は「`struct` を優先、`class` は理由があるときに使う」。`class` を選ぶ理由は (a) identity、(b) AppKit/UIKit 継承、(c) `deinit`、(d) Objective-C 互換、(e) 共有状態の五つ。
- ZoomacIt の `Stroke` は値そのものを表すから `struct`、`DrawingState` は共有される可変状態を表すから `final class`。この対比は Swift における型選びの教科書的な例である。

`struct` と `class` の使い分けを身につけたら、それぞれの型に何を書けるか — プロパティ・メソッド・イニシャライザ — をより深く学んでいきましょう。次章ではプロパティを扱います。

## 次に読む章

→ [13. Properties](./13-properties.md)
