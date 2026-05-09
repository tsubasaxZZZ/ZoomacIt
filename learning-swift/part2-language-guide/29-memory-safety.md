# 29. Memory Safety

## この章で学ぶこと

Swift は言語設計の根幹に **メモリ安全性 (memory safety)** を据えています。配列の境界外アクセスは実行時に検出され、`nil` の不正な参照外しは `Optional` の仕組みで未然に防がれ、整数オーバーフローはデフォルトで実行時トラップされます。これらの保護は、開発者が `Unsafe` という単語が付いた API を明示的に呼ばない限り、すべて有効になっています。

Java 経験者にとって memory safety という言葉自体は新しくありません。Java も配列境界をチェックし、`null` 参照は `NullPointerException` で検出され、ガベージコレクションがダングリングポインタを排除します。その意味で「メモリ安全」というラベルだけ見れば両言語は同じ立ち位置にあります。

この章で取り上げるのは、その先にある **Swift 5 で追加されたもう 1 段深い安全性** — **メモリへの排他的アクセス (exclusive access to memory)** です。これは Java にも C にも存在しない、Swift がコンパイラと実行時の両方で守ろうとしている新しい保証です。`inout` 引数を 2 か所から同時に書き換えるような状況を、コンパイラが検出して拒否します。

短めの章ですが、「日常的にハマるパターン」と「なぜそういうルールがあるのか」を中心に解説します。

---

## Swift の memory safety の哲学

Swift は次の安全性をデフォルトで保証します。

| 保護対象 | デフォルトの挙動 | エスケープハッチ |
|----------|------------------|------------------|
| 配列境界 | 実行時にチェック、違反でトラップ | `withUnsafeBufferPointer` 等 |
| `nil` 参照 | `Optional` 型で表現を強制 | `!` (force unwrap) |
| 整数オーバーフロー | 実行時トラップ | `&+`, `&-`, `&*` 演算子 |
| 未初期化メモリ | コンパイル時に使用を禁止 | `UnsafeMutablePointer.allocate` |
| 型混同 | 静的型システムで防止 | `unsafeBitCast` |
| 排他アクセス違反 | コンパイル時 + 実行時にチェック | `withUnsafePointer(to:)` 等 |

この一覧から見える設計思想は明確です。**「安全側がデフォルト、危険側は明示的に opt-in」**。 unsafe を選ぶのは開発者の責任であり、その境界線が `Unsafe` というプレフィックスで一目瞭然になっています。

Java と異なるのは最後の行 — 排他アクセスのチェックです。これが Swift 5 以降の memory safety の核心です。

---

## メモリへの排他的アクセス

Swift 5 で正式に導入された規則は、文章にすると 1 行で書けます。

> **同じ変数 (メモリ位置) への 2 つのアクセスのうち、少なくとも 1 つが書き込みであり、それらが時間的に重なってはならない。**

「時間的に重なる」とは何でしょうか。短期 (instantaneous) アクセスでは問題が起こりません。`let a = x; let b = x` のように 1 行ずつ読むだけなら、各アクセスは一瞬で終わるため重なりようがありません。

問題が起こるのは **長期 (long-term) アクセス** です。長期アクセスとは、別のコードが実行されている間ずっと続いているアクセスのことで、Swift では主に次の 3 つで発生します。

- `inout` 引数として渡されている間
- `mutating` メソッドが実行されている間
- 構造体のプロパティに対するクロージャ越しのアクセス

これらは関数本体やメソッド本体が実行される長い時間にわたってアクセスを「占有」します。占有中に同じメモリへ別のアクセスが走ると、「重なり」が発生し、規則違反となります。

なぜこんな規則があるのか。理由は 2 つあります。

1. **値の整合性**。書き込み途中の中間状態を別の場所から読み取れてしまうと、論理的に存在しないはずの値が観測されます。これは並行性とは関係なく、シングルスレッドでも起こります。
2. **コンパイラの最適化余地**。「このメモリは今この関数だけが触る」と保証されていれば、コンパイラはレジスタにキャッシュしたり、命令を並べ替えたりできます。

---

## inout 引数の競合

最も典型的にハマるのは `inout` を 2 か所に渡すケースです。次のような自前 `swap` 関数を考えます。

```swift
func mySwap(_ a: inout Int, _ b: inout Int) {
    let tmp = a
    a = b
    b = tmp
}

var x = 10
var y = 20
mySwap(&x, &y)   // OK: x と y は別の変数
```

これは何の問題もありません。ところが、同じ変数を 2 回渡すと話が変わります。

```swift
var x = 10
mySwap(&x, &x)   // error: inout arguments are not allowed to alias each other
```

コンパイラが直接エラーを出します。`a` と `b` の両方が同じ `x` を指す状況では、関数本体の `a = b` の時点で `b` の値も同時に変わってしまうかもしれず、`mySwap` の意味そのものが壊れます。だからこそ、入り口の段階で禁止されます。

