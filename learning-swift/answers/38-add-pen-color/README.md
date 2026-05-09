# 解答例: Ch38 ハンズオン 1 — 新しいペン色を追加する

このディレクトリには、[Ch38 ハンズオン](../../part4-handson/38-add-pen-color.md) の解答コードと、なぜそう書いたかの解説をまとめています。まずは自分で取り組み、つまずいた箇所だけを参照する使い方を推奨します。

## 解答の概要

このハンズオンで触るファイルは結局のところ **2 ファイル** です。

| ファイル | 変更内容 |
|---|---|
| `src/ZoomacIt/Models/DrawingState.swift` | `PenColor` enum に `purple` ケースを追加し、`nsColor` と `from(character:)` の `switch` に対応分岐を追加 |
| `src/ZoomacItTests/PenColorTests.swift` | 既存テストの定数を更新し、紫専用のテストを 3 つ追加 |

UI 側 (`DrawTab.swift`) には一切手を入れません。これは `Picker` が `ForEach(PenColor.allCases, id: \.self)` で全ケースを動的にループしているためで、`CaseIterable` プロトコルが提供する `allCases` の威力により、`enum` 拡張だけで UI が自動的に追従します。コード行数にして合計 10 行未満の変更で完結します。

ポイントは「変更が enum という 1 箇所に集約される」ことです。これは Swift コミュニティで広く使われている **「真実の単一の源泉 (single source of truth)」** という設計原則の小さな一例で、データ定義を 1 箇所にまとめることで、UI、ロジック、テストの三者が自然に同期します。

---

## Step 1-3: `DrawingState.swift` の差分

```diff
--- a/src/ZoomacIt/Models/DrawingState.swift
+++ b/src/ZoomacIt/Models/DrawingState.swift
@@ -1,30 +1,32 @@
 import AppKit

 /// Available pen/text colors.
 enum PenColor: String, Sendable, CaseIterable {
-    case red, green, blue, orange, yellow, pink
+    case red, green, blue, orange, yellow, pink, purple

     var nsColor: NSColor {
         switch self {
         case .red:    return .systemRed
         case .green:  return .systemGreen
         case .blue:   return .systemBlue
         case .orange: return .systemOrange
         case .yellow: return .systemYellow
         case .pink:   return .systemPink
+        case .purple: return .systemPurple
         }
     }

     /// Map from key character to pen color.
     static func from(character: String) -> PenColor? {
         switch character.uppercased() {
         case "R": return .red
         case "G": return .green
         case "B": return .blue
         case "O": return .orange
         case "Y": return .yellow
         case "P": return .pink
+        case "U": return .purple
         default:  return nil
         }
     }
 }
```

### なぜこう書いたか

#### `case purple` の追加位置

`case red, green, blue, orange, yellow, pink, purple` という形で末尾に追記しています。`enum` の `case` 順序は通常コードの挙動に影響しませんが、`CaseIterable.allCases` が返す配列の順序は宣言順になります。`Picker` の表示順 (赤 → 緑 → 青 → オレンジ → 黄 → ピンク → 紫) を維持するためには、末尾追加が自然です。

もし「視覚的なグループ化」を優先するなら、`case red, pink, orange, yellow, green, blue, purple` のように虹順 (色相環順) に並べ替える選択肢もあります。ただしその場合、`@AppStorage` で永続化された raw value (`"red"`、`"blue"` …) は影響を受けないので、ユーザーの設定が壊れることはありません。並べ替えは UI 表示順だけの問題です。

#### `.systemPurple` の選択

`NSColor` には大きく分けて 2 系統の色定数があります。

| 系統 | 例 | 特徴 |
|---|---|---|
| Apple system colors | `.systemRed`, `.systemPurple` | ライト/ダークモードで自動調整される。HIG 準拠 |
| 固定色 | `.purple` (`NSColor.purple`) | RGB 固定値 (0.5, 0, 0.5)。モード非依存 |

ZoomacIt は既存の他色 (`.systemRed`, `.systemGreen` …) すべてで system colors 系統を使っているので、`.systemPurple` を選ぶのが一貫性の点で正解です。これにより、ダークモード時にも視認性のよい紫が描画されます。

#### `case "U": return .purple` の選択理由

`P` キーは既に `.pink` に予約されているため、紫には別の文字を割り当てる必要があります。`U` (purp**U**le) を採用したのは、英単語の中に含まれる音節として記憶しやすいためです。代替案として `V` (Violet) や `M` (Mauve) もあり得ますが、いずれも単一文字キーなので入力負荷は同じです。

