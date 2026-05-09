# 20. Error Handling

Swift のエラーハンドリングは、Java の checked exception と表面的には似ていますが、その哲学は明確に異なります。Swift では「エラーを送出する可能性がある関数」をシグネチャに `throws` として明示し、呼び出し側は `try` キーワードで「ここはエラーが発生しうる」と読み手に伝えなければなりません。例外の伝播はあくまで型システムの一部であり、ランタイムの制御フロー機構ではありません。

この章では、Swift のエラー設計の中心にある `Error` プロトコル、`throws` 関数、`try` の三系統 (`try` / `try?` / `try!`)、`do-catch` 構文、`defer` 文、`rethrows`、`Result` 型、そして Swift 6 で正式導入された **typed throws** までを順に解説します。最後に ZoomacIt 内の `ScreenCaptureKit` を用いた実コードを読み解き、`async throws` を伴う実際のエラーハンドリングがどのような形になるかを確認します。

## この章で学ぶこと

- Swift のエラー型は `Error` プロトコルに準拠した任意の型 (主に `enum`) であること
- 関数シグネチャの `throws` がエラー伝播の契約を表すこと
- `try` / `try?` / `try!` の三つの呼び出し方の使い分け
- `do-catch` によるパターンマッチを伴うエラー受信
- `defer` を使った確実なクリーンアップ処理
- `rethrows` による条件付きエラー伝播
- `Result<Success, Failure>` を用いた値としてのエラー表現
- Swift 6 の typed throws の概要

Java 経験者は、`try-catch` / `throws` 句 / `try-finally` との対応を意識しながら読み進めると、Swift 固有の設計判断が見えてきます。

## Error プロトコル

Swift におけるエラー型は、`Error` プロトコルに準拠していれば何でも構いません。`Error` プロトコル自体は要件を一切持たない、いわゆるマーカープロトコルです。これは Java の `java.lang.Throwable` を基底クラスとした例外階層とは大きく異なる設計です。

```swift
public protocol Error: Sendable {
    // 要件なし
}
```

実際の Swift コードでは、エラー型は **enum** で定義されることがほとんどです。enum のケースに `associated value` を持たせることで、エラー固有の文脈情報 (失敗したファイルパス、HTTP ステータスコード、原因メッセージなど) を型安全に運べるためです。

```swift
enum FileError: Error {
    case notFound(path: String)
    case permissionDenied(path: String)
    case decodingFailed(underlying: Error)
}
```

Java では `FileNotFoundException`、`AccessDeniedException` のように個別のクラスを継承で作りますが、Swift では一つの enum の case として網羅できます。これにより `switch` でのコンパイラ網羅性チェックが効き、新しいケースを追加した際に取りこぼしを検出できます。

### LocalizedError による説明文

ユーザーに見せる説明文を提供したい場合は、`LocalizedError` プロトコルに準拠し、`errorDescription` を実装します。

```swift
enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Target display not found."
        }
    }
}
```

`error.localizedDescription` を呼ぶと、この `errorDescription` の値が返却されます。これは ZoomacIt 内でも実際に使われているパターンです (後述)。

### 構造体やクラスでも可

`Error` 準拠は enum 以外でも可能です。複雑なエラー文脈 (スタック情報、複数の原因など) を持たせたい場合は struct や class を使うこともあります。ただし通常の API 設計では enum で十分です。

```swift
struct NetworkError: Error {
    let url: URL
    let statusCode: Int
    let body: Data?
}
```

## throws 関数

エラーを送出する可能性がある関数は、戻り値型の前に `throws` キーワードを書きます。

```swift
func parseInteger(from text: String) throws -> Int {
    guard let value = Int(text) else {
        throw ParseError.invalidNumber(text: text)
    }
    return value
}
```

シグネチャに `throws` が書かれている関数は、関数本体内で `throw` 文を実行してエラーを送出できます。書かれていない関数では `throw` はコンパイルエラーとなります。これは Java の `throws` 句と同じく、エラー伝播を型レベルで明示する仕組みです。

### Java の checked exception との違い

Java の checked exception には、しばしば「過剰な記述コスト」「ライブラリ間で例外型を再 throw するための無意味なラップ」といった批判が向けられます。Swift の `throws` はこれらを意識して、より軽量に設計されています。

| 観点 | Java (checked exception) | Swift (throws) |
|------|--------------------------|----------------|
| 例外型の宣言 | `throws IOException, SQLException` のように具体的な型を列挙 | デフォルトでは型を書かず、単に `throws` とだけ書く |
| 例外型の階層 | クラス継承で表現 | プロトコル準拠 (主に enum) |
| 再 throw | 各メソッドの throws 句にすべて列挙が必要 | `throws` と書くだけ。型は呼び出し側に Opaque |
| 呼び出し側の構文 | 通常の呼び出しと同じ `foo()` | `try foo()` と必ず明示 |

