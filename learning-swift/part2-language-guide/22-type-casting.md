# 22. Type Casting

## この章で学ぶこと

- 実行時に値の型を **検査** する `is` 演算子 (Java の `instanceof` 相当)
- 安全に型を **変換** する `as?` (条件付きダウンキャスト)、危険な `as!` (強制ダウンキャスト)、明示的なアップキャスト/ブリッジの `as`
- 任意の型を保持する **`Any`** と、クラス専用の **`AnyObject`** という二つの存在型 (existential type)
- `switch` の `case let x as T:` パターンでキャストと分岐を一度に書く方法
- ZoomacIt の `NSApplication.shared.delegate as? AppDelegate` という典型的な AppKit パターン

> **NOTE**
> この章は **チートシート章** です。Java の `instanceof` + キャスト構文をすでに知っていれば、ほぼそのままの感覚で読めます。違いは「キャスト失敗時の挙動が文法レベルで分かれている」点に集約されます。Java では `(SomeType) obj` がいつでも `ClassCastException` を投げる可能性を持つ一方、Swift では **安全な `as?` (失敗 = `nil`)** と **クラッシュ前提の `as!`** を構文で使い分け、危険性が型シグネチャから読めるようになっています。

---

## 22.1 演算子 3 種一覧

Swift の型キャスト演算子は次の 3 つだけです。意味と Java 対応を表で整理します。

| 演算子 | 意味 | 戻り値の型 | 失敗時 | Java 相当 |
|--------|------|-----------|--------|-----------|
| `is` | 型検査 (継承関係を含む) | `Bool` | `false` を返す | `obj instanceof SomeType` |
| `as?` | 条件付きダウンキャスト | `T?` (Optional) | `nil` を返す | `instanceof` + キャスト + null |
| `as!` | 強制ダウンキャスト | `T` (非 Optional) | **実行時クラッシュ** | `(SomeType) obj` (例外送出版) |
| `as`  | アップキャスト/ブリッジ | `T` (非 Optional) | コンパイルエラー (実行時に失敗しない) | 暗黙のアップキャスト |

`as?` と `as!` の関係は、Optional の `?` と `!` の関係 (Ch04) と同じ思想です。`?` は **失敗を `nil` で表現する安全な版**、`!` は **失敗を考えないクラッシュ版** です。Swift では原則として `as?` を使い、`as!` は「失敗があり得ないことを文法で証明できないが、論理的にあり得ないと確信している」場面に限るのが慣習です。

---

## 22.2 `is` — 型検査

`is` は値が指定した型 (またはそのサブクラス) かどうかを `Bool` で返します。継承関係をたどって判定する点も Java と同じです。

```swift
class Animal {}
class Dog: Animal {}
class Cat: Animal {}

let pets: [Animal] = [Dog(), Cat(), Dog()]

var dogCount = 0
for pet in pets {
    if pet is Dog {
        dogCount += 1
    }
}
print(dogCount)  // 2
```

`is` は **検査だけ** をして値そのものは取り出さないため、続けて使うには別途キャストが必要になります。実用上は次節の `as?` + `if let` パターンを使うほうが多く、`is` 単独で書くのは「件数を数えるだけ」「型を判定してログを出すだけ」のような場面が中心です。

---

## 22.3 `as?` — 条件付きダウンキャスト (基本形)

ダウンキャストは Swift プログラミングで最も頻出する型キャストです。`as?` は **失敗時に `nil` を返す Optional 版** で、必ず `if let` または `guard let` と組み合わせて使います。

```swift
class Animal {
    let name: String
    init(name: String) { self.name = name }
}
class Dog: Animal {
    func bark() { print("\(name): Woof!") }
}

let animal: Animal = Dog(name: "Rex")

if let dog = animal as? Dog {
    dog.bark()  // "Rex: Woof!"
} else {
    print("not a dog")
}
```

`animal` の静的な型は `Animal` ですが、実際のインスタンスは `Dog` です。`as? Dog` は実行時に型をチェックし、`Dog` ならその型として、違えば `nil` を返します。

### Java との対比

```java
// Java
Animal animal = new Dog("Rex");
if (animal instanceof Dog dog) {  // Java 16+ パターンマッチング
    dog.bark();
}
```

```swift
// Swift
let animal: Animal = Dog(name: "Rex")
if let dog = animal as? Dog {
    dog.bark()
}
```

意味はほぼ同じですが、Swift では **`as?` の戻り値が Optional** という型でモデル化されているのがポイントです。`if let` で取り出すという流れも Optional 全般と同じため、構文が統一されている分覚えやすくなっています。

