# 35. ScreenCaptureKit と async/await

## この章で学ぶこと

ZoomacIt の Zoom と Break Timer は、いずれも「現在画面に映っている内容を一枚絵として取り込み、それを背景に描画する」という共通動作を持ちます。Zoom はキャプチャした画像を拡大表示し、Break Timer はキャプチャした画像をフェードして背景に敷きます。この動作の心臓部にあるのが、macOS 12.3 で導入された **ScreenCaptureKit** フレームワークと、Ch21 で学んだ Swift の **async/await** モデルの組み合わせです。

この章では次のことを学びます。

- ScreenCaptureKit が登場した背景と、置き換えた古い API との関係
- 画面収録 (Screen Recording) 権限の確認・誘導の現代的な作法
- `SCShareableContent` でキャプチャ可能な対象を列挙する方法
- `SCContentFilter` で「何を」キャプチャするかを表現する考え方
- `SCStreamConfiguration` で解像度・ピクセルフォーマット・カーソル表示を指定する方法
- `SCScreenshotManager.captureImage` による一発静止画キャプチャのパターン
- `SCStream` を使った連続フレームキャプチャの概略 (ZoomacIt は使っていないが将来用)
- `Task { @MainActor in ... }` による UI スレッドと非同期処理の連携
- **Optional で失敗を吸収する設計** (BreakTimer) と **throws で失敗を伝播する設計** (Zoom) の対比

最後に `BreakTimerWindowController.captureScreenImage` と `StillZoomWindowController.captureScreen` の二つの実装を行単位で読み解き、同じ ScreenCaptureKit 呼び出しが「どのような設計判断のもとに、なぜ別々のシグネチャで書かれているのか」を理解します。

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:185-218, src/ZoomacIt/Overlay/StillZoomWindowController.swift:137-171

---

## ScreenCaptureKit とは — 古い API を置き換えた現代的フレームワーク

macOS で「画面の内容を取得する」ための API は、長い間 CoreGraphics の `CGWindowListCreateImage` や `CGDisplayCreateImage` が定番でした。これらは同期的に呼べる手軽さがある反面、次のような問題を抱えていました。

- **権限モデルが曖昧**: 古い API は権限のない状態でも一見成功し、真っ黒な画像が返るケースがあった
- **HDR・高 DPI への対応が乏しい**: ピクセルフォーマットや色空間の指定が貧弱
- **マルチディスプレイの扱いが煩雑**: 各ディスプレイ ID を自分で列挙して呼び分ける必要があった
- **同期 API のため、呼び出しスレッドをブロックする**: 画面取得は数十ミリ秒かかることがあり、メインスレッドで呼ぶと UI が固まる

Apple は macOS 12.3 (Monterey) で **ScreenCaptureKit** という新しいフレームワークを導入し、これらの問題をまとめて解消しました。設計上の特徴は次の通りです。

| 観点 | 旧 CG 系 API | ScreenCaptureKit |
|------|--------------|-------------------|
| 呼び出しモデル | 同期 | **async/await** |
| 権限管理 | 曖昧 | TCC (Screen Recording) と密結合 |
| キャプチャ対象の表現 | ディスプレイ ID + ウィンドウ ID 番号 | `SCDisplay` / `SCWindow` / `SCRunningApplication` の構造化オブジェクト |
| フィルター | API ごとに別引数 | `SCContentFilter` に統一 |
| 静止画 | `CGImage` を即座に返す | `SCScreenshotManager.captureImage` で `async throws -> CGImage` |
| 連続キャプチャ | (実質的に存在しない) | `SCStream` + `SCStreamOutput` プロトコル |
| 推奨度 | macOS 14 以降は事実上 deprecated 扱い | **現在の標準** |

ZoomacIt は **macOS 26+ をターゲット** にしているため、旧 API を選ぶ理由は一つもありません。新規実装として ScreenCaptureKit を選ぶのは半ば自明の判断です。

加えて、`async/await` ベースで設計されているという点は、Ch21 で学んだ Swift Concurrency の知識をそのまま実戦投入できる、という意味でも重要です。ScreenCaptureKit のすべての主要 API は `async throws` で宣言されており、呼び出し側は `try await` 一発で結果を待てます。コールバック地獄やデリゲートの設計をする必要はありません。

---

## 画面収録 (Screen Recording) 権限

