# 30. Access Control

## この章で学ぶこと

**アクセス制御 (Access Control)** は、コードのある部分から別の部分への可視性を制限する仕組みです。Java を書いてきたあなたにとっては馴染み深い概念で、目的も同じです。型の内部実装を隠蔽 (encapsulation) し、外部に公開する API 表面 (surface) を最小化することで、変更が他コードに与える影響範囲を限定します。

しかし Swift のアクセス制御は、Java と比べて 1 つ重要な違いがあります。それは制御の単位として **モジュール (module)** という概念を使うことです。Java の `package` はソースファイルが置かれたディレクトリ構造に紐付くフォルダ的な単位ですが、Swift の module は **ビルドターゲットそのもの** です。この違いを理解することが、5 段階あるアクセス修飾子 (`open` / `public` / `internal` / `fileprivate` / `private`) を正しく使い分ける鍵になります。

本章では次の順で見ていきます。

1. モジュールという制御単位
2. 5 段階のアクセス修飾子
3. Java の修飾子との対応関係
4. `private(set)` — Swift 特有のセッター限定制御
5. アクセスレベルの伝播ルール (low-water mark)
6. enum と typealias におけるアクセスレベル
7. ZoomacIt の実コードに見る運用例

---

## モジュールという制御単位

Swift のアクセス制御の基本単位は次の 2 つです。

- **モジュール (module)** — ビルドの最小単位。Xcode のターゲット 1 つが 1 モジュールに対応します。たとえば ZoomacIt アプリは `ZoomacIt` というモジュールにビルドされ、ユニットテストは `ZoomacItTests` という別モジュールにビルドされます。フレームワークやライブラリも 1 つで 1 モジュールです。`import ZoomacIt` の `ZoomacIt` がモジュール名です。
- **ソースファイル (source file)** — モジュールを構成する `.swift` ファイル 1 つ 1 つ。

Java と対応付けると次のようになります。

| Java | Swift |
|------|-------|
| package (ディレクトリ階層) | なし (フラット) |
| jar / モジュール (Java 9+) | module (ビルドターゲット) |
| ソースファイル | ソースファイル |

ここで強調すべきは、**Swift には Java の `package` に相当する中間階層がない** ということです。Java では `com.example.zoomacit.draw` のようにパッケージで分けると、それだけで「同パッケージ内にだけ見える」というスコープが自動的に成立しました。Swift では、ファイルをどのフォルダに置こうが、同じモジュールに属していればすべて同じスコープとして扱われます。フォルダ階層は単にソースコードの整理整頓にすぎず、可視性に影響しません。

このため、モジュールを分割しないアプリ (ZoomacIt はその典型です) では、モジュール内の宣言は実質的にすべてのファイルから参照できます。これは「自由すぎて危険」ではなく、「ファイル配置でスコープを管理しなくてよい」という設計思想だと考えてください。Swift では可視性は **明示的な修飾子** で表現します。

> 単一モジュール構成の利点は、「どこからどこへ参照していいか」のルールが極端にシンプルになることです。ZoomacIt のように 1 つのアプリが完結する規模では、モジュール分割よりも `internal` を基本とした方が見通しが良くなります。

---

## 5 段階のアクセス修飾子

Swift のアクセス修飾子は、開かれている方から順に 5 段階あります。

| 修飾子 | スコープ | 継承・オーバーライド |
|--------|---------|----------------------|
| `open` | 全モジュール | モジュール外からも可能 (class 専用) |
| `public` | 全モジュール | 同モジュール内のみ可能 |
| `internal` | 同モジュール内 | 同モジュール内のみ可能 (デフォルト) |
| `fileprivate` | 同ファイル内 | (該当範囲のみ) |
| `private` | 同宣言ブロック内 | (該当範囲のみ) |

それぞれ簡単に見ていきましょう。

### open

`open` は最もアクセスが緩い修飾子で、**モジュール外** からの利用に加え、**サブクラス化やメソッドのオーバーライド** まで認めます。`open` は class、メソッド、プロパティにのみ付けることができ、struct や enum には適用できません (struct と enum はそもそも継承不可だからです)。

```swift
open class PluginBase {
    open func run() { /* ... */ }
}
```

`open` は基本的にライブラリやフレームワークの作者が、「これは利用者にサブクラス化してほしい」と意図して公開する型に使います。アプリケーション開発では使う機会がほぼありません。

### public

