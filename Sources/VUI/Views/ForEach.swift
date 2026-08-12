//
//  File: ForEach.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Produces a dynamic list by assigning stable identities to collection elements.
public struct ForEach<Data, ID, Content> where Data: RandomAccessCollection, ID: Hashable {
    /// Selects either an element key path or the local offset used by a constant range.
    enum IDGenerator {
        case keyPath(KeyPath<Data.Element, ID>)
        case offset

        var isConstant: Bool {
            switch self {
            case .keyPath:
                false
            case .offset:
                true
            }
        }

        func makeID(data: Data, index: Data.Index, offset: Int) -> ID {
            switch self {
            case .keyPath(let keyPath):
                data[index][keyPath: keyPath]
            case .offset:
                // The offset case is only constructed by Range<Int>'s constant
                // initializer. Keep the size check at the conversion boundary.
                unsafeBitCast(offset, to: ID.self)
            }
        }
    }

    public var data: Data
    public var content: (Data.Element) -> Content
    var idGenerator: IDGenerator
    var reuseID: KeyPath<Data.Element, Int>?
}

extension ForEach: View where Content: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        return makeImplicitRoot(view: view, inputs: inputs)
    }

    // ForEach returns .dynamicList(Attribute<any ViewList>, nil) wrapping a ForEachList.
    // ForEachList.applyNodes calls `to` once per data item (per-item sublist).
    public static func _makeViewList(view: _GraphValue<ForEach<Data, ID, Content>>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }

        if view._attribute.value.data is any _ForEachSectionCollectionViewListProducing {
            let viewListAttr: Attribute<any ViewList> = graph.makeRule {
                guard let sectionData = view._attribute.value.data as? any _ForEachSectionCollectionViewListProducing else {
                    return EmptyViewList() as any ViewList
                }
                let outputs = sectionData.makeViewList(inputs: inputs, graph: graph)
                switch outputs.views {
                case .staticList(let elements):
                    return BaseViewList(elements: elements) as any ViewList
                case .dynamicList(let attribute, _):
                    return attribute.value
                }
            }
            return _ViewListOutputs(
                views: .dynamicList(viewListAttr, nil),
                nextImplicitID: inputs.implicitID,
                staticCount: nil
            )
        }

        let state = ForEachState<Data, ID, Content>(inputs: inputs)
        let infoAttr: Attribute<ForEachState<Data, ID, Content>.Info> = graph.makeRule(
            ForEachState<Data, ID, Content>.Info.Init(
                _view: view._attribute,
                state: state
            )
        )
        state.info = infoAttr

        let isEvictionEnabled = inputs.base[ForEachEvictionInput.self]
        if !isEvictionEnabled.isInvalid || ForEachEvictionInput.evictByDefault {
            let evictor: Attribute<Void> = graph.makeRule(
                ForEachState<Data, ID, Content>.Evictor(
                    state: state,
                    _isEnabled: isEvictionEnabled,
                    _updateSeed: GraphHost.currentHost.data._updateSeed
                )
            )
            evictor.flags = [.transactional]
        }

        let viewListAttr: Attribute<any ViewList> = graph.makeStatefulRule(
            ForEachList<Data, ID, Content>.Init(
                _info: infoAttr,
                seed: 0
            )
        )
        state.list = viewListAttr

        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: inputs.implicitID,
            staticCount: nil
        )
    }

}

extension ForEach: PrimitiveView where ForEach: View {
}

/// Controls whether retained ForEach items age out during graph updates.
struct ForEachEvictionInput: ViewInput {
    static var defaultValue: WeakAttribute<Bool> { WeakAttribute() }
    static var evictByDefault: Bool { isLinkedOnOrAfter(.v6) }
}

/// Carries the generation-wide content identity assigned to a dynamic row.
struct DynamicViewContentIDTraitKey: _ViewTraitKey {
    static var defaultValue: Int? { nil }
}

/// Carries the collection-relative offset assigned to a dynamic row.
struct DynamicViewContentOffsetTraitKey: _ViewTraitKey {
    static var defaultValue: Int? { nil }
}

/// Collects inserted offsets into coalesced ranges before materializing an IndexSet.
struct IndexSetBuilder {
    var indexSet = IndexSet()
    var lastRange: Range<Int>?

    mutating func append(_ index: Int) {
        if let lastRange, lastRange.upperBound == index {
            self.lastRange = lastRange.lowerBound..<(index + 1)
            return
        }
        flushLastRange()
        lastRange = index..<(index + 1)
    }

    mutating func remove(afterOffset offset: Int) {
        if let lastRange {
            if lastRange.lowerBound >= offset {
                self.lastRange = nil
            } else if lastRange.upperBound >= offset {
                self.lastRange = lastRange.lowerBound..<offset
            }
        }
        indexSet.remove(integersIn: offset..<Int.max)
    }

    mutating func finalize() -> IndexSet {
        flushLastRange()
        return indexSet
    }

    private mutating func flushLastRange() {
        guard let lastRange else { return }
        indexSet.insert(integersIn: lastRange)
        self.lastRange = nil
    }
}

/// Captures the representative child-ID shape used by fixed-count accumulation.
private enum BaseIDs {
    case staticCount(Int)
    case viewIDs(_ViewList_ID_Views)
}

// MARK: - ForEachState

