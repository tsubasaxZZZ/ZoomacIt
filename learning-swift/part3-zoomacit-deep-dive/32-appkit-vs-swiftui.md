# 32. AppKit と SwiftUI の混在

ようこそ Part III へ。Part II では Swift 言語の文法と標準ライブラリを学んできました。ここからは ZoomacIt という具体的な macOS アプリのソースコードを題材に、「なぜこの設計にしたのか」という設計判断のレベルまで踏み込んで読み解いていきます。Part III の最初のテーマは、macOS アプリ開発における 2 つの UI フレームワーク、**AppKit** と **SwiftUI** の使い分けです。

## この章で学ぶこと

- AppKit と SwiftUI が macOS においてどのような立ち位置にあるか、その歴史的経緯
- ZoomacIt が AppKit と SwiftUI をどのように使い分けているか、その設計判断
- AppKit の特徴 — 命令型 UI、`NSView` を継承して `draw(_:)` を override する古典的なスタイル
- SwiftUI の特徴 — 宣言型 UI、`var body: some View` と property wrapper による状態駆動再描画
- 2 つのフレームワークを混在させる橋渡しの仕組み — `NSHostingView` / `NSHostingController` と `NSViewRepresentable`
- 「なぜ ZoomacIt は描画も SwiftUI で書かなかったのか」「なぜ Settings は AppKit で書かなかったのか」という設計上の意思決定

この章では API の細部には踏み込みません。`NSView` を継承した具体的な描画コードの読み解きは次章 (Ch33) に、SwiftUI の property wrapper の詳細はさらに後の章に委ねます。本章は **概観と設計判断の理解** に集中します。

---

## macOS の 2 つの UI フレームワーク

macOS には現在、Apple が公式にサポートする UI フレームワークが 2 つ並立しています。AppKit と SwiftUI です。両者は競合するものではなく、設計思想の異なる 2 つの選択肢として共存しており、現代の macOS アプリは多くの場合この 2 つを使い分けながら構築されます。ZoomacIt も例外ではありません。

### AppKit — 1989 年から続く命令型フレームワーク

AppKit のルーツは、Steve Jobs が NeXT 社で開発した **NeXTSTEP** (1989 年初版) に遡ります。当時の名称は `AppKit` ではなく `Application Kit` で、Objective-C で記述されていました。Apple が 1996 年に NeXT を買収し、その技術が Mac OS X (現 macOS) の基盤となった結果、`NSWindow`, `NSView`, `NSButton` といった `NS` 接頭辞のついたクラス群がそのまま macOS の標準 UI フレームワークとなりました。`NS` は **NeXTSTEP** の略で、35 年以上前の名残が現代の macOS API に今なお息づいています。

AppKit は典型的な **命令型 (imperative)** UI フレームワークです。「どう描くか」「どんな順序で何をするか」をプログラマが手続き的に記述します。

- `NSView` を継承し、`draw(_:)` メソッドを override してピクセルを描く
- `NSWindow` を `init` で作成し、プロパティを次々に設定し、`makeKeyAndOrderFront(_:)` で表示する
- マウスイベントは `mouseDown(with:)`, `mouseDragged(with:)`, `mouseUp(with:)` を override して受け取る
- 状態が変わったら自分で `setNeedsDisplay(_:)` を呼んで再描画を要求する

長い歴史と引き換えに、AppKit には膨大な API 群と細かい制御の自由度があります。透明ウィンドウ、ボーダーレスウィンドウ、ピクセル単位の `CGContext` 描画、グローバルなキー/マウスイベントのハンドリングなど、macOS の OS レイヤーに深く触れる仕事は今でも AppKit でなければ書けません。

### SwiftUI — 2019 年に登場した宣言型フレームワーク

一方の SwiftUI は、WWDC 2019 で発表された比較的新しいフレームワークです。Swift 言語の表現力 (`some View`, property wrapper, result builder) を最大限に活かす設計で、**宣言型 (declarative)** のアプローチを採ります。

