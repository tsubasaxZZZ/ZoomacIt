# Ch38. ハンズオン 1: 新しいペン色を追加する

## 課題概要

Part IV のハンズオン編、その第 1 弾です。ZoomacIt の描画機能には現在 6 色のペン色 (`red`, `green`, `blue`, `orange`, `yellow`, `pink`) が用意されています。本章ではここに **`purple` (紫)** を 1 色追加し、設定画面の「Default Color」プルダウンに表示し、さらに `XCTest` でテストを追加するところまでを一気通貫で行います。

ゴールは「機能を 1 つ増やす」ことそのものではなく、Swift プロジェクトに変更を加える際の **最小サイクル** ―― コードを編集し、コンパイラの指摘に従い、テストを追加し、ビルドを通し、実機で動作確認するまで ―― を 15 分で体験することにあります。とりわけ、`enum` に `case` を追加した瞬間に Swift コンパイラが「`switch` 文が網羅的でない」と警告してくれる挙動を体感することで、Swift の型システムがいかに作業を導いてくれるかを実感してもらいます。

このハンズオンは、Part II で学んだ言語機能 (Enumerations, Properties) と Part III で学んだ ZoomacIt の構造 (XCTest, `@AppStorage`) が一本につながる結節点でもあります。

> 引用元: src/ZoomacIt/Models/DrawingState.swift:1-30, src/ZoomacIt/Settings/DrawTab.swift:27-49, src/ZoomacItTests/PenColorTests.swift:1-47

---

## 前提

このハンズオンに着手する前に、以下の章を一通り読み終えていることを推奨します。

| 章 | 内容 | このハンズオンでの使い所 |
|---|---|---|
| Ch11 | Enumerations | `case` の追加と `CaseIterable` の理解 |
| Ch13 | Properties (Computed) | `nsColor` computed property の意味 |
| Ch37 | XCTest | `XCTestCase` 継承クラスへのテスト追加 |

加えて、ローカル環境で次のコマンドが通ることを確認してください。

```bash
make build       # Debug ビルド
make test        # 単体テスト実行
make run         # ビルド + 起動
```

`make build` がエラーなく完了する状態を出発点とします。もし通らない場合は、Ch00 の前提セットアップに戻ってから本章に取り組んでください。

---

## 学習狙い

このハンズオンを終える頃には、次の 4 つを「手を動かして」理解できているはずです。

1. **`enum` に `case` を追加する一連の作業**
   `case purple` の 1 行追加から始まり、波及する箇所をどう特定するかを学びます。
2. **`switch` の網羅性チェックの恩恵**
   `case` を追加した瞬間に、関連する `switch` 文がコンパイルエラーを発します。「足りない `case` を 1 つも見逃さない」という Swift の保証が、なぜ大規模リファクタリングを安全にするのかを実感します。
3. **`@AppStorage` と `Picker` のバインディング**
   `Picker` の選択肢を `ForEach(PenColor.allCases, id: \.self)` で生成しているため、`enum` を拡張するだけで UI が自動的に追従する ―― この「`CaseIterable` の威力」を観察します。
4. **XCTest にテストを追加するサイクル**
   既存の `PenColorTests.swift` にメソッドを 2〜3 個追加し、`make test` で緑になることを確認します。テストは「あとで書く」のではなく「機能と同じ PR で書く」習慣を体に入れます。

これら 4 つはいずれも、本章以降のすべてのハンズオン (シェイプ追加、ホットキー追加、ローカライズ追加 …) で繰り返し使う基本動作です。

---

## ステップ

ここからが実作業です。順番通りに進めることを推奨しますが、Step 2 のコンパイルエラーは「**わざと一度発生させる**」のがこのハンズオンの肝です。先回りして全部書き直さないでください。

### Step 1: `PenColor` enum に `case purple` を追加する

ファイル: `src/ZoomacIt/Models/DrawingState.swift`

`PenColor` の宣言行に `purple` を追記します。

```swift
enum PenColor: String, Sendable, CaseIterable {
    case red, green, blue, orange, yellow, pink, purple
}
```

ヒント:

- `enum` の `case` はカンマ区切りで 1 行に並べる書き方と、行を分けて `case purple` と書く書き方の両方が許容されます。既存スタイルに合わせて 1 行追加が無難です。
- `String` raw value 型の `enum` なので、`PenColor.purple.rawValue` は自動的に `"purple"` という文字列になります。これは `@AppStorage` への永続化や、`Picker` の表示ラベルに後で再利用されます。

### Step 2: ビルドして「網羅性エラー」をわざと出す

ここで一度 `make build` を走らせてください。

```bash
make build
```

すると、次のようなコンパイルエラーが出るはずです。

```
DrawingState.swift:8:9: error: switch must be exhaustive
        switch self {
        ^
DrawingState.swift:8:9: note: add missing case: '.purple'
```

これが Swift の `switch` 網羅性チェックです。`enum` に `case` を 1 つ追加したことで、その `enum` を扱うすべての `switch` 文の中で「`.purple` を扱っていない」ものが特定され、コンパイルが失敗します。

