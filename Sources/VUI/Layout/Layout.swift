//
//  File: Layout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol LeafViewLayout {
    func spacing() -> Spacing
    func sizeThatFits(in proposal: _ProposedSize) -> CGSize
}

extension LeafViewLayout {
    func spacing() -> Spacing {
        Spacing()
    }

    static func makeLeafLayout(
        _ outputs: inout _ViewOutputs,
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) {
        guard inputs.requestsLayoutComputer else { return }
        guard let graph = _AGGraph.current else {
            fatalError("\(self).makeLeafLayout called outside an active _AGGraph context.")
        }

        let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
            LeafLayoutComputer(_view: view._attribute)
        )
        outputs._layoutComputer = OptionalAttribute(layoutComputer)
    }
}

private struct LeafLayoutComputer<Leaf: LeafViewLayout>: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _view: Attribute<Leaf>

    mutating func updateValue() {
        update(
            to: LeafLayoutEngine(
                view: _view.value,
                cache: ViewSizeCache()
            )
        )
    }
}

struct LeafLayoutEngine<Leaf: LeafViewLayout>: LayoutEngine {
    var view: Leaf
    var cache: ViewSizeCache

    func spacing() -> Spacing {
        view.spacing()
    }

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        cache.get(proposal) {
            view.sizeThatFits(in: proposal)
        }
    }
}

// MARK: - Layout AG rules

/// Computes one coherent placement array from the container geometry and
/// layout computer. Per-child rules index this array instead of recomputing
/// placement independently.
struct LayoutChildGeometries: Rule, AsyncAttribute {
    typealias Value = [ViewGeometry]

    var _parentSize: Attribute<ViewSize>
    var _parentPosition: Attribute<CGPoint>
    var _layoutComputer: Attribute<LayoutComputer>

    init(
        parentSize: Attribute<ViewSize>,
        parentPosition: Attribute<CGPoint>,
        layoutComputer: Attribute<LayoutComputer>
    ) {
        _parentSize = parentSize
        _parentPosition = parentPosition
        _layoutComputer = layoutComputer
    }

    var value: [ViewGeometry] {
        let layoutComputer = _layoutComputer.value
        return layoutComputer.childGeometries(
            at: _parentSize.value,
            origin: _parentPosition.value
        )
    }
}

/// Selects one child geometry from the aggregate placement result. Position
/// and size remain direct projections of this same value, preserving their
/// shared invalidation boundary.
private struct LayoutChildGeometry: Rule, AsyncAttribute {
    typealias Value = ViewGeometry

    var _childGeometries: Attribute<[ViewGeometry]>
    var index: Int

    var value: ViewGeometry {
        let childGeometries = _childGeometries.value
        precondition(
            index >= 0 && index < childGeometries.count
        )
        return childGeometries[index]
    }
}

/// Resolves a stable dynamic-container identity to the current flattened child
/// geometry. Once published, the last geometry remains stable while the item is
/// retained outside the active layout prefix.
private struct DynamicLayoutViewChildGeometry: StatefulRule, AsyncAttribute {
    typealias Value = ViewGeometry

    var _containerInfo: Attribute<DynamicContainer.Info>
    var _childGeometries: Attribute<[ViewGeometry]>
    var id: DynamicContainerID

    mutating func updateValue() {
        let info = _containerInfo.value
        let currentGeometries = _childGeometries.value
        if let index = info.viewIndex(id: id),
           currentGeometries.indices.contains(index) {
            _AGGraph.setStatefulOutput(currentGeometries[index])
        } else if _AGGraph.currentStatefulOutput(ViewGeometry.self) == nil {
            _AGGraph.setStatefulOutput(ViewGeometry.zero)
        }
    }
}

/// Stable key for one flattened view produced by a dynamic container item.
///
/// `uniqueId` identifies the retained item across reconciliation passes, while
/// `viewIndex` selects one output inside a non-unary item.
struct DynamicContainerID: Comparable, Hashable {
    var uniqueId: UInt32
    var viewIndex: Int32

    init(uniqueId: UInt32, viewIndex: Int32) {
        self.uniqueId = uniqueId
        self.viewIndex = viewIndex
    }

    static func < (lhs: DynamicContainerID, rhs: DynamicContainerID) -> Bool {
        if lhs.uniqueId != rhs.uniqueId {
            return lhs.uniqueId < rhs.uniqueId
        }
        return lhs.viewIndex < rhs.viewIndex
    }
}

/// Produces the layout computer for a static child list. The rule is installed
/// before child enumeration and receives the collected child attributes
/// afterward, allowing each child to consume projections of the aggregate
/// placement result without introducing an independent placement owner.
private struct StaticLayoutComputer<L: Layout>: StatefulRule, AsyncAttribute, CustomStringConvertible {
    typealias Value = LayoutComputer

    var _layout: Attribute<L>
    var _environment: Attribute<EnvironmentValues>
    var childAttributes: [LayoutProxyAttributes]

    var description: String {
        "\(L.self) → LayoutComputer"
    }

    mutating func updateValue() {
        updateLayoutComputer(
            layout: _layout.value,
            environment: _environment,
            attributes: childAttributes
        )
    }
}

/// Describes one identity-bearing item reconciled by a dynamic container.
protocol DynamicContainerItem {
    var count: Int { get }
    var needsTransitions: Bool { get }
    var zIndex: Double { get }
    func matchesIdentity(of other: Self) -> Bool
    static var supportsReuse: Bool { get }
    func canBeReused(by other: Self) -> Bool
    var list: Attribute<any ViewList>? { get }
    var viewID: _ViewList_ID? { get }
}

extension DynamicContainerItem {
    var needsTransitions: Bool { false }
    var zIndex: Double { 0 }
    static var supportsReuse: Bool { false }
    func canBeReused(by other: Self) -> Bool { false }
    var list: Attribute<any ViewList>? { nil }
    var viewID: _ViewList_ID? { nil }
}

class DynamicStorage {
    var contentType: Any.Type {
        fatalError("abstract")
    }

    var identifier: AnyHashable {
        fatalError("abstract")
    }

    var needsTransitions: Bool {
        fatalError("abstract")
    }

    func matchesIdentity(of other: DynamicStorage) -> Bool {
        fatalError("abstract")
    }

    func makeView<A>(
        uniqueId: UInt32,
        container: Attribute<DynamicContainer.Info>,
        inputs: _ViewInputs,
        adaptor: A.Type
    ) -> _ViewOutputs where A: DynamicContainerAdaptor,
        A.Item == AnyDynamicItem {
        fatalError("abstract")
    }

    func visitContent<Visitor>(
        _ visitor: inout Visitor,
        phase: TransitionPhase
    ) where Visitor: ViewVisitor {
        fatalError("abstract")
    }
}

