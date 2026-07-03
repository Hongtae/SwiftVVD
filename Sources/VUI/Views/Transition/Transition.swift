//
//  File: Transition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Transition {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content, phase: TransitionPhase) -> Self.Body
    static var properties: TransitionProperties { get }
    typealias Content = PlaceholderContentView<Self>
    func _makeContentTransition(transition: inout _Transition_ContentTransition)
}

public struct PlaceholderContentView<Value>: View {
    public var body: Never { neverBody() }

    // Transition bodies are built around a placeholder. The real content builder
    // is pushed through inputs so a transition can wrap either a unary view or a
    // view-list subtree without owning the original source view.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        var inputs = inputs
        guard let elem = inputs.popLast(BodyInput<Self>.self) else {
            return _ViewOutputs()
        }
        if elem.isViewList {
            guard let fn = elem.makeViewListFn else {
                fatalError("PlaceholderContentView<\(Value.self)>._makeView: missing view-list body.")
            }
            guard let graph = _AGGraph.current else {
                fatalError("PlaceholderContentView<\(Value.self)>._makeView called outside AG context.")
            }
            let rootAttr: Attribute<_VStackLayout> = graph.makeInput(value: _VStackLayout())
            return _VStackLayout._makeLayoutView(root: _GraphValue(_attribute: rootAttr), inputs: inputs) { _, childInputs in
                fn(_Graph(), childInputs.listInputs)
            }
        } else {
            guard let fn = elem.makeViewFn else {
                fatalError("PlaceholderContentView<\(Value.self)>._makeView: missing view body.")
            }
            return fn(_Graph(), inputs)
        }
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        var inputs = inputs
        guard let elem = inputs.base.popLast(BodyInput<Self>.self) else {
            return _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
        }
        if elem.isViewList {
            guard let fn = elem.makeViewListFn else {
                fatalError("PlaceholderContentView<\(Value.self)>._makeViewList: missing view-list body.")
            }
            return fn(_Graph(), inputs)
        } else {
            guard let fn = elem.makeViewFn else {
                fatalError("PlaceholderContentView<\(Value.self)>._makeViewList: missing view body.")
            }
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

    public static func _viewListCount(inputs: _ViewListCountInputs, body: (_ViewListCountInputs) -> Int?) -> Int? {
        body(inputs)
    }

    public typealias Body = Never
}

extension PlaceholderContentView: _PrimitiveView {
}

// Query payload used by Transition implementations to expose renderer content-transition effects.
public struct _Transition_ContentTransition {
    // Operation requested by the content-transition lowering path.
    enum Operation: Equatable {
        case hasContentTransition
        case effects(ContentTransition.Style, CGSize)
    }

    // Result written back by a Transition implementation.
    enum Result: Equatable {
        case none
        case bool(Bool)
        case effects([ContentTransition.Effect])
    }

    var operation: Operation
    var result: Result

    init(operation: Operation = .hasContentTransition, result: Result = .none) {
        self.operation = operation
        self.result = result
    }
}

public enum TransitionPhase: Hashable, Sendable {
    case willAppear
    case identity
    case didDisappear
    public var isIdentity: Bool {
        self == .identity
    }
}

extension TransitionPhase {
    public var value: Double {
        switch self {
        case .willAppear: return -1
        case .identity: return 0
        case .didDisappear: return 1
        }
    }
}

public struct TransitionProperties: Sendable {
    public var hasMotion: Bool
    public init(hasMotion: Bool = true) {
        self.hasMotion = hasMotion
    }
}

extension Transition {
    public static var properties: TransitionProperties {
        TransitionProperties()
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
    }

    var hasContentTransition: Bool {
        var transition = _Transition_ContentTransition(
            operation: .hasContentTransition,
            result: .bool(false)
        )
        _makeContentTransition(transition: &transition)
        if case let .bool(value) = transition.result {
            return value
        }
        return false
    }

    func contentTransitionEffects(
        style: ContentTransition.Style,
        size: CGSize
    ) -> [ContentTransition.Effect] {
        var transition = _Transition_ContentTransition(
            operation: .effects(style, size),
            result: .effects([])
        )
        _makeContentTransition(transition: &transition)
        if case let .effects(effects) = transition.result {
            return effects
        }
        return []
    }

    public func apply<V>(content: V, phase: TransitionPhase) -> some View where V: View {
        content.modifier(ApplyTransitionModifier(transition: self, phase: phase))
    }
}

struct ApplyTransitionModifier<T: Transition>: ViewModifier {
    var transition: T
    var phase: TransitionPhase