/// Reconciles collection generations and owns each element's retained list state.
final class ForEachState<Data, ID, Content>
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    /// Publishes the state reference together with the generation visible to child rules.
    struct Info {
        var state: ForEachState
        var seed: UInt32

        /// Reconciles the source value before publishing its generation snapshot.
        struct Init: Rule {
            var _view: Attribute<ForEach<Data, ID, Content>>
            var state: ForEachState

            var value: Info {
                state.update(view: _view.value)
                return Info(state: state, seed: state.seed)
            }
        }
    }

    /// Ages unused items once per host update while eviction is enabled.
    struct Evictor: Rule, AsyncAttribute {
        var state: ForEachState
        var _isEnabled: WeakAttribute<Bool>
        var _updateSeed: Attribute<UInt32>

        var value: Void {
            let isEnabled = _isEnabled.value ?? ForEachEvictionInput.evictByDefault
            if isEnabled {
                state.evictItems(seed: _updateSeed.value)
            }
        }
    }

    /// Owns one element's identity, generated views, and retained subgraph lifetime.
    final class Item: _ViewList_Subgraph {
        let id: ID
        var reuseID: Int
        var views: _ViewListOutputs.Views
        weak var state: ForEachState?
        var index: Data.Index
        var offset: Int
        var contentID: Int
        var seed: UInt32
        var isConstant: Bool
        var timeToLive: Int8
        var isRemoved: Bool
        var hasWarned: Bool

        init(
            id: ID,
            reuseID: Int,
            views: _ViewListOutputs.Views,
            subgraph: AGSubgraph,
            state: ForEachState,
            index: Data.Index,
            offset: Int,
            contentID: Int,
            seed: UInt32,
            isConstant: Bool
        ) {
            self.id = id
            self.reuseID = reuseID
            self.views = views
            self.state = state
            self.index = index
            self.offset = offset
            self.contentID = contentID
            self.seed = seed
            self.isConstant = isConstant
            self.timeToLive = 8
            self.isRemoved = false
            self.hasWarned = false
            super.init(subgraph: subgraph)
        }

        func bindID(_ id: inout _ViewList_ID, isUnary: Bool, isConstant: Bool) {
            guard let owner = state?.list?.identifier else {
                return
            }
            if isConstant {
                id.bind(
                    explicitID: ForEachConstantID(offset, owner),
                    owner: owner,
                    isUnary: isUnary,
                    reuseID: reuseID
                )
            } else {
                id.bind(
                    explicitID: self.id,
                    owner: owner,
                    isUnary: isUnary,
                    reuseID: reuseID
                )
            }
        }

        /// Adds row identity metadata without replacing traits supplied by the child.
        func applyTraits(to traits: inout ViewTraitCollection) {
            traits.setValueIfUnset(
                contentID,
                for: DynamicViewContentIDTraitKey.self
            )
            traits.setValueIfUnset(
                offset,
                for: DynamicViewContentOffsetTraitKey.self
            )
            if isConstant {
                traits.setValueIfUnset(
                    .tagged(offset),
                    for: TagValueTraitKey<Int>.self
                )
            } else {
                traits.setTagIfUnset(for: ID.self, value: id)
            }
        }

        override func invalidate() {
            guard let state else {
                return
            }
            if state.items[id] === self {
                state.items.removeValue(forKey: id)
            } else {
                state.items = state.items.filter { $0.value !== self }
            }
        }
    }

    /// Records whether every element contributes a stable number of list views.
    enum ViewsPerElementCount {
        case countingDebugReplaceableViews(MutableBox<DebugReplaceableViewCount>)
        case resolved(Int)
        case uninitialized
        case indeterminate

        var resolvedCount: Int? {
            switch self {
            case .countingDebugReplaceableViews(let box):
                guard case .counting(let count) = box.value else {
                    return nil
                }
                return count
            case .resolved(let count):
                return count
            case .uninitialized, .indeterminate:
                return nil
            }
        }
    }

    /// Caches the identity comparison route selected for a queried explicit-ID type.
    enum IDTypeMatchingStrategy {
        case exact
        case anyHashable
        case customIDRepresentation
        case noMatch
    }

    /// Resolves the cumulative child-view offset preceding one materialized item.
    struct ItemOffset: Rule {
        var _existingCount: OptionalAttribute<Int>
        var item: Item?

        var value: Int {
            if let existingCount = _existingCount.value {
                return existingCount
            }
            guard let item, let state = item.state else {
                return 0
            }
            return state.offset(before: item, style: state.viewCountStyle)
        }
    }

    /// Keeps an item's lifetime reachable from its generated base list rule.
    struct ItemList: Rule {
        var _base: Attribute<any ViewList>
        var item: Item?

        var value: any ViewList {
            WrappedList(base: _base.value, item: item)
        }

        /// Forwards list behavior while retaining the owning item in the rule value.
        struct WrappedList: ViewList {
            var base: any ViewList
            var item: Item?

            func count(style: _ViewList_IteratorStyle) -> Int {
                base.count(style: style)
            }

            func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
                base.estimatedCount(style: style)
            }

            var traitKeys: ViewTraitKeys? { base.traitKeys }
            var traits: ViewTraitCollection { base.traits }
            var viewIDs: _ViewList_ID_Views? { base.viewIDs }

            func appendViewIDs(into accumulator: inout HeterogeneousViewIDsAccumulator) {
                base.appendViewIDs(into: &accumulator)
            }

            func applyNodes(
                from: inout Int,
                style: _ViewList_IteratorStyle,
                list: Attribute<any ViewList>?,
                transform: _ViewList_TemporarySublistTransform,
                to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
            ) -> Bool {
                base.applyNodes(
                    from: &from,
                    style: style,
                    list: list,
                    transform: transform,
                    to: to
                )
            }

            func firstOffset<A: Hashable>(
                forID id: A,
                style: _ViewList_IteratorStyle
            ) -> Int? {
                base.firstOffset(forID: id, style: style)
            }

            func edit(
                forID id: _ViewList_ID,
                since transaction: TransactionID
            ) -> _ViewList_Edit? {
                base.edit(forID: id, since: transaction)
            }

            func print(into printer: inout SExpPrinter) {
                base.print(into: &printer)
            }
        }
    }

    /// Supplies implicit child IDs when a static item list has no dedicated ID collection.
    struct StaticViewIDCollection: RandomAccessCollection, Equatable {
        typealias Index = Int
        typealias Element = _ViewList_ID

        var count: Int

        var startIndex: Int { 0 }
        var endIndex: Int { count }

        subscript(position: Int) -> _ViewList_ID {
            precondition(indices.contains(position), "view ID index out of range")
            var id = _ViewList_ID(implicitID: 0)
            id._index = Int32(position)
            return id
        }
    }

    /// Repeats one uniform base-ID collection while binding each data element's identity.
    struct ForEachViewIDCollection: RandomAccessCollection, Equatable {
        typealias Index = Int
        typealias Element = _ViewList_ID

        var base: _ViewList_ID_Views
        var data: Data
        var idGenerator: ForEach<Data, ID, Content>.IDGenerator
        var reuseID: KeyPath<Data.Element, Int>?
        var isUnary: Bool
        var owner: AGAttribute
        var baseCount: Int
        var count: Int

        init(
            base: _ViewList_ID_Views,
            data: Data,
            idGenerator: ForEach<Data, ID, Content>.IDGenerator,
            reuseID: KeyPath<Data.Element, Int>?,
            isUnary: Bool,
            owner: AGAttribute
        ) {
            self.base = base
            self.data = data
            self.idGenerator = idGenerator
            self.reuseID = reuseID
            self.isUnary = isUnary
            self.owner = owner
            self.baseCount = base.count
            self.count = data.count * base.count
        }

        var startIndex: Int { 0 }
        var endIndex: Int { count }

        subscript(position: Int) -> _ViewList_ID {
            precondition(indices.contains(position), "view ID index out of range")
            precondition(baseCount > 0, "nonempty ForEach ID collection requires base IDs")

            let elementOffset = position / baseCount
            let baseOffset = position % baseCount
            let dataIndex = data.index(data.startIndex, offsetBy: elementOffset)
            let reuseID = reuseID.map { data[dataIndex][keyPath: $0] } ?? 0
            var id = base[baseOffset]

            switch idGenerator {
            case .keyPath:
                id.bind(
                    explicitID: idGenerator.makeID(
                        data: data,
                        index: dataIndex,
                        offset: elementOffset
                    ),
                    owner: owner,
                    isUnary: isUnary,
                    reuseID: reuseID
                )
            case .offset:
                id.bind(
                    explicitID: ForEachConstantID(elementOffset, owner),
                    owner: owner,
                    isUnary: isUnary,
                    reuseID: reuseID
                )
            }
            return id
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.owner == rhs.owner,
                  lhs.isUnary == rhs.isUnary,
                  lhs.baseCount == rhs.baseCount,
                  lhs.count == rhs.count,
                  lhs.base == rhs.base else {
                return false
            }
            return lhs.elementsEqual(rhs)
        }
    }

    /// Stores the identity sets reported for the current list transaction.
    struct Edits {
        var removes: Set<ID> = []
        var inserts: Set<ID> = []

        mutating func appendInsert(id: ID) {
            inserts.insert(id)
        }

        mutating func appendRemove(id: ID) {
            removes.insert(id)
        }
    }

    /// Defers inserted-ID projection until an edit query requires it.
    struct EditsBuilder {
        var data: Data
        var idGenerator: ForEach<Data, ID, Content>.IDGenerator
        var insertOffsets = IndexSetBuilder()
        var edits = Edits()

        mutating func appendInsert(atOffset offset: Int) {
            insertOffsets.append(offset)
        }

        mutating func removeInserts(afterOffset offset: Int) {
            insertOffsets.remove(afterOffset: offset)
        }

        mutating func finalize() -> Edits {
            for offset in insertOffsets.finalize() {
                let index = data.index(data.startIndex, offsetBy: offset)
                edits.appendInsert(
                    id: idGenerator.makeID(data: data, index: index, offset: offset)
                )
            }
            return edits
        }
    }

    /// Holds either pending insertion offsets or the finalized transaction edit sets.
    enum LazyEdits {
        case builder(EditsBuilder)
        case raw(Edits)

        /// Records an identity insertion without forcing pending offset projection.
        mutating func appendInsert(id: ID) {
            switch self {
            case .builder(var builder):
                // Retained identities are already known. Keep offset-based
                // insertions lazy while recording this identity immediately.
                builder.edits.appendInsert(id: id)
                self = .builder(builder)
            case .raw(var edits):
                edits.appendInsert(id: id)
                self = .raw(edits)
            }
        }

        mutating func finalized() -> Edits {
            switch self {
            case .builder(var builder):
                let edits = builder.finalize()
                self = .raw(edits)
                return edits
            case .raw(let edits):
                return edits
            }
        }

        mutating func edit(for id: ID) -> _ViewList_Edit? {
            let edits = finalized()
            if edits.removes.contains(id) {
                return .removed
            }
            if edits.inserts.contains(id) {
                return .inserted
            }
            return nil
        }
    }

    var inputs: _ViewListInputs
    var parentSubgraph: AGSubgraph
    var info: Attribute<Info>?
    var list: Attribute<any ViewList>?
    var view: ForEach<Data, ID, Content>?
    var viewsPerElementCount: ViewsPerElementCount
    var viewCounts: [Int]
    var viewCountStyle: _ViewList_IteratorStyle
    var items: [ID: Item] = [:]
    var edits: LazyEdits = .raw(Edits())
    var lastTransaction = TransactionID()
    var firstInsertionOffset: Int
    var contentID: Int = 0
    var seed: UInt32 = 0
    var createdAllItems: Bool
    var evictionSeed: UInt32
    var pendingEviction: Bool
    var evictedIDs: Set<ID>
    var matchingStrategyCache: [ObjectIdentifier: IDTypeMatchingStrategy]

    init(inputs: _ViewListInputs) {
        guard let parentSubgraph = AGSubgraph.current else {
            fatalError("ForEachState.init(inputs:) requires an active parent subgraph.")
        }
        self.inputs = inputs
        self.parentSubgraph = parentSubgraph
        if let debugReplaceableViewCount = inputs.debugReplaceableViewCount {
            self.viewsPerElementCount = .countingDebugReplaceableViews(
                debugReplaceableViewCount
            )
        } else {
            self.viewsPerElementCount = .uninitialized
        }
        self.viewCounts = []
        self.viewCountStyle = _ViewList_IteratorStyle(value: 2)
        self.firstInsertionOffset = .max
        self.createdAllItems = false
        self.evictionSeed = 0
        self.pendingEviction = false
        self.evictedIDs = []
        self.matchingStrategyCache = [:]
    }

    /// Returns the rule context that owns this state's generation output.
    var context: AnyRuleContext {
        guard let info else {
            fatalError("ForEachState.context accessed before info initialization.")
        }
        return AnyRuleContext(attribute: info.identifier)
    }

    /// Clears generation-local count prefixes and restores the default iterator style.
    func invalidateViewCounts() {
        viewCounts.removeAll(keepingCapacity: true)
        viewCountStyle = _ViewList_IteratorStyle(value: 2)
    }

    func update(view incomingView: ForEach<Data, ID, Content>) {
        guard let graph = _AGGraph.current else {
            fatalError("ForEachState.update(view:) called outside an active _AGGraph context.")
        }

        let previousView = self.view
        let previouslyCreatedAllItems = createdAllItems
        var view = incomingView
        if view.idGenerator.isConstant, let previousView {
            let count = view.data.count
            let initialCount = previousView.data.count
            if count != initialCount {
                Log.warning(
                    "\(ForEach<Data, ID, Content>.self) count (\(count)) " +
                    "!= its initial count (\(initialCount)). " +
                    "`ForEach(_:content:)` should only be used for *constant* data. " +
                    "Instead conform data to `Identifiable` or use " +
                    "`ForEach(_:id:content:)` and provide an explicit `id`!"
                )
            }
            // Offset-generated rows are a compile-time constant-data lane.
            // Keep the first collection even when a rebuilt view carries a
            // same-sized shifted range; only the content closure is refreshed.
            view.data = previousView.data
        }

        var previousIDs = Set<ID>()
        if let previousView {
            var previousIndex = previousView.data.startIndex
            var previousOffset = 0
            while previousIndex != previousView.data.endIndex {
                previousIDs.insert(
                    previousView.idGenerator.makeID(
                        data: previousView.data,
                        index: previousIndex,
                        offset: previousOffset
                    )
                )
                previousIndex = previousView.data.index(after: previousIndex)
                previousOffset += 1
            }
        }

        var currentIDs = Set<ID>()
        var currentOrder: [(id: ID, index: Data.Index, offset: Int)] = []
        var index = view.data.startIndex
        var offset = 0
        while index != view.data.endIndex {
            let id = view.idGenerator.makeID(data: view.data, index: index, offset: offset)
            currentOrder.append((id, index, offset))
            currentIDs.insert(id)
            index = view.data.index(after: index)
            offset += 1
        }

        var editsBuilder = EditsBuilder(data: view.data, idGenerator: view.idGenerator)
        if previouslyCreatedAllItems {
            // A heterogeneous count visited every prior row. The final
            // surviving row bounds the offsets that can be classified during
            // reconciliation; appended rows beyond it are classified lazily
            // when their item graphs are first created.
            var visitedIDs = Set<ID>()
            var lastExistingOffset: Int?
            for element in currentOrder
            where visitedIDs.insert(element.id).inserted && items[element.id] != nil {
                lastExistingOffset = element.offset
            }
            firstInsertionOffset = lastExistingOffset ?? 0
        } else {
            // Uniform list traversal may not have created every prior item, so
            // no finite reconciliation boundary can be claimed.
            firstInsertionOffset = .max
        }
        if previousView != nil {
            for id in previousIDs where !currentIDs.contains(id) {
                editsBuilder.edits.appendRemove(id: id)
                if let item = items[id], !item.isRemoved {
                    eraseItem(item)
                }
            }
            for element in currentOrder where !previousIDs.contains(element.id) {
                editsBuilder.appendInsert(atOffset: element.offset)
            }
            if firstInsertionOffset != .max {
                // Offsets strictly beyond the last known item are reported by
                // item(at:offset:) when those rows are actually materialized.
                editsBuilder.removeInserts(afterOffset: firstInsertionOffset + 1)
            }
        }

        self.view = view
        contentID = AGMakeUniqueID()
        seed &+= 1
        edits = .builder(editsBuilder)
        lastTransaction = TransactionID(graph: graph)
        invalidateViewCounts()
        createdAllItems = false

        var updatedIDs = Set<ID>()
        for element in currentOrder where updatedIDs.insert(element.id).inserted {
            let id = element.id
            if let item = items[id] {
                item.index = element.index
                item.offset = element.offset
                item.seed = seed
                item.isConstant = view.idGenerator.isConstant
            }
        }
    }

    /// Returns the retained item for one collection position, creating its child graph lazily.
    func item(at index: Data.Index, offset: Int) -> Item {
        guard let graph = _AGGraph.current else {
            fatalError("ForEachState.item(at:offset:) called outside an active _AGGraph context.")
        }
        guard let view, let info else {
            fatalError("ForEachState.item(at:offset:) requires initialized view and info attributes.")
        }

        let id = view.idGenerator.makeID(data: view.data, index: index, offset: offset)
        evictedIDs.remove(id)
        // Every visit schedules one host-seed eviction pass. The pass resets
        // the visited item's TTL while aging only items that remain untouched.
        pendingEviction = true
        if let item = items[id] {
            if item.seed == seed, item.offset != offset {
                if !item.hasWarned {
                    Log.warning(
                        "\(ForEach<Data, ID, Content>.self): the ID \(id) " +
                        "occurs multiple times within the collection, " +
                        "this will give undefined results!"
                    )
                    item.hasWarned = true
                }
                item.timeToLive = 8
                return item
            }
            if item.isRemoved {
                uneraseItem(item)
            }
            item.index = index
            item.offset = offset
            item.seed = seed
            item.isConstant = view.idGenerator.isConstant
            item.timeToLive = 8
            return item
        }

        let subgraph = AGSubgraph.withCurrent(parentSubgraph) {
            AGSubgraph()
        }
        let reuseID = view.reuseID.map { view.data[index][keyPath: $0] } ?? 0
        let item = Item(
            id: id,
            reuseID: reuseID,
            views: .staticList(.merged([])),
            subgraph: subgraph,
            state: self,
            index: index,
            offset: offset,
            contentID: contentID,
            seed: seed,
            isConstant: view.idGenerator.isConstant
        )

        // Child source evaluation can begin while its list wiring is constructed.
        // Publish the identity first so ForEachChild can resolve the same generation.
        items[id] = item

        let contentAttribute: Attribute<Content> = AGSubgraph.withCurrent(subgraph) {
            graph.makeStatefulRule(
                ForEachChild<Data, ID, Content>(
                    _info: info,
                    id: id
                )
            )
        }
        let outputs = AGSubgraph.withCurrent(subgraph) {
            Content._makeViewList(
                view: _GraphValue(_attribute: contentAttribute),
                inputs: inputs
            )
        }
        let viewsPerElement: Int?
        if let staticCount = outputs.staticCount {
            viewsPerElement = staticCount
        } else {
            switch viewsPerElementCount {
            case .uninitialized, .countingDebugReplaceableViews:
                viewsPerElement = Content._viewListCount(inputs: inputs.countInputs)
            case .resolved, .indeterminate:
                viewsPerElement = nil
            }
        }
        resolveViewsPerElement(from: viewsPerElement)

        item.views = outputs.views
        if case .dynamicList(let base, let modifier) = outputs.views {
            let resolvedBase: Attribute<any ViewList>
            if let modifier {
                resolvedBase = AGSubgraph.withCurrent(subgraph) {
                    graph.makeRule {
                        var list = base.value
                        modifier.apply(to: &list)
                        return list
                    }
                }
            } else {
                resolvedBase = base
            }
            let wrapped: Attribute<any ViewList> = AGSubgraph.withCurrent(subgraph) {
                graph.makeRule(ItemList(_base: resolvedBase, item: item))
            }
            // Preserve static output storage on Item. Only an already-dynamic
            // child needs the lifetime wrapper around its list attribute.
            item.views = .dynamicList(wrapped, nil)
        }
        if offset >= firstInsertionOffset {
            // Rows beyond the reconciled prefix have no prior item graph from
            // which to infer identity. Record their concrete ID at creation
            // time without finalizing the remaining offset edits.
            edits.appendInsert(id: id)
        }

        return item
    }

    /// Evicts at most 64 expired items and defers overflow to a later update.
    func evictItems(seed: UInt32) {
        guard evictionSeed != seed, pendingEviction else {
            return
        }
        evictionSeed = seed

        var expiredItems: [Item] = []
        expiredItems.reserveCapacity(min(items.count, 64))
        for item in items.values {
            guard !item.isRemoved else {
                continue
            }

            let nextTimeToLive = item.timeToLive &- 1
            if nextTimeToLive != 0 {
                item.timeToLive = nextTimeToLive
                continue
            }

            // A retained list slice owns an additional reference. Leave the
            // item at the final TTL so a later update can retry after release.
            guard item.refcount == 1 else {
                continue
            }

            evictedIDs.insert(item.id)
            expiredItems.append(item)
            if expiredItems.count == 64 {
                break
            }
        }

        for item in expiredItems {
            eraseItem(item)
        }
        pendingEviction = expiredItems.count == 64
    }

    /// Resolves a uniform per-element count from static child-list metadata.
    private func resolveViewsPerElement(from staticCount: Int?) {
        switch viewsPerElementCount {
        case .uninitialized:
            if let staticCount {
                viewsPerElementCount = .resolved(staticCount)
            } else {
                viewsPerElementCount = .indeterminate
            }
        case .countingDebugReplaceableViews(let box):
            switch box.value {
            case .counting(let count):
                viewsPerElementCount = .resolved(count)
            case .uninitialized:
                if let staticCount {
                    box.value = .counting(staticCount)
                    viewsPerElementCount = .resolved(staticCount)
                } else {
                    box.value = .indeterminate
                    viewsPerElementCount = .indeterminate
                }
            case .indeterminate:
                viewsPerElementCount = .indeterminate
            }
        case .resolved, .indeterminate:
            break
        }
    }

    /// Materializes at most the first element needed to classify uniform list counts.
    func fetchViewsPerElement() -> Int? {
        if let resolved = viewsPerElementCount.resolvedCount {
            return resolved
        }
        guard case .uninitialized = viewsPerElementCount,
              let view,
              view.data.startIndex != view.data.endIndex else {
            return nil
        }
        _ = item(at: view.data.startIndex, offset: 0)
        return viewsPerElementCount.resolvedCount
    }

    /// Visits data-order items while using a uniform count to skip untouched elements.
    @discardableResult
    func forEachItem(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        do body: (inout Int, _ViewList_IteratorStyle, Item) -> Bool
    ) -> Bool {
        guard let view else {
            return true
        }

        let viewsPerElement = fetchViewsPerElement()
        var index = view.data.startIndex
        var offset = 0
        while index != view.data.endIndex {
            if let viewsPerElement,
               viewsPerElement > 0,
               from >= viewsPerElement {
                from -= viewsPerElement
            } else {
                let item = item(at: index, offset: offset)
                if !body(&from, style, item) {
                    return false
                }
            }
            index = view.data.index(after: index)
            offset += 1
        }
        return true
    }

    /// Returns the concrete list currently stored by an item.
    private func list(for item: Item) -> any ViewList {
        switch item.views {
        case .staticList(let elements):
            return BaseViewList(
                elements: elements,
                implicitID: inputs.implicitID,
                traitKeys: inputs.traitKeys,
                traits: inputs._traits.attribute?.value ?? ViewTraitCollection()
            )
        case .dynamicList(let attribute, let modifier):
            var list = attribute.value
            modifier?.apply(to: &list)
            return list
        }
    }

    /// Caches either the uniform product or cumulative heterogeneous child counts.
    func count(style: _ViewList_IteratorStyle) -> Int {
        guard let view else {
            return 0
        }
        let dataCount = view.data.count
        guard dataCount > 0 else {
            return 0
        }
        if let viewsPerElement = fetchViewsPerElement() {
            return dataCount * viewsPerElement
        }
        if viewCountStyle == style,
           viewCounts.count == dataCount,
           let count = viewCounts.last {
            return count
        }

        viewCounts.removeAll(keepingCapacity: true)
        viewCountStyle = style
        var total = 0
        var from = 0
        _ = forEachItem(from: &from, style: style) { _, style, item in
            total += self.list(for: item).count(style: style)
            self.viewCounts.append(total)
            return true
        }
        createdAllItems = true
        return total
    }

    /// Estimates the dynamic list size without bypassing the established count cache.
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        count(style: style)
    }

    /// Builds the uniform, data-dependent ID collection without materializing every item.
    var viewIDs: _ViewList_ID_Views? {
        guard let view,
              let owner = list?.identifier,
              let viewsPerElement = fetchViewsPerElement() else {
            return nil
        }

        var baseIDs: _ViewList_ID_Views?
        var from = 0
        _ = forEachItem(
            from: &from,
            style: viewCountStyle
        ) { _, style, item in
            let childList = self.list(for: item)
            if let ids = childList.viewIDs {
                baseIDs = ids
            } else {
                let count = childList.count(style: style)
                baseIDs = _ViewList_ID._Views(
                    StaticViewIDCollection(count: count),
                    isDataDependent: false
                )
            }
            return false
        }

        guard let baseIDs,
              !baseIDs.isDataDependent,
              baseIDs.count == viewsPerElement else {
            return nil
        }
        let collection = ForEachViewIDCollection(
            base: baseIDs,
            data: view.data,
            idGenerator: view.idGenerator,
            reuseID: view.reuseID,
            isUnary: viewsPerElement == 1,
            owner: owner
        )
        return _ViewList_ID._Views(collection, isDataDependent: true)
    }

    /// Appends fixed-count IDs through homogeneous typed buffers.
    func appendViewIDs<List: ViewList>(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        viewList: List
    ) {
        guard let view else {
            return
        }

        guard let viewsPerElement = fetchViewsPerElement() else {
            appendViewIDsForDynamicChildCount(
                into: &accumulator,
                viewList
            )
            return
        }

        var baseIDs: BaseIDs?
        var from = 0
        _ = forEachItem(
            from: &from,
            style: viewCountStyle
        ) { _, _, item in
            switch item.views {
            case .staticList(let elements):
                baseIDs = .staticCount(elements.count)
            case .dynamicList:
                baseIDs = self.list(for: item).viewIDs.map(BaseIDs.viewIDs)
            }
            return false
        }

        guard let baseIDs else {
            accumulator.appendSlowPath(viewList)
            return
        }

        let childShape: (indices: Range<Int32>?, views: [(index: Int32, implicitID: Int32)]?)
        switch baseIDs {
        case .staticCount(let count):
            guard count == viewsPerElement,
                  let upperBound = Int32(exactly: count) else {
                accumulator.appendSlowPath(viewList)
                return
            }
            childShape = (0..<upperBound, nil)
        case .viewIDs(let ids):
            guard !ids.isDataDependent, ids.count == viewsPerElement else {
                accumulator.appendSlowPath(viewList)
                return
            }
            let childViews = ids.map { id in
                let canonical = id.canonicalID
                return (
                    index: canonical._index,
                    implicitID: canonical.implicitID
                )
            }
            childShape = (nil, childViews)
        }

        if viewsPerElement == 1 {
            switch view.idGenerator {
            case .keyPath(let keyPath):
                appendViewIDsForSingleChildView(
                    into: &accumulator,
                    explicitIDKeyPath: keyPath
                )
            case .offset:
                appendViewIDsForSingleChildView(
                    into: &accumulator,
                    explicitIDOffsets: 0..<view.data.count
                )
            }
            return
        }

        switch (childShape.indices, childShape.views, view.idGenerator) {
        case (.some(let indices), _, .keyPath(let keyPath)):
            appendViewIDsForMultipleChildren(
                into: &accumulator,
                childViewIndices: indices,
                explicitIDKeyPath: keyPath
            )
        case (.some(let indices), _, .offset):
            appendViewIDsForMultipleChildren(
                into: &accumulator,
                childViewIndices: indices,
                explicitIDOffsets: 0..<view.data.count
            )
        case (_, .some(let childViews), .keyPath(let keyPath)):
            appendViewIDsForMultipleChildren(
                into: &accumulator,
                childViews: childViews,
                explicitIDKeyPath: keyPath
            )
        case (_, .some(let childViews), .offset):
            appendViewIDsForMultipleChildren(
                into: &accumulator,
                childViews: childViews,
                explicitIDOffsets: 0..<view.data.count
            )
        default:
            accumulator.appendSlowPath(viewList)
        }
    }

    /// Emits one typed explicit ID per collection element.
    private func appendViewIDsForSingleChildView(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        explicitIDKeyPath: KeyPath<Data.Element, ID>
    ) {
        guard let view else {
            return
        }
        let values = ContiguousArray<ID>(
            unsafeUninitializedCapacity: view.data.count
        ) { buffer, initializedCount in
            var position = 0
            for element in view.data {
                buffer.baseAddress!.advanced(by: position).initialize(
                    to: element[keyPath: explicitIDKeyPath]
                )
                position += 1
            }
            initializedCount = position
        }
        accumulator.append(contentsOf: values)
    }

    /// Emits one owner-scoped constant ID per collection offset.
    private func appendViewIDsForSingleChildView(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        explicitIDOffsets: Range<Int>
    ) {
        guard let owner = list?.identifier else {
            fatalError("ForEachState.appendViewIDs requires an initialized list attribute.")
        }
        let values = ContiguousArray<ForEachConstantID>(
            unsafeUninitializedCapacity: explicitIDOffsets.count
        ) { buffer, initializedCount in
            var position = 0
            for offset in explicitIDOffsets {
                buffer.baseAddress!.advanced(by: position).initialize(
                    to: ForEachConstantID(offset, owner)
                )
                position += 1
            }
            initializedCount = position
        }
        accumulator.append(contentsOf: values)
    }

    /// Expands regular child indices for each key-path identity in one typed allocation.
    private func appendViewIDsForMultipleChildren(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        childViewIndices: Range<Int32>,
        explicitIDKeyPath: KeyPath<Data.Element, ID>
    ) {
        guard let view else {
            return
        }
        let childCount = childViewIndices.count
        let count = view.data.count * childCount
        accumulator.appendWithUnsafeOutputBuffer(
            explicitID: ID.self,
            count: count
        ) { buffer in
            var dataOffset = 0
            for element in view.data {
                let explicitID = element[keyPath: explicitIDKeyPath]
                var childOffset = 0
                for childIndex in childViewIndices {
                    buffer.initialize(
                        at: dataOffset * childCount + childOffset,
                        index: childIndex,
                        implicitID: 0,
                        explicitID: explicitID
                    )
                    childOffset += 1
                }
                dataOffset += 1
            }
        }
    }

    /// Expands regular child indices for each constant-range offset.
    private func appendViewIDsForMultipleChildren(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        childViewIndices: Range<Int32>,
        explicitIDOffsets: Range<Int>
    ) {
        guard let owner = list?.identifier else {
            fatalError("ForEachState.appendViewIDs requires an initialized list attribute.")
        }
        appendConstantViewIDs(
            into: &accumulator,
            childViews: childViewIndices.map { (index: $0, implicitID: 0) },
            explicitIDOffsets: explicitIDOffsets,
            owner: owner
        )
    }

    /// Expands irregular child index/implicit-ID pairs for each key-path identity.
    private func appendViewIDsForMultipleChildren(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        childViews: [(index: Int32, implicitID: Int32)],
        explicitIDKeyPath: KeyPath<Data.Element, ID>
    ) {
        guard let view else {
            return
        }
        let childCount = childViews.count
        let count = view.data.count * childCount
        accumulator.appendWithUnsafeOutputBuffer(
            explicitID: ID.self,
            count: count
        ) { buffer in
            var dataOffset = 0
            for element in view.data {
                let explicitID = element[keyPath: explicitIDKeyPath]
                for (childOffset, childView) in childViews.enumerated() {
                    buffer.initialize(
                        at: dataOffset * childCount + childOffset,
                        index: childView.index,
                        implicitID: childView.implicitID,
                        explicitID: explicitID
                    )
                }
                dataOffset += 1
            }
        }
    }

    /// Expands irregular child index/implicit-ID pairs for constant-range offsets.
    private func appendViewIDsForMultipleChildren(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        childViews: [(index: Int32, implicitID: Int32)],
        explicitIDOffsets: Range<Int>
    ) {
        guard let owner = list?.identifier else {
            fatalError("ForEachState.appendViewIDs requires an initialized list attribute.")
        }
        appendConstantViewIDs(
            into: &accumulator,
            childViews: childViews,
            explicitIDOffsets: explicitIDOffsets,
            owner: owner
        )
    }

    /// Builds the typed canonical carrier used by constant-range multi-child rows.
    private func appendConstantViewIDs(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        childViews: [(index: Int32, implicitID: Int32)],
        explicitIDOffsets: Range<Int>,
        owner: AGAttribute
    ) {
        let childCount = childViews.count
        let count = explicitIDOffsets.count * childCount
        let values = ContiguousArray<TypedCanonicalViewID<ForEachConstantID>>(
            unsafeUninitializedCapacity: count
        ) { buffer, initializedCount in
            var position = 0
            for offset in explicitIDOffsets {
                let explicitID = ForEachConstantID(offset, owner)
                for childView in childViews {
                    buffer.baseAddress!.advanced(by: position).initialize(
                        to: TypedCanonicalViewID(
                            index: childView.index,
                            implicitID: childView.implicitID,
                            explicitID: explicitID
                        )
                    )
                    position += 1
                }
            }
            initializedCount = position
        }
        accumulator.append(contentsOf: values)
    }

    /// Traverses dynamic nodes while preserving the active transformed explicit-ID scope.
    private func appendViewIDsForDynamicChildCount<List: ViewList>(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        _ viewList: List
    ) {
        var from = 0
        _ = viewList.applyNodes(
            from: &from,
            style: viewCountStyle,
            list: nil,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, node, transform in
            var transformedID = _ViewList_ID(implicitID: 0)
            transform.bindID(&transformedID)
            if let explicit = transformedID.explicitIDs.first,
               let explicitID = explicit.id.base as? any Hashable {
                appendViewIDsForDynamicNode(
                    into: &accumulator,
                    explicitID: explicitID,
                    isUnary: explicit.isUnary,
                    node: node,
                    transform: transform
                )
            } else {
                appendViewIDsForDynamicNode(
                    into: &accumulator,
                    node: node,
                    transform: transform
                )
            }
            return true
        }
    }

    /// Opens the transformed ID's concrete type for one scoped node append.
    private func appendViewIDsForDynamicNode<ExplicitID: Hashable>(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        explicitID: ExplicitID,
        isUnary: Bool,
        node: _ViewList_Node,
        transform: _ViewList_TemporarySublistTransform
    ) {
        accumulator.withExplicitID(explicitID, isUnary: isUnary) {
            appendViewIDsForDynamicNode(
                into: &$0,
                node: node,
                transform: transform
            )
        }
    }

    /// Dispatches each dynamic node through its native-shaped ID producer.
    private func appendViewIDsForDynamicNode(
        into accumulator: inout HeterogeneousViewIDsAccumulator,
        node: _ViewList_Node,
        transform: _ViewList_TemporarySublistTransform
    ) {
        switch node {
        case .list(let list, _):
            list.appendViewIDs(into: &accumulator)
        case .group(let group):
            group.appendViewIDs(into: &accumulator)
        case .sublist(var sublist):
            transform.apply(to: &sublist)
            sublist.appendViewIDs(into: &accumulator)
        case .section(let section):
            section.appendViewIDs(into: &accumulator)
        }
    }

    /// Returns the trait-key surface of the first representative child list.
    var traitKeys: ViewTraitKeys? {
        var result: ViewTraitKeys?
        var from = 0
        _ = forEachItem(
            from: &from,
            style: viewCountStyle
        ) { _, _, item in
            result = self.list(for: item).traitKeys
            return false
        }
        return result
    }

    /// Finds the first transformed child offset, using the uniform ID collection when available.
    func firstOffset<A: Hashable>(
        forID id: A,
        style: _ViewList_IteratorStyle
    ) -> Int? {
        guard view != nil else {
            return nil
        }

        let strategy = matchingStrategy(for: A.self)
        var from = 0
        var found: Int?
        _ = forEachItem(from: &from, style: style) { _, style, item in
            if self.matches(item.id, id, using: strategy) {
                found = self.offset(before: item, style: style)
                return false
            }

            let childList = self.list(for: item)
            if let childOffset = childList.firstOffset(forID: id, style: style) {
                let prefix = self.offset(before: item, style: style)
                found = prefix + childOffset
                return false
            }
            return true
        }
        return found
    }

    /// Selects and caches the comparison route for an external ID type.
    private func matchingStrategy<A: Hashable>(
        for _: A.Type
    ) -> IDTypeMatchingStrategy {
        let typeID = ObjectIdentifier(A.self)
        if let cached = matchingStrategyCache[typeID] {
            return cached
        }

        let strategy: IDTypeMatchingStrategy
        if A.self == ID.self {
            strategy = .exact
        } else if ID.self == AnyHashable.self {
            strategy = .anyHashable
        } else if ID.self is any HasCustomIDRepresentation.Type {
            strategy = .customIDRepresentation
        } else {
            strategy = .noMatch
        }
        matchingStrategyCache[typeID] = strategy
        return strategy
    }

    /// Compares a data element's ID using the strategy selected for the query type.
    private func matches<A: Hashable>(
        _ elementID: ID,
        _ target: A,
        using strategy: IDTypeMatchingStrategy
    ) -> Bool {
        switch strategy {
        case .exact:
            guard let target = target as? ID else {
                return false
            }
            return elementID == target
        case .anyHashable:
            return AnyHashable(elementID) == AnyHashable(target)
        case .customIDRepresentation:
            return (elementID as? any HasCustomIDRepresentation)?
                .containsID(target) ?? false
        case .noMatch:
            return false
        }
    }

    /// Computes the prefix count for an item, extending the heterogeneous cache as needed.
    func offset(before item: Item, style: _ViewList_IteratorStyle) -> Int {
        if let viewsPerElement = fetchViewsPerElement() {
            return item.offset * viewsPerElement
        }
        if viewCountStyle == style, item.offset > 0,
           viewCounts.indices.contains(item.offset - 1) {
            return viewCounts[item.offset - 1]
        }

        guard let view else {
            return 0
        }
        if viewCountStyle != style {
            viewCounts.removeAll(keepingCapacity: true)
            viewCountStyle = style
        }
        var total = viewCounts.last ?? 0
        var offset = viewCounts.count
        var index = view.data.index(view.data.startIndex, offsetBy: offset)
        while index != view.data.endIndex, offset < item.offset {
            let current = self.item(at: index, offset: offset)
            total += list(for: current).count(style: style)
            viewCounts.append(total)
            offset += 1
            index = view.data.index(after: index)
        }
        return total
    }

    /// Applies identity and lifetime transforms while preserving the outer list anchor.
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list listAttribute: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        let isUnary = fetchViewsPerElement() == 1
        return forEachItem(from: &from, style: style) { from, style, item in
            let itemTransform = transform.withPushedItem(
                Transform(
                    item: item,
                    bindID: true,
                    isUnary: isUnary,
                    isConstant: item.isConstant
                )
            )
            return self.list(for: item).applyNodes(
                from: &from,
                style: style,
                list: listAttribute,
                transform: itemTransform,
                to: to
            )
        }
    }

    /// Detaches an item while retained list slices keep its subgraph alive.
    func eraseItem(_ item: Item) {
        guard !item.isRemoved else {
            return
        }
        item.subgraph.willRemove()
        item.subgraph.removeFromParent()
        item.isRemoved = true
        item.timeToLive = 0
        item.release()
    }

    /// Restores a detached item when its identity returns before final release.
    func uneraseItem(_ item: Item) {
        guard item.isRemoved, AGSubgraphIsValid(item.subgraph) else {
            return
        }
        item.refcount &+= 1
        item.isRemoved = false
        item.timeToLive = 8
        parentSubgraph.addChild(item.subgraph)
        item.subgraph.didReinsert()
    }

    func edit(forID id: _ViewList_ID, since transaction: TransactionID) -> _ViewList_Edit? {
        guard let owner = list?.identifier else {
            return nil
        }

        let explicitID: ID?
        if view?.idGenerator.isConstant == true,
           let constantID: ForEachConstantID = id.explicitID(owner: owner) {
            explicitID = items.values.first { $0.offset == constantID.offset }?.id
        } else {
            explicitID = id.explicitID(owner: owner)
        }
        guard let explicitID else {
            return nil
        }

        if transaction >= lastTransaction,
           let edit = edits.edit(for: explicitID) {
            return edit
        }

        guard let item = items[explicitID], item.seed == seed else {
            return nil
        }
        return list(for: item).edit(forID: id, since: transaction)
    }
}

