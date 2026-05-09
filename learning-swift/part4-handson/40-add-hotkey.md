# Ch40. ハンズオン 3: 新しいホットキーアクション

## 課題概要

これまでの 2 つのハンズオン (Ch38: ペンカラー追加 / Ch39: 図形追加) は、Draw 機能の内側で完結する変更でした。今回はさらに範囲を広げ、**アプリ全体の入り口にあたるグローバルホットキー** に新しいアクションを足します。

具体的には、ZoomacIt に **「⌃4 で現在の画面をキャプチャし、`~/Desktop` に PNG ファイルとして保存する」** ホットキーを追加します。

ここで触れるレイヤーは多岐にわたります。

- `Settings` (UserDefaults 永続化) に新しいキーコード/モディファイアの保存場所を作る
- `HotkeyManager` に `@escaping` クロージャプロパティを追加し、Carbon API でホットキーを登録する
- `AppDelegate` で `[weak self]` を使ったハンドラを実装し、ScreenCaptureKit で画面を取得して PNG として書き出す

ZoomacIt の 5 階層アーキテクチャ (App / Core / Overlay / Draw / Settings) のうち、**App・Core・Models** の 3 つを横断する総合演習です。今までの章でバラバラに学んだ部品が、実際のアプリでどう組み合わさるのかを確認してください。

## 前提となる章

このハンズオンは複数章の知識を統合します。実装中に詰まったら以下に戻ってください。

| 章 | 復習する内容 |
|----|--------------|
| [Ch10. クロージャ](../part2-language-guide/10-closures.md) | `@escaping`、関数型プロパティ、トレーリングクロージャ |
| [Ch21. async/await](../part2-language-guide/21-async-await.md) | `Task { @MainActor in ... }` でメインスレッドに戻すパターン |
| [Ch28. ARC とメモリ管理](../part2-language-guide/28-arc-memory.md) | キャプチャリストでの `[weak self]`、循環参照回避 |
| [Ch34. Carbon API と C 橋渡し](../part3-zoomacit-deep-dive/34-carbon-bridging.md) | `RegisterEventHotKey`、`EventHotKeyID`、コールバック構造 |
| [Ch35. ScreenCaptureKit](../part3-zoomacit-deep-dive/35-screencapturekit.md) | `SCShareableContent`・`SCScreenshotManager.captureImage` |
| [Ch36. UserDefaults と Settings](../part3-zoomacit-deep-dive/36-userdefaults.md) | `Keys` enum、`registerDefaults`、computed property での read/write |

## 学習狙い

このハンズオンを終えると、次の知識・技能が確認できます。

- `@escaping` クロージャプロパティを既存マネージャーに「足す」フローが身につく
- Carbon の `RegisterEventHotKey` を **2 つの引数 (key code / modifiers) を変えながら複数登録** する流儀を実装で体得できる
- C コールバックからメインスレッドへ戻す `DispatchQueue.main.async { [weak self] in ... }` の必然性を再認識できる
- `Task { @MainActor in ... }` で非同期処理の結果を UI スレッドへ橋渡しする実例を書ける
- `FileManager` + `URL.appendingPathComponent` + `Data.write(to:)` の組み合わせで、ファイル保存をミニマムに実装できる

## 完成イメージ

実装後、メニューバーアプリを起動した状態で `⌃4` を押すと:

1. 画面全体が ScreenCaptureKit で撮影される
2. `~/Desktop` に `ZoomacIt_Screenshot_2026-05-09T15-32-04Z.png` のような名前で PNG が保存される
3. ターミナルから `make run` していれば、保存先パスが NSLog に流れる

UI 側 (Settings ダイアログのキー割り当て編集) には今回触れません。**実コードを書くハンズオンとしては最小、しかし複数レイヤーを跨ぐ点で総合的** という難易度設計です。

## ステップ

1. **Settings.swift の Keys に追加**: `Keys` enum に `screenshotHotkeyKeyCode` と `screenshotHotkeyModifiers` の文字列キーを追加する。
2. **registerDefaults に既定値を登録**: `kVK_ANSI_4` と `controlKey` を初期値として `defaults.register` 辞書に追記する。
3. **Settings に computed property を追加**: 既存の `zoomHotkeyKeyCode` などと同じパターンで、`screenshotHotkeyKeyCode` / `screenshotHotkeyModifiers` の `get/set` を作る。
4. **HotkeyManager にクロージャプロパティを追加**: `var onScreenshotHotkey: (() -> Void)?` を既存の 3 プロパティの隣に置く。
5. **HotkeyManager に保管プロパティと ID を追加**: `private var screenshotHotKeyRef: EventHotKeyRef?` と `private let screenshotHotKeyID: UInt32 = 3` を追加する。
6. **start() で 4 つ目の RegisterEventHotKey を呼ぶ**: 既存の Break Timer 登録のすぐ後に、同じ書式で 4 つ目を登録する。エラーチェックも忘れない。
7. **stop() で UnregisterEventHotKey を呼ぶ**: `screenshotHotKeyRef` の解放処理を `stop()` に足す。
8. **handleHotKeyEvent に分岐を追加**: `else if hotKeyID.id == screenshotHotKeyID { ... }` を `switch` 相当の `if-else if` 連鎖に追加する。
9. **AppDelegate でハンドラを接続**: `applicationDidFinishLaunching` 内に `hotkeyManager.onScreenshotHotkey = { [weak self] in self?.takeScreenshot() }` を追加する。
10. **AppDelegate に `takeScreenshot()` を実装**: `Task { @MainActor in ... }` で囲み、ScreenCaptureKit で画面取得 → `NSBitmapImageRep` で PNG 化 → `~/Desktop` に保存する。
11. **ビルド & 実行**: `make build && make run` を実行し、`⌃4` を押してデスクトップに PNG が出ることを確認する。