ScreenCaptureKit を呼び出す前に、必ず確認すべきものがあります。それが **Screen Recording 権限** です。これは macOS 10.15 (Catalina) で導入された TCC (Transparency, Consent, and Control) の枠組みの一部で、ユーザーが「システム設定 > プライバシーとセキュリティ > 画面収録」で個別アプリに対して明示的に許可する必要があります。

### `CGPreflightScreenCaptureAccess()` で事前チェック

ZoomacIt は CoreGraphics が提供する **`CGPreflightScreenCaptureAccess()`** を使ってチェックしています。

```swift
guard CGPreflightScreenCaptureAccess() else {
    NSLog("[BreakTimerController] Screen Recording not permitted — using black background.")
    return nil
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:191-194

`CGPreflightScreenCaptureAccess()` は名前の通り、`true` (許可済み) / `false` (未許可) を **副作用なし** で返します。同じファミリーには副作用ありの `CGRequestScreenCaptureAccess()` もあり、こちらは初回呼び出し時にシステムのプロンプトを表示します。

ZoomacIt の他の場所 (`Settings` 画面や初回起動時) では `CGRequestScreenCaptureAccess()` を呼び、ユーザーをシステム設定に誘導するフローが用意されています。`captureScreenImage` の中では既に「許可されているはず」を前提に **チェックのみ** を行い、未許可ならキャプチャを諦めて nil を返します。

> 補足: CLAUDE.md にも明記されている通り、ZoomacIt が要求する権限は **Screen Recording のみ** です。Accessibility 権限は不要です (理由は Ch34 を参照)。

### `.app` バンドルでなければ権限が壊れる

`design/Zoom.md` には次の警告が記されています。

```
macOS 26.1 (Tahoe) の注意点:
.app バンドルでない plain executable は
Screen Recording の権限UIに表示されなくなった (Developer Forums 確認)。
→ 必ず .app バンドルとして配布すること。
```

> 引用元: design/Zoom.md:164-166

このため ZoomacIt は CLAUDE.md にも書かれている通り `open ZoomacIt.app` で起動することが推奨されています。直接バイナリを `./ZoomacIt` のように実行すると、**ターミナル.app** が責任プロセス (responsible process) として TCC に登録され、権限管理が破綻します。これは ScreenCaptureKit に限らず、すべての TCC 系権限で共通する重要なポイントです。

---

## `SCShareableContent` — 何がキャプチャ可能か

ScreenCaptureKit の最初の関門が `SCShareableContent` です。これは「現時点でキャプチャ可能なもの」のスナップショットで、以下を含みます。

- `displays: [SCDisplay]` — 接続中のディスプレイ一覧
- `windows: [SCWindow]` — 表示中のウィンドウ一覧
- `applications: [SCRunningApplication]` — 起動中のアプリ一覧

ZoomacIt では次のように呼び出します。

```swift
let availableContent = try await SCShareableContent.excludingDesktopWindows(
    false, onScreenWindowsOnly: true
)
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:143-145

`excludingDesktopWindows(_:onScreenWindowsOnly:)` は次の二つの真偽値を取ります。

| 引数 | 意味 |
|------|------|
| 第 1 引数 (`Bool`) | デスクトップアイコン (Finder のデスクトップウィンドウ) を **除外** するか。`false` なら含める |
| `onScreenWindowsOnly` | 画面上に実際に見えているウィンドウのみに絞るか |

ZoomacIt の用途は「ディスプレイ全体をそのまま撮る」ことなので、ウィンドウリストは厳密には不要です。しかし `SCShareableContent` を取得しなければ `SCDisplay` も得られない構造になっているため、軽量な引数 (`onScreenWindowsOnly: true` でウィンドウ列挙を最小化) を渡しています。

### 取得した `SCDisplay` から目的のディスプレイを探す

ZoomacIt はマウスのある (またはメインの) ディスプレイをキャプチャ対象にします。そのために、AppKit から取得した `CGDirectDisplayID` を `SCShareableContent.displays` の中から照合します。