extension ForEachState {
    /// Applies element identity and lifetime state to every nested child sublist.
    struct Transform: _ViewList_SublistTransform_Item {
        var item: Item
        var bindID: Bool
        var isUnary: Bool
        var isConstant: Bool

        func apply(sublist: inout _ViewList_Sublist) {
            if bindID {
                item.bindID(
                    &sublist.id,
                    isUnary: isUnary,
                    isConstant: isConstant
                )
            }
            sublist.elements.wrap(subgraph: item)
            item.applyTraits(to: &sublist.traits)
        }

        func bindID(_ id: inout _ViewList_ID) {
            guard bindID else {
                return
            }
            item.bindID(&id, isUnary: isUnary, isConstant: isConstant)
        }

        func wrapSubgraph(into storage: inout _ViewList_SublistSubgraphStorage) {
            if !storage.subgraphs.contains(where: { $0 === item }) {
                storage.subgraphs.append(item)
            }
        }
    }
}

/// Re-evaluates one element's content from the state generation captured by Info.
private struct ForEachChild<Data, ID, Content>: StatefulRule
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    typealias Value = Content

    var _info: Attribute<ForEachState<Data, ID, Content>.Info>
    var id: ID

    mutating func updateValue() {
        let info = _info.value
        guard let item = info.state.items[id],
              item.seed == info.seed,
              let forEach = info.state.view else {
            return
        }
        _AGGraph.setStatefulOutput(forEach.content(forEach.data[item.index]))
    }
}

