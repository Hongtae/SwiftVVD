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
    // Returns static view count, or nil when the count is dynamic or unknown.
    static func _viewListCount(inputs: _ViewListCountInputs) -> Int?
}

protocol MultiView: View {}

extension View {
    // Default: unknown count. Primitive views and most containers return nil.
    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? { nil }
}

extension View {
    /// Creates a reactive body rule that
    ///   1. reads the live `EnvironmentValues` AG node (registers dependency), and
    ///   2. tracks `@Observable` property accesses via `withObservationTracking`.
    /// Both environment changes and @Observable mutations invalidate the body rule
    /// automatically, causing it to re-evaluate on the next render pass.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _makeDefaultView(view: view, inputs: inputs)
    }

    /// Default implementation: produces a reactive body rule (same as `_makeView`)
    /// then delegates list construction to `Body._makeViewList`.
    ///
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _makeDefaultViewList(view: view, inputs: inputs)
    }
}

func _makeDefaultView<V: View>(view: _GraphValue<V>, inputs: _ViewInputs) -> _ViewOutputs {
    guard let graph = _AGGraph.current else {
        fatalError("\(V.self)._makeView called outside an active _AGGraph context.")
    }

    if V.Body.self is Never.Type {
        fatalError("\(V.self) may not have Body == Never")
    }

    // Build the DynamicProperty buffer before evaluating body. ViewBodyAccessor
    // exists for parity but is not wired into this default body route yet.
    var graphInputs = inputs.base
    let dpFields = DynamicPropertyCache.fields(of: V.self)
    let dpBuffer = _DynamicPropertyBuffer(fields: dpFields, container: view, inputs: &graphInputs)

    // Body rule: reactive to environment changes and @Observable mutations.
    let inbox  = graph.inbox
    let handle = MutableBox<AGAttribute?>(nil)

    let bodyAttr: Attribute<V.Body> = graph.makeRule {
        var viewCopy = view._attribute.value
        dpBuffer.applyContexts(to: &viewCopy)

        var result: V.Body!
        withObservationTracking {
            result = viewCopy.body
        } onChange: { [weak inbox, handle] in
            let transactionBox = UnsafeBox(Transaction.current)
            inbox?.enqueue {
                if let id = handle.value {
                    _AGGraph.current?.markNeedsEvaluation(
                        id,
                        transaction: transactionBox.value,
                        propagateTransaction: !transactionBox.value.isEmpty
                    )
                }
            }
        }
        return result
    }
    handle.value = bodyAttr.identifier

    var childInputs = inputs
    childInputs.base = graphInputs
    return V.Body._makeView(view: _GraphValue(_attribute: bodyAttr), inputs: childInputs)
}

func _makeDefaultViewList<V: View>(view: _GraphValue<V>, inputs: _ViewListInputs) -> _ViewListOutputs {
    if V.Body.self is Never.Type {
        fatalError("\(V.self) may not have Body == Never")
    }

    guard let graph = _AGGraph.current else {
        fatalError("\(V.self)._makeViewList called outside an active _AGGraph context.")
    }

    var graphInputs = inputs.base
    let dpFields = DynamicPropertyCache.fields(of: V.self)
    let dpBuffer = _DynamicPropertyBuffer(fields: dpFields, container: view, inputs: &graphInputs)

    let inbox  = graph.inbox
    let handle = MutableBox<AGAttribute?>(nil)

    let bodyAttr: Attribute<V.Body> = graph.makeRule {
        var viewCopy = view._attribute.value
        dpBuffer.applyContexts(to: &viewCopy)

        var result: V.Body!
        withObservationTracking {
            result = viewCopy.body
        } onChange: { [weak inbox, handle] in
            let transactionBox = UnsafeBox(Transaction.current)
            inbox?.enqueue {
                if let id = handle.value {
                    _AGGraph.current?.markNeedsEvaluation(
                        id,
                        transaction: transactionBox.value,
                        propagateTransaction: !transactionBox.value.isEmpty
                    )
                }
            }
        }
        return result
    }
    handle.value = bodyAttr.identifier

    var childInputs = inputs
    childInputs.base = graphInputs
    return V.Body._makeViewList(view: _GraphValue(_attribute: bodyAttr), inputs: childInputs)
}

