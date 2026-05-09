# Ch39. ハンズオン 2: 新しいシェイプ(三角形)を追加

難易度: 中 (Part IV ハンズオン 2 つ目)

所要時間の目安: 60〜90 分

---

## 課題概要

ZoomacIt の Draw モードは現在、フリーハンド・直線・長方形・楕円・矢印の **5 種類** のシェイプを描画できます。本章ではこれに **三角形 (triangle)** を 6 つ目のシェイプとして追加します。

実装のポイントは次の 3 点です。

1. `enum ShapeType` に `case triangle` を追加する
2. `ShapeRenderer` に三角形の `NSBezierPath` を生成する関数 `drawTriangle(...)` を追加する
3. `DrawingCanvasView` の 2 箇所の `switch shapeType` (mouseDragged / compositeStrokeOntoFinished) と、`DrawingState.currentShapeType(modifiers:)` の修飾キー判定ロジックを更新する

最後に `ShapeRendererTests` にユニットテストを追加し、`make build && make test` で全体を確認、`make run` で実動作を確認します。

修飾キー割り当ては、既存の `Shift / ⌃ / Tab / Shift + ⌃` と衝突しない組み合わせとして **Tab + Shift** (Tab を押しっぱなしにしながら Shift を押す) を採用します。`design/Draw.md` の修飾キー仕様を一読してから始めることを推奨します。

---

## 前提

| 章 | 内容 | なぜ必要か |
|---|---|---|
| Ch11 | Enumerations | `ShapeType` への `case` 追加と `switch` 網羅性が中心テーマ |
| Ch16 | Inheritance / Polymorphism | `NSView` のサブクラスとして `DrawingCanvasView` を理解 |
| Ch33 | NSView 描画 | `NSBezierPath` の `move(to:)` / `line(to:)` / `close()` API |
| Ch37 | XCTest | `XCTAssertEqual` / `XCTAssertGreaterThan` の使い方 |
| Ch38 | ハンズオン 1: 新しいペン色 | 同じ「列挙型を拡張して全 switch を辿る」パターンの先行例 |

また、`design/Draw.md` の **A 章 (Draw モードの操作体系)** と **H 章 (イベントハンドリングの実装方針)** に目を通しておくと、修飾キーの設計思想が把握しやすくなります。

---

## 学習狙い

本章の到達目標は次の 4 つです。

1. **enum + switch の網羅性チェック (exhaustiveness checking) がリファクタリングの安全網になることを体験する。** Swift コンパイラは `switch` 文に未処理の `case` があるとエラーを出します。`ShapeType` に新しい `case` を 1 つ追加した瞬間、関連する `switch` がすべてビルドエラーになり、修正すべき箇所をコンパイラが教えてくれます。これは大規模リファクタリングを安全に行うための強力な仕組みです。
2. **新しい描画関数 (`ShapeRenderer.drawTriangle`) を追加する手順を学ぶ。** 既存の `linePath` / `rectanglePath` / `ellipsePath` / `arrowPath` を参考に、責務を分離した小さな関数として実装します。
3. **`NSBezierPath` の基本 API を実コードで使う。** `move(to:)` で始点に移動し、`line(to:)` で線分を追加し、`close()` で多角形を閉じる、という流れを覚えます。
4. **修飾キーの状態 → シェイプ種別 のマッピング (`currentShapeType(modifiers:)`) を変更する経験を積む。** 既存ロジックの優先順位を理解し、新しい組み合わせを衝突なく追加します。

---

## ステップ

ここからは実コードを変更していきます。各ステップの後に必ず `make build` を実行し、コンパイルエラーが想定通りに出る (あるいは消える) ことを確認してください。

### Step 1. `ShapeType` に `case triangle` を追加する

`src/ZoomacIt/Models/Stroke.swift` の 4〜10 行目にある `enum ShapeType` を編集します。

```swift
enum ShapeType: Sendable {
    case freehand
    case line
    case rectangle
    case ellipse
    case arrow
    case triangle    // 追加
}
```

この時点で `make build` を実行すると、ビルドが **失敗** します。ここで失敗するのが今回の学習狙いの本質です。コンパイラは「`switch shapeType` が網羅的ではない」というエラーを、`DrawingCanvasView.swift` の 2 箇所で出してくれます。

