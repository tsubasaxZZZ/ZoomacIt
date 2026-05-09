# 21. Concurrency

## この章で学ぶこと

- Swift の **並行性 (Concurrency)** モデルが、Java の `Thread` / `synchronized` / `volatile` / `CompletableFuture` といった「ライブラリで提供される並行性」とどう違うかを、設計思想から整理する
- **`async` / `await`** — 非同期関数の宣言と中断点 (*suspension point*) の意味、戻り値ベースの非同期処理
- **`Task`** — 非同期ジョブの単位、`Task { ... }` での起動、`Task.detached`、協調的キャンセル (*cooperative cancellation*)
- **`TaskGroup`** — 構造化並行処理 (*structured concurrency*) による並列実行
- **Actor モデル** — `actor` 型による *データ競合* (*data race*) のコンパイル時防止
- **`@MainActor`** — UI スレッド隔離を型システムで保証する特殊 actor
- **`Sendable` プロトコル** — スレッド境界を越えられる型のマーカー
- **`@unchecked Sendable`** — 既存ライブラリ・C API との接続における現実解
- **Swift 6 の strict concurrency** によるコンパイル時のデータ競合検出
- ZoomacIt の `BreakTimerWindowController`、`Settings`、`HotkeyManager` から実際の使われ方を読む

> **NOTE**
> この章は本書の中で **最も重要かつ最も丁寧に書かれた章のひとつ** です。Swift 6 の strict concurrency は 2026 年現在の Swift 学習における最重要トピックであり、Java 経験者にとっては「`synchronized` を書けば守れる」という思考からの**根本的なパラダイムシフト**を要求します。Swift は並行性に関するバグの大半を **コンパイル時に** 弾くことを設計目標とし、そのために言語そのものに `actor` / `Sendable` / `async`/`await` を組み込みました。これは Java が標準ライブラリ (`java.util.concurrent`) で提供してきた仕組みとは、抽象度が一段違います。

---

## 21.1 Java の並行性との哲学的な違い

まず大局観を掴みましょう。Swift と Java は、並行性に対する **アプローチそのもの** が異なります。

### Java の並行性 — ライブラリで提供される

Java では、並行性の主要部品は **言語ではなくライブラリ** で提供されてきました。

| カテゴリ | Java の機構 | 提供層 |
| --- | --- | --- |
| スレッド | `java.lang.Thread`, `Runnable` | ライブラリ |
| 排他制御 | `synchronized` キーワード, `ReentrantLock` | 言語キーワード + ライブラリ |
| メモリ可視性 | `volatile`, `final` | 言語キーワード |
| 非同期戻り値 | `Future`, `CompletableFuture` | ライブラリ |
| スレッドプール | `ExecutorService` | ライブラリ |
| データ競合検出 | (なし — 実行時にしか分からない) | — |

`synchronized` や `volatile` は言語キーワードですが、その粒度は **ブロック単位・フィールド単位** に留まり、「この型の不変条件を破るアクセスはコンパイル時に弾く」ような型レベルの保護機構はありません。データ競合は **実行してみて初めて分かる** バグになりがちです。

### Swift の並行性 — 言語そのものに組み込まれた

Swift 5.5 (2021) で `async`/`await` と `actor` が導入され、Swift 6 (2024) で strict concurrency が完成しました。Swift は次の機構を **言語コア** に持ちます。

| カテゴリ | Swift の機構 | 提供層 |
| --- | --- | --- |
| 非同期関数 | `async` 修飾子, `await` 演算子 | 言語キーワード |
| 非同期ジョブ単位 | `Task`, `TaskGroup` | 標準ライブラリ (言語密結合) |
| 排他制御 | `actor` 型 | 言語キーワード |
| UI スレッド隔離 | `@MainActor` | 言語属性 |
| 越境可能性マーカー | `Sendable` プロトコル | 言語と密結合した型システム |
| データ競合検出 | **コンパイラが静的に検査** | コンパイル時 |

最後の行が決定的です。Swift 6 では「2 つのスレッドから同じ可変状態に同時アクセスしうる」コードは、**コンパイルが通りません**。Java で実行時にデバッガを張って初めて見つかった race condition が、Swift では `swift build` の段階でエラーになります。

> **NOTE**
> この違いは、世代の違いだと考えるとしっくり来ます。Java の並行性は 1990 年代後半 (Java 1.0, 1.5) の設計で、当時はマルチコアより単一プロセッサが主流でした。Swift の並行性は 2020 年代の設計で、最初からマルチコア・モバイル・GUI スレッド分離を前提にしています。Swift は「Java の `java.util.concurrent` で 25 年かけて分かった教訓を、最初から型システムで強制する」アプローチを採っています。

