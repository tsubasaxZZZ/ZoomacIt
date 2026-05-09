# 23. Nested Types

## この章で学ぶこと

Swift では、class / struct / enum の内部に別の型を定義できます。これを **nested type (ネスト型)** と呼びます。本章では基本構文、Java の inner class との違い、典型的な用途、そして ZoomacIt で実際に使われているパターンを学びます。

この章は短めのチートシート章です。Java 経験者であれば、概念は数分で把握できるでしょう。重要なのは「Swift の nested type は常に static nested 相当である」という 1 点だけです。

---

## 基本構文

任意の型 (class / struct / enum) の宣言ブロックの内側に、別の型を宣言できます。ネストは何段でも可能です。

```swift
struct Outer {
    struct Inner {
        var value: Int
    }

    enum Status {
        case active, inactive
    }
}

enum Network {
    enum Protocol {
        case http, https, ws
    }

    struct Endpoint {
        let url: String
        let proto: Protocol
    }
}
```

### アクセス方法

外側の型を名前空間として、ドット記法で参照します。

```swift
let inner = Outer.Inner(value: 42)
let status: Outer.Status = .active

let endpoint = Network.Endpoint(url: "https://example.com", proto: .https)
```

外側型の内部からは、外側型名を省略して直接 `Inner` や `Status` と書けます。

```swift
struct Outer {
    enum Status { case active, inactive }

    func defaultStatus() -> Status {  // Outer.Status と書かなくてよい
        return .active
    }
}
```

---

## Java の inner class との違い

Java を経験した方は、nested class と inner class の区別 (静的か非静的か、外側 `this` を保持するか) に馴染みがあるはずです。**Swift にはこの区別がありません。** Swift の nested type は **常に static nested 相当** であり、外側のインスタンスへの暗黙の参照を一切持ちません。

| 観点 | Java non-static inner class | Java static nested class | Swift nested type |
|------|----------------------------|--------------------------|-------------------|
| 外側 `this` への参照 | 持つ | 持たない | **持たない** (常に) |
| 外側インスタンスなしで生成可能 | 不可 | 可 | **可** |
| 外側のインスタンスメンバーへ直接アクセス | 可 | 不可 | **不可** |

Swift の nested type は単に「外側型のスコープに名前が属しているだけ」と理解してください。Java の `Outer.Inner inner = outer.new Inner()` のような構文は存在しません。

```swift
class Outer {
    var instanceValue = 10

    class Inner {
        // self.instanceValue にはアクセス不可。
        // Outer のインスタンスを明示的に渡さない限り、
        // 外側のインスタンス状態は見えない。
    }
}

let inner = Outer.Inner()  // Outer のインスタンスは不要
```

このシンプルさが Swift の方針です。外側の状態が必要なら、コンストラクタで明示的に注入します。

---

## 典型的な用途

### 1. 設定キーの名前空間化

最も頻出するパターンです。文字列定数群を `enum` でまとめ、外側型のスコープに閉じ込めます。`enum` を使うのは「インスタンス化させない」意図を明示するためで、case を持たない `enum` は事実上の名前空間となります。

```swift
final class Settings {
    enum Keys {
        static let userName = "userName"
        static let theme = "theme"
    }

    func loadUserName() -> String? {
        UserDefaults.standard.string(forKey: Keys.userName)
    }
}
```

### 2. エラー型を関連する型の中に定義

特定の型からのみ送出されるエラーは、その型の内部に定義すると関連性が明確になります。

```swift
struct DataLoader {
    enum Error: Swift.Error {
        case notFound
        case decodingFailed
        case networkUnavailable
    }

    func load(id: String) throws -> Data {
        throw Error.notFound
    }
}

// 利用側
do {
    _ = try DataLoader().load(id: "x")
} catch DataLoader.Error.notFound {
    print("見つかりません")
}
```

`Swift.Error` と書いているのは、内側の `Error` と Swift 標準の `Error` プロトコルの名前衝突を回避するためです。

### 3. 状態管理

特定のクラスでのみ使われる状態列挙は、そのクラスの中に置きます。

```swift
final class Downloader {
    enum State {
        case idle
        case loading(progress: Double)
        case success(Data)
        case failure(Error)
    }

    var state: State = .idle
}
```

---

