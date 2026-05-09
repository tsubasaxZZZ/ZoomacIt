# 34. Carbon API と C 橋渡し

## この章で学ぶこと

ZoomacIt の心臓部に位置する `HotkeyManager` は、Swift 6 で書かれていながら、その内部では **Carbon** という Mac OS Classic 時代から続く C 言語ベースの古い API を呼び出しています。なぜ最新の Cocoa や CoreGraphics を使わず、敢えて Carbon を選択したのか。そして Swift から C API を呼ぶときに登場する `@convention(c)`、`UnsafeMutableRawPointer`、`Unmanaged<T>` といった見慣れない仕組みは何を意味するのか。

この章では次のことを学びます。

- Carbon フレームワークの歴史的位置付けと、現代でも残っている領域
- グローバルホットキー実装で Carbon を選ぶ実用的な理由 (`CGEventTap` との比較)
- `import Carbon.HIToolbox` で C API を Swift から扱う基本
- C 関数ポインタ互換のクロージャを作る `@convention(c)` 修飾
- 生ポインタ `UnsafeMutableRawPointer` を経由してコンテキストを受け渡すパターン
- Swift クラスインスタンスを安全にポインタへ変換する `Unmanaged<T>`
- `EventHotKeyID` のような C 構造体を Swift 側で初期化する方法
- Carbon API で確保したリソース (`EventHotKeyRef` など) の手動メモリ管理
- C コールバックが呼ばれるスレッドと、`DispatchQueue.main.async` でメインスレッドへ戻す定石

最後に `HotkeyManager.swift` の全 200 行を上から下まで読み解きます。Java から来た方には JNI (Java Native Interface) との対比 — JNI より遥かに簡潔ですが、概念は驚くほど似ています — も交えて解説します。

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:1-200

---

## Carbon とは何か — 歴史的経緯

Carbon は、Apple が 2001 年の Mac OS X 移行時に提供した「橋渡し」用の C ベース API 群です。それまで Mac OS Classic 上で動いていた C 言語のアプリケーションが、最小限の変更で新しい Mac OS X (Cocoa ベース) に移行できるよう用意されました。歴史的には、Mac OS Classic の Toolbox API (QuickDraw、Window Manager、Event Manager など) の流れを汲んでいます。

その後 Apple は段階的に Carbon を縮小しました。

| 時期 | 出来事 |
|------|--------|
| 2001 | Mac OS X 10.0 で Carbon 提供開始 |
| 2007 | 64bit 版 Carbon GUI API の打ち切りを Apple が宣言 |
| 2012 | OS X 10.8 で多くの Carbon API が "deprecated" マーク |
| 2019 | macOS Catalina (10.15) で 32bit アプリ完全廃止。これにより Carbon アプリの大半が動作しなくなる |
| 現在 | Carbon の "ほとんど" は廃止だが、**HIToolbox の一部 (キーボードフック、Apple Event 関連)** は今も現役で残っている |

つまり Carbon = 完全に死んでいる、ではありません。**ごく一部の API は、今も "公式に推奨されている代替がない" ため残されている** のです。その代表格が、本章の主役である `RegisterEventHotKey` です。

`Carbon.HIToolbox` モジュールは macOS 26 SDK にも含まれており、これは Apple が「将来も使える」と暗に保証しているサブセットだと理解してください。

---

## なぜ Carbon を使うのか — `CGEventTap` との比較

「グローバルホットキー」(アプリが非アクティブでも反応するキー入力) を macOS で実装する手段は、大きく分けて 2 つあります。

### 選択肢 1: `CGEventTap` (CoreGraphics)

`CGEventTap` は CoreGraphics が提供する低レベル API で、**システム全体のキーボード/マウスイベントを傍受** できます。一見こちらが「現代的な選択」に見えますが、実用上は深刻な問題を抱えています。

- **Accessibility 権限が必須**: ユーザーは「システム設定 > プライバシーとセキュリティ > アクセシビリティ」でアプリを明示的に許可する必要があります
- **権限がリビルド毎に無効化される**: 開発中、Xcode でビルドし直すたびに署名が変わったとみなされ、Accessibility 許可がリセットされます。毎回手動で再許可することになり、開発体験が極めて悪化します
- **過剰な権限**: ホットキー数個のために「全キー入力を傍受できる権限」をユーザーに求めるのは、プライバシー観点で過剰です

