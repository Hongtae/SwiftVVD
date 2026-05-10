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
    // Returns a static view count when known, otherwise nil.
    static func _viewListCount(inputs: _ViewListCountInputs) -> Int?
}

extension View {
    // Default: unknown count. Primitive views and most containers return nil.
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { nil }
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
        // The current body path uses withObservationTracking for @Observable support.
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let dpBuffer = _DynamicPropertyBuffer(fields: dpFields, container: view, inputs: &graphInputs)

        // Body rule: reactive to environment changes and @Observable mutations.
        let inbox  = graph.inbox
        let handle = MutableBox<AGAttribute?>(nil)

        let bodyAttr: Attribute<Body> = graph.makeRule {
            var viewCopy = view._attribute.value
            dpBuffer.applyContexts(to: &viewCopy)

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

        var childInputs = inputs
        childInputs.base = graphInputs
        return Body._makeView(view: _GraphValue(_attribute: bodyAttr), inputs: childInputs)
    }

    /// Default implementation: produces a reactive body rule (same as `_makeView`)
    /// then delegates list construction to `Body._makeViewList`.
    ///
    /// For Body == Never: returns a single-proxy static list so the parent layout
    /// can call `_makeView` via the proxy.
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        if self is any _PrimitiveView.Type {
            return _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
        }
        if Body.self is Never.Type {
            fatalError("\(Self.self) may not have Body == Never")
        }

        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }

        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let dpBuffer = _DynamicPropertyBuffer(fields: dpFields, container: view, inputs: &graphInputs)

        let inbox  = graph.inbox
        let handle = MutableBox<AGAttribute?>(nil)

        let bodyAttr: Attribute<Body> = graph.makeRule {
            var viewCopy = view._attribute.value
            dpBuffer.applyContexts(to: &viewCopy)

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

        var childInputs = inputs
        childInputs.base = graphInputs
        return Body._makeViewList(view: _GraphValue(_attribute: bodyAttr), inputs: childInputs)
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

// File-scope state class. It cannot be nested inside a generic function in Swift.
private final class _OptionalViewState {
    var hasValue: Bool? = nil
    var subgraph: AGSubgraph? = nil
    var lcAttr: Attribute<LayoutComputer>? = nil
    var activeOutputs: PreferencesOutputs? = nil
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never

    /// Dynamic-subgraph implementation for optional views.
    ///
    /// When `.none` becomes `.some`, creates a AGSubgraph and wires `Wrapped._makeView` into it.
    /// When `.some` becomes `.none`, invalidates the subgraph; master rule returns `.fixed(.zero)`.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let state = _OptionalViewState()
        state.subgraph = AGSubgraph() // Created while parent AGSubgraph is active

        func updateActiveBranchIfNeeded() {
            guard let graph = AttributeGraph.current else {
                fatalError("Optional<\(Wrapped.self)> branch update evaluated outside an active AttributeGraph context.")
            }
            let nowHas = view._attribute.value != nil
            guard state.hasValue != nowHas else { return }
            state.subgraph?.invalidate()
            state.hasValue = nowHas

            if nowHas {
                // Force-unwrap is safe: node lives only while hasValue == true.
                let wrappedAttr: Attribute<Wrapped> = AGSubgraph.$current.withValue(state.subgraph) {
                    graph.makeRule { view._attribute.value! }
                }
                let outputs = AGSubgraph.$current.withValue(state.subgraph) {
                    Wrapped._makeView(view: _GraphValue(_attribute: wrappedAttr), inputs: inputs)
                }
                state.lcAttr = outputs._layoutComputer.attribute
                state.activeOutputs = outputs.preferences
            } else {
                state.lcAttr = nil
                state.activeOutputs = nil
            }
        }

        let masterLC: Attribute<LayoutComputer> = graph.makeRule {
            guard AttributeGraph.current != nil else {
                fatalError("Optional<\(Wrapped.self)> rule evaluated outside an active AttributeGraph context.")
            }

            updateActiveBranchIfNeeded()

            return state.lcAttr?.value ?? LayoutComputer.fixed(.zero)
        }

        // Optional child views keep ResourceList/DisplayList and other requested
        // preferences alive when they switch between nil and some.
        // FIXME: Revisit this relay once Optional-specific preference handling is complete.
        var outPrefs = PreferencesOutputs()
        for key in inputs.preferences.keys.keys {
            func addRelay<K: PreferenceKey>(_ k: K.Type) {
                let relayAttr: Attribute<K.Value> = graph.makeRule {
                    updateActiveBranchIfNeeded()
                    guard let prefs = state.activeOutputs else { return K.defaultValue }
                    var combined = K.defaultValue
                    for kv in prefs.preferences {
                        guard ObjectIdentifier(kv.key) == ObjectIdentifier(k) else { continue }
                        let val = Attribute<K.Value>(kv.value).value
                        K.reduce(value: &combined) { val }
                    }
                    return combined
                }
                outPrefs.append(k, node: relayAttr.identifier)
            }
            addRelay(key)
        }

        return _ViewOutputs(preferences: outPrefs,
                            layoutComputer: OptionalAttribute(masterLC))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
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

struct TypedUnaryViewGenerator {
    var view: AGWeakAttribute
    var viewType: any View.Type
    var baseInputs: _GraphInputs
    /// AG-backed trait collection for this subview.
    /// `nil` (empty OptionalAttribute) when no `_TraitWritingModifier` was applied.
    /// Set by `_TraitWritingModifier._makeViewList` to a derived `Attribute<ViewTraitCollection>`.
    var traitListAttr: OptionalAttribute<ViewTraitCollection> = OptionalAttribute()
    /// Per-child reactive environment override.
    /// `nil` = use baseInputs.cachedEnvironment as-is (common case).
    /// When set, makeView replaces cachedEnvironment with this attribute so the child
    /// re-evaluates reactively when the attribute changes (e.g. preferredColorScheme).
    /// Set by _PreferenceWritingModifier<PreferredColorSchemeKey>._makeViewList.
    var envAttr: OptionalAttribute<EnvironmentValues> = OptionalAttribute()
}

extension TypedUnaryViewGenerator {
    init<V: View>(_ graphValue: _GraphValue<V>, baseInputs: _GraphInputs) {
        guard AttributeGraph.current != nil else {
            fatalError("TypedUnaryViewGenerator init called outside an active AttributeGraph context.")
        }
        self.view = graphValue._attribute.asWeak().raw
        self.viewType = V.self
        self.baseInputs = baseInputs
    }

    init<V: View>(_ graphValue: _GraphValue<V>, inputs: _ViewListInputs) {
        guard AttributeGraph.current != nil else {
            fatalError("TypedUnaryViewGenerator init called outside an active AttributeGraph context.")
        }
        self.view = graphValue._attribute.asWeak().raw
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
        var inputs = inputs
        var mergedBase = baseInputs
        mergedBase.merge(inputs.base, ignoringPhase: false)
        inputs.base = mergedBase
        if let env = envAttr.attribute {
            // Replace cachedEnvironment with per-child reactive env attribute.
            // New MutableBox so child's env changes are isolated from siblings.
            var newCached = inputs.base.cachedEnvironment.value
            newCached.environment = env
            inputs.base.cachedEnvironment = MutableBox(newCached)
        }
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


/// The bundle of AG context Attributes passed from parent to child during `_makeView`.
///
/// All geometry fields (`transform`, `position`, `size`, etc.) are Attribute references,
/// not concrete values: the parent creates the nodes at `_makeView` time (wiring phase)
/// and fills in their values later during the layout pass.
public struct _ViewInputs {
    /// Shared graph-level inputs (time, environment, transaction, etc.).
    /// Base channel: _GraphInputs.customInputs stores GraphInput keys.
    var base: _GraphInputs

    /// View-level input channel. Stores ViewInput keys.
    /// Separate from base.customInputs.
    var customInputs: PropertyList

    /// Which preference keys this subtree should collect.
    var preferences: PreferencesInputs

    /// The cumulative coordinate-space transform for this child.
    var transform: Attribute<ViewTransform>

    /// The position assigned to this child by its parent (in window-global coords).
    var position: Attribute<CGPoint>

    /// The position of the parent container (in window-global coords, used for coordinate conversion).
    var containerPosition: Attribute<CGPoint>

    /// The proposed size this parent is offering to the child.
    var size: Attribute<ViewSize>

    /// Safe-area insets from the nearest ancestor that defines a safe area.
    /// `nil` when no safe-area context exists above this child.
    var safeAreaInsets: OptionalAttribute<SafeAreaInsets>

    /// The actual size of the parent container.
    /// `nil` when the parent has not yet been sized (e.g., during bootstrapping).
    var containerSize: OptionalAttribute<ViewSize>

    /// The nearest stack layout orientation seen by primitive children.
    /// Used by primitives such as Divider to resolve their axis.
    var stackOrientation: Axis?

    // View-channel subscript for _ViewInputs.customInputs (ViewInput keys).
    subscript<T: ViewInput>(_ key: T.Type) -> T.Value {
        get { customInputs.value(forKey: key) }
        set { customInputs.setValue(newValue, forKey: key) }
    }

    /// Copies per-subtree caches (e.g. CachedEnvironment box) before constructing a child
    /// in a retained subgraph, so each child has an independent cache copy.
    mutating func copyCaches() {
        base.cachedEnvironment = MutableBox(base.cachedEnvironment.value)
    }

    /// Creates placeholder outputs that can later be attached to concrete child outputs.
    func makeIndirectOutputs() -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_ViewInputs.makeIndirectOutputs called outside AG context.")
        }
        let layoutComputer = graph.makeIndirectAttribute(defaultValue: LayoutComputer.defaultValue)
        return _ViewOutputs(
            preferences: preferences.makeIndirectOutputs(),
            layoutComputer: OptionalAttribute(layoutComputer)
        )
    }
}

/// The bundle of AG context Attributes passed from parent to child during `_makeViewList`.
///
/// Unlike `_ViewInputs`, this struct does NOT carry layout Attributes (`position`, `size`,
/// `transform`, etc.).  Those are created fresh by the parent Layout when it later calls
/// `_makeView` on each child proxy.  Only the non-layout context (`_GraphInputs`) is
/// threaded through the list-traversal phase so that per-child environment modifications
/// (applied by ancestor modifiers) are captured in each child's `ViewProxy.baseInputs`.
///
/// Additional list-specific fields (`implicitID`, `options`, `_traits`, etc.) are reserved
/// for ForEach ID tracking, ViewTrait propagation, and container-context injection respectively.
public struct _ViewListInputs {
    /// Shared graph-level inputs (time, environment, transaction, etc.).
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
/// - `_layoutComputer`: `OptionalAttribute`, absent for invisible/preference-only views
public struct _ViewOutputs {
    /// Preference nodes produced by this view (e.g., DisplayList, Accessibility, etc.).
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

    /// Points each placeholder output slot at the corresponding concrete child output.
    func attachIndirectOutputs(to placeholders: _ViewOutputs) {
        guard let graph = AttributeGraph.current else {
            fatalError("_ViewOutputs.attachIndirectOutputs called outside AG context.")
        }
        preferences.attachIndirectOutputs(to: placeholders.preferences)
        if let placeholder = placeholders._layoutComputer.attribute {
            graph.setIndirectTarget(placeholder, to: _layoutComputer.attribute)
        }
    }

    /// Registers a permanent AG dependency on `attr` for all placeholder output slots.
    func setIndirectDependency(_ attr: AGAttribute?) {
        guard let dep = attr else { return }
        guard let graph = AttributeGraph.current else {
            fatalError("_ViewOutputs.setIndirectDependency called outside AG context.")
        }
        if let placeholder = _layoutComputer.attribute {
            graph.setIndirectDependency(placeholder.identifier, dependsOn: dep)
        }
        preferences.setIndirectDependency(dep)
    }

    /// Detaches all placeholder output slots, pointing them to nil/default values.
    func detachIndirectOutputs() {
        guard let graph = AttributeGraph.current else {
            fatalError("_ViewOutputs.detachIndirectOutputs called outside AG context.")
        }
        if let placeholder = _layoutComputer.attribute {
            graph.setIndirectTarget(placeholder.identifier, to: nil)
        }
        preferences.detachIndirectOutputs()
    }
}

/// The AG nodes produced by a view's `_makeViewList` call.
///
/// - `views`: static or dynamic list discriminated union
/// - `nextImplicitID`: next auto-assigned child index (equals child count for static lists)
/// - `staticCount`: non-nil only for fully static lists (all children known at build time)
public struct _ViewListOutputs {
    /// The resolved list content: static (TupleView) or dynamic (ForEach / mixed).
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

extension _ViewListOutputs {
    static func unaryViewList<V: View>(view: _GraphValue<V>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let generator = TypedUnaryViewGenerator(view, inputs: inputs)
        return _ViewListOutputs(
            views: .staticList(.unaryElements(UnaryElements(generator: generator))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }

    /// FIXME: Route through BodyUnaryViewGenerator when generic layout wiring is ready.
    static func unaryViewList(
        viewType: Any.Type,
        inputs: _ViewListInputs,
        body: @escaping (_ViewInputs) -> _ViewOutputs
    ) -> _ViewListOutputs {
        let _ = BodyUnaryViewGenerator(body: body, viewType: viewType)
        return _ViewListOutputs(
            views: .staticList(.unaryElements(UnaryElements(body: body, baseInputs: inputs.base))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}
