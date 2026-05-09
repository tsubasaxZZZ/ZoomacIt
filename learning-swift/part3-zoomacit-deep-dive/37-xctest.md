# 37. XCTest による単体テスト

## この章で学ぶこと

ZoomacIt は、外部ライブラリを一切持ち込まない純粋な Swift 6 + AppKit プロジェクトでありながら、`src/ZoomacItTests/` 配下に 12 ファイル・約 135 個のテストメソッドを保持しています。これらはすべて Apple 標準の **XCTest** フレームワークで書かれており、Java の世界における JUnit 5 とほぼ同じ立ち位置を占めます。

この章では次のことを学びます。

- XCTest フレームワークの全体像と Swift 標準テスト基盤としての位置付け
- テストクラス・テストメソッドの基本構造と命名規則
- `@testable import` による internal メンバー公開の仕組み (Ch30 access control の応用)
- アサーション API 一覧と、JUnit `assertEquals` との対応
- `setUp` / `tearDown` による準備・後始末ライフサイクル
- `async`/`await` を使った非同期テストの書き方
- 旧 `XCTestExpectation` API と新 `async`/`await` API の使い分け
- `make test` および Xcode `⌘U` でのテスト実行
- 「何をテストし、何をテストしないか」— ZoomacIt が採用する Pure function 中心のテスト哲学
- 実コードの読解 (`ZoomMathTests`, `StrokeManagerTests`, `SettingsTests`)

最後に、Swift コミュニティで生まれた新しいテストフレームワーク **Swift Testing** との関係にも軽く触れます。XCTest は登場から十数年を経た成熟基盤であり、本書執筆時点 (Swift 6.0) でも実プロジェクトの大半でこれが使われ続けています。ZoomacIt も例外ではありません。

> 引用元: src/ZoomacItTests/ZoomMathTests.swift:1-202, src/ZoomacItTests/StrokeManagerTests.swift:1-60, src/ZoomacItTests/SettingsTests.swift:1-269

---

## XCTest とは — Apple 公式のテスト基盤

**XCTest** は Apple が iOS / macOS / tvOS / watchOS 向けに提供する公式テストフレームワークです。Xcode に標準同梱されており、追加インストールは不要です。Swift Package Manager のテスト機構もまた、内部的に XCTest を呼び出しています。

XCTest は「ユニットテスト」「UI テスト」「パフォーマンステスト」の 3 つを 1 つの API でカバーする統合フレームワークです。本章の対象であるユニットテストの観点では、Java の **JUnit 5** とほぼ等価な機能を備えています。

| 機能 | JUnit 5 | XCTest |
|---|---|---|
| テストクラス | `class FooTest` | `final class FooTests: XCTestCase` |
| テストメソッド | `@Test void testBar()` | `func testBar()` |
| 各テスト前 | `@BeforeEach setUp()` | `override func setUp()` |
| 各テスト後 | `@AfterEach tearDown()` | `override func tearDown()` |
| 全テスト前 | `@BeforeAll` | `override class func setUp()` |
| 等価判定 | `assertEquals(a, b)` | `XCTAssertEqual(a, b)` |
| 例外検証 | `assertThrows(...)` | `XCTAssertThrowsError(...)` |
| 失敗の明示 | `fail("...")` | `XCTFail("...")` |
| 非同期 | `CompletableFuture.get()` | `async`/`await` または `XCTestExpectation` |
| 実行 | `mvn test` / `gradle test` | `xcodebuild test` / `swift test` / `⌘U` |

決定的に異なるのは、JUnit 5 がアノテーションでテストメソッドを識別するのに対し、XCTest は **メソッド名のプレフィックス** で識別する点です。これは XCTest が古くは Objective-C ランタイムのリフレクションに依存していた歴史的経緯によるものですが、Swift 6 でも仕様として受け継がれています。

---

## 基本構造 — テストファイルのテンプレート

XCTest を使うすべてのファイルは、次の 3 行で始まります。