extension Never: View {
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        makeDynamicView(
            metadata: makeConditionalMetadata(ViewDescriptor.self),
            view: view,
            inputs: inputs
        )
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        makeDynamicViewList(
            metadata: makeConditionalMetadata(ViewDescriptor.self),
            view: view,
            inputs: inputs
        )
    }
}

extension Optional: PrimitiveView where Self: View {
}

extension Optional: DynamicView where Wrapped: View {
    typealias Metadata = ConditionalMetadata<ViewDescriptor>
    typealias ID = UniqueID

    static var canTransition: Bool { true }

    static func makeConditionalMetadata(
        _ descriptor: ViewDescriptor.Type
    ) -> ConditionalMetadata<ViewDescriptor> {
        ConditionalMetadata(desc: conditionalTypeDescriptor)
    }

    func childInfo(metadata: Metadata) -> (type: Any.Type, id: UniqueID?) {
        metadata.childInfo(source: self as Any)
    }

    func makeChildView(
        metadata: Metadata,
        view: Attribute<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        metadata.childView(source: view, inputs: inputs)
    }

    func makeChildViewList(
        metadata: Metadata,
        view: Attribute<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        metadata.childViewList(source: view, inputs: inputs)
    }
}

extension Optional: ConditionalTypeDescriptorProvider where Wrapped: View {
    static var conditionalTypeDescriptor: ConditionalTypeDescriptor<ViewDescriptor> {
        let wrapped = makeConditionalTypeDescriptor(for: Wrapped.self)
        return ConditionalTypeDescriptor(
            storage: .optional(Self.self, wrapped),
            count: wrapped.count + 1
        )
    }
}

struct IDView<Content, ID>: View, DynamicView where Content: View, ID: Hashable {
    var content: Content
    var id: ID

    init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    typealias Body = Never
    var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }

    typealias Metadata = Void

    static var canTransition: Bool { true }
    static var traitKeysDependOnView: Bool { false }

    static func makeID() -> ID {
        fatalError("IDView requires an explicit identifier")
    }

    func childInfo(metadata: Void) -> (type: Any.Type, id: ID?) {
        (Content.self, id)
    }

    func makeChildView(
        metadata: Void,
        view: Attribute<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        Content._makeView(
            view: _GraphValue(_attribute: view)[\.content],
            inputs: inputs
        )
    }

    func makeChildViewList(
        metadata: Void,
        view: Attribute<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        Content._makeViewList(
            view: _GraphValue(_attribute: view)[\.content],
            inputs: inputs
        )
    }
}

extension View {
    public func id<ID>(_ id: ID) -> some View where ID: Hashable {
        IDView(self, id: id)
    }
}

extension IDView {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        makeDynamicView(metadata: (), view: view, inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        makeDynamicViewList(metadata: (), view: view, inputs: inputs)
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
        guard _AGGraph.current != nil else {
            fatalError("TypedUnaryViewGenerator init called outside an active _AGGraph context.")
        }
        self.view = graphValue._attribute.asWeak().base
        self.viewType = V.self
        self.baseInputs = baseInputs
    }

    init<V: View>(_ graphValue: _GraphValue<V>, inputs: _ViewListInputs) {
        guard _AGGraph.current != nil else {
            fatalError("TypedUnaryViewGenerator init called outside an active _AGGraph context.")
        }
        self.view = graphValue._attribute.asWeak().base
        self.viewType = V.self
        self.baseInputs = inputs.base
        self.traitListAttr = inputs._traits
    }

