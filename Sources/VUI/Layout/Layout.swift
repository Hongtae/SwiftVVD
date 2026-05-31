//
//  File: Layout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Layout AG rules

/// AG Rule: computes child geometries for a layout container.
/// Reads parentSize/parentPosition and calls LayoutComputer.childGeometries via the box vtable.
private struct LayoutChildGeometries: Rule {
    typealias Value = [ViewGeometry]
    var parentSize: Attribute<ViewSize>
    var parentPosition: Attribute<CGPoint>
    var layoutComputer: Attribute<LayoutComputer>
    func updateValue() -> [ViewGeometry] {
        let lc = layoutComputer.value
        return lc.box.childGeometries_(at: parentSize.value, origin: parentPosition.value)
    }
}

/// AG Rule: extracts one ViewGeometry from the LayoutChildGeometries output by index.
private struct LayoutChildGeometry: Rule {
    typealias Value = ViewGeometry
    var geometriesAttr: Attribute<[ViewGeometry]>
    var index: Int
    func updateValue() -> ViewGeometry {
        let geoms = geometriesAttr.value
        guard index < geoms.count else {
            return ViewGeometry(origin: .zero,
                                dimensions: ViewDimensions(guideComputer: .defaultValue, size: .zero))
        }
        return geoms[index]
    }
}

/// StatefulRule: produces LayoutComputer wrapping ViewLayoutEngine<L> for a static child list.
/// Re-fires when layoutAttr changes (e.g. animating spacing). Child LC deps are tracked
/// downstream by LayoutChildGeometries (which calls childGeometries via ViewLayoutEngine).
private struct StaticLayoutComputer<L: Layout>: StatefulRule {
    typealias Value = LayoutComputer
    var layoutAttr: Attribute<L>
    var children: [LayoutProxyAttributes]
    var layoutDirection: LayoutDirection
    mutating func updateValue() {
        let layout = layoutAttr.value
        let engine = ViewLayoutEngine(layout: layout, children: children, layoutDirection: layoutDirection)
        let box = LayoutEngineBox(engine: engine)
        AttributeGraph.setStatefulOutput(LayoutComputer(box: box))
    }
}

/// Dynamic container storage used by DynamicContainerInfo.
private enum DynamicContainer {
    /// Per-item lifecycle and layout state.
    final class ItemInfo {
        var subgraph: AGSubgraph
        var uniqueId: _ViewList_ID.Canonical
        var viewCount: Int
        var outputs: _ViewOutputs
        var needsTransitions: Bool
        // FIXME: Transition listener/completion is intentionally not wired yet.
        // Removed items are retained for one update as a phase-2 suffix until
        // AnyTransition, TransitionPhase, and animation completion infrastructure exists.
        var listener: AnyObject?
        var zIndex: Double
        var removalOrder: Int
        var precedingViewCount: Int
        var resetSeed: UInt32
        var phase: UInt8
        // Cache for non-unary DynamicContainer items. Keeps each materialized child
        // addressable until the multi-output storage path is fully wired.
        var layoutAttributes: [LayoutProxyAttributes]
        var preferenceOutputs: [PreferencesOutputs]

        init(
            subgraph: AGSubgraph,
            uniqueId: _ViewList_ID.Canonical,
            viewCount: Int,
            outputs: _ViewOutputs,
            layoutAttributes: [LayoutProxyAttributes],
            preferenceOutputs: [PreferencesOutputs],
            needsTransitions: Bool = false,
            listener: AnyObject? = nil,
            zIndex: Double = 0,
            removalOrder: Int = 0,
            precedingViewCount: Int = 0,
            resetSeed: UInt32 = 0,
            phase: UInt8 = 1
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
            self.layoutAttributes = layoutAttributes
            self.preferenceOutputs = preferenceOutputs
        }

        func invalidate() {
            subgraph.invalidate()
            subgraph.removeFromParent()
        }
    }

        /// Collection state for dynamic layout items. Equality compares the seed field.
        struct Info: Equatable {
        var items: [ItemInfo] = []
        var indexMap: [_ViewList_ID.Canonical: Int] = [:]
        var displayMap: [UInt32]?
        var removedCount: Int = 0
        var unusedCount: Int = 0
        var allUnary: Bool = true
        var seed: UInt32 = 0

        static func == (lhs: Info, rhs: Info) -> Bool {
            lhs.seed == rhs.seed
        }

