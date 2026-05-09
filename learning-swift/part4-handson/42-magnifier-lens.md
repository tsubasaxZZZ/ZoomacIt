# Ch42. 卒業課題: Magnifier Lens 機能

## この課題の位置づけ

これは本教材の **卒業課題** です。Part I から Ch41 までで学んだすべての知識を統合して、新機能をゼロから設計・実装します。これまでのハンズオンとは違い、**詳細な手順書はありません**。仕様だけを提示するので、自力で設計判断を下しながら進めてください。

> **NOTE**
> 卒業課題に「正解」はありません。動作する実装にたどり着けば、それがあなたの解です。複数の設計判断があり得る場面では、自分で選択し、その理由を説明できるようになることがゴールです。

---

## 課題概要

ZoomacIt に **Magnifier Lens(ルーペ)機能** を追加します。これは Windows 版 ZoomIt の Live Zoom と Spotlight の中間にあたる機能で、マウスカーソル周辺の小さな領域だけを拡大して表示する **円形の浮遊ウィンドウ** です。

イメージ:

```
            +------+
        +---|      |---+
       /    | 拡大 |    \
      |     |  画 |     |
      |     |  像 |     |
       \    |      |    /
        +---|      |---+
            +------+
              ↑
        マウスカーソル
```

## 機能仕様

| 項目 | 仕様 |
|---|---|
| 起動ホットキー | `⌃4` (Control + 4) |
| ウィンドウ形状 | 円形(直径 200pt) |
| 拡大倍率 | 4 倍 |
| キャプチャ範囲 | マウスカーソル周辺 50pt × 50pt(縦横が `200 / 4 = 50pt` のため) |
| 終了 | `ESC` キー、または `⌃4` を再度押す |
| 動作中の追従 | マウス移動に追従して常に最新の周辺を表示する(60Hz 程度の更新で OK) |
| 他機能との排他 | Zoom / Draw / Break Timer がアクティブなら起動しない |

## 前提

完了しておくべき章:

- Ch16 (Inheritance) — `NSWindow` を継承するか、`NSWindow` の通常インスタンスを使うかの判断
- Ch21 (Concurrency) — `@MainActor` と `Task`
- Ch28 (ARC) — `[weak self]` の運用
- Ch33 (NSView 描画) — マスクで円形に切り抜く方法
- Ch34 (Carbon C 橋渡し) — `⌃4` ホットキー登録(Ch40 の応用)
- Ch35 (ScreenCaptureKit) — マウス周辺領域だけをキャプチャする `SCStreamConfiguration.sourceRect`

動作確認に必要なコマンド: `make build`, `make run`

## 学習狙い

この課題で身につくスキル:

1. **要件 → 設計 → 実装** の全工程を自力で進める力
2. **複数のレイヤー(App / Overlay / Core / Models / Settings)を横断する変更** を整合させる経験
3. **既存コードの設計思想に沿って新機能を追加する** 感覚(ZoomacIt の `final class` + `@MainActor` + `[weak self]` のパターンを踏襲)
4. **ScreenCaptureKit の応用**(部分領域キャプチャ、連続フレーム取得)
5. **NSWindow の特殊形状**(円形マスク、`NSWindow.StyleMask.borderless`、`isOpaque = false`)

## 設計上の判断ポイント

実装に取りかかる前に、次の問いに自分で答えを出してください。

### 1. キャプチャ方式 — 単発か連続か

`SCScreenshotManager.captureImage(...)` は単発の静止画キャプチャです。マウス追従するには **タイマーで繰り返し呼ぶ** か、**`SCStream` で連続フレームを受け取る** かの選択になります。

- **単発を繰り返す**: 実装は単純。性能は 30Hz 程度が限界
- **`SCStream` 連続受信**: 実装は複雑。60Hz でも余裕

学習目的なら **単発を `Timer` で繰り返す** が手軽です。`SCStream` 採用は応用課題として後回しにしても構いません。

### 2. 円形ウィンドウの実装方法

NSWindow を円形にする方法は複数あります。

- **Method A**: `NSWindow.isOpaque = false` + `backgroundColor = .clear` + `NSView` の `wantsLayer = true` + `layer?.cornerRadius = 100` + `layer?.masksToBounds = true`
- **Method B**: カスタム `NSView` の `draw(_:)` 内で `NSBezierPath(ovalIn:).addClip()` してから画像描画
- **Method C**: `NSWindow.contentView?.layer?.mask` に円形 `CAShapeLayer` をセット

ZoomacIt の他のオーバーレイは `BorderlessWindowMask` + 透明背景で書かれているので、それを参考に Method A が最も整合します。

### 3. ホットキー競合の処理

既に `⌃1` (Zoom)、`⌃2` (Draw)、`⌃3` (Break Timer) が登録されています。`⌃4` を追加するには:

- `Settings.swift` に `magnifierHotkeyKeyCode` / `magnifierHotkeyModifiers` を追加
- `HotkeyManager.swift` に `var onMagnifierHotkey: (() -> Void)?` と 4 つ目の `RegisterEventHotKey` を追加
- `AppDelegate.swift` でハンドラを登録

これは Ch40(ハンズオン 3)で学んだパターンの再利用です。

### 4. 起動と排他制御