Swift では伝統的に `throws` は型を伴わない (= `any Error` を投げる) ため、再 throw する側は `throws` と書くだけで済みます。具体的な型を限定したい場合は、後述する **typed throws** を使います。

### 関数型としての throws

`throws` は関数型シグネチャの一部です。クロージャを引数に取る場合も同様に書きます。

```swift
func transform<T>(_ value: String, using converter: (String) throws -> T) throws -> T {
    return try converter(value)
}
```

ここで `converter` が throws する可能性があるため、それを呼ぶ側にも `try` が必要であり、外側の関数も `throws` を宣言する必要があります。

## try / try? / try!

throws 関数を呼ぶときは、必ず `try` キーワードを前置します。Swift では `try` の付け忘れがコンパイルエラーになるため、「ここはエラーが起きうる行だ」がコードを読むだけで分かるようになっています。

`try` には三つのバリエーションがあります。

### try

最も標準的な書き方です。`do-catch` ブロックの中で使うか、自身も `throws` 関数の中で使う必要があります。

```swift
do {
    let value = try parseInteger(from: "42")
    print(value)
} catch {
    print("Failed: \(error)")
}
```

### try?

エラーを Optional に変換します。エラーが発生した場合は `nil`、成功した場合は `.some(value)` が返ります。エラーの詳細は捨てられます。

```swift
let value: Int? = try? parseInteger(from: "abc")
// value == nil
```

「失敗したかどうかだけ知りたい」「エラー詳細はログにも出さなくてよい」という場面で使います。Optional の章 (Ch. 17) で学んだ Optional binding と組み合わせると簡潔に書けます。

```swift
if let value = try? parseInteger(from: "42") {
    print(value)
}
```

### try!

エラーが発生しないことを開発者が保証する場合の書き方です。実行時にエラーが発生するとプログラムはクラッシュします。Optional の `!` (強制アンラップ) と同じ哲学で、「失敗したらバグ」というシグナルを発します。

```swift
let value = try! parseInteger(from: "42")
// "42" は確実に Int にパースできるためクラッシュしない
```

リソースバンドルから自分で配置したファイルを読む場合や、テストコード内など、失敗が明らかにバグである場面に限定して使うべきです。

### 使い分けの指針

| 構文 | 失敗時の挙動 | 主な用途 |
|------|-------------|---------|
| `try` | do-catch で受け取る、または上位に伝播 | 通常のエラー処理 |
| `try?` | nil に変換 | エラー詳細不要、Optional として扱いたい |
| `try!` | クラッシュ | 失敗が論理的にあり得ない場面 |

## do-catch 構文

`do-catch` は Swift のエラー受信の中核となる構文です。Java の `try-catch` とほぼ同じ役割を果たしますが、`try` ではなく `do` で始まる点が表面的な違いです (`try` は呼び出し位置に書くため)。

```swift
do {
    let value = try parseInteger(from: input)
    print("Parsed: \(value)")
} catch ParseError.invalidNumber(let text) {
    print("Invalid number: \(text)")
} catch {
    print("Other error: \(error)")
}
```

### パターンマッチ

`catch` 節は switch の case と同じパターンマッチが書けます。enum のケースを直接マッチさせたり、`as` で型を絞り込んだりできます。

```swift
do {
    try someOperation()
} catch let error as FileError {
    // FileError 限定の処理
} catch let error as NetworkError {
    // NetworkError 限定の処理
} catch {
    // それ以外
}
```

`catch` だけで型もパターンも書かない場合、暗黙的に `error` という名前の定数で受け取れます。これは Swift の慣用句で、簡潔に「とにかく何かエラーが起きたら」を表現できます。

### catch 節の網羅性

`do-catch` では、`do` ブロック内で発生しうるすべてのエラーを catch 節がカバーする必要があります。`catch` (型なし) を最後に置くか、関数全体が `throws` を宣言していて未処理エラーを上位に伝播できる必要があります。

```swift
func loadConfig() throws {
    do {
        try parseFile()
    } catch FileError.notFound(let path) {
        // 未処理のエラー (NetworkError など) は throws により上位に伝播
        print("Config not at \(path), using defaults.")
    }
}
```

## defer 文

