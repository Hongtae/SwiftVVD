//
//  File: MatchedGeometryEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: UInt32

    @inlinable
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
    public static let frame: MatchedGeometryProperties = [.position, .size]
}

typealias MatchedGeometryArguments = (
    properties: MatchedGeometryProperties,
    anchor: UnitPoint,
    isSource: Bool
)

private struct MatchedGeometryKey: Hashable {
    var id: AnyHashable
    var namespace: Namespace.ID
}

final class MatchedGeometryScope: PropertyKey {
    struct ViewRegistration {
        var attribute: AGAttribute
        var args: Attribute<MatchedGeometryArguments>
        var transaction: Attribute<Transaction>
        var phase: Attribute<Phase>
        var placement: OptionalAttribute<Bool>
        var size: Attribute<ViewSize>
        var position: Attribute<CGPoint>
        var transform: Attribute<ViewTransform>
    }

    final class Frame {
        var key: AnyHashable
        var views: [ViewRegistration] = []
        var sharedFrame: Attribute<ViewFrame?>?
        var sourcePhase: Attribute<Phase>?
        var sourceTransaction: Attribute<Transaction>?

        init(key: AnyHashable) {
            self.key = key
        }
    }

    static var defaultValue: MatchedGeometryScope? { nil }

    static func valuesEqual(
        _ lhs: MatchedGeometryScope?,
        _ rhs: MatchedGeometryScope?
    ) -> Bool {
        lhs === rhs
    }

    private weak var graph: _AGGraph?
    private let rootSubgraph: AGSubgraph?
    private let inputs: _ViewInputs
    private(set) var frames: [Frame] = []
    private var keyedFrames: [AnyHashable: Int] = [:]