private final class IdentifiedItemStorage<Content, Identifier>: DynamicStorage
    where Content: View, Identifier: Hashable {
    var content: Content
    var _identifier: Identifier

    init(content: Content, identifier: Identifier) {
        self.content = content
        self._identifier = identifier
    }

    override var contentType: Any.Type {
        Content.self
    }

    override var identifier: AnyHashable {
        AnyHashable(_identifier)
    }

    override var needsTransitions: Bool {
        false
    }

    override func matchesIdentity(of other: DynamicStorage) -> Bool {
        guard let other = other as? IdentifiedItemStorage else {
            return false
        }
        return _identifier == other._identifier
    }

    override func makeView<A>(
        uniqueId: UInt32,
        container: Attribute<DynamicContainer.Info>,
        inputs: _ViewInputs,
        adaptor: A.Type
    ) -> _ViewOutputs where A: DynamicContainerAdaptor,
        A.Item == AnyDynamicItem {
        guard let graph = _AGGraph.current else {
            fatalError(
                "IdentifiedItemStorage.makeView called outside an active AG context."
            )
        }
        let child: Attribute<Content> = graph.makeStatefulRule(
            AnyDynamicChild<A, Content>(
                _info: container,
                uniqueId: uniqueId,
                item: nil
            )
        )
        return Content._makeView(
            view: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }

    override func visitContent<Visitor>(
        _ visitor: inout Visitor,
        phase: TransitionPhase
    ) where Visitor: ViewVisitor {
        visitor.visit(content)
    }
}

private struct MakeStorageVisitor1<Identifier>: ViewVisitor
    where Identifier: Hashable {
    var identifier: Identifier
    var storage: DynamicStorage?

    mutating func visit<Content>(_ view: Content) where Content: View {
        storage = makeStorage(content: view, identifier: identifier)
    }
}

private func makeStorage<Content, Identifier>(
    content: Content,
    identifier: Identifier
) -> DynamicStorage where Content: View, Identifier: Hashable {
    guard let anyView = content as? AnyView else {
        return IdentifiedItemStorage(
            content: content,
            identifier: identifier
        )
    }
    var visitor = MakeStorageVisitor1<Identifier>(
        identifier: identifier,
        storage: nil
    )
    anyView.visitContent(&visitor)
    guard let storage = visitor.storage else {
        preconditionFailure("AnyView must contain one concrete View value.")
    }
    return storage
}

struct AnyDynamicItem: DynamicContainerItem {
    var storage: DynamicStorage
    var layoutPriority: Double?
    var zIndex: Double

    init<Content, Identifier>(_ content: Content, id: Identifier)
        where Content: View, Identifier: Hashable {
        storage = makeStorage(content: content, identifier: id)
        layoutPriority = nil
        zIndex = 0
    }

    var count: Int { 1 }
    var needsTransitions: Bool { storage.needsTransitions }

    func matchesIdentity(of other: AnyDynamicItem) -> Bool {
        if storage === other.storage || storage.matchesIdentity(of: other.storage) {
            return true
        }
        return storage.contentType == other.storage.contentType &&
            storage.identifier == other.storage.identifier
    }

    static var supportsReuse: Bool { true }

    func canBeReused(by other: AnyDynamicItem) -> Bool {
        storage.contentType == other.storage.contentType
    }

    func makeView<A>(
        uniqueId: UInt32,
        container: Attribute<DynamicContainer.Info>,
        inputs: _ViewInputs,
        adaptor: A.Type
    ) -> _ViewOutputs where A: DynamicContainerAdaptor,
        A.Item == AnyDynamicItem {
        storage.makeView(
            uniqueId: uniqueId,
            container: container,
            inputs: inputs,
            adaptor: adaptor
        )
    }
}

private struct AnyDynamicChild<A, Content>: StatefulRule
    where A: DynamicContainerAdaptor,
          A.Item == AnyDynamicItem,
          Content: View {
    typealias Value = Content

    var _info: Attribute<DynamicContainer.Info>
    var uniqueId: UInt32
    var item: AnyDynamicItem?

    private struct UpdateVisitor: ViewVisitor {
        var context: RuleContext<Content>

        mutating func visit<V>(_ view: V) where V: View {
            guard let content = view as? Content else {
                preconditionFailure(
                    "A reusable dynamic item changed its concrete content type."
                )
            }
            context.value = content
        }
    }

    mutating func updateValue() {
        let info = _info.value
        guard let itemInfo = info.item(for: uniqueId),
              let phase = itemInfo.phase else {
            return
        }
        let currentItem = itemInfo.for(A.self).item
        item = currentItem
        var visitor = UpdateVisitor(context: context)
        currentItem.storage.visitContent(&visitor, phase: phase)
    }
}

/// Separates item enumeration and item-layout lifetime from generic container
/// reconciliation.
protocol DynamicContainerAdaptor {
    associatedtype Item: DynamicContainerItem
    associatedtype Items
    associatedtype ItemLayout

    static var maxUnusedItems: Int { get }
    mutating func updatedItems() -> Items?
    func foreachItem(items: Items, _ body: (Item) -> Void)
    static func containsItem(_ items: Items, _ item: Item) -> Bool
    func makeItemLayout(
        item: Item,
        uniqueId: UInt32,
        inputs: _ViewInputs,
        containerInfo: Attribute<DynamicContainer.Info>,
        containerInputs: (inout _ViewInputs) -> Void
    ) -> (_ViewOutputs, ItemLayout)
    func removeItemLayout(uniqueId: UInt32, itemLayout: ItemLayout)
}

extension DynamicContainerAdaptor {
    static var maxUnusedItems: Int { 0 }
}

extension DynamicContainerAdaptor where Item == Items {
    func foreachItem(items: Items, _ body: (Item) -> Void) {
        body(items)
    }

    static func containsItem(_ items: Items, _ item: Item) -> Bool {
        items.matchesIdentity(of: item)
    }
}

extension DynamicContainerAdaptor where Items: Collection, Items.Element == Item {
    func foreachItem(items: Items, _ body: (Item) -> Void) {
        for item in items {
            body(item)
        }
    }

    static func containsItem(_ items: Items, _ item: Item) -> Bool {
        items.contains { $0.matchesIdentity(of: item) }
    }
}

/// Invalidates the owning dynamic-container rule after every registered
/// removal animation releases the listener.
final class DynamicAnimationListener: AnimationListener, @unchecked Sendable {
    private weak var viewGraph: ViewGraph?
    private var asyncSignal: AGWeakAttribute
    private var count: Int

    override init() {
        guard let graph = _AGGraph.current,
              let currentAttribute = _AGGraph.currentRuleContextAttribute,
              let asyncSignal = graph.weakAttributeIfValid(
                  for: currentAttribute
              ) else {
            fatalError(
                "DynamicAnimationListener requires a live dynamic-container rule."
            )
        }
        self.viewGraph = GraphHost.currentHost as? ViewGraph
        self.asyncSignal = asyncSignal
        self.count = 0
    }

    var isComplete: Bool {
        count == 0
    }

    func beginTrackingAnimations() {
        animationWasAdded()
        Update.enqueueAction { [weak self] in
            self?.animationWasRemoved()
        }
    }

    func detachFromViewGraph() {
        viewGraph = nil
    }

    override func animationWasAdded() {
        count += 1
    }

    override func animationWasRemoved() {
        count -= 1
        guard count == 0, let viewGraph else {
            return
        }
        viewGraph.continueTransaction(invalidating: asyncSignal)
    }
}

/// Dynamic container storage used by DynamicContainerInfo.
enum DynamicContainer {
    /// Retained item state shared by every dynamic-container adaptor. A nil
    /// phase denotes an unused item outside the active and removed prefixes.
    class ItemInfo {
        var subgraph: AGSubgraph
        var uniqueId: UInt32
        var viewCount: Int32
        var outputs: _ViewOutputs
        var needsTransitions: Bool
        var listener: DynamicAnimationListener?
        var zIndex: Double
        var removalOrder: UInt32
        var precedingViewCount: Int32
        var resetSeed: UInt32
        var phase: TransitionPhase?

        init(
            subgraph: AGSubgraph,
            uniqueId: UInt32,
            viewCount: Int32,
            outputs: _ViewOutputs,
            needsTransitions: Bool = false,
            listener: DynamicAnimationListener? = nil,
            zIndex: Double = 0,
            removalOrder: UInt32 = 0,
            precedingViewCount: Int32 = 0,
            resetSeed: UInt32 = 0,
            phase: TransitionPhase? = .identity
        ) {
            self.subgraph = subgraph
            self.uniqueId = uniqueId
            self.viewCount = viewCount
            self.outputs = outputs
            self.needsTransitions = needsTransitions
            self.listener = listener
            self.zIndex = zIndex
            self.removalOrder = removalOrder
            self.precedingViewCount = precedingViewCount
            self.resetSeed = resetSeed
            self.phase = phase
        }

        func `for`<A: DynamicContainerAdaptor>(_ type: A.Type) -> _ItemInfo<A> {
            guard let item = self as? _ItemInfo<A> else {
                preconditionFailure(
                    "Dynamic container item does not belong to \(A.self)."
                )
            }
            return item
        }

        func invalidate() {
            guard let graph = _AGGraph.current else {
                fatalError("DynamicContainer.ItemInfo.invalidate() called outside an active _AGGraph context.")
            }
            Update.begin()
            defer { Update.end() }
            subgraph.willRemove()
            subgraph.invalidate()
            graph.drainActionOutbox()
            subgraph.removeFromParent()
        }
    }

    /// Adds the adaptor item and adaptor-owned layout lifetime to the common
    /// retained state without type erasure.
    final class _ItemInfo<A: DynamicContainerAdaptor>: ItemInfo {
        var item: A.Item
        var itemLayout: A.ItemLayout

        init(
            item: A.Item,
            itemLayout: A.ItemLayout,
            subgraph: AGSubgraph,
            uniqueId: UInt32,
            viewCount: Int32,
            phase: TransitionPhase,
            needsTransitions: Bool,
            outputs: _ViewOutputs
        ) {
            self.item = item
            self.itemLayout = itemLayout
            super.init(
                subgraph: subgraph,
                uniqueId: uniqueId,
                viewCount: viewCount,
                outputs: outputs,
                needsTransitions: needsTransitions,
                phase: phase
            )
        }
    }

    /// Stores items, the numeric-id index, display ordering, active-suffix
    /// counts, the unary fast-path flag, and the change seed. Equality compares
    /// only the seed.
    struct Info: Equatable, _AGTypeDescriptorEquatable {
        var items: [ItemInfo] = []
        var indexMap: [UInt32: Int] = [:]
        var displayMap: [UInt32]?
        var removedCount: Int = 0
        var unusedCount: Int = 0
        var allUnary: Bool = true
        var seed: UInt32 = 0

        static func == (lhs: Info, rhs: Info) -> Bool {
            lhs.seed == rhs.seed
        }

        func viewIndex(id: DynamicContainerID) -> Int? {
            guard let itemIndex = indexMap[id.uniqueId],
                  items.indices.contains(itemIndex) else {
                return nil
            }
            // The identifier producer owns the per-item range invariant. This
            // lookup only composes the item's flattened base with that offset.
            return Int(items[itemIndex].precedingViewCount + id.viewIndex)
        }

        func item(for uniqueId: UInt32) -> ItemInfo? {
            guard let index = indexMap[uniqueId],
                  items.indices.contains(index) else {
                return nil
            }
            return items[index]
        }

        func item(for subgraph: AGSubgraph) -> ItemInfo? {
            items.first { $0.subgraph === subgraph }
        }

        var activeItems: ArraySlice<ItemInfo> {
            let activeEnd = max(0, items.count - unusedCount - removedCount)
            return items.prefix(activeEnd)
        }

        var activeAndRemovedItems: ArraySlice<ItemInfo> {
            let retainedEnd = max(0, items.count - unusedCount)
            return items.prefix(retainedEnd)
        }

        var displayItems: [ItemInfo] {
            let retainedCount = max(0, items.count - unusedCount)
            guard retainedCount > 0 else { return [] }
            if let displayMap {
                // The map begins with the active-only layout segment and ends
                // with the retained-inclusive display segment.
                return displayMap.suffix(retainedCount).compactMap { index in
                    let index = Int(index)
                    return items.indices.contains(index) ? items[index] : nil
                }
            }
            let activeCount = max(0, retainedCount - removedCount)
            // Removed items render below their active replacements. This lets
            // insertion and removal opacity compose independently instead of
            // the outgoing opaque surface masking the incoming one.
            return Array(items[activeCount..<retainedCount]) +
                Array(items[..<activeCount])
        }

        var activeDisplayItems: [ItemInfo] {
            let activeCount = max(0, items.count - unusedCount - removedCount)
            guard activeCount > 0 else { return [] }
            guard let displayMap else {
                return Array(items.prefix(activeCount))
            }
            return displayMap.prefix(activeCount).compactMap { index in
                let index = Int(index)
                return items.indices.contains(index) ? items[index] : nil
            }
        }

        mutating func replaceItems(
            active activeItems: [ItemInfo],
            removed removedItems: [ItemInfo] = [],
            unused unusedItems: [ItemInfo] = [],
            forceChange: Bool = false
        ) {
            let oldIdentity = items.map { ItemIdentity(item: $0) }
            let oldDisplayMap = displayMap
            let oldAllUnary = allUnary
            let oldRemovedCount = removedCount
            let oldUnusedCount = unusedCount
            let newItems = activeItems + removedItems + unusedItems
            var precedingViewCount: Int32 = 0
            for item in newItems {
                item.precedingViewCount = precedingViewCount
                let (next, overflow) = precedingViewCount.addingReportingOverflow(
                    item.viewCount
                )
                precondition(!overflow, "Dynamic container view count overflow.")
                precedingViewCount = next
            }
            let newIdentity = newItems.map { ItemIdentity(item: $0) }
            items = newItems
            removedCount = removedItems.count
            unusedCount = unusedItems.count
            allUnary = !activeItems.contains { $0.viewCount != 1 }
            rebuildIndexMap()
            rebuildDisplayMap()
            if forceChange ||
                oldIdentity != newIdentity ||
                oldDisplayMap != displayMap ||
                oldAllUnary != allUnary ||
                oldRemovedCount != removedCount ||
                oldUnusedCount != unusedCount {
                seed &+= 1
            }
        }

        private mutating func rebuildIndexMap() {
            indexMap.removeAll(keepingCapacity: true)
            for (index, item) in items.enumerated() {
                indexMap[item.uniqueId] = index
            }
        }

        private mutating func rebuildDisplayMap() {
            // zIndex/depth can produce displayMap. LayoutProxyAttributes does not
            // currently provide a zIndex source, so this only covers stored values.
            let activeEnd = max(0, items.count - unusedCount - removedCount)
            let activeRange = 0..<activeEnd
            let retainedEnd = activeEnd + removedCount
            let retainedRange = 0..<retainedEnd
            guard items[retainedRange].contains(where: { $0.zIndex != 0 }) else {
                displayMap = nil
                return
            }
            let activeMap = sortedDisplayIndexes(in: activeRange)
            guard removedCount != 0 else {
                displayMap = activeMap
                return
            }
            displayMap = activeMap + sortedDisplayIndexes(in: retainedRange)
        }

        private func sortedDisplayIndexes(in range: Range<Int>) -> [UInt32] {
            range.sorted { lhsIndex, rhsIndex in
                let lhs = items[lhsIndex]
                let rhs = items[rhsIndex]
                if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
                // At equal depth, phase-2 removals sort before active phase-1 items
                // in the retained-inclusive segment.
                if lhs.phase != rhs.phase {
                    if lhs.phase == .didDisappear { return true }
                    if rhs.phase == .didDisappear { return false }
                }
                return lhsIndex < rhsIndex
            }.map { UInt32($0) }
        }

        private struct ItemIdentity: Equatable {
            var uniqueId: UInt32
            var viewCount: Int32
            var phase: TransitionPhase?
            init(item: ItemInfo) {
                self.uniqueId = item.uniqueId
                self.viewCount = item.viewCount
                self.phase = item.phase
            }
        }
    }
}

private struct DynamicViewPhase: Rule, AsyncAttribute {
    var containerInfo: Attribute<DynamicContainer.Info>
    var phase: Attribute<_GraphInputs.Phase>
    var uniqueId: UInt32

    var value: _GraphInputs.Phase {
        var value = phase.value
        guard let item = containerInfo.value.item(for: uniqueId) else {
            return value
        }
        value.resetSeed &+= item.resetSeed
        if item.phase == .didDisappear {
            value.isBeingRemoved = true
        }
        return value
    }
}

/// Exposes the retained item's current transition phase to effects that need
/// the same phase as the transition-body rule.
private struct DynamicTransitionPhase: Rule {
    var containerInfo: Attribute<DynamicContainer.Info>
    var uniqueId: UInt32
    var initialPhase: TransitionPhase

    var value: TransitionPhase {
        // Item materialization can read the phase before the owner publishes
        // the new record. Preserve the phase selected by that owner meanwhile.
        containerInfo.value.item(for: uniqueId)?.phase ?? initialPhase
    }
}

private struct DynamicTransaction: StatefulRule, AsyncAttribute {
    typealias Value = Transaction

    var containerInfo: Attribute<DynamicContainer.Info>
    var transaction: Attribute<Transaction>
    var uniqueId: UInt32
    var wasRemoved = false

    mutating func updateValue() {
        guard let item = containerInfo.value.item(for: uniqueId),
              let itemPhase = item.phase else {
            _AGGraph.setStatefulOutput(Transaction())
            return
        }

        var value = transaction.value
        let previouslyRemoved = wasRemoved
        wasRemoved = false

        switch itemPhase {
        case .willAppear:
            value.animation = nil
            value.disablesAnimations = true
        case .identity:
            break
        case .didDisappear:
            if !previouslyRemoved, let listener = item.listener {
                value.addAnimationListener(listener)
            }
            wasRemoved = true
        }
        _AGGraph.setStatefulOutput(value)
    }
}

/// Stores one flat, identity-sorted layout-attribute entry per dynamic child
/// and rebuilds its active container-order cache when the info seed changes.
struct DynamicLayoutMap {
    var map: [(id: DynamicContainerID, value: LayoutProxyAttributes)] = []
    var sortedArray: [LayoutProxyAttributes] = []
    var sortedSeed: UInt32 = 0

    subscript(id: DynamicContainerID) -> LayoutProxyAttributes {
        get {
            let index = lowerBound(for: id)
            guard index < map.endIndex, map[index].id == id else {
                return LayoutProxyAttributes()
            }
            return map[index].value
        }
        set {
            let index = lowerBound(for: id)
            let found = index < map.endIndex && map[index].id == id
            if newValue == LayoutProxyAttributes() {
                if found {
                    map.remove(at: index)
                }
            } else if found {
                map[index].value = newValue
            } else {
                map.insert((id: id, value: newValue), at: index)
            }
            sortedSeed = 0
        }
    }

    mutating func remove(uniqueId: UInt32) {
        let start = lowerBound(
            for: DynamicContainerID(uniqueId: uniqueId, viewIndex: 0)
        )
        var end = start
        while end < map.endIndex, map[end].id.uniqueId == uniqueId {
            end += 1
        }
        if start < end {
            map.removeSubrange(start..<end)
            sortedSeed = 0
        }
    }

    mutating func attributes(info: DynamicContainer.Info) -> [LayoutProxyAttributes] {
        if sortedSeed == info.seed {
            return sortedArray
        }

        // displayMap belongs to retained rendering order. Layout flattens only
        // the active item prefix in container order.
        sortedArray.removeAll(keepingCapacity: true)
        for item in info.activeItems {
            let count = Int(item.viewCount)
            for viewIndex in 0..<count {
                guard let viewIndex = Int32(exactly: viewIndex) else {
                    preconditionFailure(
                        "Dynamic layout child index must fit Int32."
                    )
                }
                sortedArray.append(
                    self[
                        DynamicContainerID(
                            uniqueId: item.uniqueId,
                            viewIndex: viewIndex
                        )
                    ]
                )
            }
        }
        sortedSeed = info.seed
        return sortedArray
    }

    private func lowerBound(for id: DynamicContainerID) -> Int {
        var lower = map.startIndex
        var upper = map.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if map[middle].id < id {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

/// One dynamic-layout item produced from one transformed view-list sublist.
struct DynamicViewListItem: DynamicContainerItem {
    var id: _ViewList_ID
    var elements: _ViewList_SubgraphElements
    var traits: ViewTraitCollection
    var list: Attribute<any ViewList>?

    var count: Int {
        elements.count
    }

    var needsTransitions: Bool {
        guard traits[CanTransitionTraitKey.self] else {
            return false
        }
        return !traits[TransitionTraitKey.self].isIdentity
    }

    var zIndex: Double {
        traits[ZIndexTraitKey.self]
    }

    func matchesIdentity(of other: DynamicViewListItem) -> Bool {
        id == other.id
    }
}

struct TransitionHelper<T: Transition> {
    var _list: OptionalAttribute<any ViewList>
    var _info: Attribute<DynamicContainer.Info>
    var uniqueId: UInt32
    var transition: T
    var phase: TransitionPhase

    mutating func update() -> Bool {
        guard let item = _info.value.item(for: uniqueId) else {
            return false
        }

        var changed = false
        if let itemPhase = item.phase, itemPhase != phase {
            phase = itemPhase
            changed = true
        }

        // A disappearing item keeps the transition captured while it was
        // active; its list traits may already describe a replacement item.
        guard phase != .didDisappear,
              let list = _list.attribute else {
            return changed
        }
        let listValue = list.changedValue(options: [])
        guard listValue.changed,
              let refreshed = listValue.value.traits[
                TransitionTraitKey.self
              ].base(as: T.self) else {
            return changed
        }
        transition = refreshed
        return true
    }
}

private struct ViewListTransition<T: Transition>: StatefulRule, AsyncAttribute {
    typealias Value = T.Body

    var helper: TransitionHelper<T>

    mutating func updateValue() {
        if helper.update() || !hasValue {
            _AGGraph.setStatefulOutput(
                helper.transition.body(
                    content: PlaceholderContentView<T>(),
                    phase: helper.phase
                )
            )
        }
    }
}

/// Carries the animation and stable value attached to archived list content.
struct ArchivedAnimationTraitKey: _ViewTraitKey {
    var animation: Animation?
    var hash: StrongHash

    static var defaultValue: ArchivedAnimationTraitKey {
        ArchivedAnimationTraitKey(animation: nil, hash: StrongHash())
    }
}

/// Resolves archived-animation traits into a display-list renderer effect.
struct ViewListArchivedAnimation: Rule {
    struct Effect: _RendererEffect {
        typealias Body = Never

        var animation: Animation?
        var value: StrongHash?

        func effectValue(size: CGSize) -> DisplayList.Effect {
            guard let animation else {
                return .identity
            }
            return .interpolatorAnimation(
                DisplayList.InterpolatorAnimation(
                    value: value,
                    animation: animation
                )
            )
        }

        static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            _RendererEffectSupport.makeView(
                effect: modifier,
                inputs: inputs,
                body: body
            )
        }

        static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            _RendererEffectSupport.makeViewList(
                modifier: modifier,
                inputs: inputs,
                body: body
            )
        }
    }

    var _traitsList: OptionalAttribute<any ViewList>

    var value: Effect {
        guard let list = _traitsList.attribute else {
            return Effect(animation: nil, value: nil)
        }
        let trait = list.value.traits[ArchivedAnimationTraitKey.self]
        guard let animation = trait.animation else {
            return Effect(animation: nil, value: nil)
        }
        return Effect(animation: animation, value: trait.hash)
    }
}

/// Recomputes the content-transition renderer state for an archived item.
struct ViewListContentTransition<T: Transition>:
    StatefulRule,
    AsyncAttribute {
    typealias Value = ContentTransitionEffect

    var helper: TransitionHelper<T>
    var _size: Attribute<ViewSize>
    var _environment: Attribute<EnvironmentValues>

    mutating func updateValue() {
        guard helper.update() || !hasValue else {
            return
        }

        var state = _environment.value[ContentTransition.State.self]
        let effects = helper.transition.contentTransitionEffects(
            style: state.style,
            size: _size.value.value
        )
        state.transition = ContentTransition(
            method: .binary,
            effects: effects
        )
        _AGGraph.setStatefulOutput(ContentTransitionEffect(state: state))
    }
}

/// Materializes dynamic-layout items while the generic container owns
/// reconciliation and retained-item lifetime.
struct DynamicLayoutViewAdaptor: DynamicContainerAdaptor {
    struct ItemLayout {
        var release: _ViewList_SubgraphRelease?
    }

    private struct MakeTransition: TransitionVisitor {
        var containerInfo: Attribute<DynamicContainer.Info>
        var uniqueId: UInt32
        var item: DynamicViewListItem
        var inputs: _ViewInputs
        var makeElt: (_Graph, _ViewInputs) -> _ViewOutputs
        var outputs: _ViewOutputs?
        var isArchived: Bool

        mutating func visit<T: Transition>(_ transition: T) {
            guard let graph = _AGGraph.current else {
                fatalError(
                    "DynamicLayoutViewAdaptor transition materialization requires an active AG context."
                )
            }

            // Ordinary dynamic content is lowered through the phase-driven
            // transition body. The archived flag is retained for the separate
            // archived-content lowering path.
            let helper = TransitionHelper(
                _list: OptionalAttribute(item.list),
                _info: containerInfo,
                uniqueId: uniqueId,
                transition: transition,
                phase: .identity
            )

            if isArchived {
                makeArchivedTransition(helper: helper, graph: graph)
                return
            }

            let body: Attribute<T.Body> = graph.makeStatefulRule(
                ViewListTransition(helper: helper)
            )
            outputs = T.makeView(
                view: _GraphValue(_attribute: body),
                inputs: inputs,
                body: makeElt
            )
        }

        private mutating func makeArchivedTransition<T: Transition>(
            helper: TransitionHelper<T>,
            graph: _AGGraph
        ) {
            guard helper.transition.hasContentTransition else {
                outputs = makeElt(_Graph(), inputs)
                return
            }

            var archivedInputs = inputs

            // Archived transitions use a type-derived child namespace before
            // the outer renderer effect materializes its content.
            archivedInputs.base.pushStableType(Self.self)

            let archivedAnimation: Attribute<ViewListArchivedAnimation.Effect> =
                graph.makeRule(
                    ViewListArchivedAnimation(
                        _traitsList: OptionalAttribute(item.list)
                    )
                )
            let traits = item.traits
            let makeElement = makeElt
            outputs = _RendererEffectSupport.makeView(
                effect: _GraphValue(_attribute: archivedAnimation),
                inputs: archivedInputs
            ) { _, archivedInputs in
                var contentInputs = archivedInputs

                // A sublist can carry a previously-created stable scope as a
                // trait. Copy only a live weak handle into the graph channel.
                let stableScope =
                    traits[_DisplayList_StableIdentityScope.self]
                if !stableScope.isInvalid {
                    contentInputs.base[
                        _DisplayList_StableIdentityScope.self
                    ] = stableScope
                }

                let contentTransition:
                    Attribute<ContentTransitionEffect> =
                    graph.makeStatefulRule(
                        ViewListContentTransition(
                            helper: helper,
                            _size: contentInputs.size,
                            _environment:
                                contentInputs.base.cachedEnvironment.value
                                    .environment
                        )
                    )
                return _RendererEffectSupport.makeView(
                    effect: _GraphValue(_attribute: contentTransition),
                    inputs: contentInputs,
                    body: makeElement
                )
            }
        }
    }

    var _items: Attribute<any ViewList>
    var _childGeometries: OptionalAttribute<[ViewGeometry]>
    var mutateLayoutMap: (@escaping (inout DynamicLayoutMap) -> Void) -> Void

    init(
        _items: Attribute<any ViewList>,
        _childGeometries: OptionalAttribute<[ViewGeometry]> = OptionalAttribute(),
        mutateLayoutMap: @escaping (
            @escaping (inout DynamicLayoutMap) -> Void
        ) -> Void = { _ in }
    ) {
        self._items = _items
        self._childGeometries = _childGeometries
        self.mutateLayoutMap = mutateLayoutMap
    }

    mutating func updatedItems() -> (any ViewList)? {
        let result = _items.changedValue(options: [])
        return result.changed ? result.value : nil
    }

    func foreachItem(items: any ViewList, _ body: (DynamicViewListItem) -> Void) {
        var from = 0
        _ = _applySublists(
            in: items,
            from: &from,
            listAttribute: _items
        ) { sublist in
            body(
                DynamicViewListItem(
                    id: sublist.id,
                    elements: sublist.elements,
                    traits: sublist.traits,
                    list: sublist.list
                )
            )
            return true
        }
    }

    static func containsItem(
        _ items: any ViewList,
        _ item: DynamicViewListItem
    ) -> Bool {
        var found = false
        var from = 0
        _ = _applySublists(in: items, from: &from) { sublist in
            let candidate = DynamicViewListItem(
                id: sublist.id,
                elements: sublist.elements,
                traits: sublist.traits,
                list: sublist.list
            )
            found = candidate.matchesIdentity(of: item)
            return !found
        }
        return found
    }

    func makeItemLayout(
        item: DynamicViewListItem,
        uniqueId: UInt32,
        inputs: _ViewInputs,
        containerInfo: Attribute<DynamicContainer.Info>,
        containerInputs: (inout _ViewInputs) -> Void
    ) -> (_ViewOutputs, ItemLayout) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "DynamicLayoutViewAdaptor.makeItemLayout called outside an active AG context."
            )
        }

        let archiveOptions = inputs[ArchivedViewInput.self]
        let transition: AnyTransition?
        if item.traits[CanTransitionTraitKey.self] {
            let candidate = item.traits[TransitionTraitKey.self]
            transition = !archiveOptions.isArchived && candidate.isIdentity
                ? nil
                : candidate
        } else {
            transition = nil
        }

        var childIndex: Int32 = 0
        var layoutAttributes: [LayoutProxyAttributes] = []
        let traitsList = item.list.map(OptionalAttribute.init) ??
            OptionalAttribute<any ViewList>()

        let finalOutputs = item.elements.makeAllElements(inputs: inputs) {
            elementInputs,
            makeView in
            var childInputs = elementInputs
            childInputs.copyCaches()
            containerInputs(&childInputs)

            let inheritedPosition = inputs.position
            let inheritedSize = inputs.size

            let geometry: Attribute<ViewGeometry>?
            if let childGeometries = _childGeometries.attribute {
                geometry = graph.makeStatefulRule(
                    DynamicLayoutViewChildGeometry(
                        _containerInfo: containerInfo,
                        _childGeometries: childGeometries,
                        id: DynamicContainerID(
                            uniqueId: uniqueId,
                            viewIndex: childIndex
                        )
                    )
                )
            } else {
                geometry = nil
            }

            let childPosition = geometry?.origin() ?? inheritedPosition
            let childSize = geometry?.size() ?? inheritedSize

            childInputs.position = childPosition
            childInputs.size = childSize
            // Layout placement does not redefine the transform or nearest
            // container channels.
            childInputs.safeAreaInsets = inputs.safeAreaInsets
            childInputs.stackOrientation = inputs.stackOrientation

            let outputs: _ViewOutputs
            if let transition {
                var visitor = MakeTransition(
                    containerInfo: containerInfo,
                    uniqueId: uniqueId,
                    item: item,
                    inputs: childInputs,
                    makeElt: { _, transitionInputs in
                        makeView(transitionInputs)
                    },
                    outputs: nil,
                    isArchived: archiveOptions.isArchived
                )
                transition.visit(&visitor)
                guard let transitionOutputs = visitor.outputs else {
                    preconditionFailure(
                        "Dynamic layout transition did not produce view outputs."
                    )
                }
                outputs = transitionOutputs
            } else {
                outputs = makeView(childInputs)
            }

            if let layoutComputer = outputs._layoutComputer.attribute {
                layoutAttributes.append(
                    LayoutProxyAttributes(
                        layoutComputer: layoutComputer,
                        traitsList: traitsList
                    )
                )
            } else {
                layoutAttributes.append(LayoutProxyAttributes())
            }
            childIndex &+= 1
            return outputs
        }

        guard let outputs = finalOutputs else {
            preconditionFailure(
                "A dynamic layout item must materialize at least one view output."
            )
        }

        mutateLayoutMap { map in
            for (offset, attributes) in layoutAttributes.enumerated() {
                guard let viewIndex = Int32(exactly: offset) else {
                    preconditionFailure(
                        "Dynamic layout child index must fit Int32."
                    )
                }
                map[
                    DynamicContainerID(
                        uniqueId: uniqueId,
                        viewIndex: viewIndex
                    )
                ] = attributes
            }
        }
        return (
            outputs,
            ItemLayout(release: item.elements.retain())
        )
    }

    func removeItemLayout(uniqueId: UInt32, itemLayout: ItemLayout) {
        mutateLayoutMap { map in
            map.remove(uniqueId: uniqueId)
        }
        _ = itemLayout.release
    }
}