```swift
guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
    throw CaptureError.displayNotFound
}
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:146-148

`SCDisplay.displayID` は `CGDirectDisplayID` と直接比較可能です。これは **AppKit と ScreenCaptureKit が共通の識別子体系を共有している** ことを意味します。古い API では「ディスプレイ ID は何番目か」を別途調べる必要がありましたが、ScreenCaptureKit ではこの面倒がありません。

### `try await` の意味

`SCShareableContent.excludingDesktopWindows` は `async throws` です。Ch21 で学んだ通り、`try await` 一発で「非同期かつ失敗しうる呼び出し」を表現できます。失敗したときの理由は様々で、Screen Recording 権限が剥奪された、別プロセスがロックを握っている、システム負荷が極端に高い、などがあります。これらはすべて `do-catch` でまとめて吸収します。

---

## `SCContentFilter` — 「何を」キャプチャするか

`SCContentFilter` は **キャプチャ対象を表現するイミュータブルな値** です。コンストラクタの種類によって、ディスプレイ全体、特定ウィンドウのみ、特定アプリのみ、などが選べます。

ZoomacIt は **ディスプレイ全体 + 除外ウィンドウなし** を選んでいます。

```swift
let filter = SCContentFilter(display: display, excludingWindows: [])
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:150

`excludingWindows` 引数に `[SCWindow]` を渡すと、それらは **キャプチャから除外** されます。例えば「自分のオーバーレイウィンドウは映したくない」というケースで便利です。ZoomacIt の場合、Zoom や Break Timer のオーバーレイウィンドウは「キャプチャした **後** に」表示されるため、自分自身を除外する必要がありません。

代表的な `SCContentFilter` のコンストラクタは以下の通りです。

| コンストラクタ | 用途 |
|----------------|------|
| `SCContentFilter(display:excludingWindows:)` | ディスプレイ全体 (除外指定可) |
| `SCContentFilter(display:including:)` | 特定ウィンドウだけ含める |
| `SCContentFilter(desktopIndependentWindow:)` | 単一ウィンドウだけ |
| `SCContentFilter(display:includingApplications:exceptingWindows:)` | 特定アプリだけ |

ZoomacIt の用途では一番シンプルなパターンで十分です。

---

## `SCStreamConfiguration` — どのように撮るか

`SCContentFilter` が「何を」を表すなら、`SCStreamConfiguration` は「どのように」を表します。代表的なプロパティは次の通り。

| プロパティ | 意味 |
|------------|------|
| `width` / `height` | 出力解像度 (ピクセル) |
| `pixelFormat` | `kCVPixelFormatType_32BGRA` などの CV ピクセルフォーマット |
| `showsCursor` | カーソルを画像に含めるか |
| `minimumFrameInterval` | (`SCStream` 用) 最大フレームレートを表す `CMTime` |
| `colorSpaceName` | カラースペース名 |
| `queueDepth` | (`SCStream` 用) 内部バッファ深さ |

ZoomacIt の Still Zoom 用設定はこうです。

```swift
let config = SCStreamConfiguration()
config.width = Int(width * scaleFactor)
config.height = Int(height * scaleFactor)
config.pixelFormat = kCVPixelFormatType_32BGRA
config.showsCursor = false
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:151-155

### Retina スケールの掛け算

`width * scaleFactor` の掛け算が肝です。`NSScreen.frame.width` は **ポイント** 単位 (Retina で 1pt = 2px) を返すため、ピクセル解像度を指定する `SCStreamConfiguration.width` には `backingScaleFactor` を掛ける必要があります。例えば 2880×1800 (実ピクセル) の Retina ディスプレイなら、`frame.width = 1440`、`scaleFactor = 2.0`、結果として `config.width = 2880` となります。

これを忘れると、撮影解像度が半分になり、拡大時にぼやけた画像になってしまいます。Zoom のように後から拡大する用途では特に致命的です。

### `kCVPixelFormatType_32BGRA` を選ぶ理由

CoreVideo のピクセルフォーマット定数で、1 ピクセル 32bit (8bit × 4ch) の BGRA レイアウトを指定します。これは `CGImage` や `CALayer.contents` がもっとも自然に扱える形式で、変換コストが最小になります。HDR や高ビット深度は別の定数 (`kCVPixelFormatType_64RGBAHalf` など) を選ぶことで対応可能ですが、ZoomacIt の用途では `BGRA8` で十分です。

### `showsCursor = false`

Zoom も Break Timer も「自分が出した時点のマウスカーソル」を画像に焼き込みたくありません。理由は以下の通り。

- Zoom: マウスカーソルは ZoomacIt が再描画 (オーバーレイの上で) するので、二重表示を避けたい
- Break Timer: 静止した背景にカーソル位置が固定で映ると違和感が大きい

`showsCursor` を `false` にすることで、両者ともクリーンな背景画像が得られます。

---

## `SCScreenshotManager.captureImage` — 一発静止画キャプチャ

ScreenCaptureKit の中で、ZoomacIt が実際に呼んでいる「キャプチャ実行」関数はこれだけです。

```swift
return try await SCScreenshotManager.captureImage(
    contentFilter: filter,
    configuration: config
)
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:157-160

