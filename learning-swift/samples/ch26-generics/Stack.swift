// Stack.swift
//
// これは教材専用ファイルです。ZoomacIt 本体には組み込まれません。
// `swift Stack.swift` で単独実行できます。
//
// このファイルでは、最も基本的なジェネリック型である Stack<Element> を実装します。
// 型パラメータ Element には任意の型を指定でき、利用側で Stack<Int>、Stack<String>
// のようにインスタンス化できます。

import Foundation

/// LIFO (Last-In, First-Out) スタックのジェネリック実装。
///
/// Swift 標準ライブラリの `Array<Element>` と同じく、`Element` という命名慣習に従う。
/// 単一要素の型パラメータには `Element`、関数のパラメータには `T` が好まれる。
struct Stack<Element> {

    /// 内部表現は配列。push は append、pop は removeLast に委譲する。
    private var storage: [Element] = []

    /// 要素数。
    var count: Int { storage.count }

    /// 空かどうか。
    var isEmpty: Bool { storage.isEmpty }

    /// 末尾に要素を積む。
    mutating func push(_ element: Element) {
        storage.append(element)
    }

    /// 末尾の要素を取り出して返す。空なら nil。
    @discardableResult
    mutating func pop() -> Element? {
        storage.popLast()
    }

    /// 末尾の要素を取り出さずに覗き見する。空なら nil。
    func peek() -> Element? {
        storage.last
    }
}

// MARK: - Demo

// Stack<Int> としてインスタンス化。
var intStack = Stack<Int>()
intStack.push(1)
intStack.push(2)
intStack.push(3)
print("intStack.count =", intStack.count)        // 3
print("intStack.peek() =", intStack.peek() ?? -1) // 3
print("intStack.pop() =", intStack.pop() ?? -1)   // 3
print("intStack.pop() =", intStack.pop() ?? -1)   // 2
print("intStack.count =", intStack.count)        // 1

// 同じ Stack 型から、Stack<String> もインスタンス化できる。
// 別の型パラメータで実体化されるため、intStack と stringStack は別の型として扱われる。
var stringStack = Stack<String>()
stringStack.push("apple")
stringStack.push("banana")
print("stringStack.peek() =", stringStack.peek() ?? "nil")  // banana
print("stringStack.isEmpty =", stringStack.isEmpty)         // false