        func viewIndex(id: _ViewList_ID.Canonical) -> Int? {
            indexMap[id]
        }

        func item(for id: _ViewList_ID.Canonical) -> ItemInfo? {
            guard let index = indexMap[id], items.indices.contains(index) else { return nil }
            return items[index]
        }

        var activeItems: ArraySlice<ItemInfo> {
            let activeEnd = max(0, items.count - unusedCount - removedCount)
            return items.prefix(activeEnd)
        }

        mutating func replaceItems(
            active activeItems: [ItemInfo],
            removed removedItems: [ItemInfo] = [],
            // FIXME: Scroll retained-unused lifecycle is not wired yet.
            // Keep this empty until scroll-specific DynamicContainer item geometry
            // and retained-unused lifecycle rules are implemented.
            unused unusedItems: [ItemInfo] = []
        ) {
            let oldIdentity = items.map { ItemIdentity(item: $0) }
            let oldDisplayMap = displayMap
            let oldAllUnary = allUnary
            let oldRemovedCount = removedCount
            let oldUnusedCount = unusedCount
            let newItems = activeItems + removedItems + unusedItems
            let newIdentity = newItems.map { ItemIdentity(item: $0) }
            items = newItems
            removedCount = removedItems.count
            unusedCount = unusedItems.count
            allUnary = !activeItems.contains { $0.viewCount != 1 }
            rebuildIndexMap()
            rebuildDisplayMap()
            if oldIdentity != newIdentity ||
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
            // zIndex/depth can produce displayMap. This currently covers stored values only.
            guard items.contains(where: { $0.zIndex != 0 }) else {
                displayMap = nil
                return
            }
            let activeEnd = max(0, items.count - unusedCount - removedCount)
            let activeRange = 0..<activeEnd
            let retainedEnd = activeEnd + removedCount
            let retainedRange = 0..<retainedEnd
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
                // At equal depth, phase-2 removals sort before active phase-1
                // items in the retained-inclusive segment.
                if lhs.phase != rhs.phase {
                    if lhs.phase == 2 { return true }
                    if rhs.phase == 2 { return false }
                }
                return lhsIndex < rhsIndex
            }.map { UInt32($0) }
        }

        private struct ItemIdentity: Equatable {
            var uniqueId: _ViewList_ID.Canonical
            var viewCount: Int
            var phase: UInt8

            init(item: ItemInfo) {
                self.uniqueId = item.uniqueId
                self.viewCount = item.viewCount
                self.phase = item.phase
            }
        }
    }
}

/// Stores layout attributes keyed by DynamicContainer item id and rebuilds the
/// sorted attribute cache when DynamicContainer.Info.seed changes.
private struct DynamicLayoutMap {
    var map: [_ViewList_ID.Canonical: [LayoutProxyAttributes]] = [:]
    var sortedArray: [LayoutProxyAttributes] = []
    var sortedSeeds: UInt32?

    mutating func set(_ attributes: [LayoutProxyAttributes], uniqueId: _ViewList_ID.Canonical) {
        if attributes.isEmpty {
            map.removeValue(forKey: uniqueId)
        } else {
            map[uniqueId] = attributes
        }
        sortedSeeds = nil
    }

    mutating func remove(uniqueId: _ViewList_ID.Canonical) {
        map.removeValue(forKey: uniqueId)
        sortedSeeds = nil
    }

    mutating func replace(with info: DynamicContainer.Info) {
        map.removeAll(keepingCapacity: true)
        sortedSeeds = nil
        for item in info.activeItems {
            set(item.layoutAttributes, uniqueId: item.uniqueId)
        }
    }

    mutating func attributes(info: DynamicContainer.Info) -> [LayoutProxyAttributes] {
        if sortedSeeds == info.seed { return sortedArray }

        let activeItems = info.activeItems
        let orderedItems: [DynamicContainer.ItemInfo]
        if let displayMap = info.displayMap {
            // When retained removals are present, displayMap starts with the
            // active segment and then appends a retained-inclusive segment.
            // FIXME: retained transition layout is incomplete. LayoutSubviews
            // only consumes the active prefix until transition listener/completion
            // and removed-item placement semantics are implemented.
            let activeDisplayMap = info.removedCount > 0 ?
                displayMap.prefix(activeItems.count) : displayMap[...]
            orderedItems = activeDisplayMap.compactMap { index in
                let i = Int(index)
                guard i >= activeItems.startIndex && i < activeItems.endIndex else { return nil }
                return info.items[i]
            }
        } else {
            orderedItems = Array(activeItems)
        }

        sortedArray = orderedItems.flatMap { item in
            let attributes = map[item.uniqueId] ?? item.layoutAttributes
            if attributes.isEmpty {
                return Array(repeating: LayoutProxyAttributes(), count: item.viewCount)
            }
            return attributes
        }
        sortedSeeds = info.seed
        return sortedArray
    }
}

