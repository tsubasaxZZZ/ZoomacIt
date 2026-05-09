# 13. Properties

## この章で学ぶこと

Swift のプロパティは、Java の field、getter、setter、`@Lazy`、PropertyChangeListener を一つの構文体系に統合した、言語レベルの抽象化です。本章では値を保存するだけの単純な **stored property** から、計算で値を返す **computed property**、値の変更をフックする **property observer**、初回アクセスまで初期化を遅延する **lazy property**、型に紐づく **type property**、そしてアクセサそのものを再利用可能にする **property wrapper** までを順に解説します。Java で書かれていた `private int x; public int getX() { return x; }` という冗長なボイラープレートが Swift では `var x: Int` の一行に収まる、その背景にある設計思想までを掘り下げます。

ZoomacIt の `DrawingState` と `Settings` には、本章で扱うほぼすべてのプロパティ種別が登場します。実コードを並べながら、Swift の型設計が Java の Bean 規約と何が違うのかを確認していきましょう。

---

## 13.1 Stored Property — 値を保存する基本のプロパティ

**stored property** は、その名のとおり値を「保存」するプロパティです。クラスや構造体のインスタンスに紐づき、`var` または `let` キーワードで宣言します。Java の field と同じ役割ですが、宣言と同時にデフォルト値を与えられる点と、可変・不変が `var` / `let` で表現される点が異なります。

```swift
final class Pen {
    var color: String = "red"   // 可変。後から変更できる
    let maxWidth: CGFloat = 50  // 不変。インスタンス生成後は変更不可
}
```

Java で同じことを書くと次のようになります。

```java
public final class Pen {
    private String color = "red";
    private final double maxWidth = 50;

    public String getColor()        { return color; }
    public void setColor(String c)  { this.color = c; }
    public double getMaxWidth()     { return maxWidth; }
}
```

Swift では `getX()` / `setX()` メソッドが言語シュガーとして組み込まれているため、外部からのアクセスは `pen.color = "blue"` のようにフィールド代入の構文で書けます。にもかかわらず、後述の computed property や observer に書き換えても呼び出し側コードは一切変わりません。これが **uniform access principle** と呼ばれる Swift の設計原則です。

### ZoomacIt の実例

`DrawingState` クラスは、描画中の状態を保持する典型的な stored property の集合体です。

```swift
// src/ZoomacIt/Models/DrawingState.swift:33-48 より
final class DrawingState {

    // MARK: - Pen Properties
    var activeColor: PenColor = Settings.shared.defaultPenColor
    var penWidth: CGFloat = Settings.shared.defaultPenWidth
    var isHighlighterMode: Bool = false

    // MARK: - Text Mode
    var isTextMode: Bool = false

    // MARK: - Modifier Key Tracking
    /// Tab key must be tracked via keyDown/keyUp since it's not a modifier flag.
    var isTabHeld: Bool = false
}
```

注目すべきは、**初期化子 (`init`) を一切書いていない** ことです。すべての stored property にデフォルト値が与えられているため、Swift コンパイラが「メンバーをすべてデフォルト値で初期化する暗黙の `init()`」を自動生成します。Java で同じ効果を得るには、引数なしコンストラクタを明示的に書くか、Lombok の `@NoArgsConstructor` に頼る必要がありました。

### init で値を設定する

stored property のデフォルト値を与えず、`init` で確定させることもできます。

```swift
final class Stroke {
    let color: PenColor
    let width: CGFloat

    init(color: PenColor, width: CGFloat) {
        self.color = color
        self.width = width
    }
}
```

`let` で宣言した不変プロパティであっても、`init` の中でなら一度だけ値を代入できます。これは Java の `final` field と同じ意味論です。`init` を抜けた瞬間に値は固まり、以後の変更は型システムが拒否します。

> **NOTE**: 構造体 (`struct`) の場合、すべての stored property を引数に取る **memberwise initializer** がコンパイラによって自動合成されます。クラス (`class`) ではこの恩恵はなく、`init` を自分で書く必要があります。詳しくは Ch15 で扱います。

### var と let の選択指針

「変更されうる状態か、生成後不変か」を考え、迷ったら `let` を選んでください。Swift コミュニティでは「最初は `let`、コンパイラに怒られたら `var` に変える」という方針が広く採用されています。これは、ミュータブルな状態を可能な限り減らすことでバグの混入を抑える、関数型寄りのスタイルです。

---

## 13.2 Computed Property — getter / setter が言語シュガーになったもの

