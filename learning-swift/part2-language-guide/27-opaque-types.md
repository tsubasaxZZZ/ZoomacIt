# 27. Opaque Types

## この章で学ぶこと

Swift 5.1 で導入された **opaque type (不透明型)** は、関数の戻り値の型を **「具体型は隠したいが、コンパイラには確定された 1 つの型として扱わせたい」** ときに使うキーワードです。SwiftUI で `var body: some View { ... }` と書くたびに使う、最も身近な機能の 1 つです。

本章では、なぜ opaque type が必要だったのか、`some` と `any` の違い、SwiftUI における役割、そして Generics との関係を順に見ていきます。Java には対応する概念が存在しないため、ここで紹介するのは **Swift 独自の型システム** です。

この章は短めの丁寧解説章です。型理論には深入りせず、「SwiftUI を書くために知っておくべき」実用的な視点でまとめます。

---

## 問題提起 — protocol を返すだけでは不十分

まず、なぜ新しいキーワードが必要になったのかから始めます。次のような protocol と具体型を考えてください。

```swift
protocol Animal {
    func sound() -> String
}

struct Dog: Animal {
    func sound() -> String { "Woof" }
}

struct Cat: Animal {
    func sound() -> String { "Meow" }
}
```

ここで「動物を作って返す関数」を書きたいとします。素直な書き方は次のとおりです。

```swift
func makeAnimal() -> Animal {
    Dog()
}
```

一見問題なさそうですが、この戻り値の型 `Animal` には 2 つの厄介な性質があります。

1. **呼び出し側は具体型を知らない** (これは意図どおり)。
2. **コンパイラも具体型を確定できていない**。`Animal` という protocol は実装を持つかもしれない複数の型の集合 (existential type と呼ばれる) として扱われ、内部で型消去 (type erasure) が行われます。

その結果、性能オーバーヘッドが発生します。protocol 値はヒープ上に箱を作って実体を格納し、メソッド呼び出しはディスパッチテーブル経由で間接的に行われるからです。さらに、`some PrimaryAssociatedType` を要求する protocol (`Collection` など associated type を持つ protocol) は、そもそも戻り値の型として書くことに以前は強い制約がありました。

実装側がやりたかったのは、もっと素直な要求のはずです。

> **「内部実装は `Dog` という 1 つの具体型に決まっている。外からは『何かの `Animal`』としか見えなくてよい。でも、それを protocol 値の箱に詰めて性能を犠牲にするのはもったいない」**

この要求に答えるのが opaque type です。

---

## some キーワード — 具体型を隠蔽しつつ、確定はさせる

戻り値の型に `some` を付けると、その関数は **「あるひとつの具体型」を返す** とコンパイラに約束したことになります。具体的にどの型かは関数の実装だけが知っています。

```swift
func makeAnimal() -> some Animal {
    Dog()  // 内部はあくまで Dog
}
```

呼び出し側から見える情報は次のとおりです。

- 戻り値は `Animal` プロトコルに適合している。
- すべての呼び出しで返ってくる型は **常に同じ具体型** である (= 確定している)。

ただし、その「具体型」が何であるかは見えません。これが opaque type の語感どおり、外側からは「不透明 (opaque)」だけれども内部からは透明、という非対称な可視性です。

### 重要な制約 — 戻り値の具体型は 1 つに決まらなければならない

`some` は **「実装側は 1 つの型に決め打ちする」** という宣言です。したがって、条件分岐で異なる具体型を返すコードはコンパイルエラーになります。

```swift
func makeAnimal(isDog: Bool) -> some Animal {
    if isDog {
        return Dog()
    } else {
        return Cat()  // コンパイルエラー: 戻り値が Dog と Cat で不一致
    }
}
```

「呼び出し条件で型を変えたい」場合は、後述する `any` を使う必要があります。

### コンパイラだけが知っている具体型

opaque type のもう 1 つの効能は、**型情報を保ったまま隠蔽する** という点です。たとえば次のコードは合法です。

```swift
let a = makeAnimal()
let b = makeAnimal()
// a と b は「同じ型」であるとコンパイラは知っている
let array = [a, b]  // OK: [some Animal] として推論される
```

