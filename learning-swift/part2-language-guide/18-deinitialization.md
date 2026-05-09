# 18. Deinitialization

## この章で学ぶこと

- `deinit` の基本構文 — 引数なし、戻り値なし、parens 不要
- なぜ `deinit` が **class 限定** で、struct / enum には書けないのか
- Java の `finalize()` との決定的な違い — ARC ベースなので **タイミングが予測可能**
- 典型的な用途 — オープンしたファイル、Notification の observer、`Timer` などの解放
- 継承時の挙動 — サブクラスの `deinit` のあとに、自動でスーパークラスの `deinit` が呼ばれる
- ZoomacIt が `deinit` をひとつも実装していない理由を、設計の観点から読み解く

> **NOTE**
> この章は **丁寧解説章 (短め)** です。やることは小さい (`deinit { ... }` を書くだけ) ですが、Java の `finalize` を知っている人ほど誤解しやすいトピックなので、違いだけはきっちり押さえてください。

---

## 18.1 ひとことで

| 言語 | デストラクタ相当 | 呼ばれるタイミング |
| --- | --- | --- |
| Java | `finalize()` (Java 9 以降 deprecated, 18 で削除予定) | GC 任せ。**いつ呼ばれるか保証されない** |
| Swift | `deinit` (class のみ) | 最後の参照が消えた瞬間に **同期的に** 呼ばれる |

Swift には GC がなく、メモリ管理は **ARC (Automatic Reference Counting)** で行われます。クラスインスタンスへの参照カウントが 0 になると、その場でただちに `deinit` が走り、続いてメモリが解放されます。タイミングが決定論的なので、「ファイルを閉じる」「Timer を止める」といった副作用を `deinit` に書いても安全です。

---

## 18.2 `deinit` の基本構文

`deinit` はクラス本体の中に **引数も戻り値もなく** 宣言します。`func` キーワードも、丸括弧も書きません。

```swift
final class TempFile {
    private let handle: FileHandle
    private let url: URL

    init(url: URL) throws {
        self.url = url
        self.handle = try FileHandle(forWritingTo: url)
    }

    func write(_ data: Data) {
        handle.write(data)
    }

    deinit {
        // インスタンスが解放される直前に必ず呼ばれる
        try? handle.close()
        NSLog("[TempFile] closed: \(url.lastPathComponent)")
    }
}
```

呼び出し側は何もしません。最後の参照が消えた瞬間に Swift ランタイムが `deinit` を起動します。

```swift
do {
    let f = try TempFile(url: someURL)
    f.write(payload)
}   // ← このスコープを抜けた瞬間に deinit が走る (同期的)
```

`deinit` を **明示的に呼ぶことはできません**。`f.deinit()` のような呼び出しはコンパイルエラーになります。あくまで「ARC が呼ぶもの」であって、「あなたが呼ぶもの」ではないという設計です。

---

## 18.3 なぜ class 限定なのか

`deinit` は **クラス型でしか書けません**。struct や enum (値型) に `deinit` を宣言するとコンパイルエラーになります。

```swift
struct Box {
    var value: Int
    deinit { }   // error: deinitializers may only be declared within a class
}
```

理由はシンプルです。値型は **代入や引数渡しのたびにコピーされる** ため、「どのインスタンスが最後の 1 個か」を Swift が定義できません。

```swift
var a = Box(value: 1)
var b = a       // ← コピーされる
b.value = 2
// a, b はそれぞれ独立した値。「a の deinit」「b の deinit」をいつ呼ぶ?
```

参照型 (class) の場合は、参照カウントを追いかければ「最後の参照が消えた瞬間」が一意に決まります。だから `deinit` を持てます。値型はそうではないので、そもそも概念が成立しないのです。

| 型 | アイデンティティ | `deinit` |
| --- | --- | --- |
| `class` | 参照で同一性が決まる | あり |
| `struct` / `enum` | 値そのもの。コピー可能 | なし (コンパイルエラー) |

Ch12 の「class と struct の使い分け」で「リソースを管理するなら class」と書いたのは、この `deinit` が書けるかどうかも理由のひとつです。

---

## 18.4 Java の `finalize()` との決定的な違い

Java を書いてきた人がいちばん勘違いしやすいポイントです。**Swift の `deinit` は Java の `finalize()` とは別物** だと考えてください。