**computed property** は、値を保存しません。アクセスされるたびに `get` ブロックが評価され、その戻り値が値として扱われます。代入時には `set` ブロックが呼ばれます。Java の `getX()` / `setX()` メソッドペアを、フィールドアクセスの構文で透過的に呼び出せるようにした仕組みです。

### 基本構文

```swift
struct Rectangle {
    var width: CGFloat
    var height: CGFloat

    var area: CGFloat {
        get { width * height }
        set { width = sqrt(newValue * width / height); height = newValue / width }
    }
}
```

`get` ブロックの戻り値が呼び出し時の値、`set` ブロックには呼び出し元が代入した値が暗黙の名前 `newValue` で渡されます。引数名を変えたい場合は `set(myValue) { ... }` のように書けます。

### 読み取り専用 computed property は `get` を省略可能

`set` がない場合 (= 読み取り専用) は `get` キーワードごと省略でき、ブロックの中身がそのまま getter 本体として扱われます。

```swift
struct Rectangle {
    var width: CGFloat
    var height: CGFloat

    // get { ... } と書く必要がない
    var area: CGFloat {
        width * height
    }
}
```

これは Swift で頻出するスタイルなので、慣れておきましょう。

### Java との比較

Java で同じ「面積」を提供するには、メソッドとして公開するか、フィールドと「同期させ続けるロジック」を `setWidth` / `setHeight` の両方に書くかしかありませんでした。

```java
public final class Rectangle {
    private double width;
    private double height;

    public double getArea() { return width * height; }
}
```

呼び出し側は `rect.getArea()` と書くしかなく、後から `area` を field に格上げしたくなったとしても API 互換性が壊れます。Swift の computed property は、**呼び出し側の構文を変えずに保存方法を切り替えられる** という、メンテナンス上の大きな利点を持ちます。

### ZoomacIt の実例: 派生プロパティ

`DrawingState` の `currentNSColor` は、保存された `activeColor` (列挙体) と `isHighlighterMode` (Bool) から、その都度 `NSColor` を計算して返す典型的な computed property です。

```swift
// src/ZoomacIt/Models/DrawingState.swift:62-65 より
/// The NSColor to use for drawing, applying highlighter alpha if needed.
var currentNSColor: NSColor {
    let base = activeColor.nsColor
    return isHighlighterMode ? base.withAlphaComponent(Settings.shared.highlighterOpacity) : base
}
```

`get` キーワードを省略した、読み取り専用 computed property です。呼び出し側は `state.currentNSColor` と書くだけで、内部のハイライターモード判定や透過度適用を意識する必要がありません。もし `currentNSColor` を将来 stored property としてキャッシュする実装に変えたとしても、呼び出し側コードは一切修正不要です。

### ZoomacIt の実例: get / set 両方持つ computed property

`Settings` クラスは、`UserDefaults` (キー文字列ベースのキー・バリュー永続化機構) という生 API を、型安全なプロパティアクセスに変換するレイヤーとして実装されています。すべての設定値は computed property として宣言され、`get` で `UserDefaults` から読み出し、`set` で書き込んでいます。

```swift
// src/ZoomacIt/Models/Settings.swift:164-172 より
var defaultPenColor: PenColor {
    get { PenColor(rawValue: defaults.string(forKey: Keys.defaultPenColor) ?? "") ?? .red }
    set { defaults.set(newValue.rawValue, forKey: Keys.defaultPenColor) }
}

var defaultPenWidth: CGFloat {
    get { CGFloat(defaults.double(forKey: Keys.defaultPenWidth)) }
    set { defaults.set(Double(newValue), forKey: Keys.defaultPenWidth) }
}
```

```swift
// src/ZoomacIt/Models/Settings.swift:191-194 より
var fontWeight: FontWeightOption {
    get { FontWeightOption(rawValue: defaults.string(forKey: Keys.fontWeight) ?? "") ?? .medium }
    set { defaults.set(newValue.rawValue, forKey: Keys.fontWeight) }
}
```

呼び出し側は `Settings.shared.defaultPenColor = .blue` と書くだけで、裏では `UserDefaults` への文字列変換と保存が走ります。Java の `Preferences` API を直接叩く場合と比較すると、型安全性、デフォルト値のフォールバック、列挙体の rawValue 変換まで一行ずつ収まっており、API 利用側の認知負荷が大幅に下がっています。