    init(inputs: _ViewInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("MatchedGeometryScope initialized outside an active _AGGraph context.")
        }
        self.graph = graph
        self.rootSubgraph = AGSubgraph.current
        self.inputs = inputs
    }

    func frame(
        index: inout Int?,
        for key: AnyHashable,
        view: ViewRegistration
    ) -> Attribute<ViewFrame?> {
        guard let graph, graph === _AGGraph.current else {
            fatalError("MatchedGeometryScope.frame called outside its owning graph context.")
        }

        let frameIndex: Int
        if let existing = index,
           frames.indices.contains(existing),
           frames[existing].key == key {
            frameIndex = existing
        } else {
            if let existing = index {
                releaseFrame(index: existing, owner: view.attribute)
            }
            if let existing = keyedFrames[key] {
                frameIndex = existing
            } else {
                frameIndex = frames.count
                frames.append(Frame(key: key))
                keyedFrames[key] = frameIndex
            }
            index = frameIndex
        }

        let frame = frames[frameIndex]
        if let viewIndex = frame.views.firstIndex(where: { $0.attribute == view.attribute }) {
            frame.views[viewIndex] = view
        } else {
            frame.views.append(view)
            invalidateSharedFrame(frame)
        }
        return makeSharedFrameIfNeeded(at: frameIndex)
    }

    func releaseFrame(index: Int, owner: AGAttribute) {
        guard frames.indices.contains(index) else { return }
        let frame = frames[index]
        let oldCount = frame.views.count
        frame.views.removeAll { $0.attribute == owner }
        if frame.views.count != oldCount {
            invalidateSharedFrame(frame)
        }
    }

    func sourceInfo(frameIndex: Int) -> MatchedGeometrySourceInfo? {
        guard frames.indices.contains(frameIndex) else { return nil }
        let frame = frames[frameIndex]
        let sources = frame.views.filter { $0.args.value.isSource }
        let activeSource = sources.first(where: {
            !$0.phase.value.isBeingRemoved && ($0.placement.attribute?.value ?? true)
        })
        let hasUnplacedActiveSource = sources.contains(where: {
            !$0.phase.value.isBeingRemoved && !($0.placement.attribute?.value ?? true)
        })
        let deferredSource = hasUnplacedActiveSource
            ? sources.first(where: {
                $0.phase.value.isBeingRemoved && ($0.placement.attribute?.value ?? true)
            })
            : nil
        let source = activeSource ?? deferredSource
        guard let source else { return nil }

        let args = source.args.value
        let size = source.size.value
        var points = [CGPoint(
            x: size.value.width * args.anchor.x,
            y: size.value.height * args.anchor.y
        )]
        source.transform.value.convertGlobal(from: .local, points: &points)
        let anchorPosition = points[0]
        let origin = CGPoint(
            x: anchorPosition.x - size.value.width * args.anchor.x,
            y: anchorPosition.y - size.value.height * args.anchor.y
        )
        let transaction = graph?.transaction(for: source.position.identifier) ??
            graph?.transaction(for: source.size.identifier) ??
            source.transaction.value
        var phase = source.phase.value
        if activeSource == nil {
            // A replacement source can exist before its parent layout has
            // assigned target geometry. Keep the retained source authoritative
            // during that gap instead of retargeting the shared frame to the
            // new layout bridge's placeholder origin.
            phase.isBeingRemoved = false
        }
        return MatchedGeometrySourceInfo(
            frame: ViewFrame(origin: origin, size: size),
            phase: phase,
            transaction: transaction,
            positionAttribute: source.position.identifier,
            sizeAttribute: source.size.identifier
        )
    }

    private func makeSharedFrameIfNeeded(at index: Int) -> Attribute<ViewFrame?> {
        let frame = frames[index]
        if let sharedFrame = frame.sharedFrame {
            return sharedFrame
        }
        guard let graph else {
            fatalError("MatchedGeometryScope lost its owning graph.")
        }

        let attributes = AGSubgraph.withCurrent(rootSubgraph) { () -> (
            Attribute<Phase>,
            Attribute<Transaction>,
            Attribute<ViewFrame?>
        ) in
            let sourcePhase: Attribute<Phase> = graph.makeRule { [weak self] in
                self?.sourceInfo(frameIndex: index)?.phase ?? self?.inputs.base.phase.value ?? Phase()
            }
            let sourceTransaction: Attribute<Transaction> = graph.makeRule { [weak self] in
                self?.sourceInfo(frameIndex: index)?.transaction ??
                    self?.inputs.base.transaction.value ?? Transaction()
            }
            let sharedFrame: Attribute<ViewFrame?> = graph.makeStatefulRule(
                MatchedGeometrySharedFrame(
                    scope: self,
                    frameIndex: index,
                    phase: sourcePhase,
                    transaction: sourceTransaction,
                    time: inputs.base.time,
                    environment: inputs.base.cachedEnvironment.value.environment
                )
            )
            return (sourcePhase, sourceTransaction, sharedFrame)
        }
        frame.sourcePhase = attributes.0
        frame.sourceTransaction = attributes.1
        frame.sharedFrame = attributes.2
        return attributes.2
    }

    private func invalidateSharedFrame(_ frame: Frame) {
        guard let graph, let sharedFrame = frame.sharedFrame else { return }
        graph.invalidateAttribute(sharedFrame.identifier)
        (_AGGraphContext.current?.context as? GraphHost)?.graphDelegate?.graphDidChange()
    }
}

struct MatchedGeometrySourceInfo {
    var frame: ViewFrame
    var phase: Phase
    var transaction: Transaction
    var positionAttribute: AGAttribute
    var sizeAttribute: AGAttribute
}

private struct MatchedGeometrySharedFrame: StatefulRule {
    typealias Value = ViewFrame?

    weak var scope: MatchedGeometryScope?
    var frameIndex: Int
    var helper: AnimatableAttributeHelper<ViewFrame>
    var environment: Attribute<EnvironmentValues>

    init(
        scope: MatchedGeometryScope,
        frameIndex: Int,
        phase: Attribute<Phase>,
        transaction: Attribute<Transaction>,
        time: Attribute<Time>,
        environment: Attribute<EnvironmentValues>
    ) {
        self.scope = scope
        self.frameIndex = frameIndex
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
        self.environment = environment
    }