`SCScreenshotManager.captureImage(contentFilter:configuration:)` のシグネチャは概念的に次のようなものです。

```swift
class SCScreenshotManager {
    static func captureImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage
}
```

- **`async throws -> CGImage`**: `try await` で `CGImage` が直接返ってくる
- **副作用なし**: 一回呼ぶと一枚撮って終了、内部状態を残さない
- **権限が無いと throws**: Screen Recording が剥奪されていれば例外が投げられる

このメソッドの存在こそが、「Still Zoom や Break Timer のように『一枚撮って終わり』のユースケースで `SCStream` を組まなくていい」という、ScreenCaptureKit 設計上の最重要ポイントです。`SCStream` はデリゲートを実装し、開始・停止のライフサイクル管理が必要で、コードが格段に複雑になります。`SCScreenshotManager.captureImage` はそれを **3 行のセットアップ + 1 行の `try await`** で済ませてくれます。

---

## `SCStream` — 連続キャプチャ (今回は使わないが)

`SCStream` は連続フレームを受け取るための API で、Live Zoom (= リアルタイムにマウス追従して画面を拡大する機能) のような用途で必要になります。design ドキュメントでは Live Zoom 実装の指針として次のように示されています。

```swift
let config = SCStreamConfiguration()
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)  // 最大 60fps
config.pixelFormat = kCVPixelFormatType_32BGRA
config.showsCursor = true   // Live Zoom ではカーソルを表示

func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
            of type: SCStreamOutputType) {
    guard let pixelBuffer = buffer.imageBuffer else { return }
    DispatchQueue.main.async {
        self.overlayLayer.contents = pixelBuffer
    }
}
```

> 引用元: design/Zoom.md:128-143

ポイントだけ押さえておきます。

- `SCStream` は `init(filter:configuration:delegate:)` で初期化し、`addStreamOutput(_:type:sampleHandlerQueue:)` で出力先を登録する
- フレーム到着は **デリゲート (`SCStreamOutput`) のメソッド呼び出し** として届く。`async/await` ではない (毎フレーム数十回/秒呼ばれるためコールバックの方が自然)
- `startCapture()` / `stopCapture()` は `async throws` で、こちらは `try await` で扱える
- フレームを `CGImage` に変換すると毎フレームコピーが発生するので、`CALayer.contents` に `CVPixelBuffer` を直接渡す **ゼロコピー** が定石

ZoomacIt の現バージョン (Still Zoom のみ) では `SCStream` は使っていません。よって本章での詳説は割愛しますが、「`SCScreenshotManager` は一発撮影、`SCStream` は連続撮影」と覚えておけば、将来 Live Zoom を実装するときにすぐに該当 API へ辿り着けるはずです。

---

## async/await + `@MainActor` + Task の連携

ScreenCaptureKit の API はすべて非同期 (`async throws`) です。一方、UI 操作は `@MainActor` でなければなりません。この二つを橋渡しするのが `Task { @MainActor in ... }` のイディオムです。Ch21 で学んだ Swift Concurrency の知識を、ZoomacIt は次の形で実戦投入しています。

### Break Timer の起動フロー