```swift
import XCTest
@testable import ZoomacIt

final class ZoomMathTests: XCTestCase {
    func testClampWithinRange() {
        XCTAssertEqual(ZoomMath.clamp(5.0, lower: 0, upper: 10), 5.0)
    }
}
```

> 引用元: src/ZoomacItTests/ZoomMathTests.swift:1-10

要素を分解します。

| 要素 | 意味 |
|---|---|
| `import XCTest` | XCTest フレームワークを取り込む |
| `@testable import ZoomacIt` | テスト対象モジュールを「internal メンバーまで含めて」取り込む |
| `final class ... : XCTestCase` | `XCTestCase` を継承したクラスがテストクラスとして認識される |
| `func testXxx()` | `test` プレフィックスを持つ「引数なし・戻り値なし」のメソッドが個別テストとして実行される |

`final` 修飾子を付けるのは Swift コミュニティの慣習で、テストクラスの継承を明示的に禁じる意図があります (Ch30 で扱った access control の応用)。継承がない分、Swift コンパイラは仮想呼び出しを静的呼び出しへ最適化でき、テスト実行も僅かに高速化します。

---

## `@testable import` — internal を見せるための特権

通常の `import ZoomacIt` で参照できるのは `public` および `open` で宣言されたシンボルのみです。Swift では多くの型がデフォルトの `internal` (Ch30 参照) で宣言されているため、これではユニットテストはほとんど何も検証できません。

そこで XCTest では `@testable import` という特殊な構文を使います。

```swift
@testable import ZoomacIt
```

これにより、テスト対象モジュール内の **internal** および **public** メンバーが、テストクラスから直接参照可能になります。`private` および `fileprivate` は依然として隠蔽されたままです。これは Swift の「カプセル化を壊さずにテスト可能性を確保する」設計判断の表れです。

| 修飾子 | 通常 import | `@testable` import |
|---|---|---|
| `public` / `open` | 参照可 | 参照可 |
| `internal` (デフォルト) | 参照不可 | 参照可 |
| `fileprivate` | 参照不可 | 参照不可 |
| `private` | 参照不可 | 参照不可 |

ZoomacIt の `ZoomMath` 構造体や `StrokeManager` クラスはいずれもデフォルトの internal で宣言されているため、`@testable import` がなければ `ZoomMathTests` は 1 行も書けません。Java の `package-private` メンバーをテストするために、テストクラスを同一パッケージに置くのと類似のテクニックです。

ただし `@testable` には注意点もあります。

- リリースビルドでは `@testable` 用の追加メタデータが付与されないため、**Debug 構成でビルドされたモジュールに対してのみ** 機能します。本番ビルドのテスト実行には使えません。
- ライブラリ作者にとっては「テスト用 API を意図せず公開してしまう」リスクの隔離装置です。public にせざるを得なかった内部関数を `internal` のままに保てます。

---

## テストメソッドの命名規則

XCTest はテストメソッドを **名前** で識別します。次のすべてを満たすメソッドのみが個別テストとして実行されます。

1. 名前が `test` で始まる (例: `testClampWithinRange`)
2. 引数を取らない
3. 戻り値を持たない (`Void` を返す)
4. インスタンスメソッドである (`static` ではない)

例外として、Swift 5.5 以降は `async` および `throws` を持つテストメソッドが認められています (後述)。

```swift
func testClampWithinRange() { ... }              // 実行される
func testClampBelowLower() throws { ... }        // 実行される
func testFetchData() async throws { ... }        // 実行される
func helperMethod() { ... }                      // 実行されない (test プレフィックスなし)
func test_clampWithinRange() { ... }             // 実行される (アンダースコアは許容)
```

ZoomacIt のテストでは `testClampWithinRange` のような **キャメルケース + 動詞句** が一貫して採用されています。これは Apple のサンプルコードとも揃ったスタイルです。

> 引用元: src/ZoomacItTests/ZoomMathTests.swift:8-23