    func body(content: Content) -> T.Body {
        transition.body(content: PlaceholderContentView<T>(), phase: phase)
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (bodyGV, _) = makeBody(modifier: modifier, inputs: &graphInputs, fields: dpFields)

        var inputs = inputs
        inputs.base = graphInputs
        // Store the original body builder under the placeholder key. When the
        // transition body evaluates PlaceholderContentView, it relays back here.
        inputs.base.append(BodyInputElement(makeView: body), forKey: BodyInput<PlaceholderContentView<T>>.self)
        return T.Body._makeView(view: bodyGV, inputs: inputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }
        var graphInputs = inputs.base
        let dpFields = DynamicPropertyCache.fields(of: Self.self)
        let (bodyGV, _) = makeBody(modifier: modifier, inputs: &graphInputs, fields: dpFields)

        var inputs = inputs
        inputs.base = graphInputs
        inputs.base.append(BodyInputElement(makeViewList: body), forKey: BodyInput<PlaceholderContentView<T>>.self)
        return T.Body._makeViewList(view: bodyGV, inputs: inputs)
    }
}

struct TransitionBodyAccessor<T: Transition>: BodyAccessor {
    typealias Container = ApplyTransitionModifier<T>
    typealias Body = T.Body

    let containerAttr: Attribute<ApplyTransitionModifier<T>>

    mutating func updateBody(of modifier: ApplyTransitionModifier<T>, changed: Bool) -> T.Body {
        modifier.body(content: _ViewModifier_Content<ApplyTransitionModifier<T>>())
    }

    static func makeBody(
        container: _GraphValue<ApplyTransitionModifier<T>>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<T.Body>, Optional<_DynamicPropertyBuffer>) {
        guard let graph = _AGGraph.current else {
            fatalError("TransitionBodyAccessor.makeBody called outside _AGGraph context")
        }
        let buffer = _DynamicPropertyBuffer(fields: fields, container: container, inputs: &inputs)
        let accessor = TransitionBodyAccessor(containerAttr: container._attribute)
        if buffer.isEmpty {
            let attr = graph.makeStatefulRule(StaticBody<TransitionBodyAccessor<T>, MainThreadFlags>(accessor: accessor))
            return (_GraphValue(_attribute: attr), nil)
        } else {
            let attr = graph.makeStatefulRule(DynamicBody<TransitionBodyAccessor<T>, MainThreadFlags>(accessor: accessor, buffer: buffer))
            return (_GraphValue(_attribute: attr), buffer)
        }
    }
}

extension ApplyTransitionModifier {
    static func makeBody(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs,
        fields: DynamicPropertyCache.Fields
    ) -> (_GraphValue<T.Body>, Optional<_DynamicPropertyBuffer>) {
        TransitionBodyAccessor<T>.makeBody(container: modifier, inputs: &inputs, fields: fields)
    }
}

public struct IdentityTransition: Transition {
    public init() {}

    public func body(content: Content, phase: TransitionPhase) -> Content {
        content
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([])
        }
    }

    public static let properties = TransitionProperties(hasMotion: false)
}

public struct OpacityTransition: Transition {
    public init() {}

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 1 : 0)
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([
                ContentTransition.Effect(
                    type: .opacity,
                    events: 3
                )
            ])
        }
    }

    public static let properties = TransitionProperties(hasMotion: false)
}

public struct MoveTransition: Transition {
    public var edge: Edge

