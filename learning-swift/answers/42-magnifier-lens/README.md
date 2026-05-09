# Ch42 卒業課題: 設計判断ヒント

## このディレクトリの方針

本教材の他のハンズオン(Ch38-41)とは違い、**Ch42 には完成コードを置きません**。卒業課題の本質は「自分で設計判断を下す経験」にあるため、ここには **判断のヒント** だけを記します。

行き詰まったときの参照用です。**1 時間以上自力で格闘してから** 開いてください。

---

## 設計判断のサンプル回答

本文 Ch42 で問うた 5 つの設計判断ポイントについて、私(教材執筆者)ならどう答えるかを示します。**これは唯一の正解ではありません**。あなたの判断と違っても、動くなら問題ありません。

### 1. キャプチャ方式 — 単発か連続か

**学習段階なら単発を Timer で繰り返す方を推奨**します。

理由:

- ZoomacIt の `BreakTimerWindowController.captureScreenImage` がそのまま参考になる(Ch35 で読んだコード)
- `SCStream` は `SCStreamOutput` プロトコルに適合する delegate を作る必要があり、boilerplate が多い
- 30Hz の更新速度なら Timer + 単発で十分

性能を本気で詰めるなら `SCStream` に切り替える価値がありますが、それは応用課題として後で取り組めば OK です。

### 2. 円形ウィンドウの実装方法

**Method A(`layer.cornerRadius`)を推奨**します。

```swift
window.isOpaque = false
window.backgroundColor = .clear
window.styleMask = .borderless

contentView.wantsLayer = true
contentView.layer?.cornerRadius = 100  // 直径 200 の半分
contentView.layer?.masksToBounds = true
```

理由:

- AppKit のレイヤーシステムが GPU で円形クリップしてくれる(描画コードが軽量)
- 既存の `OverlayWindow.swift`(`borderless` + transparent + content view layer)のパターンと整合する

Method B(`NSBezierPath` の `addClip`)は描画ごとに毎回クリップを設定するためやや重く、Method C(`CAShapeLayer` mask)は柔軟だが冗長です。

### 3. ホットキー競合の処理

Ch40 で実装した `screenshotHotKeyID` のパターンをそのまま流用します。

```swift
// HotkeyManager.swift
var onMagnifierHotkey: (() -> Void)?
private var magnifierHotKeyRef: EventHotKeyRef?
private let magnifierHotKeyID: UInt32 = 4   // 既存 0,1,2,3 と被らない
```

`start()` の中で `RegisterEventHotKey` を 1 回追加、`stop()` で `UnregisterEventHotKey` を 1 回追加、`handleHotKeyEvent` の switch に `magnifierHotKeyID` 分岐を追加。

### 4. 起動と排他制御

`AppDelegate` で次のようなガードを書きます。

```swift
private func toggleMagnifier() {
    if magnifierController != nil {
        magnifierController?.dismiss()
        magnifierController = nil
        return
    }
    // 他のオーバーレイが出ているなら起動しない
    guard zoomController == nil,
          drawController == nil,
          breakTimerController == nil else {
        NSSound.beep()
        return
    }
    let controller = MagnifierWindowController()
    controller.onDismiss = { [weak self] in
        self?.magnifierController = nil
    }
    controller.show()
    magnifierController = controller
}
```

`onDismiss` クロージャで自分自身の参照を nil にするパターンは、ZoomacIt の `BreakTimerWindowController` などが採用しているお約束です。

### 5. ウィンドウの配置位置

```swift
let mouseLocation = NSEvent.mouseLocation   // グローバル座標、左下原点
let offset: CGFloat = 30                    // マウスの右下にずらす
let windowOrigin = CGPoint(
    x: mouseLocation.x + offset,
    y: mouseLocation.y - 200 - offset       // ウィンドウは下方向に伸びる
)
window.setFrameOrigin(windowOrigin)
```

Timer のたびに `setFrameOrigin` で更新するとちらつくので、`window.animator()` 経由か、または `setFrameOrigin` を直接呼ぶ前に `disableScreenUpdatesUntilFlush()` を使う手もあります(必須ではない)。

---

## ハマりどころの追加解説

### A. マウス座標系の変換

`NSEvent.mouseLocation` は **AppKit 座標系**(左下原点、`NSScreen` の論理座標)です。一方、`SCStreamConfiguration.sourceRect` は **キャプチャ対象 display のピクセル座標系**(左上原点、Retina スケール込み)です。