| 観点 | Java `finalize()` | Swift `deinit` |
| --- | --- | --- |
| 呼び出しタイミング | **GC に任される。いつ呼ばれるか不定** | 最後の参照が消えた瞬間に **同期的** |
| 呼ばれる保証 | 保証されない (プロセス終了時に呼ばれないこともある) | **必ず呼ばれる** (循環参照でリークしない限り) |
| 副作用の実用性 | 信用できないため「リソース解放」目的には NG。`try-with-resources` を使え、と公式が言う | リソース解放目的に使ってよい |
| 言語仕様上の扱い | Java 9 で `@Deprecated`、Java 18 で削除予定 | 言語の標準機能 |

Java の世界では、ファイルやソケットを閉じるためには `try-with-resources` (`AutoCloseable`) を使うのが正解で、`finalize()` に頼るのは反パターンでした。

Swift では事情が逆で、`deinit` に「閉じる」「止める」を書くのが普通の選択肢のひとつです。理由は ARC が「最後の参照が切れた瞬間」を決定論的に検出できるからです。GC のように「いつかは回収される」ではなく、「**今この瞬間** に回収される」というセマンティクスなので、副作用を書いても安全です。

ただし注意点もあります。

- **循環参照が残ると `deinit` は永遠に呼ばれません**。これが Swift で唯一のメモリリーク経路で、`weak` / `unowned` で対処します (Ch20 で扱います)。
- **`deinit` 内で例外を投げることはできません** (`throws` を付けられない)。Java の `finalize` も同様でしたが、Swift では言語仕様で禁じられています。`try?` でエラーを握りつぶすのが定石です。

---

## 18.5 典型的な用途

ARC は **メモリの解放を完全に自動化** してくれます。子オブジェクトへの参照を nil にするとか、配列を空にするとか、そういう「メモリを返す」目的で `deinit` を書く必要はありません。`deinit` を書くべきなのは、**ARC が面倒を見てくれない外部リソース** を扱っているときだけです。

代表的な 4 ケースを挙げます。

### (1) ファイルディスクリプタなどの OS リソース

```swift
final class LogWriter {
    private let handle: FileHandle
    init(url: URL) throws {
        self.handle = try FileHandle(forWritingTo: url)
    }
    deinit {
        try? handle.close()
    }
}
```

### (2) NotificationCenter の observer 解除

```swift
final class ScreenObserver {
    private var token: NSObjectProtocol?

    init() {
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            NSLog("[ScreenObserver] screens changed")
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
```

ブロックベース observer は self を強参照する可能性があるため、解除し忘れるとリークの原因になります。

### (3) Timer の停止

```swift
final class Heartbeat {
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() { /* ... */ }

    deinit {
        timer?.invalidate()
    }
}
```

`Timer` は RunLoop に強参照されるため、`invalidate()` を呼ばないとオブジェクトが解放されません。

### (4) 借りたリソースの返却 (公式ドキュメントの定番例)

ゲームで「銀行から借りたコイン」を返すような、抽象的なリソース返却にも使われます。

書かない場合の例

```swift
final class Vec3 {
    var x, y, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x; self.y = y; self.z = z
    }
    // deinit 不要 — 解放するメモリだけなら ARC が自動でやる
}
```

「ARC が解放するもの」と「自分で閉じる必要があるもの」を区別するのが、`deinit` を書くか書かないかの判断基準です。

---

## 18.6 継承時の挙動

サブクラスは `deinit` を独自に持てます。スーパークラスにも `deinit` がある場合、Swift は **サブクラスの `deinit` を実行したあと、自動でスーパークラスの `deinit` を呼びます**。`super.deinit()` を明示的に書く必要はありません (むしろ書けません)。

```swift
class Resource {
    deinit { NSLog("Resource.deinit") }
}

final class FileResource: Resource {
    deinit { NSLog("FileResource.deinit") }
}

do {
    _ = FileResource()
}
// 出力:
// FileResource.deinit
// Resource.deinit
```

Java で `super.finalize()` を呼び忘れるとスーパークラスのクリーンアップが走らない、という古典的なバグがありましたが、Swift ではそもそも書けないので起きえません。

スーパークラスのプロパティはサブクラスの `deinit` 内でも有効です。チェーンの最後にメモリが解放されます。

---

## 18.7 ZoomacIt はなぜ `deinit` を 1 つも持たないのか

ZoomacIt のコードベースを `grep -rn "deinit" src/ZoomacIt/` で検索すると、ヒットは **0 件** です。ウィンドウやタイマーや observer を扱うクラスがいくつもあるのに、`deinit` を 1 つも書いていません。

これは「書き忘れ」ではなく、**書く必要がないように設計されている** からです。具体的に 3 つの根拠を見ていきます。

