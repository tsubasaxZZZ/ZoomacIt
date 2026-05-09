# Ch40 解答例: 新しいホットキーアクション

[ハンズオン本文](../../part4-handson/40-add-hotkey.md) の解答例です。

このハンズオンは ZoomacIt の 5 階層アーキテクチャのうち **App / Core / Models** の 3 つを横断します。変更ファイルは 3 つです。

| ファイル | 役割 | 変更内容 |
|----------|------|----------|
| `src/ZoomacIt/Models/Settings.swift` | UserDefaults 永続化 | キー定義 + 既定値 + computed property を追加 |
| `src/ZoomacIt/Core/HotkeyManager.swift` | グローバルホットキー登録 | クロージャプロパティ + 登録/解除/分岐を追加 |
| `src/ZoomacIt/App/AppDelegate.swift` | ライフサイクル + ハンドラ | クロージャ接続 + `takeScreenshot()` 実装 |

順番に diff で変更を確認してから、各変更の意図を解説します。

---

## Step 1-3: Settings.swift の拡張

### 1. Keys 列挙体 (line 60-66 付近)

```diff
     enum Keys {
         // Hotkeys
         static let zoomHotkeyKeyCode = "hotkeyZoomKeyCode"
         static let zoomHotkeyModifiers = "hotkeyZoomModifiers"
         static let drawHotkeyKeyCode = "hotkeyDrawKeyCode"
         static let drawHotkeyModifiers = "hotkeyDrawModifiers"
         static let breakHotkeyKeyCode = "hotkeyBreakKeyCode"
         static let breakHotkeyModifiers = "hotkeyBreakModifiers"
+        static let screenshotHotkeyKeyCode = "hotkeyScreenshotKeyCode"
+        static let screenshotHotkeyModifiers = "hotkeyScreenshotModifiers"
```

**ポイント**: `UserDefaults` のキー名は **将来も変更しない** ことを前提に決めます。一度リリースするとユーザーの環境に保存された値の検索キーになるため、後から名前を変えると過去の設定が失われます。命名は既存の `hotkey<機能名><Field>` 規約に従いました。

### 2. 既定値の登録 (line 96-103 付近)

```diff
     func registerDefaults() {
         defaults.register(defaults: [
             // Hotkeys
             Keys.zoomHotkeyKeyCode: Int(kVK_ANSI_1),
             Keys.zoomHotkeyModifiers: Int(controlKey),
             Keys.drawHotkeyKeyCode: Int(kVK_ANSI_2),
             Keys.drawHotkeyModifiers: Int(controlKey),
             Keys.breakHotkeyKeyCode: Int(kVK_ANSI_3),
             Keys.breakHotkeyModifiers: Int(controlKey),
+            Keys.screenshotHotkeyKeyCode: Int(kVK_ANSI_4),
+            Keys.screenshotHotkeyModifiers: Int(controlKey),
```

**ポイント**: `kVK_ANSI_4` は Carbon が定義する仮想キーコードで、値は `21` です。`controlKey` は Carbon の修飾子マスクで、値は `4096`。生の数値リテラル `21` や `4096` を書くのではなく、必ず**定数経由**で書くこと。意図が読み取れますし、将来 Apple が SDK で値を変更したときも追従できます。

### 3. Computed Property (line 152-160 の直後)

```diff
     var breakHotkeyModifiers: UInt32 {
         get { UInt32(defaults.integer(forKey: Keys.breakHotkeyModifiers)) }
         set { defaults.set(Int(newValue), forKey: Keys.breakHotkeyModifiers) }
     }

+    var screenshotHotkeyKeyCode: UInt32 {
+        get { UInt32(defaults.integer(forKey: Keys.screenshotHotkeyKeyCode)) }
+        set { defaults.set(Int(newValue), forKey: Keys.screenshotHotkeyKeyCode) }
+    }
+
+    var screenshotHotkeyModifiers: UInt32 {
+        get { UInt32(defaults.integer(forKey: Keys.screenshotHotkeyModifiers)) }
+        set { defaults.set(Int(newValue), forKey: Keys.screenshotHotkeyModifiers) }
+    }
+
     // MARK: - Draw
```

**ポイント**: 既存の Zoom/Draw/Break と完全に同じパターンです。`UInt32` ↔ `Int` の変換は、`UserDefaults.integer(forKey:)` が `Int` を返すために必要です。`Carbon` API は `UInt32` 前提なのでアプリ側は `UInt32` で扱い、永続化レイヤーで `Int` にダウンキャストするという責務分離になっています。

### (任意) resetToDefaults

ハンズオン本文には書きませんでしたが、`resetToDefaults()` の `allKeys` 配列にも 2 つのキーを足すと完全です。