```swift
Task { @MainActor in
    let captured = await Self.captureScreenImage(
        displayID: screenNumber,
        width: screenFrame.width,
        height: screenFrame.height,
        scaleFactor: scaleFactor
    )
    self.presentTimer(screen: screen, capturedImage: captured)
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:48-56

このわずか 8 行の中に、Swift 6 Concurrency の重要要素が凝縮されています。

1. **`Task { ... }`**: 新規の非同期タスクを作って、現在のスコープから抜ける (ノンブロッキング)
2. **`@MainActor in`**: タスク本体を MainActor 上で実行することを **明示**
3. **`await Self.captureScreenImage(...)`**: 静的メソッドを await で呼び出す
4. **`self.presentTimer(...)`**: 戻ってきたら MainActor 上で UI を構築

`captureScreenImage` は内部で ScreenCaptureKit の `try await` を呼びますが、await の意味は「処理が終わるまでこのスレッドを **解放** する」です。メインスレッド (= MainActor) は ScreenCaptureKit 待ちの間、他の UI イベント処理を続けられます。これが従来の同期 API と決定的に違う点です。

### `@MainActor` クラスからの呼び出し

`BreakTimerWindowController` は冒頭で `@MainActor` 修飾されています。

```swift
@MainActor
final class BreakTimerWindowController {
    ...
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:6-7

このクラスのメソッドはすべて MainActor 上で動くため、`Task { @MainActor in ... }` の `@MainActor` 注釈は **冗長** に見えるかもしれません。実際には冗長なのですが、明示することで「このタスクが MainActor で動く」というコードの意図を読み手に伝える効果があります。Swift 6 の strict concurrency 下では、コンパイラに依存せず明示する方が保守性が高くなります。

### `static func` にする理由

`captureScreenImage` も `captureScreen` も `static` メソッドとして実装されています。

```swift
private static func captureScreenImage(
    displayID: CGDirectDisplayID,
    width: CGFloat,
    height: CGFloat,
    scaleFactor: CGFloat
) async -> CGImage? {
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:185-190

なぜ `self` を持たない `static` にしたか。理由は二つあります。

1. **`self` を キャプチャする必要がない**: 引数だけで完結するため、インスタンス状態に依存しない
2. **MainActor 隔離を緩める**: `static func` (かつ `nonisolated` ではないが、actor isolation の観点では呼び出しが容易) なので、Task の外側からも内側からも安全に呼べる

これは Swift 6 のコンパイラに「このメソッドは状態を共有しません」とはっきり伝える、明示的な設計選択です。

---

## エラーハンドリング — Optional vs throws の対比

ScreenCaptureKit を扱う上で、本章でもっとも理解してほしいのは **エラーハンドリングの設計判断** です。同じ ScreenCaptureKit 呼び出しでも、ZoomacIt は二箇所で **意図的に異なる戦略** を採用しています。

### Break Timer: 失敗しても続行 (Optional)

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

Break Timer 用の `captureScreenImage` は **戻り値が `CGImage?`**、シグネチャは **`async -> CGImage?`** で **`throws` を持ちません**。エラーはすべて `do-catch` で `nil` に丸められます。

呼び出し側は次のように使います。

```swift
let captured = await Self.captureScreenImage(...)
self.presentTimer(screen: screen, capturedImage: captured)
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:49-55

`captured` は `CGImage?`。これを `BreakTimerView` の `capturedImage` 引数にそのまま渡します。`BreakTimerView` 側はこの引数が `nil` なら **黒い背景**、非 `nil` ならフェードした背景を描く実装になっています。

なぜこの設計にしたか。**Break Timer の本質的役割は「指定時間が経過したら通知する」ことであり、背景画像の有無は補助的な見た目に過ぎない** からです。背景キャプチャに失敗してもタイマーは正しく動かなければなりません。失敗を例外として伝播させてしまうと、上位は try-catch を強いられ、最悪「タイマー機能が立ち上がらない」という本末転倒な事態になります。

つまり「背景の有無は機能の本質ではない、失敗しても続行すべき」という業務的判断が、Optional 戻り値という型シグネチャに表現されているのです。

### Still Zoom: 失敗ならエラー扱い (throws)

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

private enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "Target display not found."
        }
    }
}
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:137-171

Still Zoom 用の `captureScreen` は **戻り値が `CGImage` (Optional ではない)**、シグネチャは **`async throws -> CGImage`** です。エラーは伝播され、独自エラー型 `CaptureError` まで定義しています。

呼び出し側は次の通り。

```swift
do {
    let captured = try await Self.captureScreen(...)
    NSLog("[StillZoomWindowController] Capture succeeded: %dx%d", captured.width, captured.height)
    self.sourceImage = captured
    ...
    self.presentOverlay(on: screen, image: captured, ...)
} catch {
    NSLog("[StillZoomWindowController] Screen capture failed: %@", error.localizedDescription)
    self.onShowFailed?()
}
```

> 引用元: src/ZoomacIt/Overlay/StillZoomWindowController.swift:39-68

成功時は `presentOverlay` を呼んで Zoom オーバーレイを表示。失敗時は `onShowFailed?()` でエラーコールバックを発火し、上位 (`AppDelegate` など) が「Zoom を起動できなかった」というユーザー通知を出す責務を負います。