### この章の進め方

以降では、まず `async`/`await` と `Task` という **「非同期処理を書く側」** の API を学び、続いて `actor` / `@MainActor` / `Sendable` という **「データ競合を防ぐ側」** の機構を学びます。最後に ZoomacIt の実コードで、両者がどう組み合わさっているかを読み解きます。

---

## 21.2 `async` / `await` の基本

### 非同期関数の宣言

時間のかかる処理 (ネットワーク I/O、ディスク I/O、画面キャプチャ、など) を表す関数には **`async`** 修飾子を付けます。

```swift
func fetchData(from url: URL) async -> Data {
    // 時間のかかる処理
}
```

返り値を持つ通常の関数とほぼ同じ宣言ですが、`async` キーワードが追加されている点に注目してください。これは「この関数は途中で **中断 (suspend) する可能性がある**」というマーカーです。

エラーを投げる場合は `async throws` を付けます (Ch10/Ch20 で扱った `throws` と組み合わせるだけです)。

```swift
func fetchData(from url: URL) async throws -> Data {
    // ネットワークエラーなら throw する
}
```

### `await` で呼び出す

`async` 関数を呼び出すには **`await`** キーワードが必要です。

```swift
let data = await fetchData(from: someURL)
```

`async throws` であれば `try await` を組み合わせます。

```swift
let data = try await fetchData(from: someURL)
```

### Java との対応

Java の `CompletableFuture` で同じことを書くと次のようになります。

```java
// Java
CompletableFuture<Data> future = fetchDataAsync(url);
future.thenAccept(data -> {
    // data を使う
}).exceptionally(ex -> {
    // エラー処理
    return null;
});
```

Swift の `await` は本質的に `thenCompose` / `thenAccept` のチェーンを **手続き的に書ける構文糖衣** です。読みやすさが段違いです。

```swift
// Swift
do {
    let data = try await fetchData(from: url)
    // data を使う (返り値が直接ローカル変数に入る)
} catch {
    // エラー処理 (try/catch と統合)
}
```

### `await` は何を意味するのか — 中断点 (*suspension point*)

`await` は単なる「待つ」ではありません。正確には **「ここで現在のタスクを中断してよい (= スレッドを他の仕事に明け渡してよい)」というマーカー** です。

```text
時間軸 →
スレッド A: [task1 実行中] ─ await ─ [他の task 実行中] ─── [task1 再開]
                              ↑                            ↑
                              中断点                       resume
```

Java のスレッドが I/O 待ちで「ブロック (= スレッドそのものが寝る)」のと違い、Swift の `await` は **タスクを論理的に止めるだけで、スレッドはプールに返却されて他のタスクを処理できます**。これによって、少数のスレッドで多数の非同期タスクを効率的にさばけます (いわゆる cooperative scheduling)。

> **NOTE**
> この挙動は Kotlin の `suspend` 関数や C# の `async`/`await`、JavaScript の `async`/`await` に近いものです。Java も Project Loom で virtual thread が導入されましたが、思想は別です (Java は「スレッドを軽量化する」、Swift は「スレッドを意識させない」アプローチ)。

### どこから `await` を呼べるか

`await` は **`async` 関数の中**、または **`Task { ... }` ブロックの中** からしか書けません。同期関数の中で `await` を呼ぶことはできません。次節の `Task` がそのブリッジになります。

---

## 21.3 `Task` — 非同期ジョブの単位

`Task` は **非同期処理の実行単位** です。同期コードから非同期処理へ橋渡しするのにも使います。

### 基本形

```swift
Task {
    let data = try await fetchData(from: url)
    print("取得完了: \(data.count) bytes")
}
```

これで「`fetchData` を非同期で実行する」ジョブが起動し、`Task { ... }` の呼び出し自体は即座に戻ります。Java で言えば次のような書き方の代替です。

```java
// Java
new Thread(() -> {
    Data data = fetchData(url);
    System.out.println("取得完了: " + data.length);
}).start();
```

ただし `Task` は **OS スレッドではありません**。Swift ランタイムが管理する軽量なジョブで、内部で **協調的スケジューラ** によって実スレッドに割り当てられます。

### `Task` の戻り値を待つ

`Task` 自体も値オブジェクトです。`.value` プロパティで結果を取り出せます。

```swift
let task = Task {
    return try await fetchData(from: url)
}
let data = try await task.value
```

### `Task.detached` — 親コンテキストから切り離す

通常の `Task { ... }` は、起動元の actor 隔離・優先度・タスクローカル値を **継承** します (これが「構造化並行処理」の基本です)。一方 **`Task.detached`** はそれらを **継承しません**。