    public init(edge: Edge) {
        self.edge = edge
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(MoveLayout(edge: phase.isIdentity ? nil : edge))
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case let .effects(_, size):
            transition.result = .effects([
                ContentTransition.Effect(
                    type: .translation(Self.translationOffset(edge: edge, size: size))
                )
            ])
        }
    }

    static func translationOffset(edge: Edge, size: CGSize) -> CGSize {
        switch edge {
        case .top:
            return CGSize(width: 0, height: -size.height)
        case .leading:
            return CGSize(width: -size.width, height: 0)
        case .bottom:
            return CGSize(width: 0, height: size.height)
        case .trailing:
            return CGSize(width: size.width, height: 0)
        }
    }

    struct MoveLayout: ViewModifier, Animatable {
        var edge: Edge?

        init(edge: Edge?) {
            self.edge = edge
        }

        typealias AnimatableData = EmptyAnimatableData
        typealias Body = Never

        static func _makeView(
            modifier: _GraphValue<Self>,
            inputs: _ViewInputs,
            body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
        ) -> _ViewOutputs {
            guard let graph = _AGGraph.current else {
                fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
            }

            let progressSource: Attribute<MoveLayoutProgress> = graph.makeRule {
                MoveLayoutProgress(value: modifier._attribute.value.edge == nil ? 0 : 1)
            }
            var progress = _GraphValue<MoveLayoutProgress>(_attribute: progressSource)
            MoveLayoutProgress._makeAnimatable(value: &progress, inputs: inputs.base)

            let activeEdge: Attribute<Edge?> = graph.makeStatefulRule(
                MoveLayoutActiveEdge(modifier: modifier._attribute)
            )
            let sizeAttr = inputs.size
            let positionAttr = inputs.position
            let parentTransformAttr = inputs.transform
            let progressAttr = progress._attribute

            let effectAttr: Attribute<ProjectionTransform> = graph.makeRule {
                Self.effectValue(
                    edge: activeEdge.value,
                    progress: progressAttr.value.value,
                    size: sizeAttr.value.value
                )
            }
            let transformAttr: Attribute<ViewTransform> = graph.makeRule {
                var transform = parentTransformAttr.value
                transform.appendProjectionTransform(effectAttr.value, inverse: false)
                return transform
            }

            var modifiedInputs = inputs
            modifiedInputs.transform = transformAttr
            var outputs = body(_Graph(), modifiedInputs)
            _GeometryEffectSupport.applyProjectionEffect(
                to: &outputs.preferences,
                effect: effectAttr,
                position: positionAttr,
                graph: graph
            )
            return outputs
        }

        static func _makeViewList(
            modifier: _GraphValue<Self>,
            inputs: _ViewListInputs,
            body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
        ) -> _ViewListOutputs {
            guard _AGGraph.current != nil else {
                fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
            }
            var outputs = body(_Graph(), inputs)
            outputs.multiModifier(modifier, inputs: inputs)
            return outputs
        }

        func effectValue(size: CGSize) -> ProjectionTransform {
            Self.effectValue(
                edge: edge,
                progress: edge == nil ? 0 : 1,
                size: size
            )
        }

        private static func effectValue(edge: Edge?, progress: CGFloat, size: CGSize) -> ProjectionTransform {
            guard progress != 0, let edge else {
                return ProjectionTransform()
            }
            let offset: CGSize
            switch edge {
            case .leading:
                offset = CGSize(width: -size.width * progress, height: 0)
            case .trailing:
                offset = CGSize(width: size.width * progress, height: 0)
            case .top:
                offset = CGSize(width: 0, height: -size.height * progress)
            case .bottom:
                offset = CGSize(width: 0, height: size.height * progress)
            }
            return ProjectionTransform(
                CGAffineTransform(translationX: offset.width, y: offset.height)
            )
        }
    }

    private struct MoveLayoutActiveEdge: StatefulRule {
        typealias Value = Edge?
        var modifier: Attribute<MoveLayout>
        private var lastEdge: Edge?

        init(modifier: Attribute<MoveLayout>) {
            self.modifier = modifier
            self.lastEdge = nil
        }

        mutating func updateValue() {
            if let edge = modifier.value.edge {
                lastEdge = edge
            }
            _AGGraph.setStatefulOutput(modifier.value.edge ?? lastEdge)
        }
    }

    private struct MoveLayoutProgress: Animatable, Equatable {
        var value: CGFloat

        var animatableData: CGFloat {
            get { value }
            set { value = newValue }
        }
    }
}

public struct PushTransition: Transition {
    public var edge: Edge

    public init(edge: Edge) {
        self.edge = edge
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        let activeEdge = phase.isIdentity ? edge : edge(for: phase)
        return content
            .modifier(MoveTransition.MoveLayout(
                edge: phase.isIdentity ? nil : activeEdge
            ))
            .modifier(OpacityRendererEffect(opacity: phase.isIdentity ? 1 : 0))
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case let .effects(style, size):
            let offset = MoveTransition.translationOffset(edge: edge, size: size)
            let insertionOffset: CGSize
            let opacityBegin: Float
            let opacityDuration: Float
            if style == .default {
                insertionOffset = offset
                opacityBegin = 0
                opacityDuration = 1
            } else {
                insertionOffset = CGSize(
                    width: offset.width * 0.4,
                    height: offset.height * 0.4
                )
                opacityBegin = 0.4
                opacityDuration = 0.6
            }
            let removalOffset = CGSize(width: -offset.width, height: -offset.height)
            transition.result = .effects([
                ContentTransition.Effect(
                    type: .translation(insertionOffset),
                    events: 1
                ),
                ContentTransition.Effect(
                    type: .translation(removalOffset),
                    events: 2
                ),
                ContentTransition.Effect(
                    type: .opacity,
                    begin: opacityBegin,
                    duration: opacityDuration,
                    events: 3
                ),
            ])
        }
    }

    private func edge(for phase: TransitionPhase) -> Edge {
        switch phase {
        case .willAppear:
            return edge
        case .identity:
            return edge
        case .didDisappear:
            return edge.opposite
        }
    }
}