---

## アサーション — 結果を検証する

XCTest が提供するアサーション関数は十数種類あり、多くは JUnit と一対一に対応します。

| 関数 | 用途 | JUnit 対応 |
|---|---|---|
| `XCTAssertEqual(a, b)` | `a == b` を検証 | `assertEquals` |
| `XCTAssertEqual(a, b, accuracy: 0.001)` | 浮動小数点で誤差許容比較 | `assertEquals(a, b, delta)` |
| `XCTAssertNotEqual(a, b)` | `a != b` を検証 | `assertNotEquals` |
| `XCTAssertNil(x)` | `x == nil` を検証 | `assertNull` |
| `XCTAssertNotNil(x)` | `x != nil` を検証 | `assertNotNull` |
| `XCTAssertTrue(cond)` | 条件が真 | `assertTrue` |
| `XCTAssertFalse(cond)` | 条件が偽 | `assertFalse` |
| `XCTAssertGreaterThan(a, b)` | `a > b` | `assertTrue(a > b)` 相当 |
| `XCTAssertGreaterThanOrEqual(a, b)` | `a >= b` | 〃 |
| `XCTAssertLessThan(a, b)` | `a < b` | 〃 |
| `XCTAssertLessThanOrEqual(a, b)` | `a <= b` | 〃 |
| `XCTAssertIdentical(a, b)` | 同一インスタンス (`===`) | `assertSame` |
| `XCTAssertNotIdentical(a, b)` | 別インスタンス | `assertNotSame` |
| `XCTAssertThrowsError(try expr)` | 例外を投げる | `assertThrows` |
| `XCTAssertNoThrow(try expr)` | 例外を投げない | `assertDoesNotThrow` |
| `XCTFail("メッセージ")` | 無条件で失敗 | `fail` |
| `XCTUnwrap(optional)` | Optional を非 nil で展開 (失敗時はテスト中断) | — |

すべての関数の **最終引数** にメッセージ文字列を渡すと、失敗時のレポートに添えられます。

```swift
XCTAssertNotNil(snapshot, "Stack was not empty, should return a snapshot")
```

> 引用元: src/ZoomacItTests/StrokeManagerTests.swift:19

### 浮動小数点比較の注意

`Double` や `CGFloat` は IEEE 754 表現の都合で厳密な等値比較が信頼できません。ZoomacIt の `ZoomMathTests` では一貫して `accuracy:` 引数を使い、許容誤差を明示しています。

```swift
XCTAssertEqual(rect.origin.x, 0.0, accuracy: 0.001)
XCTAssertEqual(rect.origin.y, 0.0, accuracy: 0.001)
XCTAssertEqual(rect.size.width, 1.0, accuracy: 0.001)
XCTAssertEqual(rect.size.height, 1.0, accuracy: 0.001)
```

> 引用元: src/ZoomacItTests/ZoomMathTests.swift:56-59

整数同士の比較や `String`、`enum` の比較なら `accuracy:` は不要です。

### `XCTUnwrap` — オプショナルの安全な展開

Optional を含む式をテストする際、Swift では強制アンラップ (`!`) はクラッシュ要因となります。`XCTUnwrap` は nil の場合にテストを **失敗扱いで中断** し、後続のアサーションを実行しません。

```swift
let snapshot = try XCTUnwrap(manager.popUndoSnapshot())
XCTAssertEqual(snapshot.undoLevels, 0)  // snapshot が確実に non-nil の状態で続行
```

`XCTUnwrap` を含むテストメソッドは `throws` を宣言する必要があります。これは Swift の throwing 関数の慣習に従ったものです。

---

## `setUp` / `tearDown` — テストの前後処理

XCTest は各テストメソッドの実行前後で、専用のフックメソッドを呼び出します。これは JUnit 5 の `@BeforeEach` / `@AfterEach` に対応します。

