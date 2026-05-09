# Ch39 解答例: 新しいシェイプ(三角形)を追加

本章のハンズオンの完成形コード差分と解説をまとめます。実装に行き詰まった場合や、自分の実装と見比べる目的で参照してください。

修正対象ファイルは合計 4 つです。

| ファイル | 変更内容 |
|---|---|
| `src/ZoomacIt/Models/Stroke.swift` | `enum ShapeType` に `case triangle` を追加 |
| `src/ZoomacIt/Draw/ShapeRenderer.swift` | `static func drawTriangle(from:to:)` を新設 |
| `src/ZoomacIt/Draw/DrawingCanvasView.swift` | 2 箇所の `switch shapeType` に `case .triangle` を追加 |
| `src/ZoomacIt/Models/DrawingState.swift` | `currentShapeType(modifiers:)` に `Tab + Shift → triangle` を追加 |
| `src/ZoomacItTests/ShapeRendererTests.swift` | `testTrianglePath` / `testTriangleTopVertexIsAtBoundingBoxTop` を追加 |

---

## Step 1: `ShapeType` への case 追加

### 修正後 (`src/ZoomacIt/Models/Stroke.swift`)

```swift
enum ShapeType: Sendable {
    case freehand
    case line
    case rectangle
    case ellipse
    case arrow
    case triangle
}
```

### diff

```diff
 enum ShapeType: Sendable {
     case freehand
     case line
     case rectangle
     case ellipse
     case arrow
+    case triangle
 }
```

### この変更で何が起きるか

この一行を追加して `make build` を実行すると、コンパイラは **`switch shapeType`** を含むすべての箇所で `error: switch must be exhaustive` を出します。ZoomacIt のコードベースには該当箇所が 2 つあります。

- `src/ZoomacIt/Draw/DrawingCanvasView.swift` の `mouseDragged(with:)` 内
- `src/ZoomacIt/Draw/DrawingCanvasView.swift` の `compositeStrokeOntoFinished(shapeType:endPoint:)` 内

これが Swift の **網羅性チェック (exhaustiveness checking)** です。enum に case を 1 つ追加するだけで、コンパイラが「この箇所を直さないとビルドが通らない」と教えてくれるのです。これは大規模なコードベースをリファクタリングする際の **静的な安全網** として機能します。

逆に言えば、列挙型を分岐する処理を `if let` チェーンや `default:` 付きの `switch` で書いてしまうと、この恩恵を受けられません。`switch` 文を `default:` なしで書くスタイルは「列挙型の case が増えたら必ずここを更新せよ」という設計上の意思表示でもあります。

---

## Step 2-3: `ShapeRenderer.drawTriangle` の実装

### 追加コード (`src/ZoomacIt/Draw/ShapeRenderer.swift`)

`arrowPath` 関数の **後ろ** に以下を追加します。

```swift
// MARK: - Triangle

/// Creates an upward-pointing triangle path inscribed in the bounding box
/// defined by `start` and `end`.
///
/// - The top vertex is the midpoint of the top edge.
/// - The bottom-left and bottom-right vertices are the lower corners
///   of the bounding box.
static func drawTriangle(from start: CGPoint, to end: CGPoint) -> NSBezierPath {
    let minX = min(start.x, end.x)
    let maxX = max(start.x, end.x)
    let minY = min(start.y, end.y)
    let maxY = max(start.y, end.y)

    let topVertex   = CGPoint(x: (minX + maxX) / 2, y: maxY)
    let bottomLeft  = CGPoint(x: minX, y: minY)
    let bottomRight = CGPoint(x: maxX, y: minY)

    let path = NSBezierPath()
    path.move(to: topVertex)
    path.line(to: bottomLeft)
    path.line(to: bottomRight)
    path.close()
    return path
}
```

### 設計上のポイント

#### a. 引数を `start` と `end` だけにする (色・太さは取らない)

ハンズオン本文の指示でも触れましたが、既存の `linePath` / `rectanglePath` / `ellipsePath` / `arrowPath` のシグネチャと揃えています。これらの関数はいずれも **ジオメトリ生成だけを担当** しており、色や線の太さは呼び出し側 (`DrawingCanvasView.draw(_:)` や `compositeStrokeOntoFinished`) が `setStroke()` / `setLineWidth(_:)` で適用します。

責務を分離しておくと、たとえば「同じ三角形を 2 色のグラデーションでストロークしたい」「マスク用に黒で塗りつぶしたい」といった派生要求が来たときも、`drawTriangle` 自体に手を入れる必要がなくなります。

#### b. `min` / `max` でドラッグ方向を吸収する