// Blur, opacity, and scale transition used for content replacement.
public struct BlurReplaceTransition: Transition {
    // Direction preset controlling the removal scale behavior.
    public struct Configuration: Equatable, Sendable {
        enum Storage: UInt8, Equatable, Sendable {
            case downUp = 0
            case upUp = 1
        }

        var storage: Storage

        init(storage: Storage) {
            self.storage = storage
        }

        public static let downUp = Configuration(storage: .downUp)
        public static let upUp = Configuration(storage: .upUp)
    }

    public var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .modifier(OpacityRendererEffect(opacity: phase.isIdentity ? 1 : 0))
            .blur(radius: phase.isIdentity ? 0 : 7)
            .scaleEffect(scale(for: phase), anchor: .center)
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            let begin = Float(bitPattern: 0x3EA8F5C3)
            let duration = Float(bitPattern: 0x3F2B851E)
            let scale = CGFloat(Float(bitPattern: 0x3F666666))
            let flags: UInt32 = configuration == .upUp ? 1 : 0
            transition.result = .effects([
                ContentTransition.Effect(
                    type: .opacity,
                    begin: begin,
                    duration: duration,
                    events: 3
                ),
                ContentTransition.Effect(
                    type: .blur(radius: 7),
                    begin: begin,
                    duration: duration,
                    events: 3
                ),
                ContentTransition.Effect(
                    type: .scale(scale),
                    begin: begin,
                    duration: duration,
                    events: 3,
                    flags: flags
                ),
            ])
        }
    }

    private func scale(for phase: TransitionPhase) -> CGFloat {
        switch phase {
        case .identity:
            return 1
        case .willAppear:
            return 0.9
        case .didDisappear:
            return configuration == .upUp ? 1.1 : 0.9
        }
    }
}

public struct SlideTransition: Transition {
    public init() {}

    public func body(content: Content, phase: TransitionPhase) -> some View {
        let edge = edge(for: phase)
        return content.modifier(MoveTransition.MoveLayout(
            edge: phase.isIdentity ? nil : edge
        ))
    }

    private func edge(for phase: TransitionPhase) -> Edge {
        switch phase {
        case .willAppear:
            return .leading
        case .identity:
            return .leading
        case .didDisappear:
            return .trailing
        }
    }
}

public struct ScaleTransition: Transition {
    public var scale: Double
    public var anchor: UnitPoint

    public init(_ scale: Double, anchor: UnitPoint = .center) {
        self.scale = scale
        self.anchor = anchor
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.scaleEffect(phase.isIdentity ? 1 : CGFloat(scale), anchor: anchor)
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([
                ContentTransition.Effect(type: .scale(CGFloat(scale)))
            ])
        }
    }
}

public struct AsymmetricTransition<Insertion, Removal>: Transition
    where Insertion: Transition, Removal: Transition {
    public var insertion: Insertion
    public var removal: Removal

    public init(insertion: Insertion, removal: Removal) {
        self.insertion = insertion
        self.removal = removal
    }

    @ViewBuilder
    public func body(content: Content, phase: TransitionPhase) -> some View {
        switch phase {
        case .willAppear:
            insertion.apply(content: content, phase: phase)
        case .identity:
            content
        case .didDisappear:
            removal.apply(content: content, phase: phase)
        }
    }

    public static var properties: TransitionProperties {
        TransitionProperties(hasMotion: Insertion.properties.hasMotion || Removal.properties.hasMotion)
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(insertion.hasContentTransition || removal.hasContentTransition)
        case let .effects(style, size):
            transition.result = .effects(
                insertion.contentTransitionEffects(style: style, size: size) +
                removal.contentTransitionEffects(style: style, size: size)
            )
        }
    }
}

