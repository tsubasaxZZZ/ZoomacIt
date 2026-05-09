// Queue.swift
//
// これは教材専用ファイルです。ZoomacIt 本体には組み込まれません。
// `swift Queue.swift` で単独実行できます。
//
// このファイルでは FIFO キューを通じて、Stack.swift とは別の型パラメータ命名 (`T`) を
// 使った場合の感触を確認します。Swift では、型パラメータ名は意味を伝えるなら任意の
// 識別子を使えます。慣習として、単一汎用パラメータには `T`、コンテナの要素には
// `Element`、辞書のキー/値には `Key` / `Value` が用いられます。

import Foundation

/// FIFO (First-In, First-Out) キューのジェネリック実装。
///
/// 実装の素朴さを優先し、内部配列の先頭を removeFirst で取り出す。
/// 計算量は dequeue が O(n) になるため、本物のプロダクション実装では
/// 二本のスタックや循環バッファを使うが、本サンプルでは可読性を優先する。
struct Queue<T> {

    private var storage: [T] = []

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    /// 末尾に要素を追加する。
    mutating func enqueue(_ element: T) {
        storage.append(element)
    }

    /// 先頭の要素を取り出して返す。空なら nil。
    @discardableResult
    mutating func dequeue() -> T? {
        guard !storage.isEmpty else { return nil }
        return storage.removeFirst()
    }

    /// 先頭の要素を取り出さずに覗き見する。空なら nil。
    func peek() -> T? {
        storage.first
    }
}

// MARK: - Demo

var queue = Queue<String>()
queue.enqueue("first")
queue.enqueue("second")
queue.enqueue("third")
print("queue.count =", queue.count)            // 3
print("queue.peek() =", queue.peek() ?? "nil")  // first
print("queue.dequeue() =", queue.dequeue() ?? "nil")  // first
print("queue.dequeue() =", queue.dequeue() ?? "nil")  // second
print("queue.peek() =", queue.peek() ?? "nil")  // third

// 別の要素型でもそのまま使える。
var doubleQueue = Queue<Double>()
doubleQueue.enqueue(1.1)
doubleQueue.enqueue(2.2)
print("doubleQueue.dequeue() =", doubleQueue.dequeue() ?? -1)  // 1.1
