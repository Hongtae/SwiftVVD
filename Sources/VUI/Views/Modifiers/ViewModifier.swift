//
//  File: ViewModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// MARK: - BodyInputElement
// One entry on the BodyInput<Content> stack.
// Stores Swift closures for make-view and make-view-list body paths.
struct BodyInputElement {
    let isViewList: Bool
    // Valid when isViewList == false:
    let makeViewFn: ((_Graph, _ViewInputs) -> _ViewOutputs)?
    // Valid when isViewList == true:
    let makeViewListFn: ((_Graph, _ViewListInputs) -> _ViewListOutputs)?

    init(makeView: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) {
        self.isViewList = false
        self.makeViewFn = makeView
        self.makeViewListFn = nil
    }

    init(makeViewList: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) {
        self.isViewList = true
        self.makeViewFn = nil
        self.makeViewListFn = makeViewList
    }
}

extension BodyInputElement: Equatable {
    // Different body kinds are not equal. Matching kinds are also conservatively
    // false because stored Swift closures cannot be compared directly.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.isViewList == rhs.isViewList else { return false }
        return false
    }
}

extension BodyInputElement: GraphReusable {
    static var isTriviallyReusable: Bool { true }
    mutating func tryToReuse(by other: Self, indirectMap: IndirectAttributeMap, testOnly: Bool) -> Bool { true }
}

// MARK: - BodyInput<Content>
// PropertyKey for the ViewModifier body closure stack.
// Value = Stack<BodyInputElement>. defaultValue = .empty.
// Conforms to both ViewInput and GraphInput. Stored via _GraphInputs.append (base channel).
struct BodyInput<Content>: ViewInput {
    typealias Value = Stack<BodyInputElement>
    static var defaultValue: Stack<BodyInputElement> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    // BodyInputElement is trivially reusable, so the stack key is reusable too.
    static var isTriviallyReusable: Bool { true }
}

// MARK: - BodyCountInput<Content>
// Count-only companion to BodyInput. It carries the body count closure while
// a modifier body's `_viewListCount` asks `_ViewModifier_Content` for the
// modified content count.
struct BodyCountInput<Content>: GraphInput {
    typealias CountBody = (_ViewListCountInputs) -> Int?
    typealias Value = Stack<CountBody>

    static var defaultValue: Stack<CountBody> { .empty }
    static func valuesEqual(_ a: Value, _ b: Value) -> Bool { false }
    static var isTriviallyReusable: Bool { true }
}

extension _ViewListCountInputs {
    static func withBodyCache<Content>(
        type: Content.Type,
        inputs: _ViewListCountInputs,
        content: (_ViewListCountInputs) -> Int?,
        body: @escaping (_ViewListCountInputs) -> Int?
    ) -> Int? {
        var inputs = inputs
        inputs.append(body, to: BodyCountInput<Content>.self)
        return content(inputs)
    }

    @usableFromInline
    func cachedViewListCount<Content>(type: Content.Type) -> Int? {
        var inputs = self
        guard let body: BodyCountInput<Content>.CountBody = inputs.popLast(BodyCountInput<Content>.self) else {
            return nil
        }
        return body(inputs)
    }
}

// MARK: - _ViewModifier_Content<Modifier>

public struct _ViewModifier_Content<Modifier> where Modifier: ViewModifier {
    public typealias Body = Never
}

extension _ViewModifier_Content: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Self.providerMakeView(view: view, inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Self.providerMakeViewList(view: view, inputs: inputs)
    }

    // Count resolution reads the matching BodyCountInput stack entry.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        _viewListCount(inputs: inputs)
    }

    // Always-emitted client wrapper.
    @_alwaysEmitIntoClient
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        inputs.cachedViewListCount(type: Self.self)
    }
}

extension _ViewModifier_Content {
    // Consumes the latest BodyInputElement and calls the stored closure.
    static func providerMakeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var inputs = inputs
        guard let elem = inputs.popLast(BodyInput<Self>.self) else {
            return _ViewOutputs()
        }
        if elem.isViewList {
            guard let fn = elem.makeViewListFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView: missing view-list body.")
            }
            guard let graph = _AGGraph.current else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView called outside AG context.")
            }
            let rootAttr: Attribute<_VStackLayout> = graph.makeInput(value: _VStackLayout())
            // View-list body closures use the default VStack implicit root in this path.
            return _VStackLayout._makeLayoutView(root: _GraphValue(_attribute: rootAttr), inputs: inputs) { _, childInputs in
                fn(_Graph(), childInputs.listInputs)
            }
        } else {
            guard let fn = elem.makeViewFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeView: missing view body.")
            }
            return fn(_Graph(), inputs)
        }
    }

    // providerMakeViewList consumes directly from the base graph inputs.
    static func providerMakeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs
        guard let elem = inputs.base.popLast(BodyInput<Self>.self) else {
            return _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
        }
        if elem.isViewList {
            guard let fn = elem.makeViewListFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeViewList: missing view-list body.")
            }
            return fn(_Graph(), inputs)
        } else {
            guard let fn = elem.makeViewFn else {
                fatalError("_ViewModifier_Content<\(Modifier.self)>.providerMakeViewList: missing view body.")
            }
            // makeView body closures are exposed as a unary view-list element.
            return _ViewListOutputs.unaryViewList(viewType: Self.self, inputs: inputs) { viewInputs in
                var viewInputs = viewInputs
                var mergedBase = inputs.base
                mergedBase.merge(viewInputs.base, ignoringPhase: false)
                mergedBase.applyViewPhaseOverrideIfNeeded()
                viewInputs.base = mergedBase
                return fn(_Graph(), viewInputs)
            }
        }
    }
}