`defer` は Swift 特有のクリーンアップ機構で、現在のスコープから抜ける際に必ず実行されるブロックを登録します。Java の `try-finally` に近い役割ですが、Java の finally がブロック単位なのに対し、Swift の `defer` は **スコープ単位** で動作し、関数の途中どこにでも書けます。

```swift
func processFile(at path: String) throws {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer {
        handle.closeFile()
        NSLog("[processFile] File closed.")
    }

    // この後どこで return / throw / 例外発生しても closeFile() は実行される
    let data = try handle.readToEnd()
    try parse(data)
}
```

`defer` の特徴は次の通りです。

- **関数の任意の位置で登録できる**。リソース取得直後に対応する解放処理を書けるため、コードの局所性が高い。
- **複数登録可能で、LIFO (後入れ先出し) で実行される**。

```swift
func multiDefer() {
    defer { print("1") }
    defer { print("2") }
    defer { print("3") }
    print("body")
}
// 出力:
// body
// 3
// 2
// 1
```

これは「リソース A を取得 → リソース B を取得 → … → 解放は逆順」という典型パターンに自然に合致します。

### Java の try-finally との対比

Java では try-finally は構文ブロックを必要とします。

```java
FileHandle handle = open(path);
try {
    // ...
} finally {
    handle.close();
}
```

リソースの取得と解放が **構文上のブロック** で結ばれるため、ブロックのインデントが深くなりがちです。Swift の `defer` は、解放処理を取得処理のすぐ近くに **平坦に** 書けるのが利点です。複数のリソースを順番に取得していく場合、Java では try のネストが必要ですが、Swift では `defer` を並べるだけで済みます。

なお、`defer` は throws 関数の中だけでなく、通常の関数や `do` ブロック内でも使えます。

## rethrows

`rethrows` は「引数のクロージャがエラーを送出する場合のみ、自分もエラーを送出する」という条件付き throws を表します。標準ライブラリでは `map`、`filter`、`forEach` などの高階関数で使われています。

```swift
public func map<T>(_ transform: (Element) throws -> T) rethrows -> [T]
```

このシグネチャがあるおかげで、`map` を **throws しないクロージャ** で呼んだ場合は `try` 不要、**throws するクロージャ** で呼んだ場合のみ `try` が必要、という挙動になります。

```swift
let nums = ["1", "2", "3"]

// throws しないクロージャ → try 不要
let lengths: [Int] = nums.map { $0.count }

// throws するクロージャ → try 必要
let parsed: [Int] = try nums.map { try parseInteger(from: $0) }
```

自分でユーティリティ関数を書くときも、クロージャを引数に取る関数は `rethrows` にしておくと、利用側の柔軟性が高まります。

```swift
func retry<T>(times: Int, _ block: () throws -> T) rethrows -> T {
    var lastError: Error?
    for _ in 0..<times {
        do {
            return try block()
        } catch {
            lastError = error
        }
    }
    // lastError は必ず非 nil
    throw lastError!
}
```

ただし上記の例では「block が throws しなくても自分は throw しうる」ので厳密には rethrows ではなく `throws` にすべきです。`rethrows` は本当に「クロージャが投げる以外の経路でエラーを投げない」場合のみ使えます。

## Result<Success, Failure>

`Result` は標準ライブラリで定義された enum で、成功値と失敗値を一つの値として表現します。

```swift
public enum Result<Success, Failure: Error> {
    case success(Success)
    case failure(Failure)
}
```

throws 関数が「呼んだ側が即座に try / catch する」前提なのに対し、`Result` は **エラーを値として持ち回りたい場面** で使います。

代表的な用途は次の通りです。

- **コールバック型の非同期 API** — 完了ハンドラの引数として `Result<Data, NetworkError>` を渡す。
- **複数の処理結果を集約したい場合** — `[Result<Item, ItemError>]` のように配列で持つ。
- **エラー型を明示したい場合** — `Result` のジェネリクスでエラー型が型レベルに現れる。

```swift
func fetchUser(id: Int, completion: @escaping (Result<User, NetworkError>) -> Void) {
    // ... 非同期処理 ...
    if success {
        completion(.success(user))
    } else {
        completion(.failure(.timeout))
    }
}

fetchUser(id: 42) { result in
    switch result {
    case .success(let user):
        print(user.name)
    case .failure(let error):
        print("Failed: \(error)")
    }
}
```

### Result と throws の相互変換

`Result` には `get()` メソッドがあり、`.success` の場合は値を返し、`.failure` の場合はエラーを `throw` します。

```swift
let result: Result<Int, ParseError> = .success(42)
let value = try result.get()  // 42
```

逆に、throws 関数を `Result` に変換するイニシャライザもあります。

