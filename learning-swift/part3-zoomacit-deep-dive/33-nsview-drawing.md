# 33. NSView を継承して描画する

## この章で学ぶこと

AppKit における描画の中核は `NSView` のサブクラス化です。Quartz 2D (Core Graphics) のフルパワーをアプリケーションに取り込みたいとき、開発者は `NSView` を継承し、`draw(_:)` メソッドを override して任意のピクセルを画面に焼き付けることができます。SwiftUI が宣言的な記法でビューを構築するのに対し、`NSView` は命令的でありながら、低レベルの描画 API に対して直接的なアクセスを提供します。

この章では、ZoomacIt のアノテーション機能を支える `DrawingCanvasView` (766 行) を題材に、`NSView` を継承したカスタム描画の設計を解説します。具体的には次の項目を順に扱います。

| トピック | 解説対象 |
|---|---|
| `NSView` 継承の基本 | サブクラス宣言と `draw(_:)` の役割 |
| 描画コンテキスト | `NSGraphicsContext.current?.cgContext` で `CGContext` を取得 |
| イベントハンドリング | マウス・キーボード・修飾キー・スクロールホイール |
| First Responder | `acceptsFirstResponder` とキーボードイベントの導通 |
| 3 層合成パターン | `finishedLayer` / `previewLayer` / `activeFreehand` の設計判断 |
| ラスタライズ | `CGBitmapContext` で確定ストロークを焼き付ける |
| カーソル変更 | `resetCursorRects` でビュー領域内のカーソル形状を切り替え |
| `NSBezierPath` | 線・矩形・楕円・カスタムカーブを表現する |

`DrawingCanvasView` は ZoomacIt 全体の中でも最大のクラスですが、本章では全体を読ませることはしません。代表的な数十行を抜き出し、そこから「複雑な描画ロジックを 3 層に整理する設計判断」を読み解きます。

---

## NSView 継承の基本

`NSView` は AppKit における「描画とイベントの最小単位」です。すべてのビューは矩形領域 (`bounds`) を持ち、その内部にピクセルを描画し、内部に向けて発生したマウス・キーボードイベントを受け取ります。

ZoomacIt の `DrawingCanvasView` は次のように宣言されています。