- 「UI とはこういうものだ」と `body` プロパティで宣言する
- 状態 (`@State`, `@Binding`, `@AppStorage` など) が変わると、SwiftUI ランタイムが自動的に差分を計算して再描画する
- レイアウトは `VStack`, `HStack`, `ZStack` といった構造体を入れ子にすることで表現する
- マルチプラットフォーム (macOS / iOS / watchOS / tvOS / visionOS) でほぼ同じコードが動く

SwiftUI の設計思想は React や Flutter といったモダンな宣言型 UI フレームワークと共通しており、フォーム入力、リスト表示、設定画面など **状態と UI の対応付けが明確な画面** を最小限のコードで書けます。

| 観点 | AppKit | SwiftUI |
| --- | --- | --- |
| 登場年 | 1989 (NeXTSTEP) | 2019 |
| パラダイム | 命令型 | 宣言型 |
| 主言語 | Objective-C → Swift | Swift 専用 |
| 描画モデル | `draw(_:)` を override | `body` を宣言、ランタイムが差分更新 |
| 状態管理 | プロパティを手動で更新 + `setNeedsDisplay` | property wrapper による自動再描画 |
| OS レイヤー制御 | 細かく可能 (NSWindow, NSEvent...) | 限定的 (`NSViewRepresentable` 必要) |
| マルチプラットフォーム | macOS 専用 | macOS / iOS / watchOS / tvOS / visionOS |

両者は **どちらが優れているという話ではなく、得意分野が違う** だけです。Apple 自身も「適材適所」を公式に推奨しています。重要なのは、自分が作ろうとしている UI がどちらのパラダイムに馴染むかを見極めることです。

---

## ZoomacIt の使い分け設計

ZoomacIt はこの 2 つを意図的に使い分けています。割合としては圧倒的に AppKit が多く、SwiftUI は設定ダイアログのみに限定されています。

| コンポーネント | 使用フレームワーク | 主なファイル |
| --- | --- | --- |
| アプリ起動・ライフサイクル | AppKit (`NSApplicationDelegate`) | `App/main.swift`, `App/AppDelegate.swift` |
| メニューバー (`NSStatusItem`) | AppKit | `App/StatusBarController.swift` |
| オーバーレイウィンドウ (透明・最前面) | AppKit (`NSWindow` サブクラス) | `Overlay/OverlayWindow.swift` |
| 描画キャンバス (ピクセル描画 + マウス処理) | AppKit (`NSView` サブクラス) | `Draw/DrawingCanvasView.swift` |
| 画面キャプチャ表示 | AppKit + ScreenCaptureKit | `Overlay/OverlayWindowController.swift` |
| ホットキー (Carbon API) | AppKit と直接の依存はないが C 系 API | `Core/HotkeyManager.swift` |
| **設定ダイアログ (Preferences)** | **SwiftUI** | `Settings/SettingsView.swift`, 各 `*Tab.swift` |
| Settings ウィンドウのホスト | AppKit (`NSWindowController`) | `Settings/SettingsWindowController.swift` |

この分担はかなりはっきりしています。ピクセルを直接触る仕事・OS レイヤーに深く食い込む仕事はすべて AppKit、フォーム入力やタブ切り替えだけで済む設定画面は SwiftUI、という線引きです。

なぜこの分担になったのか、設計ドキュメントには次のように明記されています。

> Draw 機能の全要件が AppKit ネイティブ API に 1:1 で対応するため採用。将来の設定画面は `NSHostingController` 経由で SwiftUI を導入可能。
>
> 引用元: design/ARCHITECTURE.md:265-266

つまり、Draw 機能 (透明オーバーレイ、3 層合成、修飾キー中ドラッグ) は AppKit でなければ書けないので AppKit を採用、設定画面は SwiftUI のほうが圧倒的に楽なので SwiftUI を採用、という二段階の判断です。両者の境界は `NSHostingController` という橋渡し API が引き受けます。これについては後述します。

---

## AppKit の特徴 — 命令型と継承の世界