```swift
let result = Result { try parseInteger(from: "42") }
// result は Result<Int, Error>
```

async/await の登場 (Ch. 21 で詳述) 以降、コールバック型 API は減りつつあるため、`Result` を直接書く機会は減ってきています。しかし「エラーを値として運ぶ」概念は残るため、ライブラリ境界などでは依然として有用です。

## typed throws (Swift 6)

Swift 6 で正式に導入された **typed throws** は、関数が送出するエラー型を限定する機能です。

```swift
func parseStrict(_ text: String) throws(ParseError) -> Int {
    guard let value = Int(text) else {
        throw ParseError.invalidNumber(text: text)
    }
    return value
}
```

`throws(ParseError)` と書くことで、この関数は `ParseError` 以外のエラーを送出できないことが型レベルで保証されます。呼び出し側でも catch する型が `ParseError` に絞られ、より厳密な処理が可能になります。

```swift
do {
    let value = try parseStrict("42")
} catch {
    // ここでの error の型は ParseError (any Error ではない)
}
```

### いつ使うか

typed throws は強力ですが、過剰に使うと Java の checked exception と同じ「型を伝播させるための無意味なラップ」を引き起こします。Apple の指針としては、次のような場面で限定的に使うことが推奨されています。

- **ライブラリ内部の閉じた API** — 公開 API ではなく、限られたコード範囲でのみ流通するエラー
- **組み込みやリソース制約のある環境** — エラー型を `any Error` (existential) ではなく具体型で持つことでパフォーマンス上の利点がある場面
- **エラー型が一つに自然と決まる API** — 例えば JSON パーサが `JSONError` のみを送出するような場合

通常のアプリケーションコードでは、従来通り `throws` (= `throws(any Error)` と等価) で十分です。

## ZoomacIt の実コード読解

ここまでの内容を踏まえて、ZoomacIt が実際にどのように `throws` を扱っているかを見ていきます。題材は `ScreenCaptureKit` を用いた画面キャプチャ処理です。

`ScreenCaptureKit` の API はほぼすべて `async throws` で定義されており、画面キャプチャの権限が無い、ディスプレイが見つからない、システムが応答しない、などの理由でエラーを送出する可能性があります。

### throws 関数の定義

ZoomacIt では、画面キャプチャを行う関数を `async throws -> CGImage` として定義しています。

```swift
private static func captureScreen(
    displayID: CGDirectDisplayID,
    width: CGFloat,
    height: CGFloat,
    scaleFactor: CGFloat
) async throws -> CGImage {
    let availableContent = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true
    )
    guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
        throw CaptureError.displayNotFound
    }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = Int(width * scaleFactor)
    config.height = Int(height * scaleFactor)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false

    return try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
    )
}
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:137-161

注目すべきポイントは次の通りです。

- 関数シグネチャに `async throws -> CGImage` と書くことで、「非同期かつエラー送出しうる」ことを宣言している。
- 内部で `SCShareableContent.excludingDesktopWindows(...)` の呼び出しに `try await` が付いている。これは「非同期に待機しつつ、失敗時はエラーを送出する」という二つの性質を同時に表現する書き方。
- ディスプレイが見つからない場合は、自前で定義した `CaptureError.displayNotFound` を `throw` している。
- 最後の `return try await SCScreenshotManager.captureImage(...)` でも `try await` を使い、エラーをそのまま上位に伝播させている。

ここで投げられるエラーは、`ScreenCaptureKit` 由来のもの (`SCStreamError` など) や、自前の `CaptureError` の両方が混在します。Swift の従来の `throws` は型を限定しないため、これらをまとめて `any Error` として上位に伝播できます。

### エラー型の定義

`CaptureError` は `LocalizedError` に準拠した enum として定義されています。

```swift
private enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Target display not found."
        }
    }
}
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:163-171

`private enum` として閉じたスコープに置くことで、ファイル外への漏れを防いでいます。`LocalizedError` 準拠により、`error.localizedDescription` で人間可読な文字列を取得できます。

### do-catch での受信

呼び出し側では `do-catch` でエラーを受け取り、ログに出力した上で UI 側のフェイルセーフ処理 (`onShowFailed?()`) に切り替えています。