```swift
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// The main NSView subclass that implements the 3-layer compositing architecture
/// for Draw mode rendering.
///
/// Layer stack (bottom to top):
///   1. `finishedLayer` (CGImage)  — all confirmed strokes rasterized
///   2. `previewLayer`  (NSBezierPath) — shape preview during drag
///   3. `activeFreehand` (NSBezierPath) — freehand path during drag
final class DrawingCanvasView: NSView {
    // ...
    init(frame: NSRect, backgroundImage: CGImage?) {
        self.backgroundImage = backgroundImage
        super.init(frame: frame)
        wantsLayer = false  // Use draw(_:) based rendering, not layer-backed
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:1-61

ここで注目すべき点は三つあります。

第一に、`final class` 宣言です。継承を許さないことで、Swift コンパイラは仮想呼び出し (vtable) を排除し、メソッド呼び出しを直接ディスパッチに最適化できます。描画とイベントが秒間に何度も呼び出される `NSView` サブクラスでは、この最適化は実用上の意味を持ちます。

第二に、`init(coder:)` を `unavailable` で封じています。`NSView` はもともと Interface Builder (XIB / Storyboard) からのインスタンス化を前提とした初期化子 `init?(coder:)` を `NSCoding` プロトコル経由で要求しますが、ZoomacIt はコードでビュー階層を組み立てるため、この経路を完全に閉じています。`@available(*, unavailable)` を付けたうえで `fatalError` を返す書き方は、AppKit / UIKit のコードで頻出するイディオムです。

第三に、`wantsLayer = false` の指定です。AppKit のビューは「レイヤーバックド (layer-backed)」モードで動作させると、ビューの内容が `CALayer` のキャッシュにラスタライズされ、合成は GPU で行われます。一方 `wantsLayer = false` のままにすると、ビューは伝統的な「ビューバックド」モードで動作し、`draw(_:)` が呼び出されるたびに CPU 側で内容を描画します。

`DrawingCanvasView` がレイヤーバックドを使わない理由は、後述する「3 層合成」のロジックが `draw(_:)` の呼び出しを前提としているからです。レイヤーバックドではダーティ領域の管理を `CALayer` 側に委ねるため、`activeFreehand` のような「毎フレーム更新する path」を効率良く描画するには `setNeedsDisplay(_:)` 駆動の伝統的モデルの方が素直に書けます。

---

## NSGraphicsContext と CGContext

`NSView.draw(_:)` の中で実際に描画を行うには、現在のグラフィックスコンテキストを取得します。AppKit では `NSGraphicsContext.current` がスレッドローカルなコンテキストスタックの先頭を返し、その `cgContext` プロパティが Core Graphics の `CGContext` です。

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
    if let preview = previewLayer {
        drawingState.currentNSColor.setStroke()
        if drawingState.isHighlighterMode {
            HighlighterRenderer.applyHighlighterStyle(to: preview, penWidth: drawingState.penWidth)
            let blendMode: CGBlendMode = (backgroundImage != nil) ? .multiply : .normal
            NSGraphicsContext.current?.cgContext.setBlendMode(blendMode)
        } else {
            preview.lineWidth = drawingState.penWidth
            preview.lineCapStyle = .round
            preview.lineJoinStyle = .round
        }
        preview.stroke()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
    }

    // 4. Draw activeFreehand (freehand path being drawn)
    if let freehand = activeFreehand {
        // ...
        freehand.stroke()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
    }
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:71-114

このメソッドが `DrawingCanvasView` の心臓部です。順に見ていきましょう。

冒頭の `guard let context = NSGraphicsContext.current?.cgContext else { return }` は、現在のスレッドに描画コンテキストが設定されていることを確認します。`NSView.draw(_:)` の内側では AppKit が事前にコンテキストを push してくれるため、通常はこの guard が失敗することはありません。それでも `Optional` を返すのは、コンテキストスタックが空のスレッドから誤って `current` を呼ばれる可能性があるためです。

`CGContext` を取得した後、コードは「背景 → 確定ストローク → シェイププレビュー → フリーハンド」という固定の順序で描画を行います。この順序こそが「3 層合成」のレイヤースタックを実装した部分です。

注意したいのは、`NSBezierPath` と `CGContext` の関係です。`preview.stroke()` のような呼び出しは引数を取りませんが、内部では暗黙に `NSGraphicsContext.current` を読み取り、その上に `NSBezierPath` の経路を描画します。つまり `NSBezierPath` は「現在のコンテキストに描く」という暗黙のグローバル状態を前提に動作します。これは古典的な Mac OS の描画モデルを引きずった API 設計で、`UIBezierPath` (UIKit) と動作が完全に同じになるよう設計されています。

`setBlendMode(.multiply)` のような Core Graphics 直叩きの呼び出しを混ぜることもできます。ハイライター描画では下地のピクセルとアルファブレンドする必要があるため、ブレンドモードを切り替えてから `stroke()` を呼んでいます。最後に `setBlendMode(.normal)` で必ずリセットしているのは、コンテキストが共有資源であり、次の描画呼び出しに副作用を残さないための定石です。

---

## NSView のイベントハンドリング

`NSView` はイベントを受け取れるため、ユーザー入力に反応する独自のコントロールを実装できます。マウスイベントは座標を持ち、キーボードイベントは「キーが押された」「修飾キーが変わった」といった状態変化を伝えます。

`DrawingCanvasView` は次の override を備えています。

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
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:133-149

`event.locationInWindow` はウィンドウ座標系での位置を返します。これを `convert(_:from:)` の第 2 引数に `nil` を渡してビュー座標系へ変換するのは AppKit の慣用句です。

```swift
override func mouseDragged(with event: NSEvent) {
    guard isDragging else { return }

    let currentPoint = convert(event.locationInWindow, from: nil)

    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let shapeType = drawingState.currentShapeType(modifiers: modifiers)

    switch shapeType {
    case .freehand:
        freehandPoints.append(currentPoint)
        activeFreehand = FreehandRenderer.smoothedPath(from: freehandPoints)
        previewLayer = nil

    case .line:
        previewLayer = ShapeRenderer.linePath(from: dragOrigin, to: currentPoint)
        activeFreehand = nil

    // ... rectangle / ellipse / arrow も同様
    }

    setNeedsDisplay(bounds)
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:151-183

`event.modifierFlags` はマウスドラッグ中の現在の修飾キー状態を取得します。`.deviceIndependentFlagsMask` でマスクするのは、デバイス依存のフラグ (Caps Lock の機械的状態など) を取り除き、論理的な Shift / Control / Option / Command だけを残すためです。

最後の `setNeedsDisplay(bounds)` はとても重要です。これを呼ばないと AppKit はビューの再描画が必要だと認識せず、`draw(_:)` が呼び出されません。`NSView` の状態を変更したら必ずこのメソッドで「次のディスプレイサイクルで再描画してくれ」と AppKit に通知する、という対応関係を覚えておきましょう。

```swift
override func mouseUp(with event: NSEvent) {
    guard isDragging else { return }
    isDragging = false

    let currentPoint = convert(event.locationInWindow, from: nil)
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let shapeType = drawingState.currentShapeType(modifiers: modifiers)

    // Push current state for undo
    strokeManager.pushUndoSnapshot(finishedLayer, backgroundMode: drawingState.backgroundMode)

    // Composite the completed stroke onto finishedLayer
    finishedLayer = compositeStrokeOntoFinished(
        shapeType: shapeType,
        endPoint: currentPoint
    )

    // Clear transient layers
    previewLayer = nil
    activeFreehand = nil
    freehandPoints.removeAll()

    setNeedsDisplay(bounds)
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:185-208

`mouseUp` でストロークが「確定」します。具体的には、`previewLayer` または `activeFreehand` の現在の path を `finishedLayer` (CGImage) に焼き付け、一時レイヤーをクリアします。「確定」のタイミングで Undo スナップショットも積み上げ、後に `⌘Z` で巻き戻せるようにしています。

```swift
override func rightMouseDown(with event: NSEvent) {
    if drawingState.isTextMode {
        commitCurrentText()
    }
    onDismiss?()
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:210-217

`rightMouseDown` で Draw モードを抜けるのは ZoomIt 由来の操作仕様です。`onDismiss` クロージャを呼ぶことで、上位のオーバーレイコントローラがウィンドウを閉じ、状態を破棄できます。

### 修飾キーの変化を捕まえる

ZoomacIt の Draw モードは「マウスドラッグ中に修飾キーを押すと形状が切り替わる」という独特な操作体系を持ちます。これを実現するために `flagsChanged(with:)` を override しています。

```swift
override func flagsChanged(with event: NSEvent) {
    // Modifier changes during drag cause shape type to update.
    if isDragging {
        mouseDragged(with: event)
    }
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:312-319

`flagsChanged(with:)` は Shift / Control / Option / Command などの修飾キーの押下・離脱を検知します。ドラッグ中にこの呼び出しが来たら、`mouseDragged(with:)` を再呼び出しすることで「同じ位置だが新しい修飾キー状態でのプレビュー」を再計算しています。これにより、ドラッグしたまま Shift を押すと直線、Control を加えると矩形、というシームレスな切替が実現します。

### スクロールホイール

スクロールホイールは `scrollWheel(with:)` で扱います。

```swift
override func scrollWheel(with event: NSEvent) {
    let modifiers = event.modifierFlags

    if drawingState.isTextMode {
        textInputController?.adjustFontSize(delta: event.scrollingDeltaY)
        return
    }

    if modifiers.contains(.control) {
        if event.scrollingDeltaY > 0 {
            drawingState.increasePenWidth()
        } else if event.scrollingDeltaY < 0 {
            drawingState.decreasePenWidth()
        }
    }
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:323-340

`event.scrollingDeltaY` は連続的なホイール回転量を Float として返します。トラックパッドの慣性スクロールやマウスホイールのクリック単位など、入力デバイスの違いを吸収した値です。`Control` キーと組み合わせることで、システム全体のスクロール挙動と衝突しないようにしています。

---

## First Responder

キーボードイベントを受け取るには、ビューが「First Responder」である必要があります。First Responder とは、現在のキーボード入力を最初に受け取るオブジェクトのことで、ウィンドウごとに 1 つだけ存在します。

`NSView` がキーボードイベントを受け取る権利を持つことを宣言するには、`acceptsFirstResponder` を `true` にします。

```swift
// MARK: - Keyboard Events

override var acceptsFirstResponder: Bool { true }

override func keyDown(with event: NSEvent) {
    guard let characters = event.charactersIgnoringModifiers?.uppercased() else { return }
    let modifiers = event.modifierFlags

    switch characters {
    // Exit draw mode
    case "\u{1B}": // Escape
        if drawingState.isTextMode {
            commitText()
        } else {
            onDismiss?()
        }

    // Color keys
    case "R", "G", "B", "O", "Y", "P":
        if let color = PenColor.from(character: characters) {
            // ...
        }

    // Clear all
    case "E":
        strokeManager.pushUndoSnapshot(finishedLayer, backgroundMode: drawingState.backgroundMode)
        finishedLayer = nil
        setNeedsDisplay(bounds)

    // ... 以下、W / K / T / Tab / Space / ⌘Z / ⌘C / ⌘S
    default:
        break
    }
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:221-303

ここで重要な API は `event.charactersIgnoringModifiers` です。これは「修飾キーを無視した場合の文字」を返します。たとえば `Shift+R` を押した場合、`event.characters` は `"R"` を返しますが、`Shift+1` を押すと `event.characters` は `"!"` を返します。`charactersIgnoringModifiers` を使うと後者でも `"1"` が返るため、修飾キーの組み合わせを判定する際の分岐が安定します。

`acceptsFirstResponder` を `true` にしただけでは First Responder にはなりません。実際にキー入力を受け取るには、ビューを表示する側 (オーバーレイウィンドウのコントローラ) が `window.makeFirstResponder(canvasView)` を呼び出す必要があります。`DrawingCanvasView` 自身はキーを受け取る「資格」を宣言するだけで、実際の制御はウィンドウ側が握っています。

`keyUp(with:)` も対称的に override されており、`Tab` キーの離脱を検知して `drawingState.isTabHeld` を `false` に戻しています。`Tab` は AppKit の標準的なフォーカス移動ショートカットでもあるため、フリーハンドに対する楕円描画フラグとして利用するには「押している間だけ有効」という状態管理が必要になります。

```swift
override func keyUp(with event: NSEvent) {
    guard let characters = event.charactersIgnoringModifiers else { return }
    if characters == "\t" {
        drawingState.isTabHeld = false
    }
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:305-310

---

## 3 層合成パターン

ここからが本章の核心です。`DrawingCanvasView` は描画ロジックを「3 層」に分けて整理しています。これは ZoomacIt の Draw 機能を「実装可能で、なおかつパフォーマンスが破綻しない」設計に落とし込むための重要な判断です。

設計ドキュメントでは次のように説明されています。

> シェイプのプレビュー実装
>
> 直線・長方形・楕円・矢印はドラッグ中に「プレビュー」を見せる必要がある。
> `mouseDragged` のたびに finishedLayer を書き換えるのは重いため:
>
> ```
> 描画レイヤー構成:
>   [ finishedLayer  (CGImage) ]   ← 確定済みストローク、変更しない
>   [ previewLayer   (NSBezierPath) ]  ← ドラッグ中のシェイプのみ、mouseUpで破棄
>   [ activeFreehand (NSBezierPath) ]  ← フリーハンドの現在のストローク
> ```
>
> `draw(_:)` 内で 3 層を順に描画し、`mouseUp` 時に `previewLayer` を `finishedLayer` に焼き込む。
> 引用元: design/Draw.md:140-152

`DrawingCanvasView` 内のプロパティ宣言は次のとおりです。

```swift
// MARK: - 3-Layer Architecture

/// Confirmed strokes rasterized into a single bitmap.
private var finishedLayer: CGImage?

/// Shape preview path during drag (line/rect/ellipse/arrow).
private var previewLayer: NSBezierPath?

/// Freehand path being drawn.
private var activeFreehand: NSBezierPath?
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:29-38

各層の責務を表でまとめます。

| 層 | 型 | 描画される頻度 | 寿命 | 役割 |
|---|---|---|---|---|
| `finishedLayer` | `CGImage?` | 確定時のみ更新 | アプリ終了まで蓄積 | 過去のストロークすべてをラスタライズしたビットマップ |
| `previewLayer` | `NSBezierPath?` | ドラッグごと | `mouseUp` で破棄 | 直線・矩形・楕円・矢印のプレビュー |
| `activeFreehand` | `NSBezierPath?` | ドラッグごと | `mouseUp` で破棄 | フリーハンドストロークの現在の path |

ここで重要なのは「型の違い」です。`finishedLayer` だけが `CGImage` (= 既にピクセル化された画像) で、他の 2 つは `NSBezierPath` (= まだベクトルのままのパス) です。なぜこの分け方なのでしょうか。

### なぜ 3 層に分けるのか

仮に「すべてのストロークを `[NSBezierPath]` の配列で持ち、`draw(_:)` で全部描き直す」という素朴な実装を考えてみます。これはストロークが 10 本なら問題なく動きますが、ストロークが 1000 本になると `draw(_:)` のたびに 1000 個の path を `stroke()` し直すことになり、フレームレートが大幅に落ちます。

逆に「すべてを単一のビットマップに即座に焼き付ける」という素朴な実装ではどうでしょうか。これはドラッグ中のシェイププレビュー (たとえば矩形を引き伸ばす操作) では破綻します。なぜなら、プレビューが変化するたびに、過去のストローク全てを再ラスタライズする必要があるからです。

3 層に分ける設計は、この 2 つの極端を融合した最適解です。

| 状況 | コスト |
|---|---|
| ストロークが 1000 本に達しても | `finishedLayer` は 1 枚の CGImage なので描画コストは O(1) |
| ドラッグ中にプレビューが変化しても | `finishedLayer` は触らず、`previewLayer` の path だけ差し替え |
| 確定時に新たな焼き付けが発生しても | 1 ストロークごとに 1 度きりなので体感できない |

「確定済みのものはラスタライズして高速合成」「進行中のものはベクトルのまま柔軟に変形」という二つのモードを共存させる、極めて実用的な設計判断です。

### draw(_:) における合成の順序

3 層の描画順序は固定で、下から「背景 → finishedLayer → previewLayer → activeFreehand」です。一度 `mouseUp` でストロークが確定すると `previewLayer` と `activeFreehand` はクリアされるため、次のフレームでは「背景 + finishedLayer」だけが描画されます。

実装上、`previewLayer` と `activeFreehand` は同時に非 nil になることはありません。`mouseDragged` の switch 文で、フリーハンドモードなら `activeFreehand` を更新し `previewLayer = nil` に、シェイプモードなら逆に設定するからです。これにより、両者を if let で順番にチェックする `draw(_:)` のロジックが、結果として「どちらか一方だけが描画される」ことを保証します。

---

## CGBitmapContext で確定ストロークをラスタライズ

`mouseUp` で発火する「焼き付け処理」を見てみましょう。これは `compositeStrokeOntoFinished` というプライベートメソッドが担います。

```swift
/// Renders the current stroke onto finishedLayer and returns the new CGImage.
private func compositeStrokeOntoFinished(shapeType: ShapeType, endPoint: CGPoint) -> CGImage? {
    let size = bounds.size
    guard size.width > 0 && size.height > 0 else { return finishedLayer }

    guard let bitmapContext = CGContext.createBitmapContext(size: size) else {
        return finishedLayer
    }

    // Draw existing finished layer
    if let existing = finishedLayer {
        bitmapContext.draw(existing, in: CGRect(origin: .zero, size: size))
    }

    // Set stroke properties
    let color = drawingState.currentNSColor
    if drawingState.isHighlighterMode {
        let blendMode: CGBlendMode = (backgroundImage != nil) ? .multiply : .normal
        bitmapContext.setBlendMode(blendMode)
        bitmapContext.setStrokeColor(color.cgColor)
        bitmapContext.setLineWidth(drawingState.penWidth * Settings.shared.highlighterWidthMultiplier)
        bitmapContext.setLineCap(.square)
        bitmapContext.setLineJoin(.round)
    } else {
        bitmapContext.setStrokeColor(color.cgColor)
        bitmapContext.setLineWidth(drawingState.penWidth)
        bitmapContext.setLineCap(.round)
        bitmapContext.setLineJoin(.round)
    }

    // Draw the stroke
    let path: CGPath
    switch shapeType {
    case .freehand:
        let bezier = FreehandRenderer.smoothedPath(from: freehandPoints)
        path = bezier.cgPath
    case .line:
        path = ShapeRenderer.linePath(from: dragOrigin, to: endPoint).cgPath
    // ... rectangle / ellipse / arrow
    }

    bitmapContext.addPath(path)
    bitmapContext.strokePath()

    return bitmapContext.makeImage()
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:344-395

このメソッドの流れを整理すると次のようになります。

1. `CGContext.createBitmapContext(size:)` でオフスクリーンの RGBA ビットマップコンテキストを作る
2. 既存の `finishedLayer` をそのまま描画する (= 過去のストロークを引き継ぐ)
3. ストロークの色・太さ・線端・線結合・ブレンドモードを設定する
4. ストローク種別ごとに `CGPath` を作って `addPath` → `strokePath` で線を描く
5. `bitmapContext.makeImage()` で新しい `CGImage` を作って返す

返ってきた `CGImage` を `finishedLayer` に代入することで、確定済みストロークのレイヤーが「1 ストローク分だけ進んだビットマップ」へと差し替わります。

### CGBitmapContext を作る Utility

`CGContext.createBitmapContext(size:)` は ZoomacIt 自身が用意した extension です。実装はシンプルですが、AppKit / Core Graphics で正しいビットマップコンテキストを作るのは意外と落とし穴が多いため、独立したファイルに切り出されています。

```swift
import CoreGraphics
import AppKit

extension CGContext {

    /// Creates an RGBA bitmap context matching the given size, suitable for
    /// compositing drawing strokes.
    static func createBitmapContext(size: CGSize) -> CGContext? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
    }
}
```
> 引用元: src/ZoomacIt/Utilities/CGContext+Extensions.swift:1-26

各引数の意味を整理します。

| 引数 | 意味 | この実装での値 |
|---|---|---|
| `data` | ピクセルバッファのポインタ。`nil` なら CG が自前で確保 | `nil` |
| `width` / `height` | ピクセル単位のサイズ | 入力 `size` を `Int` 化 |
| `bitsPerComponent` | 1 チャンネルあたりのビット数 | `8` (= 256 階調) |
| `bytesPerRow` | 1 行あたりのバイト数 | `width * 4` (RGBA 4 バイト) |
| `space` | 色空間 | `CGColorSpaceCreateDeviceRGB()` |
| `bitmapInfo` | アルファとビットレイアウトの指定 | `premultipliedLast` (= RGBA、αは事前に乗算済み) |

`premultipliedLast` は AppKit / SwiftUI の標準的なピクセルフォーマットです。`Last` は「アルファチャンネルが各ピクセルの末尾にある (= R, G, B, A の順)」を意味し、`premultiplied` は「RGB 値があらかじめアルファで乗算されている」ことを意味します。Core Graphics で生成した `CGImage` を AppKit の `NSImage` や `CALayer` に渡すときに、最も互換性の高い組み合わせです。

`bytesPerRow = width * 4` の計算は、各ピクセルが 4 バイト (R, G, B, A) で構成されることに由来します。8 ビット * 4 チャンネル = 32 ビット = 4 バイトです。

`data` を `nil` にすると、Core Graphics は内部でピクセルバッファを確保し、コンテキストの解放時に自動的に破棄してくれます。自前でメモリを管理する必要がなく、Swift の ARC との相性も良いため、この記法が推奨されます。

---

## resetCursorRects でカーソル変更

ZoomacIt の Draw モードでは、マウスカーソルが「クロスヘア (十字)」に変わります。これは画面のどこに線を引くかをピクセル単位で示唆するためのものです。

```swift
// MARK: - Cursor

override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
}
```
> 引用元: src/ZoomacIt/Draw/DrawingCanvasView.swift:63-67

`resetCursorRects()` は `NSView` の特殊な override ポイントです。AppKit はビューが画面に表示されるとき、また再レイアウトされるときに、すべてのビューの `resetCursorRects` を呼び出してカーソル割当をリセットします。`addCursorRect(_:cursor:)` で「この矩形にマウスが入ったら、このカーソルを表示してくれ」と AppKit に登録できます。

ビュー全体に同じカーソルを適用したい場合は、上のように `bounds` を渡せば充分です。複数のサブ領域に異なるカーソルを割り当てたい場合は、複数回 `addCursorRect` を呼び出します。たとえば「描画領域はクロスヘア、左下のリサイズハンドルは斜めの両方向矢印」といった使い分けが可能です。

`NSCursor.crosshair` 以外にも、AppKit は `.arrow`、`.iBeam` (テキスト用 I ビーム)、`.pointingHand` (リンクなどの指差し)、`.openHand` / `.closedHand` (ドラッグ操作)、`.resizeLeftRight` / `.resizeUpDown` といった標準カーソルを提供します。独自のカーソル画像が必要な場合は `NSCursor(image:hotSpot:)` で `NSImage` から生成できます。

なお、`resetCursorRects` を「いつ自分で呼ぶか」を意識する必要は基本的にありません。レイアウト変更で再呼び出しが必要なときは `invalidateCursorRects(for:)` を呼び、AppKit に「次のサイクルでリセットしてくれ」と通知します。`DrawingCanvasView` のように単一カーソルしか使わないケースでは、この呼び出しすら不要です。

---

## NSBezierPath の使い方

`NSBezierPath` は AppKit における 2D ベクトル path の表現です。直線・曲線・矩形・楕円・任意のカスタム曲線を構築でき、`stroke()` で輪郭、`fill()` で塗りつぶしができます。Core Graphics の `CGPath` と相互変換可能で、`NSBezierPath.cgPath` プロパティで `CGPath` を取り出せます。

`DrawingCanvasView` のドラッグ処理は `ShapeRenderer` という別クラスに path 生成を委譲していますが、内部では `NSBezierPath` のお決まりのメソッドを使っています。代表的な構築パターンを示します。

```swift
// 1. 直線
let line = NSBezierPath()
line.move(to: startPoint)
line.line(to: endPoint)

// 2. 矩形
let rect = NSBezierPath(rect: CGRect(x: 10, y: 10, width: 100, height: 60))

// 3. 楕円
let ellipse = NSBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 100, height: 60))

// 4. カスタム曲線 (3 次ベジエ)
let curve = NSBezierPath()
curve.move(to: CGPoint(x: 0, y: 0))
curve.curve(
    to: CGPoint(x: 100, y: 0),
    controlPoint1: CGPoint(x: 30, y: 80),
    controlPoint2: CGPoint(x: 70, y: -80)
)

// 5. ストロークの見た目を調整
curve.lineWidth = 4
curve.lineCapStyle = .round   // 線端を丸める
curve.lineJoinStyle = .round  // 角を丸める

// 6. 描画 (現在のグラフィックスコンテキストに対して)
NSColor.systemRed.setStroke()
curve.stroke()
```

`DrawingCanvasView` の `draw(_:)` では `preview.lineWidth = drawingState.penWidth` のように、描画する直前にプロパティを設定してから `stroke()` を呼ぶパターンが頻出します。`NSBezierPath` のストロークプロパティは「path に紐付いた状態」として保存されるため、同じ path を異なる太さで描き直したい場合はそのプロパティを書き換えれば済みます。

`NSBezierPath` で表現できない複雑なケース (たとえば滑らかな手書きストロークの平滑化) では、Catmull-Rom スプラインなどのアルゴリズムで補間点を計算し、`curve(to:controlPoint1:controlPoint2:)` で 3 次ベジエ曲線を順次積み上げていきます。ZoomacIt の `FreehandRenderer.smoothedPath(from:)` がまさにこの処理を担っています。

---

## ZoomacIt 実コード読解

ここまで個別に説明してきた要素が `DrawingCanvasView` の中でどう繋がっているのか、改めて全体の流れを追ってみます。

### ライフサイクル

```
1. オーバーレイウィンドウのコントローラが
     DrawingCanvasView(frame:backgroundImage:) を生成
   ↓
2. ウィンドウに addSubview し、
     window.makeFirstResponder(canvasView) でキー入力を有効化
   ↓
3. AppKit が draw(_:) を呼び、初期状態 (背景のみ) を描画
   ↓
4. ユーザがマウスをクリック
     → mouseDown でドラッグ状態に入る
   ↓
5. ドラッグ中、mouseDragged が連続呼び出し
     → 修飾キーで shapeType を判定
     → previewLayer / activeFreehand を更新
     → setNeedsDisplay でフレーム要求
   ↓
6. AppKit が draw(_:) を呼び、3 層を合成して表示
   ↓
7. マウスを離すと mouseUp が発火
     → strokeManager.pushUndoSnapshot で Undo スナップショット
     → compositeStrokeOntoFinished で finishedLayer を更新
     → previewLayer / activeFreehand を nil
     → setNeedsDisplay
   ↓
8. AppKit が draw(_:) を呼び、確定済み描画を反映
   ↓
9. ユーザが Escape または右クリック
     → onDismiss を呼び、上位コントローラがウィンドウを破棄
```

この流れの中で、`DrawingCanvasView` 自身は「キャンバス」としての責務だけに集中していることが分かります。色の管理は `DrawingState`、Undo は `StrokeManager`、シェイプ生成は `ShapeRenderer`、テキスト入力は `TextInputController`、フリーハンド平滑化は `FreehandRenderer`、ハイライターのスタイリングは `HighlighterRenderer` といった具合に、責任が細かく分割されています。766 行という長さは、それでもなお `DrawingCanvasView` がこれら全ての中心ハブだからです。

### イベントとレイヤーの対応関係

3 層と各イベントの対応関係を表にまとめます。

| イベント | 操作する層 | setNeedsDisplay |
|---|---|---|
| `mouseDown` | `activeFreehand` 初期化、`previewLayer = nil` | 暗黙 (次のドラッグで起こる) |
| `mouseDragged` (フリーハンド) | `activeFreehand` を再生成 | あり |
| `mouseDragged` (シェイプ) | `previewLayer` を再生成、`activeFreehand = nil` | あり |
| `flagsChanged` (ドラッグ中) | `mouseDragged` を再呼び出しして層を更新 | あり (mouseDragged 内で) |
| `mouseUp` | `finishedLayer` に焼付、`previewLayer = nil`、`activeFreehand = nil` | あり |
| `keyDown` (E/W/K/⌘Z) | `finishedLayer` を更新または nil | あり |
| `keyDown` (R/G/B/...) | `drawingState` を更新 (層には触らない) | 不要 (次のフレームで色が変わる) |

`keyDown` の色キーが `setNeedsDisplay` を呼んでいない点に注目してください。色は `drawingState` 経由で `draw(_:)` の各層描画時に参照されるため、現在描画中のストローク (= `previewLayer` または `activeFreehand`) があれば次のフレームで自動的に新色に変わります。確定済みの `finishedLayer` は色変更の影響を受けません (= 過去のストロークの色は変わらない)。これは設計として理にかなった挙動です。

---

## ハンズオン (任意)

実際に手を動かして理解を深めたい方は、以下のミニ課題に挑戦してみてください。

**課題 1**: 単一の `NSWindow` を生成し、その中に `MyCanvasView: NSView` を配置して、マウスをドラッグした軌跡をフリーハンドで描く最小限のアプリを書く。`finishedLayer` はなく、`activeFreehand` だけで実装する。

**課題 2**: 課題 1 のアプリに「`mouseUp` で `activeFreehand` を `CGImage` に焼き付け、`finishedLayer` に保存して以降のドラッグでは下に表示する」処理を追加する。`CGContext.createBitmapContext(size:)` の自前実装も要件に含める。

**課題 3**: 課題 2 のアプリに「Shift キーを押しながらドラッグすると直線を描く」プレビュー機能を追加する。`flagsChanged(with:)` でリアルタイムに切り替えられるか確認する。

これらを順に実装すると、`DrawingCanvasView` がたどった設計上の判断を追体験できます。最初の課題はおそらく 50 行で書けますが、課題 3 まで行くと 200 行近くになり、3 層合成の必然性が腑に落ちるはずです。

---

## まとめ

| 観点 | キーポイント |
|---|---|
| 描画の起点 | `NSView` を継承し `draw(_:)` を override |
| コンテキスト | `NSGraphicsContext.current?.cgContext` で `CGContext` を取得 |
| イベント | `mouseDown/Dragged/Up`、`keyDown/Up`、`flagsChanged`、`scrollWheel` |
| First Responder | `acceptsFirstResponder = true` でキーボード入力を受け取る |
| 3 層合成 | 確定済み (CGImage) ・プレビュー (NSBezierPath) ・フリーハンド (NSBezierPath) |
| ラスタライズ | `mouseUp` で `CGBitmapContext` に焼き付け、`makeImage()` で `CGImage` 化 |
| カーソル | `resetCursorRects` で `addCursorRect(_:cursor:)` を呼ぶ |
| `NSBezierPath` | `move(to:)` `line(to:)` `curve(to:controlPoint1:controlPoint2:)` などで構築 |

`DrawingCanvasView` は 766 行と巨大ですが、その骨格は「`NSView` の override ポイント (描画 / イベント / カーソル) を素直に使い、状態を 3 層に分けて整理する」という単純な原則の積み上げです。AppKit の伝統的な API を理解していれば、これだけ複雑な機能でも見通しよく実装できることが、この章で伝えたかった一番のメッセージです。

次章では、ZoomacIt のホットキー実装で使われている Carbon API と、Swift から C 言語の API を呼び出すための橋渡し技法を解説します。

## 次に読む章

→ [34. Carbon API と C 橋渡し](./34-carbon-bridging.md)