各ステップの **完成形** はこの章の解答例 (`learning-swift/answers/40-add-hotkey/`) にあります。詰まったときだけ覗いてください。

## 動作確認チェックリスト

実装後、以下を順に確認してください。

- [ ] `make build` がエラーゼロで通る (Swift 6 の strict concurrency が有効なため、`@MainActor` 越境警告も出ない)
- [ ] `make run` で起動し、メニューバーに ZoomacIt アイコンが現れる
- [ ] 既存の `⌃1` (Zoom)、`⌃2` (Draw)、`⌃3` (Break Timer) が**従来通り動く** (= 4 つ目の登録が他を壊していない)
- [ ] `⌃4` を押すとデスクトップに `ZoomacIt_Screenshot_*.png` が生成される
- [ ] ファイルを Finder で開き、現在画面のスクリーンショットになっていることを確認
- [ ] Console.app で `[AppDelegate] Screenshot saved to ...` という NSLog が見える

ScreenCaptureKit は **Screen Recording 権限** を要求します。初回実行時はシステム設定からの許可が必要です。`CLAUDE.md` にも記載のとおり、ZoomacIt が要求する唯一の OS 権限です。

## 失敗しやすいポイント

### 1. クロージャに `[weak self]` を付け忘れる

`hotkeyManager.onScreenshotHotkey = { self.takeScreenshot() }` のように書くと、`HotkeyManager.shared` (シングルトン) が `AppDelegate` を強参照し、**プロセス終了まで AppDelegate が解放されません**。常に `[weak self] in self?.takeScreenshot()` の形を守ってください (Ch28 復習)。

### 2. `Task { @MainActor in ... }` を忘れる

ScreenCaptureKit の `captureImage(contentFilter:configuration:)` は `async throws` です。同期的に呼ぶことはできません。また、ファイルパス組み立てや `NSLog` を含む後続処理を **メインスレッド** に揃えるため、`Task { @MainActor in ... }` で囲むのが安全です。

### 3. ファイル名に `:` を含めてしまう

ISO 8601 形式 (`2026-05-09T15:32:04Z`) には `:` (コロン) が含まれます。macOS の Finder では `:` がファイル名で許されません (内部的にスラッシュに変換されて表示される)。`replacingOccurrences(of: ":", with: "-")` で置換しましょう。

### 4. キーコードの値を間違える

`kVK_ANSI_4` は `21` です。Carbon の仮想キーコードは「キーボード上の物理位置」基準なので、見た目の文字とは一致しません。**必ず `kVK_ANSI_*` 定数を使う** こと (Ch34 復習)。

### 5. start() の `guard hotKeyRef == nil else` でガードされて 4 つ目が登録されない

既存の `start()` 冒頭は `guard hotKeyRef == nil else { return }` で「もう登録済みならスキップ」する作りです。ここを変える必要はありませんが、**ガードの意味を正しく理解** してから 4 つ目の登録を Break の後に書くこと。`hotKeyRef` (Draw 用) が nil でない時点で、Zoom/Break/Screenshot もまとめて登録済みという前提です。

## さらにチャレンジ

基本実装が動いたら、余裕があれば以下に取り組んでください。

- **保存先を Settings から指定可能に**: `breakTimerSoundFile` のように `URL?` を `UserDefaults` に保存し、`NSOpenPanel` でフォルダを選ばせる。
- **マウス位置周辺だけキャプチャ**: `SCStreamConfiguration` の `sourceRect` を活用し、`NSEvent.mouseLocation` の周囲 800×600px だけを撮影する。
- **保存後に macOS 通知を出す**: `UserNotifications` フレームワーク (`UNUserNotificationCenter.current().add(...)`) で「ScreenShot saved」のバナーを出す。
- **Settings UI に項目を追加**: `GeneralTab.swift` に `KeyRecorderView` を追加してキー組み合わせを編集可能にする。これは次章 [Ch41](./41-add-settings-tab.md) で扱う題材なので、先取りしたい人向け。

## 次に読む章

→ [41. ハンズオン 4: 設定タブを 1 つ増やす](./41-add-settings-tab.md)

## 参考: 解答例

`learning-swift/answers/40-add-hotkey/README.md` に diff 形式で全変更を載せています。途中で詰まったら、自分の実装と照らし合わせて差分を確認してください。「動かしてから答え合わせ」が最も学習効率が高いので、まずはステップ 1〜11 を**すべて自力で書ききって** ください。