    mutating func updateValue() {
        guard let info = scope?.sourceInfo(frameIndex: frameIndex) else {
            helper.finishAndClearAnimatorState()
            _AGGraph.setStatefulOutput(Optional<ViewFrame>.none)
            return
        }
        guard let graph = _AGGraph.current else {
            fatalError("MatchedGeometrySharedFrame.updateValue called outside an active graph.")
        }

        var value = (value: info.frame, changed: false)
        let update = helper.beginStandaloneUpdate(
            value: &value,
            defaultAnimation: nil,
            transactionForChangedTarget: {
                graph.transaction(for: info.positionAttribute) ??
                    graph.transaction(for: info.sizeAttribute) ??
                    info.transaction
            }
        )
        let stored: ViewFrame?? = _AGGraph.currentStatefulOutput(Optional<ViewFrame>.self)
        let previous = stored ?? nil

        if update.didReset || previous == nil {
            helper.finishAndClearAnimatorState()
            helper.commitTarget(update.target)
            _AGGraph.setStatefulOutput(Optional(update.target))
            return
        }

        if let branch = update.targetAnimationBranch {
            switch branch {
            case .animated(let animation, let transaction, let time):
                helper.retargetStandaloneAnimation(
                    animation: animation,
                    start: previous ?? update.target,
                    target: update.target,
                    transaction: transaction,
                    time: time,
                    environment: environment
                )
                value.value = update.target
            case .noAnimation:
                helper.finishAndClearAnimatorState()
                helper.commitTarget(update.target)
                _AGGraph.setStatefulOutput(Optional(update.target))
                return
            }
        }

        guard helper.isAnimating else {
            _AGGraph.setStatefulOutput(Optional(previous ?? update.target))
            return
        }
        helper.update(
            value: &value,
            environment: environment,
            advancesDelayedSecondSample: true
        )
        _AGGraph.setStatefulOutput(Optional(value.value))
    }

    mutating func destroy() {
        helper.finishAndClearAnimatorState()
    }
}

private struct MatchedGeometryRegistration<ID: Hashable>: StatefulRule, RemovableAttribute {
    typealias Value = Attribute<ViewFrame?>

    var modifier: Attribute<_MatchedGeometryEffect<ID>>
    var args: Attribute<MatchedGeometryArguments>
    var transaction: Attribute<Transaction>
    var phase: Attribute<Phase>
    var placement: OptionalAttribute<Bool>
    var size: Attribute<ViewSize>
    var position: Attribute<CGPoint>
    var transform: Attribute<ViewTransform>
    weak var scope: MatchedGeometryScope?
    var frameIndex: Int?
    var selfAttribute: AGAttribute = .invalid
    var isRemoved = false

    mutating func updateValue() {
        guard let scope else {
            fatalError("MatchedGeometryRegistration lost its scope.")
        }
        let owner = _AGGraph.currentRuleContextAttribute ?? selfAttribute
        guard !owner.isInvalid else {
            fatalError("MatchedGeometryRegistration has no current attribute.")
        }
        selfAttribute = owner
        let value = modifier.value
        let key = AnyHashable(MatchedGeometryKey(
            id: AnyHashable(value.id),
            namespace: value.namespace
        ))
        if isRemoved, let frameIndex {
            scope.releaseFrame(index: frameIndex, owner: owner)
        }
        let sharedFrame = scope.frame(
            index: &frameIndex,
            for: key,
            view: MatchedGeometryScope.ViewRegistration(
                attribute: owner,
                args: args,
                transaction: transaction,
                phase: phase,
                placement: placement,
                size: size,
                position: position,
                transform: transform
            )
        )
        if isRemoved, let frameIndex {
            scope.releaseFrame(index: frameIndex, owner: owner)
        }
        _AGGraph.setStatefulOutput(sharedFrame)
    }

    mutating func destroy() {
        if let frameIndex, !selfAttribute.isInvalid {
            scope?.releaseFrame(index: frameIndex, owner: selfAttribute)
        }
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.isRemoved = true
            if let frameIndex = rule.frameIndex {
                rule.scope?.releaseFrame(index: frameIndex, owner: attribute)
            }
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else { return }
        graph.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.isRemoved = false
        }
        graph.invalidateAttribute(attribute)
        (_AGGraphContext.current?.context as? GraphHost)?.graphDelegate?.graphDidChange()
    }
}

