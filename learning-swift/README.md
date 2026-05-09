# ZoomacIt で学ぶ Swift

このディレクトリは、リポジトリ `ZoomacIt`(macOS メニューバーアプリ、Windows 版 ZoomIt のクローン)を **Swift 学習教材** として再構成したものです。

実際にビルド・実行できる macOS アプリのコードを題材にして、Swift の文法から AppKit / 並行性 / C 橋渡しまでを段階的に学びます。

## 対象読者

- **Java を業務レベルで使える人**(クラス、継承、インターフェース、ジェネリクス、ラムダなどは既知)
- **macOS 開発・Xcode・AppKit/SwiftUI は未経験**
- ゴール: ZoomacIt のコードを自力で読めて、自分で改修できるようになる

Java と本質的に同じ概念は **チートシート** で素早く流し、Swift 特有のもの(Optional、struct と class の使い分け、`@MainActor`、`Sendable`、capture list など)は **段落で丁寧に** 解説します。

## 読む順序

| Part | 章 | 内容 |
|---|---|---|
| **Part I** | [01-03](./part1-welcome/) | Swift とは / 環境構築 / A Swift Tour(ZoomacIt 版) |
| **Part II** | [04-31](./part2-language-guide/) | Language Guide(変数・型・関数・クラス・並行性・ジェネリクスなど) |
| **Part III** | [32-37](./part3-zoomacit-deep-dive/) | ZoomacIt 応用編(AppKit、Carbon API、ScreenCaptureKit ほか) |
| **Part IV** | [38-42](./part4-handson/) | ハンズオン(自分の手で機能を追加する) |

Part I → Part II → Part III → Part IV の順で読むのが推奨ですが、Java 経験者は **Part II の 🟢 マークの章は流し読み** で構いません。

### 章タイプ凡例

- 🟢 **チートシート章**: Java と本質的に同じ概念。表 + 短いコードで一気通貫
- 🟡 **丁寧章**: Swift 特有 or Java と挙動が違うもの。段落 + 実コード引用
- 🔴 **応用章**: macOS / AppKit / 並行性 / C 橋渡しなど Swift を超えた領域

## 全章一覧

### Part I — Welcome to Swift

- [01. Swift とは / なぜ ZoomacIt で学ぶか](./part1-welcome/01-what-is-swift.md) 🟡
- [02. 環境構築 — Xcode・xcodegen・make](./part1-welcome/02-environment.md) 🟡
- [03. A Swift Tour(ZoomacIt 版)](./part1-welcome/03-swift-tour.md) 🟡

### Part II — Language Guide

- [04. The Basics(変数・型・Optional 入門)](./part2-language-guide/04-the-basics.md) 🟢+🟡
- [05. Basic Operators](./part2-language-guide/05-basic-operators.md) 🟢
- [06. Strings and Characters](./part2-language-guide/06-strings-and-characters.md) 🟢+🟡
- [07. Collection Types](./part2-language-guide/07-collection-types.md) 🟢
- [08. Control Flow](./part2-language-guide/08-control-flow.md) 🟢+🟡
- [09. Functions](./part2-language-guide/09-functions.md) 🟢+🟡
- [10. Closures](./part2-language-guide/10-closures.md) 🟡
- [11. Enumerations](./part2-language-guide/11-enumerations.md) 🟡
- [12. Structures and Classes](./part2-language-guide/12-structures-and-classes.md) 🟡
- [13. Properties](./part2-language-guide/13-properties.md) 🟡
- [14. Methods](./part2-language-guide/14-methods.md) 🟢+🟡
- [15. Subscripts](./part2-language-guide/15-subscripts.md) 🟢
- [16. Inheritance](./part2-language-guide/16-inheritance.md) 🟢+🟡
- [17. Initialization](./part2-language-guide/17-initialization.md) 🟡
- [18. Deinitialization](./part2-language-guide/18-deinitialization.md) 🟡
- [19. Optional Chaining](./part2-language-guide/19-optional-chaining.md) 🟡
- [20. Error Handling](./part2-language-guide/20-error-handling.md) 🟡
- [21. Concurrency](./part2-language-guide/21-concurrency.md) 🔴
- [22. Type Casting](./part2-language-guide/22-type-casting.md) 🟢
- [23. Nested Types](./part2-language-guide/23-nested-types.md) 🟢
- [24. Extensions](./part2-language-guide/24-extensions.md) 🟡
- [25. Protocols](./part2-language-guide/25-protocols.md) 🟡
- [26. Generics](./part2-language-guide/26-generics.md) 🟢+🟡
- [27. Opaque Types](./part2-language-guide/27-opaque-types.md) 🟡
- [28. Automatic Reference Counting](./part2-language-guide/28-arc.md) 🟡
- [29. Memory Safety](./part2-language-guide/29-memory-safety.md) 🟡
- [30. Access Control](./part2-language-guide/30-access-control.md) 🟡
- [31. Advanced Operators](./part2-language-guide/31-advanced-operators.md) 🟢

### Part III — ZoomacIt 応用編

- [32. AppKit と SwiftUI の混在](./part3-zoomacit-deep-dive/32-appkit-vs-swiftui.md) 🔴
- [33. NSView を継承して描画する](./part3-zoomacit-deep-dive/33-nsview-drawing.md) 🔴
- [34. Carbon API と C 橋渡し](./part3-zoomacit-deep-dive/34-carbon-bridging.md) 🔴
- [35. ScreenCaptureKit と async/await](./part3-zoomacit-deep-dive/35-screencapturekit.md) 🔴
- [36. UserDefaults とシングルトン設定](./part3-zoomacit-deep-dive/36-userdefaults.md) 🔴
- [37. XCTest による単体テスト](./part3-zoomacit-deep-dive/37-xctest.md) 🔴

### Part IV — ハンズオン

- [38. 新しいペン色を追加する](./part4-handson/38-add-pen-color.md) 🟢
- [39. 新しいシェイプ(三角形)を追加](./part4-handson/39-add-shape.md) 🟡
- [40. 新しいホットキーアクション](./part4-handson/40-add-hotkey.md) 🟡
- [41. 設定タブを 1 つ増やす](./part4-handson/41-add-settings-tab.md) 🟡
- [42. 卒業課題: Magnifier Lens 機能](./part4-handson/42-magnifier-lens.md) 🔴

ハンズオンの解答例は [`answers/`](./answers/) 配下にあります。

## このリポジトリで動かしながら学ぶ

```bash
make build       # Debug ビルド
make test        # 単体テスト
make run         # ビルド + 起動
```

詳細は [02. 環境構築](./part1-welcome/02-environment.md) を参照。

## 参考資料

- Apple 公式: [The Swift Programming Language(Swift 6.0)](https://docs.swift.org/swift-book/)
- Apple 公式: [AppKit Documentation](https://developer.apple.com/documentation/appkit)
- ZoomacIt 設計ドキュメント: [`design/`](../design/)