これは protocol 戻り値型では実現できません (existential 同士は型が同じかどうか保証できないため)。

---

## some と any の対比 (Swift 5.7+)

Swift 5.7 で `any` キーワードが導入され、existential type (型消去された protocol 値) を明示的に書くようになりました。`some` と `any` は文法的に対称的に並ぶため、ここで対比を整理します。

```swift
let opaqueAnimal: some Animal = Dog()       // 具体型は Dog に確定 (コンパイラだけが知る)
let existentialAnimal: any Animal = Dog()   // 任意の Animal を入れられる箱
```

| 観点 | `some Animal` (opaque) | `any Animal` (existential) |
|------|------------------------|----------------------------|
| 具体型 | 1 つに確定 (隠蔽されている) | 複数の異なる型を保持できる |
| 型消去 | なし | あり (内部で box を作る) |
| 性能オーバーヘッド | なし (静的ディスパッチ) | あり (動的ディスパッチ + ヒープ) |
| 異なる具体型の配列 | 不可 (`[some Animal]` は 1 つの型) | 可 (`[any Animal]` に Dog と Cat を混在) |
| associated type を持つ protocol | 戻り値として自然に書ける | 制約あり (Swift 5.7 で緩和) |
| 主な用途 | 関数の戻り値、SwiftUI の `body` | 異種コレクション、ランタイム多態 |

`any` は **箱を渡している**、`some` は **コンパイラに型をささやいている**、という比喩で覚えると整理しやすいです。

---

## 使い分けの判断フロー

実装で迷ったときは、次の順で判断してください。

1. **戻り値や格納する値の具体型が、1 つに固定できるか?**
   - はい → `some` を使う。性能オーバーヘッドなし。
   - いいえ (条件で型が変わる、配列に異なる型を混ぜる) → `any` を使う。
2. **呼び出し側に具体型を見せたいか?**
   - 見せたい → `some` も `any` も使わず、具体型 (`Dog`) を直接返す。
   - 隠したい → 上記 1. に従う。
3. **associated type を持つ protocol を戻したいか?**
   - はい → 基本は `some` (例: `some Collection<Int>`)。

実用上は、**「迷ったらまず `some` を試して、要件が合わなくなったら `any` に切り替える」** という方針で困りません。`some` のほうが性能面の前提が単純で、コンパイラのチェックも厳しい (= バグを早く見つけられる) からです。

---

## SwiftUI での `some View` — 最も日常的な opaque type

SwiftUI を学び始めると、必ず最初に出会うのが `some View` です。

```swift
struct ContentView: View {
    var body: some View {
        Text("Hello")
    }
}
```

なぜここで `View` ではなく `some View` なのか。SwiftUI の View は内部的に **入れ子の構造をすべて型として表現する** 設計になっており、たとえば次のような view の本当の型は

```swift
VStack {
    Text("A")
    Button("B") { }
}
```

`VStack<TupleView<(Text, Button<Text>)>>` のような長大なジェネリック型になります。さらにモディファイアを重ねるたびに型はどんどん複雑になります。

開発者がこの型を毎回手で書くのは現実的ではありません。一方で、SwiftUI の差分計算を高速化するためには、**型情報をランタイムに失わずに保ちたい** という要件があります。`any View` で型消去してしまうと、この最適化が壊れます。

そこで `some View` の出番です。

- **書く側は短く済む** (本当の型を知らなくてよい)。
- **コンパイラには 1 つの具体型として伝わる** ので、SwiftUI の最適化が効く。

これはまさに opaque type が解決すべき問題そのものです。SwiftUI のために `some` が導入されたと言っても過言ではありません。

---

## Generics との関係 — 「逆ジェネリクス」

opaque type は **「逆ジェネリクス (reverse generics)」** と呼ばれることがあります。それぞれが「型を選ぶ主体」を以下のように整理すると意味が見えてきます。

| キーワード | 型を選ぶのは | 例 |
|-----------|-------------|----|
| Generics `<T: Animal>` | **呼び出し側** | `func wrap<T: Animal>(_ a: T) -> T` |
| Opaque `some Animal` | **実装側** | `func makeAnimal() -> some Animal` |
| Existential `any Animal` | **どちらでもなく、実行時に変わる** | `var a: any Animal = ...` |