```diff
         let allKeys: [String] = [
             Keys.zoomHotkeyKeyCode, Keys.zoomHotkeyModifiers,
             Keys.drawHotkeyKeyCode, Keys.drawHotkeyModifiers,
             Keys.breakHotkeyKeyCode, Keys.breakHotkeyModifiers,
+            Keys.screenshotHotkeyKeyCode, Keys.screenshotHotkeyModifiers,
             Keys.defaultPenColor, Keys.defaultPenWidth,
```

ここを忘れると「設定リセット」を押しても screenshot 関連キーだけがリセットされません。学習目的としては気づければ十分です。

---

## Step 4-8: HotkeyManager.swift の拡張

### 1. クロージャプロパティを追加 (line 17 の直後)

```diff
     /// Called when the Break Timer hotkey (⌃3) is triggered.
     var onBreakHotkey: (() -> Void)?

+    /// Called when the Screenshot hotkey (⌃4) is triggered.
+    var onScreenshotHotkey: (() -> Void)?
+
     private var hotKeyRef: EventHotKeyRef?
```

**ポイント**: クロージャプロパティは**自動的に `@escaping`** です (オプショナル関数型は格納されるので)。明示的に `@escaping` を書く必要はありません。Ch10 で学んだとおり、クロージャを格納する型は逃避クロージャです。

### 2. 保管プロパティと ID (line 21-28 付近)

```diff
     private var hotKeyRef: EventHotKeyRef?
     private var zoomHotKeyRef: EventHotKeyRef?
     private var breakHotKeyRef: EventHotKeyRef?
+    private var screenshotHotKeyRef: EventHotKeyRef?
     private var eventHandlerRef: EventHandlerRef?

     /// Signature used to identify our hot-key events ('ZmIt')
     private let hotKeySignature: OSType = 0x5A6D_4974 // 'ZmIt'
     private let zoomHotKeyID: UInt32 = 0
     private let drawHotKeyID: UInt32 = 1
     private let breakHotKeyID: UInt32 = 2
+    private let screenshotHotKeyID: UInt32 = 3
```

**ポイント**: `EventHotKeyRef` は **C 言語のポインタを持つ不透明型**です (`OpaquePointer`)。Swift の値型ではなく**手動で開放しなければならない** リソースであることを意識してください (Ch34 で学んだとおり)。`stop()` で必ず `UnregisterEventHotKey` を呼ぶ必要があります。

`screenshotHotKeyID = 3` は他と被らない値であれば何でも構いません。ハンドラ側 (`handleHotKeyEvent`) が `hotKeyID.id` でディスパッチするためのタグです。

### 3. start() で 4 つ目の RegisterEventHotKey (line 122 の直後)

```diff
         NSLog("[HotkeyManager] Break hotkey registered: %@",
               Settings.hotkeyDisplayString(keyCode: Settings.shared.breakHotkeyKeyCode,
                                            modifiers: Settings.shared.breakHotkeyModifiers))
+
+        // Register Screenshot hotkey
+        let screenshotKeyID = EventHotKeyID(signature: hotKeySignature, id: screenshotHotKeyID)
+        let screenshotStatus = RegisterEventHotKey(
+            Settings.shared.screenshotHotkeyKeyCode,
+            Settings.shared.screenshotHotkeyModifiers,
+            screenshotKeyID,
+            GetApplicationEventTarget(),
+            0,
+            &screenshotHotKeyRef
+        )
+
+        guard screenshotStatus == noErr else {
+            NSLog("[HotkeyManager] Failed to register screenshot hotkey: %d", screenshotStatus)
+            return
+        }
+
+        NSLog("[HotkeyManager] Screenshot hotkey registered: %@",
+              Settings.hotkeyDisplayString(keyCode: Settings.shared.screenshotHotkeyKeyCode,
+                                           modifiers: Settings.shared.screenshotHotkeyModifiers))
     }
```

**ポイント**: 既存の Zoom/Draw/Break と完全に同じパターンですが、エラー時の挙動だけ少し考えてください。Zoom 登録に失敗すると `stop()` で全部巻き戻していますが、ここでは Break 登録までは成功しているので、Screenshot だけ登録失敗しても他のホットキーは生かしておく方が親切です。`return` のみで `stop()` を呼ばないのはそのためです。

### 4. stop() の解放処理 (line 134-137 付近)

```diff
         if let ref = breakHotKeyRef {
             UnregisterEventHotKey(ref)
             breakHotKeyRef = nil
         }
+        if let ref = screenshotHotKeyRef {
+            UnregisterEventHotKey(ref)
+            screenshotHotKeyRef = nil
+        }
         if let handler = eventHandlerRef {
```

**ポイント**: Carbon は ARC の管理外です。`UnregisterEventHotKey` を呼ばないと OS 内部に登録が残り続けるリーク状態になります。`if let ref = ...` で nil チェック → 解放 → nil 代入のパターンを揃えること。