ユーザーは右下にドラッグすることもあれば左上にドラッグすることもあります。`start.x > end.x` のケースでも正しく動作するよう、`min` / `max` でバウンディングボックスを再計算しています。これは `rectanglePath` と `ellipsePath` でも採用されている既存パターンです。

#### c. `NSBezierPath` の API: `move` / `line` / `close`

```
move(to: P0)   ← P0 にペンを置く (描画はしない)
line(to: P1)   ← P0 から P1 まで線を引く
line(to: P2)   ← P1 から P2 まで線を引く
close()        ← P2 から P0 まで線を引いて閉じる
```

`close()` を呼ぶと、現在の点から **直近の `move(to:)` した点** まで自動で線分が引かれます。これにより 3 辺すべてを `line(to:)` で書く必要がなく、コードが簡潔になります。また `close()` した方が描画時の角の処理が綺麗になる (lineJoinStyle が確実に適用される) という利点もあります。

#### d. 上向き三角形にした理由

下向き・左向き・右向きの三角形も実装可能ですが、PowerPoint や Keynote などのプレゼンツールにおける「三角形」は通例として **上向き** がデフォルトです。ZoomacIt は学習目的のクローンなので、最も期待値の高い形状をデフォルトとしています。下向き三角形が必要なら本文の「さらにチャレンジ 1」の通り、別 case として追加してください。

---

## Step 2 (続き): `DrawingCanvasView` の switch を 2 箇所修正

### 2-1. `mouseDragged(with:)` 内の switch

#### 修正前 (`src/ZoomacIt/Draw/DrawingCanvasView.swift` 159〜180 行目)

```swift
switch shapeType {
case .freehand:
    freehandPoints.append(currentPoint)
    activeFreehand = FreehandRenderer.smoothedPath(from: freehandPoints)
    previewLayer = nil

case .line:
    previewLayer = ShapeRenderer.linePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .rectangle:
    previewLayer = ShapeRenderer.rectanglePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .ellipse:
    previewLayer = ShapeRenderer.ellipsePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .arrow:
    previewLayer = ShapeRenderer.arrowPath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil
}
```

#### 修正後

```swift
switch shapeType {
case .freehand:
    freehandPoints.append(currentPoint)
    activeFreehand = FreehandRenderer.smoothedPath(from: freehandPoints)
    previewLayer = nil

case .line:
    previewLayer = ShapeRenderer.linePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .rectangle:
    previewLayer = ShapeRenderer.rectanglePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .ellipse:
    previewLayer = ShapeRenderer.ellipsePath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .arrow:
    previewLayer = ShapeRenderer.arrowPath(from: dragOrigin, to: currentPoint)
    activeFreehand = nil

case .triangle:
    previewLayer = ShapeRenderer.drawTriangle(from: dragOrigin, to: currentPoint)
    activeFreehand = nil
}
```

### 2-2. `compositeStrokeOntoFinished(shapeType:endPoint:)` 内の switch

#### 修正前 (377〜389 行目)

```swift
let path: CGPath
switch shapeType {
case .freehand:
    let bezier = FreehandRenderer.smoothedPath(from: freehandPoints)
    path = bezier.cgPath
case .line:
    path = ShapeRenderer.linePath(from: dragOrigin, to: endPoint).cgPath
case .rectangle:
    path = ShapeRenderer.rectanglePath(from: dragOrigin, to: endPoint).cgPath
case .ellipse:
    path = ShapeRenderer.ellipsePath(from: dragOrigin, to: endPoint).cgPath
case .arrow:
    path = ShapeRenderer.arrowPath(from: dragOrigin, to: endPoint).cgPath
}
```

#### 修正後

```swift
let path: CGPath
switch shapeType {
case .freehand:
    let bezier = FreehandRenderer.smoothedPath(from: freehandPoints)
    path = bezier.cgPath
case .line:
    path = ShapeRenderer.linePath(from: dragOrigin, to: endPoint).cgPath
case .rectangle:
    path = ShapeRenderer.rectanglePath(from: dragOrigin, to: endPoint).cgPath
case .ellipse:
    path = ShapeRenderer.ellipsePath(from: dragOrigin, to: endPoint).cgPath
case .arrow:
    path = ShapeRenderer.arrowPath(from: dragOrigin, to: endPoint).cgPath
case .triangle:
    path = ShapeRenderer.drawTriangle(from: dragOrigin, to: endPoint).cgPath
}
```

### なぜ 2 箇所あるのか

ZoomacIt の Draw モードは「3 レイヤー合成」アーキテクチャ (`design/Draw.md` 参照) を採用しています。