なぜ Zoom はこの設計か。**Zoom 機能の本質は「画面を拡大表示する」ことであり、画像が無ければ機能が成立しません**。背景なし、ではなく **何もできない** わけです。失敗を `nil` で返してしまうと、上位は「画像が無い Zoom オーバーレイ」を表示しようとして無意味な状態に陥ります。代わりに `throw` で明確にエラーを伝え、上位に「失敗したので何もしない」を選ばせる方が正しい。

### 設計判断のまとめ — 「失敗の意味」が型に現れる

両者の対比を表にしましょう。

| 観点 | Break Timer | Still Zoom |
|------|-------------|-------------|
| 関数シグネチャ | `async -> CGImage?` | `async throws -> CGImage` |
| 失敗時の戻り値 | `nil` (Optional) | `throw` (例外) |
| 失敗時の上位の挙動 | 黒い背景でタイマー継続 | エラー通知 + Zoom 起動取消 |
| 失敗の業務的意味 | 「見た目が劣化する」だけ | 「機能が成立しない」 |
| エラー型の有無 | なし (NSLog のみ) | `CaptureError` enum |
| 上位コードのパターン | `await + 直接渡し` | `do-catch + try await` |

**「同じ API を呼んでいても、業務上の失敗の重みが違えば、シグネチャを変えるべき」** という、Swift の型システムを使った設計判断の典型例です。Optional と throws のどちらを使うかは美学の問題ではなく、**失敗の意味論をコードで表現する** ためにあります。

Java の `Optional<T>` vs `throws Exception` の選択と同じ判断ですが、Swift では型シグネチャに `throws` キーワードと `?` という最小コストで明示できる点が優れています。

---

## ZoomacIt 実コード読解 — 二つの `captureScreen` を並べて読む

最後に、本章の主役である二つの実装を、行単位で対比しながら読み解きます。

### Break Timer 版 (BreakTimerWindowController.swift:185-218)

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

| 行 | 役割 |
|----|------|
| 185-190 | `static`, `private`, `async`, `CGImage?` のシグネチャ宣言 |
| 191-194 | 権限の事前チェック。未許可なら NSLog して `nil` |
| 196 | `do-catch` 全体を囲み、すべての throws を吸収 |
| 197 | `SCShareableContent` を `try await` で取得 |
| 198-201 | 目的のディスプレイを `displays.first(where:)` で検索、無ければ `nil` |
| 203 | `SCContentFilter` 構築 |
| 204-208 | `SCStreamConfiguration` 構築 |
| 210-213 | `SCScreenshotManager.captureImage` を `try await` で呼んで戻り値を返す |
| 214-217 | `catch` で NSLog して `nil` |

### Still Zoom 版 (StillZoomWindowController.swift:137-171)

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

| 行 | 役割 |
|----|------|
| 137-142 | `static`, `private`, `async throws`, `CGImage` のシグネチャ宣言 |
| 143-145 | `SCShareableContent` を `try await` で取得 (失敗は外へ伝播) |
| 146-148 | ディスプレイ検索、見つからなければ `CaptureError.displayNotFound` を `throw` |
| 150 | `SCContentFilter` 構築 |
| 151-155 | `SCStreamConfiguration` 構築 |
| 157-160 | `SCScreenshotManager.captureImage` を `try await` で呼んで戻り値を返す |

### 差分のサマリ

中身の **API 呼び出しは完全に同一** です。違うのは外側の包み方だけ。

- Break Timer: `do-catch` + `nil` 返却 + 権限事前チェック (NSLog で詳細記録)
- Still Zoom: `throws` 伝播 + `CaptureError` enum 定義

`design/Zoom.md` には、Still Zoom のフロー全体が次のように示されています。

```
【Still Zoom】
⌃1押下
  → SCScreenshotManager.captureImage()  ← 1枚だけキャプチャ
  → CGImageをCALayerに設定
  → マウス移動/スクロールでcontentsRect更新
  → Escape/右クリックでオーバーレイ破棄
```

> 引用元: design/Zoom.md:201-206

つまり Still Zoom の責務は「キャプチャした 1 枚を CALayer に流し込み、`contentsRect` で領域を切り出す」だけ。GPU 側で拡大が走るので CPU 負荷は最小です。本章の主題ではありませんが、ScreenCaptureKit 側を「正しく一枚撮ってもらう」までで仕事が完結する、という前提が大事です。

---

## ハンズオン (任意)

理解を深めたい方は、次の課題に挑戦してみてください。