/// StatefulRule: reconciles dynamic container items and publishes DynamicContainer.Info.
private struct DynamicContainerInfo: StatefulRule {
    typealias Value = DynamicContainer.Info
    var viewListAttr: Attribute<any ViewList>
    var inputs: _ViewInputs
    var info = DynamicContainer.Info()
    var retainedElements: [_ViewList_ID.Canonical: _ViewList_SubgraphRelease] = [:]

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("DynamicContainerInfo.updateValue called outside AG context.")
        }

        let capturedInputs = inputs
        let currentList = viewListAttr.value
        var from = 0
        var liveIDs = Set<_ViewList_ID.Canonical>()
        var orderedItems: [DynamicContainer.ItemInfo] = []
        var precedingViewCount = 0

        _ = _applySublists(in: currentList, from: &from, listAttribute: viewListAttr) { sublist in
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                let id = sublist.id.elementID(at: elementIndex).canonicalID
                liveIDs.insert(id)

                let viewCount = sublist.elements.count
                // allUnary is false when any active DynamicContainer item reports
                // viewCount != 1. The same viewCount is used for cumulative child offsets.
                if let existing = info.item(for: id), existing.viewCount != viewCount {
                    existing.invalidate()
                    retainedElements.removeValue(forKey: id)
                }

                let reusableItem = info.item(for: id).flatMap { existing in
                    existing.viewCount == viewCount ? existing : nil
                }
                let item = reusableItem ?? makeItem(
                    uniqueId: id,
                    viewCount: viewCount,
                    sublist: sublist,
                    offset: offset,
                    capturedInputs: capturedInputs,
                    graph: graph
                )
                if let item {
                    // Item depth is driven by view-level zIndex. displayMap stores
                    // UInt32 item indexes sorted by that depth.
                    item.zIndex = sublist.traits[ZIndexTraitKey.self]
                    item.needsTransitions = sublist.traits[CanTransitionTraitKey.self]
                    item.phase = 1
                    item.precedingViewCount = precedingViewCount
                    precedingViewCount += item.viewCount
                    orderedItems.append(item)
                }
            }
            return true
        }

        let removedItems = retainedRemovedItems(excluding: liveIDs)
        info.replaceItems(active: orderedItems, removed: removedItems)
        AttributeGraph.setStatefulOutput(info)
    }

    private mutating func retainedRemovedItems(
        excluding liveIDs: Set<_ViewList_ID.Canonical>
    ) -> [DynamicContainer.ItemInfo] {
        var removedItems: [DynamicContainer.ItemInfo] = []
        for item in info.items where !liveIDs.contains(item.uniqueId) {
            if item.phase == 2 {
                item.invalidate()
                retainedElements.removeValue(forKey: item.uniqueId)
                continue
            }

            guard item.needsTransitions else {
                item.invalidate()
                retainedElements.removeValue(forKey: item.uniqueId)
                continue
            }

            // FIXME: transition listener/completion is not wired yet.
            // Keep one phase-2 retained item output so DynamicContainer.Info has a
            // removed suffix, then erase it on the next update if it is still absent.
            // Replace this with listener-driven retention when
            // AnyTransition/TransitionPhase/animation completion infrastructure exists.
            item.phase = 2
            item.removalOrder = removedItems.count
            removedItems.append(item)
        }
        return removedItems
    }

    private mutating func makeItem(
        uniqueId: _ViewList_ID.Canonical,
        viewCount: Int,
        sublist: _ViewList_Sublist,
        offset: Int,
        capturedInputs: _ViewInputs,
        graph: AttributeGraph
    ) -> DynamicContainer.ItemInfo? {
        let subgraph = AGSubgraph()
        let release = (sublist.elements as? _ViewList_SubgraphElements)?.retain()
        var baseInputs = capturedInputs
        baseInputs.copyCaches()

        let item: DynamicContainer.ItemInfo? = AGSubgraph.$current.withValue(subgraph) {
            let parentTransform = capturedInputs.transform

            var firstOutputs: _ViewOutputs?
            var layoutAttributes: [LayoutProxyAttributes] = []
            var preferenceOutputs: [PreferencesOutputs] = []
            let traitsListAttr = sublist.list.map { OptionalAttribute($0) } ??
                OptionalAttribute<any ViewList>()

            // Non-unary items are a single DynamicContainer item whose viewCount
            // spans multiple child outputs, not multiple item records.
            for elementOffset in offset..<(offset + viewCount) {
                let posAttr = graph.makeInput(value: CGPoint.zero)
                let sizeAttr = graph.makeInput(value: ViewSize(.zero))
                let childTransform: Attribute<ViewTransform> = graph.makeRule {
                    var t = parentTransform.value
                    var pts = [posAttr.value]
                    t.convertGlobal(from: .local, points: &pts)
                    t.appendPosition(pts[0])
                    return t
                }

                let childOutputs = sublist.elements.makeOneElement(at: elementOffset, inputs: baseInputs) {
                    elementInputs,
                    makeView in
                    var childInputs = elementInputs
                    childInputs.transform = childTransform
                    childInputs.position = posAttr
                    childInputs.containerPosition = capturedInputs.position
                    childInputs.size = sizeAttr
                    childInputs.safeAreaInsets = capturedInputs.safeAreaInsets
                    childInputs.containerSize = OptionalAttribute(capturedInputs.size)
                    return makeView(childInputs)
                }

                guard let childOutputs else { return nil }
                if firstOutputs == nil { firstOutputs = childOutputs }
                preferenceOutputs.append(childOutputs.preferences)

                guard let lcAttr = childOutputs._layoutComputer.attribute else {
                    layoutAttributes.append(LayoutProxyAttributes())
                    continue
                }

                let wrapperLC: Attribute<LayoutComputer> = graph.makeRule {
                    let inner = lcAttr.value
                    return LayoutComputer(
                        sizeThatFits: { inner.sizeThatFits($0) },
                        spacing: inner.spacing,
                        place: { pos, anchor, proposal in
                            let sz = inner.sizeThatFits(proposal)
                            posAttr.setValue(CGPoint(x: pos.x - sz.width * anchor.x,
                                                     y: pos.y - sz.height * anchor.y))
                            sizeAttr.setValue(ViewSize(sz))
                            inner.place(at: pos, anchor: anchor, proposal: proposal)
                        },
                        explicitAlignment: { inner.explicitAlignment($0, at: $1) }
                    )
                }

                layoutAttributes.append(LayoutProxyAttributes(
                    layoutComputer: wrapperLC,
                    traitsList: traitsListAttr
                ))
            }

            guard var outputs = firstOutputs else { return nil }
            if let firstLayoutComputer = layoutAttributes.first?.layoutComputer.attribute {
                outputs._layoutComputer = OptionalAttribute(firstLayoutComputer)
            }
            return DynamicContainer.ItemInfo(
                subgraph: subgraph,
                uniqueId: uniqueId,
                viewCount: viewCount,
                outputs: outputs,
                layoutAttributes: layoutAttributes,
                preferenceOutputs: preferenceOutputs
            )
        }

        if item == nil {
            subgraph.invalidate()
            subgraph.removeFromParent()
        } else {
            retainedElements[uniqueId] = release
        }
        return item
    }
}