```swift
Task.detached {
    // 親の actor 隔離を引き継がない、独立したジョブ
    let data = try await fetchData(from: url)
}
```

`Task.detached` は強力ですが、構造化並行処理のメリット (キャンセル伝播、優先度伝播) を失うため **多用しないのが原則** です。「どうしても親から独立したジョブを走らせたい」場合の最終手段と捉えてください。

### キャンセル — 協調的キャンセル (*cooperative cancellation*)

Swift のキャンセルは **協調的** です。`task.cancel()` を呼んでもタスクが強制停止されるわけではなく、「キャンセル要求が立った」ことが伝わるだけです。タスク側が定期的に `Task.checkCancellation()` を呼ぶか、`Task.isCancelled` を確認することで、自主的に処理を中断する責務があります。

```swift
let task = Task {
    for i in 0..<1000 {
        try Task.checkCancellation()  // キャンセル要求があれば throw
        await processItem(i)
    }
}

// あとでキャンセル
task.cancel()
```

Java の `Thread.interrupt()` の思想に近く、`Thread.stop()` のような強制終了は提供されません。スレッド強制停止が招く中途半端な状態を避けるためです。

---

## 21.4 `TaskGroup` — 構造化並行処理による並列実行

複数の非同期処理を **並列に走らせて、すべての結果を集めたい** 場合は `TaskGroup` を使います。

### 基本形

```swift
func fetchAll(urls: [URL]) async throws -> [Data] {
    try await withThrowingTaskGroup(of: Data.self) { group in
        for url in urls {
            group.addTask {
                try await fetchData(from: url)
            }
        }

        var results: [Data] = []
        for try await data in group {
            results.append(data)
        }
        return results
    }
}
```

`withThrowingTaskGroup` で `group` を作り、`group.addTask { ... }` で子タスクを追加します。`for try await data in group` で結果を順次受け取れます。

### Java との対応

Java の `CompletableFuture.allOf` と `thenApply` の組み合わせに相当します。

```java
// Java
List<CompletableFuture<Data>> futures = urls.stream()
    .map(url -> CompletableFuture.supplyAsync(() -> fetchData(url)))
    .toList();

CompletableFuture<Void> all = CompletableFuture.allOf(
    futures.toArray(new CompletableFuture[0])
);
all.thenAccept(v -> {
    List<Data> results = futures.stream()
        .map(CompletableFuture::join)
        .toList();
    // results を使う
});
```

Swift の `TaskGroup` のほうが、エラー伝播・キャンセル伝播・スコープ内での生存保証 (子タスクは必ず `withThrowingTaskGroup` のブロックを抜ける前に完了する) のすべてが言語レベルで保証されます。これが「構造化並行処理」の意味するところです。

### 構造化並行処理とは

```text
親タスク
  ├── 子タスク 1 (TaskGroup 内)
  ├── 子タスク 2 (TaskGroup 内)
  └── 子タスク 3 (TaskGroup 内)
       ↑
       親が抜ける前に、すべての子の完了が型システムで保証される
       親がキャンセルされたら、子にも伝わる
```

Java のスレッドが「親子関係を持たない」 (= ある `Thread` がもう片方の `Thread` の親かどうかをランタイムは知らない) のに対し、Swift の `Task` / `TaskGroup` は **親子関係を構造化** し、コンパイラとランタイムが協調してリーク・取り残しを防ぎます。

---

## 21.5 Actor モデル — データ競合を型システムで防ぐ

ここまでは「非同期処理の書き方」でした。ここからが Swift の真骨頂、「**データ競合を防ぐ仕組み**」です。

### 問題: 共有可変状態

複数のタスクから同じオブジェクトのフィールドを読み書きすると、**データ競合** が起きます。

```swift
// 危険な例
final class Counter {
    var value = 0
    func increment() { value += 1 }   // 複数スレッドから呼ぶと壊れる
}
```

Java では `synchronized` で守りました。

```java
// Java
public class Counter {
    private int value = 0;
    public synchronized void increment() { value++; }
}
```

しかし `synchronized` の付け忘れはコンパイル時に検出できません。**プログラマの規律に頼る** モデルです。

### Swift の解 — `actor`

Swift では `class` の代わりに **`actor`** を使うと、**型システムが排他制御を強制** してくれます。

```swift
actor Counter {
    var value = 0

    func increment() {
        value += 1
    }
}
```

文法は `class` とほぼ同じですが、決定的に違うのは **外部からのアクセス方法** です。

