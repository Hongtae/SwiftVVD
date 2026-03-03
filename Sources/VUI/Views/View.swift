//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Self.Body { get }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}

extension View {
    /// Default implementation for Body == Never (primitive views not yet AG-implemented):
    /// returns a stub 10×10 LayoutComputer so the layout tree wires correctly.
    ///
    /// For Body != Never: creates a reactive body rule that
    ///   1. reads the live `EnvironmentValues` AG node (registers dependency), and
    ///   2. tracks `@Observable` property accesses via `withObservationTracking`.
    /// Both environment changes and @Observable mutations invalidate the body rule
    /// automatically, causing it to re-evaluate on the next render pass.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        if self is any _PrimitiveView.Type {
            let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
                LayoutComputer.fixed(CGSize(width: 10, height: 10))
            }
            return _ViewOutputs(preferences: PreferencesOutputs(),
                                layoutComputer: OptionalAttribute(lcAttr))
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }

        // Build DynamicProperty buffer (e.g. @Environment resolve closures).
        var dpBuffer = _DynamicPropertyBuffer()
        var graphInputs = inputs.base
        _forEachField(of: Self.self) { _, offset, fieldType in
            if let propType = fieldType as? any DynamicProperty.Type {
                func make<T: DynamicProperty>(_ t: T.Type) {
                    T._makeProperty(in: &dpBuffer, container: view, fieldOffset: offset, inputs: &graphInputs)
                }
                make(propType)
            }
            return true
        }

        // Body rule: reactive to environment changes and @Observable mutations.
        let inbox  = graph.inbox
        let handle = MutableBox<AGAttribute?>(nil)

        let bodyAttr: Attribute<Body> = graph.makeRule {
            // Get a mutable copy of the view struct (fields are still .keyPath at this point).
            var viewCopy = view._attribute.value

            // Apply DynamicProperty resolutions: each write closure reads the live
            // environment (registering AG dependencies) and mutates the copy in place
            // before calling body.
            if !dpBuffer.properties.isEmpty {
                withUnsafeMutableBytes(of: &viewCopy) { bytes in
                    for prop in dpBuffer.properties {
                        if let write = dpBuffer.contexts[prop.offset] as? (UnsafeMutableRawPointer) -> Void {
                            write(bytes.baseAddress!.advanced(by: prop.offset))
                        }
                    }
                }
            }

            var result: Body!
            withObservationTracking {
                result = viewCopy.body
            } onChange: { [weak inbox, handle] in
                inbox?.enqueue {
                    if let id = handle.value {
                        AttributeGraph.current?.markNeedsEvaluation(id)
                    }
                }
            }
            return result
        }
        handle.value = bodyAttr.identifier

        return Body._makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
    }

    /// Default implementation: produces a reactive body rule (same as `_makeView`)
    /// then delegates list construction to `Body._makeViewList`.
    ///
    /// For Body == Never: returns a single-proxy static list so the parent layout
    /// can call `_makeView` via the proxy.
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if self is any _PrimitiveView.Type {
            return _ViewListOutputs(
                views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
                nextImplicitID: 1,
                staticCount: 1
            )
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }

        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        // Build DynamicProperty buffer — mirrors _makeView.
        var dpBuffer = _DynamicPropertyBuffer()
        var graphInputs = inputs.base
        _forEachField(of: Self.self) { _, offset, fieldType in
            if let propType = fieldType as? any DynamicProperty.Type {
                func make<T: DynamicProperty>(_ t: T.Type) {
                    T._makeProperty(in: &dpBuffer, container: view, fieldOffset: offset, inputs: &graphInputs)
                }
                make(propType)
            }
            return true
        }

        let inbox  = graph.inbox
        let handle = MutableBox<AGAttribute?>(nil)

        let bodyAttr: Attribute<Body> = graph.makeRule {
            var viewCopy = view._attribute.value

            if !dpBuffer.properties.isEmpty {
                withUnsafeMutableBytes(of: &viewCopy) { bytes in
                    for prop in dpBuffer.properties {
                        if let write = dpBuffer.contexts[prop.offset] as? (UnsafeMutableRawPointer) -> Void {
                            write(bytes.baseAddress!.advanced(by: prop.offset))
                        }
                    }
                }
            }

            var result: Body!
            withObservationTracking {
                result = viewCopy.body
            } onChange: { [weak inbox, handle] in
                inbox?.enqueue {
                    if let id = handle.value {
                        AttributeGraph.current?.markNeedsEvaluation(id)
                    }
                }
            }
            return result
        }
        handle.value = bodyAttr.identifier

        return Body._makeViewList(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
    }
}