変換式:

```swift
let mouse = NSEvent.mouseLocation
guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
let scale = screen.backingScaleFactor

// AppKit (左下) → ピクセル (左上) 変換
let pixelX = (mouse.x - screen.frame.minX) * scale
let pixelY = (screen.frame.maxY - mouse.y) * scale  // Y 軸反転
```

`SCStreamConfiguration.sourceRect` には CGRect を渡しますが、AppKit ではなく **ピクセル単位の左上原点** で指定します。

### B. Timer の確実な停止

Timer は `RunLoop` に登録されるため、`weak` 参照だけでは解放されません。**明示的に `invalidate()` を呼ぶ責務** を `MagnifierWindowController.dismiss()` に持たせてください。

```swift
@MainActor
final class MagnifierWindowController {
    private var captureTimer: Timer?

    func dismiss() {
        captureTimer?.invalidate()
        captureTimer = nil
        window?.orderOut(nil)
        window = nil
        onDismiss?()
    }
}
```

`deinit` を書く誘惑に駆られますが、ZoomacIt の流儀(Ch18 で見た「deinit を書かずに dismiss で能動的に解放する」)に従うほうが整合します。

### C. ScreenCaptureKit のスケール

`SCStreamConfiguration.width` と `height` は **実ピクセル単位** です。Retina の場合、`50pt × 50pt` を 4 倍に拡大したいなら:

```swift
let captureSize: CGFloat = 50
let scale = screen.backingScaleFactor
config.width = Int(captureSize * scale)         // Retina なら 100
config.height = Int(captureSize * scale)
config.sourceRect = CGRect(
    x: pixelX - (captureSize * scale / 2),
    y: pixelY - (captureSize * scale / 2),
    width: captureSize * scale,
    height: captureSize * scale
)
```

ウィンドウ側は `200pt × 200pt`(論理単位)で表示します。AppKit が Retina スケールを自動で扱うので、CGImage が `100 × 100` ピクセルでも、200pt のビューに描画すれば 4 倍拡大されたように見えます。

### D. ホットキー登録の対称性

`start()` で `RegisterEventHotKey` を呼んだら、必ず `stop()` で `UnregisterEventHotKey` を呼びます。`HotkeyRef` を 4 個に増やしたら、すべての対称性を保つこと。

---

## 参考になる既存ファイル

Magnifier Lens の実装に近い既存ファイルを優先順に挙げます。

| ファイル | 何を学べるか |
|---|---|
| `src/ZoomacIt/Overlay/StillZoomWindowController.swift` | 全画面オーバーレイ + ScreenCaptureKit + dismiss パターン |
| `src/ZoomacIt/Overlay/BreakTimerWindowController.swift` | `@MainActor` final class + Timer + onDismiss callback |
| `src/ZoomacIt/Overlay/OverlayWindow.swift` | `borderless` + 透明背景の NSWindow サブクラス |
| `src/ZoomacIt/Core/HotkeyManager.swift` | ホットキー追加の手順全体 |
| `src/ZoomacIt/App/AppDelegate.swift` | 複数オーバーレイの排他制御 |

これらを **コピペするのではなく、パターンを学ぶ** スタンスで読んでください。

---

## 進め方の推奨ペース

| 経過時間 | 達成すべき状態 |
|---|---|
| 30 分 | 設計メモ完成。新規作成するファイル一覧と修正するファイル一覧が明確 |
| 60 分 | `MagnifierWindowController` の骨格(NSWindow 生成、空の content view、dismiss)が動く |
| 90 分 | ホットキー追加完了、`⌃4` で空の円形ウィンドウが出る |
| 120 分 | ScreenCaptureKit で **静止画 1 枚** が円形ウィンドウに表示される |
| 150 分 | Timer による連続更新で、マウス追従が動く |
| 180 分 | 排他制御、ESC 終了などの仕上げ |

3 時間で最低動作にたどり着ければ十分です。詰まったらここに戻ってきてください。

---

## 自分の解を残す

完成したら、別途 `solution.md` などに **設計判断とその理由** を書き残しておくことを強く推奨します。あとで自分の成長を振り返る記録になります。

> **NOTE**
> 本物の OSS 開発でも、PR の説明文に「なぜこの設計を選んだか」を書く習慣は重要です。卒業課題はその予行演習でもあります。