ZoomacIt のコードベースで影響を受けるのは、`DrawingState.swift` 内の **2 箇所** ―― `nsColor` computed property の `switch` と、`from(character:)` static method の `switch` ―― です (後者は `default` 句があるためエラーにはなりませんが、後で対応分岐を追加します)。

> Tips: Java や Python から来た方は、この「コンパイラが足りない `case` を全部教えてくれる」挙動に驚くはずです。これがあるからこそ、`enum` を中心に据えた設計が安全に拡張できます。

### Step 3: `nsColor` computed property に対応分岐を追加する

`DrawingState.swift` の `nsColor` プロパティを開き、`switch` 文に `.purple` のケースを追加します。

```swift
var nsColor: NSColor {
    switch self {
    case .red:    return .systemRed
    case .green:  return .systemGreen
    case .blue:   return .systemBlue
    case .orange: return .systemOrange
    case .yellow: return .systemYellow
    case .pink:   return .systemPink
    case .purple: return .systemPurple
    }
}
```

ヒント:

- `NSColor` には `.systemPurple` という定義済みのシステムカラーがあるので、それをそのまま返します (Apple の Human Interface Guidelines 準拠の紫)。
- 既存のスタイルに合わせて、`case .purple:` のあと半角スペースで縦を揃えると読みやすくなります。

### Step 4: `from(character:)` にも対応分岐を追加する (キーボードショートカット連動)

`from(character:)` は描画モード中にキーボードのキー (`R` キーで赤、`G` キーで緑 …) を押すとペン色を切り替える、ZoomIt 互換のショートカット解決メソッドです。`P` は既に **pink** に割り当てられているため、紫には別のキーを割り当てる必要があります。

ここではシンプルに `U` キー (purp**U**le から取る) を紫に割り当てます。

```swift
static func from(character: String) -> PenColor? {
    switch character.uppercased() {
    case "R": return .red
    case "G": return .green
    case "B": return .blue
    case "O": return .orange
    case "Y": return .yellow
    case "P": return .pink
    case "U": return .purple
    default:  return nil
    }
}
```

ヒント:

- このメソッドは `default` 句を持つので、`.purple` を追加しなくてもコンパイルエラーにはなりません。しかし `testEveryColorHasCharacterMapping` というテスト (詳しくは Step 6) が「全色がキーボードで到達可能であること」を保証しているため、ここで分岐を追加しないとテストが赤くなります。これは「テストが仕様を語っている」良い例です。
- もしキーの選択に迷ったら、まずは `U` で進めて、後で別の文字に変えても構いません。`from(character:)` 内の文字列 1 箇所を書き換えるだけです。

### Step 5: `DrawTab` の `Picker` は何もしなくていい

ここで `src/ZoomacIt/Settings/DrawTab.swift` を開いてみてください。`Picker` の中身はこうなっています。

```swift
Picker("Default Color", selection: penColor) {
    ForEach(PenColor.allCases, id: \.self) { color in
        HStack {
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .frame(width: 12, height: 12)
            Text(color.rawValue.capitalized)
        }
        .tag(color)
    }
}
```

`ForEach(PenColor.allCases, ...)` で全ケースをループしているので、`enum` に `case purple` を追加した時点で自動的に Picker の選択肢にも紫が現れます。`CaseIterable` プロトコルが提供する `allCases` 静的プロパティの威力です。表示ラベルも `color.rawValue.capitalized` から `"Purple"` が自動生成されます。

このステップでは UI 側に手を加えなくて済むことを **目で確認** してください。「`enum` を変えたら UI も自動で追従する」のが、このコードベースが採用するパターンの中核です。

### Step 6: `PenColorTests` にテストを追加する

ファイル: `src/ZoomacItTests/PenColorTests.swift`

既存テストの末尾、`testRawValueRoundTrip()` の下あたりに以下を追加します。

```swift
func testPurpleCase() {
    let purple = PenColor.purple
    XCTAssertEqual(purple.nsColor, .systemPurple)
    XCTAssertEqual(purple.rawValue, "purple")
}

func testAllCasesIncludesPurple() {
    XCTAssertTrue(PenColor.allCases.contains(.purple))
}

func testFromCharacterPurple() {
    XCTAssertEqual(PenColor.from(character: "u"), .purple)
    XCTAssertEqual(PenColor.from(character: "U"), .purple)
}
```

加えて、既存の `testAllCasesCount` は色数を `6` でハードコードしていますので、これを **`7`** に更新する必要があります。これも「一緒にメンテする」サイクルの一部です。

```swift
func testAllCasesCount() {
    XCTAssertEqual(PenColor.allCases.count, 7)
}
```

同じく `testEveryColorHasCharacterMapping` の `chars` 配列も `["R", "G", "B", "O", "Y", "P", "U"]` に更新します。これらの「数字がハードコードされた既存テスト」を更新し忘れて落ちる、というのはハンズオンあるあるです。あえて指摘せず一度ハマってもらってもよい部分です。