protocol _TransitionTransactionFiltering {
    // A transition can alter the transaction used when its phase changes. The
    // resolver variant exposes child-specific filtered transactions for
    // retained-removal decisions before the phase setter runs.
    func _filter(transaction: inout Transaction, phase: TransitionPhase)
    func _filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction]
}

private protocol _TransitionRemovalRetentionFiltering {
    func _retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction]
}

private func _applyTransitionTransactionFilters<T: Transition>(
    _ transition: T,
    to transaction: inout Transaction,
    phase: TransitionPhase
) {
    if let filtering = transition as? any _TransitionTransactionFiltering {
        filtering._filter(transaction: &transaction, phase: phase)
    }
}

private func _transitionFilteredTransactions<T: Transition>(
    _ transition: T,
    from transaction: Transaction,
    phase: TransitionPhase
) -> [Transaction] {
    if let filtering = transition as? any _TransitionTransactionFiltering {
        return filtering._filteredTransactions(from: transaction, phase: phase)
    }
    return [transaction]
}

private func _hasPositiveAnimation(_ transaction: Transaction) -> Bool {
    guard let animation = transaction.effectiveAnimation else { return false }
    return animation.box.duration > 0
}

private func _transitionRetainedRemovalTransactions<T: Transition>(
    _ transition: T,
    from transaction: Transaction,
    phase: TransitionPhase,
    original: Transaction
) -> [Transaction] {
    if let filtering = transition as? any _TransitionRemovalRetentionFiltering {
        return filtering._retainedRemovalTransactions(
            from: transaction,
            phase: phase,
            original: original
        )
    }
    if transition is OffsetTransition,
       !_hasPositiveAnimation(original),
       _hasPositiveAnimation(transaction) {
        return []
    }
    return [transaction]
}

extension AsymmetricTransition: _TransitionTransactionFiltering {
    func _filter(transaction: inout Transaction, phase: TransitionPhase) {
        switch phase {
        case .willAppear:
            _applyTransitionTransactionFilters(insertion, to: &transaction, phase: phase)
        case .identity:
            break
        case .didDisappear:
            _applyTransitionTransactionFilters(removal, to: &transaction, phase: phase)
        }
    }

    func _filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        switch phase {
        case .willAppear:
            return _transitionFilteredTransactions(insertion, from: transaction, phase: phase)
        case .identity:
            return [transaction]
        case .didDisappear:
            return _transitionFilteredTransactions(removal, from: transaction, phase: phase)
        }
    }
}

extension AsymmetricTransition: _TransitionRemovalRetentionFiltering {
    func _retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        switch phase {
        case .willAppear:
            return _transitionRetainedRemovalTransactions(
                insertion,
                from: transaction,
                phase: phase,
                original: original
            )
        case .identity:
            return [transaction]
        case .didDisappear:
            return _transitionRetainedRemovalTransactions(
                removal,
                from: transaction,
                phase: phase,
                original: original
            )
        }
    }
}

struct CombiningTransition<First, Second>: Transition where First: Transition, Second: Transition {
    var transition1: First
    var transition2: Second

    func body(content: Content, phase: TransitionPhase) -> some View {
        transition2.apply(content: transition1.apply(content: content, phase: phase), phase: phase)
    }

    static var properties: TransitionProperties {
        TransitionProperties(hasMotion: First.properties.hasMotion || Second.properties.hasMotion)
    }

    func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(transition1.hasContentTransition || transition2.hasContentTransition)
        case let .effects(style, size):
            transition.result = .effects(
                transition1.contentTransitionEffects(style: style, size: size) +
                transition2.contentTransitionEffects(style: style, size: size)
            )
        }
    }
}

extension CombiningTransition: _TransitionTransactionFiltering {
    func _filter(transaction: inout Transaction, phase: TransitionPhase) {
        _applyTransitionTransactionFilters(transition2, to: &transaction, phase: phase)
        _applyTransitionTransactionFilters(transition1, to: &transaction, phase: phase)
    }

    func _filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        _transitionFilteredTransactions(transition1, from: transaction, phase: phase) +
        _transitionFilteredTransactions(transition2, from: transaction, phase: phase)
    }
}

extension CombiningTransition: _TransitionRemovalRetentionFiltering {
    func _retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        _transitionRetainedRemovalTransactions(
            transition1,
            from: transaction,
            phase: phase,
            original: original
        ) +
        _transitionRetainedRemovalTransactions(
            transition2,
            from: transaction,
            phase: phase,
            original: original
        )
    }
}