ZoomacIt のメニューバーアイコンを実装している `StatusBarController` は、AppKit の典型的なコードです。`NSObject` を継承し、`NSStatusItem` を作成し、`NSMenu` と `NSMenuItem` を組み立て、`@objc` アクションメソッドで反応する。すべて 1989 年からほぼ変わらないスタイルです。

```swift
private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    NSLog("[StatusBar] statusItem created: %@", statusItem != nil ? "yes" : "no")

    guard let button = statusItem?.button else {
        NSLog("[StatusBar] ERROR: button is nil")
        return
    }

    // Use custom menu bar icon from asset catalog
    if let image = NSImage(named: "MenuBarIcon") {
        image.isTemplate = true
        button.image = image
        ...
    }
    statusItem?.menu = buildMenu()
}
```

> 引用元: src/ZoomacIt/App/StatusBarController.swift:33-61

このコードを眺めると、AppKit の命令型らしさがよく分かります。

1. `NSStatusBar.system.statusItem(...)` で「ステータスバーのアイテムをくれ」と OS に命令する
2. 返ってきたオブジェクトのプロパティ (`button.image`) を上書きする
3. `buildMenu()` で `NSMenu` を組み立て、`statusItem?.menu` に代入する
4. 状態が変わったら `rebuildMenu()` を呼んでメニュー全体を作り直す

「いつ何が起きるか」「何を更新するか」をすべてプログラマが指示します。SwiftUI のように「メニューはこういう構造だ」と宣言して終わり、ということはありません。

### `NSView` を継承し `draw(_:)` を override する

AppKit のもう一つの典型的なパターンが、`NSView` のサブクラス化です。ZoomacIt の心臓部である `DrawingCanvasView` は、まさにこのパターンの集大成です。

```swift
final class DrawingCanvasView: NSView {

    // MARK: - 3-Layer Architecture

    /// Confirmed strokes rasterized into a single bitmap.
    private var finishedLayer: CGImage?

    /// Shape preview path during drag (line/rect/ellipse/arrow).
    private var previewLayer: NSBezierPath?

    /// Freehand path being drawn.
    private var activeFreehand: NSBezierPath?
    ...

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw background (captured screen or whiteboard/blackboard)
        drawBackground(in: context)

        // 2. Draw finishedLayer (all confirmed strokes)
        if let finished = finishedLayer {
            context.draw(finished, in: bounds)
        }

        // 3. Draw previewLayer (shape being dragged)
        if let preview = previewLayer { ... }

        // 4. Draw activeFreehand (freehand path being drawn)
        if let freehand = activeFreehand { ... }
    }
```

> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:12-114

注目すべき点は次の通りです。

- **`NSView` を継承している** — これは古典的なオブジェクト指向の継承で、`draw(_:)` を override することで「自分はこう描く」と表明する
- **3 つのプロパティを直接保持している** — `finishedLayer`, `previewLayer`, `activeFreehand`。これは `@State` ではなく単なるインスタンス変数
- **`draw(_:)` 内で `CGContext` を取り出して命令的に描いている** — 順序を間違えると重ね順がおかしくなる
- **再描画は `setNeedsDisplay(bounds)` を自分で呼ぶ** — マウスイベント処理のたびに呼んでいる

マウスイベントもまた、override で受け取ります。

```swift
override func mouseDown(with event: NSEvent) { ... }
override func mouseDragged(with event: NSEvent) { ... }
override func mouseUp(with event: NSEvent) { ... }
override func keyDown(with event: NSEvent) { ... }
override func flagsChanged(with event: NSEvent) { ... }
```

> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:133-319

`flagsChanged(with:)` は修飾キー (Shift, Control, Tab) の押下/離脱を検出するメソッドで、ZoomacIt のドラッグ中シェイプ切替には不可欠です。後述するように、この粒度のイベントハンドリングは SwiftUI の `DragGesture` では取得できません。

### `@MainActor` でのスレッド分離

AppKit のコードは原則としてメインスレッドで実行する必要があります。Swift 6 の strict concurrency 環境では、これを **コンパイル時に強制** するために `@MainActor` 属性を付けます。`StatusBarController` も `DrawingCanvasView` も、(またはそれらを保持するクラスが) `@MainActor` で隔離されています。

