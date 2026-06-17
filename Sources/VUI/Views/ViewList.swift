//
//  File: ViewList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - ViewList protocol

/// Internal protocol for dynamic view lists.
protocol ViewList: CustomDebugStringConvertible {
    func count(style: _ViewList_IteratorStyle) -> Int
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int
    var traitKeys: ViewTraitKeys? { get }
    var traits: ViewTraitCollection { get }
    var viewIDs: _ViewList_ID_Views? { get }
    func appendViewIDs(into: inout HeterogeneousViewIDsAccumulator)
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool
    func firstOffset<A: Hashable>(forID: A, style: _ViewList_IteratorStyle) -> Int?
    func edit(forID: _ViewList_ID, since: TransactionID) -> _ViewList_Edit?
    func print(into: inout SExpPrinter)
}

extension ViewList {
    func count(style: _ViewList_IteratorStyle) -> Int { 0 }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { count(style: style) }
    var traitKeys: ViewTraitKeys? { nil }
    var traits: ViewTraitCollection { ViewTraitCollection() }
    var viewIDs: _ViewList_ID_Views? { nil }
    func appendViewIDs(into: inout HeterogeneousViewIDsAccumulator) {}
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool { false }
    func firstOffset<A: Hashable>(forID: A, style: _ViewList_IteratorStyle) -> Int? { nil }
    func edit(forID: _ViewList_ID, since: TransactionID) -> _ViewList_Edit? { nil }
    func print(into: inout SExpPrinter) {}
    var debugDescription: String { "ViewList(\(count(style: _ViewList_IteratorStyle())))" }
}

// MARK: - _ViewList_Backing

/// Concrete backing adapter returned by variadic children.
struct _ViewList_Backing {
    var list: any ViewList
}

// MARK: - BaseViewList

/// ViewList backed by a _ViewList_Elements tree.
struct BaseViewList: ViewList {
    var elements: any _ViewList_Elements
    var implicitID: Int
    var traitKeys: ViewTraitKeys?
    var traits: ViewTraitCollection

    init(elements: any _ViewList_Elements, implicitID: Int = 0) {
        self.elements = elements
        self.implicitID = implicitID
        self.traitKeys = nil
        self.traits = ViewTraitCollection()
    }

    init(elements: any _ViewList_Elements, implicitID: Int = 0, traits: ViewTraitCollection) {
        self.elements = elements
        self.implicitID = implicitID
        self.traitKeys = nil
        self.traits = traits
    }

    func count(style: _ViewList_IteratorStyle) -> Int { elements.count }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { elements.count }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        // Builds a _ViewList_Sublist from self.elements and calls the callback once.
        let sublist = _ViewList_Sublist(
            start: from,
            count: elements.count,
            id: _ViewList_ID(implicitID: 0),
            elements: elements,
            traits: traits,
            list: list
        )
        let result = to(&from, style, .sublist(sublist), transform)
        from = 0
        return result
    }
}

// MARK: - EmptyViewList

/// An empty ViewList with no elements.
struct EmptyViewList: ViewList {
    init() {}
    func count(style: _ViewList_IteratorStyle) -> Int { 0 }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { 0 }
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        true  // No elements. Traversal completes immediately.
    }
}

// MARK: - _ViewList_IteratorStyle

/// Controls granularity when traversing a ViewList.
/// The current modeled storage is a single UInt value.
struct _ViewList_IteratorStyle: Equatable {
    var value: UInt
    init() { value = 0 }
    init(value: UInt) { self.value = value }
}

// MARK: - _ViewList_ID / _ViewList_Edit

/// A stable identity for a specific view in a ViewList.
/// Current storage keeps the known index, implicit ID, and explicit ID list.
/// Canonical, reuse identifier, and explicit binding behavior remain partial.
struct _ViewList_ID {
    struct Canonical: Hashable {
        // Canonical form does not yet track requiresImplicitID.
        var value: Int32
        var explicitID: AnyHashable?
    }