@available(*, unavailable)
extension _ViewModifier_Content: Sendable {
}

extension _ViewModifier_Content: PrimitiveView {
}

// MARK: - ViewModifier

public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content) -> Self.Body
    typealias Content = _ViewModifier_Content<Self>

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs
    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs
    // Returns static view count, or nil when the count is dynamic or unknown.
    static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int?
}

extension ViewModifier where Self.Body == Never {
    public func body(content: Self.Content) -> Self.Body {
        fatalError("\(Self.self) may not have Body == Never")
    }

    // Body == Never modifiers are transparent for count. Inner content determines count.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        body(inputs)
    }
}

extension ViewModifier {
    var _content: Self.Body {
        body(content: _ViewModifier_Content())
    }

    // Default count handling evaluates the modifier body, which asks
    // _ViewModifier_Content to read the body count closure from BodyCountInput.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        withoutActuallyEscaping(body) { body in
            viewListCount(inputs: inputs, body: body)
        }
    }

    static func viewListCount(
        inputs: _ViewListCountInputs,
        body: @escaping (_ViewListCountInputs) -> Int?
    ) -> Int? {
        _ViewListCountInputs.withBodyCache(
            type: Content.self,
            inputs: inputs,
            content: { inputs in Body._viewListCount(inputs: inputs) },
            body: body
        )
    }

    // Modifier bodies must be value types. Build the modifier body through
    // ModifierBodyAccessor so DynamicProperty fields receive the current graph inputs.
    static func makeBody(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<Body>, Optional<_DynamicPropertyBuffer>) {
        precondition(!(Self.self is AnyObject.Type), "view modifiers must be value types: \(Self.self)")
        return ModifierBodyAccessor<Self>.makeBody(container: modifier, inputs: &inputs, fields: fields)
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        // Build the modifier body through the dynamic-property body accessor path.
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (bodyGV, _) = Self.makeBody(modifier: modifier, inputs: &graphInputs, fields: dpFields)

        var inputs = inputs
        inputs.base = graphInputs
        // Default path appends directly to graph inputs instead of using pushModifierBody.
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<Content>.self)
        return Body._makeView(view: bodyGV, inputs: inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }

        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (bodyGV, _) = Self.makeBody(modifier: modifier, inputs: &graphInputs, fields: dpFields)

        var inputs = inputs
        inputs.base = graphInputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<Content>.self)
        return Body._makeViewList(view: bodyGV, inputs: inputs)
    }
}

// _GraphInputsModifier is a type of modifier that modifies _GraphInputs.
public protocol _GraphInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs)
}

protocol ViewInputsModifier: ViewModifier {
    static var graphInputsSemantics: Semantics? { get }
    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs)
}

extension ViewInputsModifier {
    static var graphInputsSemantics: Semantics? {
        nil
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var inputs = inputs
        Self._makeViewInputs(modifier: modifier, inputs: &inputs)
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graphInputsSemantics,
              isDeployedOnOrAfter(graphInputsSemantics) else {
            var outputs = body(_Graph(), inputs)
            outputs.multiModifier(modifier, inputs: inputs)
            return outputs
        }
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }
        let stubPoint: Attribute<CGPoint> = graph.makeInput(value: .zero)
        let stubSize: Attribute<ViewSize> = graph.makeInput(value: ViewSize(width: 0, height: 0))
        let stubTransform: Attribute<ViewTransform> = graph.makeInput(value: .identity)
        let stubPrefsKeys: Attribute<PreferenceKeys> = graph.makeInput(value: PreferenceKeys())
        var viewInputs = _ViewInputs(
            base: inputs.base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(keys: PreferenceKeys(), hostKeys: stubPrefsKeys),
            transform: stubTransform,
            position: stubPoint,
            containerPosition: stubPoint,
            size: stubSize,
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
        Self._makeViewInputs(modifier: modifier, inputs: &viewInputs)
        var inputs = inputs
        inputs.base = viewInputs.base
        return body(_Graph(), inputs)
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        body(inputs)
    }
}

protocol UnaryViewModifier: ViewModifier {
}