```swift
Task { @MainActor in
    NSLog("[StillZoomWindowController] Starting screen capture via ScreenCaptureKit...")
    do {
        let captured = try await Self.captureScreen(
            displayID: displayID,
            width: screen.frame.width,
            height: screen.frame.height,
            scaleFactor: scaleFactor
        )
        NSLog("[StillZoomWindowController] Capture succeeded: %dx%d", captured.width, captured.height)
        self.sourceImage = captured

        // ... マウス座標の変換処理 ...

        self.presentOverlay(on: screen, image: captured, scaleFactor: scaleFactor,
                            initialPanCenter: mousePanCenter)
    } catch {
        NSLog("[StillZoomWindowController] Screen capture failed: %@", error.localizedDescription)
        self.onShowFailed?()
    }
}
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:39-68

ここでは `catch` (型指定なし) で、あらゆるエラーをまとめて受け取っています。エラーの種類によって処理を変える必要がない (どのエラーであれ「キャプチャ失敗」として扱えばよい) ためです。

`error.localizedDescription` を `NSLog` に出力し、最後に `onShowFailed?()` クロージャを呼ぶことで、上位の状態管理側にキャプチャ失敗を通知します。これは典型的な「エラーを境界で吸収して、利用者には簡素な失敗通知だけ渡す」パターンです。

### Break Timer での同様のパターン

`BreakTimerWindowController` でも、ほぼ同じ構造の画面キャプチャが行われています。

```swift
private static func captureScreenImage(
    displayID: CGDirectDisplayID,
    width: CGFloat,
    height: CGFloat,
    scaleFactor: CGFloat
) async -> CGImage? {
    guard CGPreflightScreenCaptureAccess() else {
        NSLog("[BreakTimerController] Screen Recording not permitted — using black background.")
        return nil
    }

    do {
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
            NSLog("[BreakTimerController] Display not found.")
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(width * scaleFactor)
        config.height = Int(height * scaleFactor)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    } catch {
        NSLog("[BreakTimerController] Screen capture failed: %@", error.localizedDescription)
        return nil
    }
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:185-218

こちらでは関数シグネチャが `async -> CGImage?` (throws なし、戻り値が Optional) になっている点が `StillZoomWindowController` と異なります。設計判断としては次のようになっています。

- **Break Timer は背景画像が無くても動作可能** (黒背景にフォールバックすればよい) なので、エラーを Optional の nil に丸めてしまう。
- **Still Zoom はキャプチャ画像が無いと機能しない** ので、throws のまま外に伝播させ、呼び出し側で「ズーム自体を中止」という判断を下す。

つまり「失敗してもよい場面」では Optional に変換し、「失敗を意味のある形で扱いたい場面」では throws を保持する、という棲み分けです。`try?` を使えば throws 関数を Optional に変換できますが、ここでは元々の関数を `async -> CGImage?` として定義することで、呼び出し側に意図を明確に伝えています。

### ポイントのまとめ

実コードから読み取れる Swift エラーハンドリングの実践的な指針は次の通りです。

1. **境界で吸収するか、上位に伝播するかを意識的に決める**。すべてを `throws` で伝播すると呼び出し側に負担を強い、すべてを Optional に丸めると情報が失われる。
2. **`try await` の組み合わせは頻出**。async 関数のほとんどが throws を伴うため、両者は一緒に書かれることが多い。
3. **エラー型は private enum で十分**。広く使う必要がない限り、ファイル内に閉じた enum として定義する。
4. **`LocalizedError` 準拠でログ品質を上げる**。`error.localizedDescription` がそのまま意味のある文字列になる。

## ハンズオン (任意)

理解を深めるために、次のような小さな関数を書いてみてください。

1. **JSON 風文字列のパーサ** — `"{key: value}"` を受け取り、`(String, String)` のタプルを返す `func parseEntry(_ s: String) throws -> (String, String)` を定義する。失敗時は `enum ParseError: Error` を送出する。
2. **defer の挙動確認** — 関数内に `defer` を 3 つ書き、ログ出力で LIFO 順序を確認する。
3. **rethrows 関数の作成** — 配列の各要素にクロージャを適用し、最初の成功値を返す `func first<T>(in array: [String], where converter: (String) throws -> T?) rethrows -> T?` を定義する。`rethrows` を `throws` に変えてみて、利用側のコンパイル要件がどう変わるか観察する。
4. **Result から throws への変換** — `Result<Int, ParseError>` を返す関数を作り、`.get()` を使って throws 関数として再ラップする。

これらを通して、`try` の付け忘れがコンパイラにどう検出されるか、`defer` がどのタイミングで動くかを体感してみてください。

## 次に読む章

エラーハンドリングと密接に関わる **async/await** の世界に進みます。本章で `try await` という組み合わせを目にしましたが、`await` 側の正体と、構造化並行性 (Structured Concurrency) の仕組みを次章で詳しく扱います。

→ [21. Concurrency](./21-concurrency.md)