extension _ViewInputs {
    mutating func makeRootMatchedGeometryScope() {
        if base.customInputs.value(forKey: MatchedGeometryScope.self) != nil {
            return
        }
        base.customInputs.setValue(
            MatchedGeometryScope(inputs: self),
            forKey: MatchedGeometryScope.self
        )
    }
}

private struct MatchedGeometryFrame: Rule {
    var sharedFrame: Attribute<Attribute<ViewFrame?>>
    var args: Attribute<MatchedGeometryArguments>
    var size: Attribute<ViewSize>
    var position: Attribute<CGPoint>
    var childLayoutComputer: OptionalAttribute<LayoutComputer>

    func updateValue() -> ViewFrame {
        let ownSize = size.value
        let ownPosition = position.value
        let arguments = args.value
        guard let shared = sharedFrame.value.value else {
            return ViewFrame(origin: ownPosition, size: ownSize)
        }

        let resolvedSize: ViewSize
        if arguments.properties.contains(.size),
           let layoutComputer = childLayoutComputer.attribute?.value {
            // Matching size changes the child's layout proposal. It must not
            // scale the already-rendered content as a projection effect would.
            let proposal = ProposedViewSize(shared.size.value)
            resolvedSize = ViewSize(
                layoutComputer.sizeThatFits(proposal),
                proposal: proposal
            )
        } else {
            resolvedSize = ownSize
        }

        let resolvedOrigin: CGPoint
        if arguments.properties.contains(.position) {
            // Preserve the size accepted by the child, then place that result
            // so its requested anchor coincides with the shared-frame anchor.
            let targetAnchor = CGPoint(
                x: shared.origin.x + shared.size.value.width * arguments.anchor.x,
                y: shared.origin.y + shared.size.value.height * arguments.anchor.y
            )
            resolvedOrigin = CGPoint(
                x: targetAnchor.x - resolvedSize.value.width * arguments.anchor.x,
                y: targetAnchor.y - resolvedSize.value.height * arguments.anchor.y
            )
        } else {
            resolvedOrigin = ownPosition
        }
        return ViewFrame(origin: resolvedOrigin, size: resolvedSize)
    }
}

private struct MatchedGeometrySourcePhase: Rule {
    var phase: Attribute<Phase>
    var transitionPhase: Attribute<TransitionPhase>

    func updateValue() -> Phase {
        var value = phase.value
        value.isBeingRemoved = transitionPhase.value == .didDisappear
        return value
    }
}

public struct _MatchedGeometryEffect<ID: Hashable>: ViewModifier {
    public var id: ID
    public var namespace: Namespace.ID
    public var args: (
        properties: MatchedGeometryProperties,
        anchor: UnitPoint,
        isSource: Bool
    )

    @inlinable
    public init(
        id: ID,
        namespace: Namespace.ID,
        properties: MatchedGeometryProperties,
        anchor: UnitPoint,
        isSource: Bool
    ) {
        self.id = id
        self.namespace = namespace
        self.args = (properties, anchor, isSource)
    }