```
DrawingCanvasView.swift:159:9: error: switch must be exhaustive
DrawingCanvasView.swift:377:9: error: switch must be exhaustive
```

(行番号は環境により多少前後します)

このエラーメッセージを見て、安心してください。コンパイラがリファクタリングの抜け漏れを正確に指摘してくれているのです。

### Step 2. `DrawingCanvasView` の 2 箇所の `switch` を修正する

#### 2-1. `mouseDragged(with:)` 内の switch (159〜180 行目付近)

`src/ZoomacIt/Draw/DrawingCanvasView.swift` を開き、`mouseDragged` メソッド内の `switch shapeType` に `case .triangle` を追加します。プレビュー用のパスを生成するだけなので、Step 3 で実装する `ShapeRenderer.drawTriangle` を呼び出します。

```swift
case .triangle:
    previewLayer = ShapeRenderer.drawTriangle(from: dragOrigin, to: currentPoint)
    activeFreehand = nil
```

#### 2-2. `compositeStrokeOntoFinished(shapeType:endPoint:)` 内の switch (377〜389 行目付近)

確定したストロークを `finishedLayer` に焼き込む `compositeStrokeOntoFinished` 内にも、同じ shapeType を分岐する switch があります。こちらは `cgPath` を取り出して `bitmapContext` に描画します。

```swift
case .triangle:
    path = ShapeRenderer.drawTriangle(from: dragOrigin, to: endPoint).cgPath
```

この時点でまだ `ShapeRenderer.drawTriangle` は実装していないので、ビルドは別のエラー (関数が未定義) に変わります。Step 3 へ進みます。

### Step 3. `ShapeRenderer` に `drawTriangle` を実装する

`src/ZoomacIt/Draw/ShapeRenderer.swift` の末尾 (Arrow セクションの後) に、三角形のパスを生成する static 関数を追加します。

`drawTriangle` は、ドラッグの開始点 (`start`) と現在点 (`end`) を対角頂点とするバウンディングボックスに対して、**底辺の中点上方を頂点 (上向き三角形)** とするロジックで設計します。これは長方形・楕円と同じ「ドラッグでバウンディングボックスを決める」思想に揃えるためです。

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

    let topVertex    = CGPoint(x: (minX + maxX) / 2, y: maxY)
    let bottomLeft   = CGPoint(x: minX, y: minY)
    let bottomRight  = CGPoint(x: maxX, y: minY)

    let path = NSBezierPath()
    path.move(to: topVertex)
    path.line(to: bottomLeft)
    path.line(to: bottomRight)
    path.close()
    return path
}
```

ここで重要なのは、関数のシグネチャを既存関数 (`linePath`, `rectanglePath`, `ellipsePath`, `arrowPath`) に合わせて **`color` や `lineWidth` を引数に取らない** ことです。色や太さの適用は呼び出し側 (`DrawingCanvasView`) が担当しているため、`ShapeRenderer` は純粋にジオメトリの生成に集中します。これは「責務の分離 (separation of concerns)」の実例です。

`make build` が通るはずです。通らない場合は、エラーメッセージを読んで Step 1〜3 の該当箇所を確認してください。

### Step 4. 修飾キー割り当て (Tab + Shift = 三角形)

`src/ZoomacIt/Models/DrawingState.swift` の `currentShapeType(modifiers:)` (68〜83 行目付近) を編集します。現在のロジックは次のようになっています。

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

ここに **`Tab + Shift` の組み合わせ** を割り込ませて三角形にします。`isTabHeld` の判定が一番上にあるので、`Tab + Shift` を `isTabHeld && hasShift` として、より具体的な条件を先に評価する必要があります。

```swift
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
```

優先順位の原則は **「より具体的な条件を先に書く」** です。`isTabHeld && hasShift` は `isTabHeld` 単独より具体的なので、上に置きます。`hasShift && hasControl` も同様の理由で `hasShift` 単独より上にあります。

> ヒント: `design/Draw.md` の修飾キー仕様表 (A 章) では Tab + Shift は未使用です。Tab + ⌃ も未使用なので、別の組み合わせを採用したい場合は同じ手順で割り込ませることができます。

### Step 5. `ShapeRendererTests` にテストを追加する

`src/ZoomacItTests/ShapeRendererTests.swift` の末尾に、三角形の幾何学的特性を検証するテストを追加します。

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
    // 1 つ目の要素 (moveTo) で頂点に移動しているはず
    var points = [NSPoint](repeating: .zero, count: 3)
    let elementType = path.element(at: 0, associatedPoints: &points)
    XCTAssertEqual(elementType, .moveTo)
    XCTAssertEqual(points[0].x, 50)   // バウンディングボックス底辺中点の x
    XCTAssertEqual(points[0].y, 100)  // バウンディングボックス上辺の y
}
```