> **NOTE**: `defaultPenColor` の getter は「文字列を読み出し → `PenColor(rawValue:)` でデコード → デコード失敗時は `.red` にフォールバック」という三段階の処理を、`?? ""` と `?? .red` の二つの nil 結合演算子だけで表現しています。Swift の Optional と nil 結合演算子は、こうした「失敗時のデフォルト値」を簡潔に書く文化を支えています。

---

## 13.3 Property Observer — 値変更の前後をフックする

**property observer** は、stored property の値が変更される直前 (`willSet`) または直後 (`didSet`) に呼び出されるブロックです。値の変更をトリガーに副作用を発生させたい場合に使います。

### 基本構文

```swift
var temperature: Double = 0 {
    willSet {
        print("about to change from \(temperature) to \(newValue)")
    }
    didSet {
        print("changed from \(oldValue) to \(temperature)")
    }
}
```

- `willSet` の中では、新しい値が暗黙の名前 `newValue` で参照できます。`temperature` 自身はまだ古い値です。
- `didSet` の中では、古い値が暗黙の名前 `oldValue` で参照できます。`temperature` はすでに新しい値に更新されています。

引数名は `willSet(myNewValue)` / `didSet(myOldValue)` のように変更可能ですが、慣例として `newValue` / `oldValue` のままにすることがほとんどです。

### Java との比較

Java で同じことをするには、setter の中に手でロジックを書くか、JavaBeans の `PropertyChangeSupport` を組み込む必要がありました。

```java
public final class Thermostat {
    private double temperature;
    private final PropertyChangeSupport support = new PropertyChangeSupport(this);

    public void setTemperature(double newValue) {
        double oldValue = this.temperature;
        this.temperature = newValue;
        support.firePropertyChange("temperature", oldValue, newValue);
    }

    public void addPropertyChangeListener(PropertyChangeListener l) {
        support.addPropertyChangeListener(l);
    }
}
```

Swift の `willSet` / `didSet` は、これを **言語仕様レベルで提供** するだけでなく、外部からのリスナー登録という間接化も省略します。値の変更に応じて UI を再描画する、ログを書く、依存する派生値を再計算する、といったユースケースに直接当てはまります。

### 重要な制約: stored property のみ

property observer は **stored property にしか付けられません**。computed property に対しては `set { ... }` の中で同等の処理を書くため、observer は不要 (むしろ二重の意味を持ってしまう) という設計判断です。

```swift
// これはコンパイルエラー
var area: CGFloat {
    get { width * height }
    set { /* ... */ }
    didSet { print("changed") }   // computed property には付けられない
}
```

副作用を発生させたい場合は、computed property の `set` ブロックの中に直接書きます。

### 重要な制約: 初期化中は呼ばれない

`init` の中で初期値を設定するときには、observer は **呼ばれません**。observer が反応するのは、インスタンスが完全に初期化された後の代入だけです。これは Java の setter と決定的に違う点で、初期化処理と通常の更新処理を観念的に区別する Swift の哲学を反映しています。

### ハンズオン例

ZoomacIt の現コードベースには直接的な observer 利用箇所はありませんが、たとえば `DrawingState.penWidth` に observer を加えれば、ペン幅変更を即座に UI へ反映する仕組みを言語機能だけで構築できます。

```swift
final class DrawingState {
    var penWidth: CGFloat = 3.0 {
        didSet {
            NSLog("[DrawingState] penWidth changed: \(oldValue) -> \(penWidth)")
            NotificationCenter.default.post(name: .penWidthDidChange, object: nil)
        }
    }
}
```

呼び出し側は `state.penWidth = 5.0` と書くだけ、`set` メソッドを呼ぶ必要も、PropertyChangeSupport を組み込む必要もありません。

> **NOTE**: `didSet` 内で `self.penWidth = ...` のように同じプロパティへ代入してもループしません。observer 内部からの書き込みは observer を再帰的に発火させない、というルールが言語仕様で保証されています。

---

## 13.4 Lazy Property — 初回アクセスまで初期化を遅延する

**lazy property** は、宣言時には初期化せず、最初にアクセスされた時点で初めて初期化される stored property です。`lazy` キーワードを `var` の前に付けます。

### 基本構文

```swift
final class ImageProcessor {
    lazy var heavyResource: ResourceCache = ResourceCache.loadFromDisk()
}
```

`heavyResource` は、`processor.heavyResource` が初めて呼ばれた瞬間に `ResourceCache.loadFromDisk()` が走り、結果が保存されます。二回目以降は保存された値が返されます。