/// StatefulRule: consumes DynamicContainer.Info through DynamicLayoutMap and produces
/// LayoutComputer for a dynamic layout list.
private struct DynamicLayoutComputer<L: Layout>: StatefulRule {
    typealias Value = LayoutComputer
    var layoutAttr: Attribute<L>
    var containerInfoAttr: Attribute<DynamicContainer.Info>
    var layoutMap = DynamicLayoutMap()

    mutating func updateValue() {
        let layout = layoutAttr.value
        let info = containerInfoAttr.value
        layoutMap.replace(with: info)
        let children = layoutMap.attributes(info: info)
        for child in children {
            _ = child.layoutComputer.attribute?.value
        }  // register AG deps on each child LC
        let engine = ViewLayoutEngine(layout: layout, children: children, layoutDirection: .leftToRight)
        AttributeGraph.setStatefulOutput(LayoutComputer(box: LayoutEngineBox(engine: engine)))
    }
}

/// Creates a single AG reduce rule whose input list is resolved dynamically
/// from `nodeListAttr` at evaluation time.
///
/// SE-0352 allows this to be called with `any PreferenceKey.Type`; the
/// compiler opens the existential and binds `K` to the concrete key type,
/// so `Attribute<K.Value>` is correctly typed at call time.
private func _makeDynReduceAttr<K: PreferenceKey>(
    _ keyType: K.Type,
    nodeListAttr: Attribute<[AGAttribute]>,
    in graph: AttributeGraph
) -> AGAttribute {
    let attr: Attribute<K.Value> = graph.makeRule {
        let nodes = nodeListAttr.value          // registers dep on the ID list
        var combined = K.defaultValue
        for nodeID in nodes {
            let val = Attribute<K.Value>(nodeID).value  // registers dep on each child
            K.reduce(value: &combined) { val }
        }
        return combined
    }
    return attr.identifier
}