---

## 22.4 `as!` — 強制ダウンキャスト (避ける文化)

`as!` はキャスト先の型を **非 Optional** で受け取ります。失敗するとプログラムがクラッシュします。

```swift
let animal: Animal = Dog(name: "Rex")

let dog = animal as! Dog   // 成功: dog は Dog
dog.bark()

let cat: Animal = Cat()
let dog2 = cat as! Dog     // 実行時クラッシュ: "Could not cast value of type 'Cat' to 'Dog'"
```

Swift コミュニティでは **`as!` は基本的に避ける** のが文化です。`as?` で受けて `if let` するか、`guard let ... else { fatalError(...) }` で意図を明示するほうが、失敗時のメッセージも追跡もしやすくなります。

```swift
// 推奨パターン
guard let dog = animal as? Dog else {
    fatalError("animal must be Dog at this point")
}
dog.bark()
```

`as!` を書きたくなったら、ほぼ常に `as?` + `guard let` で書き換えられます。コードレビューで `as!` は要注意マーカーになる、と覚えておけば十分です。

---

## 22.5 `as` — アップキャストとブリッジ

`as` (`?` も `!` も付けない形) は **コンパイル時に成功が保証されている変換** だけに使えます。実行時には絶対に失敗しないので Optional にもなりません。

### サブクラスからスーパークラスへ

```swift
let dog = Dog(name: "Rex")
let animal = dog as Animal   // 必ず成功: Dog は Animal のサブクラス
```

`as Animal` は省略可能 (`let animal: Animal = dog` でも OK) ですが、ジェネリクスや配列リテラルで型を明示したいときに役立ちます。

```swift
let mixed = [Dog(name: "Rex") as Animal, Cat() as Animal]
// 配列の要素型を [Animal] に確定させる
```

### Foundation 型ブリッジ

`as` は Swift のネイティブ型と Foundation 型の **ブリッジ** にも使われます。

```swift
let swiftString: String = "hello"
let nsString = swiftString as NSString
let length: Int = nsString.length          // NSString のメソッドが使える

let nsArray: NSArray = ["a", "b", "c"]
let swiftArray = nsArray as? [String] ?? []  // 要素型が確定しないため as? が必要
```

`String` ↔ `NSString`、`Array` ↔ `NSArray`、`Dictionary` ↔ `NSDictionary`、`Number` 系の相互変換が代表例です。同じ概念を表す型同士の変換は `as` で書けますが、要素型が落ちる `NSArray` から `[String]` のような **要素型を取り戻す** 変換は実行時検査が必要なので `as?` を使います。

---

## 22.6 `Any` と `AnyObject`

「型が事前に決まらない値」を扱うとき、Swift には 2 つの存在型があります。

| 型 | 入れられるもの | Java 相当 |
|----|--------------|-----------|
| `Any` | **任意** の型 (struct / enum / class / 関数 / Optional すべて) | `Object` (プリミティブ含む boxed) |
| `AnyObject` | **クラス** インスタンスのみ | `Object` (参照型限定) |

```swift
var things: [Any] = []
things.append(0)
things.append(0.0)
things.append("hello")
things.append((3.0, 5.0))            // タプル
things.append({ (name: String) in "Hi, \(name)" })  // クロージャ
```

`Any` は本当に何でも入りますが、入れたが最後 **元の型情報は静的には失われる** ため、取り出すときには必ず `as?` でダウンキャストすることになります。

```swift
for thing in things {
    if let str = thing as? String {
        print("String: \(str)")
    } else if let num = thing as? Int {
        print("Int: \(num)")
    }
}
```

### `[String: Any]` という典型例

Foundation の `userInfo` や JSON デシリアライズ結果は `[String: Any]` (= `[String: Any]?`) の形で渡されることが多く、Swift で AppKit / Foundation を扱う以上は必ず触れる型です。

```swift
func handle(notification userInfo: [AnyHashable: Any]?) {
    guard let info = userInfo,
          let count = info["count"] as? Int,
          let title = info["title"] as? String else {
        return
    }
    print("\(title): \(count)")
}
```

`as?` で各値を本来の型に戻すのが定石です。Java の `Map<String, Object>` から `(Integer) map.get("count")` でキャストするのと同じ感覚で、ただし安全側 (失敗 = `nil`) に倒されています。

---

## 22.7 `switch` でのパターンマッチ型キャスト

`switch` の `case` には `let x as T` というパターンが書けます。型ごとに分岐しつつ、その場で **型変換と束縛** を同時に済ませられる、Swift らしい書き方です。