// MARK: - ForEachList

/// Exposes the reconciled element states as one sublist node per collection element.
struct ForEachList<Data, ID, Content>: ViewList
    where Data: RandomAccessCollection, ID: Hashable, Content: View {

    /// Publishes each list generation and invalidates generation-local count caches.
    struct Init: StatefulRule {
        typealias Value = any ViewList

        var _info: Attribute<ForEachState<Data, ID, Content>.Info>
        var seed: UInt32

        mutating func updateValue() {
            let info = _info.value
            info.state.invalidateViewCounts()
            seed &+= 1
            value = ForEachList(state: info.state, seed: seed)
        }
    }

    var state: ForEachState<Data, ID, Content>
    var seed: UInt32

    func count(style: _ViewList_IteratorStyle) -> Int {
        state.count(style: style)
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        state.estimatedCount(style: style)
    }

    var traitKeys: ViewTraitKeys? { state.traitKeys }
    var viewIDs: _ViewList_ID_Views? { state.viewIDs }

    func appendViewIDs(into accumulator: inout HeterogeneousViewIDsAccumulator) {
        state.appendViewIDs(into: &accumulator, viewList: self)
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        state.applyNodes(
            from: &from,
            style: style,
            list: list,
            transform: transform,
            to: to
        )
    }

    func edit(forID id: _ViewList_ID, since transaction: TransactionID) -> _ViewList_Edit? {
        state.edit(forID: id, since: transaction)
    }

    func firstOffset<A: Hashable>(
        forID id: A,
        style: _ViewList_IteratorStyle
    ) -> Int? {
        state.firstOffset(forID: id, style: style)
    }

    func print(into printer: inout SExpPrinter) {
    }
}