```swift
final class SettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 各テストの直前に呼ばれる
    }

    override func tearDown() {
        // 各テストの直後に呼ばれる
        Settings.shared.resetToDefaults()
        super.tearDown()
    }
}
```

> 引用元: src/ZoomacItTests/SettingsTests.swift:10-18

`override` キーワードと `super` 呼び出しが必要な点に注意してください。`XCTestCase` の親クラス実装を呼ばないと、フレームワーク内部のセットアップが完了しないことがあります。

ZoomacIt の `SettingsTests` は、シングルトン `Settings.shared` が `UserDefaults.standard` を介してプロセス全体で値を共有するという特性に対処するため、`tearDown` で必ず `resetToDefaults()` を呼んでいます。これにより、テスト順序に依存した潜在的な失敗を避けています。

```swift
override func tearDown() {
    // Reset shared Settings to registered defaults
    Settings.shared.resetToDefaults()
    super.tearDown()
}
```

> 引用元: src/ZoomacItTests/SettingsTests.swift:14-18

### ライフサイクル一覧

| メソッド | 呼ばれるタイミング | JUnit 5 対応 |
|---|---|---|
| `class func setUp()` | クラス内の最初のテスト開始前に 1 回 | `@BeforeAll` |
| `func setUp()` (instance) | 各テストの直前 | `@BeforeEach` |
| `func setUpWithError() throws` | 同上 (throwing 版) | 同上 |
| `func tearDown()` | 各テストの直後 | `@AfterEach` |
| `func tearDownWithError() throws` | 同上 (throwing 版) | 同上 |
| `class func tearDown()` | クラス内の最後のテスト終了後に 1 回 | `@AfterAll` |

throwing 版を使うと、初期化処理で例外を投げた瞬間にテストが失敗扱いになります。`try?` で握り潰す手間が省けるため、エラーハンドリングを伴う初期化には throwing 版が推奨されます。

---

## 非同期テスト — `async`/`await` ベース

Swift 5.5 で `async`/`await` が言語に導入されて以降、XCTest もテストメソッドを直接 `async` 宣言できるようになりました。これは Java で言えば `CompletableFuture` を `.get()` でブロックする代わりに、テストランタイムが Future の完了を待ってくれるイメージです。

```swift
func testFetchUserData() async throws {
    let user = try await UserService.shared.fetch(id: 42)
    XCTAssertEqual(user.id, 42)
    XCTAssertEqual(user.name, "Alice")
}
```

このスタイルの利点は明白です。

- コールバックや expectation のセットアップが不要
- 同期テストと同じ流れで読める
- `try await` の連鎖で複数の非同期 API を逐次検証できる

ZoomacIt 自体は CLI 風の menu bar アプリで、非同期 API を多用しないため、現状の `ZoomacItTests/` 配下に `async` テストは含まれていません。とはいえ将来的に `ScreenCaptureKit` の `SCStream` (非同期ストリーム) を直接ユニットテストする場合などは、この記法が出番になります。

---

## `XCTestExpectation` — 旧 API との使い分け

`async`/`await` 以前、XCTest はコールバック型 API のテストに **`XCTestExpectation`** を使う長い歴史を持っていました。

```swift
func testCallbackBasedFetch() {
    let exp = expectation(description: "fetch completes")

    OldStyleAPI.fetch { result in
        XCTAssertEqual(result, "expected")
        exp.fulfill()  // 完了を通知
    }

    wait(for: [exp], timeout: 5.0)  // 最大 5 秒待つ
}
```

このパターンは現代でも有効ですが、新規コードでは `async`/`await` を強く推奨します。`XCTestExpectation` を使うべきなのは次のような場面です。

| シナリオ | 推奨 API |
|---|---|
| `async` で書ける新規 API のテスト | `func testXxx() async throws` |
| Combine の `Publisher` を観測 | `XCTestExpectation` (または `await publisher.values.first { ... }`) |
| Notification の発火を待つ | `XCTestExpectation` (`expectation(forNotification:object:handler:)`) |
| KVO の値変化を待つ | `XCTestExpectation` (`expectation(for:evaluatedWith:handler:)`) |
| C コールバックや Carbon イベント | `XCTestExpectation` (Carbon は async モデルを持たない) |