// _PrimitiveView is a View type that does not have a body. (body = Never)
protocol _PrimitiveView {
}

extension _PrimitiveView {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension Never: View {
}

// File-scope state class — cannot be nested inside a generic function in Swift.
private final class _OptionalViewState {
    var hasValue: Bool? = nil
    var subgraph: Subgraph? = nil
    var lcAttr: Attribute<LayoutComputer>? = nil
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never

    /// Dynamic-subgraph implementation for optional views.
    ///
    /// When `.none` → `.some`, creates a Subgraph and wires `Wrapped._makeView` into it.
    /// When `.some` → `.none`, invalidates the subgraph; master rule returns `.fixed(.zero)`.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let state = _OptionalViewState()
        state.subgraph = Subgraph() // Created while parent Subgraph is active

        let masterLC: Attribute<LayoutComputer> = graph.makeRule {
            // Retrieve the active graph from TaskLocal to avoid a retain cycle
            guard let graph = AttributeGraph.current else {
                fatalError("Optional<\(Wrapped.self)> rule evaluated outside an active AttributeGraph context.")
            }

            let nowHas = view._attribute.value != nil

            if state.hasValue != nowHas {
                // Invalidate clears old nodes/children but keeps this subgraph attached to its parent
                state.subgraph?.invalidate()
                state.hasValue = nowHas

                if nowHas {
                    // Force-unwrap is safe: node lives only while hasValue == true.
                    let wrappedAttr: Attribute<Wrapped> = Subgraph.$current.withValue(state.subgraph) {
                        graph.makeRule { view._attribute.value! }
                    }
                    let outputs = Subgraph.$current.withValue(state.subgraph) {
                        Wrapped._makeView(view: _GraphValue(_attribute: wrappedAttr), inputs: inputs)
                    }
                    state.lcAttr = outputs._layoutComputer.attribute
                } else {
                    state.lcAttr = nil
                }
            }

            return state.lcAttr?.value ?? LayoutComputer.fixed(.zero)
        }

        return _ViewOutputs(preferences: PreferencesOutputs(),
                            layoutComputer: OptionalAttribute(masterLC))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

extension Optional: _PrimitiveView where Self: View {
}

struct IDView<Content, ID>: View where Content: View, ID: Hashable {
    var content: Content
    var id: ID

    init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    typealias Body = Never
    var body: Never { neverBody() }
}

extension View {
    public func id<ID>(_ id: ID) -> some View where ID: Hashable {
        IDView(self, id: id)
    }
}

extension IDView {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Content._makeView(view: view[\.content], inputs: inputs)
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}

func makeView<V: View>(view: _GraphValue<V>, inputs: _ViewInputs) -> _ViewOutputs {
    V._makeView(view: view, inputs: inputs)
}

struct ViewProxy: Hashable {
    let type: any View.Type
    let graph: _GraphValue<Any>

    init<V: View>(_ graph: _GraphValue<V>) {
        self.type = V.self
        self.graph = graph.unsafeCast(to: Any.self)
    }

    func makeView(_: _Graph, inputs: _ViewInputs) -> _ViewOutputs {
        func make<T: View>(_ type: T.Type) -> _ViewOutputs {
            T._makeView(view: self.graph.unsafeCast(to: T.self), inputs: inputs)
        }
        return make(self.type)
    }