### 根拠 1 — 明示的な `dismiss()` メソッドでクリーンアップを完結させている

`BreakTimerWindowController` は内部で `Timer`、`NSSound`、`NSWindow` を保持しますが、これらの解放は `deinit` ではなく `dismiss()` メソッド内で能動的に行います。

```swift
// src/ZoomacIt/Overlay/BreakTimerWindowController.swift:62
func dismiss() {
    NSLog("[BreakTimerController] Dismissing break timer.")

    countdownTimer?.invalidate()
    countdownTimer = nil

    playingSound?.stop()
    playingSound = nil

    timerWindow?.orderOut(nil)
    timerWindow?.close()
    timerWindow = nil
    timerView = nil

    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
        appDelegate.breakTimerDidEnd()
    }
}
```

ここで `Timer` を `invalidate()` し、`NSSound` を `stop()` し、ウィンドウを `close()` しています。「ユーザーがブレイクを終了したタイミング」が振る舞い上の正規イベントなので、`deinit` のような暗黙のフックではなく、**明示的なメソッドで状態遷移を表現する** ほうが意図が読み取れます。

`OverlayWindowController` も同様に `dismiss()` を持ち、ウィンドウとキャンバスを能動的に解放します (`src/ZoomacIt/Overlay/OverlayWindowController.swift:56`)。

### 根拠 2 — クロージャでは `[weak self]` を徹底し、循環参照を作らない

`Timer` のコールバックや Notification のハンドラでクロージャに self を捕捉させると、強参照ループになって `deinit` が呼ばれなくなります。ZoomacIt はこれを `[weak self]` で防いでいます。

```swift
// src/ZoomacIt/Overlay/BreakTimerWindowController.swift:116
countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    guard let self else { return }
    let justExpired = self.state.tick()
    // ...
}
```

```swift
// src/ZoomacIt/Overlay/OverlayWindowController.swift:41
canvas.onDismiss = { [weak self] in
    self?.dismiss()
}
```

```swift
// src/ZoomacIt/Core/HotkeyManager.swift:170
DispatchQueue.main.async { [weak self] in
    self?.onZoomHotkey?()
}
```

「`deinit` で後始末する」よりも、「**そもそも参照ループを作らずに ARC に解放させる**」ほうが Swift では本筋の対処です。`[weak self]` の詳細は Ch20 (ARC と weak / unowned) で扱いますが、ここでは「ZoomacIt がこの規律を守っているから `deinit` の出番がない」と理解しておけば十分です。

### 根拠 3 — メモリ解放だけで完結する場面しか残っていない

`DrawingState`、`Stroke`、`Settings` のようなモデル型は、解放時に「閉じる」べき外部リソースを持っていません。`NSBezierPath` や `CGImage` などの内部状態はすべて ARC が自動で回収します。「ARC で十分」な型に `deinit` を書くのは、空の `finalize()` をオーバーライドするのと同じで、ノイズにしかなりません。

### まとめ — 「`deinit` がない」が読みやすさを担保している

ZoomacIt では、ライフサイクルが重要なクラスはすべて **`dismiss()` のような明示的な終了メソッドを持ち**、クロージャで自分を捕捉する箇所は **`[weak self]` で循環参照を断ち切っています**。その結果、`deinit` を書く必要がなくなりました。

これは「`deinit` は禁止」という意味ではありません。たとえば将来 `NotificationCenter.addObserver` のトークンを保持するクラスを追加したり、独自に `mmap` で開いたバッファを抱えるクラスを作るなら、そのときは迷わず `deinit` を書くべきです。判断基準はひとつだけ — **ARC が自動で面倒を見られない外部リソースを持っているかどうか** です。

---

## 18.8 まとめ

- `deinit { ... }` は **クラスインスタンスが解放される直前に同期的に呼ばれる** クリーンアップフック
- `deinit` は **class 限定**。struct / enum には書けない (値型はコピーされるためアイデンティティが定まらない)
- Java の `finalize()` と違い、**呼ばれるタイミングが予測可能** で、リソース解放の用途に使ってよい
- 用途は **ARC が面倒を見ない外部リソース** に限る — ファイル、observer、Timer、借りたリソース
- 継承時はサブクラス → スーパークラスの順に **自動で連鎖**。`super` の明示は不要
- ZoomacIt は明示的な `dismiss()` と `[weak self]` の徹底で `deinit` を不要にしている — 「`deinit` がない」は良い設計の副作用

---

## 次に読む章

→ [19. Optional Chaining](./19-optional-chaining.md)