1 つ目のテストは「パスが想定通りの要素数 (move + line + line + close = 4) を持つこと」を確認します。2 つ目のテストは `NSBezierPath.element(at:associatedPoints:)` API を使って、最初の要素が `(50, 100)` の頂点に move していることを検証します。

### Step 6. `make build && make test` で確認する

```bash
make build && make test
```

ビルドとすべてのテストが通れば成功です。失敗した場合は、エラーメッセージを読んで該当箇所を確認してください。よくある失敗パターン:

- `case .triangle` を 1 箇所しか追加していない (もう片方の switch でエラー)
- `drawTriangle` の return 型が `NSBezierPath` 以外になっている
- `currentShapeType` で `isTabHeld && hasShift` を `isTabHeld` の **後** に書いたため到達不能になっている

### Step 7. `make run` で実動作確認

```bash
make run
```

`⌃2` で Draw モードに入り、Tab を押しっぱなしにしながら Shift を押し、マウスでドラッグしてみてください。上向き三角形が描画されればハンズオン完了です。

| 確認項目 | 期待される挙動 |
|---|---|
| Tab 単独 | 楕円が描画される (既存挙動) |
| Tab + Shift | 三角形が描画される (今回追加) |
| Shift 単独 | 直線が描画される (既存挙動) |
| ⌃ 単独 | 長方形が描画される (既存挙動) |
| Shift + ⌃ | 矢印が描画される (既存挙動) |

修飾キーを離すと即座にフリーハンドに戻ることも確認してください。ZoomIt の操作体系は「モード切替」ではなく「修飾キー押しっぱなし」が原則です。

---

## 動作確認チェックリスト

- [ ] `make build` が成功する
- [ ] `make test` が全件パスする (新規追加した `testTrianglePath` / `testTriangleTopVertexIsAtBoundingBoxTop` を含む)
- [ ] `make run` で起動したアプリで、`⌃2` → Draw モード → Tab + Shift + ドラッグ で三角形が描画される
- [ ] 既存のシェイプ (フリーハンド・直線・長方形・楕円・矢印) が壊れていない
- [ ] 三角形を描画した後、`⌘Z` で取り消せる (既存の Undo 機構は変更不要)
- [ ] 三角形を描画した後、`E` で全消去できる

---

## 解答例

完成版のコード差分は `learning-swift/answers/39-add-shape/` にあります。自分で一通り実装し終えてから参照することを強く推奨します。コンパイラが指摘してくれる箇所を一つひとつ手で潰す経験こそが、本章の最大の学びです。

---

## さらにチャレンジ

時間と興味があれば、次の発展課題に取り組んでみてください。

1. **下向き三角形 / 左向き三角形を追加する。** `ShapeType` に `case triangleDown` `case triangleLeft` などを追加し、それぞれの `drawTriangle*` 関数を実装します。修飾キーの組み合わせは設定ファイルから読めるようにすると、より実践的です。
2. **正三角形モードを追加する。** ドラッグの長さに応じて常に正三角形 (3 辺が等しい) を描く実装にしてみましょう。三角関数の練習になります。
3. **五角形・六角形・星形を一般化する。** `drawRegularPolygon(sides: Int, ...)` のような汎用関数を作ると、`drawTriangle` も `drawPentagon` も `drawHexagon` もすべて 1 関数に統合できます。リファクタリングの良い練習になります。
4. **塗りつぶし対応。** 現在は線描画のみですが、`NSBezierPath.fill()` を使って塗りつぶし版の `case triangleFilled` を追加してみましょう。色や透明度の扱いに踏み込めます。

---

## 次に読む章

[40. ハンズオン 3: 新しいホットキーアクション](./40-add-hotkey.md)

ハンズオン 3 では `HotkeyManager` (Carbon API) を扱い、新しいグローバルホットキーを定義してアプリの動作を呼び出します。本章で扱った「列挙型 + switch」とは異なる、**OS レベルのイベントハンドリング** に踏み込みます。