    func makeViewList(_: _Graph, inputs: _ViewListInputs) -> _ViewListOutputs {
        func make<T: View>(_ type: T.Type) -> _ViewListOutputs {
            T._makeViewList(view: self.graph.unsafeCast(to: T.self), inputs: inputs)
        }
        return make(self.type)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.graph == rhs.graph
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(graph._attribute.identifier)
    }
}

struct TypedUnaryViewGenerator {
    var view: AGWeakAttribute
    var viewType: any View.Type
    var baseInputs: _GraphInputs
    /// AG-backed trait collection for this subview.
    /// `nil` (empty OptionalAttribute) when no `_TraitWritingModifier` was applied.
    /// Set by `_TraitWritingModifier._makeViewList` to a derived `Attribute<ViewTraitCollection>`.
    var traitListAttr: OptionalAttribute<ViewTraitCollection> = OptionalAttribute()
}

extension TypedUnaryViewGenerator {
    init<V: View>(_ graphValue: _GraphValue<V>, baseInputs: _GraphInputs) {
        guard AttributeGraph.current != nil else {
            fatalError("TypedUnaryViewGenerator init called outside an active AttributeGraph context.")
        }
        self.view = graphValue._attribute.asWeak()
        self.viewType = V.self
        self.baseInputs = baseInputs
    }

    init<V: View>(_ graphValue: _GraphValue<V>, inputs: _ViewListInputs) {
        guard AttributeGraph.current != nil else {
            fatalError("TypedUnaryViewGenerator init called outside an active AttributeGraph context.")
        }
        self.view = graphValue._attribute.asWeak()
        self.viewType = V.self
        self.baseInputs = inputs.base
        self.traitListAttr = inputs._traits
    }

    func makeView(inputs: _ViewInputs) -> _ViewOutputs? {
        guard let graph = AttributeGraph.current else {
            fatalError("TypedUnaryViewGenerator.makeView called outside an active AttributeGraph context.")
        }
        guard view.isValid(in: graph) else { return nil }
        let attrID = view.toStrong()
        func call<V: View>(_ t: V.Type) -> _ViewOutputs {
            let graphValue = _GraphValue<V>(_attribute: Attribute<V>(attrID))
            return V._makeView(view: graphValue, inputs: inputs)
        }
        return call(viewType)
    }

    func makeViewList(inputs: _ViewListInputs) -> _ViewListOutputs? {
        guard let graph = AttributeGraph.current else {
            fatalError("TypedUnaryViewGenerator.makeViewList called outside an active AttributeGraph context.")
        }
        guard view.isValid(in: graph) else { return nil }
        let attrID = view.toStrong()
        func call<V: View>(_ t: V.Type) -> _ViewListOutputs {
            var listInputs = inputs
            listInputs.base = baseInputs
            return V._makeViewList(view: _GraphValue<V>(_attribute: Attribute<V>(attrID)), inputs: listInputs)
        }
        return call(viewType)
    }
}

extension TypedUnaryViewGenerator: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.view.identifier == rhs.view.identifier
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(view.identifier)
    }
}


/// The bundle of AG context Attributes passed from parent → child during `_makeView`.
///
/// All geometry fields (`transform`, `position`, `size`, …) are Attribute references,
/// not concrete values: the parent creates the nodes at `_makeView` time (wiring phase)
/// and fills in their values later during the layout pass.
public struct _ViewInputs {
    /// Shared graph-level inputs (time, environment, transaction, …).
    var base: _GraphInputs

    /// Which preference keys this subtree should collect.
    var preferences: PreferencesInputs

    /// The cumulative coordinate-space transform for this child.
    var transform: Attribute<ViewTransform>

    /// The position assigned to this child by its parent (in parent-local coords).
    var position: Attribute<CGPoint>

    /// The position of the parent container (used for coordinate conversion).
    var containerPosition: Attribute<CGPoint>

    /// The proposed size this parent is offering to the child.
    var size: Attribute<ViewSize>

    /// Safe-area insets from the nearest ancestor that defines a safe area.
    /// `nil` when no safe-area context exists above this child.
    var safeAreaInsets: OptionalAttribute<SafeAreaInsets>

    /// The actual size of the parent container.
    /// `nil` when the parent has not yet been sized (e.g., during bootstrapping).
    var containerSize: OptionalAttribute<ViewSize>
}