    struct Explicit: Hashable {
        // Explicit ID storage is simplified.
        var id: AnyHashable
    }

    var _index: Int32
    var implicitID: Int32
    var explicitIDs: [Explicit] = []

    var index: Int { Int(_index) }

    init(implicitID: Int = 0) {
        self._index = Int32(implicitID)
        self.implicitID = Int32(implicitID)
    }

    init(explicitID: AnyHashable, implicitID: Int = 0) {
        self._index = Int32(implicitID)
        self.implicitID = Int32(implicitID)
        self.explicitIDs = [Explicit(id: explicitID)]
    }

    func elementID(at index: Int) -> _ViewList_ID {
        // This hash formula is provisional.
        var id = self
        id._index = Int32(Int(self._index) &* 31 &+ index)
        return id
    }

    var canonicalID: Canonical {
        if let explicitID = explicitIDs.last?.id {
            return Canonical(value: _index, explicitID: explicitID)
        }
        return Canonical(value: _index, explicitID: nil)
    }
}

extension _ViewList_ID: Equatable {
    static func == (lhs: _ViewList_ID, rhs: _ViewList_ID) -> Bool {
        lhs._index == rhs._index &&
        lhs.implicitID == rhs.implicitID &&
        lhs.explicitIDs == rhs.explicitIDs
    }
}

/// Describes a change that occurred to a specific ViewList item.
enum _ViewList_Edit: Hashable { case inserted, removed }

// MARK: - ID / accumulator stubs

struct _ViewList_ID_Views {}
struct HeterogeneousViewIDsAccumulator {}

// MARK: - _ViewList_SublistTransform

protocol _ViewList_SublistTransform_Item {
    func apply(to sublist: inout _ViewList_Sublist)
}

struct _ViewList_SublistTransform {
    var items: [any _ViewList_SublistTransform_Item]
    var subgraphCount: Int

    init() {
        self.items = []
        self.subgraphCount = 0
    }

    mutating func push(_ item: any _ViewList_SublistTransform_Item) {
        items.append(item)
    }

    @discardableResult
    mutating func pop() -> (any _ViewList_SublistTransform_Item)? {
        items.popLast()
    }

    func apply(to sublist: inout _ViewList_Sublist) {
        for item in items {
            item.apply(to: &sublist)
        }
    }
}

// MARK: - _ViewList_TemporarySublistTransform

/// Context passed during ViewList sublist traversal.
/// Carries list modifiers that are pushed while dynamic lists are traversed.
struct _ViewList_TemporarySublistTransform {
    fileprivate var storage: _TemporarySublistTransformStorage?
    fileprivate var flag: Bool

    init() {
        self.storage = nil
        self.flag = false
    }

    fileprivate init(storage: _TemporarySublistTransformStorage?, flag: Bool) {
        self.storage = storage
        self.flag = flag
    }
}

private final class _TemporarySublistTransformStorage {
    var items: [any _ViewList_SublistTransform_Item]

    init(items: [any _ViewList_SublistTransform_Item] = []) {
        self.items = items
    }
}

// MARK: - _ViewList_Elements protocol

/// Abstraction for the view-creation mechanism within a ViewList sublist.
protocol _ViewList_Elements {
    var count: Int { get }

    /// Creates view outputs for elements starting at the given offset.
    /// - from: elements to skip before processing (0 = process, >0 = skip and decrement)
    /// - returns: (lastOutputs, shouldContinue)
    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool)

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool
}

extension _ViewList_Elements {
    /// Creates a single element at `index`.
    /// The exact helper body and conformer override behavior are still partial.
    func makeOneElement(
        at index: Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap? = nil,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> _ViewOutputs?
    ) -> _ViewOutputs? {
        var from = index
        var resolved: _ViewOutputs?
        _ = makeElements(from: &from, inputs: inputs, indirectMap: indirectMap) { elementInputs, makeView in
            withoutActuallyEscaping(makeView) { escapableMakeView in
                resolved = body(elementInputs, escapableMakeView)
            }
            return (resolved, false)
        }
        return resolved
    }

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool { false }
}

