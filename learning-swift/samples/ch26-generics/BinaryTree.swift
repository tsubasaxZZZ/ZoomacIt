// BinaryTree.swift
//
// これは教材専用ファイルです。ZoomacIt 本体には組み込まれません。
// `swift BinaryTree.swift` で単独実行できます。
//
// このファイルでは、型制約 (type constraint) のあるジェネリック型を実装します。
// 二分探索木は要素を大小比較できる必要があるため、Element に Comparable 制約を付けます。
// 制約を付けることで、型パラメータ Element に対して `<` や `>` を使えるようになります。

import Foundation

/// ジェネリック二分探索木 (Binary Search Tree)。
///
/// `Element: Comparable` という制約により、要素同士を `<` で比較できる。
/// この制約は Java の `class BinaryTree<E extends Comparable<E>>` に相当するが、
/// Swift では型消去がないため、実行時にも `Element` の具体的な型情報が保持される。
final class BinaryTree<Element: Comparable> {

    private final class Node {
        var value: Element
        var left: Node?
        var right: Node?

        init(value: Element) {
            self.value = value
        }
    }

    private var root: Node?

    /// 要素を木に挿入する。重複する値は無視する。
    func insert(_ value: Element) {
        root = insert(value, into: root)
    }

    private func insert(_ value: Element, into node: Node?) -> Node {
        guard let node else {
            return Node(value: value)
        }
        if value < node.value {
            node.left = insert(value, into: node.left)
        } else if value > node.value {
            node.right = insert(value, into: node.right)
        }
        // value == node.value の場合は何もしない。
        return node
    }

    /// 木に要素が含まれるかを判定する。
    func contains(_ value: Element) -> Bool {
        var current = root
        while let node = current {
            if value == node.value {
                return true
            } else if value < node.value {
                current = node.left
            } else {
                current = node.right
            }
        }
        return false
    }

    /// 中順 (in-order) で要素を配列として返す。Comparable 制約に基づいてソート済み。
    func inOrder() -> [Element] {
        var result: [Element] = []
        traverseInOrder(root, into: &result)
        return result
    }

    private func traverseInOrder(_ node: Node?, into result: inout [Element]) {
        guard let node else { return }
        traverseInOrder(node.left, into: &result)
        result.append(node.value)
        traverseInOrder(node.right, into: &result)
    }
}

// MARK: - Demo

let tree = BinaryTree<Int>()
[5, 3, 8, 1, 4, 7, 9].forEach { tree.insert($0) }

print("tree.contains(4) =", tree.contains(4))   // true
print("tree.contains(6) =", tree.contains(6))   // false
print("tree.inOrder() =", tree.inOrder())       // [1, 3, 4, 5, 7, 8, 9]

// String も Comparable に準拠するため、そのまま使える。
let stringTree = BinaryTree<String>()
["banana", "apple", "cherry"].forEach { stringTree.insert($0) }
print("stringTree.inOrder() =", stringTree.inOrder())  // ["apple", "banana", "cherry"]

// 次の行のコメントを外すと、Comparable に準拠しない型ではコンパイルエラーになる。
// struct NotComparable {}
// let invalid = BinaryTree<NotComparable>()
// → "type 'NotComparable' does not conform to protocol 'Comparable'"