ここで注意すべきは、`from(character:)` の `switch` には `default:` 句があるため、`.purple` の対応分岐を追加しなくてもコンパイル自体は通ってしまうことです。しかしテスト `testEveryColorHasCharacterMapping` がこの仕様を守っており、追加を忘れるとテストが赤くなります。「テストが仕様を語る」典型例です。

---

## Step 6: `PenColorTests.swift` の差分

```diff
--- a/src/ZoomacItTests/PenColorTests.swift
+++ b/src/ZoomacItTests/PenColorTests.swift
@@ -3,7 +3,7 @@

 final class PenColorTests: XCTestCase {

     func testAllCasesCount() {
-        XCTAssertEqual(PenColor.allCases.count, 6)
+        XCTAssertEqual(PenColor.allCases.count, 7)
     }

     func testNSColorMapping() {
         XCTAssertEqual(PenColor.red.nsColor, .systemRed)
         XCTAssertEqual(PenColor.green.nsColor, .systemGreen)
         XCTAssertEqual(PenColor.blue.nsColor, .systemBlue)
         XCTAssertEqual(PenColor.orange.nsColor, .systemOrange)
         XCTAssertEqual(PenColor.yellow.nsColor, .systemYellow)
         XCTAssertEqual(PenColor.pink.nsColor, .systemPink)
+        XCTAssertEqual(PenColor.purple.nsColor, .systemPurple)
     }

     func testFromCharacterCaseInsensitive() {
@@ -29,8 +30,8 @@

     func testEveryColorHasCharacterMapping() {
-        let chars = ["R", "G", "B", "O", "Y", "P"]
+        let chars = ["R", "G", "B", "O", "Y", "P", "U"]
         let mapped = chars.compactMap { PenColor.from(character: $0) }
         XCTAssertEqual(mapped.count, PenColor.allCases.count,
                        "Every PenColor should be reachable via a character")
         XCTAssertEqual(Set(mapped).count, PenColor.allCases.count,
                        "Each character should map to a unique color")
     }

     func testRawValueRoundTrip() {
         for color in PenColor.allCases {
             let restored = PenColor(rawValue: color.rawValue)
             XCTAssertEqual(restored, color, "Round-trip failed for \(color)")
         }
     }
+
+    // MARK: - Purple-specific tests
+
+    func testPurpleCase() {
+        let purple = PenColor.purple
+        XCTAssertEqual(purple.nsColor, .systemPurple)
+        XCTAssertEqual(purple.rawValue, "purple")
+    }
+
+    func testAllCasesIncludesPurple() {
+        XCTAssertTrue(PenColor.allCases.contains(.purple))
+    }
+
+    func testFromCharacterPurple() {
+        XCTAssertEqual(PenColor.from(character: "u"), .purple)
+        XCTAssertEqual(PenColor.from(character: "U"), .purple)
+    }
 }
```

### テストコードの設計判断

#### 既存テストの更新 vs. 追加

このハンズオンには「**既存テスト 2 つの定数を更新する**」「**新規テストを 3 つ追加する**」の 2 種類が混在しています。それぞれの意図を整理します。

**既存テストの更新 (`testAllCasesCount`, `testEveryColorHasCharacterMapping`)**
これらは「色の総数」「全色がキー入力で到達可能であること」という仕様を定数で表現しています。仕様自体が「6 色」から「7 色」に変わった以上、定数も同期して更新するのが正しい挙動です。テストを「仕様の表明」と捉えれば、これは仕様変更に対する追従です。

**新規テストの追加 (`testPurpleCase`, `testAllCasesIncludesPurple`, `testFromCharacterPurple`)**
これらは「`.purple` という新しいケースが正しく振る舞うこと」を **明示的に** 表明するテストです。`testNSColorMapping` への 1 行追加だけでも `nsColor` の挙動はカバーできるのですが、独立したメソッドにすることで、将来「紫色だけ何か特殊な扱いになった」場合に該当テストだけが赤くなり、原因特定が容易になります。

両者を併用することで「全体仕様」と「個別仕様」が二重に保護されます。

#### あえて書かなかったテスト

- **`Picker` 表示の UI テスト** … SwiftUI の `Picker` の表示確認はスナップショットテストや UI テストの領分で、ZoomacIt の方針 (Pure function テスト中心) からは外れます。Ch37 で議論したテスト哲学に従い、ここでは書きません。
- **`@AppStorage` への永続化テスト** … `UserDefaults` のスタブ化が必要になり、コストに見合いません。raw value のラウンドトリップ (`testRawValueRoundTrip`) で永続化に必要な前提条件は確認済みなので、これで十分とします。