`XCTestExpectation` には派生 API もあります。

```swift
let exp = expectation(description: "should NOT be called")
exp.isInverted = true   // fulfill されないことを期待
wait(for: [exp], timeout: 0.5)
```

`isInverted = true` は「指定時間内に fulfill されなかったら成功」という反転条件を表します。「コールバックが誤って呼ばれていないこと」を確認したいときに便利です。

---

## テストの実行方法

ZoomacIt はテスト実行を Makefile に集約しています。

```bash
make test
```

中身は次のとおり xcodebuild の薄いラッパーです。

```makefile
test:
	xcodebuild -project $(PROJECT) -scheme $(TEST_SCHEME) \
	    -configuration Debug -derivedDataPath $(BUILD_DIR) test
```

`-scheme ZoomacItTests` で **テスト専用スキーム** を指定し、`test` アクションで実行します。出力はターミナルに直接流れ、最後に `Test Suite 'All tests' passed` のような集計が表示されます。

Xcode から実行する場合は、メニューバーから **Product → Test** を選ぶか、ショートカット `⌘U` を押します。Xcode のテストナビゲーター (左側ペイン) からは個別メソッド単位での実行も可能です。

CI 環境では `xcodebuild test` の出力を `xcpretty` や `xcbeautify` でフォーマットし、JUnit XML 互換形式に変換して GitHub Actions などに渡すのが定石です。

---

## ZoomacIt のテスト哲学 — 何をテストし、何をテストしないか

ZoomacIt は意図的に **「Pure function と Models だけテストする」** という方針を採用しています。これは CLAUDE.md の冒頭でも明記されている設計上の判断です。

> Tests cover Models, Draw renderers, and ZoomMath (80 test methods across 7 files). UI/overlay classes are not unit-tested (require running app context).

### テスト対象 (積極的にカバー)

| レイヤー | 例 | 理由 |
|---|---|---|
| **Models** | `Settings`, `DrawingState`, `Stroke`, `BreakTimerState`, `PenColor`, `FontWeightOption` | プレーンな値型。入出力が明確で、副作用がほぼない |
| **Pure functions** | `ZoomMath.clamp`, `ZoomMath.visibleContentsRect`, `ZoomMath.cropRect` | 同じ入力に対し常に同じ出力。座標変換の正しさは目視確認が困難なため、テストで担保 |
| **Renderers** | `FreehandRenderer`, `ShapeRenderer`, `HighlighterRenderer` | NSBezierPath を生成する純粋関数群。要素数や座標を XCTAssert で検証可能 |
| **State machines** | `StrokeManager` (Undo スタック) | 入力イベントと内部状態の対応が決定的 |
| **Extensions** | `CGContext+Extensions` | 単発のユーティリティ。外部依存なし |

### テスト対象外 (意図的に外す)

| レイヤー | 例 | 理由 |
|---|---|---|
| **Views** | `DrawingCanvasView`, `OverlayWindow` | NSView の `draw(_:)` は実画面コンテキストでしか挙動を検証できない |
| **Controllers** | `OverlayWindowController`, `StatusBarController` | NSWindow / NSStatusItem のライフサイクルは実 NSApplication が必要 |
| **Hotkey** | `HotkeyManager` | Carbon `RegisterEventHotKey` はシステムへの登録を伴い、ユニットテスト環境では検証が無意味 |
| **System integration** | ScreenCaptureKit, AVFoundation 連携 | 物理スクリーンや音声デバイスが要る |

この判断の背後にある原則は明快です。

1. **テストできるものを徹底的にテストする** — 計算ロジックと値型は ROI が高い
2. **テストできない (またはテストの価値が低い) ものは手動 QA に回す** — UI の見た目とインタラクションは人間の眼が不可欠
3. **「テスト容易性」を設計の制約として用いる** — `ZoomMath` を `static func` の集合体として切り出したのも、テストしやすさを優先した結果