public protocol Layout: Animatable {
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
    /// Generic implementation of `_makeLayoutView` that works for any `Layout` type.
    ///
    /// Algorithm:
    /// 1. Calls `body(_Graph(), inputs)` to wire the content's AG nodes and obtain
    ///    `_ViewListOutputs` containing per-child `ViewProxy` values.
    /// 2. For each child proxy, creates a per-child position `Attribute<CGPoint>` and
    ///    calls `proxy.makeView` with child-specific inputs to get `_ViewOutputs`.
    /// 3. Creates an `Attribute<LayoutComputer>` rule that:
    ///    - reads the layout configuration from `root._attribute` (registers dependency),
    ///    - reads each child's LayoutComputer attribute (registers re-layout dependency),
    ///    - builds `LayoutSubviews` and returns a `LayoutComputer` with sizing and
    ///      placement closures that delegate to the concrete `Layout` protocol methods.
    public static func _makeLayoutView(root: _GraphValue<Self>, inputs: _ViewInputs, body: (_Graph, _ViewInputs) -> _ViewListOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeLayoutView called outside an active AttributeGraph context.")
        }

        let childListOutputs = body(_Graph(), inputs)

        // Debug overlay for the layout container itself.
        // Reads the container's pos/size from LayoutChildGeometries-driven posAttr/sizeAttr
        // via the parent. FIXME: route this through a dedicated layout-container geometry source.
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
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
            // Step 1: makeElements traversal creates per-child indirect posAttr/sizeAttr,
            //   call makeView, collect child LCs + prefs. Indirect attrs resolve the chicken-and-egg:
            //   makeView needs posAttr/sizeAttr handles, and those are wired to concrete attrs later.
            // Step 2: create StaticLayoutComputer -> LayoutChildGeometries.
            // Step 3: per-child LayoutChildGeometry + subscriptNode -> setIndirectTarget.
            //   subscriptNode projects position and size after LayoutChildGeometry is created.
            var posIndirectAttrs:  [Attribute<CGPoint>]  = []
            var sizeIndirectAttrs: [Attribute<ViewSize>] = []
            var childProxyAttrs: [LayoutProxyAttributes] = []
            var allPreferences: [PreferencesOutputs] = []
            var elementCount = 0

            var from = 0
            elements.makeElements(from: &from, inputs: inputs, indirectMap: nil) { elementInputs, makeView in
                elementCount += 1

                // Indirect placeholder attrs are wired to concrete geometry projections in Step 3.
                let posIndirect  = graph.makeIndirectAttribute(defaultValue: CGPoint.zero)
                let sizeIndirect = graph.makeIndirectAttribute(defaultValue: ViewSize.zero)
                posIndirectAttrs.append(posIndirect)
                sizeIndirectAttrs.append(sizeIndirect)

                let parentTransformAttr = inputs.transform
                let childTransformAttr: Attribute<ViewTransform> = graph.makeRule {
                    var t = parentTransformAttr.value
                    var pts = [posIndirect.value]
                    t.convertGlobal(from: .local, points: &pts)
                    t.appendPosition(pts[0])
                    return t
                }

                var childInputs = elementInputs
                childInputs.position = posIndirect
                childInputs.size = sizeIndirect
                childInputs.transform = childTransformAttr
                childInputs.containerPosition = inputs.position
                childInputs.containerSize = OptionalAttribute(inputs.size)
                childInputs.safeAreaInsets = inputs.safeAreaInsets

                let childOutputs = makeView(childInputs)
                if let lcAttr = childOutputs._layoutComputer.attribute {
                    // Trait-writing static bodies are promoted to dynamicList by
                    // _TraitWritingModifier._makeViewList, so the plain static path has no
                    // ViewList attribute for LayoutProxyAttributes.traitsList.
                    childProxyAttrs.append(LayoutProxyAttributes(layoutComputer: lcAttr))
                    allPreferences.append(childOutputs.preferences)
                }
                return (childOutputs, true)
            }