struct EmptyViewListElements: _ViewList_Elements {
    var count: Int { 0 }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        (nil, true)
    }
}

// MARK: - UnaryElements

/// Single-view _ViewList_Elements.
/// makeElements skips one element when from != 0.
/// When from == 0, it calls body(inputs, makeViewClosure).
///
/// This collapses separate generator specializations into one closure path.
struct UnaryElements: _ViewList_Elements {
    /// Retained for typed generator construction.
    /// nil for body-generator construction.
    var typedGenerator: TypedUnaryViewGenerator?
    var makeViewClosure: (_ViewInputs) -> _ViewOutputs
    var baseInputs: _GraphInputs

    init(generator: TypedUnaryViewGenerator) {
        self.typedGenerator = generator
        self.makeViewClosure = { inputs in generator.makeView(inputs: inputs) ?? _ViewOutputs() }
        self.baseInputs = generator.baseInputs
    }

    /// BodyUnaryViewGenerator path.
    /// Exact layout wiring remains simplified.
    init(body: @escaping (_ViewInputs) -> _ViewOutputs, baseInputs: _GraphInputs) {
        self.typedGenerator = nil
        self.makeViewClosure = body
        self.baseInputs = baseInputs
    }

    var count: Int { 1 }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        if from != 0 {
            from -= 1
            return (nil, true)
        }
        let closure = makeViewClosure
        return body(inputs, { i in closure(i) })
    }
}

// MARK: - MergedElements

/// Aggregates multiple _ViewListOutputs into a single _ViewList_Elements.
struct MergedElements: _ViewList_Elements {
    var outputs: [_ViewListOutputs]

    var count: Int {
        outputs.reduce(0) { acc, output in
            switch output.views {
            case .staticList(let elems): return acc + elems.count
            case .dynamicList(let attr, _): return acc + attr.value.count(style: _ViewList_IteratorStyle())
            }
        }
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        for output in outputs {
            switch output.views {
            case .staticList(let elems):
                let (result, cont) = elems.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
                if !cont { return (result, false) }
            case .dynamicList(let attr, _):
                var traversalFrom = from
                var remaining = from
                let list = attr.value
                var dynamicResult: _ViewOutputs?
                let cont = _applySublists(in: list, from: &traversalFrom, listAttribute: attr) { sublist in
                    var elementFrom = remaining
                    let (result, shouldContinue) = sublist.elements.makeElements(
                        from: &elementFrom,
                        inputs: inputs,
                        indirectMap: indirectMap,
                        body: body
                    )
                    dynamicResult = result
                    remaining = elementFrom
                    return shouldContinue
                }
                from = remaining
                if !cont { return (dynamicResult, false) }
            }
        }
        return (nil, true)
    }
}

// MARK: - ModifiedElements

/// Wraps a base _ViewList_Elements with a ViewModifier applied per-element.
/// Stores a type-erased projection closure for concrete modifier dispatch.
struct ModifiedElements: _ViewList_Elements {
    var base: any _ViewList_Elements
    var modifier: AGWeakAttribute
    var baseInputs: _GraphInputs
    // Type-erased closure for concrete M._makeView dispatch.
    // Calls M._makeView(modifier:inputs:body:) with the captured concrete M.
    var project: (AGAttribute, _ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> _ViewOutputs

    var count: Int { base.count }

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        false
    }