Swift コミュニティでは、この **「Pure function を分離してテストする」** スタイルが広く推奨されています。SwiftUI の登場以降、ロジックを `View` 本体から `@MainActor` のプレーンクラスや `struct` 関数集合へ抜き出す傾向が一段と強まっています。

Java で言えば、Spring の `@Service` クラスを徹底的に JUnit でカバーし、Thymeleaf テンプレートや JSP は人間が確認する、という分担に近い発想です。

---

## ZoomacIt 実コード読解

### `ZoomMathTests` — Pure function テストの教科書

`ZoomMath` は座標変換に関わる static 関数群です。引数と戻り値が CGFloat / CGPoint / CGRect で完結しており、副作用がありません。テストはひたすら「この入力ならこの出力」を列挙する形になります。

```swift
import XCTest
@testable import ZoomacIt

final class ZoomMathTests: XCTestCase {

    // MARK: - clamp

    func testClampWithinRange() {
        XCTAssertEqual(ZoomMath.clamp(5.0, lower: 0, upper: 10), 5.0)
    }

    func testClampBelowLower() {
        XCTAssertEqual(ZoomMath.clamp(-1.0, lower: 0, upper: 10), 0.0)
    }

    func testClampAboveUpper() {
        XCTAssertEqual(ZoomMath.clamp(15.0, lower: 0, upper: 10), 10.0)
    }

    func testClampAtBoundaries() {
        XCTAssertEqual(ZoomMath.clamp(0.0, lower: 0, upper: 10), 0.0)
        XCTAssertEqual(ZoomMath.clamp(10.0, lower: 0, upper: 10), 10.0)
    }
```

> 引用元: src/ZoomacItTests/ZoomMathTests.swift:1-23

注目ポイントは次の 4 つです。

1. **`// MARK:` コメント** — Xcode のジャンプバーに項目を生成するためのアノテーション風コメント。テスト群を機能別にグルーピングし、ナビゲーションを容易にします
2. **境界値テスト** — `WithinRange` / `BelowLower` / `AboveUpper` / `AtBoundaries` の 4 ケースで仕様の角を網羅
3. **1 メソッド 1 検証ではなく、関連する複数アサーションをまとめる** — `testClampAtBoundaries` は上下境界を 1 つのメソッドで検証。意味的にひとまとまりだから許容
4. **`accuracy:` の使い分け** — `clamp` の戻り値は厳密一致で OK だが、`visibleContentsRect` のような分数演算では `accuracy: 0.001` を付与

統合テスト的な「ラウンドトリップ」も 1 メソッドだけ用意されています。

```swift
func testRoundTripCentered2x() {
    let imageSize = CGSize(width: 3840, height: 2160)
    let center = ZoomMath.defaultPanCenter(for: imageSize)

    let visible = ZoomMath.visibleContentsRect(
        zoomLevel: 2.0,
        panCenter: center,
        imageSize: imageSize
    )
    let crop = ZoomMath.cropRect(contentsRect: visible, sourceSize: imageSize)

    // Centred 2x: should crop the middle quarter
    XCTAssertEqual(crop.origin.x, 960.0, accuracy: 1.0)
    XCTAssertEqual(crop.origin.y, 540.0, accuracy: 1.0)
    XCTAssertEqual(crop.size.width, 1920.0, accuracy: 1.0)
    XCTAssertEqual(crop.size.height, 1080.0, accuracy: 1.0)
}
```

> 引用元: src/ZoomacItTests/ZoomMathTests.swift:185-201

`visibleContentsRect → cropRect` という 2 段の関数を連結し、最終結果が直感に合致することを確認しています。個別のユニットテストでは捕まえられない「組み合わせバグ」を検出する保険です。

### `StrokeManagerTests` — 状態を持つクラスのテスト