### Step 7: `make build && make test` で確認

ターミナルで次を実行します。

```bash
make build && make test
```

ビルドが通り、テストが全件 pass することを確認します。失敗した場合は、出力の上部にあるエラーメッセージから 1 つずつ潰してください。多くの場合、原因は次のいずれかです。

- `nsColor` の `switch` で `.purple` を追加し忘れた
- `testAllCasesCount` の数字を更新し忘れた
- `testEveryColorHasCharacterMapping` の `chars` 配列に新しい文字を追加し忘れた

### Step 8: `make run` で実機確認

```bash
make run
```

メニューバーから設定画面を開き、`Draw` タブの **Default Color** プルダウンに `Purple` が追加されていることを目視確認します。`Purple` を選んで保存し、Draw モード (デフォルトでは `⌃2`) を起動して描画してみてください。紫色のペン跡が描かれれば成功です。

加えて Draw モード中に `U` キーを押し、ペン色が紫に切り替わることも確認しましょう。

---

## 失敗例: もし `case purple` だけ足してビルドしたら

このハンズオンの肝は Step 2 の「わざとエラーを出す」部分にあります。仮に Step 1 だけ実行して `make build` した場合、Swift コンパイラは次のように振る舞います。

1. `nsColor` の `switch` 文に `.purple` のケースが無いため、`Switch must be exhaustive` エラーで停止
2. エラーメッセージにご丁寧にも `note: add missing case: '.purple'` と「足りない case 名」まで明示
3. ビルドはまったく進まず、`.app` バンドルは生成されない

この挙動は Java の `switch` (Java 14 以前) や Python の `match` (Python 3.10+) には無いか、あっても警告止まりです。Swift では **コンパイルが通らない** ことが安全網になっています。

逆に、`from(character:)` のように `default` 句がある `switch` ではエラーが出ません。これは「明示的に default を書いた以上、足りないケースは default にフォールスルーするのが意図」という Swift の解釈です。「default 句を書くか、書かずに網羅性に頼るか」は設計判断であり、ZoomacIt は前者を採っています ―― しかしそのトレードオフとして、テスト (`testEveryColorHasCharacterMapping`) が仕様の番人を務めるわけです。

---

## 動作確認チェックリスト

すべてに チェック が付けば完了です。

- [ ] `make build` がエラーなく完了する
- [ ] `make test` で `PenColorTests` 系のテストが全件 pass する
- [ ] 設定 → Draw タブの Default Color プルダウンに `Purple` が表示される
- [ ] Default Color に `Purple` を選んで保存できる
- [ ] Draw モードで紫色のペンで線が引ける
- [ ] Draw モード中に `U` キーで紫色に切り替えられる

---

## 解答例

解答コードと詳細な解説は以下に置いてあります。先に自分で取り組んでから答え合わせをするのが、もっとも学びの深い進め方です。

→ [`learning-swift/answers/38-add-pen-color/`](../answers/38-add-pen-color/README.md)

---

## さらにチャレンジ

基本ハンズオンを終えたら、次の発展課題に挑んでみてください。難易度が緩やかに上がります。

1. **別の色を追加してみる**
   `cyan` (`.systemCyan`)、`brown` (`.systemBrown`)、`mint` (`.systemMint`) のいずれかを追加してください。同じ手順で済むはずです。これにより「3 度目の正直で手が覚える」効果を得られます。
2. **`from(character:)` の対応文字を変える**
   `purple` を `U` ではなく別の文字 (例えば `V` for **V**iolet) に変えてみてください。テストの定数も同期して書き換える必要があります。
3. **Picker をグリッド表示に変える**
   `Picker` の代わりに `LazyVGrid` を使って 4 列グリッドで色見本を並べるレイアウトに変えてみてください。SwiftUI のレイアウト操作の入門として最適です。
4. **ローカライズしてみる**
   `Text(color.rawValue.capitalized)` のままだと、英語圏外のユーザーには「Purple」と英語で表示されます。`String(localized:)` や `LocalizedStringKey` を使い、`ja.lproj/Localizable.strings` に「紫」を加えるとどうなるかを試してみてください。Ch46 (ローカライズ) の予習になります。

---

## この章のまとめ

- `enum` に `case` を 1 つ追加すると、Swift コンパイラは関連する `switch` 文の網羅性違反を **すべて** 列挙してくれる。これは大規模リファクタリングの強力な味方である。
- `CaseIterable` プロトコルの `allCases` を使った UI 生成 (`ForEach(EnumType.allCases, ...)`) は、機能拡張時に UI を **自動で** 追従させる定型パターンである。
- ZoomacIt のコードベースは、enum 中心の設計とテストが仕様を担保する設計を採っており、「コードを変えるとテストが赤くなる」ことを通じて変更箇所の見落としを防いでいる。
- 機能追加とテスト追加は同じサイクルで行う ―― これが「あとで書く」習慣を捨てる第一歩である。

---

## 次に読む章

→ [Ch39. ハンズオン 2: 新しいシェイプ (三角形) を追加する](./39-add-shape.md)
