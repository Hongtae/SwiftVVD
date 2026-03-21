//
//  File: Layout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct WiredGenerator {
    var lc: Attribute<LayoutComputer>
    var prefs: PreferencesOutputs
    var traitsList: OptionalAttribute<ViewList>
    var posAttr: Attribute<CGPoint>
    var sizeAttr: Attribute<ViewSize>
    var transformAttr: Attribute<ViewTransform>
}

private final class _DynamicLayoutState {
    var items: [UInt32: WiredGenerator] = [:]
    var subgraphs: [UInt32: Subgraph] = [:]
    init() {}
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

        // AG input nodes that track this container's placed origin and size.
        // Written by the _place closure below; read by the debug overlay rule.
        let layoutPosAttr  = graph.makeInput(value: CGPoint.zero)
        let layoutSizeAttr = graph.makeInput(value: CGSize.zero)

        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let debugLayoutAttr: Attribute<Bool> = graph.makeRule {
            cachedEnvironmentAttr.value.environment.value._debugLayout
        }
        let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
            let debugLayout = debugLayoutAttr.value
            var dl = DisplayList()
            if debugLayout {
                let frame = CGRect(origin: layoutPosAttr.value, size: layoutSizeAttr.value)
                appendDebugOverlay(to: &dl, frame: frame, category: .layoutContainer)
            }
            return dl
        }

        // Local helper: wire one generator → WiredGenerator containing the wrapper LC,
        // preferences, traitsList, and the position/size AG input nodes used by
        // wireElements rendering modifier path.
        func wireGenerator(_ gen: TypedUnaryViewGenerator) -> WiredGenerator? {
            let posAttr = graph.makeInput(value: CGPoint.zero)
            let sizeAttr = graph.makeInput(value: ViewSize(.zero))

            // Build child transform = parent transform + appendPosition(child global pos).
            // Converting the child's parent-local position to global accounts for any
            // rotation/scale in the parent's transform chain.
            let parentTransformAttr = inputs.transform
            let childTransformAttr: Attribute<ViewTransform> = graph.makeRule {
                var t = parentTransformAttr.value
                var localPts = [posAttr.value]
                t.convertGlobal(from: .local, points: &localPts)
                t.appendPosition(localPts[0])
                return t
            }

            let childInputs = _ViewInputs(
                base: gen.baseInputs,
                preferences: inputs.preferences,
                transform: childTransformAttr,
                position: posAttr,
                containerPosition: inputs.position,
                size: sizeAttr,
                safeAreaInsets: inputs.safeAreaInsets,
                containerSize: OptionalAttribute(inputs.size)
            )
            guard let childOutputs = gen.makeView(inputs: childInputs) else { return nil }
            guard let lcAttr = childOutputs._layoutComputer.attribute else { return nil }

            // Wrap the child's LayoutComputer so that calls to `place` update its AG nodes.
            let wrapperLC: Attribute<LayoutComputer> = graph.makeRule {
                let innerLC = lcAttr.value
                return LayoutComputer(
                    sizeThatFits: innerLC._sizeThatFits,
                    spacing: innerLC._spacing,
                    dimensions: innerLC._dimensions,
                    place: { position, anchor, proposal in
                        let resolvedSize = innerLC.sizeThatFits(proposal)
                        let origin = CGPoint(x: position.x - resolvedSize.width  * anchor.x,
                                             y: position.y - resolvedSize.height * anchor.y)
                        posAttr.setValue(origin)
                        sizeAttr.setValue(ViewSize(resolvedSize))
                        innerLC.place(at: position, anchor: anchor, proposal: proposal)
                    }
                )
            }

            // Per-child ViewList AG node: wraps this single generator so the Layout
            // always has a non-null _traitsList to read traits from.
            let genCopy = gen
            let viewListAttr: Attribute<ViewList> = graph.makeRule {
                ViewList(generators: [genCopy])
            }
            return WiredGenerator(lc: wrapperLC, prefs: childOutputs.preferences,
                                  traitsList: OptionalAttribute(viewListAttr),
                                  posAttr: posAttr, sizeAttr: sizeAttr,
                                  transformAttr: childTransformAttr)
        }

        // Recursive helper: traverse ViewListElements and produce flat LCs + merged preferences +
        // traitsLists + position/size AG input nodes for each wired child.
        // posAttrs/sizeAttrs are required by the rendering modifier path to construct _ViewInputs
        // for calling PrimitiveViewModifier._makeView per child.
        // Also handles dynamicList children (produced by _TraitWritingModifier) inside a .merged context.
        func wireElements(_ elements: ViewListElements)
            -> (lcs: [Attribute<LayoutComputer>], prefs: [PreferencesOutputs],
                traitsLists: [OptionalAttribute<ViewList>],
                posAttrs: [Attribute<CGPoint>], sizeAttrs: [Attribute<ViewSize>],
                transformAttrs: [Attribute<ViewTransform>]) {
            switch elements {
            case .unary(let gen):
                guard let w = wireGenerator(gen) else { return ([], [], [], [], [], []) }
                return ([w.lc], [w.prefs], [w.traitsList], [w.posAttr], [w.sizeAttr], [w.transformAttr])

            case .merged(let childOutputsList):
                var allLCs: [Attribute<LayoutComputer>] = []
                var allPrefs: [PreferencesOutputs] = []
                var allTraitsLists: [OptionalAttribute<ViewList>] = []
                var allPosAttrs: [Attribute<CGPoint>] = []
                var allSizeAttrs: [Attribute<ViewSize>] = []
                var allTransformAttrs: [Attribute<ViewTransform>] = []
                for childOutput in childOutputsList {
                    switch childOutput.views {
                    case .staticList(let innerElements):
                        let (lcs, prefs, traitsLists, posAttrs, sizeAttrs, transformAttrs) = wireElements(innerElements)
                        allLCs.append(contentsOf: lcs)
                        allPrefs.append(contentsOf: prefs)
                        allTraitsLists.append(contentsOf: traitsLists)
                        allPosAttrs.append(contentsOf: posAttrs)
                        allSizeAttrs.append(contentsOf: sizeAttrs)
                        allTransformAttrs.append(contentsOf: transformAttrs)
                    case .dynamicList(let childViewListAttr, _):
                        // _TraitWritingModifier returns a dynamicList whose ViewList
                        // contains the child generators with trait-aware traitListAttr.
                        // Read generators at build time (they are static for _TraitWritingModifier).
                        let gens = childViewListAttr.value.generators
                        for gen in gens {
                            if let w = wireGenerator(gen) {
                                allLCs.append(w.lc)
                                allPrefs.append(w.prefs)
                                // Use the viewListAttr from _TraitWritingModifier directly
                                // so the Layout's _traitsList points to the reactive AG node.
                                allTraitsLists.append(OptionalAttribute(childViewListAttr))
                                allPosAttrs.append(w.posAttr)
                                allSizeAttrs.append(w.sizeAttr)
                                allTransformAttrs.append(w.transformAttr)
                            }
                        }
                    }
                }
                return (allLCs, allPrefs, allTraitsLists, allPosAttrs, allSizeAttrs, allTransformAttrs)

            case .modified(let base, let layoutMod):
                let (innerLCs, innerPrefs, innerTraitsLists, innerPosAttrs, innerSizeAttrs, innerTransformAttrs) = wireElements(base)
                guard layoutMod.modifier.isValid(in: graph) else {
                    return (innerLCs, innerPrefs, innerTraitsLists, innerPosAttrs, innerSizeAttrs, innerTransformAttrs)
                }
                let modAttrID = layoutMod.modifier.toStrong()

                if let unaryLayoutType = layoutMod.modifierType as? any UnaryLayout.Type {
                    // Layout modifier path: wrap each child's LayoutComputer via modifyLayoutComputer.
                    func applyUnaryLayout<M: UnaryLayout>(_ type: M.Type)
                        -> ([Attribute<LayoutComputer>], [PreferencesOutputs], [OptionalAttribute<ViewList>],
                            [Attribute<CGPoint>], [Attribute<ViewSize>], [Attribute<ViewTransform>]) {
                        let modAttr = Attribute<M>(modAttrID)
                        var outLCs: [Attribute<LayoutComputer>] = []
                        var outPrefs = innerPrefs
                        var outPosAttrs: [Attribute<CGPoint>] = []
                        var outSizeAttrs: [Attribute<ViewSize>] = []
                        for (idx, innerLcAttr) in innerLCs.enumerated() {
                            let wrappedLcAttr: Attribute<LayoutComputer> = graph.makeRule {
                                modAttr.value.modifyLayoutComputer(innerLcAttr.value)
                            }
                            let outerPosAttr  = graph.makeInput(value: CGPoint.zero)
                            let outerSizeAttr = graph.makeInput(value: ViewSize(.zero))
                            let cachedEnvAttr = layoutMod.baseInputs.cachedEnvironment
                            let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
                                let debugLayout = cachedEnvAttr.value.environment.value._debugLayout
                                var dl = DisplayList()
                                if debugLayout {
                                    appendDebugOverlay(
                                        to: &dl,
                                        frame: CGRect(origin: outerPosAttr.value,
                                                      size: outerSizeAttr.value.value),
                                        category: .layoutModifier
                                    )
                                }
                                return dl
                            }
                            if idx < outPrefs.count {
                                outPrefs[idx].append(DisplayList.Key.self, node: debugDLAttr.identifier)
                            }
                            let trackedLcAttr: Attribute<LayoutComputer> = graph.makeRule {
                                var lc = wrappedLcAttr.value
                                let origPlace = lc._place
                                let origSTF   = lc._sizeThatFits
                                lc._place = { position, anchor, proposal in
                                    let size   = origSTF(proposal)
                                    let origin = CGPoint(x: position.x - size.width  * anchor.x,
                                                         y: position.y - size.height * anchor.y)
                                    outerPosAttr.setValue(origin)
                                    outerSizeAttr.setValue(ViewSize(size))
                                    origPlace(position, anchor, proposal)
                                }
                                return lc
                            }
                            outLCs.append(trackedLcAttr)
                            outPosAttrs.append(outerPosAttr)
                            outSizeAttrs.append(outerSizeAttr)
                        }
                        return (outLCs, outPrefs, innerTraitsLists, outPosAttrs, outSizeAttrs, innerTransformAttrs)
                    }
                    return applyUnaryLayout(unaryLayoutType)
                } else {
                    // Rendering modifier path: PrimitiveViewModifier that is NOT UnaryLayout
                    // (background, overlay, blur, opacity …).
                    // Call M._makeView per child so the modifier registers its DisplayList/preference
                    // AG rules against the child's posAttr/sizeAttr.
                    func applyRenderingMod<M: PrimitiveViewModifier>(_ type: M.Type)
                        -> ([Attribute<LayoutComputer>], [PreferencesOutputs], [OptionalAttribute<ViewList>],
                            [Attribute<CGPoint>], [Attribute<ViewSize>], [Attribute<ViewTransform>]) {
                        let modAttr = Attribute<M>(modAttrID)
                        var outLCs: [Attribute<LayoutComputer>] = []
                        var outPrefs: [PreferencesOutputs] = []
                        for i in 0..<innerLCs.count {
                            let posAttr  = innerPosAttrs[i]
                            let sizeAttr = innerSizeAttrs[i]
                            let innerLC  = innerLCs[i]
                            let innerPref = i < innerPrefs.count ? innerPrefs[i] : PreferencesOutputs()
                            // Use the child's accumulated transform (includes child's global position).
                            let childTransformAttr = i < innerTransformAttrs.count
                                ? innerTransformAttrs[i]
                                : inputs.transform
                            // Reconstruct _ViewInputs for this child using its position/size/transform attrs.
                            let childInputs = _ViewInputs(
                                base: layoutMod.baseInputs,
                                preferences: inputs.preferences,
                                transform: childTransformAttr,
                                position: posAttr,
                                containerPosition: inputs.position,
                                size: sizeAttr,
                                safeAreaInsets: inputs.safeAreaInsets,
                                containerSize: OptionalAttribute(inputs.size)
                            )
                            // body closure: pass through inner preferences.
                            // _BackgroundModifier._makeView: merge([bgPrefs, mainOutputs.prefs]) places bg first.
                            // _OverlayModifier._makeView:    merge([mainOutputs.prefs, ovPrefs]) places overlay later.
                            let modOutputs = M._makeView(
                                modifier: _GraphValue(_attribute: modAttr),
                                inputs: childInputs
                            ) { _, _ in
                                _ViewOutputs(
                                    preferences: innerPref,
                                    layoutComputer: OptionalAttribute(innerLC)
                                )
                            }
                            // Use the LC returned by _makeView (may differ from innerLC for
                            // background/overlay modifiers that create their own combined LC).
                            let resultLC = modOutputs._layoutComputer.attribute ?? innerLC
                            outLCs.append(resultLC)
                            outPrefs.append(modOutputs.preferences)
                        }
                        // posAttrs/sizeAttrs/transformAttrs: the inner attrs are still updated via
                        // the place chain (resultLC.place → innerLC.place → wrapperLC.place → posAttr.setValue).
                        return (outLCs, outPrefs, innerTraitsLists, innerPosAttrs, innerSizeAttrs, innerTransformAttrs)
                    }
                    return applyRenderingMod(layoutMod.modifierType)
                }
            }
        }

        // Local helper: build a LayoutComputer from a snapshot of [Attribute<LayoutComputer>] + traitsLists.
        func buildLayoutComputer(layout: Self,
                                 childLCs: [Attribute<LayoutComputer>],
                                 childTraitsLists: [OptionalAttribute<ViewList>] = []) -> LayoutComputer {
            let subviewProxies = childLCs.enumerated().map { idx, lc in
                LayoutSubviewProxy(layoutComputerAttr: lc,
                                   traitsList: idx < childTraitsLists.count ? childTraitsLists[idx] : OptionalAttribute())
            }
            let subviews = LayoutSubviews(
                subviews: subviewProxies.map { LayoutSubview(proxy: $0) },
                layoutDirection: .leftToRight
            )
            var initCache = layout.makeCache(subviews: subviews)
            let spacingValue = layout.spacing(subviews: subviews, cache: &initCache)
            return LayoutComputer(
                sizeThatFits: { [layout, subviews] proposal in
                    var c = layout.makeCache(subviews: subviews)
                    return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &c)
                },
                spacing: spacingValue,
                dimensions: { [layout, subviews] proposal in
                    var c = layout.makeCache(subviews: subviews)
                    let size = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &c)
                    return ViewDimensions(width: size.width, height: size.height)
                },
                place: { [layout, subviews] position, anchor, proposal in
                    var sizeCache = layout.makeCache(subviews: subviews)
                    let size = layout.sizeThatFits(proposal: proposal, subviews: subviews,
                                                   cache: &sizeCache)
                    let origin = CGPoint(
                        x: position.x - size.width * anchor.x,
                        y: position.y - size.height * anchor.y
                    )
                    let bounds = CGRect(origin: origin, size: size)
                    layoutPosAttr.setValue(origin)
                    layoutSizeAttr.setValue(size)
                    var placeCache = layout.makeCache(subviews: subviews)
                    layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews,
                                         cache: &placeCache)
                }
            )
        }

        let layoutComputerAttr: Attribute<LayoutComputer>
        var mergedPreferences: PreferencesOutputs

        switch childListOutputs.views {
        case .staticList(let elements):
            // Wire all generators once at graph-construction time.
            let (layoutPairs, childPrefsList, childTraitsLists, _, _, _) = wireElements(elements)

            layoutComputerAttr = graph.makeRule {
                let layout = root._attribute.value
                let _ = layoutPairs.map { $0.value }
                return buildLayoutComputer(layout: layout, childLCs: layoutPairs, childTraitsLists: childTraitsLists)
            }

            mergedPreferences = PreferencesOutputs.merge(childPrefsList, in: graph)

        case .dynamicList(let viewListAttr, _):
            // Per-generator wiring state: keyed by AGAttribute rawValue.
            // New generators are wired on first appearance; stale ones are dropped.
            let dynState = _DynamicLayoutState()

            // Eagerly wire the initial generators so that dynState is populated
            // before any AG rules fire. Each generator's nodes are owned by a
            // dedicated Subgraph so they can be removed cleanly when the item leaves.
            for gen in viewListAttr.value.generators {
                let subgraph = Subgraph()
                if let wired = Subgraph.$current.withValue(subgraph, operation: { wireGenerator(gen) }) {
                    dynState.items[gen.view.identifier] = wired
                    dynState.subgraphs[gen.view.identifier] = subgraph
                } else {
                    subgraph.invalidate()
                    subgraph.removeFromParent()
                }
            }

            layoutComputerAttr = graph.makeRule {
                let layout = root._attribute.value
                let currentGens = viewListAttr.value.generators  // registers AG dependency

                // Drop entries for generators no longer in the list.
                // Invalidate each item's Subgraph to batch-remove its AG nodes.
                let currentIDs = Set(currentGens.map { $0.view.identifier })
                for id in dynState.items.keys where !currentIDs.contains(id) {
                    dynState.subgraphs[id]?.invalidate()
                    dynState.subgraphs[id]?.removeFromParent()
                    dynState.subgraphs.removeValue(forKey: id)
                }
                dynState.items = dynState.items.filter { currentIDs.contains($0.key) }

                // Wire newly appeared generators, each into its own Subgraph.
                for gen in currentGens where dynState.items[gen.view.identifier] == nil {
                    let subgraph = Subgraph()
                    if let wired = Subgraph.$current.withValue(subgraph, operation: { wireGenerator(gen) }) {
                        dynState.items[gen.view.identifier] = wired
                        dynState.subgraphs[gen.view.identifier] = subgraph
                    } else {
                        subgraph.invalidate()
                        subgraph.removeFromParent()
                    }
                }

                // Build LayoutComputer from current generators in order.
                let ordered = currentGens.compactMap { dynState.items[$0.view.identifier] }
                let childLCs = ordered.map { $0.lc }
                let childTraitsLists = ordered.map { $0.traitsList }
                let _ = childLCs.map { $0.value }
                return buildLayoutComputer(layout: layout, childLCs: childLCs, childTraitsLists: childTraitsLists)
            }

            // For each preference key registered by the host, create a two-level
            // dynamic reduce:
            //
            //   nodeListAttr: Attribute<[AGAttribute]>
            //     — reads layoutComputerAttr (ensures dynState is current)
            //       and viewListAttr (registers dep on list changes);
            //       returns the ordered list of child preference node IDs for this key.
            //
            //   reduceAttr: Attribute<K.Value>  (via _makeDynReduceAttr, SE-0352)
            //     — reads nodeListAttr (dep on ID list changes) and each child node
            //       (dep on individual value changes); reduces with K.reduce.
            //
            // Iterate registered preference keys and create one AG reduce node
            // per key.
            var dynMergedPreferences = PreferencesOutputs()
            for keyType in inputs.preferences.keys.keys {
                let nodeListAttr: Attribute<[AGAttribute]> = graph.makeRule {
                    _ = layoutComputerAttr.value        // ensure dynState is current
                    let currentGens = viewListAttr.value.generators  // register dep
                    return currentGens.compactMap { gen in
                        dynState.items[gen.view.identifier]?.prefs.values(for: keyType).first
                    }
                }
                // SE-0352 opens `keyType: any PreferenceKey.Type` → concrete K,
                // allowing _makeDynReduceAttr to create a typed Attribute<K.Value>.
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

struct DefaultLayoutProperty: PropertyItem {
    static var defaultValue: any Layout { VStackLayout() }

    var description: String {
        "DefaultLayoutProperty"
    }
}