private struct DynamicPreferenceCombiner<K: PreferenceKey>: Rule {
    var _info = OptionalAttribute<DynamicContainer.Info>()

    var value: K.Value {
        guard let info = _info.attribute?.value else {
            return K.defaultValue
        }
        let items = K._includesRemovedValues
            ? info.displayItems
            : info.activeDisplayItems
        var value = K.defaultValue
        var hasValue = false
        for item in items {
            for attribute in item.outputs.preferences.values(for: K.self) {
                let next = Attribute<K.Value>(attribute).value
                if hasValue {
                    K.reduce(value: &value) { next }
                } else {
                    value = next
                    hasValue = true
                }
            }
        }
        return value
    }
}

extension DynamicContainer {
    private static func makePreferenceCombiner<K: PreferenceKey>(
        _ key: K.Type,
        graph: _AGGraph
    ) -> (
        attribute: AGAttribute,
        install: (Attribute<Info>) -> Void
    ) {
        let combiner: Attribute<K.Value> = graph.makeRule(
            DynamicPreferenceCombiner<K>()
        )
        return (
            combiner.identifier,
            { info in
                graph.mutateRule(
                    combiner.identifier,
                    as: DynamicPreferenceCombiner<K>.self,
                    invalidating: true
                ) {
                    $0._info = OptionalAttribute(info)
                }
            }
        )
    }