### 5. handleHotKeyEvent に分岐追加 (line 169-181 付近)

```diff
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
+        } else if hotKeyID.id == screenshotHotKeyID {
+            DispatchQueue.main.async { [weak self] in
+                self?.onScreenshotHotkey?()
+            }
         }
     }
```

**ポイント**: ここが Carbon C コールバックの「Swift 側着地点」です。再確認すべきは **`DispatchQueue.main.async { [weak self] in ... }` の二重ガード** です。

- `DispatchQueue.main.async`: C コールバックは多くの場合メインスレッドで呼ばれますが、Apple は明文化していません。UI 操作 (Overlay 表示など) を含むハンドラを安全に動かすため、必ずメインに揃えます。
- `[weak self]`: `HotkeyManager.shared` はアプリのライフタイムと同じですが、コードの局所では「シングルトンであること」を前提にしないのがプロの作法です。テスト時にインスタンスを差し替えても破綻しないよう常に弱参照で書く。

`onScreenshotHotkey?()` の末尾の `?` も忘れずに。クロージャが `nil` のまま `⌃4` を押してもクラッシュしないようにするためです。

---

## Step 9-10: AppDelegate.swift の拡張

### 1. インポートの追加 (line 1-2)

```diff
 import AppKit
+import ScreenCaptureKit
```

**ポイント**: ScreenCaptureKit は macOS 12.3+ で導入された画面キャプチャの公式 API です。`StillZoomWindowController` や `OverlayWindowController` でも使われている (Ch35 参照)。ZoomacIt のターゲット macOS 26 では問題なく利用できます。

### 2. ハンドラ接続 (line 31-33 付近)

```diff
         hotkeyManager.onBreakHotkey = { [weak self] in
             self?.toggleBreakTimer()
         }
+        hotkeyManager.onScreenshotHotkey = { [weak self] in
+            self?.takeScreenshot()
+        }
         hotkeyManager.start()
```

**ポイント**: `[weak self]` を必ず付けること。理由は Ch28 の復習ですが、要点を再掲します。

- `HotkeyManager.shared` は **シングルトン**でアプリが死ぬまで生き続ける。
- そのプロパティに格納されたクロージャが `self` (= `AppDelegate`) を強キャプチャすると、`AppDelegate` も同じく永続化される。
- `AppDelegate` は本来アプリ終了時に解放されるべき。永続化されると、その内部で参照している全コントローラ (`zoomController` 等) も道連れに残り続ける。
- 結果として **メモリリーク**かつ**解放処理が走らない問題**を引き起こす。

ZoomacIt は短時間しか動かないユーティリティではなく**常駐型メニューバーアプリ**なので、リークは確実に蓄積します。

### 3. takeScreenshot() の実装

`// MARK: - Break Timer` の前あたり、または末尾の `showPreferences()` の後に追加します。

```swift
// MARK: - Screenshot

private func takeScreenshot() {
    Task { @MainActor in
        guard let cgImage = await Self.captureFullScreen() else {
            NSLog("[AppDelegate] Screenshot capture failed")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "ZoomacIt_Screenshot_\(timestamp).png"

        guard let desktop = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask).first else {
            NSLog("[AppDelegate] Could not locate Desktop directory")
            return
        }
        let url = desktop.appendingPathComponent(filename)

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            NSLog("[AppDelegate] PNG encoding failed")
            return
        }

        do {
            try pngData.write(to: url)
            NSLog("[AppDelegate] Screenshot saved to %@", url.path)
        } catch {
            NSLog("[AppDelegate] Screenshot save failed: %@", String(describing: error))
        }
    }
}

private static func captureFullScreen() async -> CGImage? {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else { return nil }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    } catch {
        NSLog("[AppDelegate] captureFullScreen error: %@", String(describing: error))
        return nil
    }
}
```

ここを 1 ブロックずつ解説します。

#### `Task { @MainActor in ... }` の役割

`takeScreenshot()` は `func takeScreenshot()` (同期) ですが、内部で `await` を使っています。これを成立させるのが `Task { ... }` です。

- `Task { ... }` は新しい非同期タスクを生成し、内部で `await` を許可する
- `@MainActor` 指定により、タスクの実行コンテキストはメインスレッドに固定される
- `AppDelegate` は `@MainActor` 注釈クラスなので、`self.captureFullScreen()` 等を呼ぶ際に**スレッド境界を越えるエラー**を防げる

`Task.detached { ... }` ではないことに注意。`Task.detached` は親アクターを継承しません。ここでは UI スレッドから離れたくないので `Task { @MainActor in ... }` (= 親アクター継承 + 明示的に MainActor 固定) が正解です (Ch21 復習)。

#### `ISO8601DateFormatter` とコロン置換