    public typealias Body = Never

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_MatchedGeometryEffect._makeView called outside an active graph.")
        }
        guard let scope = inputs.base.customInputs.value(forKey: MatchedGeometryScope.self) else {
            return body(_Graph(), inputs)
        }

        var modifiedInputs = inputs
        modifiedInputs.needsGeometry = true
        let args = modifier[\.args]._attribute
        let animatedLayoutFrame = inputs.base.cachedEnvironment.value.animatedFrame
        let targetPosition = animatedLayoutFrame?.position ?? inputs.position
        let targetSize = animatedLayoutFrame?.size ?? inputs.size
        let targetGeometryFrame: Attribute<ViewFrame> = graph.makeRule {
            ViewFrame(origin: targetPosition.value, size: targetSize.value)
        }
        let targetTransform: Attribute<ViewTransform>
        if animatedLayoutFrame != nil {
            let presentationTransform = inputs.transform
            targetTransform = graph.makeRule {
                var transform = presentationTransform.value
                // Layout animation exposes its current presentation origin through
                // inputs.position, while the cached frame retains the newly placed
                // target origin. Matched source arbitration must start from that
                // target geometry; otherwise a newly inserted source is registered
                // at the layout bridge's initial zero frame and flies in from the
                // window origin.
                transform.appendPosition(targetPosition.value)
                return transform
            }
        } else {
            targetTransform = inputs.transform
        }
        let sourcePhase: Attribute<Phase>
        if let transitionPhase = inputs[
            DynamicContainerTransitionPhaseInput.self
        ].attribute {
            sourcePhase = graph.makeRule(
                MatchedGeometrySourcePhase(
                    phase: inputs.base.phase,
                    transitionPhase: transitionPhase
                )
            )
        } else {
            sourcePhase = inputs.base.phase
        }
        let registration: Attribute<Attribute<ViewFrame?>> = graph.makeStatefulRule(
            MatchedGeometryRegistration(
                modifier: modifier._attribute,
                args: args,
                transaction: inputs.base.transaction,
                phase: sourcePhase,
                placement: inputs[LayoutPlacementStateInput.self],
                size: targetSize,
                position: targetPosition,
                transform: targetTransform,
                scope: scope
            )
        )
        let childLayoutComputer = graph.makeIndirectAttribute(
            defaultValue: LayoutComputer.defaultValue
        )
        let matchedFrame: Attribute<ViewFrame> = graph.makeRule(
            MatchedGeometryFrame(
                sharedFrame: registration,
                args: args,
                size: inputs.size,
                position: inputs.position,
                childLayoutComputer: OptionalAttribute(childLayoutComputer)
            )
        )
        let transformedInputs: _ViewInputs = {
            var value = modifiedInputs
            value[LayoutPlacementAnimationsDisabledInput.self] = true
            value[LayoutPlacementProjectionInput.self] = LayoutPlacementProjection(
                targetFrame: targetGeometryFrame,
                presentationFrame: matchedFrame
            )
            let parentTransform = modifiedInputs.transform
            value.position = graph.makeRule { matchedFrame.value.origin }
            value.size = graph.makeRule { matchedFrame.value.size }
            value.transform = graph.makeRule {
                var transform = parentTransform.value
                transform.appendPosition(matchedFrame.value.origin)
                return transform
            }
            return value
        }()
        let outputs = body(_Graph(), transformedInputs)
        graph.setIndirectTarget(
            childLayoutComputer,
            to: outputs._layoutComputer.attribute
        )
        guard let innerLayoutComputer = outputs._layoutComputer.attribute else {
            return outputs
        }
        // The parent measures the view in its target layout, while descendants
        // must be placed in the current matched presentation frame. Replacing
        // only the outer position and size would leave overlays at the target
        // or previous layout position while the matched content is in flight.
        let projectedLayoutComputer: Attribute<LayoutComputer> = graph.makeRule {
            let inner = innerLayoutComputer.value
            let frame = targetGeometryFrame.value
            return LayoutComputer(
                sizeThatFits: { inner.sizeThatFits($0) },
                spacing: inner.spacing,
                place: { _, anchor, _ in
                    let proposal = ProposedViewSize(frame.size.value)
                    let position = CGPoint(
                        x: frame.origin.x + frame.size.value.width * anchor.x,
                        y: frame.origin.y + frame.size.value.height * anchor.y
                    )
                    inner.place(at: position, anchor: anchor, proposal: proposal)
                },
                priority: inner.priority,
                explicitAlignment: { inner.explicitAlignment($0, at: $1) }
            )
        }
        var projectedOutputs = outputs
        projectedOutputs._layoutComputer = OptionalAttribute(projectedLayoutComputer)
        return projectedOutputs
    }

    public static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("_MatchedGeometryEffect._makeViewList called outside an active graph.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

@available(*, unavailable)
extension _MatchedGeometryEffect: Sendable {
}

extension View {
    @inlinable
    public func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> some View {
        modifier(_MatchedGeometryEffect(
            id: id,
            namespace: namespace,
            properties: properties,
            anchor: anchor,
            isSource: isSource
        ))
    }
}