/// The bundle of AG context Attributes passed from parent → child during `_makeViewList`.
///
/// Unlike `_ViewInputs`, this struct does NOT carry layout Attributes (`position`, `size`,
/// `transform`, etc.).  Those are created fresh by the parent Layout when it later calls
/// `_makeView` on each child proxy.  Only the non-layout context (`_GraphInputs`) is
/// threaded through the list-traversal phase so that per-child environment modifications
/// (applied by ancestor modifiers) are captured in each child's `ViewProxy.baseInputs`.
///
/// Additional list-specific fields (`implicitID`, `options`, `_traits`, …) are reserved
/// for ForEach ID tracking, ViewTrait propagation, and container-context injection respectively.
public struct _ViewListInputs {
    /// Shared graph-level inputs (time, environment, transaction, …).
    var base: _GraphInputs

    /// Implicit order index assigned to each view within the list.
    /// Incremented as each child is processed; used by ForEach for stable identity.
    var implicitID: Int

    /// Additional options controlling list traversal behaviour (separate from base.options).
    var options: UInt32

    /// AG node carrying ViewTrait values propagated from child views to their container.
    var _traits: OptionalAttribute<ViewTraitCollection>

    /// The set of trait keys this list is currently tracking.
    var traitKeys: ViewTraitKeys?

    /// The container type metatype (e.g. `List.self`) injected by container views.
    var containerContext: Any.Type?

    /// Scroll content offset for views embedded inside a ScrollView.
    var contentOffset: ViewContentOffset?

    /// Debug-only counter for replaceable view slots in the list.
    /// `MutableBox` allows shared mutation across copies of `_ViewListInputs`
    /// in the same subtree. `nil` when debug instrumentation is not active.
    var debugReplaceableViewCount: MutableBox<Int?>?
}

extension _ViewListInputs {
    /// Create list inputs from single-view inputs.
    /// Only `base` (_GraphInputs) is carried over; layout Attributes are omitted
    /// because they are irrelevant during the list-traversal (wiring) phase.
    init(from viewInputs: _ViewInputs) {
        self.init(
            base: viewInputs.base,
            implicitID: 0,
            options: 0,
            _traits: OptionalAttribute(),
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }
}

extension _ViewInputs {
    /// Create list inputs from these view inputs, carrying only the base context.
    var listInputs: _ViewListInputs { _ViewListInputs(from: self) }
}

/// The AG nodes produced by a view's `_makeView` call.
///
/// - `preferences`: one `AGAttribute` per registered `PreferenceKey` (type-erased)
/// - `_layoutComputer`: `OptionalAttribute` — absent for invisible/preference-only views
public struct _ViewOutputs {
    /// Preference nodes produced by this view (e.g., DisplayList, Accessibility, …).
    var preferences: PreferencesOutputs

    /// The layout-computation node for this view.
    /// `nil` for views that do not participate in layout
    /// (e.g., pure-preference views, invisible spacers).
    var _layoutComputer: OptionalAttribute<LayoutComputer>

    init(preferences: PreferencesOutputs = PreferencesOutputs(),
         layoutComputer: OptionalAttribute<LayoutComputer> = OptionalAttribute()) {
        self.preferences = preferences
        self._layoutComputer = layoutComputer
    }
}

/// The AG nodes produced by a view's `_makeViewList` call.
///
/// - `views`: static or dynamic list discriminated union
/// - `nextImplicitID`: next auto-assigned child index (equals child count for static lists)
/// - `staticCount`: non-nil only for fully static lists (all children known at build time)
public struct _ViewListOutputs {
    /// The resolved list content — static (TupleView) or dynamic (ForEach / mixed).
    var views: ViewListContent

    /// The next implicit child index to assign.
    /// For a static list of N children this equals N.
    /// For any dynamic list this reflects only the statically-known prefix.
    var nextImplicitID: Int

    /// Non-nil iff every child in this list is statically known at `_makeViewList` time.
    /// `nil` whenever `views` is `.dynamicList` or the list contains a dynamic element.
    var staticCount: Int?

    init(views: ViewListContent, nextImplicitID: Int, staticCount: Int?) {
        self.views = views
        self.nextImplicitID = nextImplicitID
        self.staticCount = staticCount
    }
}