`public` はモジュール外からの利用は許可しますが、**サブクラス化やオーバーライドは同じモジュール内に限定** します。これが Swift と Java の重要な違いです。Java の `public class Foo` はどこからでも継承できましたが、Swift の `public class Foo` は他のモジュールから継承できません。同じモジュール内でしか継承できない、つまり「使えるが、拡張はモジュール作者の許可制」というニュアンスです。

```swift
public class Logger {
    public func info(_ message: String) { /* ... */ }
}
```

ライブラリの作者が「これは使わせるが、勝手に振る舞いを書き換えてほしくない」と思ったときの標準的な選択肢が `public` です。

### internal

`internal` はデフォルトのアクセスレベルです。何も書かなければ自動的に `internal` になります。**同じモジュール内ならどのファイルからでも参照可能**、しかし他のモジュールからは見えません。

```swift
class HotkeyManager {           // internal (省略)
    func register() { /* ... */ }  // internal
}
```

ZoomacIt のような単一モジュールのアプリでは、ほとんどの型・メソッド・プロパティが `internal` のままです。これは「アプリ内のすべてのコードに公開、外部 (もしテストモジュールから見ると話は別ですが) には公開しない」という、アプリにとって最も自然な設定です。

### fileprivate

`fileprivate` は **同じソースファイル内に限定** されます。複数の型がお互いの内部詳細を参照する必要がある場合に使います。

```swift
// Renderer.swift
class ShapeRenderer {
    fileprivate var sharedBuffer: [CGPoint] = []
}

class PathBuilder {
    func build(from renderer: ShapeRenderer) {
        // 同ファイル内なので sharedBuffer にアクセスできる
        let _ = renderer.sharedBuffer
    }
}
```

別ファイルの `PathBuilder` からは `sharedBuffer` は見えません。「このファイルに閉じ込めたい」という設計意図を表現します。

### private

`private` は最も狭く、**宣言が書かれているブロック (型) の内部だけ** に限定されます。Swift 4 以降、同じ型に対する **同ファイル内の extension** からも参照できるようになりました。これは Swift 3 以前と挙動が変わったポイントなので、古い記事を読むときは注意してください。

```swift
class StrokeManager {
    private var strokes: [Stroke] = []  // この class の内部だけ

    func add(_ stroke: Stroke) {
        strokes.append(stroke)  // OK
    }
}

extension StrokeManager {  // 同じファイル内ならOK
    func count() -> Int { strokes.count }
}
```

別の型から `strokes` に触れることはできません。Java の `private` とほぼ同じ感覚で使えます。

---

## Java との対応表

Java 経験者がもっとも戸惑うポイントを表で整理します。

| Java の修飾子 | スコープの説明 | Swift の最も近い対応物 | 注意点 |
|---------------|----------------|------------------------|--------|
| `public` | どこからでも | `public` | Swift の `public` はサブクラス化が同モジュール限定。さらに開く場合は `open` |
| `protected` | 同パッケージ + サブクラス | **対応物なし** | 継承先からの限定アクセスは Swift には存在しない |
| (デフォルト, package-private) | 同パッケージ内 | `internal` | Java の package と Swift の module は粒度が全く違う (後述) |
| `private` | 同クラス内 | `private` | ほぼ同じ。Swift では同ファイル内 extension からも参照可 |

特に注意すべきは次の 2 点です。

**1. Java の `protected` は Swift にはありません。** Java では「サブクラスからだけ見える」という制御ができましたが、Swift はこれを言語仕様で持ちません。やむを得ずサブクラスに渡したい場合は、`internal` (同モジュール内ならアクセス可) で代用するのが現実的です。「`protected` なメンバーが必要だ」と感じたら、まず継承自体を見直し、composition (合成) で解決できないかを検討するのが Swift らしい思考順序です。

**2. Java の package-private (デフォルト) と Swift の `internal` は粒度が全く違います。** Java の package-private は「同じディレクトリ階層 (= 同 package) 内にだけ見える」という、かなり狭い範囲でした。一方 Swift の `internal` は「同モジュール = アプリ全体 or ライブラリ全体」というかなり広い範囲です。このため、「Java で package-private にしていた感覚」で Swift のデフォルトに任せると、想定より広く公開されている可能性があります。本当に狭く隠したい場合は、明示的に `fileprivate` や `private` を選んでください。

---

## private(set) — セッターだけ閉じる Swift 特有の機能

Swift には Java にはない便利な機能があります。それが `private(set)` (および `fileprivate(set)`、`internal(set)`) です。これを使うと、**プロパティのゲッター (読み取り) はあるレベルで公開しつつ、セッター (書き込み) だけをより狭いレベルに制限** できます。

