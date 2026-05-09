# samples/ch26-generics

このディレクトリは **Ch26. Generics** の補助サンプルです。

## 目的

ZoomacIt 本体には、ジェネリクスを学ぶうえで「自分で型パラメータを宣言した型」の良い実例がほとんどありません。本体が利用しているのは、Swift 標準ライブラリ側で既に型パラメータが宣言されている `Array<Element>` や `Optional<Wrapped>` の **利用側** がほとんどです。

そこで、ジェネリクスを「自分で書く側」の感覚をつかむために、教材専用のサンプルとして 3 つの汎用データ構造を書き起こしました。いずれも本体には組み込まれず、独立して `swift` コマンドで実行できます。

## ファイルと対応トピック

| ファイル | 扱う Generics 機能 |
|----------|--------------------|
| `Stack.swift` | 基本的なジェネリック型 (`struct Stack<Element>`)。型パラメータの命名慣習 |
| `Queue.swift` | 別の型パラメータ名 (`struct Queue<T>`) と、配列を内部に持つ典型構造 |
| `BinaryTree.swift` | **型制約**つきジェネリック型 (`class BinaryTree<Element: Comparable>`)。Comparable に基づく順序比較 |

## コンパイル・実行方法

各ファイルは末尾に `// MARK: - Demo` セクションを持ち、ファイル単独で実行できます。`swift` コマンドにファイルパスを渡すだけです。

```bash
cd learning-swift/samples/ch26-generics
swift Stack.swift
swift Queue.swift
swift BinaryTree.swift
```

`swift` コマンドはトップレベルコードをそのまま実行する仕組みのため、`main` 関数は不要です。Demo セクションのコードがそのまま実行されます。

## 注意

これらは教材専用のサンプルです。ZoomacIt 本体のコードベース (`src/ZoomacIt/`) からは参照されておらず、ビルドターゲットにも含まれていません。`make build` の対象外です。