struct FilteredTransition<Base: Transition>: Transition {
    var transition: Base
    var filter: (inout Transaction, TransitionPhase) -> Void

    func body(content: Content, phase: TransitionPhase) -> some View {
        transition
            .apply(content: content, phase: phase)
            .transaction { transaction in
                filter(&transaction, phase)
            }
    }

    static var properties: TransitionProperties {
        Base.properties
    }

    func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        self.transition._makeContentTransition(transition: &transition)
    }
}

extension FilteredTransition: _TransitionTransactionFiltering {
    func _filter(transaction: inout Transaction, phase: TransitionPhase) {
        filter(&transaction, phase)
        _applyTransitionTransactionFilters(transition, to: &transaction, phase: phase)
    }

    func _filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        var transaction = transaction
        filter(&transaction, phase)
        return _transitionFilteredTransactions(transition, from: transaction, phase: phase)
    }
}

extension FilteredTransition: _TransitionRemovalRetentionFiltering {
    func _retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        var transaction = transaction
        filter(&transaction, phase)
        return _transitionRetainedRemovalTransactions(
            transition,
            from: transaction,
            phase: phase,
            original: original
        )
    }
}

struct ModifierTransition<Modifier: ViewModifier>: Transition {
    var activeModifier: Modifier
    var identityModifier: Modifier

    @ViewBuilder
    func body(content: Content, phase: TransitionPhase) -> some View {
        if phase.isIdentity {
            content.modifier(identityModifier)
        } else {
            content.modifier(activeModifier)
        }
    }
}

struct OffsetTransition: Transition {
    var offset: CGSize

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.offset(phase.isIdentity ? .zero : offset)
    }

    func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([
                ContentTransition.Effect(type: .translation(offset))
            ])
        }
    }
}

extension Edge {
    var opposite: Edge {
        switch self {
        case .top:
            return .bottom
        case .leading:
            return .trailing
        case .bottom:
            return .top
        case .trailing:
            return .leading
        }
    }
}

typealias _TransitionPhaseSetter = (TransitionPhase, Transaction) -> Void
typealias _TransitionTransactionResolver = (TransitionPhase, Transaction) -> [Transaction]

@usableFromInline
class AnyTransitionBox {
    // Type-erased transition boxes carry composition behavior without forcing
    // every call site to keep the concrete Transition type.
    @usableFromInline
    init() {}

    func combined(with other: AnyTransitionBox) -> AnyTransitionBox {
        AnyCombinedTransitionBox(first: self, second: other)
    }

    func combineFirst<First: Transition>(_ first: First) -> AnyTransitionBox {
        AnyCombinedTransitionBox(first: TransitionBox(base: first), second: self)
    }

    func asymmetric(removal: AnyTransitionBox) -> AnyTransitionBox {
        AnyAsymmetricTransitionBox(insertion: self, removal: removal)
    }

    func asymmetricRemoval<Insertion: Transition>(insertion: Insertion) -> AnyTransitionBox {
        AnyAsymmetricTransitionBox(insertion: TransitionBox(base: insertion), removal: self)
    }

    func animation(_ animation: Animation?) -> AnyTransitionBox {
        transaction { transaction, phase in
            if !phase.isIdentity {
                transaction.animation = animation
            }
        }
    }

    func transaction(_ filter: @escaping (inout Transaction, TransitionPhase) -> Void) -> AnyTransitionBox {
        AnyFilteredTransitionBox(base: self, filter: filter)
    }