ジェネリクスは「型はあなた (呼び出し側) が決めてください、私はそれに合わせます」という宣言です。opaque type は逆に「型は私 (実装側) が決めます、あなたは中身を気にしないでください」という宣言です。

この対称性が分かると、Swift の型システムでどこに `some` を置くべきかが直感的に判断できるようになります。

---

## ZoomacIt 実コード読解

ZoomacIt の Settings 画面は SwiftUI で書かれています。すべての View で `some View` が登場しています。

### SettingsView の body

```swift
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
            // ...
        }
    }
}
```

> 引用元: src/ZoomacIt/Settings/SettingsView.swift:4-20

`body` の本当の型を手で書こうとすると、`VStack<TupleView<(ModifiedContent<TabView<...>, ...>, Divider, ModifiedContent<HStack<...>, ...>)>>` のような恐ろしく長いジェネリック型になります。`some View` のおかげで開発者は内部構造を気にせず、宣言的なレイアウトに集中できます。

### GeneralTab の body と HotkeyRow の body

子ビューも同様に opaque type を返します。

```swift
struct GeneralTab: View {
    // @AppStorage プロパティ群...

    var body: some View {
        Form {
            Section("Hotkeys") {
                HotkeyRow(label: "Zoom", keyCode: $zoomKeyCode, modifiers: $zoomModifiers)
                HotkeyRow(label: "Draw", keyCode: $drawKeyCode, modifiers: $drawModifiers)
                HotkeyRow(label: "Break Timer", keyCode: $breakKeyCode, modifiers: $breakModifiers)
            }
            // ...
        }
        .formStyle(.grouped)
    }
}

struct HotkeyRow: View {
    let label: String
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Spacer()
            KeyRecorderView(keyCode: $keyCode, modifiers: $modifiers)
                .frame(width: 140, height: 28)
        }
    }
}
```

> 引用元: src/ZoomacIt/Settings/GeneralTab.swift:6-36, 65-79

`GeneralTab.body` と `HotkeyRow.body` は、それぞれ全く異なる具体型を返しますが、コードの記述はどちらも `some View` で済んでいます。これが opaque type の威力です。

ZoomacIt で SwiftUI が使われているのは Settings タブのみで、メインの描画系は AppKit (`NSView`) で実装されています (`BreakTimerView` など)。つまり opaque type を意識するのは Settings 周辺のコードだけ、という割り切った構成になっています。

---

## ハンズオン (任意)

以下を Swift Playground または Xcode で試してみてください。

1. `protocol Animal { func sound() -> String }` と `struct Dog`, `struct Cat` を定義する。
2. `func makeAnimal() -> some Animal { Dog() }` を書き、戻り値で `.sound()` を呼べることを確認する。
3. `if isDog { return Dog() } else { return Cat() }` のように分岐を入れてみてコンパイルエラーになることを確認する。
4. 戻り値型を `any Animal` に書き換えると分岐が通ることを確認する。
5. `[any Animal]` を作って Dog と Cat を混在させる、続けて `[some Animal]` でやってみてエラーになることを比較する。

`some` と `any` の境界線が体感できるはずです。

---

## まとめ

- **opaque type (`some Type`)** は「内部は 1 つの具体型に確定、外部からは型を隠蔽」する戻り値表現。
- **`any Type`** との違い: `some` は型消去なし・性能オーバーヘッドなし・1 つの具体型に確定。`any` は型消去あり・複数の具体型を保持可能。
- 迷ったらまず `some`、要件が合わなければ `any`。
- SwiftUI の `var body: some View` は opaque type の代表例で、巨大なジェネリック型を簡潔に記述するために必須。
- ジェネリクスが「呼び出し側が型を選ぶ」のに対し、opaque type は「実装側が型を選ぶ」逆ジェネリクスと位置付けられる。
- Java には対応する概念がない、Swift 独自の機能。

---

## 次に読む章

→ [28. Automatic Reference Counting](./28-arc.md)