    static func makeContainer<A: DynamicContainerAdaptor>(
        adaptor: A,
        inputs: _ViewInputs
    ) -> (Attribute<Info>, _ViewOutputs) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "DynamicContainer.makeContainer called outside an active AG context."
            )
        }

        var preferences = PreferencesOutputs()
        var installers: [(Attribute<Info>) -> Void] = []
        for key in inputs.preferences.keys.keys {
            let result = makePreferenceCombiner(key, graph: graph)
            preferences.append(key, node: result.attribute)
            installers.append(result.install)
        }
        let outputs = _ViewOutputs(preferences: preferences)
        // The first update publishes the phase-zero item snapshot. Seeding an
        // empty output here would change transition evaluation order.
        let container: Attribute<Info> = graph.makeStatefulRule(
            DynamicContainerInfo(
                adaptor: adaptor,
                inputs: inputs,
                outputs: outputs,
                parentSubgraph: AGSubgraph.current,
                info: Info(),
                lastUniqueId: 0,
                lastRemoved: 0,
                lastResetSeed: .max,
                needsPhaseUpdate: false
            )
        )
        for install in installers {
            install(container)
        }
        return (container, outputs)
    }
}


/// Reconciles adaptor items and publishes `DynamicContainer.Info`.
struct DynamicContainerInfo<A: DynamicContainerAdaptor>:
    StatefulRule,
    AsyncAttribute,
    ObservedAttribute,
    CustomStringConvertible {
    typealias Value = DynamicContainer.Info

    var adaptor: A
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var parentSubgraph: AGSubgraph?
    var info: DynamicContainer.Info
    var lastUniqueId: UInt32
    var lastRemoved: UInt32
    var lastResetSeed: UInt32
    var needsPhaseUpdate: Bool

    var description: String {
        "DynamicContainerInfo<\(A.self)>"
    }

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError(
                "DynamicContainerInfo.updateValue called outside an active AG context."
            )
        }
        guard let currentAttribute = _AGGraph.currentRuleContextAttribute else {
            fatalError(
                "DynamicContainerInfo.updateValue requires a current rule attribute."
            )
        }
        let container = Attribute<DynamicContainer.Info>(currentAttribute)

        let resetSeed = inputs.base.phase.value.resetSeed
        let disableTransitions: Bool
        if resetSeed != lastResetSeed {
            lastResetSeed = resetSeed
            disableTransitions = true
        } else {
            disableTransitions = inputs.base.options.contains(
                .animationsDisabled
            )
        }

        var stateChanged = false
        if needsPhaseUpdate {
            for item in info.items where item.phase == .willAppear {
                item.phase = .identity
                stateChanged = true
            }
            needsPhaseUpdate = false
        }

        let updated = adaptor.updatedItems()
        let activeItems: [DynamicContainer.ItemInfo]
        let inactiveItems: [DynamicContainer.ItemInfo]
        if let updated {
            let reconciliation = reconcile(
                updated,
                container: container,
                disableTransitions: disableTransitions,
                graph: graph
            )
            activeItems = reconciliation.active
            inactiveItems = reconciliation.inactive
            // A refreshed adaptor generation publishes even when every item is reused.
            stateChanged = true
        } else {
            activeItems = Array(info.activeItems)
            inactiveItems = Array(info.items.dropFirst(activeItems.count))
        }

        let retained = retainInactiveItems(
            inactiveItems,
            disableTransitions: disableTransitions,
            allowNewRemovals: updated != nil,
            changed: &stateChanged
        )
        info.replaceItems(
            active: activeItems,
            removed: retained.removed,
            unused: retained.unused,
            forceChange: stateChanged
        )
        _AGGraph.setStatefulOutput(info)
    }

    mutating func destroy() {
        for item in info.items {
            item.listener?.detachFromViewGraph()
        }
    }

    private mutating func reconcile(
        _ items: A.Items,
        container: Attribute<DynamicContainer.Info>,
        disableTransitions: Bool,
        graph: _AGGraph
    ) -> (
        active: [DynamicContainer.ItemInfo],
        inactive: [DynamicContainer.ItemInfo],
        changed: Bool
    ) {
        // The active prefix is rebuilt in place. Items at or after the cursor
        // remain eligible for exact matching, retained-unused reuse, or
        // adaptor-approved active-slot reuse.
        var pool = info.items
        var activeCount = 0
        var changed = false

        // Traverse the adaptor's item representation directly so selection
        // observes the adaptor-defined order without an intermediate owner.
        let traversalAdaptor = adaptor
        traversalAdaptor.foreachItem(items: items) { newItem in
            var exactIndex: Int?
            var unusedReuseIndex: Int?

            if activeCount < pool.count {
                for index in activeCount..<pool.count {
                    let candidate = pool[index].for(A.self)
                    if candidate.item.matchesIdentity(of: newItem) {
                        exactIndex = index
                        break
                    }
                    // Remember the first reusable retained slot while
                    // continuing the scan so an exact identity still wins.
                    if unusedReuseIndex == nil,
                       candidate.phase == nil,
                       candidate.item.canBeReused(by: newItem) {
                        unusedReuseIndex = index
                    }
                }
            }

            if let exactIndex {
                // Exact matches move into the active prefix before their typed
                // payload is refreshed. Compatibility belongs to the item's
                // identity contract, so retained metadata is not re-derived.
                if exactIndex != activeCount {
                    pool.swapAt(activeCount, exactIndex)
                    changed = true
                }
                let item = pool[activeCount].for(A.self)
                item.item = newItem
                if item.phase != .identity {
                    unremove(item, graph: graph)
                    changed = true
                }
            } else {
                var reuseIndex = unusedReuseIndex
                if reuseIndex == nil, A.Item.supportsReuse {
                    reuseIndex = (activeCount..<pool.count).first { index in
                        let candidate = pool[index].for(A.self)
                        // Do not steal transition-owned storage or an old
                        // identity that appears later in the incoming items.
                        return !candidate.needsTransitions &&
                            candidate.item.canBeReused(by: newItem) &&
                            !A.containsItem(items, candidate.item)
                    }
                }

                if let reuseIndex {
                    let item = pool[reuseIndex].for(A.self)
                    // Reuse refreshes the typed payload and reset phase before
                    // moving the retained object into the active prefix.
                    item.item = newItem
                    unremove(item, graph: graph)
                    if activeCount < reuseIndex {
                        pool.swapAt(activeCount, reuseIndex)
                    }
                    changed = true
                } else {
                    let item = makeItem(
                        newItem,
                        uniqueId: nextUniqueId(),
                        container: container,
                        disableTransitions: disableTransitions,
                        graph: graph
                    )
                    pool.append(item)
                    let appendedIndex = pool.index(before: pool.endIndex)
                    if activeCount < appendedIndex {
                        pool.swapAt(activeCount, appendedIndex)
                    }
                    changed = true
                }
            }

            let activeItem = pool[activeCount]
            if activeItem.zIndex != newItem.zIndex {
                activeItem.zIndex = newItem.zIndex
                changed = true
            }
            activeCount += 1
        }

        return (
            Array(pool.prefix(activeCount)),
            Array(pool.dropFirst(activeCount)),
            changed
        )
    }

    private mutating func unremove(
        _ item: DynamicContainer._ItemInfo<A>,
        graph: _AGGraph
    ) {
        let oldPhase = item.phase
        item.listener?.detachFromViewGraph()
        item.listener = nil
        item.removalOrder = 0

        if oldPhase == nil {
            item.subgraph.didReinsert()
        }
        if oldPhase == .didDisappear {
            item.phase = .identity
            return
        }

        item.resetSeed &+= 1
        item.phase = item.needsTransitions ? .willAppear : .identity
        guard item.phase == .willAppear else {
            return
        }
        needsPhaseUpdate = true
        continueCurrentTransaction(graph: graph)
    }

    private mutating func retainInactiveItems(
        _ candidates: [DynamicContainer.ItemInfo],
        disableTransitions: Bool,
        allowNewRemovals: Bool,
        changed: inout Bool
    ) -> (
        removed: [DynamicContainer.ItemInfo],
        unused: [DynamicContainer.ItemInfo]
    ) {
        var removed: [DynamicContainer.ItemInfo] = []
        var unused: [DynamicContainer.ItemInfo] = []
        let maxUnusedItems = max(A.maxUnusedItems, 0)

        for item in candidates {
            if item.phase == .didDisappear {
                guard let listener = item.listener else {
                    eraseItem(item)
                    changed = true
                    continue
                }
                guard listener.isComplete else {
                    removed.append(item)
                    continue
                }
                eraseItem(item)
                changed = true
                continue
            }

            if item.phase == nil {
                if unused.count < maxUnusedItems {
                    unused.append(item)
                } else {
                    eraseItem(item)
                    changed = true
                }
                continue
            }

            guard allowNewRemovals,
                  item.needsTransitions,
                  !disableTransitions else {
                cacheOrErase(
                    item,
                    maxUnusedItems: maxUnusedItems,
                    unused: &unused
                )
                changed = true
                continue
            }

            let listener = DynamicAnimationListener()
            item.listener = listener
            item.removalOrder = nextRemovalOrder()
            item.phase = .didDisappear
            listener.beginTrackingAnimations()
            removed.append(item)
            changed = true
        }
        return (removed, unused)
    }

    private mutating func cacheOrErase(
        _ item: DynamicContainer.ItemInfo,
        maxUnusedItems: Int,
        unused: inout [DynamicContainer.ItemInfo]
    ) {
        guard unused.count < maxUnusedItems else {
            eraseItem(item)
            return
        }
        item.listener?.detachFromViewGraph()
        item.listener = nil
        item.subgraph.willRemove()
        item.phase = nil
        item.removalOrder = 0
        item.resetSeed &+= 1
        unused.append(item)
    }

    private mutating func makeItem(
        _ item: A.Item,
        uniqueId: UInt32,
        container: Attribute<DynamicContainer.Info>,
        disableTransitions: Bool,
        graph: _AGGraph
    ) -> DynamicContainer._ItemInfo<A> {
        guard let viewCount = Int32(exactly: item.count) else {
            preconditionFailure(
                "Dynamic container view count must fit Int32."
            )
        }
        let phase: TransitionPhase =
            !disableTransitions && item.needsTransitions
            ? .willAppear
            : .identity
        if phase == .willAppear {
            needsPhaseUpdate = true
            continueCurrentTransaction(graph: graph)
        }

        // Rule evaluation does not inherit the construction scope. Re-enter
        // the parent captured when the container rule was installed.
        let subgraph = AGSubgraph.withCurrent(parentSubgraph) {
            AGSubgraph()
        }
        var baseInputs = inputs
        baseInputs.copyCaches()

        return AGSubgraph.withCurrent(subgraph) {
            let result = adaptor.makeItemLayout(
                item: item,
                uniqueId: uniqueId,
                inputs: baseInputs,
                containerInfo: container
            ) { childInputs in
                let transaction: Attribute<Transaction> =
                    graph.makeStatefulRule(
                        DynamicTransaction(
                            containerInfo: container,
                            transaction: childInputs.base.transaction,
                            uniqueId: uniqueId
                        )
                    )
                childInputs.base.transaction = transaction
                childInputs.base.phase = graph.makeRule(
                    DynamicViewPhase(
                        containerInfo: container,
                        phase: childInputs.base.phase,
                        uniqueId: uniqueId
                    )
                )
            }
            let resultItem = DynamicContainer._ItemInfo<A>(
                item: item,
                itemLayout: result.1,
                subgraph: subgraph,
                uniqueId: uniqueId,
                viewCount: viewCount,
                phase: phase,
                needsTransitions: item.needsTransitions,
                outputs: result.0
            )
            resultItem.zIndex = item.zIndex
            return resultItem
        }
    }

    private mutating func eraseItem(
        _ item: DynamicContainer.ItemInfo
    ) {
        let typed = item.for(A.self)
        adaptor.removeItemLayout(
            uniqueId: item.uniqueId,
            itemLayout: typed.itemLayout
        )
        item.listener?.detachFromViewGraph()
        item.listener = nil
        item.invalidate()
    }

    private mutating func nextUniqueId() -> UInt32 {
        // Numeric identity belongs to the container and wraps naturally.
        lastUniqueId &+= 1
        return lastUniqueId
    }

    private mutating func nextRemovalOrder() -> UInt32 {
        // Zero is the sentinel, so a wrapping increment skips it.
        lastRemoved &+= 1
        if lastRemoved == 0 {
            lastRemoved = 1
        }
        return lastRemoved
    }

    private func continueCurrentTransaction(graph: _AGGraph) {
        guard let currentAttribute = _AGGraph.currentRuleContextAttribute,
              let weakAttribute = graph.weakAttributeIfValid(
                  for: currentAttribute
              ) else {
            fatalError(
                "DynamicContainerInfo insertion requires a live rule attribute."
            )
        }
        GraphHost.currentHost.continueTransaction(
            invalidating: weakAttribute
        )
    }
}

