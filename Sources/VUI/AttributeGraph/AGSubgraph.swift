//
//  File: AGSubgraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// MARK: - AGSubgraph

/// Owns a group of graph nodes that share one insertion and invalidation lifecycle.
///
/// Must be created while an _AGGraph context is active (`_AGGraph.current != nil`).
/// The owning _AGGraph is captured at creation time and validated on `invalidate()`.
///
/// Wrap node-creation code in `AGSubgraph.withCurrent(subgraph) { ... }` to
/// automatically register every node created in that scope to this subgraph.
/// Call `invalidate()` to batch-remove all registered nodes at once.
///
/// Subgraphs form a parent/child tree. An AGSubgraph created with the default
/// parent while another is active becomes its child. `invalidate()` visits the
/// parent before its newest child and destroys each subgraph's newest node first.
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
    private var pendingFlags: UInt32 = 0
    private var descendantPendingFlags: UInt32 = 0
    private(set) var isValid: Bool = true
    private(set) var isInserted: Bool = true
    private var invalidationPending = false
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

    init(parent explicitParent: AGSubgraphRef? = AGSubgraphRef.current) {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph must be created within an active _AGGraph context.")
        }
        self.graph = graph
        if let parent = explicitParent {
            guard parent.graph === graph else {
                fatalError("AGSubgraph parent must belong to the active _AGGraph.")
            }
            parent.children.append(self)
            self.parent = parent
        }
    }

    func register(_ id: AGAttribute) {
        nodes.append(id)
        graph?.setSubgraph(self, for: id)
    }

    func markPending(flags: UInt32) {
        guard isValid, flags != 0 else { return }
        let addedFlags = flags & ~pendingFlags
        guard addedFlags != 0 else { return }
        pendingFlags |= addedFlags
        propagateDescendantPending(pendingFlags | descendantPendingFlags)
    }

    func hasPending(flags: UInt32) -> Bool {
        isValid && (pendingFlags | descendantPendingFlags) & flags != 0
    }

    func consumeLocalPendingFlags(matching flags: UInt32) -> UInt32 {
        let selected = pendingFlags & flags
        pendingFlags &= ~selected
        return selected
    }

    func consumeDescendantPendingFlags(matching flags: UInt32) -> UInt32 {
        let selected = descendantPendingFlags & flags
        descendantPendingFlags &= ~selected
        return selected
    }

    private func propagateDescendantPending(_ flags: UInt32) {
        var work: [AGSubgraphRef] = []
        if let parent {
            work.append(parent)
        }
        for ancestor in secondaryAncestors {
            if let ancestor = ancestor.value {
                work.append(ancestor)
            }
        }

        var visited: Set<ObjectIdentifier> = []
        while let ancestor = work.popLast() {
            guard ancestor.isValid,
                  visited.insert(ObjectIdentifier(ancestor)).inserted else {
                continue
            }
            let addedFlags = flags & ~ancestor.descendantPendingFlags
            guard addedFlags != 0 else { continue }
            ancestor.descendantPendingFlags |= addedFlags
            if let parent = ancestor.parent {
                work.append(parent)
            }
            for secondary in ancestor.secondaryAncestors {
                if let secondary = secondary.value {
                    work.append(secondary)
                }
            }
        }
    }

    func invalidate() {
        guard let graph = _AGGraph.current else {
            fatalError("AGSubgraph.invalidate() called outside an active _AGGraph context.")
        }
        guard graph === self.graph else {
            fatalError("AGSubgraph.invalidate() called from a different _AGGraph than the one that owns this subgraph.")
        }
        guard isValid else { return }

        graph.requestSubgraphInvalidation(self)
    }

    func _beginInvalidation() -> Bool {
        guard isValid else { return false }
        isValid = false
        invalidationPending = true
        for child in children {
            _ = child._beginInvalidation()
        }
        return true
    }

    func _finishInvalidation(removingNodes: Bool = true) {
        guard invalidationPending else { return }

        var work: [AGSubgraphRef] = [self]
        var ordered: [AGSubgraphRef] = []
        var visited: Set<ObjectIdentifier> = []
        while let subgraph = work.popLast() {
            guard subgraph.invalidationPending,
                  visited.insert(ObjectIdentifier(subgraph)).inserted else {
                continue
            }
            ordered.append(subgraph)
            for child in subgraph.children where child.invalidationPending {
                work.append(child)
            }
        }

        if removingNodes, let graph {
            var removals: [_AGGraph.PreparedNodeRemoval] = []
            for subgraph in ordered {
                for node in subgraph.nodes.reversed() {
                    removals.append(graph.prepareNodeRemoval(node))
                }
            }
            for removal in removals {
                graph.finishNodeRemoval(removal)
            }
        }

        for subgraph in ordered {
            for child in subgraph.children {
                if child.parent === subgraph {
                    child.parent = nil
                }
                child.removeSecondaryAncestor(subgraph)
            }
            subgraph.children.removeAll()
            subgraph.nodes.removeAll()
            subgraph.isValid = false
            subgraph.invalidationPending = false
        }
    }

    func removeFromParent() {
        parent?.children.removeAll { $0 === self }
        parent = nil
        for ancestor in secondaryAncestors {
            ancestor.value?.children.removeAll { $0 === self }
        }
        secondaryAncestors.removeAll()
    }

    /// Reattaches a valid child to this subgraph's primary ownership tree.
    func addChild(_ child: AGSubgraphRef) {
        guard isValid, child.isValid else { return }
        guard graph === child.graph else {
            fatalError("AGSubgraph.addChild(_:) cannot attach a subgraph owned by a different graph.")
        }
        guard child !== self else {
            fatalError("AGSubgraph.addChild(_:) cannot attach a subgraph to itself.")
        }
        if child.parent === self {
            return
        }
        child.removeFromParent()
        children.append(child)
        child.parent = self
        let childPending = child.pendingFlags | child.descendantPendingFlags
        if childPending != 0 {
            let addedFlags = childPending & ~descendantPendingFlags
            if addedFlags != 0 {
                descendantPendingFlags |= addedFlags
                propagateDescendantPending(
                    pendingFlags | descendantPendingFlags
                )
            }
        }
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
        let childPending = child.pendingFlags | child.descendantPendingFlags
        if childPending != 0 {
            let addedFlags = childPending & ~descendantPendingFlags
            if addedFlags != 0 {
                descendantPendingFlags |= addedFlags
                propagateDescendantPending(
                    pendingFlags | descendantPendingFlags
                )
            }
        }
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