    /// Creates a ModifiedElements wrapping `base` with modifier `M`.
    /// This is the primary factory used by multiModifier and PreferenceModifiers.
    static func make<M: ViewModifier>(
        base: any _ViewList_Elements,
        modifier: _GraphValue<M>,
        inputs: _GraphInputs
    ) -> ModifiedElements {
        let weakMod = modifier._attribute.asWeak().raw
        return ModifiedElements(
            base: base,
            modifier: weakMod,
            baseInputs: inputs,
            project: { rawAttr, mergedInputs, outerBody in
                let modAttr = Attribute<M>(rawAttr)
                let gv = _GraphValue(_attribute: modAttr)
                return M._makeView(modifier: gv, inputs: mergedInputs,
                                   body: { _, bodyInputs in outerBody(bodyInputs) })
            }
        )
    }

    /// Per-element modifier application.
    ///
    /// Flow:
    ///   1. Delegate to base.makeElements with a wrappedBody.
    ///   2. wrappedBody (called per-element by base):
    ///      a. Merge baseInputs (modifier's, higher priority) + elementInputs.base (element's)
    ///      b. Resolve modifier weak attr and return nil if expired.
    ///      c. Call project(modAttr, mergedInputs, makeView).
    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        let capturedModifier  = modifier
        let capturedBaseInputs = baseInputs
        let capturedProject   = project

        let wrappedBody: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool) = {
            elementInputs, makeView in
            guard let graph = AttributeGraph.current else {
                fatalError("ModifiedElements.makeElements wrappedBody called outside AG context.")
            }

            // Merge modifier baseInputs at higher priority than elementInputs.base.
            var mergedBase = capturedBaseInputs
            mergedBase.merge(elementInputs.base, ignoringPhase: false)
            var mergedInputs = elementInputs
            mergedInputs.base = mergedBase

            // Resolve modifier weak attr.
            guard capturedModifier.isValid(in: graph) else { return (nil, false) }

            // Pass a modifier-aware makeView closure to the outer materializer.
            // The materializer (Layout/ViewThatFits/etc.) must first install its
            // geometry/indirect attrs, then invoke this closure with the final
            // child inputs. Applying the modifier here directly would bypass that
            // wiring and drop child preferences.
            var result: (_ViewOutputs?, Bool) = (nil, true)
            withoutActuallyEscaping(makeView) { escapableMakeView in
                let strongModifier = capturedModifier.toStrong()
                result = body(mergedInputs) { childInputs in
                    capturedProject(strongModifier, childInputs) { innerInputs in
                        escapableMakeView(innerInputs)
                    }
                }
            }
            return result
        }

        return base.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: wrappedBody)
    }
}

// MARK: - _ViewList_SubgraphElements

/// Refcounted subgraph holder used by retained ViewList slices.
/// Stores an AGSubgraph object plus a manual retain count for list slices.
final class _ViewList_Subgraph {
    var subgraph: AGSubgraph
    var refcount: UInt32 = 1

    init(subgraph: AGSubgraph) {
        self.subgraph = subgraph
    }

    func invalidate() {
        // Pre-invalidation observer hooks are not wired.
        subgraph.invalidate()
        subgraph.removeFromParent()
    }
}

/// Storage for sublist subgraphs. `retain()` returns a release token.
/// retain() walks backwards, skips dead entries (refcount==0), retains live ones,
/// then creates a _ViewList_SubgraphRelease covering the live slice.
final class _ViewList_SublistSubgraphStorage {
    var subgraphs: [_ViewList_Subgraph] = []
    var isValid: Bool { !subgraphs.isEmpty }

    func retain() -> _ViewList_SubgraphRelease? {
        // Walk backwards: skip dead (refcount==0) and invalid subgraphs, retain live ones.
        // AGSubgraph validity filtering is not modeled.
        var liveItems: [_ViewList_Subgraph] = []
        var i = subgraphs.count - 1
        while i >= 0 {
            let item = subgraphs[i]
            if item.refcount > 0 {
                item.refcount += 1
                liveItems.append(item)
            }
            i -= 1
        }
        guard !liveItems.isEmpty else { return nil }
        return _ViewList_SubgraphRelease(owner: self, subgraphs: liveItems.reversed())
    }
}