/// StatefulRule: consumes DynamicContainer.Info through DynamicLayoutMap and produces
/// LayoutComputer for a dynamic layout list.
private struct DynamicLayoutComputer<L: Layout>: StatefulRule, AsyncAttribute, CustomStringConvertible {
    typealias Value = LayoutComputer
    var _layout: Attribute<L>
    var _environment: Attribute<EnvironmentValues>
    var _containerInfo: OptionalAttribute<DynamicContainer.Info>
    var layoutMap = DynamicLayoutMap()

    var description: String {
        "\(L.self) → LayoutComputer"
    }

    mutating func updateValue() {
        guard let containerInfo = _containerInfo.attribute else {
            fatalError("DynamicLayoutComputer evaluated before its container info was installed.")
        }
        let layout = _layout.value
        let info = containerInfo.value
        let children = layoutMap.attributes(info: info)
        updateLayoutComputer(
            layout: layout,
            environment: _environment,
            attributes: children
        )
    }
}

/// Scrollable collection carrier for dynamic `Layout` children.
private struct DynamicLayoutScrollable: ScrollableCollection, ScrollableContainer {
    var containerInfo: Attribute<DynamicContainer.Info>
    var viewList: Attribute<any ViewList>
    var geometries: Attribute<[ViewGeometry]>
    var transform: Attribute<ViewTransform>
    var parentScrollable: WeakAttribute<any Scrollable>
    var childScrollables: Attribute<ScrollablePreferenceKey.Value>?

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        collectionViewIDs()
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        let ids = collectionViewIDs()
        let geometries = geometries.value
        let transform = transform.value
        for offset in ids.indices where geometries.indices.contains(offset) {
            let frame = frame(for: geometries[offset])
            var stop = false
            body(
                ScrollableCollectionSubview(
                    id: viewListID(from: ids[offset]),
                    frame: frame,
                    frameInContent: frame.converted(to: .content, using: transform),
                    transform: transform
                ),
                &stop
            )
            if stop { break }
        }
    }

    func subviewClosestTo(rect: CGRect) -> ScrollableCollectionSubview? {
        var closest: (subview: ScrollableCollectionSubview, distance: CGFloat)?
        forEachVisibleSubview { subview, stop in
            let distance = subview.frame.midpointDistance(to: rect)
            if closest == nil || distance < closest!.distance {
                closest = (subview, distance)
            }
            stop = false
        }
        return closest?.subview
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        nil
    }

    static func hasMultipleViewsInAxis(_ axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        viewList.value.firstOffset(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        var emitted = false
        let completed = viewList.value.applyIDs(from: &index, listAttribute: viewList) { id in
            emitted = true
            var stop = false
            body(id.canonicalID, &stop)
            return !stop
        }
        return emitted && completed
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        containerInfo.value
            .item(for: subgraph)?
            .for(DynamicLayoutViewAdaptor.self)
            .item
            .id
            .canonicalID
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        guard let offset = firstCollectionViewIndex(of: id) else {
            return false
        }
        return setParentTarget { _, _ in
            makeTarget(at: offset, anchor: anchor)
        }
    }

    var parent: (any Scrollable)? {
        resolvedParentScrollable
    }

    var children: [any Scrollable]? {
        childScrollables?.value
    }

    func makeTarget<ID: Hashable>(
        for id: ID
    ) -> ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)? {
        guard let offset = viewList.value.firstOffset(
            forID: id,
            style: _ViewList_IteratorStyle()
        ) else {
            return nil
        }
        let anchor = Transaction.current.scrollTargetAnchor
        return { _, _ in
            makeTarget(at: offset, anchor: anchor)
        }
    }

    private func collectionViewIDs() -> [_ViewList_ID.Canonical] {
        var index = 0
        var ids: [_ViewList_ID.Canonical] = []
        _ = applyCollectionViewIDs(from: &index) { id, stop in
            ids.append(id)
            stop = false
        }
        return ids
    }

    private func makeTarget(at offset: Int, anchor: UnitPoint?) -> ScrollTarget? {
        let geometries = geometries.value
        guard geometries.indices.contains(offset) else {
            return nil
        }
        let rect = frame(for: geometries[offset])
            .converted(to: .content, using: transform.value)
        return ScrollTarget(rect: rect, anchor: anchor)
    }

    private func frame(for geometry: ViewGeometry) -> CGRect {
        CGRect(origin: geometry.origin, size: geometry.dimensions.size.value)
    }

    private func viewListID(from canonical: _ViewList_ID.Canonical) -> _ViewList_ID {
        if let explicitID = canonical.explicitID {
            let implicitID = canonical.implicitID >= 0 ? Int(canonical.implicitID) : 0
            return _ViewList_ID(explicitID: explicitID, implicitID: implicitID)
        }
        return _ViewList_ID(implicitID: Int(canonical.implicitID))
    }

    private var resolvedParentScrollable: (any Scrollable)? {
        guard let graph = _AGGraph.current,
              parentScrollable.isValid(in: graph) else {
            return nil
        }
        return parentScrollable.toStrong().value
    }
}