```swift
@MainActor
final class StatusBarController: NSObject { ... }
```

> 引用元: src/ZoomacIt/App/StatusBarController.swift:4-5

`@MainActor` を付けることで、このクラスのメソッドやプロパティへのアクセスはメインスレッドからしか行えなくなり、バックグラウンドスレッドからアクセスしようとするとコンパイルエラーになります。AppKit と Swift 6 の concurrency モデルを安全に統合するための重要な仕組みです。

### AppKit 採用の設計判断

ZoomacIt が AppKit を主軸に選んだ理由は、設計ドキュメントに表形式でまとめられています。

> | 観点 | AppKit | SwiftUI |
> |---|---|---|
> | 透明オーバーレイウィンドウ | `NSWindow` で直接制御 | `NSViewRepresentable` ハック必要 |
> | 3 層合成描画 | `draw(_:)` + `CGContext` で命令的に制御 | `Canvas` は宣言的、毎フレーム全再描画 |
> | 修飾キー中ドラッグ | `mouseDragged` + `modifierFlags` | `DragGesture` では修飾キー取得不可 |
> | イベントハンドリング | mouseDown/Dragged/Up/keyDown/flagsChanged | 粒度が不足 |
>
> 引用元: design/ARCHITECTURE.md:258-263

要点は **「ZoomacIt が必要とする操作のすべてが AppKit のネイティブ API に 1:1 で対応している」** ということです。SwiftUI でも頑張れば実現できる項目もありますが、`NSViewRepresentable` で AppKit の機能をラップする手間が発生し、結局 AppKit を書くことになります。それなら最初から AppKit で書くほうが自然です。

また、設計ドキュメントには別の設計ポイントも明記されています。

> SwiftUI の `@main App` ではなく `NSApplicationDelegate` を採用 (AppKit ネイティブのイベントハンドリングが必要なため)
>
> 引用元: design/ARCHITECTURE.md:76-77

通常の SwiftUI macOS アプリでは `@main` を付けた `App` 構造体がエントリーポイントになりますが、ZoomacIt はそれを使わず、明示的な `main.swift` から `NSApp.run()` を呼ぶ古典的な AppKit スタイルを採用しています。ホットキーやステータスバーの初期化など、起動シーケンスを完全に制御したいためです。

---

## SwiftUI の特徴 — 宣言型と property wrapper

対照的に、ZoomacIt の設定ダイアログは SwiftUI で書かれています。`SettingsView` を見てみましょう。

```swift
import SwiftUI

/// Root settings view with tabs for each configuration category.
struct SettingsView: View {

    @State private var showResetAlert = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralTab()
                    .tabItem { Text("General") }
                DrawTab()
                    .tabItem { Text("Draw") }
                ZoomTab()
                    .tabItem { Text("Zoom") }
                BreakTimerTab()
                    .tabItem { Text("Break Timer") }
            }
            .frame(minWidth: 480, minHeight: 320)

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    showResetAlert = true
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .padding()
        .alert("Reset to Defaults", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Settings.shared.resetToDefaults()
                HotkeyManager.shared.reregisterHotkeys()
            }
        } message: {
            Text("All settings will be restored to their default values. This cannot be undone.")
        }
        .onDisappear {
            BreakTimerWindowController.stopTestSound()
        }
    }
}
```

> 引用元: src/ZoomacIt/Settings/SettingsView.swift:1-47

このコードと先ほどの `StatusBarController` を比べてみてください。スタイルがまったく違います。

### `struct` で宣言する、`class` ではない

まず注目すべきは、`SettingsView` が **クラスではなく構造体** だということです。SwiftUI のビューはすべて値型 (struct) で、`View` プロトコルに準拠します。`NSView` のサブクラスのようにインスタンスが「永続的に存在する」のではなく、状態が変わるたびに `body` から新しいビュー記述が生成され、SwiftUI ランタイムが内部的に差分を計算して実際の描画を更新します。

### `var body: some View` で UI を宣言する