    func makeView(inputs: _ViewInputs) -> _ViewOutputs? {
        guard let graph = _AGGraph.current else {
            fatalError("TypedUnaryViewGenerator.makeView called outside an active _AGGraph context.")
        }
        guard view.isValid(in: graph) else { return nil }
        let attrID = view.toStrong()
        var inputs = inputs
        var mergedBase = baseInputs
        mergedBase.merge(inputs.base, ignoringPhase: false)
        mergedBase.applyViewPhaseOverrideIfNeeded()
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
        guard let graph = _AGGraph.current else {
            fatalError("TypedUnaryViewGenerator.makeViewList called outside an active _AGGraph context.")
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
    /// Shared graph-level inputs such as time, environment, and transaction.
    /// Base channel: _GraphInputs.customInputs stores GraphInput keys.
    var base: _GraphInputs

    /// View-level input channel. Stores ViewInput keys separately from base.customInputs.
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
    /// Primitive Divider reads this before resolving its axis.
    var stackOrientation: Axis?

    /// Enables the frame-velocity-dispatching animated frame rule for children
    /// that install animated layout frame attributes.
    var supportsVFD: Bool {
        base.options.contains(.supportsVariableFrameDuration)
    }

    var needsGeometry: Bool {
        get { base.options.contains(.viewNeedsGeometry) }
        set {
            if newValue {
                base.options.insert(.viewNeedsGeometry)
            } else {
                base.options.remove(.viewNeedsGeometry)
            }
        }
    }

    var requestsLayoutComputer: Bool {
        get { base.options.contains(.viewRequestsLayoutComputer) }
        set {
            if newValue {
                base.options.insert(.viewRequestsLayoutComputer)
            } else {
                base.options.remove(.viewRequestsLayoutComputer)
            }
        }
    }

    var needsLayout: Bool {
        requestsLayoutComputer || needsGeometry
    }

    // View-channel subscript. Stores in _ViewInputs.customInputs (ViewInput keys).
    // Used by view-specific inputs that should not be stored in the graph channel.
    subscript<T: ViewInput>(_ key: T.Type) -> T.Value {
        get { customInputs.value(forKey: key) }
        set { customInputs.setValue(newValue, forKey: key) }
    }

    /// Copies per-subtree caches (e.g. CachedEnvironment box) before constructing a child
    /// in a retained subgraph, so each child has an independent cache copy.
    /// Mutates self in place and gives the child a distinct cached-environment box.
    mutating func copyCaches() {
        base.cachedEnvironment = MutableBox(base.cachedEnvironment.value)
    }

    /// Creates placeholder outputs that can later be attached to concrete child outputs.
    /// Creates an indirect AG attribute for the layout output and each requested preference slot.
    func makeIndirectOutputs() -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewInputs.makeIndirectOutputs called outside AG context.")
        }
        let layoutComputer = graph.makeIndirectAttribute(defaultValue: LayoutComputer.defaultValue)
        return _ViewOutputs(
            preferences: preferences.makeIndirectOutputs(),
            layoutComputer: OptionalAttribute(layoutComputer)
        )
    }
}

/// Tracks whether debug replacement counting has produced a stable value.
enum DebugReplaceableViewCount {
    case counting(Int)
    case uninitialized
    case indeterminate
}

/// The bundle of AG context Attributes passed from parent to child during `_makeViewList`.
///
/// Unlike `_ViewInputs`, this struct does NOT carry layout Attributes (`position`, `size`,
/// `transform`, etc.). Those are created fresh by the parent Layout when it later calls
/// `_makeView` on each child proxy.  Only the non-layout context (`_GraphInputs`) is
/// threaded through the list-traversal phase so that per-child environment modifications
/// (applied by ancestor modifiers) are captured in each child's `ViewProxy.baseInputs`.
///
/// Additional list-specific fields (`implicitID`, `options`, `_traits`, etc.) are reserved
/// for ForEach ID tracking, ViewTrait propagation, and container-context injection respectively.
public struct _ViewListInputs {
    static let canTransitionOptions: UInt32 = 0x1
    static let transitionOptionsMask: UInt32 = 0x3
    static let sectionListOptions: UInt32 = 0x100

    /// Shared graph-level inputs such as time, environment, and transaction.
    var base: _GraphInputs

    /// Implicit order index assigned to each view within the list.
    /// Incremented as each child is processed. Used by ForEach for stable identity.
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
    var debugReplaceableViewCount: MutableBox<DebugReplaceableViewCount>?

    var needsSectionListOutputs: Bool {
        (options & Self.sectionListOptions) != 0
    }

    mutating func formUnion(viewListOptions: Int) {
        options |= UInt32(truncatingIfNeeded: viewListOptions)
    }
}