```swift
let counter = Counter()

// 外から呼ぶには await が必須 (actor 境界をまたぐから)
await counter.increment()
let v = await counter.value   // 読み取りも await が必要
```

### actor の保証

actor 型は次を保証します。

1. **可変状態への外部からの直接書き込みは禁止** — `counter.value = 10` のような外からの代入はコンパイルエラー
2. **メソッド呼び出しは直列化** — actor 内のコードは同時に複数走らない (Swift ランタイムが保証)
3. **境界をまたぐ呼び出しには `await` が必須** — コンパイラが強制する

これにより、actor 内の状態は「外からは読めるが書けない」「メソッド経由のアクセスは直列化される」という性質を **言語レベルで** 持ちます。Java で `private` フィールドをすべて `synchronized` メソッドでラップする規律を、Swift では `actor` キーワード一つで強制できる、と考えると分かりやすいでしょう。

### actor 隔離 (*actor isolation*) の概念図

```text
   ┌─────────── actor Counter ─────────────┐
   │                                        │
   │   var value = 0    ← 外から直接アクセス│ ← コンパイルエラー
   │                                        │
   │   func increment() {                   │
   │       value += 1   ← 内部からは自由   │
   │   }                                    │
   │                                        │
   └────────────────────────────────────────┘
              ▲
              │ await counter.increment()
              │ (境界を越えるので必ず await)
              │
        外部のタスク
```

actor の境界は **「await しないと越えられない」** 線です。コンパイラがこの線を見張り、線をまたぐコードがあれば必ず `await` を要求します。

### actor 隔離の連鎖

actor のメソッドが返した参照を別の場所で使う場合も、それが actor 内の可変状態を指すなら、引き続き actor 隔離下に置かれます。これにより「actor の内部状態を外に持ち出して並行アクセスする」抜け穴を防いでいます。

---

## 21.6 `@MainActor` — UI スレッド隔離を型システムで保証する

GUI フレームワーク (AppKit / UIKit / SwiftUI) は **UI 操作はメインスレッドからのみ行う** という規約があります。Java Swing でも同じで、`SwingUtilities.invokeLater(...)` で EDT (Event Dispatch Thread) に切り替える必要がありました。

### Java Swing の世界

```java
// Java Swing
SwingUtilities.invokeLater(() -> {
    label.setText("更新");   // EDT でしか触れない
});
```

ただし、これも **規約** です。EDT 以外から `setText` を呼んでもコンパイルエラーにはならず、たまたま動いてしまうこともあります。

### Swift の解 — `@MainActor`

Swift には **メインスレッドに対応する特殊な actor** が組み込まれており、それを `@MainActor` 属性で型・関数・プロパティに付けられます。

```swift
@MainActor
final class BreakTimerWindowController {
    private var timerWindow: BreakTimerWindow?
    // ... メインスレッドからしかアクセスできないと型システムが保証
}
```

このクラスのメソッド・プロパティは、**メインスレッド (= MainActor) 以外からのアクセスがコンパイルエラー** になります。Java Swing で「規約」だったものが、Swift では **コンパイラが守ってくれるルール** になっています。

> **NOTE**
> Java 経験者にとって `@MainActor` は **「Swing の EDT 規約を言語化したもの」** と捉えるのが最も腑に落ちます。`SwingUtilities.invokeLater` を書き忘れたら実行時に `IllegalStateException` (あるいは何も起きないが画面が壊れる) になっていた問題を、Swift では型システムが先に弾きます。

### `@MainActor` の境界をまたぐ

別の actor やバックグラウンドタスクから `@MainActor` のコードを呼ぶには `await` が必要です。

```swift
Task.detached {
    let data = try await fetchData(from: url)

    await MainActor.run {
        label.stringValue = "更新: \(data.count) bytes"
    }
}
```

または **Task の起動時に actor を指定** することもできます (ZoomacIt の実コードで多用される形)。

```swift
Task { @MainActor in
    let img = await captureScreen()
    self.imageView.image = img   // メインアクターなので OK
}
```

### `@MainActor` と通常 actor の図

```text
   ┌─── @MainActor (メインスレッド) ────┐
   │                                      │
   │   UI コード (AppKit/SwiftUI)         │
   │   - label.text = ...                 │
   │   - window.makeKeyAndOrderFront      │
   │                                      │
   └──────────────────────────────────────┘
              ▲
              │ await でメインアクターへ復帰
              │
   ┌─── 別の actor / Task.detached ──────┐
   │                                      │
   │   バックグラウンド計算                │
   │   - データ取得                        │
   │   - 画像処理                          │
   │                                      │
   └──────────────────────────────────────┘
```