`body` プロパティが SwiftUI の本体です。「この View は何でできているか」を **宣言** します。`VStack { ... }`, `HStack { ... }`, `TabView { ... }` といった構造体を入れ子にすることで、レイアウトと階層が表現されます。命令型のように `addSubview(_:)` を呼ぶことはありません。

戻り値の型は `some View` で、**opaque return type** という Swift の機能を使っています。具体的な型 (`VStack<TupleView<(...)>>` のような長大な複合型) を隠蔽し、「`View` プロトコルに準拠する何か」とだけ表明することで、ビューの組み立てを軽快に書けます。

### `@State` による状態駆動再描画

`@State private var showResetAlert = false` という宣言に注目してください。これは **property wrapper** という Swift の機能で、`SettingsView` という struct (値型) でありながら **書き換え可能な状態** を持てるようにする仕掛けです。

- `showResetAlert` の値が変わると、SwiftUI は自動的に `body` を再評価する
- 結果として `.alert(...)` モディファイアの `isPresented` 引数が `true` になり、アラートが表示される
- プログラマは `setNeedsDisplay` のような再描画指示を一切書かない

これが **宣言型** の核心です。「状態と UI の対応関係を宣言しておけば、状態が変わると UI が自動で追随する」という思想です。AppKit のように「マウスイベントを受けたら手で `setNeedsDisplay(bounds)` を呼ぶ」ことは不要です。

ZoomacIt の各タブ (`DrawTab`, `ZoomTab`, `BreakTimerTab` など) では、設定値と UI コントロールを `@AppStorage` や `@Binding` で結びつけています。これらの property wrapper の詳細は後の章で扱いますが、共通する考え方は「状態を宣言する → UI が自動追随する」というものです。

### SwiftUI の何が楽か

設定画面のような UI を AppKit で書こうとすると、`NSTabView`, `NSButton`, `NSSlider`, `NSTextField`, `NSAlert` といった NS クラスを `init` で作って `addSubview` で配置し、Auto Layout の制約を `NSLayoutConstraint` でひとつずつ設定し、ボタンの `target` と `action` を結線し、設定値が変わったらコントロールを手動で更新する、という大量のボイラープレートが必要です。

SwiftUI は同じことを 30 行程度で書けます。フォーム入力、リスト、タブ切替、アラートといった「定型的な UI 部品の組み合わせ」が中心の画面で、SwiftUI は圧倒的な生産性を発揮します。**ZoomacIt が設定画面に SwiftUI を選んだのは、まさにこの生産性のためです**。

---

## AppKit と SwiftUI の橋渡し

「主軸は AppKit、設定だけ SwiftUI」という方針を実現するには、両者を実行時に接続する仕組みが要ります。Apple は双方向の橋渡し API を提供しています。

| 方向 | API | 用途 |
| --- | --- | --- |
| SwiftUI を AppKit に埋め込む | `NSHostingView`, `NSHostingController` | AppKit の `NSWindow` の中で SwiftUI ビューを表示する |
| AppKit を SwiftUI に埋め込む | `NSViewRepresentable`, `NSViewControllerRepresentable` | SwiftUI のビュー階層に既存の `NSView` を組み込む |

ZoomacIt が使っているのは **前者** です。設定ウィンドウは AppKit の `NSWindow` で作り、その中身として SwiftUI の `SettingsView` をホストします。

### `NSHostingController` で SwiftUI を AppKit ウィンドウに埋め込む

`SettingsWindowController` のコードを見てください。これが橋渡しの実装です。

```swift
import AppKit
import SwiftUI

/// Manages the Settings window (NSWindow hosting SwiftUI SettingsView).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    func showWindow() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "ZoomacIt Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
    ...
}
```

> 引用元: src/ZoomacIt/Settings/SettingsWindowController.swift:1-32

ポイントを順に見ていきましょう。