/// Release token for a retained subgraph slice. Decrements refcounts on dealloc.
/// deinit walks the slice and decrements refcount per item.
/// It invalidates when refcount reaches 0. The retained slice is stored as an Array copy.
final class _ViewList_SubgraphRelease {
    private let owner: _ViewList_SublistSubgraphStorage
    private let subgraphs: [_ViewList_Subgraph]

    init(owner: _ViewList_SublistSubgraphStorage, subgraphs: [_ViewList_Subgraph]) {
        self.owner = owner
        self.subgraphs = subgraphs
    }

    deinit {
        for item in subgraphs {
            item.refcount -= 1
            if item.refcount == 0 {
                item.invalidate()
            }
        }
    }
}

/// Wraps a base _ViewList_Elements with per-item subgraph lifecycle management.
/// Used by per-item sublists so each item can retain its own element lifetime.
struct _ViewList_SubgraphElements: _ViewList_Elements {
    var base: any _ViewList_Elements
    var subgraphs: _ViewList_SublistSubgraphStorage? = nil
    var releaseElements: _ViewList_SubgraphRelease? = nil

    var count: Int { base.count }

    func retain() -> _ViewList_SubgraphRelease? {
        subgraphs?.retain() ?? releaseElements
    }

    /// Attaches a subgraph to this elements wrapper for lifecycle tracking.
    /// Item-subgraph link behavior is not fully wired.
    mutating func wrap(subgraph: _ViewList_Subgraph) {
        if subgraphs == nil { subgraphs = _ViewList_SublistSubgraphStorage() }
        subgraphs?.subgraphs.append(subgraph)
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        base.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
    }
}

// MARK: - _ViewList_Node

/// A single node yielded by `ViewList.applyNodes`.
enum _ViewList_Node {
    case list(any ViewList, Attribute<any ViewList>?)
    case group(_ViewList_Group)
    case section(_ViewList_Section)
    case sublist(_ViewList_Sublist)
}
struct _ViewList_Section {}

// MARK: - _ViewList_Group

/// Wraps multiple ViewList entries for mixed static+dynamic content.
/// Created when TupleView/ViewBuilder mixes static and dynamic content (Text + ForEach, etc.).
/// applyNodes iterates each entry and delegates to its list.applyNodes, passing entry.attribute
/// as the list: parameter so each sublist has its own AG reactivity anchor.
struct _ViewList_Group: ViewList {
    /// Each entry is (current ViewList value, its AG node for dependency tracking).
    var lists: [(list: any ViewList, attribute: Attribute<any ViewList>)]

    func count(style: _ViewList_IteratorStyle) -> Int {
        lists.reduce(0) { $0 + $1.list.count(style: style) }
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        for entry in lists {
            let cont = entry.list.applyNodes(
                from: &from,
                style: style,
                list: entry.attribute,
                transform: transform,
                to: to
            )
            if !cont { return false }
        }
        return true
    }
}

/// A contiguous slice of a ViewList passed to the `applyNodes` callback.
struct _ViewList_Sublist {
    var start: Int
    var count: Int
    var id: _ViewList_ID
    var elements: any _ViewList_Elements
    var traits: ViewTraitCollection
    var list: Attribute<any ViewList>?
}

/// View wrapper used by `_VariadicView_Children.Element`.
struct _ViewList_View {
    var elements: _ViewList_SubgraphElements
    var id: _ViewList_ID
    var index: Int
    var count: Int
    var contentSubgraph: AGSubgraph?

    /// _VariadicView_Children.Element._makeView delegates here.
    /// This creates placeholder outputs, then uses `PlaceholderInfo` to attach
    /// concrete child outputs through indirect output attributes.
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ViewList_View._makeView called outside an active AttributeGraph context.")
        }
        let placeholders = inputs.makeIndirectOutputs()
        let infoAttr: Attribute<_ViewOutputs> = graph.makeStatefulRule(
            PlaceholderInfo(view: view._attribute, inputs: inputs, placeholders: placeholders)
        )
        _ = graph.makeSideEffectRule {
            _ = infoAttr.value
            return ()
        }
        return placeholders
    }
}