            let staticLCAttr: Attribute<LayoutComputer> = graph.makeStatefulRule(
                StaticLayoutComputer(
                    layoutAttr: root._attribute,
                    children: childProxyAttrs,
                    layoutDirection: .leftToRight
                )
            )
            let geometriesAttr: Attribute<[ViewGeometry]> = graph.makeRule(
                LayoutChildGeometries(
                    parentSize: inputs.size,
                    parentPosition: inputs.position,
                    layoutComputer: staticLCAttr
                )
            )

            // Step 3: wire per-child indirect attrs to KeyPath projections of LayoutChildGeometry[i].
            for i in 0..<elementCount {
                let childGeomAttr: Attribute<ViewGeometry> = graph.makeRule(
                    LayoutChildGeometry(geometriesAttr: geometriesAttr, index: i)
                )
                graph.setIndirectTarget(posIndirectAttrs[i],
                                        to: graph.subscriptNode(parent: childGeomAttr,
                                                                 keyPath: \ViewGeometry.origin))
                graph.setIndirectTarget(sizeIndirectAttrs[i],
                                        to: graph.subscriptNode(parent: childGeomAttr,
                                                                 keyPath: \ViewGeometry.dimensions.size))
            }

            layoutComputerAttr = staticLCAttr
            mergedPreferences = PreferencesOutputs.merge(allPreferences, in: graph)

        case .dynamicList(let viewListAttr, _):
            // DynamicContainerInfo manages item lifecycle; DynamicLayoutComputer consumes its Info.
            let containerInfoAttr: Attribute<DynamicContainer.Info> = graph.makeStatefulRule(
                DynamicContainerInfo(
                    viewListAttr: viewListAttr,
                    inputs: inputs
                )
            )

            layoutComputerAttr = graph.makeStatefulRule(
                DynamicLayoutComputer(
                    layoutAttr: root._attribute,
                    containerInfoAttr: containerInfoAttr
                )
            )

            // Two-level dynamic preference reduce.
            // nodeListAttr reads containerInfoAttr to ensure DynamicContainer.Info is current,
            // then collects the ordered per-child preference node IDs.
            var dynMergedPreferences = PreferencesOutputs()
            for keyType in inputs.preferences.keys.keys {
                let nodeListAttr: Attribute<[AGAttribute]> = graph.makeRule {
                    let info = containerInfoAttr.value
                    return info.activeItems.flatMap { item in
                        item.preferenceOutputs.flatMap { preferences in
                            preferences.values(for: keyType)
                        }
                    }
                }
                let reducedID = _makeDynReduceAttr(keyType, nodeListAttr: nodeListAttr, in: graph)
                dynMergedPreferences.append(keyType, node: reducedID)
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
        return nil
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Self.Subviews,
                                  cache: inout Self.Cache) -> CGFloat? {
        return nil
    }

    public func spacing(subviews: Self.Subviews,
                        cache: inout Self.Cache) -> ViewSpacing {
        subviews.reduce(ViewSpacing()) { spacing, subview in
            spacing.union(subview.spacing, edges: .all)
        }
    }
}

extension Layout where Self.Cache == () {
    public func makeCache(subviews: Self.Subviews) -> Self.Cache {
        ()
    }
}

extension Layout {
    public func callAsFunction<V>(@ViewBuilder _ content: () -> V) -> some View where V: View {
        _VariadicView.Tree(root: _LayoutRoot(self), content: content())
    }
}

public enum LayoutDirection: Hashable, CaseIterable {
    case leftToRight
    case rightToLeft
}

public struct LayoutProperties {
    public var stackOrientation: Axis?
    public init(stackOrientation: Axis? = nil) {
        self.stackOrientation = stackOrientation
    }
}