```swift
class Counter {
    private(set) var count: Int = 0   // 外からは読めるが、書けない

    func increment() {
        count += 1                      // 内部からは書ける
    }
}

let c = Counter()
print(c.count)  // OK (read)
c.count = 100   // コンパイルエラー (write)
c.increment()   // OK (内部メソッド経由)
```

Java で同じことを実現するには、フィールドを `private` にして public なゲッターメソッドを書く必要がありました。

```java
// Java の場合
public class Counter {
    private int count = 0;
    public int getCount() { return count; }
    public void increment() { count++; }
}
```

Swift の `private(set)` は、この「読み取り専用プロパティ」というよくあるパターンを 1 行で表現します。`get`/`set` メソッドを手書きする必要がなく、利用側からは普通のプロパティとしてアクセスできます。Swift らしい簡潔さの好例です。

書ける範囲を内部に閉じる用途以外にも、`fileprivate(set)` で同ファイル内ヘルパー型からだけ更新できるようにしたり、`internal(set)` を `public` 型に組み合わせて「ライブラリ利用者には読み取り専用、ライブラリ内部からは書き込み可」を表現したりできます。

```swift
public class DownloadTask {
    public internal(set) var progress: Double = 0  // 外: read only / 内: read-write
}
```

---

## アクセスレベルの伝播ルール (low-water mark)

関数の戻り値や引数、プロパティの型などが絡むと、アクセスレベルは自動的に「より狭い方」に揃えられます。これを公式ドキュメントでは **low-water mark** ルール と呼びます。

具体例で見ましょう。

```swift
internal class Logger { /* ... */ }

public func makeLogger() -> Logger {  // コンパイルエラー
    Logger()
}
```

`makeLogger()` を `public` にしようとしていますが、戻り値の型 `Logger` は `internal` です。もし関数を本当に `public` で公開してしまうと、モジュール外の利用者は「戻り値の型」を表現する手段を持ちません (なぜなら `Logger` 自体がモジュール外には見えないからです)。これは矛盾なので、コンパイラはエラーにします。

解決策は 2 つです。

```swift
// 案 1: 関数のレベルを下げる
internal func makeLogger() -> Logger { Logger() }

// 案 2: 型のレベルを上げる
public class Logger { /* ... */ }
public func makeLogger() -> Logger { Logger() }
```

このルールは関数の引数、プロパティの型、subscript の型など、**「型が登場するあらゆる場所」に適用** されます。次のような細かい例にも注意してください。

```swift
private struct Token { /* ... */ }

class Session {
    var current: Token?  // ここで暗黙のうちに internal にできず、エラーになる場合がある
}
```

ジェネリック型では、型パラメータの制約として使う protocol のレベルも考慮されます。たとえば `public func process<T: SomeProtocol>(...)` と書くなら、`SomeProtocol` も `public` でなければなりません。

このルールの背景は単純です。**「公開した API は、その API を構成するすべてのパーツが同じ可視性で見えていなければ意味をなさない」** からです。利用者が見えない型を返り値にする関数は、利用者にとってまったく使い物になりません。

---

## enum case と raw value のアクセスレベル

enum を `internal` で宣言すると、その **すべての case も自動的に `internal`** になります。case ごとに個別のアクセスレベルを設定することはできません。

```swift
public enum LogLevel {
    case debug   // 自動的に public
    case info    // 自動的に public
    case error   // 自動的に public
}
```

raw value 型 (`LogLevel: String` のような) の付随型もまた、enum 自身のレベルと同等以上である必要があります。たとえば `public enum` の raw value 型は `public` (またはそれ以上) でなければなりません。

これは「enum はその全ケースが揃って初めて意味をなす」という設計思想に沿っています。一部の case だけを隠して別の case だけを公開すると、`switch` の網羅性が壊れる、case 追加で外部コードが破綻するなど、扱いが破綻します。case 単位で公開を分けたい場合は、enum を分割するか別のデータ構造に置き換えるのが正解です。

---

## typealias のアクセスレベル

`typealias` 自身もアクセスレベルを持ち、デフォルトは `internal` です。ただし `typealias` のレベルは、**実体型のレベルを超えてはいけません**。

```swift
internal struct Vec2 { var x, y: CGFloat }

public typealias PublicVec2 = Vec2  // コンパイルエラー (実体が internal)
internal typealias Position = Vec2  // OK
private typealias FilePosition = Vec2  // OK (より狭くする方向は可)
```