### なぜ var なのか

`lazy let` は許されません。lazy property は「未初期化 → 初期化済み」という状態遷移を内部的に持つため、不変として宣言できないという設計上の制約があります。

### Java との比較

Java で同等の遅延初期化を書くと、スレッドセーフ性まで考慮した double-checked locking パターンが必要になります。

```java
public final class ImageProcessor {
    private volatile ResourceCache heavyResource;

    public ResourceCache getHeavyResource() {
        ResourceCache local = heavyResource;
        if (local == null) {
            synchronized (this) {
                local = heavyResource;
                if (local == null) {
                    heavyResource = local = ResourceCache.loadFromDisk();
                }
            }
        }
        return local;
    }
}
```

Swift の `lazy var` は、これを **キーワード一つ** に圧縮します。

### 重要な制約: スレッドセーフではない

ただし、Swift の `lazy var` はスレッドセーフではありません。複数スレッドから同時にアクセスされた場合、初期化処理が複数回走る可能性があります。マルチスレッド環境で安全に遅延初期化したい場合は、`DispatchQueue` や `NSLock`、Swift Concurrency の `actor` などを別途用いる必要があります。

### 重要な制約: 構造体での副作用

`lazy var` は、構造体 (struct) でも宣言できますが、初回アクセスがプロパティの「変更」とみなされるため、`var` で保持していないと呼び出せません。

```swift
struct Container {
    lazy var data: [Int] = (0..<1000).map { $0 * 2 }
}

let c = Container()
// print(c.data)  // コンパイルエラー: 'let' で保持しているため変更不可
var c2 = Container()
print(c2.data)   // OK
```

クラスを使えばこの制約はありません。

### ユースケース

- 計算が重い初期値 (大きな配列の生成、ファイル読み込みなど)
- 自分自身のほかのプロパティに依存する初期値 (`init` の段階では `self` が完全には使えない場面)
- 必要にならない可能性がある資源の初期化

ZoomacIt 内では現状 lazy 利用箇所はありませんが、たとえば「設定ダイアログで使う巨大な選択肢リスト」「アプリ起動直後には必要ないキャッシュ」などに適しています。

---

## 13.5 Type Property — クラス・構造体に紐づくプロパティ

**type property** は、インスタンスではなく **型そのもの** に紐づくプロパティです。Java の `static` field と同じ役割で、Swift では `static` キーワードを付けて宣言します。

### 基本構文

```swift
struct PhysicsConstants {
    static let speedOfLight: Double = 299_792_458
    static var iterationCount: Int = 0
}

print(PhysicsConstants.speedOfLight)
PhysicsConstants.iterationCount += 1
```

インスタンスを生成せず、型名から直接アクセスします。

### ZoomacIt の実例: シングルトン

`Settings` クラスはアプリ全体で一つの設定インスタンスを共有するため、典型的なシングルトンパターンを `static let` で実装しています。

```swift
// src/ZoomacIt/Models/Settings.swift:47-55 より
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        registerDefaults()
    }
    // ...
}
```

ポイントは三つあります。

1. `static let shared = Settings()` で型に紐づく定数として一つだけインスタンスを生成。
2. `private init()` でクラス外部からの追加インスタンス生成を禁止。
3. `static let` の初期化は **Swift ランタイムによって自動的にスレッドセーフ** に行われる (Java の static initializer 相当)。double-checked locking を書く必要がありません。

呼び出し側は `Settings.shared.defaultPenColor` のように書きます。実コード中の `DrawingState` も `Settings.shared.defaultPenColor` を参照していますね (`DrawingState.swift:37`)。

### class var による override 可能版

通常の `static` プロパティはサブクラスで override できません。サブクラスで上書き可能な type property を宣言したい場合は、`class var` (computed property のみ) を使います。

```swift
class Vehicle {
    class var description: String { "a generic vehicle" }
}

final class Bicycle: Vehicle {
    override class var description: String { "a bicycle" }
}

print(Vehicle.description)  // "a generic vehicle"
print(Bicycle.description)  // "a bicycle"
```

`class var` は computed property に限られ、stored property の `class let` / `class var` は許されません。stored type property を持ちたい場合は `static` のみが選択肢になります。

### 構造体・列挙体での type property

type property はクラスだけでなく、struct や enum でも使えます。`PenColor` 列挙体を拡張するなら次のようになります。