/// Stateful placeholder rule for `_ViewList_View._makeView`.
private struct PlaceholderInfo: StatefulRule {
    typealias Value = _ViewOutputs

    var view: Attribute<_ViewList_View>
    var inputs: _ViewInputs
    var placeholders: _ViewOutputs
    var childSubgraph: AGSubgraph?
    var releaseElements: _ViewList_SubgraphRelease?
    var lastID: _ViewList_ID?
    var lastIndex: Int?
    var lastContentSubgraph: AGSubgraph?

    mutating func updateValue() {
        let item = view.value

        // Reuse the item when contentSubgraph and _ViewList_ID identity match.
        if canReuse(item) {
            releaseElements = item.elements.retain()
            AttributeGraph.setStatefulOutput(placeholders)
            return
        }

        eraseItem()

        let subgraph = AGSubgraph()
        childSubgraph = subgraph
        lastID = item.id
        lastIndex = item.index
        lastContentSubgraph = item.contentSubgraph

        releaseElements = item.elements.retain()
        var childInputs = inputs
        childInputs.copyCaches()
        let concrete = AGSubgraph.$current.withValue(subgraph) {
            item.elements.makeOneElement(at: item.index, inputs: childInputs) { elementInputs, makeView in
                makeView(elementInputs)
            }
        } ?? _ViewOutputs()

        concrete.attachIndirectOutputs(to: placeholders)
        AttributeGraph.setStatefulOutput(placeholders)
    }

    private func canReuse(_ item: _ViewList_View) -> Bool {
        guard childSubgraph != nil,
              let lastID,
              let lastIndex else { return false }
        return lastID == item.id &&
            lastIndex == item.index &&
            lastContentSubgraph === item.contentSubgraph
    }

    private mutating func eraseItem() {
        guard let subgraph = childSubgraph else { return }
        placeholders.detachIndirectOutputs()
        subgraph.invalidate()
        subgraph.removeFromParent()
        childSubgraph = nil
        releaseElements = nil
        lastID = nil
        lastIndex = nil
        lastContentSubgraph = nil
    }
}

// MARK: - TransactionID

/// A monotonically increasing ID representing an AttributeGraph transaction.
/// Graph/context initializer value semantics are not modeled.
struct TransactionID: Comparable, Hashable {
    var value: UInt = 0
    init() {}
    static func < (a: TransactionID, b: TransactionID) -> Bool { a.value < b.value }
}

// MARK: - SExpPrinter

/// Debug pretty-printer for ViewList trees. Stub.
struct SExpPrinter {}

// MARK: - ViewListElements

/// Discriminated union for a fully-static view list structure.
indirect enum ViewListElements {
    case unaryElements(UnaryElements)
    case merged([_ViewListOutputs])
    // staticList modifier path.
    case modified(ModifiedElements)
}

extension ViewListElements: _ViewList_Elements {
    var count: Int {
        switch self {
        case .unaryElements(let unary): return unary.count
        case .merged(let outputs): return MergedElements(outputs: outputs).count
        case .modified(let mod): return mod.count
        }
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        switch self {
        case .unaryElements(let unary):
            return unary.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
        case .merged(let outputs):
            return MergedElements(outputs: outputs).makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
        case .modified(let mod):
            return mod.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
        }
    }
}

// MARK: - Trait types

/// Type-erased storage for a single trait entry in a `ViewTraitCollection`.
protocol AnyViewTrait {}

/// Typed wrapper for one `_ViewTraitKey` value.
struct AnyTrait<Key: _ViewTraitKey>: AnyViewTrait {
    var value: Key.Value
}

/// Per-view trait values propagated from child to container.
struct ViewTraitCollection {
    var storage: [AnyViewTrait] = []
    init() {}