`AppDelegate` で他のオーバーレイ(Zoom / Draw / Break Timer)が表示されていない時のみ起動するようにします。具体的には `if zoomController != nil || drawController != nil || breakTimerController != nil { return }` のようなガード。

### 5. ウィンドウの配置位置

ルーペウィンドウはマウスカーソルの周辺(やや右下にずらすと、自分の指の影にならず見やすい)に配置します。マウス座標は `NSEvent.mouseLocation` で取得できます。

## 推奨する実装順序

1. **設計メモを書く**(15 分程度) — 上の判断ポイントに自分の答えを書き出す
2. **`MagnifierWindowController.swift` を新規作成**(`src/ZoomacIt/Overlay/` 配下)
3. **`MagnifierView.swift` を新規作成**(`src/ZoomacIt/Overlay/` 配下、`NSView` サブクラス)
4. **`HotkeyManager` に 4 つ目のホットキーを追加**(Ch40 の知識)
5. **`Settings` にホットキー設定を追加**
6. **`AppDelegate` で起動・終了の制御**
7. **ScreenCaptureKit でマウス周辺をキャプチャ**(`SCStreamConfiguration.sourceRect` を使う)
8. **タイマーで連続キャプチャ**(`Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`)
9. **`make generate` でプロジェクトに新ファイルを追加**(xcodegen が `project.yml` の `sources` を見て自動収集します)
10. **`make build && make run` で動作確認**

## 動作確認チェックリスト

- [ ] `make build` がエラーなく成功する
- [ ] `make run` で起動後、`⌃4` でルーペが現れる
- [ ] ルーペは円形に表示される(四角ではない)
- [ ] マウスを動かすとルーペがその周辺を表示する
- [ ] `ESC` または再度の `⌃4` で消える
- [ ] Zoom / Draw / Break Timer がアクティブなときに `⌃4` を押しても起動しない(または、その逆も成立する)
- [ ] アプリ終了後にプロセスがゴーストにならない(リソースが解放される)

## ハマりやすいポイント

### A. マウス座標系の混乱

macOS の座標系は **左下原点**(SwiftUI / iOS は左上原点)です。`NSEvent.mouseLocation` の座標を NSWindow の `setFrameOrigin(_:)` に渡すときは、そのまま使えますが、`SCStreamConfiguration.sourceRect` に渡すときはディスプレイのピクセル座標(左上原点、Retina スケール考慮)に変換が必要です。

### B. Timer のメモリリーク

`Timer.scheduledTimer(withTimeInterval:repeats:)` のクロージャは強参照です。`[weak self]` を必ず付けて、`deinit` でなくても **明示的に `timer.invalidate()`** を呼ぶ責務をどこかに置いてください(MagnifierWindowController の `dismiss()` メソッドが妥当)。

### C. ScreenCaptureKit のスケールファクター

Retina ディスプレイでは `SCStreamConfiguration.width` / `height` を **実ピクセル単位** で指定する必要があります。`50pt × 50pt` の領域なら、Retina で `100 × 100` ピクセル分指定します。`NSScreen.backingScaleFactor` で取得できます。

### D. ホットキー登録漏れ

`HotkeyManager.start()` の中で 4 つ目の `RegisterEventHotKey` を呼び出す手順を忘れがちです。Ch34 で読んだ HotkeyManager のパターンを丁寧に踏襲してください。

## 解答例について

本教材では、卒業課題には **完成コード例を提供しません**。これは単なる「答え隠し」ではなく、卒業課題の本質が「自分で設計判断を下す経験」にあるためです。

ただし、行き詰まったときのために、設計案のヒントは [`learning-swift/answers/42-magnifier-lens/`](../answers/42-magnifier-lens/) に置いてあります。そこには:

- 設計判断のサンプル回答
- ハマりどころの追加解説
- 参考になる既存ファイル(`OverlayWindowController` など)へのリンク

が記載されています。**完成コードを直接見るのは、自分で 1 時間以上格闘してから** にしてください。それが学習効果を最大化する近道です。

## さらにチャレンジ

ルーペが動いたら、次の応用にも挑戦できます:

1. **`SCStream` で 60Hz 連続キャプチャに置き換える**(Timer + 単発キャプチャからのアップグレード)
2. **拡大倍率を `+` / `-` キーで動的に変える**
3. **ルーペを固定モード(マウス追従しない)に切り替える機能**
4. **設定タブ "Magnifier" を追加して、倍率・サイズ・形状(円 / 四角)を設定可能にする**(Ch41 の応用)
5. **画面録画中にルーペが映らないようにする**(`window.sharingType = .none`)

---

## 卒業おめでとう

ここまで完走したあなたは、Swift と macOS 開発の基礎から応用までを **実プロダクトのコードで** 学びきりました。あとは自分のプロジェクトで磨き続けるのみです。

ZoomacIt のリポジトリには、これからも改善余地が無数にあります(`design/CONCEPT.md` の "未実装機能" セクションを参照)。気が向いたら、本物の Pull Request としてあなたの実装を投げてみてください。

> **NOTE**
> 本教材で扱わなかった発展トピック: Swift Package Manager、Swift Testing(新フレームワーク)、Swift Macros、Distributed actors、Embedded Swift。これらはあなたの次の学習材料です。