    func filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        [transaction]
    }

    func retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        filteredTransactions(from: transaction, phase: phase)
    }

    func _makeView(
        phase: TransitionPhase,
        inputs: _ViewInputs,
        phaseSetters: inout [_TransitionPhaseSetter],
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

@usableFromInline
final class TransitionBox<Base: Transition>: AnyTransitionBox {
    let base: Base

    init(base: Base) {
        self.base = base
        super.init()
    }

    override func combined(with other: AnyTransitionBox) -> AnyTransitionBox {
        other.combineFirst(base)
    }

    override func combineFirst<First: Transition>(_ first: First) -> AnyTransitionBox {
        TransitionBox<CombiningTransition<First, Base>>(
            base: CombiningTransition(transition1: first, transition2: base)
        )
    }

    override func asymmetric(removal: AnyTransitionBox) -> AnyTransitionBox {
        removal.asymmetricRemoval(insertion: base)
    }

    override func asymmetricRemoval<Insertion: Transition>(insertion: Insertion) -> AnyTransitionBox {
        TransitionBox<AsymmetricTransition<Insertion, Base>>(
            base: AsymmetricTransition(insertion: insertion, removal: base)
        )
    }

    override func animation(_ animation: Animation?) -> AnyTransitionBox {
        transaction { transaction, phase in
            if !phase.isIdentity {
                transaction.animation = animation
            }
        }
    }

    override func transaction(_ filter: @escaping (inout Transaction, TransitionPhase) -> Void) -> AnyTransitionBox {
        TransitionBox<FilteredTransition<Base>>(
            base: FilteredTransition(transition: base, filter: filter)
        )
    }

    override func filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        _transitionFilteredTransactions(base, from: transaction, phase: phase)
    }

    override func retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        _transitionRetainedRemovalTransactions(
            base,
            from: transaction,
            phase: phase,
            original: original
        )
    }

    override func _makeView(
        phase: TransitionPhase,
        inputs: _ViewInputs,
        phaseSetters: inout [_TransitionPhaseSetter],
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("TransitionBox<\(Base.self)>._makeView called outside AG context.")
        }
        let attr: Attribute<ApplyTransitionModifier<Base>> = graph.makeInput(
            value: ApplyTransitionModifier(transition: base, phase: phase)
        )
        // Retained items keep this setter so removal can flip the same transition
        // subtree to didDisappear with the transaction selected for that phase.
        phaseSetters.append { [base] phase, transaction in
            var filteredTransaction = transaction
            _applyTransitionTransactionFilters(base, to: &filteredTransaction, phase: phase)
            attr.setValue(
                ApplyTransitionModifier(transition: base, phase: phase),
                transaction: filteredTransaction
            )
        }
        return ApplyTransitionModifier<Base>._makeView(
            modifier: _GraphValue(_attribute: attr),
            inputs: inputs,
            body: body
        )
    }
}

private final class AnyCombinedTransitionBox: AnyTransitionBox {
    let first: AnyTransitionBox
    let second: AnyTransitionBox

    init(first: AnyTransitionBox, second: AnyTransitionBox) {
        self.first = first
        self.second = second
        super.init()
    }

    override func filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        first.filteredTransactions(from: transaction, phase: phase) +
        second.filteredTransactions(from: transaction, phase: phase)
    }

    override func retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        first.retainedRemovalTransactions(
            from: transaction,
            phase: phase,
            original: original
        ) +
        second.retainedRemovalTransactions(
            from: transaction,
            phase: phase,
            original: original
        )
    }
}

private final class AnyAsymmetricTransitionBox: AnyTransitionBox {
    let insertion: AnyTransitionBox
    let removal: AnyTransitionBox

    init(insertion: AnyTransitionBox, removal: AnyTransitionBox) {
        self.insertion = insertion
        self.removal = removal
        super.init()
    }

    override func filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        switch phase {
        case .willAppear:
            return insertion.filteredTransactions(from: transaction, phase: phase)
        case .identity:
            return [transaction]
        case .didDisappear:
            return removal.filteredTransactions(from: transaction, phase: phase)
        }
    }

    override func retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        switch phase {
        case .willAppear:
            return insertion.retainedRemovalTransactions(
                from: transaction,
                phase: phase,
                original: original
            )
        case .identity:
            return [transaction]
        case .didDisappear:
            return removal.retainedRemovalTransactions(
                from: transaction,
                phase: phase,
                original: original
            )
        }
    }
}

private final class AnyFilteredTransitionBox: AnyTransitionBox {
    let base: AnyTransitionBox
    let filter: (inout Transaction, TransitionPhase) -> Void

    init(base: AnyTransitionBox, filter: @escaping (inout Transaction, TransitionPhase) -> Void) {
        self.base = base
        self.filter = filter
        super.init()
    }