UI コードは常に上の領域に閉じ込められ、データ取得は下の領域で動く、という構造が **型システムで強制** されます。

---

## 21.7 `Sendable` プロトコル — 越境可能性のマーカー

actor 境界・タスク境界をまたいで **値を渡す** とき、その値は **スレッドセーフでなければなりません**。Swift はこれを **`Sendable` プロトコル** で表現します。

### `Sendable` とは

`Sendable` は **「この型の値は並行コンテキストの境界を越えて安全に渡せる」** ことを示すマーカープロトコル (要件メソッドなし) です。

```swift
public protocol Sendable {}
```

メソッドはありません。ただ「私はスレッド境界を越えてもよい型です」と宣言するだけのプロトコルです。

### 自動適合される型

次の型は **自動的に Sendable** になります (プログラマが書く必要なし)。

- 値型の `struct` / `enum` で、すべてのプロパティが `Sendable`
- すべての基本型 (`Int`, `Double`, `String`, `Bool`, など)
- イミュータブルな `let` プロパティのみを持つ `final class`
- `actor` 型 (定義上スレッドセーフ)
- 関数型のうち `@Sendable` 修飾されたクロージャ

```swift
struct Point: Sendable {       // 自動的に Sendable
    let x: Double
    let y: Double
}

actor Counter {                 // actor は自動的に Sendable
    var value = 0
}
```

### 自動適合されない型

通常の `class` (可変状態を持ち得る) は **自動では Sendable ではありません**。

```swift
final class MutableBox {
    var value = 0
}

func send(_ box: MutableBox) {
    Task {
        box.value += 1   // ← Swift 6 ではコンパイルエラー
    }
}
```

このコードは Swift 6 の strict concurrency でエラーになります。`MutableBox` が `Sendable` を満たさないため、別のタスクへ渡せません。

### Sendable な値が境界を越える図

```text
        Task A                                 Task B
   ┌────────────┐                          ┌────────────┐
   │            │   Sendable な値 ✓        │            │
   │   value ───┼────────────────────────→ │ → 受け取り │
   │            │                          │            │
   └────────────┘                          └────────────┘

        Task A                                 Task B
   ┌────────────┐                          ┌────────────┐
   │            │   非 Sendable な値 ✗     │            │
   │   value ───┼─── ✗ コンパイルエラー →  │            │
   │            │                          │            │
   └────────────┘                          └────────────┘
```

コンパイラが境界を見張り、安全でない値の越境を **静的に拒否** します。

### Java との比較

Java では「このオブジェクトは複数スレッドから安全か」を表す **型レベルの仕組みがありません**。`@ThreadSafe` のようなアノテーション (FindBugs/SpotBugs) はありますが、コンパイラには伝わらない情報でした。Swift の `Sendable` は **コンパイラが解釈する** マーカーで、違反は型エラーとして検出されます。

### `enum` の Sendable

ZoomacIt の `Settings.swift` に登場する次の `enum` を見てみましょう。

```swift
enum FontWeightOption: String, CaseIterable, Sendable {
    case ultraLight
    case thin
    // ...
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:5-14

`Sendable` を明示的に宣言していますが、実は **値型の enum で associated value もないため、自動でも Sendable** になります。明示すると意図が読み手に伝わるので、ライブラリ的なコードでは書いておくのが望ましいです。

---

## 21.8 `@unchecked Sendable` — 現実解としての逃げ道

ここまで「Sendable は型システムでスレッド安全性を保証する」と説明してきました。しかし、現実のコードベースには次のようなケースが山ほどあります。

- **`UserDefaults`** など、Apple 公式が「内部でスレッドセーフ」と保証しているがコンパイラには伝わらない API
- **Carbon API** など、C 言語ベースで Sendable 概念がそもそも存在しない API
- **シングルトン** として `static let shared = ...` で保持される、可変状態を抱えるが内部で同期している型

これらを actor 化したり、すべての可変フィールドを actor に移したりするのは、現実的に途方もないリファクタになります。Swift はそのための逃げ道として **`@unchecked Sendable`** を提供します。

### 構文

```swift
final class Settings: @unchecked Sendable {
    // ...
}
```

`@unchecked Sendable` を付けると、コンパイラはその型を **Sendable として扱いますが、内部のスレッド安全性はチェックしません** (= プログラマの責任になります)。

### ZoomacIt の実例 — `Settings`

ZoomacIt の `Settings` クラスは `@unchecked Sendable` を採用しています。

```swift
/// Centralized settings manager backed by UserDefaults.
/// Thread-safe (UserDefaults is thread-safe).
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    private let defaults = UserDefaults.standard
    // ...
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:45-55