1. **`import AppKit` と `import SwiftUI` の両方** を読み込んでいる。両者を混在させるファイルはこうなります
2. **クラスは `NSObject` を継承し `NSWindowDelegate` に準拠** — AppKit のウィンドウ管理の流儀
3. **`SettingsView()` を生成** — これは SwiftUI の View struct
4. **`NSHostingController(rootView: settingsView)`** — SwiftUI ビューを AppKit の `NSViewController` でラップする魔法。`NSHostingController` は `NSViewController` のサブクラスで、内部に SwiftUI ランタイムを持ち、与えられた `rootView` を描画します
5. **`NSWindow(contentViewController: hostingController)`** — できあがった `NSViewController` を、これまた AppKit の `NSWindow` のコンテンツビューとして設置

つまり、**「SwiftUI ビュー → `NSHostingController` で AppKit の世界に変換 → AppKit の `NSWindow` に乗せる」** という三段階の変換が起きています。SwiftUI の世界と AppKit の世界はこの境界線で完全に分離されており、それぞれの世界の中では純粋にそのフレームワーク流のコードを書けます。

### 逆方向: `NSViewRepresentable`

逆方向の橋渡しも知っておくと便利です。SwiftUI のビュー階層の中に既存の `NSView` を埋め込みたい場合は、`NSViewRepresentable` プロトコルに準拠した薄いラッパー struct を書きます。例えば、ZoomacIt の `DrawingCanvasView` を仮に SwiftUI のビュー階層に埋め込もうとすると、次のようなラッパーが必要になります。

```swift
struct DrawingCanvasRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> DrawingCanvasView {
        DrawingCanvasView(frame: .zero, backgroundImage: nil)
    }
    func updateNSView(_ nsView: DrawingCanvasView, context: Context) {
        // 状態を NSView に反映するコード
    }
}
```

ZoomacIt は実際にはこの方向の橋渡しは使っていません。設計ドキュメントの言葉を借りれば、**「`NSViewRepresentable` ハック」が要らないように設計の境界を引いたから** です。Draw キャンバスは AppKit の世界の中で完結させ、SwiftUI の中に持ち込まない。これが ZoomacIt の設計判断です。

---

## 設計判断の振り返り

ここまで見てきた使い分けを、改めて 2 つの視点から問い直してみましょう。

### なぜ ZoomacIt は描画も SwiftUI で書かなかったのか

SwiftUI には `Canvas` というビューがあり、宣言的に `GraphicsContext` に描画できます。一見、Draw 機能もこれで書けそうに思えます。実際、シンプルな図形描画なら SwiftUI で十分です。しかし ZoomacIt の Draw には次の要件があります。

1. **透明・ボーダーレス・最前面・全 Space のオーバーレイウィンドウ** — `NSWindow` のサブクラス化と `collectionBehavior` の細かい制御が必要
2. **3 層合成 (`finishedLayer` + `previewLayer` + `activeFreehand`) のピクセル単位の制御** — 確定ストロークを `CGBitmapContext` にラスタライズし、毎フレームの再描画コストを抑える
3. **修飾キー中ドラッグでシェイプを切り替える** — Shift/Control/Tab を押している間だけ図形が直線/矩形/楕円に変わる
4. **`mouseDragged` 中に `flagsChanged` で修飾キーを検出して即座にプレビュー更新**

設計ドキュメントの表が示すように、これらはすべて AppKit ネイティブ API に 1:1 で対応します。一方 SwiftUI の `DragGesture` は修飾キー情報を渡してくれず、`Canvas` は毎フレーム全描画モデルなので 3 層合成の最適化が難しい。`NSViewRepresentable` で AppKit の `NSView` をラップして SwiftUI に埋めることもできますが、それは結局 AppKit を書いていることになります。

> Draw 機能の全要件が AppKit ネイティブ API に 1:1 で対応するため採用。
>
> 引用元: design/ARCHITECTURE.md:265

「ピクセル制御 + 低レベルイベント処理が中心の画面は AppKit」 — これは ZoomacIt の明確な設計原則です。

### なぜ Settings は AppKit で書かなかったのか

逆に、設定画面を AppKit で書くことも当然できます。`NSTabView`, `NSButton`, `NSAlert` を組み合わせれば、機能的には同じものが作れます。なぜしなかったのか。