private extension Layout {
    @inline(__always)
    mutating func _setAnimatableData(_ data: AnyLayout.AnimatableData) {
        assert(data.value is Self.AnimatableData)
        self.animatableData = data.value as! Self.AnimatableData
    }
    @inline(__always)
    func _updateCache(_ cache: inout AnyLayout.Cache,
                      subviews: AnyLayout.Subviews) {
        var c = cache.cache as! Self.Cache
        self.updateCache(&c, subviews: subviews)
        cache.cache = c
    }
    @inline(__always)
    func _spacing(subviews: AnyLayout.Subviews,
                  cache: inout AnyLayout.Cache) -> ViewSpacing {
        var c = cache.cache as! Self.Cache
        let result = self.spacing(subviews: subviews, cache: &c)
        cache.cache = c
        return result
    }
    @inline(__always)
    func _sizeThatFits(proposal: ProposedViewSize,
                       subviews: AnyLayout.Subviews,
                       cache: inout AnyLayout.Cache) -> CGSize {
        var c = cache.cache as! Self.Cache
        let result = self.sizeThatFits(proposal: proposal,
                                       subviews: subviews,
                                       cache: &c)
        cache.cache = c
        return result
    }
    @inline(__always)
    func _placeSubviews(in bounds: CGRect,
                        proposal: ProposedViewSize,
                        subviews: AnyLayout.Subviews,
                        cache: inout AnyLayout.Cache) {
        var c = cache.cache as! Self.Cache
        self.placeSubviews(in: bounds,
                           proposal: proposal,
                           subviews: subviews,
                           cache: &c)
        cache.cache = c
    }
    @inline(__always)
    func _explicitAlignment(of guide: HorizontalAlignment,
                            in bounds: CGRect,
                            proposal: ProposedViewSize,
                            subviews: AnyLayout.Subviews,
                            cache: inout AnyLayout.Cache) -> CGFloat? {
        var c = cache.cache as! Self.Cache
        let result = self.explicitAlignment(of: guide,
                                            in: bounds,
                                            proposal: proposal,
                                            subviews: subviews,
                                            cache: &c)
        cache.cache = c
        return result
    }
    @inline(__always)
    func _explicitAlignment(of guide: VerticalAlignment,
                            in bounds: CGRect,
                            proposal: ProposedViewSize,
                            subviews: AnyLayout.Subviews,
                            cache: inout AnyLayout.Cache) -> CGFloat? {
        var c = cache.cache as! Self.Cache
        let result = self.explicitAlignment(of: guide,
                                            in: bounds,
                                            proposal: proposal,
                                            subviews: subviews,
                                            cache: &c)
        cache.cache = c
        return result
    }
}

public struct AnyLayout: Layout {
    var layout: any Layout

    public struct Cache {
        var cache: Any
    }

    public typealias AnimatableData = _AnyAnimatableData

    public init<L>(_ layout: L) where L: Layout {
        self.layout = layout
    }

    public var animatableData: AnimatableData {
        get { AnimatableData(self.layout.animatableData) }
        set { self.layout._setAnimatableData(newValue) }
    }

    public func placeSubviews(in bounds: CGRect,
                              proposal: ProposedViewSize,
                              subviews: Subviews,
                              cache: inout Cache) {
        self.layout._placeSubviews(in: bounds,
                                   proposal: proposal,
                                   subviews: subviews,
                                   cache: &cache)
    }

    public func sizeThatFits(proposal: ProposedViewSize,
                             subviews: Subviews,
                             cache: inout Cache) -> CGSize {
        self.layout._sizeThatFits(proposal: proposal,
                                  subviews: subviews,
                                  cache: &cache)
    }

    public func explicitAlignment(of guide: HorizontalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Cache) -> CGFloat? {
        self.layout._explicitAlignment(of: guide,
                                       in: bounds,
                                       proposal: proposal,
                                       subviews: subviews,
                                       cache: &cache)
    }

    public func explicitAlignment(of guide: VerticalAlignment,
                                  in bounds: CGRect,
                                  proposal: ProposedViewSize,
                                  subviews: Subviews,
                                  cache: inout Cache) -> CGFloat? {
        self.layout._explicitAlignment(of: guide,
                                       in: bounds,
                                       proposal: proposal,
                                       subviews: subviews,
                                       cache: &cache)
    }

    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        self.layout._spacing(subviews: subviews, cache: &cache)
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(cache: self.layout.makeCache(subviews: subviews))
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        self.layout._updateCache(&cache, subviews: subviews)
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

struct DefaultLayoutProperty: PropertyKey {
    static var defaultValue: any Layout { VStackLayout() }
    static func valuesEqual(_ a: any Layout, _ b: any Layout) -> Bool { false }

    var description: String {
        "DefaultLayoutProperty"
    }
}
