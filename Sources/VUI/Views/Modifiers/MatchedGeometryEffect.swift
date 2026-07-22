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

typealias MatchedGeometrySharedValue = (
    frame: ViewFrame?,
    source: AnyOptionalAttribute
)

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
        var sharedFrame: Attribute<MatchedGeometrySharedValue>?
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
    ) -> MatchedGeometrySharedValue {
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
        return makeSharedFrameIfNeeded(at: frameIndex).value
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
        guard !sources.isEmpty else { return nil }
        let soleSource = frame.views.count == 1 ? sources.first : nil
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
        let source = soleSource ?? activeSource ?? deferredSource
        guard let source else { return nil }

        return makeSourceInfo(
            source,
            clearsRemoval: soleSource == nil && activeSource == nil
        )
    }

    func sourceInfo(
        frameIndex: Int,
        matching attribute: AGAttribute
    ) -> MatchedGeometrySourceInfo? {
        guard frames.indices.contains(frameIndex),
              let source = frames[frameIndex].views.first(where: {
                  $0.attribute == attribute
              }) else {
            return nil
        }
        return makeSourceInfo(source, clearsRemoval: false)
    }

    private func makeSourceInfo(
        _ source: ViewRegistration,
        clearsRemoval: Bool
    ) -> MatchedGeometrySourceInfo {
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
        let transaction = source.transaction.value
        var phase = source.phase.value
        if clearsRemoval {
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
            sourceAttribute: source.attribute
        )
    }

    private func makeSharedFrameIfNeeded(
        at index: Int
    ) -> Attribute<MatchedGeometrySharedValue> {
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
            Attribute<MatchedGeometrySharedValue>
        ) in
            let sourcePhase: Attribute<Phase> = graph.makeRule { [weak self] in
                self?.sourceInfo(frameIndex: index)?.phase ?? self?.inputs.base.phase.value ?? Phase()
            }
            let sourceTransaction: Attribute<Transaction> = graph.makeRule { [weak self] in
                self?.sourceInfo(frameIndex: index)?.transaction ??
                    self?.inputs.base.transaction.value ?? Transaction()
            }
            let sharedFrame: Attribute<MatchedGeometrySharedValue> = graph.makeStatefulRule(
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
    var sourceAttribute: AGAttribute
}

private struct MatchedGeometrySharedFrame: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = MatchedGeometrySharedValue

    weak var scope: MatchedGeometryScope?
    var frameIndex: Int
    var helper: AnimatableAttributeHelper<ViewFrame>
    var environment: Attribute<EnvironmentValues>
    var lastSourceAttribute = AGWeakAttribute.invalid

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
            if helper.isAnimating,
               let lastSource = lastSourceAttribute.attribute,
               let retained = scope?.sourceInfo(
                   frameIndex: frameIndex,
                   matching: lastSource
               ),
               !retained.phase.isBeingRemoved {
                var value = (value: retained.frame, changed: false)
                helper.update(
                    value: &value,
                    environment: environment,
                    advancesDelayedSecondSample: true
                )
                _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
                    frame: value.value,
                    source: AnyOptionalAttribute()
                ))
                return
            }
            helper.finishAndClearAnimatorState()
            lastSourceAttribute = .invalid
            _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
                frame: nil,
                source: AnyOptionalAttribute()
            ))
            return
        }
        var value = (value: info.frame, changed: false)
        let update = helper.beginStandaloneUpdate(
            value: &value,
            defaultAnimation: nil,
            transactionForChangedTarget: {
                info.transaction
            }
        )
        let stored: MatchedGeometrySharedValue? = _AGGraph.currentStatefulOutput()
        let previous = stored?.frame
        let source = AnyOptionalAttribute(info.sourceAttribute)
        lastSourceAttribute = AGWeakAttribute(info.sourceAttribute)

        if update.didReset || previous == nil {
            helper.finishAndClearAnimatorState()
            helper.commitTarget(update.target)
            _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
                frame: update.target,
                source: source
            ))
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
                _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
                    frame: update.target,
                    source: source
                ))
                return
            }
        }

        guard helper.isAnimating else {
            _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
                frame: previous ?? update.target,
                source: source
            ))
            return
        }
        helper.update(
            value: &value,
            environment: environment,
            advancesDelayedSecondSample: true
        )
        _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
            frame: value.value,
            source: helper.isAnimating ? AnyOptionalAttribute() : source
        ))
    }

    mutating func destroy() {
        helper.finishAndClearAnimatorState()
    }
}