```swift
extension PenColor {
    static let allDisplayNames: [String] = PenColor.allCases.map { $0.rawValue.capitalized }
}
```

> **NOTE**: 列挙体に `static func` でファクトリメソッドを生やすパターンも頻出です。実際 `PenColor.from(character:)` (`DrawingState.swift:19`) は `static func` で実装されており、`PenColor.from(character: "R")` のように型名から直接呼べます。これは type method (Ch14 で扱います) ですが、type property と同じく型空間に属するという意味では同じ仲間です。

---

## 13.6 Property Wrapper — アクセサそのものを再利用可能にする

**property wrapper** は、`get` / `set` のロジックを別の型に切り出し、複数のプロパティで再利用するための仕組みです。`@propertyWrapper` 属性を付けた型を定義し、`@MyWrapper` のように呼び出し先のプロパティに付与します。

### 概念だけ理解しておく

property wrapper を本格的に書く機会は少なく、まず利用者として SwiftUI の `@State`、`@Binding`、`@Published`、`@Environment` などを通じて触れることがほとんどです。これらはすべて property wrapper として実装されています。

```swift
// SwiftUI の世界 (詳細は Part III)
struct ContentView: View {
    @State private var count: Int = 0

    var body: some View {
        Button("Tapped \(count) times") { count += 1 }
    }
}
```

`@State` を付けたプロパティは、見た目は普通の `var count` ですが、実際には wrapper 内部で値の変更を検知し、SwiftUI に再レンダリングを通知する処理が走っています。Java で同じことを言語内で表現する方法はなく、アノテーションプロセッサや AspectJ といった外部ツールに頼る必要がありました。Swift は wrapper を **言語の一級機能** として組み込んでいる点で大きく異なります。

### 自作する場合の最小例 (参考)

```swift
@propertyWrapper
struct Clamped {
    private var value: CGFloat
    let range: ClosedRange<CGFloat>

    init(wrappedValue: CGFloat, _ range: ClosedRange<CGFloat>) {
        self.range = range
        self.value = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }

    var wrappedValue: CGFloat {
        get { value }
        set { value = min(max(newValue, range.lowerBound), range.upperBound) }
    }
}

struct Pen {
    @Clamped(1...50) var width: CGFloat = 3.0
}
```

`Pen.width` に `100` を代入しても、wrapper が `50` にクランプしてくれます。この仕組みは ZoomacIt の `DrawingState.increasePenWidth()` (`DrawingState.swift:88-90`) で `min(penWidth + 1.0, 50.0)` のように手書きされている処理を、wrapper としてまとめれば再利用可能になります。

> **NOTE**: 詳細は本書 Part III の SwiftUI 章で扱います。本章の段階では「`@State` のような `@` 付きプロパティは property wrapper という仕組みで動いている」ということだけ覚えておけば十分です。

---

## 13.7 ZoomacIt 実コード読解: Settings.swift を俯瞰する

ここまで学んだ知識を使って、`Settings` クラスを最初から読んでみましょう。

```swift
// src/ZoomacIt/Models/Settings.swift より抜粋
final class Settings: @unchecked Sendable {

    // 1. シングルトンインスタンス (type property)
    static let shared = Settings()

    // 2. 内部保持される UserDefaults 参照 (stored property, 不変)
    private let defaults = UserDefaults.standard

    // 3. 外部からの生成を禁止する private init
    private init() {
        registerDefaults()
    }

    // 4. 各設定値は computed property として宣言される
    var defaultPenColor: PenColor {
        get { PenColor(rawValue: defaults.string(forKey: Keys.defaultPenColor) ?? "") ?? .red }
        set { defaults.set(newValue.rawValue, forKey: Keys.defaultPenColor) }
    }

    var defaultPenWidth: CGFloat {
        get { CGFloat(defaults.double(forKey: Keys.defaultPenWidth)) }
        set { defaults.set(Double(newValue), forKey: Keys.defaultPenWidth) }
    }
    // ... 以下、すべての設定値が同じパターンで定義されている
}
```

このクラスは、本章で扱ったプロパティ機能のほとんどを使い分けています。

| 行 | プロパティ | 種別 | 役割 |
|----|-----------|------|------|
| `static let shared` | type property (stored) | クラス全体で唯一のインスタンス |
| `private let defaults` | stored property (不変) | 内部実装の参照を保持 |
| `var defaultPenColor` | computed property | UserDefaults との型安全な橋渡し |
| `var defaultPenWidth` | computed property | 同上、CGFloat と Double の変換も内包 |