このクラスは `UserDefaults` のラッパーで、シングルトン (`shared`) として全モジュールから読み書きされます。`UserDefaults` 自体が Apple によって「スレッドセーフ」と公式に保証されているため、`Settings` も実質スレッドセーフです。しかしコンパイラはそれを知らないので、`Sendable` を満たさないと判定します。

そこで `@unchecked Sendable` を付けて「私はスレッドセーフです、責任は取ります」とコンパイラに告げています。

> **NOTE**
> 本来は `actor Settings` として書くか、設定値を全部 `Sendable` な値型に切り出して `actor` 経由で渡すのが Swift 6 の理想形です。しかしここでは **UserDefaults との連携と既存 API 互換** のため、`@unchecked Sendable` を選んでいます。これは「ベストプラクティスではないが、現実的に必要な場面がある」ことを示す代表例です。リファクタの優先度が下がるため、新規コードでは可能な限り `actor` か値型 + `Sendable` を選び、`@unchecked` は **既存資産との橋渡し** に限定するのが望ましいです。

### ZoomacIt の実例 — `HotkeyManager`

もう一例、`HotkeyManager` も `@unchecked Sendable` です。

```swift
/// Manages global hotkeys using the Carbon RegisterEventHotKey API.
/// Does NOT require Accessibility permission.
final class HotkeyManager: @unchecked Sendable {

    static let shared = HotkeyManager()
    // ...
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:4-8

こちらは **Carbon API (`RegisterEventHotKey`)** との連携が理由です。Carbon は C 言語の API で、Swift の actor / Sendable 概念とは無縁の世界です。グローバルなホットキー登録という性質上、シングルトンでなければならず、かつ C コールバックから呼ばれるため、`@unchecked Sendable` が現実解となります。

### `@unchecked Sendable` の使いどころまとめ

| 状況 | `@unchecked Sendable` を使う妥当性 |
| --- | --- |
| Apple 公式 API (UserDefaults など) のラッパー | ◯ 妥当 |
| Carbon / C ライブラリとの橋渡し | ◯ 妥当 |
| 自分で書いた新規ロジック | ✗ 避ける (actor か値型を選ぶ) |
| 「面倒だから」 | ✗ 絶対に避ける |

`@unchecked` は型システムの保証を **無効化** する強力な道具です。使ったら必ずコメントで「なぜ unchecked にしたか」を残すのが礼儀です。

---

## 21.9 Swift 6 strict concurrency によるコンパイル時のデータ競合検出

Swift 6 では **strict concurrency checking** がデフォルトで有効になり、データ競合を **コンパイル時に検出** します。

### 検出される代表的なエラー

#### 1. 非 Sendable な型を Task 境界で渡す

```swift
final class Box {       // Sendable ではない
    var value = 0
}

let box = Box()
Task {
    box.value += 1      // ← エラー: Box is not Sendable
}
```

#### 2. actor の状態を await なしで触る

```swift
actor Counter {
    var value = 0
}

let counter = Counter()
print(counter.value)    // ← エラー: actor-isolated property requires await
```

#### 3. `@MainActor` の関数を別 actor から await なしで呼ぶ

```swift
@MainActor func updateUI() { ... }