`StrokeManager` は Undo スタックを内部状態として持ちます。Pure function ではないので、各テストはインスタンスを **その場で生成** し、状態を作り、検証する流れになります。

```swift
import XCTest
@testable import ZoomacIt

final class StrokeManagerTests: XCTestCase {

    func testPushAndPopSnapshot() {
        let manager = StrokeManager()

        // Initially empty
        XCTAssertNil(manager.popUndoSnapshot())
        XCTAssertEqual(manager.undoLevels, 0)

        // Push a nil snapshot (representing empty canvas)
        manager.pushUndoSnapshot(nil)
        XCTAssertEqual(manager.undoLevels, 1)

        // Pop returns the snapshot with nil finishedLayer and default backgroundMode
        let snapshot = manager.popUndoSnapshot()
        XCTAssertNotNil(snapshot, "Stack was not empty, should return a snapshot")
        XCTAssertNil(snapshot?.finishedLayer, "Popped snapshot should have nil finishedLayer since we pushed nil")
        XCTAssertEqual(manager.undoLevels, 0)
    }
```

> 引用元: src/ZoomacItTests/StrokeManagerTests.swift:1-22

この `StrokeManagerTests` には興味深い設計判断があります。

- **`setUp()` で共有インスタンスを作らず、各テスト内で `let manager = StrokeManager()` を毎回新規生成** している
- これにより「テスト間の状態共有」を完全に断ち切り、順序依存バグを構造的に排除している

仕様の境界 — 「Undo は最大 30 段まで」 — も明示的にテストされています。

```swift
func testUndoStackCap() {
    let manager = StrokeManager()

    // Push 35 snapshots — should cap at 30
    for _ in 0..<35 {
        manager.pushUndoSnapshot(nil)
    }

    XCTAssertEqual(manager.undoLevels, 30)
}
```

> 引用元: src/ZoomacItTests/StrokeManagerTests.swift:39-48

「35 件 push したのに 30 件しか残らない」という仕様を、コード上の事実としてロックします。将来この上限を変更する開発者は、まずこのテストを書き換えてから実装を変えることになります。テストはこうして **仕様書としても機能** します。

### `SettingsTests` — シングルトンと UserDefaults を扱う技法

`Settings.shared` は `UserDefaults.standard` をストレージとするシングルトンです。テストプロセス内で値を書き換えれば、その変更は同一プロセス内のすべてのテストに伝播します。これに対処する典型パターンが、先ほど見た `tearDown` での `resetToDefaults()` 呼び出しです。

```swift
override func tearDown() {
    // Reset shared Settings to registered defaults
    Settings.shared.resetToDefaults()
    super.tearDown()
}
```

> 引用元: src/ZoomacItTests/SettingsTests.swift:14-18

加えて、3 つの観点で網羅的にテストが組まれています。

1. **デフォルト値検証** — `testDefaultPenColor` などで「初期値が期待通り」を確認
2. **ラウンドトリップ** — `testPenColorRoundTrip` などで「set した値が get で取り戻せる」ことを確認
3. **変換の対称性** — `testModifierConversionRoundTrip` で `carbonToNSEventModifiers → nsEventToCarbonModifiers` の合成が恒等関数であることを検証

特に最後のラウンドトリップテストは、見落とされがちな「双方向変換」のバグを早期に発見する強力な手法です。

```swift
func testModifierConversionRoundTripAllModifiers() {
    let allCarbon = UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
    let nsFlags = Settings.carbonToNSEventModifiers(allCarbon)
    let roundTripped = Settings.nsEventToCarbonModifiers(nsFlags)
    XCTAssertEqual(roundTripped, allCarbon)
}
```

> 引用元: src/ZoomacItTests/SettingsTests.swift:229-234

Carbon ↔ AppKit の修飾キー変換は Ch34 で扱った C 橋渡しの中核機能のひとつです。この対称性が崩れると、ホットキー設定が UI と内部表現でずれてしまうため、テストで担保する価値が高い箇所です。