少し複雑な例も見てみましょう。

```swift
var scores = [10, 20, 30]
mySwap(&scores[0], &scores[0])  // error: 同じ要素への重複 inout
```

配列要素についても同じです。同じインデックスを 2 回指定すれば、結局同じメモリへの 2 つの書き込みアクセスになります。

ただし、次は問題ありません。

```swift
mySwap(&scores[0], &scores[1])  // OK: 異なる要素
```

異なるインデックスは異なるメモリ位置として扱われ、競合は起こりません。

---

## mutating メソッド内でのプロパティ競合

もうひとつの典型例は、`mutating func` 内で `self` の他のプロパティを `inout` 引数に渡す場合です。`mutating` メソッドは実行中、**`self` 全体への書き込みアクセスを長期間保持** します。その状態で `self` の一部を別の関数に `inout` として渡すと、同じメモリへの重複アクセスが発生します。

```swift
struct Player {
    var health: Int
    var stamina: Int

    mutating func boost() {
        // self への長期書き込みアクセスが進行中
        mySwap(&health, &stamina)   // OK: health と stamina は別フィールド
        mySwap(&health, &health)    // error
    }
}
```

最初の `mySwap(&health, &stamina)` は問題ありません。`health` と `stamina` は構造体の別々のメモリ領域だからです。一方、同じプロパティを 2 回渡すと、先ほどと同じ理由でエラーになります。

より厄介なのは、構造体全体を `inout` で渡してしまうケースです。

```swift
extension Player {
    mutating func transfer(to other: inout Player) {
        // ...
    }
}

var p = Player(health: 100, stamina: 100)
p.transfer(to: &p)   // error: 同じインスタンスへの重複アクセス
```

`mutating func` の暗黙の `self` への書き込みアクセスと、引数 `other` の書き込みアクセスが同じ `p` を指してしまうため、コンパイラがこれを拒否します。

これらのエラーは「**コードがおかしいから直しましょう**」という素直な信号で、回避策ではなく設計を見直すサインです。同じメモリを 2 つの名前で同時に変更したい状況は、たいていデータモデルの方に問題があります。

---

## 不安全な API — エスケープハッチ

memory safety はデフォルトの保証であって絶対的な禁止ではありません。Swift は、必要な場面では **明示的に** 安全性を諦めるための API を用意しています。代表的なのは次の型・関数です。

- `UnsafePointer<T>` / `UnsafeMutablePointer<T>` — 型付きのポインタ
- `UnsafeRawPointer` / `UnsafeMutableRawPointer` — 型なし (生バイト) のポインタ
- `UnsafeBufferPointer<T>` — 連続領域への型付きビュー
- `withUnsafePointer(to:)`, `withUnsafeMutableBytes(of:)` — スコープ限定でポインタを取り出すヘルパー
- `Unmanaged<T>` — ARC の管理外で参照を保持する仕組み

これらは「**見ればわかる危険信号**」として `Unsafe` という単語を冠しています。コードレビュー中に `Unsafe` という単語を見つけたら、その箇所はメモリ安全性の責任が開発者側にあると即座に分かる仕組みです。

ZoomacIt も Carbon API を呼び出す箇所で、まさにこのエスケープハッチを使っています。