extension UnaryViewModifier {
    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        makeUnaryViewList(modifier: modifier, inputs: inputs, body: body)
    }

    public static func _viewListCount(
        inputs: _ViewListCountInputs,
        body: (_ViewListCountInputs) -> Int?
    ) -> Int? {
        1
    }
}

extension ViewModifier {
    static func makeUnaryViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(viewType: Self.self, inputs: inputs) { viewInputs in
            makeImplicitRoot(
                modifier: modifier,
                inputs: viewInputs,
                body: body
            )
        }
    }

    static func makeImplicitRoot(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        Self._makeView(modifier: modifier, inputs: inputs) { _, inputs in
            guard let graph = _AGGraph.current else {
                fatalError("\(Self.self).makeImplicitRoot called outside an active _AGGraph context.")
            }
            let root = graph.makeInput(value: _VStackLayout())
            return _VStackLayout._makeLayoutView(
                root: _GraphValue(_attribute: root),
                inputs: inputs
            ) { _, inputs in
                body(_Graph(), inputs.listInputs)
            }
        }
    }
}


extension ViewModifier where Self: _GraphInputsModifier, Self.Body == Never {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)
        return body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        Self._makeInputs(modifier: modifier, inputs: &inputs.base)
        return body(_Graph(), inputs)
    }

    // _GraphInputsModifier is transparent for count. Inner content determines count.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        body(inputs)
    }
}

// Animatable modifiers let _makeAnimatable replace the modifier graph value
// before pushing BodyInput and evaluating the modifier body. UnaryLayout keeps a
// more specific _makeView implementation and does not route through this path.
extension ViewModifier where Self: Animatable {
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<Content>.self)
        return Body._makeView(view: modifier[\._content], inputs: inputs)
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        var inputs = inputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<Content>.self)
        return Body._makeViewList(view: modifier[\._content], inputs: inputs)
    }
    // This extension inherits _viewListCount from the default ViewModifier extension.
}