private extension CGRect {
    func midpointDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return (dx * dx + dy * dy).squareRoot()
    }
}

public protocol Layout: Sendable, Animatable {
    static var layoutProperties: LayoutProperties { get }

    associatedtype Cache = Void

    typealias Subviews = LayoutSubviews

    func makeCache(subviews: Self.Subviews) -> Self.Cache
    func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews)
    func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?

    static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs
}

extension Layout {
    /// Builds either the static or dynamic layout graph while keeping
    /// measurement, aggregate placement, and per-child geometry in their
    /// distinct rule owners.
    public static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeLayoutView called outside an active _AGGraph context.")
        }

        var layoutInputs = inputs
        if ObjectIdentifier(Self.self) == ObjectIdentifier(AnyLayout.self) {
            let layout = Attribute<AnyLayout>(
                identifier: root._attribute.identifier
            )
            let properties: Attribute<Axis?> = graph.makeRule(
                AnyLayoutProperties(_layout: layout)
            )
            layoutInputs.stackOrientation = nil
            layoutInputs[DynamicStackOrientation.self] = OptionalAttribute(
                properties
            )
        } else {
            let stackOrientation = Self.layoutProperties.stackOrientation
            layoutInputs.stackOrientation = stackOrientation
            if stackOrientation == nil {
                layoutInputs[DynamicStackOrientation.self] = OptionalAttribute()
            }
        }
        let dynamicStackOrientation =
            layoutInputs[DynamicStackOrientation.self]

        let childListOutputs = body(_Graph(), layoutInputs)

        // Debug overlay for the layout container itself.
        // Reads the container's pos/size from LayoutChildGeometries-driven posAttr/sizeAttr
        // via the parent. Replace this with the exact layout-container overlay
        // mechanism once modeled.
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let environment = cachedEnvironmentAttr.value.environment
        let containerPosAttr  = inputs.position
        let containerSizeAttr = inputs.size
        let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
            let debugLayout = cachedEnvironmentAttr.value.environment.value._debugLayout
            var dl = DisplayList()
            if debugLayout {
                appendDebugOverlay(
                    to: &dl,
                    frame: CGRect(origin: containerPosAttr.value, size: containerSizeAttr.value.value),
                    category: .layoutContainer
                )
            }
            return dl
        }

        let layoutComputerAttr: Attribute<LayoutComputer>
        var mergedPreferences: PreferencesOutputs

        switch childListOutputs.views {
        case .staticList(let elements):
            var childProxyAttrs: [LayoutProxyAttributes] = []
            var allPreferences: [PreferencesOutputs] = []

            let staticLCAttr: Attribute<LayoutComputer> = graph.makeStatefulRule(
                StaticLayoutComputer(
                    _layout: root._attribute,
                    _environment: environment,
                    childAttributes: [],
                )
            )
            let childGeometries: Attribute<[ViewGeometry]> = graph.makeRule(
                LayoutChildGeometries(
                    parentSize: inputs.size,
                    parentPosition: inputs.position,
                    layoutComputer: staticLCAttr
                )
            )

            var from = 0
            var childIndex = 0
            elements.makeElements(from: &from, inputs: layoutInputs, indirectMap: nil) { elementInputs, makeView in
                let geometry = graph.makeRule(
                    LayoutChildGeometry(
                        _childGeometries: childGeometries,
                        index: childIndex
                    )
                )
                childIndex += 1

                var childInputs = elementInputs
                childInputs.copyCaches()
                childInputs.base.options.insert(.viewNeedsGeometry)
                childInputs.requestsLayoutComputer = true
                // Both child inputs project from the same geometry rule so a
                // placement update cannot publish independently recomputed
                // position and size values.
                let posAttr = geometry.origin()
                let sizeAttr = geometry.size()
                childInputs.position = posAttr
                childInputs.size = sizeAttr
                // Layout placement does not redefine the transform or nearest
                // container channels.
                childInputs.safeAreaInsets = inputs.safeAreaInsets
                childInputs.stackOrientation = layoutInputs.stackOrientation
                childInputs[DynamicStackOrientation.self] =
                    dynamicStackOrientation

                let childOutputs = makeView(childInputs)
                if let layoutComputer = childOutputs._layoutComputer.attribute {
                    childProxyAttrs.append(
                        LayoutProxyAttributes(layoutComputer: layoutComputer)
                    )
                } else {
                    childProxyAttrs.append(LayoutProxyAttributes())
                }
                allPreferences.append(childOutputs.preferences)
                return (childOutputs, true)
            }

            graph.mutateStatefulRule(
                staticLCAttr.identifier,
                as: StaticLayoutComputer<Self>.self,
                invalidating: true
            ) {
                $0.childAttributes = childProxyAttrs
            }
            layoutComputerAttr = staticLCAttr
            mergedPreferences = PreferencesOutputs.merge(allPreferences, in: graph)

        case .dynamicList(let viewListAttr, _):
            let dynamicLayoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                DynamicLayoutComputer(
                    _layout: root._attribute,
                    _environment: environment,
                    _containerInfo: OptionalAttribute()
                )
            )
            let childGeometries: Attribute<[ViewGeometry]> = graph.makeRule(
                LayoutChildGeometries(
                    parentSize: inputs.size,
                    parentPosition: inputs.position,
                    layoutComputer: dynamicLayoutComputer
                )
            )
            let adaptor = DynamicLayoutViewAdaptor(
                _items: viewListAttr,
                _childGeometries: OptionalAttribute(childGeometries)
            ) { mutation in
                guard let graph = _AGGraph.current else {
                    fatalError("DynamicLayoutMap mutation requires an active AG context.")
                }
                graph.mutateStatefulRule(
                    dynamicLayoutComputer.identifier,
                    as: DynamicLayoutComputer<Self>.self,
                    invalidating: true
                ) {
                    mutation(&$0.layoutMap)
                }
            }
            var dynamicInputs = layoutInputs
            dynamicInputs.stackOrientation = layoutInputs.stackOrientation
            dynamicInputs[DynamicStackOrientation.self] =
                dynamicStackOrientation
            let (
                containerInfoAttr,
                containerOutputs
            ) = DynamicContainer.makeContainer(
                adaptor: adaptor,
                inputs: dynamicInputs
            )
            graph.mutateStatefulRule(
                dynamicLayoutComputer.identifier,
                as: DynamicLayoutComputer<Self>.self,
                invalidating: true
            ) {
                $0._containerInfo = OptionalAttribute(containerInfoAttr)
            }
            layoutComputerAttr = dynamicLayoutComputer

            // The container owns one combiner per requested key, so retained
            // inclusion follows the key's own lifecycle policy.
            var dynMergedPreferences = containerOutputs.preferences
            let childScrollables = dynMergedPreferences
                .value(for: ScrollablePreferenceKey.self)
                .map {
                    Attribute<ScrollablePreferenceKey.Value>(
                        identifier: $0
                    )
                }

            let parentScrollable = inputs.weakScrollable
            let collection: Attribute<any ScrollableCollection> = graph.makeRule {
                DynamicLayoutScrollable(
                    containerInfo: containerInfoAttr,
                    viewList: viewListAttr,
                    geometries: childGeometries,
                    transform: inputs.transform,
                    parentScrollable: parentScrollable,
                    childScrollables: childScrollables
                ) as any ScrollableCollection
            }
            if inputs.preferences.keys.contains(ScrollTargetRole.ContentKey.self),
               let role = inputs.scrollTargetRole.attribute {
                let transform: Attribute<(inout ScrollTargetRole.ContentKey.Value) -> Void> = graph.makeRule(
                    ScrollTargetRole.SetLayout(role: role, collection: collection)
                )
                dynMergedPreferences.makePreferenceTransformer(
                    inputs: inputs.preferences,
                    key: ScrollTargetRole.ContentKey.self,
                    transform: transform
                )
            }
            if inputs.preferences.keys.contains(ScrollTargetRole.Key.self),
               let role = inputs.scrollTargetRole.attribute {
                let transform: Attribute<(inout ScrollTargetRole.Key.Value) -> Void> = graph.makeRule(
                    ScrollTargetRole.SetLayout(role: role, collection: collection)
                )
                dynMergedPreferences.makePreferenceTransformer(
                    inputs: inputs.preferences,
                    key: ScrollTargetRole.Key.self,
                    transform: transform
                )
            }
            if inputs.preferences.keys.contains(ScrollablePreferenceKey.self) {
                let transform: Attribute<(inout ScrollablePreferenceKey.Value) -> Void> = graph.makeRule {
                    let scrollable = collection.value as any Scrollable
                    return { value in
                        ScrollablePreferenceKey.reduce(value: &value) { [scrollable] }
                    }
                }
                dynMergedPreferences.makePreferenceTransformer(
                    inputs: inputs.preferences,
                    key: ScrollablePreferenceKey.self,
                    transform: transform
                )
            }
            if inputs.preferences.keys.contains(UpdateScrollStateRequestKey.self) {
                let requests: Attribute<UpdateScrollStateRequestKey.Value> = graph.makeStatefulRule(
                    ScrollStateRequestTransform(collection: collection, inputs: inputs)
                )
                let transform: Attribute<(inout UpdateScrollStateRequestKey.Value) -> Void> = graph.makeRule {
                    let requests = requests.value
                    return { value in
                        UpdateScrollStateRequestKey.reduce(value: &value) { requests }
                    }
                }
                dynMergedPreferences.makePreferenceTransformer(
                    inputs: inputs.preferences,
                    key: UpdateScrollStateRequestKey.self,
                    transform: transform
                )
            }
            mergedPreferences = dynMergedPreferences
        }

        mergedPreferences.append(DisplayList.Key.self, node: debugDLAttr.identifier)

        return _ViewOutputs(
            preferences: mergedPreferences,
            layoutComputer: OptionalAttribute(layoutComputerAttr)
        )
    }
}