```swift
let things: [Any] = [0, 3.14, "Swift", Dog(name: "Rex")]

for thing in things {
    switch thing {
    case let n as Int:
        print("Int: \(n)")
    case let d as Double:
        print("Double: \(d)")
    case let s as String:
        print("String: \(s)")
    case let dog as Dog:
        dog.bark()
    default:
        print("unknown")
    }
}
```

`case let n as Int:` は **「`thing` を `Int` にダウンキャストできたら、その値を `n` に束縛する」** という意味です。`if let n = thing as? Int` を `switch` の case 一行で書いたものと考えてください。型の分岐が 3 つ以上ある場合は `if let` の連鎖よりこちらのほうが読みやすくなります。

`where` 句と組み合わせて条件を絞ることもできます。

```swift
switch thing {
case let n as Int where n > 0:
    print("positive Int: \(n)")
case let n as Int:
    print("non-positive Int: \(n)")
default:
    break
}
```

---

## 22.8 ZoomacIt 実コードでの登場箇所

ZoomacIt は素直な AppKit アプリで型階層が浅いため、ダウンキャストの登場頻度は高くありません。とはいえ AppKit 由来の **「Any を返す API から本来の型を取り戻す」** パターンは何箇所かに現れます。

### `NSApplication.shared.delegate as? AppDelegate`

`NSApplication.delegate` は `(any NSApplicationDelegate)?` 型です。具象型の `AppDelegate` のメソッドを呼ぶには `as?` でダウンキャストする必要があります。

```swift
if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
    appDelegate.breakTimerDidEnd()
}
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:78-80
> (同様のパターンが OverlayWindowController.swift:63-65 にもあります)

`if let` で安全に取り出してから具象メソッド (`breakTimerDidEnd()`) を呼ぶ、教科書通りの形です。`as!` を使えば `?` を省けますが、テスト用の差し替えで delegate が別実装になるケースを考えると **`as?` のほうが安全側** で、ZoomacIt でも一貫してこのスタイルが採られています。

### `deviceDescription[...] as? CGDirectDisplayID`

`NSScreen.deviceDescription` は `[NSDeviceDescriptionKey: Any]` を返します。中の値は実装依存なので、欲しい型に `as?` で取り戻す必要があります。

```swift
let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
    as? CGDirectDisplayID ?? CGMainDisplayID()
```

> 引用元: src/ZoomacIt/Overlay/BreakTimerWindowController.swift:44

`as?` で取り出して、失敗したら `??` でデフォルト値 (`CGMainDisplayID()`) にフォールバックする組み合わせは、Foundation/AppKit を扱うときの定型パターンです。

ZoomacIt 全体で `as!` は使われていません。これが Swift コミュニティの標準的な姿勢であり、新規コードを書くときも踏襲してよい指針です。

---

## 22.9 まとめ

| 場面 | 演算子 | 例 |
|------|--------|-----|
| 型かどうかを `Bool` で判定したい | `is` | `obj is NSView` |
| **本命**: 型を変換して使いたい | `as?` + `if let` | `if let v = obj as? NSView { ... }` |
| 失敗があり得ないと確信している (非推奨) | `as!` | `let v = obj as! NSView` |
| 上位型として扱いたい / Foundation 型へ橋渡し | `as` | `dog as Animal` / `str as NSString` |
| 任意の型を保持したい | `Any` / `AnyObject` | `var things: [Any] = []` |
| 型ごとに分岐しつつ束縛したい | `case let x as T` | `switch obj { case let v as NSView: ... }` |

押さえておきたい原則は次の 3 つです。

1. **`as?` を第一選択にする**。`as!` は基本書かない。書きたくなったら `guard let ... else { fatalError(...) }` に置き換えられないか考える。
2. **`Any` を見たら `as?` で開ける**。`[String: Any]` や `userInfo` のような Foundation の型は、必ず本来の型に戻してから使う。
3. **3 つ以上の型分岐は `switch case let x as T:`**。`if let` の連鎖より読みやすくなる。

Java の `instanceof` を知っていれば違和感なく書ける一方で、「失敗時の挙動が型シグネチャから読める」という Swift の設計思想がよく現れる領域でもあります。

---

## 次に読む章

→ [23. Nested Types](./23-nested-types.md)

次章では **型の中に型を定義する** Nested Types を扱います。Java の static nested class とほぼ同じ概念ですが、Swift では struct / enum / class すべてを自由にネストでき、関連の強い型をまとめて表現する手段としてより積極的に使われます。