    subscript<K: _ViewTraitKey>(key: K.Type) -> K.Value {
        get {
            for item in storage { if let t = item as? AnyTrait<K> { return t.value } }
            return K.defaultValue
        }
        set {
            for i in 0..<storage.count {
                if storage[i] is AnyTrait<K> {
                    storage[i] = AnyTrait<K>(value: newValue)
                    return
                }
            }
            storage.append(AnyTrait<K>(value: newValue))
        }
    }
}

/// The set of trait keys a view list is tracking.
/// Data-dependency propagation is surface-modeled only.
struct ViewTraitKeys {
    var types: Set<ObjectIdentifier> = []
    var isDataDependent: Bool = false

    mutating func insert<T: _ViewTraitKey>(_ key: T.Type) {
        types.insert(ObjectIdentifier(key))
    }
    func contains<T: _ViewTraitKey>(_ key: T.Type) -> Bool {
        types.contains(ObjectIdentifier(key))
    }
    mutating func formUnion(_ other: ViewTraitKeys) {
        types.formUnion(other.types)
        isDataDependent = isDataDependent || other.isDataDependent
    }
    func withDataDependency() -> ViewTraitKeys {
        var copy = self
        copy.isDataDependent = true
        return copy
    }
}

/// Scroll content offset. Stub.
struct ViewContentOffset {}

// MARK: - ListModifier

/// Abstract base for `_ViewListOutputs.Views.dynamicList` modifier chain.
/// Stores a type-erased projection closure for concrete modifier dispatch.
class ListModifier: _ViewList_SublistTransform_Item {
    var pred: ListModifier?
    let modifierType: any ViewModifier.Type
    let modifier: AGWeakAttribute
    let baseInputs: _GraphInputs
    // Type-erased closure for concrete M._makeView dispatch.
    let project: (AGAttribute, _ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> _ViewOutputs

    init<M: ViewModifier>(pred: ListModifier?,
                          modifier: Attribute<M>,
                          inputs: _GraphInputs) {
        self.pred = pred
        self.modifierType = M.self
        self.modifier = modifier.asWeak().raw
        self.baseInputs = inputs
        self.project = { rawAttr, mergedInputs, outerBody in
            let modAttr = Attribute<M>(rawAttr)
            let gv = _GraphValue(_attribute: modAttr)
            return M._makeView(modifier: gv, inputs: mergedInputs,
                               body: { _, bodyInputs in outerBody(bodyInputs) })
        }
    }

    /// Applies this modifier chain to `list`.
    func apply(to list: inout any ViewList) {
        pred?.apply(to: &list)
        let modified = ModifiedViewList(list: list, listModifier: self)
        list = modified
    }

    func apply(to sublist: inout _ViewList_Sublist) {
        sublist.elements = ModifiedElements(
            base: sublist.elements,
            modifier: modifier,
            baseInputs: baseInputs,
            project: project
        )
    }
}

extension _ViewList_TemporarySublistTransform {
    /// Pushes a ListModifier during ModifiedViewList.applyNodes, then applies
    /// the stack when sublists are materialized.
    fileprivate func withPushedItem(_ item: any _ViewList_SublistTransform_Item) -> Self {
        let storage = self.storage ?? _TemporarySublistTransformStorage()
        storage.items.append(item)
        return Self(storage: storage, flag: true)
    }

    fileprivate func apply(to sublist: inout _ViewList_Sublist) {
        guard let storage, flag else { return }
        for item in storage.items {
            item.apply(to: &sublist)
        }
    }
}

// MARK: - ModifiedViewList

/// Wraps a ViewList with a ListModifier chain for the dynamicList modifier path.
/// applyNodes: pushes modifier info into transform, then delegates to original list.applyNodes.
struct ModifiedViewList: ViewList {
    var list: any ViewList
    var listModifier: ListModifier