- **mouseDragged 中**: `previewLayer` (NSBezierPath) として **動的に再生成** し、`draw(_:)` で毎フレーム描画する
- **mouseUp 後**: `finishedLayer` (CGImage) に **ラスタライズして焼き込む** (1 回限り)

この 2 つは描画先が違うだけで「ドラッグ開始点と終点からシェイプを生成する」というロジックは共通です。そのため switch も 2 箇所に存在します。`ShapeRenderer.drawTriangle` を 1 つ用意しておけば、両方から呼べる設計になっています。

---

## Step 4: 修飾キー割り当て

### 修正前 (`src/ZoomacIt/Models/DrawingState.swift` 68〜83 行目)

```swift
func currentShapeType(modifiers: NSEvent.ModifierFlags) -> ShapeType {
    let hasShift = modifiers.contains(.shift)
    let hasControl = modifiers.contains(.control)

    if isTabHeld {
        return .ellipse
    } else if hasShift && hasControl {
        return .arrow
    } else if hasShift {
        return .line
    } else if hasControl {
        return .rectangle
    } else {
        return .freehand
    }
}
```

### 修正後

```swift
func currentShapeType(modifiers: NSEvent.ModifierFlags) -> ShapeType {
    let hasShift = modifiers.contains(.shift)
    let hasControl = modifiers.contains(.control)

    if isTabHeld && hasShift {
        return .triangle
    } else if isTabHeld {
        return .ellipse
    } else if hasShift && hasControl {
        return .arrow
    } else if hasShift {
        return .line
    } else if hasControl {
        return .rectangle
    } else {
        return .freehand
    }
}
```

### 優先順位の原則

`if-else if` チェーンでは **より具体的な条件を先に評価する** のが鉄則です。`isTabHeld && hasShift` は `isTabHeld` 単独より具体的なので、上に置く必要があります。もし順序を逆にすると、Tab を押しながら Shift を押しても先に `isTabHeld` 単独条件が成立してしまい、永遠に `.triangle` には到達しません (デッドコードになる)。

これは `switch` の網羅性チェックと違い、**コンパイラは検出してくれません**。論理エラーは静的解析の対象外なので、ロジックを書いた人間が責任を持って優先順位を確認する必要があります。テスト (Step 5) を書く動機の一つでもあります。

### `Tab + Shift` を選んだ理由

`design/Draw.md` の修飾キー仕様表 (A 章) を確認すると、現在使われている組み合わせは次の 5 つです。

| 修飾キー | シェイプ |
|---|---|
| なし | フリーハンド |
| Shift | 直線 |
| ⌃ | 長方形 |
| Tab | 楕円 |
| Shift + ⌃ | 矢印 |

未使用の組み合わせは `Tab + Shift` `Tab + ⌃` `Tab + Shift + ⌃` の 3 つです。このうち最も指が届きやすく、かつ「Tab (楕円系) のバリエーション」として直感的なのが `Tab + Shift` だと判断しました。

別の選択を採用しても問題ありません。たとえば `Tab + ⌃` を triangle にする場合は、`if isTabHeld && hasControl` の条件を `isTabHeld` 単独条件より上に書きます。

---

## Step 5: テストの追加

### 追加コード (`src/ZoomacItTests/ShapeRendererTests.swift`)

`testArrowPath` の **後ろ** に以下を追加します。

```swift
func testTrianglePath() {
    let path = ShapeRenderer.drawTriangle(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 100, y: 100)
    )
    // Triangle = moveTo + lineTo + lineTo + closePath = 4 elements
    XCTAssertEqual(path.elementCount, 4)
}

func testTriangleTopVertexIsAtBoundingBoxTop() {
    let path = ShapeRenderer.drawTriangle(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 100, y: 100)
    )
    var points = [NSPoint](repeating: .zero, count: 3)
    let elementType = path.element(at: 0, associatedPoints: &points)
    XCTAssertEqual(elementType, .moveTo)
    XCTAssertEqual(points[0].x, 50)   // 底辺中点の x
    XCTAssertEqual(points[0].y, 100)  // 上辺の y
}
```

### テスト設計の意図

- **`testTrianglePath`**: パスの **構造 (要素数)** を検証します。move + line + line + close = 4 要素。これは `NSBezierPath.close()` を呼ばずに `line(to:)` だけで 3 辺を引いてしまった場合 (要素数 5) と区別するための簡易な構造テストです。
- **`testTriangleTopVertexIsAtBoundingBoxTop`**: パスの **意味 (頂点座標)** を検証します。バウンディングボックスが (0, 0)〜(100, 100) のとき、上向き三角形の頂点は (50, 100) でなければなりません。このテストにより、もし誰かが将来「下向き三角形に変えたい」と思って実装を書き換えた場合、テストが赤くなって意図的な変更であることを明示的に承認 (テストも更新) する必要が生まれます。