## アクセス制御との組み合わせ

nested type にもアクセス修飾子を付けられます。`private` を組み合わせれば、外部からは存在すら見えない補助型を作れます。

```swift
final class Cache {
    private enum InternalKey {
        static let prefix = "cache."
    }

    private struct Entry {
        let key: String
        let value: Data
    }

    func store(_ data: Data, for id: String) {
        let entry = Entry(key: InternalKey.prefix + id, value: data)
        // ...
    }
}

// Cache.Entry や Cache.InternalKey は外部から参照不可
```

API 表面を最小限に保ちつつ、関連する型を 1 ファイルに整理できます。

---

## ZoomacIt 実コード読解

### Settings の `enum Keys` (UserDefaults キーの名前空間化)

ZoomacIt の `Settings` シングルトンは UserDefaults を裏側に持ちます。文字列キーを直接散らすとタイポ事故が発生するため、すべてのキーを nested `enum Keys` に集約しています。

```swift
final class Settings: @unchecked Sendable {

    static let shared = Settings()

    // ...

    enum Keys {
        // Hotkeys
        static let zoomHotkeyKeyCode = "hotkeyZoomKeyCode"
        static let zoomHotkeyModifiers = "hotkeyZoomModifiers"
        static let drawHotkeyKeyCode = "hotkeyDrawKeyCode"
        // ...

        // Draw
        static let defaultPenColor = "drawDefaultPenColor"
        static let defaultPenWidth = "drawDefaultPenWidth"
        // ...
    }
}
```

> 引用元: src/ZoomacIt/Models/Settings.swift:47-91

利用側ではこう書きます。

```swift
defaults.set(Double(newValue), forKey: Settings.Keys.defaultPenWidth)
```

`Settings.Keys.defaultPenWidth` という記述により、(1) この定数は Settings 関連であること、(2) Keys というカテゴリの定数であること、(3) 具体的に何のキーかが、一目で読み取れます。case を持たない `enum` を使っているのは、誰かが誤って `Keys()` のようにインスタンス化しようとした際に **コンパイルエラーで防ぐ** ためです (詳細は 8 章 Enumerations 参照)。

### DrawingState の `enum BackgroundMode` (状態の列挙)

`DrawingState` は描画中の状態を保持するクラスです。背景モード (透明 / ホワイトボード / ブラックボード) は `DrawingState` 固有の概念なので、内部に nested enum として定義しています。

```swift
final class DrawingState {

    // ...

    // MARK: - Background Mode

    enum BackgroundMode {
        case transparent  // draw on transparent canvas
        case whiteboard
        case blackboard
    }
    var backgroundMode: BackgroundMode = .transparent
}
```

> 引用元: src/ZoomacIt/Models/DrawingState.swift:33-57

外部からは `DrawingState.BackgroundMode.whiteboard` という形で参照されます。型名そのものが「これは DrawingState の背景モードである」という文書として機能します。仮にトップレベルに `enum BackgroundMode` を置くと、他の文脈の背景モード (例えばタイマーの背景) と名前が衝突する恐れがありますが、nested 化することで衝突は構造的に回避されます。

---

## ハンズオン (任意)

`Settings.swift` を眺めながら、以下を試してみてください。

1. `Settings.Keys.defaultPenColor` を Xcode で **option クリック** し、Quick Help の所属が `Settings.Keys` と表示されることを確認する
2. `DrawingState.BackgroundMode` に新しい case (`.gridPaper` など) を追加し、`backgroundMode` プロパティの初期値を変更してビルドが通ることを確認する
3. 自分のプロジェクトで、トップレベルに散らばっている定数群を関連クラスの内部に nested `enum Keys` として集約してみる

---

## まとめ

- Swift の nested type は **外側型のスコープに名前が属するだけ** で、外側インスタンスへの参照は持たない
- Java の inner class / static nested class の区別は Swift には存在しない (常に static nested 相当)
- 主な用途は **名前空間化** (`enum Keys`)、**関連エラー型の定義** (`enum Error`)、**状態列挙** (`enum State`) の 3 つ
- `private` と組み合わせて、外部から見えない補助型を作れる
- API 表面を狭く保ちつつ、関連する型を構造的に整理する強力な道具

## 次に読む章

→ [24. Extensions](./24-extensions.md)