    func count(style: _ViewList_IteratorStyle) -> Int { list.count(style: style) }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { list.estimatedCount(style: style) }
    var traitKeys: ViewTraitKeys? { list.traitKeys }
    var traits: ViewTraitCollection { list.traits }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list listAttr: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        let newTransform = transform.withPushedItem(listModifier)
        return list.applyNodes(
            from: &from,
            style: style,
            list: listAttr,
            transform: newTransform,
            to: to
        )
    }

    var debugDescription: String { "ModifiedViewList(\(list))" }
}

// MARK: - ViewListContent

enum ViewListContent {
    case staticList(ViewListElements)
    case dynamicList(Attribute<any ViewList>, ListModifier?)
}

// MARK: - Generator extraction helper

/// Traverses a ViewList via applyNodes and visits each sublist in order.
@discardableResult
func _forEachSublist(
    in list: any ViewList,
    listAttribute: Attribute<any ViewList>? = nil,
    style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
    sublistTransform: _ViewList_SublistTransform = _ViewList_SublistTransform(),
    body: (_ViewList_Sublist) -> Bool
) -> Bool {
    var from = 0
    return list.applyNodes(
        from: &from,
        style: style,
        list: listAttribute,
        transform: _ViewList_TemporarySublistTransform()
    ) { _, _, node, transform in
        guard case .sublist(var sublist) = node else { return true }
        transform.apply(to: &sublist)
        sublistTransform.apply(to: &sublist)
        return body(sublist)
    }
}

/// Applies a callback to sublists before materializing children.
@discardableResult
func _applySublists(
    in list: any ViewList,
    from: inout Int,
    listAttribute: Attribute<any ViewList>? = nil,
    style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
    sublistTransform: _ViewList_SublistTransform = _ViewList_SublistTransform(),
    body: (_ViewList_Sublist) -> Bool
) -> Bool {
    list.applyNodes(
        from: &from,
        style: style,
        list: listAttribute,
        transform: _ViewList_TemporarySublistTransform()
    ) { _, _, node, transform in
        guard case .sublist(var sublist) = node else { return true }
        transform.apply(to: &sublist)
        sublistTransform.apply(to: &sublist)
        return body(sublist)
    }
}

// MARK: - ApplyModifiers

/// AG Rule that wraps a source ViewList with a ListModifier chain.
/// Reads the source list, applies the modifier chain, and returns the wrapped list.
struct ApplyModifiers: Rule {
    typealias Value = any ViewList
    var source: Attribute<any ViewList>
    var listModifier: ListModifier

    func updateValue() -> any ViewList {
        var list: any ViewList = source.value   // registers AG dependency on source ViewList
        listModifier.apply(to: &list)
        return list
    }
}

// MARK: - _ViewListOutputs.multiModifier

extension _ViewListOutputs {
    /// Wraps the current view list content with a ViewModifier applied to each element.
    ///
    /// staticList branch (tag != 1): creates ModifiedElements, stores as .staticList(.modified(...))
    /// dynamicList branch (tag == 1): creates ListModifier + ApplyModifiers AG rule
    mutating func multiModifier<M: ViewModifier>(
        _ modifier: _GraphValue<M>,
        inputs: _ViewListInputs
    ) {
        switch views {
        case .staticList(let innerElements):
            let modElements = ModifiedElements.make(base: innerElements, modifier: modifier,
                                                    inputs: inputs.base)
            views = .staticList(.modified(modElements))

        case .dynamicList(let listAttr, let pred):
            guard let graph = AttributeGraph.current else {
                fatalError("_ViewListOutputs.multiModifier called outside AG context.")
            }
            let lm = ListModifier(pred: pred, modifier: modifier._attribute, inputs: inputs.base)
            let newAttr: Attribute<any ViewList> = graph.makeRule(
                ApplyModifiers(source: listAttr, listModifier: lm)
            )
            views = .dynamicList(newAttr, lm)
        }
    }
}