extension Layout {
    public static var layoutProperties: LayoutProperties {
        .init()
    }

    public func updateCache(_ cache: inout Self.Cache,
                            subviews: Self.Subviews) {
    }

    public func explicitAlignment(of guide: HorizontalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Self.Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        ThreadLayoutData.defaultAlignment(guide.key)
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Self.Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        ThreadLayoutData.defaultAlignment(guide.key)
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        guard !subviews.isEmpty else {
            return .zero
        }

        var spacing = Spacing()
        for subview in subviews {
            spacing.incorporate(.all, of: subview.proxy.spacing())
        }
        return ViewSpacing(
            spacing,
            layoutDirection: subviews.layoutDirection
        )
    }
}

extension Layout where Self.Cache == () {
    public func makeCache(subviews: Self.Subviews) -> Self.Cache {
        ()
    }
}

protocol DerivedLayout: Layout where Cache == Base.Cache {
    associatedtype Base: Layout

    var base: Base { get }
}

extension DerivedLayout {
    public static var layoutProperties: LayoutProperties {
        Base.layoutProperties
    }

    public func makeCache(subviews: Self.Subviews) -> Self.Cache {
        base.makeCache(subviews: subviews)
    }

    public func updateCache(
        _ cache: inout Self.Cache,
        subviews: Self.Subviews
    ) {
        base.updateCache(&cache, subviews: subviews)
    }