extension _ViewListInputs {
    /// Create list inputs from single-view inputs.
    /// Only `base` (_GraphInputs) is carried over. Layout Attributes are omitted
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

// _ViewListCountInputs threads the graph-level input channel through static
// view-list count evaluation. It intentionally omits layout fields because
// count resolution happens before concrete child layout attributes exist.
public struct _ViewListCountInputs {
    var base: _GraphInputs
    var options: UInt32

    init(base: _GraphInputs, options: UInt32 = 0) {
        self.base = base
        self.options = options
    }

    init(_ inputs: _ViewListInputs) {
        self.init(base: inputs.base, options: inputs.options)
    }

    var customInputs: PropertyList {
        get { base.customInputs }
        set { base.customInputs = newValue }
    }

    var baseOptions: _GraphInputs.Options {
        get { base.options }
        set { base.options = newValue }
    }

    subscript<T: GraphInput>(_ key: T.Type) -> T.Value {
        get { base[key] }
        set { base[key] = newValue }
    }

    mutating func append<T: GraphInput, E>(_ element: E, to key: T.Type) where T.Value == Stack<E> {
        base.append(element, forKey: key)
    }

    mutating func popLast<T: GraphInput, E>(_ key: T.Type) -> E? where T.Value == Stack<E> {
        base.popLast(key)
    }
}

extension _ViewListInputs {
    var countInputs: _ViewListCountInputs {
        _ViewListCountInputs(self)
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
    /// Preference nodes produced by this view, such as DisplayList or Accessibility.
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
    /// Used after a delayed or erased child has produced real outputs.
    func attachIndirectOutputs(to placeholders: _ViewOutputs) {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewOutputs.attachIndirectOutputs called outside AG context.")
        }
        preferences.attachIndirectOutputs(to: placeholders.preferences)
        if let placeholder = placeholders._layoutComputer.attribute {
            graph.setIndirectTarget(placeholder, to: _layoutComputer.attribute)
        }
    }

    /// Registers a permanent AG dependency on `attr` for all placeholder output slots.
    /// Keeps delayed placeholder outputs invalidated by the child source attribute.
    func setIndirectDependency(_ attr: AGAttribute?) {
        guard let dep = attr else { return }
        guard let graph = _AGGraph.current else {
            fatalError("_ViewOutputs.setIndirectDependency called outside AG context.")
        }
        if let placeholder = _layoutComputer.attribute {
            graph.setIndirectDependency(placeholder.identifier, dependsOn: dep)
        }
        preferences.setIndirectDependency(dep)
    }

    /// Detaches all placeholder output slots and restores their default values.
    func detachIndirectOutputs() {
        guard let graph = _AGGraph.current else {
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
    typealias Views = ViewListContent

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
    func makeAttribute(inputs: _ViewListInputs) -> Attribute<any ViewList> {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewListOutputs.makeAttribute(inputs:) called outside an active graph.")
        }
        switch views {
        case .dynamicList(let attribute, let modifier):
            guard let modifier else { return attribute }
            return graph.makeRule {
                var list = attribute.value
                modifier.apply(to: &list)
                return list
            }
        case .staticList(let elements):
            let implicitID = inputs.implicitID
            let traitKeys = inputs.traitKeys
            let traits = inputs._traits
            let canTransition =
                inputs.options & _ViewListInputs.transitionOptionsMask ==
                _ViewListInputs.canTransitionOptions
            return graph.makeRule {
                var values = traits.attribute?.value ?? ViewTraitCollection()
                if canTransition {
                    values[CanTransitionTraitKey.self] = true
                }
                return BaseViewList(
                    elements: elements,
                    implicitID: implicitID,
                    traitKeys: traitKeys,
                    traits: values
                ) as any ViewList
            }
        }
    }

    static func unaryViewList<V: View>(view: _GraphValue<V>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let generator = TypedUnaryViewGenerator(view, inputs: inputs)
        return _ViewListOutputs(
            views: .staticList(.unaryElements(UnaryElements(generator: generator))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }

    /// Closure-backed unary list fallback used until the generic body-unary generator
    /// wiring path is implemented.
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