理由は単純で、**コード量と保守性が桁違いに不利だから** です。

- AppKit で書くと、各コントロールの生成・配置・Auto Layout 制約・イベント結線・状態同期で軽く 5 倍〜10 倍のコード量になる
- 設定値の変更検知を `target/action` で結線し、コントロールの値を手動で同期する必要がある
- タブ切替、アラート、フォーム入力といった定型 UI に AppKit の細かい制御は要らない

SwiftUI の `@State`, `@AppStorage`, `@Binding` を使えば、設定値とコントロールが自動同期され、再描画も自動です。**コードが「やりたいこと」をそのまま表現する** ようになります。`SettingsView` の 47 行のコードを AppKit で再現すれば、控えめに見ても 200〜300 行は必要でしょう。

「フォーム入力 + 階層的な設定が中心の画面は SwiftUI」 — これも ZoomacIt の設計原則です。

### 境界の引き方が設計の本質

ZoomacIt の AppKit / SwiftUI の使い分けは、技術的な能力の問題というよりも **「どこに境界を引くか」という設計判断** です。境界を `NSHostingController` という単一のクラスに集約し、その内側と外側ではそれぞれのフレームワーク流のコードを書く。両者が混ざり合うコードを書かない。これが混在を破綻させずに保つコツです。

もし将来 ZoomacIt に別のオプションウィンドウを追加するとしても、同じパターンが使えます。新しい SwiftUI ビューを定義し、`NSHostingController` でラップし、新しい `NSWindowController` から表示する。逆に新しいオーバーレイ機能 (例: スクリーンショット範囲選択) を追加するなら、それは AppKit の `NSWindow` サブクラスとして実装する。境界線が明確だから、追加の判断が迷わずに済みます。

---

## ハンズオン (任意)

時間があれば、`SettingsWindowController.swift` を開いて次のことを試してみてください。

1. `NSHostingController(rootView: settingsView)` の行をコメントアウトし、代わりに自分で作った `NSView` のサブクラスを `window.contentView` にセットしてみる。SwiftUI を AppKit ウィンドウから外したら何が起きるか
2. `SettingsView.swift` の `@State private var showResetAlert = false` を、ただの `var showResetAlert = false` (property wrapper なし) に変えてみる。Swift コンパイラが何と言うか
3. `DrawingCanvasView.swift` の `override func draw(_ dirtyRect: NSRect) { ... }` を空にすると、Draw モードを起動しても何も描かれなくなる。AppKit が `draw(_:)` の override を「絶対に呼ぶ前提」で動いていることを確認する

これらを通して、AppKit と SwiftUI の責務の違いと、両者を結ぶ橋渡し API の役割を体感できるはずです。

---

## まとめ

- AppKit は 1989 年の NeXTSTEP 由来の命令型 UI フレームワーク。`NSView` を継承し `draw(_:)` を override し、自分で再描画を要求する古典的なスタイル。OS レイヤーへの細かい制御が可能
- SwiftUI は 2019 年に登場した宣言型 UI フレームワーク。`View` プロトコルに準拠した struct と `body` プロパティで UI を宣言し、property wrapper による状態駆動再描画で記述が劇的に短くなる
- ZoomacIt は **ピクセル制御と低レベルイベントが必要なところは AppKit、フォーム入力中心の設定画面は SwiftUI** という明確な使い分けをしている
- 両者の橋渡しは `NSHostingController` (SwiftUI を AppKit に埋め込む) と `NSViewRepresentable` (AppKit を SwiftUI に埋め込む) で行う。ZoomacIt は前者のみを使用
- 設計の本質は **境界線の引き方**。境界を `SettingsWindowController` に集約することで、両者が混ざり合うコードを避けている

次章からは、AppKit の中でも特に重要な `NSView` の継承と `draw(_:)` の実装を、`DrawingCanvasView` のコードを題材に詳しく読み解いていきます。

## 次に読む章

→ [33. NSView を継承して描画する](./33-nsview-drawing.md)