actor Worker {
    func doWork() {
        updateUI()      // ← エラー: must call across actor with await
    }
}
```

### Swift 5 と Swift 6 の違い

| バージョン | データ競合検出 |
| --- | --- |
| Swift 5.5 〜 5.9 | actor / Sendable は導入済みだが、警告のみ (オプトインで strict 化可能) |
| Swift 6.0 (2024) | デフォルトで strict、**警告がエラーに昇格** |

ZoomacIt は Swift 6 + macOS 26+ を対象としており、`project.yml` で strict concurrency が有効です。本書のコード例も Swift 6 の挙動を前提としています。

> **NOTE**
> Java で 25 年かけて学んだ「並行性のバグは実行時に偶発的に発現する、テストでは捕まえにくい、本番でだけ起きる」という苦い経験を、Swift は **言語レベルで先回り** して解決しました。これは単なる便利機能ではなく、**並行プログラミングの方法論そのものの転換** です。Swift で書いている限り、データ競合に関しては Java のそれより遥かに堅牢なコードが書けます。

---

## 21.10 旧 API (`DispatchQueue`) との関係

Swift 5.5 以前は、並行性の標準は **GCD (Grand Central Dispatch)** でした。`DispatchQueue.main.async { ... }` はその代表で、Java Swing の `SwingUtilities.invokeLater` に対応する書き方です。

```swift
// 旧 API (GCD)
DispatchQueue.main.async {
    label.stringValue = "更新"
}
```

これは現在も動きますが、**新規コードでは原則 `Task { @MainActor in ... }` または `await MainActor.run { ... }` を使う** のが推奨です。actor / Sendable と協調しないため、Swift 6 strict concurrency 下では型安全性が落ちます。

### ZoomacIt の例 — Carbon C コールバックから main へ

ただし、`HotkeyManager` には次のコードが残っています。

```swift
fileprivate func handleHotKeyEvent(_ event: EventRef) {
    // ...
    if hotKeyID.id == zoomHotKeyID {
        DispatchQueue.main.async { [weak self] in
            self?.onZoomHotkey?()
        }
    }
    // ...
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:153-181

ここで `DispatchQueue.main.async` が使われているのは、**Carbon の C 言語コールバックから呼ばれる** という特殊な文脈だからです。C コールバックは Swift の actor / Task の概念を一切知らず、任意のスレッドで実行されます。そこから安全にメインスレッドへ橋渡しする最短経路が `DispatchQueue.main.async` です。

> **NOTE**
> `DispatchQueue.main.async` は「過去の遺産」というより「**Swift の概念外の世界 (C/Carbon/古いコールバック API) との橋渡し**」として今も価値を持つ API です。新規の純粋 Swift コードで使う必然性はほぼなくなりました。

---

## 21.11 ZoomacIt 実コード読解

ここまで学んだ概念が、実際のコードでどう組み合わさっているかを、`BreakTimerWindowController` を例に追います。

### `@MainActor` クラスとしての宣言

```swift
/// Manages the lifecycle of the Break Timer overlay window.
@MainActor
final class BreakTimerWindowController {

    private var timerWindow: BreakTimerWindow?
    private var timerView: BreakTimerView?
    // ...
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:5-11

クラス全体に `@MainActor` を付けています。これにより、**このクラスのすべてのメソッド・プロパティはメインスレッドからしか呼べない** ことが型システムで保証されます。AppKit (`NSWindow`, `NSView`, `NSScreen`) は当然メインスレッド前提なので、これが型安全な書き方です。

### `Task { @MainActor in ... }` で非同期処理を起動

`showTimer()` の中で、画面キャプチャを非同期に走らせる箇所を見ます。

```swift
if state.background == .fadedDesktop {
    let screenNumber = screen.deviceDescription[...] as? CGDirectDisplayID ?? CGMainDisplayID()
    let scaleFactor = screen.backingScaleFactor
    let screenFrame = screen.frame

    Task { @MainActor in
        let captured = await Self.captureScreenImage(
            displayID: screenNumber,
            width: screenFrame.width,
            height: screenFrame.height,
            scaleFactor: scaleFactor
        )
        self.presentTimer(screen: screen, capturedImage: captured)
    }
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:43-56

ここに **本章のキーコンセプトが凝縮** されています。

1. **`Task { @MainActor in ... }`** — 新しい非同期ジョブを起動。`@MainActor` 指定により、ブロック内のコードは MainActor 隔離下で動く
2. **`await Self.captureScreenImage(...)`** — `async` 関数の呼び出し。中断ポイント。ここで他のタスクが走る可能性がある
3. **`self.presentTimer(...)`** — await から再開後、引き続き MainActor 上で動く。`@MainActor` クラスのメソッドを安全に呼べる

Java の `SwingUtilities.invokeLater(() -> { ... CompletableFuture.supplyAsync(...).thenAccept(result -> ...) ... })` を、Swift では **手続き的なコードのまま書ける** わけです。

### `async` 関数の本体 — `captureScreenImage`

呼び出されている `captureScreenImage` の本体はこうなっています。

```swift
private static func captureScreenImage(
    displayID: CGDirectDisplayID,
    width: CGFloat,
    height: CGFloat,
    scaleFactor: CGFloat
) async -> CGImage? {
    guard CGPreflightScreenCaptureAccess() else {
        return nil
    }

    do {
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        // ...
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    } catch {
        return nil
    }
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:185-218

ポイントは次の通りです。

- `static func ... async -> CGImage?` — `async` 関数の宣言。`throws` を付けず、エラーは `do/catch` で潰して `nil` を返している
- `try await SCShareableContent.excludingDesktopWindows(...)` — Apple の ScreenCaptureKit が提供する **本物の async API** をそのまま呼べる
- `try await SCScreenshotManager.captureImage(...)` — 同上、複数の await を直列に並べられる

Java の `CompletableFuture` チェーンを書いていた人は、この **「async 関数の中身がほとんど同期コードと変わらない」** 読みやすさに驚くはずです。

### Settings の Sendable 適合 — `@unchecked` の現実解

```swift
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    private let defaults = UserDefaults.standard
    // ...
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:47-55

`Settings.shared` は `BreakTimerWindowController`、`HotkeyManager`、`StatusBarController` など、複数の actor / Task コンテキストから自由に読み書きされます。これらの呼び出しを `await` 越しに書き換えるのは現実的ではないため、`UserDefaults` の組み込みスレッドセーフ性に乗っかって `@unchecked Sendable` で逃げています。

> **NOTE**
> 本来は `actor Settings` 化や、設定スナップショットを `Sendable` な値型 `struct SettingsSnapshot` として配ることで、`@unchecked` を排除できます。しかしリファクタコストと利得のバランスから、現状は `@unchecked` を選んでいます。教科書的に「正しい」かどうかと、現場で「妥当」かどうかは別問題、というのが Swift 6 移行期のリアルです。

### HotkeyManager の Sendable 適合 — Carbon との橋渡し

```swift
final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()
    // ...
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:6-8

こちらは Carbon API (`RegisterEventHotKey`, `InstallEventHandler`) との連携が理由です。C コールバックは Swift の actor 概念を持たず、任意スレッドで呼ばれ得るため、actor 化はできません。`@unchecked Sendable` + 内部での `DispatchQueue.main.async` への即橋渡し、というのが落とし所です。

---

## 21.12 ハンズオン (任意)

理解の定着のため、次のうち興味のあるものを試してみてください。

### 1. 並列ダウンロードの書き比べ

3 つの URL から並列にデータを取得し、すべて取れたら結合する関数を、次の二通りで書いてみてください。

- `async let` を 3 個並べる版 (静的に並列数が決まっている場合に使う糖衣構文)
- `withThrowingTaskGroup` を使う版 (動的に並列数が決まる場合)

```swift
// async let 版のスケルトン
func fetchThree() async throws -> (Data, Data, Data) {
    async let a = fetchData(from: url1)
    async let b = fetchData(from: url2)
    async let c = fetchData(from: url3)
    return try await (a, b, c)
}
```

### 2. actor を作ってみる

スレッドセーフな簡易キャッシュを actor として書いてみてください。

```swift
actor Cache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]

    func get(_ key: Key) -> Value? { storage[key] }
    func set(_ key: Key, _ value: Value) { storage[key] = value }
}
```

複数の `Task` から `await cache.set(...)` / `await cache.get(...)` を呼んで、データ競合エラーが **出ない** ことを確認しましょう。次に同じことを `final class` でやって、Sendable 違反がコンパイル時に出ることを観察すると理解が深まります。

### 3. `@unchecked Sendable` を `actor` に置き換える練習

`Settings` を `actor Settings { ... }` に書き換えると、呼び出し側にどれだけ `await` の波及が起こるかを試してみてください。これが **「リファクタコストが現実的でないため `@unchecked` を選ぶ」判断の体験** になります。

---

## 21.13 まとめ

- Swift の並行性は **言語コアに `async`/`await`、`actor`、`Sendable` を組み込んだ第二世代の設計**。Java の `Thread`/`synchronized`/`CompletableFuture` のライブラリ提供アプローチとは抽象度が違う
- `async`/`await` で **非同期処理を手続き的に** 書ける。`CompletableFuture` のチェーンが直線的なコードに
- `Task` は非同期ジョブの単位。`Task.detached` は親隔離を継承しないので慎重に
- `TaskGroup` で **構造化された並列実行**。子の完了が型システムで保証される
- `actor` は **データ競合を型システムで防ぐ** 言語機構。`synchronized` の付け忘れがそもそも構文上ありえない
- `@MainActor` は **UI スレッド隔離を型システムで保証する特殊 actor**。Java Swing の EDT 規約を言語化したもの
- `Sendable` プロトコルで **越境可能な型** を表現。Swift 6 ではコンパイラが境界を見張る
- `@unchecked Sendable` は **既存ライブラリ・C API との橋渡しのための現実解**。新規コードでは可能な限り避け、使うときは理由をコメントに残す
- ZoomacIt の `BreakTimerWindowController` は `@MainActor` クラス + `Task { @MainActor in ... }` + `async` 関数を組み合わせた典型例。`Settings` と `HotkeyManager` は `@unchecked Sendable` の妥当な使用例

並行性は Swift で **最も丁寧に学ぶ価値のある領域** です。一度この型システムに馴染めば、Java で苦労してきた race condition の多くは Swift では発生しえないバグになります。

---

## 次に読む章

→ [22. Type Casting](./22-type-casting.md)