---

## ハンズオン (任意)

XCTest の手応えを掴むため、次のテストを `src/ZoomacItTests/` に追加してみましょう。

1. `src/ZoomacItTests/ZoomMathTests.swift` を開き、末尾の `}` の直前に次のメソッドを追加します。

   ```swift
   func testClampZoomLevelExactBoundaries() {
       XCTAssertEqual(ZoomMath.clampZoomLevel(1.0), 1.0)
       XCTAssertEqual(ZoomMath.clampZoomLevel(8.0), 8.0)
   }
   ```

2. ターミナルで `make test` を実行し、追加したテストを含めて全部 pass することを確認します。

3. 試しに `1.0` を `1.5` に書き換えて再実行し、**意図的に失敗** させてみてください。XCTest の出力フォーマットがどう失敗を伝えてくるかが体感できます。

4. 最後に値を元に戻し、再度 `make test` で grean を確認して終了です。

---

## (参考) Swift Testing — XCTest の後継候補

Swift 5.10 / 6.0 と並走して、Apple は **Swift Testing** という新しいテストフレームワークを公式に提供し始めました。`@Test` マクロベースで、JUnit 5 のスタイルにより近い記述が可能です。

```swift
import Testing

@Test func clampWithinRange() {
    #expect(ZoomMath.clamp(5.0, lower: 0, upper: 10) == 5.0)
}
```

主な違いは次のとおりです。

| 観点 | XCTest | Swift Testing |
|---|---|---|
| テスト宣言 | `func testXxx()` | `@Test func xxx()` |
| アサーション | `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| パラメータ化テスト | 標準サポートなし | `@Test(arguments: [...])` |
| 並列実行 | デフォルト直列 | デフォルト並列 |
| Swift Concurrency 統合 | 後付け | ネイティブ |
| 利用可能 SDK | 全 Apple プラットフォーム + Linux | Swift 5.10+ 限定 |

Swift Testing はモダンで魅力的ですが、本書執筆時点 (2026 年) では XCTest が **依然としてデファクト** であり、ZoomacIt も XCTest 一本で運用しています。理由は次のとおりです。

- 既存資産 (12 ファイル・135 メソッド) を移行する ROI が低い
- XCTest は Xcode との統合が成熟しており、UI テストとの併存も容易
- CI / xcodebuild / Linter / カバレッジツールチェーンが XCTest 前提

新規プロジェクトであれば Swift Testing を選ぶ価値は十分ありますが、**既存プロジェクトでは XCTest を続けて使うのが現実的** です。両者は同一テストターゲット内に共存可能なので、段階的な移行も後から選択できます。

---

## まとめ

XCTest は Apple 標準の成熟したテストフレームワークで、Java の JUnit 5 とほぼ同等の機能を提供します。`@testable import` で internal メンバーに踏み込み、`func testXxx()` という命名規則でテストメソッドを定義し、`XCTAssertEqual` などのアサーションで結果を検証する、というシンプルな構造です。

ZoomacIt のテスト戦略は明確です — **Pure function と Models は徹底的に、UI / Controller / システム連携は手動で**。この線引きをコードベース全体で守ることで、約 135 個のユニットテストが `make test` 数十秒で全 pass する高速で信頼できる安全網となっています。設計段階で「テスト容易性」を制約として持ち込み、`ZoomMath` のような static 関数集合を切り出す判断は、テスト戦略がアーキテクチャを駆動する好例です。

これで Part III「ZoomacIt 深掘り」の全章が完了しました。次の Part IV では、ここまで学んだ知識を総動員して、実際に ZoomacIt のコードを変更する小さなハンズオンに取り組みます。最初の課題は「新しいペン色を追加する」 — Models 層、Settings 層、UI 層、テスト層の 4 箇所を一貫して触る、横断的な実装課題です。

---

## 次に読む章

→ Part IV - [38. 新しいペン色を追加する](../part4-handson/38-add-pen-color.md)