`typealias` は単なる別名なので、別名を通じて元の型より広い範囲に公開することはできません。「別名を作って、こっそり public にする」という抜け道は塞がれているわけです。

ジェネリック制約の中で使う場合や、ネストした型に対して短い別名を付ける用途では便利ですが、アクセスレベルが絡むと「実体の型より狭くしか付けられない」と覚えておけば困りません。

---

## ZoomacIt 実コードに見る運用例

ZoomacIt は単一モジュールで構成されたアプリなので、`open` や `public` はほぼ登場しません。**「アプリ全体に公開する `internal` (デフォルト)」と「型の内部実装を隠す `private`」の 2 種類を使い分けるだけ** で、必要十分な可視性管理ができています。実コードで具体的に見てみましょう。

### `Settings` クラス — internal + シングルトンの実例

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

> 引用元: src/ZoomacIt/Models/Settings.swift:47-55

ここに見える要素を可視性の観点から整理します。

| 宣言 | アクセスレベル | 意図 |
|------|---------------|------|
| `final class Settings` | `internal` (省略) | アプリ内のどこからでも `Settings.shared` を参照させる |
| `static let shared` | `internal` (省略) | シングルトンインスタンスを公開 |
| `private let defaults` | `private` | UserDefaults との通信は内部実装。外部に漏らさない |
| `private init()` | `private` | 外部から `Settings()` を呼ばせない (シングルトン強制) |

`final` はアクセス修飾子ではありませんが、ここで一緒に説明する価値があります。`final` は **サブクラス化を禁止** する宣言で、可視性ではなく拡張可能性に関する制御です。「このクラスは継承させない」と明示することで、コンパイラに最適化のヒントを与えると同時に、設計意図 (継承の余地を残さない) を読み手に伝えます。継承させたくない class には `final` を付けるのが Swift の良い習慣です。

そして `private init()` は、Swift で **シングルトンを実装する常套句** です。Java で言うところの「コンストラクタを `private` にして `getInstance()` を提供する」と全く同じパターンですが、`init` キーワードと `static let shared` の組み合わせでより簡潔に書けています。`Settings()` という直接初期化が型の外部から不可能になり、唯一の入り口は `Settings.shared` だけになります。

### `private static let` でルックアップテーブルを隠す

`Settings` の中で、内部だけで使うキー変換テーブルが `private static` で宣言されています。

```swift
private static let keyCodeDisplayNames: [Int: String] = [
    kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
    // ...
    kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`"
]