なぜ stored property で値を保持せず、毎回 `UserDefaults` から読むのでしょうか。理由は **永続化** です。`UserDefaults` はファイルにバックアップされるキー・バリューストアなので、別プロセスや別バンドル経由での変更にも追随できる必要があります。stored property にキャッシュしてしまうと、外部変更に気付けません。computed property で常に最新値を読み出すことで、シンプルなコードのまま正しい挙動を保証しています。

これは **「呼び出し側の構文を変えずに保存方法を切り替えられる」** という Swift プロパティの設計原則を、現実のコードベースで活かしている好例です。もし将来 `UserDefaults` から SQLite へ移行したくなっても、各プロパティの `get` / `set` を書き換えるだけで、`Settings.shared.defaultPenColor` を呼んでいる側のコード (`DrawingState.swift:37` や `DrawTab.swift` など多数) は一切変更不要です。

### DrawingState との対比

`DrawingState` のほうは、まったく逆のアプローチを取っています。

```swift
// DrawingState.swift より抜粋
final class DrawingState {
    var activeColor: PenColor = Settings.shared.defaultPenColor   // stored
    var penWidth: CGFloat = Settings.shared.defaultPenWidth       // stored
    var isHighlighterMode: Bool = false                           // stored

    var currentNSColor: NSColor {                                 // computed
        let base = activeColor.nsColor
        return isHighlighterMode ? base.withAlphaComponent(...) : base
    }
}
```

`activeColor` や `penWidth` は **描画セッション中だけ存在する短命な状態** であり、永続化は必要ありません。だから stored property として保持し、初期値だけ `Settings.shared` から取得しています。一方 `currentNSColor` は他の二つのプロパティから一意に決まる派生値なので、computed として表現しています。

「永続化が必要 → computed (バックエンド経由)」「セッション内の一時的な状態 → stored」「複数の状態から導出される値 → computed」という三つの判断基準が、同じプロジェクトの中で使い分けられているのが見えてきます。

---

## 13.8 ハンズオン (任意)

`DrawingState` に property observer を追加し、`penWidth` が変更されるたびにログを出力してみましょう。

```swift
final class DrawingState {
    var penWidth: CGFloat = Settings.shared.defaultPenWidth {
        willSet {
            NSLog("[DrawingState] penWidth will change: \(penWidth) -> \(newValue)")
        }
        didSet {
            NSLog("[DrawingState] penWidth did change: \(oldValue) -> \(penWidth)")
        }
    }
}
```

`make build` でビルドし、`make run` でアプリを起動。Draw モード (`⌃2`) に入り、`+` / `-` キーでペン幅を変えながら Console.app でログを観察してみてください。`increasePenWidth()` (`DrawingState.swift:88-90`) を一度呼ぶだけで `willSet` と `didSet` の両方が一回ずつ発火し、`min(penWidth + 1.0, 50.0)` で 50 に張り付いた後は `oldValue == penWidth` のログが続くはずです。

余裕があれば、`activeColor` にも observer を追加し、色変更時にカーソル形状やステータスバーアイコンを変える実装に発展させてみてください。

---

## 章のまとめ

- **stored property**: 値を保存する。`var` (可変) または `let` (不変)。デフォルト値で `init` 省略可。
- **computed property**: `get` / `set` で値を計算。読み取り専用なら `get` キーワード省略可。Java の getter/setter ボイラープレートを言語シュガーに置き換える。
- **property observer**: `willSet` / `didSet` で値変更をフック。`oldValue` / `newValue` が暗黙の名前。**stored property のみ** で利用可、`init` 中は呼ばれない。
- **lazy property**: `lazy var` で初回アクセスまで初期化を遅延。スレッドセーフではない点に注意。`lazy let` は不可。
- **type property**: `static` で型に紐づくプロパティ。`static let` の初期化はランタイムによってスレッドセーフ。サブクラスで override 可能版は `class var` (computed のみ)。
- **property wrapper**: アクセサロジックを切り出して再利用する仕組み。SwiftUI の `@State` 等の正体。詳細は Part III で。

ZoomacIt の `Settings` と `DrawingState` は、本章のすべてのトピックを実コードで体現しています。Swift のプロパティは、Java の field + getter/setter + Lombok アノテーション + PropertyChangeListener + double-checked lazy + static field を、一つの統一構文に再設計したものだと捉えると、その威力が見えてきます。

## 次に読む章

→ [14. Methods](./14-methods.md)