### 選択肢 2: Carbon `RegisterEventHotKey`

一方の Carbon `RegisterEventHotKey` は、**OS にホットキーの組み合わせを「登録」しておき、一致したときだけコールバックされる** モデルです。全イベントを傍受するわけではないので、Apple は権限を要求しません。

- **権限不要**: ユーザー操作なしで動作する
- **API が単純**: キーコード + 修飾子 + ID を渡すだけ
- **オーバーヘッドが小さい**: 登録された組み合わせ以外は OS 側でフィルタされる
- **現役の API**: deprecated されていない (2026 年現在)

ZoomacIt のリポジトリルート `CLAUDE.md` には、この設計判断が次のように明記されています。

```
Hotkeys: Carbon RegisterEventHotKey, NOT CGEventTap.
CGEventTap requires Accessibility permission which invalidates on every rebuild.
Default: ⌃1=Zoom, ⌃2=Draw, ⌃3=Break Timer.
```

> 引用元: CLAUDE.md (Critical Patterns セクション)

つまり ZoomacIt が古臭い C API を呼んでいるのは「枯れているから」ではなく、**現代のモダン API が抱える運用上の欠点を回避するための合理的選択** です。新しい = 良い、ではないことを示す好例と言えます。

---

## Swift から C API を呼ぶ基本

Swift コンパイラは Clang のモジュールマップ機能を通じて、C のヘッダをそのまま Swift モジュールとして取り込めます。Carbon の場合は次の 1 行だけです。