/// Converts a Carbon virtual key code to a display string.
static func keyCodeToString(_ keyCode: UInt32) -> String {
    keyCodeDisplayNames[Int(keyCode)] ?? "Key\(keyCode)"
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:288-316

このテーブル自体は `Settings` クラスの実装詳細にすぎず、利用者は変換結果である文字列だけを必要とします。テーブルそのものを露出する必要はないので `private static` にしてあります。一方で、テーブルを引いて文字列を返す `keyCodeToString(_:)` は `internal` (デフォルト) で公開され、メニュー表示など他の場所から呼ばれます。

これは **「データ構造は隠し、操作だけ公開する」** という古典的なカプセル化の実例です。テーブルの形式 (Dictionary か配列か、どんなキーを持つか) を後で変えても、`keyCodeToString(_:)` のシグネチャさえ守れば呼び出し側に影響しません。

### `DrawingCanvasView` — 内部状態をすべて private で覆う

ビュークラスの状態管理は、徹底的に `private` で隠蔽されています。

```swift
final class DrawingCanvasView: NSView {

    // MARK: - Callbacks
    var onDismiss: (() -> Void)?

    // MARK: - State
    let drawingState = DrawingState()
    private let strokeManager = StrokeManager()

    private var backgroundImage: CGImage?

    // MARK: - 3-Layer Architecture
    private var finishedLayer: CGImage?
    private var previewLayer: NSBezierPath?
    private var activeFreehand: NSBezierPath?

    // MARK: - Drag State
    private var dragOrigin: CGPoint = .zero
    private var freehandPoints: [CGPoint] = []
    private var isDragging: Bool = false
    // ...
}
```

> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:12-44

ここでも `final class` で継承を禁止し、内部状態のほとんどに `private` を付けています。可視性の階層を読み取るとこうなっています。

| 宣言 | レベル | 役割 |
|------|--------|------|
| `var onDismiss` | `internal` | 外部 (overlay controller) からコールバックを差し込む口 |
| `let drawingState` | `internal` | 描画状態を共有する公開オブジェクト |
| `private let strokeManager` | `private` | ストローク管理は完全な内部実装 |
| `private var finishedLayer` 等 | `private` | 3 層描画アーキテクチャの内部バッファ |
| `private var dragOrigin` 等 | `private` | ドラッグ中の一時的な状態 |

ポイントは、**外部とのインターフェース** (`onDismiss`, `drawingState`) と **完全な内部実装** (`finishedLayer`, `dragOrigin` など) を `private` の有無で明示的に区別している点です。コードを読む人は「`private` が付いていない 2 行 = この型の公開 API」だと一目で理解できます。クラスの API 表面を最小化することで、後で内部表現を変更しても呼び出し側に影響を与えずに済みます。

たとえば後日、3 層描画アーキテクチャを 4 層に拡張したり、`finishedLayer` を `CGImage` から `Metal` テクスチャに変更したりしても、`private` で隠してある以上、外部コードに影響は出ません。これがアクセス制御の本質的な価値です。

### モジュール分割していないアプリでは internal で十分

ZoomacIt のコード全体を見渡すと、`public` や `open` の使用例は実質ゼロです。これは怠慢ではなく、**意識的な設計判断** です。

- アプリは単一モジュールで完結している
- 外部に SDK や API を提供する予定がない
- ユニットテストは `@testable import` で `internal` にもアクセスできる

これらの条件下では、`public` を付けても付けなくても動作は変わりません。むしろ `public` を散りばめると、「ここは外部公開を意識した API なのか」というシグナルがノイズに埋もれます。**「`internal` をデフォルトとし、本当に隠したいものに `private` を付ける」** というシンプルな運用が、単一モジュールアプリでは最も効果的です。

将来、ZoomacIt の一部 (例えば Draw モジュール) を独立したフレームワークに切り出す日が来たら、その時点で初めて `public` の付与を検討すれば十分です。最初から過度に設計しないという、Swift の現実的な姿勢を反映した運用です。

---

## ハンズオン (任意)

実際に手を動かしてアクセス制御の挙動を確かめてみましょう。次のコードを Playground または小さなプロジェクトで試してください。

```swift
// アクセスレベル違反を順に見る

internal struct Token {
    let value: String
}

// 1. low-water mark 違反 — 戻り値の型のレベルが関数より狭い
public func makeToken() -> Token {  // コンパイルエラーになる
    Token(value: "abc")
}

// 2. typealias は実体より広くできない
internal class Storage {}
public typealias PublicStorage = Storage  // コンパイルエラーになる

// 3. private(set) の挙動
class Box {
    private(set) var contents: String = "empty"
    func fill(_ s: String) { contents = s }
}

let b = Box()
print(b.contents)        // OK
// b.contents = "x"      // コンパイルエラー
b.fill("apple")          // OK
print(b.contents)        // "apple"
```

次に、ZoomacIt を `git clone` した上で `Settings.swift` を開き、`private init()` から `private` を外して保存してみてください。`Settings()` を呼び出す箇所を増やすのは難しいので、テストファイル `ZoomacItTests` 配下で次のように書いてビルドしてみると、可視性の違いが体感できます。

```swift
// テストモジュール内
@testable import ZoomacIt

let s = Settings()  // private init を外せば成功、付けたままなら失敗
```

`@testable` 修飾子を付けた `import` は、`internal` 宣言にもアクセスできるようにする特殊な機能ですが、`private` までは突破できません。テスト容易性と可視性のバランスを考えるうえで、知っておくと役立つテクニックです。

---

## まとめ

アクセス制御は地味な機能ですが、コードベースの保守性を長期にわたって支える基盤です。Swift では次の優先順位で考えるのが定石です。

1. デフォルトの `internal` から始める
2. 型の内部実装は `private` で隠す
3. 同ファイル内で複数型が密に協調するときだけ `fileprivate`
4. ライブラリ作者だけが `public` / `open` を意識する

Java の `package` という中間階層を持たない代わりに、Swift は `module` という大粒度の境界と、`private`/`fileprivate` という細粒度の制御を組み合わせます。`protected` がないこと、`private(set)` のように get/set を分離できること、low-water mark で型レベルが伝播することの 3 点は、Java からの移行時に特に意識してください。

そして ZoomacIt のような単一モジュールアプリでは、`public` を一度も書かずに済む — そのことを引け目に感じる必要はまったくありません。アクセス制御の目的はラベルを増やすことではなく、変更が及ぶ範囲を制御することだからです。

---

## 次に読む章

→ [31. Advanced Operators](./31-advanced-operators.md)