### 課題 1: `showsCursor` を切り替える

Break Timer の `captureScreenImage` で `config.showsCursor = true` に変更し、ビルドして Break Timer を起動してください。背景画像にマウスカーソルがそのまま焼き込まれることを確認してください。なぜ Break Timer ではこれが望ましくないかを、自分の言葉で説明できればこの章の理解は十分です。

### 課題 2: Break Timer の関数を `throws` 版にリファクタする

`captureScreenImage` を `throws` 版に書き換え、呼び出し側 (`showTimer`) で `do-catch` を組んでください。catch 節では「キャプチャ失敗を NSLog したうえで nil を渡して `presentTimer` を呼ぶ」という挙動を維持してください。**外形的な振る舞いは変えずに、エラー伝搬の経路だけを変える** 練習です。書き終えたら、現行コードと比べて「どちらが意図を伝えやすいか」を考察してください。

### 課題 3: Still Zoom 版に `CaptureError` ケースを追加する

現在の `CaptureError` は `displayNotFound` だけです。`SCShareableContent.excludingDesktopWindows` 呼び出しが失敗したケースを `case underlyingError(Error)` として明示的に区別する形に書き換えてみてください。`errorDescription` も適切に追記してください。`throws` の利点 (= 型を使ってエラーを分類できる) を体感する課題です。

### 課題 4: 解像度を `width / 2` にして撮る

`config.width` と `config.height` から `* scaleFactor` を外してみてください。Zoom を起動して、拡大時の画質劣化を観察してください。Retina スケールの掛け算が「飾り」ではなく必須であることが体感できます。

---

## 章のまとめ

- **ScreenCaptureKit** は macOS 12.3 で導入された画面キャプチャの新標準。`async/await` ベース、構造化された権限管理、`SCDisplay` / `SCWindow` の明示的なオブジェクトモデルが特徴
- **権限**: Screen Recording が必須。`CGPreflightScreenCaptureAccess()` で事前チェック、`CGRequestScreenCaptureAccess()` でシステム設定誘導。`.app` バンドルでなければ TCC が壊れるので注意
- **`SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)`** で `SCDisplay` / `SCWindow` 一覧を取得。`async throws` なので `try await` で待つ
- **`SCContentFilter`** で「何を」キャプチャするか表現。ZoomacIt は `SCContentFilter(display:excludingWindows: [])` でディスプレイ全体を選択
- **`SCStreamConfiguration`** で「どう撮るか」を指定。`width`/`height` には **必ず `backingScaleFactor` を掛ける**。`pixelFormat = kCVPixelFormatType_32BGRA` と `showsCursor = false` が ZoomacIt の選択
- **`SCScreenshotManager.captureImage(contentFilter:configuration:)`** が一発静止画キャプチャの主役。`async throws -> CGImage` で 1 行で結果が得られる
- **`SCStream`** は連続キャプチャ用 (Live Zoom 等)。`SCStreamOutput` デリゲートでフレームを受け、`CALayer.contents` にゼロコピーで渡すのが定石。ZoomacIt 現バージョンでは未使用
- **`Task { @MainActor in ... }`** で UI スレッドを維持しつつ非同期処理を起動。`@MainActor` 修飾は冗長でも明示する方が意図が伝わる
- **`static func`** にすることで `self` 依存を外し、actor 隔離の問題も最小化する
- **設計判断: Optional vs throws**
  - Break Timer は `async -> CGImage?` で **失敗を nil に丸める**。背景画像は本質ではないため、失敗してもタイマーを止めない
  - Still Zoom は `async throws -> CGImage` で **失敗を伝播する**。画像が無ければ Zoom 機能が成立しないため、上位に明示的にエラーを通知する
  - **同じ API を呼んでいても、業務上の失敗の重みが違えばシグネチャを変える** — Swift の型システムを使った設計表現

ScreenCaptureKit 自体は API 数の多い大きなフレームワークですが、ZoomacIt のように「現在のディスプレイを 1 枚撮りたい」というユースケースなら、**4 つの構成要素 (`SCShareableContent` / `SCContentFilter` / `SCStreamConfiguration` / `SCScreenshotManager`) を順に並べるだけ** で実現できます。Ch21 で学んだ `async/await` と `@MainActor` の知識が、AppKit の世界でこのように実用化されていることを実感していただけたはずです。

## 次に読む章

→ [36. UserDefaults とシングルトン設定](./36-userdefaults.md)