    override func filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        var filteredTransaction = transaction
        filter(&filteredTransaction, phase)
        return base.filteredTransactions(from: filteredTransaction, phase: phase)
    }

    override func retainedRemovalTransactions(
        from transaction: Transaction,
        phase: TransitionPhase,
        original: Transaction
    ) -> [Transaction] {
        var filteredTransaction = transaction
        filter(&filteredTransaction, phase)
        return base.retainedRemovalTransactions(
            from: filteredTransaction,
            phase: phase,
            original: original
        )
    }

    override func _makeView(
        phase: TransitionPhase,
        inputs: _ViewInputs,
        phaseSetters: inout [_TransitionPhaseSetter],
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var basePhaseSetters: [_TransitionPhaseSetter] = []
        let outputs = base._makeView(
            phase: phase,
            inputs: inputs,
            phaseSetters: &basePhaseSetters,
            body: body
        )
        phaseSetters.append { [filter, basePhaseSetters] phase, transaction in
            var filteredTransaction = transaction
            filter(&filteredTransaction, phase)
            for setter in basePhaseSetters {
                setter(phase, filteredTransaction)
            }
        }
        return outputs
    }
}

public struct AnyTransition {
    fileprivate let box: AnyTransitionBox

    public init<T>(_ transition: T) where T: Transition {
        self.box = TransitionBox(base: transition)
    }

    init(box: AnyTransitionBox) {
        self.box = box
    }

    public static var slide: AnyTransition {
        AnyTransition(SlideTransition())
    }

    public static func offset(_ offset: CGSize) -> AnyTransition {
        AnyTransition(OffsetTransition(offset: offset))
    }

    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        offset(CGSize(width: x, height: y))
    }

    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(box: box.combined(with: other.box))
    }

    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition(PushTransition(edge: edge))
    }

    public static var scale: AnyTransition {
        scale(scale: 1)
    }

    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(ScaleTransition(Double(scale), anchor: anchor))
    }

    nonisolated(unsafe) public static let opacity: AnyTransition = AnyTransition(OpacityTransition())

    public static func modifier<E>(active: E, identity: E) -> AnyTransition where E: ViewModifier {
        AnyTransition(ModifierTransition(activeModifier: active, identityModifier: identity))
    }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(box: insertion.box.asymmetric(removal: removal.box))
    }

    public static var identity: AnyTransition {
        AnyTransition(IdentityTransition())
    }

    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition(MoveTransition(edge: edge))
    }

    public func animation(_ animation: Animation?) -> AnyTransition {
        AnyTransition(box: box.animation(animation))
    }

    public func transaction(_ filter: @escaping (inout Transaction, TransitionPhase) -> Void) -> AnyTransition {
        AnyTransition(box: box.transaction(filter))
    }

    func _filteredTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        box.filteredTransactions(from: transaction, phase: phase)
    }

    func _retainedRemovalTransactions(from transaction: Transaction, phase: TransitionPhase) -> [Transaction] {
        box.retainedRemovalTransactions(
            from: transaction,
            phase: phase,
            original: transaction
        )
    }

    var _transitionType: Any.Type {
        type(of: box)
    }

    func _makeView(
        phase: TransitionPhase,
        inputs: _ViewInputs,
        phaseSetters: inout [_TransitionPhaseSetter],
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        box._makeView(phase: phase, inputs: inputs, phaseSetters: &phaseSetters, body: body)
    }
}

extension Transition where Self == IdentityTransition {
    public static var identity: IdentityTransition {
        Self()
    }
}

extension Transition where Self == OpacityTransition {
    public static var opacity: OpacityTransition {
        Self()
    }
}

extension Transition where Self == MoveTransition {
    public static func move(edge: Edge) -> Self {
        Self(edge: edge)
    }
}

extension Transition where Self == PushTransition {
    public static func push(from edge: Edge) -> Self {
        Self(edge: edge)
    }
}

extension Transition where Self == BlurReplaceTransition {
    public static func blurReplace(_ config: BlurReplaceTransition.Configuration = .downUp) -> Self {
        Self(configuration: config)
    }

    public static var blurReplace: BlurReplaceTransition {
        blurReplace(.downUp)
    }
}

extension Transition where Self == SlideTransition {
    public static var slide: SlideTransition {
        Self()
    }
}

extension Transition where Self == ScaleTransition {
    public static var scale: ScaleTransition {
        Self(1e-5)
    }

    public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> Self {
        Self(scale, anchor: anchor)
    }
}

extension Transition {
    public func animation(_ animation: Animation?) -> some Transition {
        FilteredTransition(transition: self) { transaction, phase in
            if !phase.isIdentity {
                transaction.animation = animation
            }
        }
    }

    public func transaction(_ filter: @escaping (inout Transaction, TransitionPhase) -> Void) -> some Transition {
        FilteredTransition(transition: self, filter: filter)
    }

    public func combined<T>(with other: T) -> some Transition where T: Transition {
        CombiningTransition(transition1: self, transition2: other)
    }
}