    public func spacing(
        subviews: Self.Subviews,
        cache: inout Self.Cache
    ) -> ViewSpacing {
        base.spacing(subviews: subviews, cache: &cache)
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Self.Subviews,
        cache: inout Self.Cache
    ) -> CGSize {
        base.sizeThatFits(
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Self.Subviews,
        cache: inout Self.Cache
    ) {
        base.placeSubviews(
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Self.Subviews,
        cache: inout Self.Cache
    ) -> CGFloat? {
        base.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Self.Subviews,
        cache: inout Self.Cache
    ) -> CGFloat? {
        base.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }
}

extension Layout {
    public func callAsFunction<V>(@ViewBuilder _ content: () -> V) -> some View where V: View {
        _VariadicView.Tree(root: _LayoutRoot(self), content: content())
    }
}

public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}

private struct LayoutDirectionKey: EnvironmentKey {
    static var defaultValue: LayoutDirection { .leftToRight }
}

extension EnvironmentValues {
    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }
}

public struct LayoutProperties: Sendable {
    public var stackOrientation: Axis?
    var isDefaultEmptyLayout: Bool
    var isIdentityUnaryLayout: Bool

    public init() {
        stackOrientation = nil
        isDefaultEmptyLayout = false
        isIdentityUnaryLayout = false
    }
}

struct DynamicStackOrientation: ViewInput {
    static var defaultValue: OptionalAttribute<Axis?> {
        OptionalAttribute()
    }

    static func valuesEqual(_ a: OptionalAttribute<Axis?>, _ b: OptionalAttribute<Axis?>) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

struct AnyLayoutProperties: Rule, AsyncAttribute {
    var _layout: Attribute<AnyLayout>

    var value: Axis? {
        _layout.value.storage.layoutProperties.stackOrientation
    }
}

class AnyLayoutBox: @unchecked Sendable {
    var layoutProperties: LayoutProperties {
        fatalError("abstract")
    }

    func makeCache(subviews: LayoutSubviews) -> AnyLayout.Cache {
        fatalError("abstract")
    }

    func updateCache(
        _ cache: inout AnyLayout.Cache,
        subviews: LayoutSubviews
    ) {
        fatalError("abstract")
    }

    func spacing(
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> ViewSpacing {
        fatalError("abstract")
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> CGSize {
        fatalError("abstract")
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) {
        fatalError("abstract")
    }

    func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> CGFloat? {
        fatalError("abstract")
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> CGFloat? {
        fatalError("abstract")
    }

    var animatableData: _AnyAnimatableData {
        get { fatalError("abstract") }
        set { fatalError("abstract") }
    }

    func withAnimatableData(_ data: _AnyAnimatableData) -> AnyLayoutBox {
        fatalError("abstract")
    }
}

private final class _AnyLayoutBox<L: Layout>: AnyLayoutBox,
    @unchecked Sendable {
    var layout: L

    init(_ layout: L) {
        self.layout = layout
    }

    override var layoutProperties: LayoutProperties {
        L.layoutProperties
    }

    override func makeCache(subviews: LayoutSubviews) -> AnyLayout.Cache {
        AnyLayout.Cache(
            type: L.self,
            value: layout.makeCache(subviews: subviews)
        )
    }

    override func updateCache(
        _ cache: inout AnyLayout.Cache,
        subviews: LayoutSubviews
    ) {
        guard cache.type == L.self else {
            cache = makeCache(subviews: subviews)
            return
        }
        var value = cache.value as! L.Cache
        defer { cache.value = value }
        layout.updateCache(&value, subviews: subviews)
    }

    override func spacing(
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> ViewSpacing {
        var value = cache.value as! L.Cache
        defer { cache.value = value }
        return layout.spacing(subviews: subviews, cache: &value)
    }

    override func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> CGSize {
        var value = cache.value as! L.Cache
        defer { cache.value = value }
        return layout.sizeThatFits(
            proposal: proposal,
            subviews: subviews,
            cache: &value
        )
    }

    override func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) {
        var value = cache.value as! L.Cache
        defer { cache.value = value }
        layout.placeSubviews(
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &value
        )
    }

    override func explicitAlignment(
        of guide: HorizontalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> CGFloat? {
        var value = cache.value as! L.Cache
        defer { cache.value = value }
        return layout.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &value
        )
    }

    override func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout AnyLayout.Cache
    ) -> CGFloat? {
        var value = cache.value as! L.Cache
        defer { cache.value = value }
        return layout.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &value
        )
    }

    override var animatableData: _AnyAnimatableData {
        get { _AnyAnimatableData(layout) }
        set { newValue.update(&layout) }
    }

    override func withAnimatableData(
        _ data: _AnyAnimatableData
    ) -> AnyLayoutBox {
        var layout = layout
        data.update(&layout)
        return _AnyLayoutBox(layout)
    }
}

public struct AnyLayout: Layout {
    var storage: AnyLayoutBox

    public struct Cache: @unchecked Sendable {
        var type: Any.Type
        var value: Any
    }

    public typealias AnimatableData = _AnyAnimatableData

    public init<L>(_ layout: L) where L: Layout {
        storage = _AnyLayoutBox(layout)
    }

    public var animatableData: AnimatableData {
        get { storage.animatableData }
        set {
            if isKnownUniquelyReferenced(&storage) {
                storage.animatableData = newValue
            } else {
                storage = storage.withAnimatableData(newValue)
            }
        }
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Cache) {
        storage.placeSubviews(
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Cache) -> CGSize {
        storage.sizeThatFits(
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func explicitAlignment(of guide: HorizontalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Cache) -> CGFloat? {
        storage.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Cache) -> CGFloat? {
        storage.explicitAlignment(
            of: guide,
            in: bounds,
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
    }

    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        storage.spacing(subviews: subviews, cache: &cache)
    }

    public func makeCache(subviews: Subviews) -> Cache {
        storage.makeCache(subviews: subviews)
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        storage.updateCache(&cache, subviews: subviews)
    }
}

// VariadicView Root for Layout
public struct _LayoutRoot<L>: _VariadicView.UnaryViewRoot where L: Layout {
    @usableFromInline
    var layout: L
    @inlinable init(_ layout: L) {
        self.layout = layout
    }

    /// Delegates to `L._makeLayoutView` by navigating the root KeyPath to the
    /// embedded `layout: L` AG node.  The generic `Layout._makeLayoutView`
    /// implementation handles the rest.
    public static func _makeView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        L._makeLayoutView(root: root[\.layout], inputs: inputs, body: body)
    }

    public typealias Body = Never
}

@available(*, unavailable)
extension _LayoutRoot: Sendable {
}

struct DefaultLayoutProperty: PropertyKey {
    static var defaultValue: any Layout { VStackLayout() }
    static func valuesEqual(_ a: any Layout, _ b: any Layout) -> Bool { false }

    var description: String {
        "DefaultLayoutProperty"
    }
}