---

## 別解の議論

### 別解 1: `from(character:)` を辞書で実装する

`switch` が長くなるのが嫌なら、辞書ベースに書き換える手もあります。

```swift
private static let characterMap: [String: PenColor] = [
    "R": .red,
    "G": .green,
    "B": .blue,
    "O": .orange,
    "Y": .yellow,
    "P": .pink,
    "U": .purple,
]

static func from(character: String) -> PenColor? {
    characterMap[character.uppercased()]
}
```

**メリット**: 短い。1 行で全マッピングを表現できる。
**デメリット**: `switch` の網羅性チェックが効かない。新しい色を追加して辞書への登録を忘れると、コンパイラは何も指摘してくれずテストだけが赤くなる。

ZoomacIt は前者 (`switch` 版) を採用しています。これは「コンパイラに守ってもらう」哲学を貫くためです。型安全性と可読性のトレードオフですが、`enum` の規模が 7 程度であれば `switch` のコストは無視できます。

### 別解 2: `Picker` のラベルを `LocalizedStringKey` で管理する

現状の `Text(color.rawValue.capitalized)` は英語固定です。日本語ロケール下でも「Purple」と表示されます。これを「紫」と表示したい場合は、computed property `displayName` を `PenColor` に追加します。

```swift
var displayName: LocalizedStringKey {
    switch self {
    case .red:    return "color.red"
    case .green:  return "color.green"
    case .blue:   return "color.blue"
    case .orange: return "color.orange"
    case .yellow: return "color.yellow"
    case .pink:   return "color.pink"
    case .purple: return "color.purple"
    }
}
```

そして `Localizable.strings` の `ja.lproj` に `"color.purple" = "紫";` のように記述します。これは Ch46 (ローカライズ) で詳しく扱う発展課題です。

### 別解 3: `CGColor` ベースに統一する

ZoomacIt は AppKit ベースなので `NSColor` で問題ありませんが、もし将来 SwiftUI 比率を増やすなら `Color` 型に揃えることも検討できます。`Color(nsColor:)` で双方向変換が可能なので、現状の設計でも SwiftUI 側で問題は起きていません。これは将来のリファクタリング案件であり、本ハンズオンの範囲外です。

---

## 補足: 「Picker は何もしなくていい」が成立する仕組み

DrawTab の Picker が `ForEach(PenColor.allCases, ...)` でループしているため、enum 拡張時に UI コードを触らなくて済む ―― この仕組みは表面的な便利さだけでなく、**保守性の観点からも極めて重要** です。

仮に Picker を以下のようにハードコードしていたとしましょう。

```swift
Picker("Default Color", selection: penColor) {
    Text("Red").tag(PenColor.red)
    Text("Green").tag(PenColor.green)
    Text("Blue").tag(PenColor.blue)
    Text("Orange").tag(PenColor.orange)
    Text("Yellow").tag(PenColor.yellow)
    Text("Pink").tag(PenColor.pink)
    // ← purple を追加し忘れる可能性
}
```

この書き方では、`enum` に `case` を追加した際に **UI 側を更新し忘れる** バグが容易に発生します。発生してもコンパイルは通り、テストも (UI を見ない限り) 通ります。発覚するのはユーザーが「紫が選べない」と気づいたときです。

`ForEach(PenColor.allCases, ...)` のような **データ駆動 UI** は、こうしたヒューマンエラーを構造的に排除します。Single source of truth の利点はここに現れます。

---

## 動作確認結果の例

`make build && make test` の最終出力は次のようになるはずです。

```
xcodebuild test ... ZoomacItTests
...
Test Suite 'PenColorTests' passed at 2026-XX-XX HH:MM:SS.
     Executed 9 tests, with 0 failures (0 unexpected) in 0.012 (0.014) seconds
...
** TEST SUCCEEDED **
```

(既存 6 個 + 新規 3 個 = 9 テストになります)

---

## さらに学ぶ

このハンズオンで体験した「enum 中心設計」と「コンパイラ駆動開発」は、Swift プロジェクト全般に通用する設計手法です。次のハンズオン (Ch39) では、より大きな対象である **Shape (図形種別)** に同じパターンを適用します。enum 拡張 → switch 網羅性 → Picker 自動追従 → テスト追加、という型 (テンプレート) を体に入れる訓練として位置付けてください。

→ [Ch39. ハンズオン 2: 新しいシェイプ (三角形) を追加する](../../part4-handson/39-add-shape.md)