```swift
import Carbon.HIToolbox
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:2

`HIToolbox` は Carbon の中の Human Interface Toolbox サブモジュールで、イベント処理関連の API がここにまとまっています。`import` した瞬間に、次のような C の型と関数が Swift から直接見えるようになります。

| C の名前 | Swift での型 | 意味 |
|----------|--------------|------|
| `OSStatus` | `Int32` のエイリアス | 関数の成否を返すエラーコード |
| `OSType` | `UInt32` のエイリアス | 4 文字コード型 (FourCC) |
| `EventRef` | opaque pointer (`OpaquePointer?`) | イベントオブジェクトへの参照 |
| `EventHotKeyRef` | opaque pointer | 登録済みホットキーへの参照 |
| `EventHotKeyID` | C 構造体 | `signature` と `id` を持つ |
| `EventTypeSpec` | C 構造体 | イベントの種類を表す |
| `RegisterEventHotKey` | Swift 関数 | ホットキー登録 |
| `UnregisterEventHotKey` | Swift 関数 | ホットキー解除 |
| `InstallEventHandler` | Swift 関数 | イベントハンドラ登録 |
| `GetEventParameter` | Swift 関数 | イベントからパラメータ取得 |

Swift コンパイラは C のヘッダを読み、命名規則 (`enum CamelCase { case foo }` のようなマッピング) や型変換 (`int32_t` → `Int32`) を自動で行います。Java の JNI のように `JNIEXPORT` プロトタイプを別途書いたり、ヘッダを手で翻訳する必要は **一切ありません**。これは Swift の C 相互運用性の真骨頂です。

### 戻り値の `OSStatus` と `noErr`

Carbon API はほぼ全て `OSStatus` (= `Int32`) を返します。成功は `noErr` (= 0) です。Swift 側ではこのように扱います。

```swift
let status = InstallEventHandler(...)
guard status == noErr else {
    NSLog("[HotkeyManager] Failed: %d", status)
    return
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:48-60

これは典型的な C 流のエラー処理で、Swift の `throws` には変換されません。Carbon API は **古い C の慣習をそのまま** Swift に持ち込んでいると理解してください。

---

## `@convention(c)` クロージャ — C 関数ポインタの正体

### Swift クロージャと C 関数ポインタの違い

Swift のクロージャは、内部的に「関数ポインタ + キャプチャした変数」の組です。これを **コンテキスト付きクロージャ** と呼びます。一方、C の関数ポインタは「ただの関数アドレス」で、状態を持ちません。

両者は ABI (Application Binary Interface) が違うため、Swift のクロージャをそのまま C API に渡すことはできません。コンパイラエラーになります。

### `@convention(c)` 属性

Swift では `@convention(c)` 属性を付けることで、「この関数はキャプチャを持たず、C の関数ポインタ互換である」ことを宣言できます。

`HotkeyManager.swift` の末尾を見てください。

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

注目してほしいのは、これが **トップレベルの `private func`** として書かれていることです。クラスのメソッドではありません。これは意図的で、トップレベル関数 (= self をキャプチャしない) は自動的に `@convention(c)` 互換とみなされ、Carbon の `EventHandlerProcPtr` 型に渡せるからです。

`InstallEventHandler` の定義を Xcode で覗くと、第 2 引数は次のように宣言されています。

```swift
public typealias EventHandlerProcPtr = @convention(c) (
    EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?
) -> OSStatus
```

そして `HotkeyManager.start()` では、こう呼び出しています。

```swift
let status = InstallEventHandler(
    GetApplicationEventTarget(),
    hotKeyEventHandler,    // ← トップレベル関数をそのまま関数ポインタとして渡す
    1,
    &eventType,
    selfPtr,
    &eventHandlerRef
)
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:48-55

もし `hotKeyEventHandler` をクラスのメソッドにしたり、self をキャプチャするクロージャにしたりすると、コンパイラは「`@convention(c)` を要求する箇所に Swift クロージャは渡せない」という旨のエラーを出します。

### Java との対比 (JNI)

Java で C のコールバックを受けるときは、`JNIEnv*` と `jobject` を引数に取る関数を C 側で書き、`javah` で生成したヘッダに合わせて `JNICALL` 規約で実装します。Swift の `@convention(c)` は、概念的には JNI における `JNICALL` 修飾子に近い役割です。ただし JNI と違い、

- 別の C ファイルを書く必要がない
- ヘッダ生成ツールも不要
- Swift コードの中に直接書ける

という意味で、JNI より遥かに軽量です。

---

## `UnsafeMutableRawPointer` — 生ポインタで context を運ぶ

`@convention(c)` 関数は self を持てない、と書きました。ではどうやってコールバックの中から元のオブジェクト (ここでは `HotkeyManager` インスタンス) にアクセスするのでしょうか。

答えは **`void*` 型のユーザーデータ** を経由する、という C の伝統的な手法です。Swift ではこれを `UnsafeMutableRawPointer` (型情報を持たない生ポインタ) と表現します。

`InstallEventHandler` のシグネチャを見直すと、第 5 引数 `userData` がそれです。

```c
// C の元の宣言 (概念)
OSStatus InstallEventHandler(
    EventTargetRef          inTarget,
    EventHandlerProcPtr     inHandler,
    ItemCount               inNumTypes,
    const EventTypeSpec *   inList,
    void *                  inUserData,        // ← ここ
    EventHandlerRef *       outRef
);
```

ZoomacIt はここに `HotkeyManager` のインスタンスへのポインタを渡しています。

```swift
let selfPtr = Unmanaged.passUnretained(self).toOpaque()

let status = InstallEventHandler(
    GetApplicationEventTarget(),
    hotKeyEventHandler,
    1,
    &eventType,
    selfPtr,                    // ← self を生ポインタに変換して渡す
    &eventHandlerRef
)
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:46-55

Carbon は登録時に受け取った `userData` を、コールバック呼び出し時にそのまま第 3 引数として戻してくれます。コールバック側ではこれを Swift オブジェクトに復元します。

```swift
let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:196

これでトップレベル関数の中から `HotkeyManager` のメソッドが呼べるようになりました。

---

## `Unmanaged<T>` — Swift 参照型をポインタへ

`Unmanaged<T>` は Swift 標準ライブラリが提供する「ARC の管理外で参照を扱う」ためのラッパー型です。Swift クラスは通常 ARC (Automatic Reference Counting) によってメモリ管理されますが、生ポインタを経由して C API に渡してしまうと、ARC は「もう誰も参照していない」と判断して解放してしまう恐れがあります。

`Unmanaged` は、

- ARC の参照カウントを意図的に増やしたり (`passRetained`)
- ARC を一切触らずに「ただのアドレス」として渡したり (`passUnretained`)
- ポインタから参照を復元するときに、参照カウントを増やすか (`takeRetainedValue`) 増やさないか (`takeUnretainedValue`) を選ぶ

ことを可能にします。

### `passUnretained` + `takeUnretainedValue` の組

`HotkeyManager` は次の組み合わせを使っています。

| 渡すとき | 取り出すとき |
|----------|--------------|
| `Unmanaged.passUnretained(self).toOpaque()` | `Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()` |

両方とも `Unretained` 系を使うのは、**`HotkeyManager.shared` がシングルトンとして app プロセス全体で生存する** ことが分かっているからです。`HotkeyManager.shared` は次のように定義されています。

```swift
static let shared = HotkeyManager()
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:8

シングルトンは app 終了まで決して解放されません。だから ARC を増やす必要がありません。

もし `HotkeyManager` を一時的なオブジェクトとして作って渡すなら、`passRetained` (登録時に +1) + `takeRetainedValue` (解除時に -1) のペアで明示的に寿命を管理する必要があります。今回はその必要がないため、軽量な `Unretained` 系を選んでいます。

### `toOpaque` と `fromOpaque`

- `toOpaque() -> UnsafeMutableRawPointer`: `Unmanaged` を生ポインタに変換
- `fromOpaque(_ ptr) -> Unmanaged<T>`: 生ポインタから `Unmanaged` を復元

「`Opaque`」とは「型情報が見えない」という意味で、要するに C の `void*` 互換ということです。

### Java JNI との対比

JNI では `jobject` (= グローバル参照) を `NewGlobalRef` で作って C 側に保存し、`DeleteGlobalRef` で解放しました。Swift の `Unmanaged.passRetained` / `takeRetainedValue` は、これとほぼ同じ役割です。`passUnretained` は、JNI のローカル参照に近い軽量版だと考えてよいでしょう。

---

## C 構造体の初期化

Carbon API には `EventHotKeyID` や `EventTypeSpec` のような小さな C 構造体が頻出します。Swift から C 構造体を作るときは、**Swift がメンバ名付きの初期化子を自動生成してくれる** ので、極めて自然に書けます。

### `EventHotKeyID`

C ヘッダ上はこう定義されています。

```c
struct EventHotKeyID {
    OSType signature;
    UInt32 id;
};
```

Swift からはこう呼びます。

```swift
let zoomKeyID = EventHotKeyID(signature: hotKeySignature, id: zoomHotKeyID)
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:63

`signature` と `id` の 2 メンバを名前付き引数で渡すだけ。Swift コンパイラが C 構造体に対応する初期化子を自動生成してくれます。

### `EventTypeSpec`

```swift
var eventType = EventTypeSpec(
    eventClass: OSType(kEventClassKeyboard),
    eventKind: UInt32(kEventHotKeyPressed)
)
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:41-44

ここで `kEventClassKeyboard` は Carbon が定義する定数で、Swift では `Int` として import されます。`OSType` (= `UInt32`) に明示変換しているのは、Swift が暗黙の型変換を許さないためです。

### 4 文字コード (FourCC) の魔法

Carbon の世界では、識別子に **4 文字の ASCII コード (FourCC)** を使う伝統があります。`HotkeyManager` でも次のように定義されています。

```swift
private let hotKeySignature: OSType = 0x5A6D_4974 // 'ZmIt'
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:25

`0x5A6D_4974` は ASCII コードで `'Z' (0x5A) 'm' (0x6D) 'I' (0x49) 't' (0x74)`、つまり "ZmIt" を 32bit 整数として表したものです。アンダースコアは Swift の数値リテラル区切り (可読性向上) です。

C/Objective-C 時代は `'ZmIt'` のような **マルチキャラクタリテラル** を直接書けましたが、Swift にはこの構文がないため、**手動で 16 進数に変換** して書くのがイディオムになっています。

なぜわざわざ FourCC を使うかというと、Carbon のイベントシステム上で **「この HotKeyID はどのアプリ/モジュールが登録したか」を識別する** ためです。同じプロセス内で複数の Carbon クライアントが登録した HotKey を区別するために使われます。`signature` で「どのモジュールか」、`id` で「そのモジュール内の何番目か」を表す、と覚えておけば十分です。

---

## 手動メモリ管理 — Carbon リソースの解放

Swift クラスは ARC で自動解放されますが、**Carbon API が確保したリソースは手動で解放する必要があります**。これは Carbon が C ベースで、ARC とは無関係だからです。

`HotkeyManager` は次のリソースを保持しています。

```swift
private var hotKeyRef: EventHotKeyRef?
private var zoomHotKeyRef: EventHotKeyRef?
private var breakHotKeyRef: EventHotKeyRef?
private var eventHandlerRef: EventHandlerRef?
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:19-22

`EventHotKeyRef` も `EventHandlerRef` も実体は opaque pointer (Swift 上では `OpaquePointer?` のような型) です。これらは `RegisterEventHotKey` / `InstallEventHandler` で確保され、`stop()` メソッドで明示的に解放されます。

```swift
func stop() {
    if let ref = zoomHotKeyRef {
        UnregisterEventHotKey(ref)
        zoomHotKeyRef = nil
    }
    if let ref = hotKeyRef {
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }
    if let ref = breakHotKeyRef {
        UnregisterEventHotKey(ref)
        breakHotKeyRef = nil
    }
    if let handler = eventHandlerRef {
        RemoveEventHandler(handler)
        eventHandlerRef = nil
    }
    NSLog("[HotkeyManager] Hotkeys unregistered.")
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:125-143

このパターンはとても重要です。

1. `if let` で nil チェックしつつ unwrap
2. Carbon の解放 API を呼ぶ (`UnregisterEventHotKey`, `RemoveEventHandler`)
3. プロパティを `nil` に戻して二重解放を防ぐ

もしこの解放を忘れると、**ホットキーは登録されたまま残り、ユーザーが ⌃1 を押すたびに古い (もう存在しない) ハンドラが呼ばれて即クラッシュ** という事態になります。Carbon の世界では、Swift と違って「忘れたら勝手に綺麗になる」ことはありません。

### `deinit` を書かない理由

通常、リソース解放を `deinit` に書きたくなりますが、`HotkeyManager` はシングルトン (`static let shared`) なので、app 終了まで `deinit` が呼ばれません。代わりに、`reregisterHotkeys()` のように **設定変更時に明示的に stop → start で再登録する** スタイルを採用しています。

```swift
func reregisterHotkeys() {
    stop()
    start()
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:146-149

ユーザーが Settings 画面でホットキーの組み合わせを変えたとき、このメソッドが呼ばれます。

---

## スレッド境界 — C コールバックは未知のスレッドから来る

C で書かれたフレームワークの規約では、**コールバック関数がどのスレッドから呼ばれるかは保証されないことがあります**。Carbon のホットキーイベントは事実上メインスレッドから配送されるとされていますが、Swift 6 の strict concurrency モデルでは「事実上」では済みません。コンパイラが「main actor 以外から触られている可能性があるなら、UI 操作を許可しない」と判断します。

ZoomacIt の解決策は、

1. `HotkeyManager` を `@unchecked Sendable` にする
2. C コールバック内では UI を一切触らず、`DispatchQueue.main.async { [weak self] in ... }` で main thread に処理を渡す

の組み合わせです。

### `@unchecked Sendable`

```swift
final class HotkeyManager: @unchecked Sendable {
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:6

`@unchecked Sendable` は「コンパイラのチェックは無効にして、Sendable と扱ってよい」という宣言です。Swift 6 のコンパイラは、参照型 (class) が複数スレッドから触られる可能性があるとき、デフォルトでは `Sendable` 適合を許可しません。しかし `HotkeyManager` は **自分の責任でスレッド安全性を保証する** という意思表示として、この属性を使っています。

実際にはシングルトンとして単一インスタンスしか存在せず、内部状態 (`hotKeyRef` など) は `start()` / `stop()` のときだけ書き換わります。これらは UI イベント駆動でメインスレッドから呼ばれるため、競合は起きません。

### `DispatchQueue.main.async`

C コールバックから Swift 側に処理が戻ったあと、`handleHotKeyEvent` の中で必ずメインスレッドへディスパッチしています。

```swift
fileprivate func handleHotKeyEvent(_ event: EventRef) {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return }

    guard hotKeyID.signature == hotKeySignature else { return }

    if hotKeyID.id == zoomHotKeyID {
        DispatchQueue.main.async { [weak self] in
            self?.onZoomHotkey?()
        }
    } else if hotKeyID.id == drawHotKeyID {
        DispatchQueue.main.async { [weak self] in
            self?.onDrawHotkey?()
        }
    } else if hotKeyID.id == breakHotKeyID {
        DispatchQueue.main.async { [weak self] in
            self?.onBreakHotkey?()
        }
    }
}
```

> 引用元: src/ZoomacIt/Core/HotkeyManager.swift:153-182

`onZoomHotkey?()` などのクロージャは、最終的に `StatusBarController` などの `@MainActor` クラスのメソッドを呼び出すため、必ずメインスレッドである必要があります。`[weak self]` で循環参照も防いでいます。

これは「C と Swift のスレッドモデルの境界をどう扱うか」の **教科書的な定石** です。覚えておいてください。

---

## ZoomacIt 実コード読解 — `HotkeyManager` 全体ツアー

ここまで個別の概念を見てきました。最後に `HotkeyManager.swift` の全 200 行を、上から順に役割分担を意識しながら読み解きます。

### 行 1-6: import と class 宣言

```swift
import AppKit
import Carbon.HIToolbox

/// Manages global hotkeys using the Carbon RegisterEventHotKey API.
/// Does NOT require Accessibility permission.
final class HotkeyManager: @unchecked Sendable {
```

`AppKit` は `NSLog` のため、`Carbon.HIToolbox` は本章の主役 API のためにインポートしています。コメントに「Accessibility 権限不要」と明記されていることに注目してください。これは **設計判断のドキュメント化** であり、未来の自分や他人が「なぜ Carbon を使うのか」を理解する手助けになります。

### 行 8-17: シングルトンとコールバックプロパティ

```swift
static let shared = HotkeyManager()

/// Called when the Draw hotkey (⌃2) is triggered.
var onDrawHotkey: (() -> Void)?

/// Called when the Still Zoom hotkey (⌃1) is triggered.
var onZoomHotkey: (() -> Void)?

/// Called when the Break Timer hotkey (⌃3) is triggered.
var onBreakHotkey: (() -> Void)?
```

シングルトンと、3 つのオプショナルクロージャ。`AppDelegate` などの上位レイヤがこのクロージャに「キーが押されたら何をするか」を注入します。HotkeyManager 自身は **UI ロジックを一切持たず、純粋にイベント分配だけを担当** する設計です。

### 行 19-22: Carbon リソース保持

```swift
private var hotKeyRef: EventHotKeyRef?
private var zoomHotKeyRef: EventHotKeyRef?
private var breakHotKeyRef: EventHotKeyRef?
private var eventHandlerRef: EventHandlerRef?
```

Carbon が確保した opaque pointer を保持。手動解放のために `var` (mutable) にしてあります。

### 行 24-30: 識別子定数と private init

```swift
/// Signature used to identify our hot-key events ('ZmIt')
private let hotKeySignature: OSType = 0x5A6D_4974 // 'ZmIt'
private let zoomHotKeyID: UInt32 = 0
private let drawHotKeyID: UInt32 = 1
private let breakHotKeyID: UInt32 = 2

private init() {}
```

`hotKeySignature` は前述の FourCC。`id` は単なる連番で、Carbon イベント受信時にどのキーが押されたかを区別するために使います。`private init()` でシングルトン以外の生成を禁止しています。

### 行 34-60: `start()` の前半 (event handler のインストール)

```swift
func start() {
    guard hotKeyRef == nil else {
        NSLog("[HotkeyManager] Hot key already registered — skipping.")
        return
    }

    var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
    )

    let selfPtr = Unmanaged.passUnretained(self).toOpaque()

    let status = InstallEventHandler(
        GetApplicationEventTarget(),
        hotKeyEventHandler,
        1,
        &eventType,
        selfPtr,
        &eventHandlerRef
    )

    guard status == noErr else {
        NSLog("[HotkeyManager] Failed to install event handler: %d", status)
        return
    }
```

ここまでで本章の主要トピックが全て登場しています。

- `EventTypeSpec` という C 構造体を Swift で初期化
- `Unmanaged.passUnretained(self).toOpaque()` で self を生ポインタに変換
- `&eventType` / `&eventHandlerRef` で Swift 変数のアドレスを C に渡す (inout 引数)
- `hotKeyEventHandler` というトップレベル関数を C 関数ポインタとして渡す
- 戻り値 `OSStatus` を `noErr` と比較してエラーチェック

`GetApplicationEventTarget()` は「このアプリのイベントターゲット」を返す Carbon API で、これに対してハンドラをインストールすることで、アプリがフォーカスを持っていなくてもキーイベントを受け取れます。

### 行 62-122: `start()` の後半 (3 つのホットキー登録)

3 つのホットキー (Zoom, Draw, Break) を順番に登録します。Zoom 登録部分を抜き出します。

```swift
let zoomKeyID = EventHotKeyID(signature: hotKeySignature, id: zoomHotKeyID)
let zoomStatus = RegisterEventHotKey(
    Settings.shared.zoomHotkeyKeyCode,
    Settings.shared.zoomHotkeyModifiers,
    zoomKeyID,
    GetApplicationEventTarget(),
    0,
    &zoomHotKeyRef
)
```

`Settings.shared` から動的にキーコードと修飾子を取得しているのがポイントです。これにより、ユーザーが Settings 画面でホットキーを変更し、`reregisterHotkeys()` を呼べば即座に新しい設定で再登録されます。

`RegisterEventHotKey` の第 5 引数 `0` は flags で、現状予約済み (常に 0) です。最後の `&zoomHotKeyRef` で、確保された opaque pointer を Swift 側のプロパティに書き戻してもらいます。これがあとで `UnregisterEventHotKey` で解放するときの引数になります。

### 行 125-143: `stop()` (リソース解放)

前述の通り、確保した 4 つのリソースを順次解放。`if let` パターンで nil 安全に処理。

### 行 146-149: `reregisterHotkeys()` (再登録)

```swift
func reregisterHotkeys() {
    stop()
    start()
}
```

たった 2 行ですが、設定変更時の挙動を担保する重要なメソッドです。

### 行 153-182: `handleHotKeyEvent` (Swift 側ハンドラ)

C コールバックから呼ばれ、`EventRef` から `EventHotKeyID` を取り出して、どのホットキーが押されたかを判定し、対応するクロージャをメインスレッドで実行。`fileprivate` にしているのは、同じファイル内のトップレベル関数 `hotKeyEventHandler` から呼べるようにするためです。

`GetEventParameter` は Carbon イベントから任意のパラメータを取り出す汎用 API です。引数の意味は次の通り。

| 引数 | 意味 |
|------|------|
| `event` | 取り出し元のイベント |
| `UInt32(kEventParamDirectObject)` | 取り出すパラメータ名 (HotKey の場合は "Direct Object") |
| `UInt32(typeEventHotKeyID)` | 取り出す型 |
| `nil` | 実際の型 (out 引数、不要) |
| `MemoryLayout<EventHotKeyID>.size` | バッファサイズ |
| `nil` | 実際にコピーされたサイズ (out 引数、不要) |
| `&hotKeyID` | コピー先バッファのアドレス |

`MemoryLayout<T>.size` は **Swift から構造体のバイト数を取得する標準的な方法** です。C の `sizeof(EventHotKeyID)` に相当します。

### 行 187-200: `hotKeyEventHandler` (C コールバック本体)

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

最後にもう一度、本章の全エッセンスが詰まったこの 14 行を眺めてください。

1. **トップレベルの `private func`** だから `@convention(c)` 互換
2. 引数は全て C 由来の opaque pointer (`?` 付き optional)
3. `guard let` で nil チェック → 失敗時は `eventNotHandledErr` を返して Carbon に「処理しなかった」と伝える
4. `Unmanaged.fromOpaque` で `userData` を `HotkeyManager` インスタンスに復元
5. `takeUnretainedValue()` で参照カウントを増やさずに取り出す
6. Swift 側のメソッドへ処理を委譲
7. 成功は `noErr` を返す

C の世界と Swift の世界の **境界** が、この 14 行にぎゅっと凝縮されています。

---

## ハンズオン (任意)

理解を深めたい方は、次の課題に挑戦してみてください。

### 課題 1: 4 つ目のホットキーを追加する

`HotkeyManager` に「⌃4 を押すと NSLog が出る」だけの 4 つ目のホットキーを追加してください。手順:

1. `breakHotKeyRef` の隣に `private var debugHotKeyRef: EventHotKeyRef?` を追加
2. `debugHotKeyID: UInt32 = 3` を追加
3. `start()` の末尾に Break と同様の `RegisterEventHotKey` ブロックを追加
4. `stop()` に解放処理を追加
5. `handleHotKeyEvent` に `debugHotKeyID` の分岐を追加
6. `var onDebugHotkey: (() -> Void)?` を追加し、`AppDelegate` から `NSLog` するクロージャを注入

### 課題 2: ホットキーを `passRetained` に変えてみる

`Unmanaged.passUnretained` を `Unmanaged.passRetained` に変更し、`takeUnretainedValue` を `takeRetainedValue` に変更してみてください。実行して、何回ホットキーを押せばクラッシュするか観察してください (毎回参照カウントを 1 ずつ消費するので、いずれ 0 になり解放されます)。

このハンズオンは **`Retained` / `Unretained` の意味を体感する** ためのものです。本番コードでは絶対にこの変更を残さないでください。

### 課題 3: `@convention(c)` を外してみる

`hotKeyEventHandler` をクラスのメソッドに移動するか、self をキャプチャするローカルクロージャに変えてみてください。コンパイラがどのようなエラーを出すか観察し、Swift の C 相互運用の制約を体感してください。

---

## 章のまとめ

- **Carbon は完全に死んでいない**: HIToolbox の一部 (キーボードフックなど) は今も現役
- **Carbon `RegisterEventHotKey` を選ぶ理由**: `CGEventTap` が要求する Accessibility 権限を回避できるから。リビルド毎の権限失効という開発体験の悪化も避けられる
- **`import Carbon.HIToolbox` で C API がそのまま見える**: Swift の C 相互運用性は JNI より遥かに簡潔
- **`@convention(c)`** はトップレベル関数 (= キャプチャを持たない関数) に自動付与される。クラスメソッドや self キャプチャクロージャは C 関数ポインタになれない
- **`UnsafeMutableRawPointer`** は C の `void*` 互換。`InstallEventHandler` の `userData` 引数経由でコンテキストを運ぶ
- **`Unmanaged<T>`**: `passUnretained.toOpaque()` で参照を生ポインタへ、`fromOpaque.takeUnretainedValue()` で復元。シングルトンには `Unretained` 系で十分
- **C 構造体は名前付き引数で初期化**: `EventHotKeyID(signature:id:)` のように Swift 流の自然な構文
- **FourCC**: `0x5A6D_4974 // 'ZmIt'` のように 16 進数で書くのが Swift のイディオム
- **手動メモリ管理**: `RegisterEventHotKey` / `InstallEventHandler` で確保したリソースは `UnregisterEventHotKey` / `RemoveEventHandler` で明示解放。ARC は介入しない
- **スレッド境界**: C コールバックは `@unchecked Sendable` クラスで受け、`DispatchQueue.main.async { [weak self] in ... }` でメインスレッドへ。これが Swift 6 strict concurrency 下での定石

これらは Carbon に限らず、**Swift から任意の C ライブラリを呼ぶときに繰り返し登場するパターン** です。`libxml2`、SQLite C API、自作 C ライブラリ、何にでも応用できます。Java の JNI を経験した方であれば、Swift の C 相互運用が「JNI で苦しんだあらゆることを、ヘッダ翻訳もブリッジファイルもなしに、Swift コード内に直接書ける」優雅さに気付くはずです。

## 次に読む章

→ [35. ScreenCaptureKit と async/await](./35-screencapturekit.md)