`ISO8601DateFormatter().string(from: Date())` は `2026-05-09T15:32:04Z` 形式の文字列を返します。これをそのままファイル名にすると、Finder では `:` が `/` として表示される (HFS+/APFS の伝統的振る舞い)。`replacingOccurrences(of: ":", with: "-")` でハイフンに置換して安全な名前にします。

#### `FileManager.urls(for:in:)`

`urls(for: .desktopDirectory, in: .userDomainMask)` はユーザーホーム下の Desktop ディレクトリの URL を返します (`~/Desktop` = `/Users/<user>/Desktop`)。`first` は配列の先頭という意味ですが、`.userDomainMask` 単独なら要素は基本 1 つです。Sandbox 化したアプリでは挙動が変わりますが、ZoomacIt は非サンドボックスなので素直にユーザーの Desktop が取れます。

#### `NSBitmapImageRep(cgImage:)` + `.representation(using: .png)`

`CGImage` から PNG `Data` への変換は AppKit の `NSBitmapImageRep` 経由が定番です。

```swift
let bitmap = NSBitmapImageRep(cgImage: cgImage)
let pngData = bitmap.representation(using: .png, properties: [:])
```

ここで `.png` の代わりに `.jpeg` を渡すと JPEG が得られます。今回は劣化なしの PNG を選択。

#### `captureFullScreen()` を `static` にした理由

`AppDelegate` の他のメソッド (`toggleStillZoomMode` など) は `self` 経由で呼ぶインスタンスメソッドですが、`captureFullScreen()` は `self` の状態を一切使わないため `static` にしてあります。`Self.captureFullScreen()` の `Self` (大文字) は型自身の参照で、`self` (小文字、インスタンス) と区別されます。`@MainActor` クラス内なので結局メインスレッドで動きますが、「インスタンス状態に触れない関数」だと明示するための慣行です。

#### ScreenCaptureKit の流儀

`SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` は**画面に映っているウィンドウだけ**を含めるフィルタです。第 1 引数 `false` は「デスクトップ壁紙アイコンも除外しない」という意味。

`SCContentFilter(display: display, excludingWindows: [])` で「この display を撮るが、特定ウィンドウは除外」できますが、今回は何も除外しないので空配列。

`SCStreamConfiguration` で出力解像度とカーソルの可否を指定。`showsCursor = false` にしないと、ホットキー押下時のカーソル位置がスクリーンショットに写り込みます。

`SCScreenshotManager.captureImage(contentFilter:configuration:)` がワンショット撮影 API です。`SCStream` (連続撮影) ではなく `SCScreenshotManager` を使うのがスクリーンショット用途の正解 (Ch35 参照)。

---

## なぜこのハンズオンが「総合演習」なのか

このハンズオン 1 つで、これまでの章のほぼすべてに触れています。

| 触れた要素 | 関連章 |
|------------|--------|
| `@escaping` クロージャプロパティ | Ch10 |
| `[weak self]` キャプチャリスト | Ch28 |
| `Task { @MainActor in ... }` | Ch21 |
| `async`/`await` で SCK を呼ぶ | Ch21, Ch35 |
| Carbon `RegisterEventHotKey` の引数構造 | Ch34 |
| C コールバックからメインスレッド戻し | Ch34 |
| `UserDefaults` への永続化 (computed property) | Ch36 |
| シングルトン (`Settings.shared`, `HotkeyManager.shared`) からの読み出し | Ch7, Ch36 |
| `FileManager` + `URL` + `Data.write` | Foundation 全般 |
| `NSBitmapImageRep` で CGImage → PNG | Ch33, AppKit 一般 |

機能的には「ホットキーを 1 つ足しただけ」ですが、**ZoomacIt の縦割りアーキテクチャを 3 階層 (App / Core / Models) 縦断する** ため、各レイヤーの責務とデータの流れが体感できる構成になっています。

仕事で実際の機能追加をするときも、この種の縦断作業がほとんどです。「クラスを 1 つ作って終わり」になることは稀で、**永続化レイヤー → ロジック層 → エントリーポイント** の順に手を入れることになります。今回身につけた手順は他のプロジェクトにそのまま転用できる汎用パターンです。

---

## 次に試したいこと

[ハンズオン本文](../../part4-handson/40-add-hotkey.md) の **「さらにチャレンジ」** に挙げた 4 つの拡張のうち、もっとも学習効果が高いのは **「Settings UI に項目を追加」** です。次章 [Ch41](../../part4-handson/41-add-settings-tab.md) で SwiftUI 設定タブの追加を扱うので、そこで自然に補完されます。

「マウス位置周辺だけキャプチャ」は ScreenCaptureKit の `SCStreamConfiguration.sourceRect` (CGRect) を使えば短く実装できます。座標系が **左下原点 (= AppKit 座標)** なのか **左上原点 (= 画面ピクセル座標)** なのかでハマるポイントなので、デバッグのよい題材です。