extension ViewModifier {
    @inlinable public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> {
          return .init(content: self, modifier: modifier)
      }
}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Modifier._makeView(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(view: view[\.content], inputs: inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        // Dispatch: Modifier._makeViewList owns all modifier-specific list behavior.
        //
        // MultiViewModifier (AlertModifier, GestureViewModifier, _BackgroundModifier, etc.):
        //   Inherits MultiViewModifier._makeViewList default, calls body, then wraps with
        //   ModifiedElements. Element materialization then calls Modifier._makeView per child
        //   or layout methods for unary layout modifiers.
        //
        // MultiViewModifier with _makeViewList override (ToolbarFilterModifier):
        //   Override is selected and body pass-through is preserved.
        //
        // Non-MultiViewModifier with Body == Never and explicit _makeViewList override
        //   (_PreferenceTransformModifier): override runs (body pass-through).
        //
        // Non-PrimitiveViewModifier, Body != Never (SheetToolbarModifier):
        //   ViewModifier._makeViewList default builds a body-based list.
        return Modifier._makeViewList(modifier: view[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(view: view[\.content], inputs: inputs)
        }
    }

    // ModifiedContent delegates count handling to the modifier, with content
    // count supplied as the body closure.
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        Modifier._viewListCount(inputs: inputs) { inputs in
            Content._viewListCount(inputs: inputs)
        }
    }
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        Modifier._makeView(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeView(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        Modifier._makeViewList(modifier: modifier[\.modifier], inputs: inputs) { _, inputs in
            Content._makeViewList(modifier: modifier[\.content], inputs: inputs, body: body)
        }
    }

    // Chained modifiers: outer modifier's _viewListCount wraps inner modifier's count.
    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        Modifier._viewListCount(inputs: inputs) { inputs in
            Content._viewListCount(inputs: inputs, body: body)
        }
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> {
        return ModifiedContent(content: self, modifier: modifier)
    }
}

/// Marker protocol for modifiers whose view construction is implemented
/// without evaluating a modifier body.
protocol PrimitiveViewModifier: ViewModifier {}

/// Primitive view-modifier marker that provides the default multi-element list wrapper.
protocol MultiViewModifier: PrimitiveViewModifier where Body == Never {}

extension MultiViewModifier {
    // Calls body to get inner outputs, then wraps via multiModifier.
    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

/// Layout-specific modifier protocol used by geometry-only modifiers.
protocol UnaryLayout: Animatable, MultiViewModifier, PrimitiveViewModifier {
    associatedtype PlacementContextType
    static func makeViewImpl(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs
    func spacing(
        in context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> Spacing
    func placement(
        of child: LayoutProxy,
        in context: PlacementContextType
    ) -> _Placement
    func sizeThatFits(
        in proposal: _ProposedSize,
        context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> CGSize
    func layoutPriority(child: LayoutProxy) -> Double
    func ignoresAutomaticPadding(child: LayoutProxy) -> Bool
}

extension UnaryLayout {
    func spacing(
        in context: SizeAndSpacingContext,
        child: LayoutProxy
    ) -> Spacing {
        child.layoutComputer.spacing()
    }

    func layoutPriority(child: LayoutProxy) -> Double {
        child.layoutComputer.layoutPriority()
    }

    func ignoresAutomaticPadding(child: LayoutProxy) -> Bool {
        false
    }
}

struct PlacementContext {
    private enum ParentSize {
        case eager(ViewSize)
        case lazy(Attribute<ViewSize>)

        var value: ViewSize {
            switch self {
            case .eager(let size):
                return size
            case .lazy(let size):
                return size.value
            }
        }
    }

    var context: AnyRuleContext
    var owner: AGAttribute
    var _environment: Attribute<EnvironmentValues>
    private var parentSize: ParentSize

    init(
        context: AnyRuleContext,
        owner: AGAttribute?,
        environment: Attribute<EnvironmentValues>,
        parentSize: ViewSize
    ) {
        self.context = context
        self.owner = owner ?? context.attribute
        self._environment = environment
        self.parentSize = .eager(parentSize)
    }

    init(
        context: AnyRuleContext,
        owner: AGAttribute?,
        environment: Attribute<EnvironmentValues>,
        parentSize: Attribute<ViewSize>
    ) {
        self.context = context
        self.owner = owner ?? context.attribute
        self._environment = environment
        self.parentSize = .lazy(parentSize)
    }

    var size: CGSize {
        parentSize.value.value
    }

    var proposedSize: _ProposedSize {
        parentSize.value.proposal
    }
}

struct Cache3<Key: Equatable, Value> {
    typealias Entry = (key: Key, value: Value)

    var store: (Entry?, Entry?, Entry?) = (nil, nil, nil)

    func find(_ key: Key) -> Value? {
        if let entry = store.0, entry.key == key { return entry.value }
        if let entry = store.1, entry.key == key { return entry.value }
        if let entry = store.2, entry.key == key { return entry.value }
        return nil
    }

    mutating func get(_ key: Key, makeValue: () -> Value) -> Value {
        if let value = find(key) {
            return value
        }
        let value = makeValue()
        put(key, value: value)
        return value
    }

    mutating func put(_ key: Key, value: Value) {
        if store.0?.key == key {
            store.0 = (key, value)
        } else if store.1?.key == key {
            store.1 = (key, value)
        } else if store.2?.key == key {
            store.2 = (key, value)
        } else {
            store = (store.1, store.2, (key, value))
        }
    }

    func map(
        _ transform: (Entry?) -> Entry?
    ) -> Cache3<Key, Value> {
        var result = Cache3<Key, Value>()
        result.store = (
            transform(store.0),
            transform(store.1),
            transform(store.2)
        )
        return result
    }
}

/// Caches the three most recent proposal-to-size measurements for one engine.
struct ViewSizeCache {
    var cache: Cache3<ProposedViewSize, CGSize>

    init(cache: Cache3<ProposedViewSize, CGSize> = Cache3()) {
        self.cache = cache
        ViewSizeCacheStats.incrementInvalidationCount()
    }

    mutating func get(
        _ proposal: _ProposedSize,
        makeValue: () -> CGSize
    ) -> CGSize {
        let key = ProposedViewSize(proposal)
        if let value = cache.find(key) {
            ViewSizeCacheStats.incrementHitCount()
            LayoutTrace.traceCacheLookup(proposal, true)
            return value
        }
        ViewSizeCacheStats.incrementMissCount()
        LayoutTrace.traceCacheLookup(proposal, false)
        let value = makeValue()
        cache.put(key, value: value)
        return value
    }
}

/// Reports process-wide size-cache construction, hit, and miss counters.
struct ViewSizeCacheStats: Equatable, AdditiveArithmetic {
    var invalidationCount: UInt32
    var hitCount: UInt32
    var missCount: UInt32

    private static let invalidations = Atomic<UInt32>(0)
    private static let hits = Atomic<UInt32>(0)
    private static let misses = Atomic<UInt32>(0)

    static func current() -> ViewSizeCacheStats {
        ViewSizeCacheStats(
            invalidationCount: invalidations.load(ordering: .relaxed),
            hitCount: hits.load(ordering: .relaxed),
            missCount: misses.load(ordering: .relaxed)
        )
    }

    static func incrementInvalidationCount() {
        _ = invalidations.wrappingAdd(1, ordering: .relaxed)
    }

    static func incrementHitCount() {
        _ = hits.wrappingAdd(1, ordering: .relaxed)
    }

    static func incrementMissCount() {
        _ = misses.wrappingAdd(1, ordering: .relaxed)
    }

    static func + (
        lhs: ViewSizeCacheStats,
        rhs: ViewSizeCacheStats
    ) -> ViewSizeCacheStats {
        ViewSizeCacheStats(
            invalidationCount: lhs.invalidationCount &+ rhs.invalidationCount,
            hitCount: lhs.hitCount &+ rhs.hitCount,
            missCount: lhs.missCount &+ rhs.missCount
        )
    }

    static func - (
        lhs: ViewSizeCacheStats,
        rhs: ViewSizeCacheStats
    ) -> ViewSizeCacheStats {
        ViewSizeCacheStats(
            invalidationCount: lhs.invalidationCount &- rhs.invalidationCount,
            hitCount: lhs.hitCount &- rhs.hitCount,
            missCount: lhs.missCount &- rhs.missCount
        )
    }

    static let zero = ViewSizeCacheStats(
        invalidationCount: 0,
        hitCount: 0,
        missCount: 0
    )
}

/// Caches the three most recent resolved placements for one unary engine.
struct ViewPlacementCache {
    var cache = Cache3<ViewSize, _Placement>()

    mutating func get(
        _ size: ViewSize,
        makeValue: () -> _Placement
    ) -> _Placement {
        cache.get(size, makeValue: makeValue)
    }
}

/// Measures and places an ordinary unary layout using eager parent geometry.
private struct UnaryLayoutEngine<L: UnaryLayout>: LayoutEngine
where L.PlacementContextType == PlacementContext {
    var layout: L
    var layoutContext: SizeAndSpacingContext
    var child: LayoutProxy
    var dimensionsCache: ViewSizeCache
    var placementCache: ViewPlacementCache

    mutating func update(
        layout: L,
        layoutContext: SizeAndSpacingContext,
        child: LayoutProxy
    ) {
        self.layout = layout
        self.layoutContext = layoutContext
        self.child = child
        dimensionsCache = ViewSizeCache()
        placementCache = ViewPlacementCache()
    }

    func layoutPriority() -> Double {
        var result: Double!
        layoutContext.context.update {
            result = layout.layoutPriority(child: child)
        }
        return result
    }

    func ignoresAutomaticPadding() -> Bool {
        var result: Bool!
        layoutContext.context.update {
            result = layout.ignoresAutomaticPadding(child: child)
        }
        return result
    }

    func spacing() -> Spacing {
        var result: Spacing!
        layoutContext.context.update {
            result = layout.spacing(in: layoutContext, child: child)
        }
        return result
    }

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        let layout = layout
        let layoutContext = layoutContext
        let child = child
        return dimensionsCache.get(proposal) {
            var result: CGSize!
            layoutContext.context.update {
                result = layout.sizeThatFits(
                    in: proposal,
                    context: layoutContext,
                    child: child
                )
            }
            return result
        }
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        var result: CGFloat?
        layoutContext.context.update {
            result = child.layoutComputer.explicitAlignment(key, at: size)
        }
        return result
    }

    mutating func childPlacement(at size: ViewSize) -> _Placement {
        let layout = layout
        let layoutContext = layoutContext
        let child = child
        return placementCache.get(size) {
            var result: _Placement!
            layoutContext.context.update {
                result = layout.placement(
                    of: child,
                    in: PlacementContext(
                        context: layoutContext.context,
                        owner: layoutContext.owner,
                        environment: layoutContext._environment,
                        parentSize: size
                    )
                )
            }
            return result
        }
    }

}

/// Measures a unary layout whose placement reads graph-backed position context.
private struct UnaryPositionAwareLayoutEngine<L: UnaryLayout>: LayoutEngine
where L.PlacementContextType == _PositionAwarePlacementContext {
    var layout: L
    var layoutContext: SizeAndSpacingContext
    var child: LayoutProxy
    var cache: ViewSizeCache

    mutating func update(
        layout: L,
        layoutContext: SizeAndSpacingContext,
        child: LayoutProxy
    ) {
        self.layout = layout
        self.layoutContext = layoutContext
        self.child = child
        cache = ViewSizeCache()
    }

    func layoutPriority() -> Double {
        var result: Double!
        layoutContext.context.update {
            result = layout.layoutPriority(child: child)
        }
        return result
    }

    func ignoresAutomaticPadding() -> Bool {
        var result: Bool!
        layoutContext.context.update {
            result = layout.ignoresAutomaticPadding(child: child)
        }
        return result
    }

    func spacing() -> Spacing {
        var result: Spacing!
        layoutContext.context.update {
            result = layout.spacing(in: layoutContext, child: child)
        }
        return result
    }

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        let layout = layout
        let layoutContext = layoutContext
        let child = child
        return cache.get(proposal) {
            var result: CGSize!
            layoutContext.context.update {
                result = layout.sizeThatFits(
                    in: proposal,
                    context: layoutContext,
                    child: child
                )
            }
            return result
        }
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        var result: CGFloat?
        layoutContext.context.update {
            result = child.layoutComputer.explicitAlignment(key, at: size)
        }
        return result
    }

    func childPlacement(
        at size: ViewSize,
        placementContext: _PositionAwarePlacementContext
    ) -> _Placement {
        var result: _Placement!
        placementContext.context.update {
            result = layout.placement(of: child, in: placementContext)
        }
        return result
    }
}

/// Publishes the ordinary unary engine while preserving its measurement caches.
/// An absent child computer remains optional so `LayoutProxy` supplies the default leaf metrics.
private struct UnaryLayoutComputer<L: UnaryLayout>: StatefulRule, AsyncAttribute
where L.PlacementContextType == PlacementContext {
    typealias Value = LayoutComputer

    var _layout: Attribute<L>
    var _environment: Attribute<EnvironmentValues>
    var _childLayoutComputer: OptionalAttribute<LayoutComputer>

    mutating func updateValue() {
        let layout = _layout.value
        let ruleContext = AnyRuleContext(context)
        // The unary rule owns every child-computer read performed by its
        // engine. A child attribute is data, not a substitute context owner.
        let child = LayoutProxy(
            context: ruleContext,
            layoutComputer: _childLayoutComputer.attribute
        )
        let layoutContext = SizeAndSpacingContext(
            context: ruleContext,
            owner: context.attribute.identifier,
            environment: _environment
        )
        update(
            modify: { (engine: inout UnaryLayoutEngine<L>) in
                engine.update(
                    layout: layout,
                    layoutContext: layoutContext,
                    child: child
                )
            },
            create: {
                UnaryLayoutEngine(
                    layout: layout,
                    layoutContext: layoutContext,
                    child: child,
                    dimensionsCache: ViewSizeCache(),
                    placementCache: ViewPlacementCache()
                )
            }
        )
    }
}

/// Publishes the position-aware unary engine and its proposal cache.
/// It preserves a missing child computer as the proxy's default-layout sentinel.
private struct UnaryPositionAwareLayoutComputer<L: UnaryLayout>:
    StatefulRule, AsyncAttribute
where L.PlacementContextType == _PositionAwarePlacementContext {
    typealias Value = LayoutComputer

    var _layout: Attribute<L>
    var _environment: Attribute<EnvironmentValues>
    var _childLayoutComputer: OptionalAttribute<LayoutComputer>

    mutating func updateValue() {
        let layout = _layout.value
        let ruleContext = AnyRuleContext(context)
        // Measurement and position-aware placement share the publishing
        // rule's identity so both dependency paths invalidate one owner.
        let child = LayoutProxy(
            context: ruleContext,
            layoutComputer: _childLayoutComputer.attribute
        )
        let layoutContext = SizeAndSpacingContext(
            context: ruleContext,
            owner: context.attribute.identifier,
            environment: _environment
        )
        update(
            modify: { (engine: inout UnaryPositionAwareLayoutEngine<L>) in
                engine.update(
                    layout: layout,
                    layoutContext: layoutContext,
                    child: child
                )
            },
            create: {
                UnaryPositionAwareLayoutEngine(
                    layout: layout,
                    layoutContext: layoutContext,
                    child: child,
                    cache: ViewSizeCache()
                )
            }
        )
    }
}

/// Resolves ordinary unary placement into the child geometry output.
/// Layout-empty children are measured through `LayoutProxy`'s default computer.
private struct UnaryChildGeometry<L: UnaryLayout>: Rule, AsyncAttribute {
    var _parentSize: Attribute<ViewSize>
    var _layoutDirection: Attribute<LayoutDirection>
    var _parentLayoutComputer: Attribute<LayoutComputer>
    var _childLayoutComputer: OptionalAttribute<LayoutComputer>

    var value: ViewGeometry {
        let size = _parentSize.value
        let placement = _parentLayoutComputer.value.childPlacement(at: size)
        guard let currentAttribute = _AGGraph.currentRuleContextAttribute else {
            fatalError(
                "UnaryChildGeometry evaluated outside an active rule context."
            )
        }
        // Final measurement belongs to this geometry rule even though the
        // measured computer belongs to the child.
        return LayoutProxy(
            context: AnyRuleContext(attribute: currentAttribute),
            layoutComputer: _childLayoutComputer.attribute
        ).finallyPlaced(
            at: placement,
            in: size.value,
            layoutDirection: _layoutDirection.value
        )
    }
}

/// Resolves position-aware unary placement from live graph geometry inputs.
/// Its child proxy retains the optional-computer sentinel through placement.
private struct UnaryPositionAwareChildGeometry<L: UnaryLayout>:
    Rule, AsyncAttribute
where L.PlacementContextType == _PositionAwarePlacementContext {
    var _parentLayoutComputer: Attribute<LayoutComputer>
    var _layoutDirection: Attribute<LayoutDirection>
    var _parentSize: Attribute<ViewSize>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var _environment: Attribute<EnvironmentValues>
    var _childLayoutComputer: OptionalAttribute<LayoutComputer>
    var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>

    var value: ViewGeometry {
        guard let currentAttribute = _AGGraph.currentRuleContextAttribute else {
            fatalError(
                "UnaryPositionAwareChildGeometry evaluated outside an active rule context."
            )
        }
        let context = AnyRuleContext(attribute: currentAttribute)
        let parentSize = _parentSize.value
        let placementContext = _PositionAwarePlacementContext(
            context: context,
            owner: currentAttribute,
            size: _parentSize,
            environment: _environment,
            transform: _transform,
            position: _position,
            safeAreaInsets: _safeAreaInsets
        )
        let placement = _parentLayoutComputer.value.childPlacement(
            at: parentSize,
            placementContext: placementContext
        )
        // The geometry rule remains the dependency owner for final child
        // measurement; the optional child computer is only the measured input.
        var geometry = LayoutProxy(
            context: context,
            layoutComputer: _childLayoutComputer.attribute
        ).finallyPlaced(
            at: placement,
            in: parentSize.value,
            layoutDirection: _layoutDirection.value
        )
        let position = _position.value
        geometry.origin.x += position.x
        geometry.origin.y += position.y
        return geometry
    }
}

/// Combines parent and layout-local positions for ordinary unary descendants.
struct LayoutPositionQuery: Rule, AsyncAttribute {
    var _parentPosition: Attribute<CGPoint>
    var _localPosition: Attribute<CGPoint>

    var value: CGPoint {
        let parent = _parentPosition.value
        let local = _localPosition.value
        return CGPoint(x: parent.x + local.x, y: parent.y + local.y)
    }
}

extension UnaryLayout {
    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        makeViewImpl(modifier: modifier, inputs: inputs, body: body)
    }
}

extension UnaryLayout where PlacementContextType == PlacementContext {
    static func makeViewImpl(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard inputs.needsLayout else {
            return body(_Graph(), inputs)
        }
        guard let graph = _AGGraph.current else {
            fatalError("\(self).makeViewImpl called outside an active _AGGraph context.")
        }
        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        let environment = inputs.base.cachedEnvironment.value.environment
        let parentLayoutComputer = graph.makeStatefulRule(
            UnaryLayoutComputer(
                _layout: modifier._attribute,
                _environment: environment,
                _childLayoutComputer: OptionalAttribute()
            )
        )
        var childInputs = inputs
        childInputs.copyCaches()
        let childGeometry: Attribute<UnaryChildGeometry<Self>.Value>?
        if inputs.needsGeometry {
            let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
                environment.value.layoutDirection
            }
            let geometry = graph.makeRule(
                UnaryChildGeometry<Self>(
                    _parentSize: inputs.size,
                    _layoutDirection: layoutDirection,
                    _parentLayoutComputer: parentLayoutComputer,
                    _childLayoutComputer: OptionalAttribute()
                )
            )
            childGeometry = geometry
            let localChildPosition: Attribute<CGPoint> = graph.makeRule {
                geometry.value.origin
            }
            let childSize: Attribute<ViewSize> = graph.makeRule {
                geometry.value.dimensions.size
            }
            let childPosition = graph.makeRule(
                LayoutPositionQuery(
                    _parentPosition: inputs.position,
                    _localPosition: localChildPosition
                )
            )
            let parentTransform = inputs.transform
            let childTransform: Attribute<ViewTransform> = graph.makeRule {
                var transform = parentTransform.value
                transform.appendPosition(childPosition.value)
                return transform
            }
            // Unary geometry replaces only the child's local frame channels.
            // The nearest container channels pass through unchanged.
            childInputs.position = childPosition
            childInputs.size = childSize
            childInputs.transform = childTransform
        } else {
            childGeometry = nil
        }
        childInputs.requestsLayoutComputer = true

        let childOutputs = body(_Graph(), childInputs)
        graph.mutateStatefulRule(
            parentLayoutComputer.identifier,
            as: UnaryLayoutComputer<Self>.self,
            invalidating: true
        ) { computer in
            computer._childLayoutComputer = childOutputs._layoutComputer
        }
        if let childGeometry {
            graph.mutateRule(
                childGeometry.identifier,
                as: UnaryChildGeometry<Self>.self,
                invalidating: true
            ) { geometry in
                geometry._childLayoutComputer = childOutputs._layoutComputer
            }
        }
        let cachedEnvAttr = inputs.base.cachedEnvironment
        let positionAttr  = inputs.position
        let sizeAttr      = inputs.size
        let debugDLAttr: Attribute<DisplayList> = graph.makeRule {
            let debugLayout = cachedEnvAttr.value.environment.value._debugLayout
            var dl = DisplayList()
            if debugLayout {
                let pos  = positionAttr.value
                let size = sizeAttr.value.value
                appendDebugOverlay(to: &dl,
                                   frame: CGRect(origin: pos, size: size),
                                   category: .layoutModifier)
            }
            return dl
        }
        var prefs = childOutputs.preferences
        prefs.append(DisplayList.Key.self, node: debugDLAttr.identifier)
        return _ViewOutputs(
            preferences: prefs,
            layoutComputer: inputs.requestsLayoutComputer
                ? OptionalAttribute(parentLayoutComputer)
                : OptionalAttribute()
        )
    }
}

extension UnaryLayout
where PlacementContextType == _PositionAwarePlacementContext {
    static func makeViewImpl(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard inputs.needsLayout else {
            return body(_Graph(), inputs)
        }
        guard let graph = _AGGraph.current else {
            fatalError("\(self).makeViewImpl called outside an active _AGGraph context.")
        }

        var modifier = modifier
        Self._makeAnimatable(value: &modifier, inputs: inputs.base)
        let environment = inputs.base.cachedEnvironment.value.environment
        var childInputs = inputs
        childInputs.copyCaches()

        let geometryLayoutComputer: Attribute<LayoutComputer>?
        let childGeometry: Attribute<ViewGeometry>?
        if inputs.needsGeometry {
            let layoutComputer = graph.makeStatefulRule(
                UnaryPositionAwareLayoutComputer(
                    _layout: modifier._attribute,
                    _environment: environment,
                    _childLayoutComputer: OptionalAttribute()
                )
            )
            geometryLayoutComputer = layoutComputer
            let layoutDirection: Attribute<LayoutDirection> = graph.makeRule {
                environment.value.layoutDirection
            }
            let geometry = graph.makeRule(
                UnaryPositionAwareChildGeometry<Self>(
                    _parentLayoutComputer: layoutComputer,
                    _layoutDirection: layoutDirection,
                    _parentSize: inputs.size,
                    _position: inputs.position,
                    _transform: inputs.transform,
                    _environment: environment,
                    _childLayoutComputer: OptionalAttribute(),
                    _safeAreaInsets: inputs.safeAreaInsets
                )
            )
            childGeometry = geometry
            let childPosition = graph.subscriptNode(
                parent: geometry,
                keyPath: \ViewGeometry.origin
            )
            let childSize = graph.subscriptNode(
                parent: geometry,
                keyPath: \ViewGeometry.dimensions.size
            )
            let parentTransform = inputs.transform
            // Unary geometry replaces only the child's local frame channels.
            // The nearest container channels pass through unchanged.
            childInputs.position = childPosition
            childInputs.size = childSize
            childInputs.transform = graph.makeRule {
                var transform = parentTransform.value
                transform.appendPosition(childPosition.value)
                return transform
            }
        } else {
            geometryLayoutComputer = nil
            childGeometry = nil
        }

        childInputs.requestsLayoutComputer = true
        let childOutputs = body(_Graph(), childInputs)

        if let geometryLayoutComputer {
            graph.mutateStatefulRule(
                geometryLayoutComputer.identifier,
                as: UnaryPositionAwareLayoutComputer<Self>.self,
                invalidating: true
            ) { computer in
                computer._childLayoutComputer = childOutputs._layoutComputer
            }
        }
        if let childGeometry {
            graph.mutateRule(
                childGeometry.identifier,
                as: UnaryPositionAwareChildGeometry<Self>.self,
                invalidating: true
            ) { geometry in
                geometry._childLayoutComputer = childOutputs._layoutComputer
            }
        }

        let outputLayoutComputer: OptionalAttribute<LayoutComputer>
        if inputs.requestsLayoutComputer {
            let layoutComputer = graph.makeStatefulRule(
                UnaryPositionAwareLayoutComputer(
                    _layout: modifier._attribute,
                    _environment: environment,
                    _childLayoutComputer: childOutputs._layoutComputer
                )
            )
            outputLayoutComputer = OptionalAttribute(layoutComputer)
        } else {
            outputLayoutComputer = OptionalAttribute()
        }

        return _ViewOutputs(
            preferences: childOutputs.preferences,
            layoutComputer: outputLayoutComputer
        )
    }
}

// MARK: - _ViewInputs + pushModifierBody / popLast / top
// ViewModifier body stack helpers.
// pushModifierBody creates a BodyInputElement and appends it to graph inputs.
// The default ViewModifier._makeView path appends directly instead of using this helper.
// popLast: Thin wrapper delegating to _GraphInputs.popLast.
// top: Thin wrapper delegating to _GraphInputs.top.

extension _ViewInputs {
    /// Pushes a makeView closure onto the BodyInput stack.
    mutating func pushModifierBody<T>(_ type: T.Type, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) {
        base.append(BodyInputElement(makeView: body), forKey: BodyInput<T>.self)
    }

    /// Returns the top element of the Stack for a ViewInput key without consuming it. Delegates to _GraphInputs.top.
    func top<T: ViewInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        base.top(key)
    }

    /// Pops the top element from the Stack for a ViewInput key. Thin wrapper delegating to _GraphInputs.popLast.
    mutating func popLast<T: ViewInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        base.popLast(key)
    }
}

extension _ViewListInputs {
    /// Pushes a makeViewList closure onto the BodyInput stack.
    mutating func pushModifierBody<T>(_ type: T.Type, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) {
        base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<T>.self)
    }
}