/// Names a constant-range element by local offset within a specific list owner.
struct ForEachConstantID: Hashable {
    var offset: Int
    var owner: AGAttribute

    init(_ offset: Int, _ owner: AGAttribute) {
        self.offset = offset
        self.owner = owner
    }

    init<Value>(_ offset: Int, _ owner: Attribute<Value>) {
        self.init(offset, owner.identifier)
    }
}

@available(*, unavailable)
extension ForEach: Sendable {
}

extension ForEach where ID == Data.Element.ID, Content: View, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

extension ForEach where Content: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
        self.idGenerator = .keyPath(id)
        self.reuseID = nil
    }
}

extension ForEach where Content: View {
    public init<C>(_ data: Binding<C>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, ID == C.Element.ID, C: MutableCollection, C: RandomAccessCollection, C.Element: Identifiable, C.Index: Hashable {
        self.init(data, id: \.id, content: content)
    }

    public init<C>(_ data: Binding<C>, id: KeyPath<C.Element, ID>, @ViewBuilder content: @escaping (Binding<C.Element>) -> Content) where Data == LazyMapSequence<C.Indices, (C.Index, ID)>, C: MutableCollection, C: RandomAccessCollection, C.Index: Hashable {
        let elementIDs = data.wrappedValue.indices.lazy.map { index in
            (index, data.wrappedValue[index][keyPath: id])
        }
        self.init(elementIDs, id: \.1) { (index, _) in
            let elementBinding = Binding {
                data.wrappedValue[index]
            } set: {
                data.wrappedValue[index] = $0
            }
            content(elementBinding)
        }
    }
}

extension ForEach where Data == ForEachSectionCollection<Content>, ID == SectionConfiguration.ID, Content: View {
    public init<V>(
        sections view: V,
        @ViewBuilder content: @escaping (SectionConfiguration) -> Content
    ) where V: View {
        self.init(
            ForEachSectionCollection(subviewOf: view, content: content),
            id: \.id,
            content: content
        )
    }
}

extension ForEach where Data == Range<Int>, ID == Int, Content: View {
    // Range-based initializer.
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = data
        self.content = content
        self.idGenerator = .offset
        self.reuseID = nil
    }
}

extension ForEach: DynamicViewContent where Content: View {
}

/// Exposes the collection that drives a view's dynamically identified children.
public protocol DynamicViewContent<Data>: View {
    associatedtype Data: Collection
    var data: Self.Data { get }
}

extension ModifiedContent: DynamicViewContent where Content: DynamicViewContent, Modifier: ViewModifier {
    public var data: Content.Data {
        content.data
    }

    public typealias Data = Content.Data
}