```swift
private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKeyEvent(event)

    return noErr
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:187-200

ここでは Carbon (C 言語ベースの古い macOS API) の `InstallEventHandler` にコールバック関数を登録しています。Carbon は `void *` (= `UnsafeMutableRawPointer`) でユーザーデータを受け渡すため、Swift 側もこれに合わせざるを得ません。

注目すべき設計の流れは次の通りです。

1. 登録時 (`HotkeyManager.start()`) に `Unmanaged.passUnretained(self).toOpaque()` で `self` を生ポインタに変換して Carbon に渡す。
2. コールバックが呼ばれたら、`Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()` で生ポインタを `HotkeyManager` インスタンスに復元する。

ここでは Swift の安全機構が完全に外れています。`userData` が本当に `HotkeyManager` を指しているか、そのインスタンスがまだ解放されていないか — どれも実行時に検証されません。だから `HotkeyManager` は `static let shared` のシングルトンとして、アプリの寿命と一致するライフタイムを持たせる設計になっているのです。

これが Swift の memory safety の使い分けです。**99% は安全な世界で書き、外部 API との境界 1% だけ unsafe な世界に踏み込む**。

---

## Swift と Rust の比較

排他的アクセスというルールを聞いて Rust の所有権 (ownership) と借用 (borrow) を思い出した方もいるかもしれません。実際、両者は同じ問題意識から出発しています。

|  | Swift | Rust |
|---|-------|------|
| 検出タイミング | コンパイル時 + 実行時 | コンパイル時のみ |
| 適用範囲 | `inout` などの長期アクセス中心 | すべての参照 (`&`, `&mut`) |
| エスケープハッチ | `Unsafe*` 系 API | `unsafe { ... }` ブロック |
| ライフタイム注釈 | 不要 (限定的に使用) | 明示的に必須な場面が多い |
| 学習コスト | 低い (普段意識しない) | 高い (借用検査と常に格闘) |

Rust は **借用検査器 (borrow checker)** によって、すべての参照について「同時に複数の不変借用、または単一の可変借用」という規則をコンパイル時に厳密に検証します。これは強力な安全性をもたらす一方、コンパイルを通すこと自体が学習負担になります。

Swift は適用範囲を `inout` のような長期アクセスに絞り、それ以外は実行時チェックや `Unsafe` 系へのエスケープを許す設計を採りました。**安全性と書きやすさのバランスを取った折衷** であり、Rust ほど厳密ではない代わりに、ふだん書くコードで借用検査の存在を意識する必要はほぼありません。

どちらが優れているという話ではなく、言語の用途とトレードオフの違いです。Swift は「アプリを書く生産性」を、Rust は「システムレベルでの絶対的な保証」を優先したと理解すると整理しやすいでしょう。

---

## strict concurrency との関係

Swift 6 で本格化した **strict concurrency checking** も、広い意味では memory safety の延長線上にあります。複数のスレッド (= タスク) から同じ可変状態を同時に触ることは、まさに「重なるアクセス」の並行版だからです。

排他アクセスがシングルスレッド内の時間軸での重なりを禁止したのに対し、`Sendable` と actor の仕組みは複数スレッド間での重なりを禁止します。

- `actor` は内部状態への並行アクセスを直列化する。
- `@MainActor` はその実行をメインスレッドに固定する。
- `Sendable` 準拠は「タスク境界を越えて安全に渡せる」ことの型レベルの保証となる。

ZoomacIt では UI を扱うクラスの多くが `@MainActor` で修飾され、`HotkeyManager` のように Carbon コールバックから呼ばれるクラスは `@unchecked Sendable` を選び、内部で `DispatchQueue.main.async` してメインスレッドに戻すというパターンになっています。これは「並行版の排他的アクセス保証を、自分の責任で守ります」という宣言です。

排他アクセスとデータ競合は、別々の機能というより **同じ哲学を時間軸とスレッド軸の両方に適用したもの** と捉えるのが正確です。

---

## ZoomacIt における memory safety

ZoomacIt のコードベース全体を見渡すと、明示的な `Unsafe` の登場箇所は実はかなり限定されています。

- `HotkeyManager` の Carbon コールバック (上で見た例)
- ピクセルバッファや Core Graphics 連携の一部

これは **典型的な Swift アプリの姿** です。アプリケーションロジック (描画ロジックや状態モデル) は安全な世界で書き、OS との境界やパフォーマンスクリティカルな箇所だけ慎重に unsafe に踏み込む。`Unsafe` の出現箇所が少ないこと自体が、コードレビューの効率を高めるシグナルになっています。

逆に、もし新しいコードで `UnsafeMutablePointer` を使いたくなったときは、**まず本当に必要か立ち止まって考える** のが正しい振る舞いです。`Array` や `Data`、あるいは `withUnsafeBytes(of:)` のようなスコープ限定のヘルパーで代替できないかを先に検討します。

---

## ハンズオン (任意)

排他アクセスの違反を体験する最短コードは次の通りです。Xcode の Playground にコピーして、コンパイルエラーが実際に出ることを確認してみてください。

```swift
func mySwap(_ a: inout Int, _ b: inout Int) {
    let t = a; a = b; b = t
}

var x = 0
mySwap(&x, &x)        // error 1

struct Box {
    var a = 0
    var b = 0
    mutating func test() {
        mySwap(&a, &a) // error 2
        mySwap(&a, &b) // OK
    }
}
```

エラーメッセージは Swift コンパイラの世代によって表現が変わりますが、いずれも「同じメモリへの重複した書き込みアクセスは許されない」という趣旨が示されます。

---

## まとめ

- Swift の memory safety は「**安全側がデフォルト、危険は明示**」という哲学で設計されている。
- Swift 5 で導入された **排他的アクセス** は、同じメモリへの読み書きが時間的に重なることを禁止する規則。
- 典型的な違反例は `swap(&x, &x)` のような `inout` 引数の重複と、`mutating func` 内で `self` の同じプロパティを `inout` で渡すケース。
- どうしても安全保証を外したい場面のために `Unsafe*` 系 API が用意されている。Carbon など C 連携で使う。
- Rust の borrow checker と問題意識は同じだが、Swift は適用範囲を絞りエスケープハッチを許す **折衷型** の設計。
- Swift 6 の strict concurrency は、排他アクセス保証の **並行版** と捉えると理解しやすい。
- ZoomacIt では `HotkeyManager` の Carbon コールバックが unsafe API の典型例。アプリ全体では unsafe の出現箇所が極めて少ないことが安全設計の証となっている。

---

## 次に読む章

→ [30. Access Control](./30-access-control.md)