private struct MatchedGeometryRegistration<ID: Hashable>: StatefulRule, ObservedAttribute, RemovableAttribute, AsyncAttribute {
    typealias Value = MatchedGeometrySharedValue

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
    var resetSeed: UInt32 = 0
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
        let currentResetSeed = phase.value.resetSeed
        if resetSeed != currentResetSeed {
            resetSeed = currentResetSeed
            if let frameIndex {
                scope.releaseFrame(index: frameIndex, owner: owner)
                self.frameIndex = nil
            }
        }
        if isRemoved {
            _AGGraph.setStatefulOutput(MatchedGeometrySharedValue(
                frame: nil,
                source: AnyOptionalAttribute()
            ))
            return
        }
        let value = modifier.value
        let key = AnyHashable(MatchedGeometryKey(
            id: AnyHashable(value.id),
            namespace: value.namespace
        ))
        let sharedValue = scope.frame(
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
        _AGGraph.setStatefulOutput(sharedValue)
    }

    mutating func destroy() {
        if let frameIndex, !selfAttribute.isInvalid {
            scope?.releaseFrame(index: frameIndex, owner: selfAttribute)
        }
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(
            attribute,
            as: Self.self,
            invalidating: true
        ) { rule in
            if let frameIndex = rule.frameIndex {
                rule.scope?.releaseFrame(index: frameIndex, owner: attribute)
                rule.frameIndex = nil
            }
            rule.isRemoved = true
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else { return }
        graph.mutateStatefulRule(
            attribute,
            as: Self.self,
            invalidating: true
        ) { rule in
            rule.isRemoved = false
        }
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

private struct MatchedFrame: Rule, AsyncAttribute {
    var sharedFrame: Attribute<MatchedGeometrySharedValue>
    var args: Attribute<MatchedGeometryArguments>
    var size: Attribute<ViewSize>
    var position: Attribute<CGPoint>
    // The target position is authoritative for self geometry, while coordinate
    // conversion must use the origin represented by the current transform.
    var transformPosition: Attribute<CGPoint>
    var transform: Attribute<ViewTransform>
    var childLayoutComputer: OptionalAttribute<LayoutComputer>

    var value: ViewFrame {
        let ownSize = size.value
        let ownPosition = position.value
        let arguments = args.value
        let sharedValue = sharedFrame.value
        guard let shared = sharedValue.frame,
              sharedValue.source.identifier != sharedFrame.identifier else {
            return ViewFrame(origin: ownPosition, size: ownSize)
        }

        let resolvedSize: ViewSize
        if arguments.properties.contains(.size),
           let layoutComputer = childLayoutComputer.attribute?.value {
            // Matching size changes the child's layout proposal. It must not
            // scale the already-rendered content as a projection effect would.
            let proposal = ProposedViewSize(shared.size.value)
            resolvedSize = ViewSize(
                layoutComputer.sizeThatFits(_ProposedSize(proposal)),
                proposal: _ProposedSize(proposal)
            )
        } else {
            resolvedSize = ownSize
        }

        let resolvedOrigin: CGPoint
        if arguments.properties.contains(.position) {
            var targetAnchor = [CGPoint(
                x: shared.origin.x + shared.size.value.width * arguments.anchor.x,
                y: shared.origin.y + shared.size.value.height * arguments.anchor.y
            )]
            transform.value.convertGlobal(to: .local, points: &targetAnchor)
            let coordinateOrigin = transformPosition.value
            resolvedOrigin = CGPoint(
                x: coordinateOrigin.x + targetAnchor[0].x
                    - resolvedSize.value.width * arguments.anchor.x,
                y: coordinateOrigin.y + targetAnchor[0].y
                    - resolvedSize.value.height * arguments.anchor.y
            )
        } else {
            resolvedOrigin = ownPosition
        }
        return ViewFrame(origin: resolvedOrigin, size: resolvedSize)
    }
}

private struct MatchedDisplayList: Rule, AsyncAttribute {
    var identity: _DisplayList_Identity
    var sharedFrame: Attribute<MatchedGeometrySharedValue>
    var args: Attribute<MatchedGeometryArguments>
    var content: Attribute<DisplayList>
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var containerPosition: Attribute<CGPoint>

    var value: DisplayList {
        let content = content.value
        let presentationPosition = position.value
        let frame = CGRect(
            origin: CGPoint(
                x: presentationPosition.x - containerPosition.value.x,
                y: presentationPosition.y - containerPosition.value.y
            ),
            size: size.value.value
        )

        var result = DisplayList()
        result.appendEffect(
            .identity,
            contents: content,
            frame: frame,
            identity: identity,
            version: DisplayList.Version(forUpdate: ())
        )
        return result
    }
}

private struct MatchedGeometrySourcePhase: Rule {
    var phase: Attribute<Phase>
    var transitionPhase: Attribute<TransitionPhase>

    var value: Phase {
        var value = phase.value
        value.isBeingRemoved = transitionPhase.value == .didDisappear
        return value
    }
}

public struct _MatchedGeometryEffect<ID: Hashable>: MultiViewModifier, PrimitiveViewModifier {
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
        let targetPosition = inputs.position
        let targetSize = inputs.size
        let targetTransform = inputs.transform
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
        let registration: Attribute<MatchedGeometrySharedValue> = graph.makeStatefulRule(
            MatchedGeometryRegistration(
                modifier: modifier._attribute,
                args: args,
                transaction: inputs[
                    LayoutPlacementTransactionInput.self
                ].attribute ?? inputs.base.transaction,
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
            MatchedFrame(
                sharedFrame: registration,
                args: args,
                size: targetSize,
                position: targetPosition,
                transformPosition: inputs.position,
                transform: inputs.transform,
                childLayoutComputer: OptionalAttribute(childLayoutComputer)
            )
        )
        let matchedPosition = graph.subscriptNode(
            parent: matchedFrame,
            keyPath: \ViewFrame.origin
        )
        let matchedSize = graph.subscriptNode(
            parent: matchedFrame,
            keyPath: \ViewFrame.size
        )
        var matchedInputs = modifiedInputs
        matchedInputs.copyCaches()
        matchedInputs.position = matchedPosition
        matchedInputs.size = matchedSize
        var presentationEnvironment = matchedInputs.base.cachedEnvironment.value
        let bodyContainerPosition = presentationEnvironment.animatedPosition(
            for: matchedInputs
        )
        matchedInputs.base.cachedEnvironment.value = presentationEnvironment

        var bodyInputs = matchedInputs
        bodyInputs.containerPosition = bodyContainerPosition
        bodyInputs.requestsLayoutComputer = true
        let outputs = body(_Graph(), bodyInputs)
        graph.setIndirectTarget(
            childLayoutComputer,
            to: outputs._layoutComputer.attribute
        )
        var projectedOutputs = outputs
        if let content = outputs.preferences.reducedValue(
            for: DisplayList.Key.self,
            in: graph
        ) {
            var presentationEnvironment = matchedInputs.base.cachedEnvironment.value
            let animatedPosition = presentationEnvironment.animatedPosition(
                for: matchedInputs
            )
            let animatedSize = presentationEnvironment.animatedSize(
                for: matchedInputs
            )
            matchedInputs.base.cachedEnvironment.value = presentationEnvironment
            let displayList = graph.makeRule(
                MatchedDisplayList(
                    identity: _DisplayList_Identity(),
                    sharedFrame: registration,
                    args: args,
                    content: content,
                    position: animatedPosition,
                    size: animatedSize,
                    containerPosition: inputs.containerPosition
                )
            )
            projectedOutputs.preferences.setValue(
                displayList.identifier,
                for: DisplayList.Key.self
            )
        }
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
