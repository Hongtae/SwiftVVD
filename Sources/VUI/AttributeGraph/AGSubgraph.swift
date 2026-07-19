//
//  File: AGSubgraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// MARK: - AGSubgraph

/// A group of AG nodes that are created and destroyed together.
///
/// Subgraph lifecycle handle for groups of AG nodes.
///
/// Must be created while an _AGGraph context is active (`_AGGraph.current != nil`).
/// The owning _AGGraph is captured at creation time and validated on `invalidate()`.
///
/// Wrap node-creation code in `AGSubgraph.withCurrent(subgraph) { ... }` to
/// automatically register every node created in that scope to this subgraph.
/// Call `invalidate()` to batch-remove all registered nodes at once.
///
/// Subgraphs form a parent/child tree: an AGSubgraph created while another is active
/// automatically becomes its child. `invalidate()` cascades depth-first,
/// so invalidating a parent also destroys all descendant subgraphs.
///
/// Typical use: ForEach item lifecycle:
/// ```swift
/// let subgraph = AGSubgraph()
/// AGSubgraph.withCurrent(subgraph) {
///     Content._makeView(view: itemGraph, inputs: inputs)
/// }
/// itemSubgraphs[id] = subgraph
///
/// // item removed:
/// itemSubgraphs[id]?.invalidate()
/// itemSubgraphs[id]?.removeFromParent()
/// itemSubgraphs[id] = nil
/// ```
final class AGSubgraphRef: @unchecked Sendable {
    private final class WeakAncestor {
        weak var value: AGSubgraphRef?

        init(_ value: AGSubgraphRef) {
            self.value = value
        }
    }

    private(set) var nodes: [AGAttribute] = []
    private(set) var children: [AGSubgraphRef] = []
    private(set) weak var parent: AGSubgraphRef? = nil
    private var secondaryAncestors: [WeakAncestor] = []
    private(set) var isValid: Bool = true
    private(set) var isInserted: Bool = true
    weak let graph: AGGraphRef?

    private static let currentStorage = _AGThreadLocal<AGSubgraphRef?>(nil)

    static var current: AGSubgraphRef? {
        currentStorage.value
    }

    @discardableResult
    static func withCurrent<R>(_ subgraph: AGSubgraphRef?, _ body: () throws -> R) rethrows -> R {
        try currentStorage.withValue(subgraph) {
            try body()
        }
    }

    init() {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph must be created within an active _AGGraph context.")
        }
        self.graph = graph
        if let parent = AGSubgraphRef.current {
            parent.children.append(self)
            self.parent = parent
        }
    }

    func register(_ id: AGAttribute) {
        nodes.append(id)
        graph?.setSubgraph(self, for: id)
    }

    func invalidate() {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph.invalidate() called outside an active _AGGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.invalidate() called from a different _AGGraph than the one that owns this subgraph.")
        }
        guard isValid else { return }

        children.forEach {
            $0.invalidate()
            if $0.parent === self {
                $0.parent = nil
            }
            $0.removeSecondaryAncestor(self)
        }
        children.removeAll()

        nodes.forEach {
            graph.removeNode($0)
        }
        nodes.removeAll()
        isValid = false
    }

    func removeFromParent() {
        parent?.children.removeAll { $0 === self }
        parent = nil
        for ancestor in secondaryAncestors {
            ancestor.value?.children.removeAll { $0 === self }
        }
        secondaryAncestors.removeAll()
    }

    func addSecondaryChild(_ child: AGSubgraphRef) {
        guard isValid, child.isValid else { return }
        guard graph === child.graph else {
            fatalError("AGSubgraph.addSecondaryChild(_:) cannot attach a subgraph owned by a different graph.")
        }
        guard child !== self else {
            fatalError("AGSubgraph.addSecondaryChild(_:) cannot attach a subgraph to itself.")
        }
        if child.parent === self ||
            child.secondaryAncestors.contains(where: { $0.value === self }) {
            return
        }
        children.append(child)
        child.secondaryAncestors.append(WeakAncestor(self))
    }

    private func removeSecondaryAncestor(_ ancestor: AGSubgraphRef) {
        secondaryAncestors.removeAll { edge in
            edge.value == nil || edge.value === ancestor
        }
    }

    func update(flags: UInt32 = 1) {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph.update() called outside an active _AGGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.update() called from a different _AGGraph than the one that owns this subgraph.")
        }
        graph.updateSubgraph(self, flags: flags)
    }

    func willRemove() {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph.willRemove() called outside an active _AGGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.willRemove() called from a different _AGGraph than the one that owns this subgraph.")
        }
        guard isValid, isInserted else { return }
        graph.willRemoveSubgraph(self)
        isInserted = false
    }

    func didReinsert() {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph.didReinsert() called outside an active _AGGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.didReinsert() called from a different _AGGraph than the one that owns this subgraph.")
        }
        guard isValid, !isInserted else { return }
        graph.didReinsertSubgraph(self)
        isInserted = true
    }
}

typealias AGSubgraph = AGSubgraphRef

func _AGSubgraphIsValid(_ subgraph: AGSubgraphRef) -> Bool {
    subgraph.isValid
}

func AGSubgraphIsValid(_ subgraph: AGSubgraphRef) -> Bool {
    _AGSubgraphIsValid(subgraph)
}