`elementCount` だけでは「上向き」「下向き」「左向き」を区別できません。**ジオメトリの本質を捉えるテスト** を 1 本追加することで、リグレッション検出能力が大きく向上します。

### `NSBezierPath.element(at:associatedPoints:)` API

`NSBezierPath` のパス要素を 1 つずつ取り出す API です。`associatedPoints` は最大 3 点を受け取る `NSPoint` の配列で、要素タイプによって使われる点数が変わります。

- `.moveTo` / `.lineTo` → 1 点 (`points[0]`)
- `.curveTo` → 3 点 (制御点 2 + 終点 1)
- `.closePath` → 0 点

今回は `moveTo` を検証するので `points[0]` だけ参照すれば十分です。

---

## 動作確認

### `make build && make test`

```
Build Succeeded
Test Suite 'All tests' passed at ...
     Executed 82 tests, with 0 failures (0 unexpected) in ... seconds
```

(テスト件数は元の 80 件 + 今回追加の 2 件 = 82 件になります)

### `make run`

`⌃2` で Draw モードに入り、Tab を押しっぱなしにしてから Shift も押し、マウスでドラッグしてみてください。上向き三角形が描画されます。

| 修飾キー | 期待されるシェイプ |
|---|---|
| なし | フリーハンド |
| Shift | 直線 |
| ⌃ | 長方形 |
| Shift + ⌃ | 矢印 |
| Tab | 楕円 |
| **Tab + Shift** | **三角形 (今回追加)** |

---

## 解説: なぜこの設計が良いのか

### 1. 網羅性チェックがリファクタリングの安全網になる

本章で最も重要な学びは、**「`enum` + `switch` (default なし)」のパターンが大規模変更を安全にする** という点です。`ShapeType` に case を 1 つ追加した瞬間、コンパイラは関連するすべての switch でエラーを出してくれました。これにより:

- 「どこを修正すべきか」を人間が grep して回る必要がない
- 修正漏れがあれば必ずビルドエラーになる (本番に漏れない)
- レビュアーも「このコミットの switch が網羅的か」を疑う必要がない

これは Swift / Rust / Scala / Kotlin (sealed class) などの近代的な型システムを持つ言語に共通する強みです。Dynamic 型言語 (Python, Ruby, JavaScript) や、`default:` 付きの switch を多用するスタイル (古典的な C / Java) では得られない安心感です。

### 2. `ShapeRenderer` の責務分離

`drawTriangle` は色も太さも知りません。これは一見すると「使いにくい」ように見えるかもしれませんが、以下の利点があります。

- **テストしやすい**: 純粋関数 (引数のみで結果が決まる) なので、`XCTAssertEqual` で頂点座標を直接検証できます。色や太さがあると比較が面倒になります。
- **再利用しやすい**: プレビュー描画 (画面上の `NSBezierPath`) と最終焼き込み (`CGBitmapContext` への描画) で同じ関数を使い回せます。色や太さは呼び出し側のコンテキストに合わせて適用できます。
- **拡張しやすい**: 「グラデーション」「点線」「破線」などの新要求が来ても、`ShapeRenderer` 自体に手を入れる必要がありません。

### 3. `NSBezierPath` と `CGPath` の橋渡し

最終的な焼き込み (`compositeStrokeOntoFinished` 内) では `path.cgPath` を呼び出して `NSBezierPath` から `CGPath` に変換しています。これは `CGContext.addPath` が `CGPath` を要求するためです。

`NSBezierPath` は AppKit 専用 (macOS のみ) ですが、`CGPath` は Core Graphics の型で、iOS / macOS 両方で動きます。AppKit の便利な API (move, line, close) を使いつつ、最終的な描画は Core Graphics に委譲するハイブリッドな設計になっています。

---

## まとめ

本章で学んだ核心は次の 3 点です。

1. **`enum` に case を 1 つ追加すると、関連する `switch` がすべてビルドエラーになる**。これがコンパイラ駆動リファクタリングの基本パターン。
2. **`NSBezierPath` の `move` / `line` / `close` を使うと多角形が簡潔に書ける**。`close()` は最後の `move` 地点まで自動で線を引いてくれる。
3. **`if-else if` チェーンでは具体的な条件を先に書く**。`Tab + Shift` を `Tab` 単独より上に書かないと到達不能になる。コンパイラは検出してくれないのでテストで担保する。

次のハンズオン (Ch40) では、`HotkeyManager` (Carbon API) を扱ってグローバルホットキーを追加します。本章とは異なる、**OS レベルのイベントハンドリング** に踏み込みます。
