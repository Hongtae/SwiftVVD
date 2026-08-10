//
//  File: SystemScrollViewHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Default anchors used for initial placement, size changes, and undersized alignment.
struct ScrollAnchorStorage: Equatable {
    enum Role: Hashable, CaseIterable, Sendable {
        case initialOffset
        case sizeChanges
        case alignment
    }

    var anchors: [Role: UnitPoint]
    var defaultValue: UnitPoint?

    init(
        anchors: [Role: UnitPoint] = [:],
        defaultValue: UnitPoint? = nil
    ) {
        self.anchors = anchors
        self.defaultValue = defaultValue
    }

    var isEmpty: Bool {
        anchors.isEmpty && defaultValue == nil
    }

    var initialOffset: UnitPoint {
        anchor(role: .initialOffset)
    }

    var sizeChanges: UnitPoint {
        anchor(role: .sizeChanges)
    }

    var alignment: UnitPoint {
        anchor(role: .alignment)
    }

    func anchor(role: Role) -> UnitPoint {
        anchors[role] ?? defaultValue ?? .zero
    }

    func adjustedAnchor(role: Role, layoutDirection: LayoutDirection) -> UnitPoint {
        let anchor = anchor(role: role)
        guard layoutDirection == .rightToLeft else {
            return anchor
        }
        return UnitPoint(x: 1 - anchor.x, y: anchor.y)
    }
}

/// Configuration carried with a graph-requested scroll target.
struct ScrollTargetConfiguration: Equatable {
    var animation: Animation?
    var requiresVisibility: Bool
    var preservesVelocity: Bool

    init(
        animation: Animation? = nil,
        requiresVisibility: Bool = false,
        preservesVelocity: Bool = false
    ) {
        self.animation = animation
        self.requiresVisibility = requiresVisibility
        self.preservesVelocity = preservesVelocity
    }

    init(transaction: Transaction) {
        self.animation = transaction.isAnimated ? transaction.animation : nil
        self.requiresVisibility = transaction.scrollToRequiresCompleteVisibility
        self.preservesVelocity = transaction.scrollPositionUpdatePreservesVelocity
    }
}

enum ScrollViewUtilities {
    static func contentFrame(
        in containingSize: CGSize,
        contentComputer: LayoutComputer?,
        axes: Axis.Set
    ) -> ViewFrame {
        var proposal = ProposedViewSize(containingSize)
        if axes.contains(.horizontal) {
            proposal.width = nil
        }
        if axes.contains(.vertical) {
            proposal.height = nil
        }

        var contentSize = containingSize
        if !axes.isEmpty {
            let measured = (contentComputer ?? LayoutComputer.defaultValue)
                .sizeThatFits(_ProposedSize(proposal))
            if axes.contains(.horizontal) {
                contentSize.width = measured.width
            }
            if axes.contains(.vertical) {
                contentSize.height = measured.height
            }
        }

        let origin = CGPoint(
            x: axes.contains(.horizontal)
                ? 0
                : max(containingSize.width - contentSize.width, 0) * 0.5,
            y: axes.contains(.vertical)
                ? 0
                : max(containingSize.height - contentSize.height, 0) * 0.5
        )
        return ViewFrame(
            origin: origin,
            size: ViewSize(contentSize, proposal: _ProposedSize(proposal))
        )
    }

    static func sizeThatFits(
        in proposal: ProposedViewSize,
        contentComputer: LayoutComputer?,
        axes: Axis.Set
    ) -> CGSize? {
        guard !axes.isEmpty else {
            return nil
        }

        var contentProposal = proposal
        if axes.contains(.horizontal) {
            contentProposal.width = nil
        }
        if axes.contains(.vertical) {
            contentProposal.height = nil
        }

        var size = (contentComputer ?? LayoutComputer.defaultValue)
            .sizeThatFits(_ProposedSize(contentProposal))
        if axes.contains(.horizontal), let width = proposal.width {
            size.width = width
        }
        if axes.contains(.vertical), let height = proposal.height {
            size.height = height
        }
        return size
    }

    static func animationOffset(
        targetFrame: CGRect,
        anchor: UnitPoint?,
        viewPortFrame: CGRect,
        contentFrame: CGRect,
        requiresVisibility: Bool
    ) -> CGPoint {
        CGPoint(
            x: animationOffset(
                targetMin: targetFrame.minX,
                targetLength: targetFrame.width,
                viewportMin: viewPortFrame.minX,
                viewportLength: viewPortFrame.width,
                contentMin: contentFrame.minX,
                contentLength: contentFrame.width,
                anchor: anchor?.x,
                requiresVisibility: requiresVisibility
            ),
            y: animationOffset(
                targetMin: targetFrame.minY,
                targetLength: targetFrame.height,
                viewportMin: viewPortFrame.minY,
                viewportLength: viewPortFrame.height,
                contentMin: contentFrame.minY,
                contentLength: contentFrame.height,
                anchor: anchor?.y,
                requiresVisibility: requiresVisibility
            )
        )
    }

    private static func animationOffset(
        targetMin: CGFloat,
        targetLength: CGFloat,
        viewportMin: CGFloat,
        viewportLength: CGFloat,
        contentMin: CGFloat,
        contentLength: CGFloat,
        anchor: CGFloat?,
        requiresVisibility: Bool
    ) -> CGFloat {
        let targetMax = targetMin + targetLength
        let viewportMax = viewportMin + viewportLength
        let contentMax = max(contentMin + contentLength - viewportLength, contentMin)

        let result: CGFloat
        if let anchor {
            result = targetMin + targetLength * anchor - viewportLength * anchor
        } else {
            let overlap = min(targetMax, viewportMax) - max(targetMin, viewportMin)
            let hasVisibleArea = overlap > 0
            let isCompletelyVisible = targetMin >= viewportMin && targetMax <= viewportMax
            if hasVisibleArea && (!requiresVisibility || isCompletelyVisible || targetLength > viewportLength) {
                result = viewportMin
            } else {
                let leading = targetMin
                let trailing = targetMax - viewportLength
                result = abs(leading - viewportMin) <= abs(trailing - viewportMin)
                    ? leading
                    : trailing
            }
        }
        return min(max(result, contentMin), contentMax)
    }
}

/// Graph-side state shared with the platform scroll host.
struct SystemScrollLayoutState: Equatable {
    enum ContentOffsetMode {
        case adjustment(reason: ContentOffsetAdjustmentReason)
        case target(
            ((ScrollGeometry, LayoutDirection) -> ScrollTarget?)?,
            config: ScrollTargetConfiguration
        )
        case system
    }

    var contentOffset: CGPoint
    var contentInsets: EdgeInsets
    var systemContentInsets: EdgeInsets
    var systemTranslation: CGSize
    var contentRectToPrepare: CGRect?
    var contentOffsetMode: ContentOffsetMode
    var contentOffsetSeed: VersionSeed

    init(
        contentOffset: CGPoint = .zero,
        contentInsets: EdgeInsets = EdgeInsets(),
        systemContentInsets: EdgeInsets = EdgeInsets(),
        systemTranslation: CGSize = .zero,
        contentRectToPrepare: CGRect? = nil,
        contentOffsetMode: ContentOffsetMode = .system,
        contentOffsetSeed: VersionSeed = VersionSeed()
    ) {
        self.contentOffset = contentOffset
        self.contentInsets = contentInsets
        self.systemContentInsets = systemContentInsets
        self.systemTranslation = systemTranslation
        self.contentRectToPrepare = contentRectToPrepare
        self.contentOffsetMode = contentOffsetMode
        self.contentOffsetSeed = contentOffsetSeed
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.contentOffset == rhs.contentOffset
            && lhs.contentInsets == rhs.contentInsets
            && lhs.systemContentInsets == rhs.systemContentInsets
            && lhs.systemTranslation == rhs.systemTranslation
            && lhs.contentRectToPrepare == rhs.contentRectToPrepare
            && lhs.contentOffsetMode == rhs.contentOffsetMode
            && lhs.contentOffsetSeed.matches(rhs.contentOffsetSeed)
    }

    mutating func updateContentOffset(
        mode: ContentOffsetMode,
        updateSeed: UInt32
    ) {
        contentOffsetMode = mode
        contentOffsetSeed.mergeValue(updateSeed)
        switch mode {
        case let .adjustment(reason):
            contentOffsetSeed.mergeValue(reason.rawValue)
        case .target:
            contentOffsetSeed.mergeValue(ContentOffsetAdjustmentReason.maxValue)
        case .system:
            break
        }
    }
}

extension SystemScrollLayoutState.ContentOffsetMode: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.adjustment(lhsReason), .adjustment(rhsReason)):
            return lhsReason == rhsReason
        case let (.target(_, lhsConfig), .target(_, rhsConfig)):
            // The closure is an operation, not persistent value identity. The seed on
            // SystemScrollLayoutState distinguishes successive target requests.
            return lhsConfig == rhsConfig
        case (.system, .system):
            return true
        default:
            return false
        }
    }
}

/// Narrow graph-to-host update payload.
struct HostingScrollViewUpdateContext: Equatable {
    var contentOffset: CGPoint
    var contentFrame: CGRect
    var containingSize: CGSize
    var offsetMode: SystemScrollLayoutState.ContentOffsetMode
    var safeInsets: EdgeInsets
}

/// Logical host carrier. A backend can consume this state while
/// graph-side scroll ownership remains in the graph layer.
class HostingScrollView {
    private struct DragState {
        var initialOffset: CGPoint
        var translation: CGSize
    }

    private struct DecelerationState {
        var simulation: Deceleration2D
        var beginTime: Time?
        var targetOffsetState: TargetOffsetState?
    }

    private struct TargetOffsetState {
        var proposedOffset: CGPoint
        var originalOffset: CGPoint
        var velocity: _Velocity<CGSize>
        var resolvedOffset: CGPoint
    }

    final class PlatformGroupContainer {
        weak var scrollView: HostingScrollView?
        private(set) var bounds = CGRect.zero
        private(set) var clipBounds = CGRect.zero

        func updateViewport(
            contentOffset: CGPoint,
            containingSize: CGSize
        ) {
            let viewport = CGRect(
                origin: contentOffset,
                size: containingSize
            )
            bounds = viewport
            clipBounds = viewport
        }
    }

    final class PlatformContainer: PlatformGroupFactory {
        let scrollView: HostingScrollView
        private(set) var safeAreaInsets = EdgeInsets()
        private(set) var layoutDirection = LayoutDirection.leftToRight

        init(scrollView: HostingScrollView) {
            self.scrollView = scrollView
        }

        var platformGroupContainer: AnyObject {
            scrollView.host
        }

        func updateSafeArea(
            _ safeAreaInsets: EdgeInsets,
            layoutDirection: LayoutDirection
        ) {
            self.safeAreaInsets = safeAreaInsets
            self.layoutDirection = layoutDirection
        }

        func renderPlatformGroup(
            contents: DisplayList,
            in context: GraphicsContext,
            render: (DisplayList, GraphicsContext) -> Void
        ) {
            let group = scrollView.host
            var context = context
            context.translateBy(
                x: -group.bounds.origin.x,
                y: -group.bounds.origin.y
            )
            context.clip(to: Path(group.clipBounds))
            render(contents, context)
        }
    }

    private let graphRef: _AGGraphContext
    private let layoutState: WeakAttribute<SystemScrollLayoutState>
    private let phaseState: WeakAttribute<ScrollPhaseState>
    private let containerSize: WeakAttribute<CGSize>
    private var dragState: DragState?
    private var decelerationState: DecelerationState?

    let host: PlatformGroupContainer
    weak var parentContainer: PlatformContainer?
    weak var responder: HostingScrollViewResponder?

    private(set) var pendingContext: HostingScrollViewUpdateContext?
    private(set) var configuration = ScrollViewConfiguration()
    private(set) var properties = ScrollEnvironmentProperties()
    private(set) var contentMargins = ContentMarginProxy()
    private(set) var environment = EnvironmentValues()
    private(set) var safeAreaInsets = EdgeInsets()
    private(set) var layoutDirection = LayoutDirection.leftToRight
    private(set) var rtlAdjustment = CGSize.zero
    private(set) var descendantScrollableAxes: Axis.Set?
    private(set) var animationTarget: ScrollTarget?
    private(set) var animationTargetConfig: ScrollTargetConfiguration?

    var isDecelerating: Bool {
        decelerationState != nil
    }

    var currentMotionVelocity: _Velocity<CGSize> {
        decelerationState?.simulation.velocity ?? _Velocity(valuePerSecond: .zero)
    }

    init(
        graphRef: _AGGraphContext,
        layoutState: WeakAttribute<SystemScrollLayoutState>,
        phaseState: WeakAttribute<ScrollPhaseState> = WeakAttribute(),
        containerSize: WeakAttribute<CGSize> = WeakAttribute()
    ) {
        self.graphRef = graphRef
        self.layoutState = layoutState
        self.phaseState = phaseState
        self.containerSize = containerSize
        self.host = PlatformGroupContainer()
        self.host.scrollView = self
    }

    @discardableResult
    func updateContext(_ context: HostingScrollViewUpdateContext) -> Bool {
        var context = context
        publishContainerSize(context.containingSize)
        switch context.offsetMode {
        case let .target(targetProvider, config):
            animationTargetConfig = config
            if !config.preservesVelocity {
                // A non-preserving target owns the presentation immediately;
                // stale drag or inertial state must not move it afterward.
                dragState = nil
                decelerationState = nil
                publishPhase(.idle, velocity: _Velocity(valuePerSecond: .zero))
            }
            let geometry = ScrollGeometry(
                contentOffset: context.contentOffset,
                contentSize: context.contentFrame.size,
                contentInsets: context.safeInsets,
                containerSize: context.containingSize
            )
            if let target = targetProvider?(geometry, layoutDirection) {
                animationTarget = target
                context.contentOffset = ScrollViewUtilities.animationOffset(
                    targetFrame: target.rect,
                    anchor: target.anchor,
                    viewPortFrame: geometry.visibleRect,
                    contentFrame: context.contentFrame,
                    requiresVisibility: config.requiresVisibility
                )
                if config.preservesVelocity, var decelerationState {
                    // Retarget only the destination. The simulation keeps its
                    // current velocity so the presentation remains continuous.
                    decelerationState.simulation.updateTarget(context.contentOffset)
                    decelerationState.targetOffsetState = nil
                    self.decelerationState = decelerationState
                }
            } else {
                animationTarget = nil
            }
        case .adjustment, .system:
            animationTarget = nil
            animationTargetConfig = nil
        }
        host.updateViewport(
            contentOffset: context.contentOffset,
            containingSize: context.containingSize
        )
        pendingContext = context
        retargetContentOffsetIfNeeded()
        return false
    }

    private func publishContainerSize(_ size: CGSize) {
        graphRef.withCurrent {
            guard let graph = _AGGraph.current,
                  containerSize.isValid(in: graph) else {
                return
            }
            let attribute = containerSize.toStrong()
            let current = graph.cachedValue(for: attribute.identifier) as? CGSize
            if current != size {
                attribute.setValue(size, transaction: Transaction.current)
            }
        }
    }

    func updateConfiguration(_ configuration: ScrollViewConfiguration) {
        self.configuration = configuration
    }

    func updateProperties(_ properties: ScrollEnvironmentProperties) {
        self.properties = properties
    }

    func updateContentMargins(_ margins: ContentMarginProxy) {
        contentMargins = margins
    }

    func adoptEnvironment(_ environment: EnvironmentValues) {
        self.environment = environment.untrackedCopy()
    }

    func updateSafeArea(
        _ safeAreaInsets: EdgeInsets,
        layoutDirection: LayoutDirection
    ) {
        self.safeAreaInsets = safeAreaInsets
        self.layoutDirection = layoutDirection
    }

    func updateRTLAdjustment(_ adjustment: CGSize) {
        rtlAdjustment = adjustment
    }

    func updateDescendantScrollableAxes(_ axes: Axis.Set?) {
        descendantScrollableAxes = axes
    }

    func makeLayoutState() -> SystemScrollLayoutState {
        guard let context = pendingContext else {
            return SystemScrollLayoutState()
        }
        return SystemScrollLayoutState(
            contentOffset: context.contentOffset,
            contentInsets: context.safeInsets,
            systemContentInsets: context.safeInsets,
            contentOffsetMode: .system,
            contentOffsetSeed: VersionSeed()
        )
    }

    /// Publishes a host-originated offset, such as a platform wheel or scrollbar update.
    func publishSystemContentOffset(_ offset: CGPoint) {
        graphRef.withCurrent {
            guard let graph = _AGGraph.current,
                  layoutState.isValid(in: graph) else {
                return
            }
            let stateAttribute = layoutState.toStrong()
            var state = stateAttribute.value
            state.contentOffset = offset
            state.contentOffsetMode = .system
            state.contentOffsetSeed.value &+= 1
            stateAttribute.setValue(state, transaction: Transaction.current)
        }
    }

    func dispatchScrollGesturePhase(_ gesturePhase: GesturePhase<ScrollGesture.Value>) {
        graphRef.withCurrent {
            guard let graph = _AGGraph.current,
                  layoutState.isValid(in: graph) else {
                return
            }
            let currentOffset = layoutState.toStrong().value.contentOffset
            switch gesturePhase {
            case .possible(.none):
                return
            case .possible(.some(let value)), .active(let value):
                let translation: CGSize
                let velocity: _Velocity<CGSize>
                switch value {
                case .pan(let pan):
                    translation = pan.translation
                    velocity = pan.velocity
                case .wheel(let wheel):
                    translation = wheel
                    velocity = _Velocity(valuePerSecond: .zero)
                }

                decelerationState = nil
                var drag = dragState ?? DragState(
                    initialOffset: currentOffset,
                    translation: .zero
                )
                drag.translation = translation
                dragState = drag
                // Gesture translation follows the pointer; content offset moves
                // in the opposite direction as if the content were being dragged.
                let nextOffset = interactiveContentOffset(CGPoint(
                    x: drag.initialOffset.x - translation.width,
                    y: drag.initialOffset.y - translation.height
                ))
                let moved = nextOffset != currentOffset
                publishInteraction(
                    offset: nextOffset,
                    phase: moved ? .interacting : .tracking,
                    velocity: velocity
                )

            case .ended(let value):
                let velocity: _Velocity<CGSize>
                let eventTime: Time?
                switch value {
                case .pan(let pan):
                    velocity = pan.velocity
                    eventTime = pan.timestamp
                case .wheel:
                    velocity = _Velocity(valuePerSecond: .zero)
                    eventTime = nil
                }
                let originalOffset = dragState?.initialOffset ?? currentOffset
                dragState = nil
                // Deceleration evolves content-space offset, so convert the
                // pointer-space terminal velocity before starting the simulation.
                let contentVelocity = velocity.map {
                    CGSize(width: -$0.width, height: -$0.height)
                }
                let boundedOffset = clampedContentOffset(currentOffset)
                var simulation = makeDeceleration(
                    offset: currentOffset,
                    velocity: contentVelocity
                )
                let targetOffsetState = makeTargetOffsetState(
                    from: currentOffset,
                    originalOffset: originalOffset,
                    velocity: contentVelocity
                )
                let behaviorTarget = targetOffsetState?.resolvedOffset
                simulation.updateTarget(behaviorTarget)
                if contentVelocity.valuePerSecond != .zero
                    || currentOffset != boundedOffset
                    || (behaviorTarget != nil && behaviorTarget != currentOffset) {
                    decelerationState = DecelerationState(
                        simulation: simulation,
                        // Gesture timestamps use event time, while inertial
                        // presentation advances on ViewGraph animation time.
                        beginTime: (graphRef.context as? ViewGraph)?.currentTimestamp
                            ?? eventTime,
                        targetOffsetState: targetOffsetState
                    )
                    publishInteraction(
                        offset: currentOffset,
                        phase: .decelerating,
                        velocity: contentVelocity
                    )
                    scheduleMotionUpdate()
                } else {
                    decelerationState = nil
                    publishInteraction(
                        offset: currentOffset,
                        phase: .idle,
                        velocity: velocity
                    )
                }

            case .failed:
                dragState = nil
                decelerationState = nil
                publishInteraction(
                    offset: currentOffset,
                    phase: .idle,
                    velocity: _Velocity(valuePerSecond: .zero)
                )
            }
        }
    }

    @discardableResult
    func updateMotion(at time: Time) -> Bool {
        guard var decelerationState else {
            return false
        }
        let elapsed: Double
        if let beginTime = decelerationState.beginTime {
            elapsed = max(time.seconds - beginTime.seconds, 0)
        } else {
            decelerationState.beginTime = time
            elapsed = 0
        }
        let maximum = maximumContentOffset()
        let completed = decelerationState.simulation.iter(
            elapsed,
            minValue: .zero,
            maxValue: maximum
        )
        let offset = decelerationState.simulation.offset
        let velocity = decelerationState.simulation.velocity
        if completed {
            self.decelerationState = nil
            publishInteraction(
                offset: offset,
                phase: .idle,
                velocity: _Velocity(valuePerSecond: .zero)
            )
        } else {
            self.decelerationState = decelerationState
            publishInteraction(
                offset: offset,
                phase: .decelerating,
                velocity: velocity
            )
            scheduleMotionUpdate()
        }
        return true
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        guard let context = pendingContext else {
            return offset
        }
        let visibleSize = context.containingSize.inset(by: context.safeInsets)
        let maxOffset = maximumContentOffset(
            contentSize: context.contentFrame.size,
            visibleSize: visibleSize
        )
        return CGPoint(
            x: configuration.axes.contains(.horizontal)
                ? min(max(offset.x, 0), maxOffset.x)
                : 0,
            y: configuration.axes.contains(.vertical)
                ? min(max(offset.y, 0), maxOffset.y)
                : 0
        )
    }

    /// Applies the sampled residue-based rubber-band curve only while input is
    /// directly manipulating the content. The graph state keeps this
    /// presentation offset so the terminal deceleration can spring back from
    /// the exact visible position instead of jumping to the nearest bound.
    private func interactiveContentOffset(_ offset: CGPoint) -> CGPoint {
        guard let context = pendingContext else {
            return offset
        }
        let visibleSize = context.containingSize.inset(by: context.safeInsets)
        let maximum = maximumContentOffset(
            contentSize: context.contentFrame.size,
            visibleSize: visibleSize
        )
        let clamped = clampedContentOffset(offset)
        var residue = CGSize(
            width: clamped.x - offset.x,
            height: clamped.y - offset.y
        )
        if !permitsBounce(axis: .horizontal, maximumOffset: maximum.x) {
            residue.width = 0
        }
        if !permitsBounce(axis: .vertical, maximumOffset: maximum.y) {
            residue.height = 0
        }
        let rubberBand = _scrollViewAddRubberBandingToResidue(
            residue,
            range: visibleSize
        )
        return CGPoint(
            x: clamped.x - rubberBand.width,
            y: clamped.y - rubberBand.height
        )
    }

    private func permitsBounce(axis: Axis, maximumOffset: CGFloat) -> Bool {
        let axisSet: Axis.Set = axis == .horizontal ? .horizontal : .vertical
        guard configuration.axes.contains(axisSet) else {
            return false
        }
        let role = axis == .horizontal
            ? properties.horizontalBounceBehavior
            : properties.verticalBounceBehavior
        switch role.rawValue {
        case 0, 1: // automatic, always
            return true
        case 2: // basedOnSize
            return maximumOffset > 0
        default:
            return false
        }
    }

    private func makeDeceleration(
        offset: CGPoint,
        velocity: _Velocity<CGSize>
    ) -> Deceleration2D {
        let maximum = maximumContentOffset()
        var value = velocity.valuePerSecond
        if !permitsBounce(axis: .horizontal, maximumOffset: maximum.x) {
            value.width = maximum.x > 0 ? value.width : 0
        }
        if !permitsBounce(axis: .vertical, maximumOffset: maximum.y) {
            value.height = maximum.y > 0 ? value.height : 0
        }
        return Deceleration2D(
            time: 0,
            offset: CGSize(width: offset.x, height: offset.y),
            velocity: _Velocity(valuePerSecond: value),
            drag: min(max(1 - resolvedDecelerationRate, 0), 1),
            bounceStiffness: 100,
            bounceDrag: 17,
            stoppedVelocity: _Velocity(valuePerSecond: CGFloat(2.5))
        )
    }

    /// Resolves the native-style projected offset through the graph-owned target
    /// behavior before the local deceleration simulation takes ownership.
    private func makeTargetOffsetState(
        from offset: CGPoint,
        originalOffset: CGPoint,
        velocity: _Velocity<CGSize>
    ) -> TargetOffsetState? {
        let rate = resolvedDecelerationRate
        let proposedOffset = clampedContentOffset(CGPoint(
            x: offset.x + _scrollViewProjectedDecelerationDistance(
                velocity: Double(velocity.valuePerSecond.width),
                decelerationRate: rate
            ),
            y: offset.y + _scrollViewProjectedDecelerationDistance(
                velocity: Double(velocity.valuePerSecond.height),
                decelerationRate: rate
            )
        ))
        guard let resolvedOffset = targetContentOffset(
            proposedOffset,
            originalOffset: originalOffset,
            velocity: velocity,
            geometryOffset: offset
        ) else {
            return nil
        }
        return TargetOffsetState(
            proposedOffset: proposedOffset,
            originalOffset: originalOffset,
            velocity: velocity,
            resolvedOffset: resolvedOffset
        )
    }

    private func targetContentOffset(
        _ proposedOffset: CGPoint,
        originalOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        geometryOffset: CGPoint
    ) -> CGPoint? {
        guard let behavior = properties.scrollBehavior,
              !configuration.axes.isEmpty,
              let context = pendingContext else {
            return nil
        }

        let geometry = ScrollGeometry(
            contentOffset: geometryOffset,
            contentSize: context.contentFrame.size,
            contentInsets: context.safeInsets,
            containerSize: context.containingSize
        )
        let insetOrigin = CGPoint(
            x: context.safeInsets.leading,
            y: context.safeInsets.top
        )
        func target(at offset: CGPoint) -> ScrollTarget {
            ScrollTarget(rect: CGRect(
                origin: CGPoint(
                    x: offset.x + insetOrigin.x,
                    y: offset.y + insetOrigin.y
                ),
                size: geometry.containerSize
            ))
        }

        var resolvedTarget = target(at: proposedOffset)
        let targetContext = ScrollTargetBehaviorContext(
            originalTarget: target(at: originalOffset),
            velocity: CGVector(
                dx: velocity.valuePerSecond.width,
                dy: velocity.valuePerSecond.height
            ),
            geometry: geometry,
            axes: configuration.axes,
            decelerationRate: properties.decelerationRate,
            environment: environment
        )
        Update.ensure {
            behavior.updateTarget(&resolvedTarget, context: targetContext)
        }
        return clampedContentOffset(CGPoint(
            x: resolvedTarget.rect.minX - insetOrigin.x,
            y: resolvedTarget.rect.minY - insetOrigin.y
        ))
    }

    /// Layout can change collection frames while inertial motion is active. Keep
    /// the platform-proposed candidate and terminal velocity stable, and only
    /// replace the simulation target when the resolved behavior output changes.
    private func retargetContentOffsetIfNeeded() {
        guard var decelerationState,
              var targetOffsetState = decelerationState.targetOffsetState,
              let context = pendingContext,
              let resolvedOffset = targetContentOffset(
                  targetOffsetState.proposedOffset,
                  originalOffset: targetOffsetState.originalOffset,
                  velocity: targetOffsetState.velocity,
                  geometryOffset: context.contentOffset
              ),
              resolvedOffset != targetOffsetState.resolvedOffset else {
            return
        }
        decelerationState.simulation.updateTarget(resolvedOffset)
        targetOffsetState.resolvedOffset = resolvedOffset
        decelerationState.targetOffsetState = targetOffsetState
        self.decelerationState = decelerationState
    }

    private func maximumContentOffset() -> CGPoint {
        guard let context = pendingContext else {
            return .zero
        }
        return maximumContentOffset(
            contentSize: context.contentFrame.size,
            visibleSize: context.containingSize.inset(by: context.safeInsets)
        )
    }

    private func maximumContentOffset(
        contentSize: CGSize,
        visibleSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: configuration.axes.contains(.horizontal)
                ? max(contentSize.width - visibleSize.width, 0)
                : 0,
            y: configuration.axes.contains(.vertical)
                ? max(contentSize.height - visibleSize.height, 0)
                : 0
        )
    }

    private var resolvedDecelerationRate: Double {
        switch properties.decelerationRate {
        case .fast, .viewAligned, .paging:
            _ScrollViewConfig.decelerationRateFast
        default:
            _ScrollViewConfig.decelerationRateNormal
        }
    }

    private func scheduleMotionUpdate() {
        guard let viewGraph = graphRef.context as? ViewGraph else {
            return
        }
        viewGraph.nextUpdate.views.interval(1.0 / 60.0)
    }

    private func publishInteraction(
        offset: CGPoint,
        phase: ScrollPhase,
        velocity: _Velocity<CGSize>
    ) {
        guard let graph = _AGGraph.current,
              layoutState.isValid(in: graph) else {
            return
        }
        let stateAttribute = layoutState.toStrong()
        var state = stateAttribute.value
        state.contentOffset = offset
        state.contentOffsetMode = .system
        state.contentOffsetSeed.value &+= 1

        var transaction = Transaction.current
        // Only direct manipulation is continuous. Inertial samples remain
        // scroll-originated but form discrete frame updates.
        transaction.isContinuous = phase == .tracking || phase == .interacting
        transaction.fromScrollView = true
        stateAttribute.setValue(state, transaction: transaction)

        guard phaseState.isValid(in: graph) else {
            return
        }
        let phaseAttribute = phaseState.toStrong()
        let value = ScrollPhaseState(
            phase: phase,
            velocity: CGVector(
                dx: velocity.valuePerSecond.width,
                dy: velocity.valuePerSecond.height
            )
        )
        if phaseAttribute.value != value {
            phaseAttribute.setValue(value, transaction: transaction)
        }
    }

    private func publishPhase(
        _ phase: ScrollPhase,
        velocity: _Velocity<CGSize>
    ) {
        guard let graph = _AGGraph.current,
              phaseState.isValid(in: graph) else {
            return
        }
        let phaseAttribute = phaseState.toStrong()
        let value = ScrollPhaseState(
            phase: phase,
            velocity: CGVector(
                dx: velocity.valuePerSecond.width,
                dy: velocity.valuePerSecond.height
            )
        )
        if phaseAttribute.value != value {
            phaseAttribute.setValue(value, transaction: Transaction.current)
        }
    }
}

/// Resolves the default anchor fallback once per axes/anchor input revision.
struct ScrollViewDefaultAnchors: StatefulRule {
    typealias Value = ScrollAnchorStorage

    var _configuration: Attribute<ScrollViewConfiguration>
    var _anchors: Attribute<ScrollAnchorStorage>
    var oldAnchors: ScrollAnchorStorage
    var oldAxes: Axis.Set

    init(
        _configuration: Attribute<ScrollViewConfiguration>,
        _anchors: Attribute<ScrollAnchorStorage>,
        oldAnchors: ScrollAnchorStorage = ScrollAnchorStorage(),
        oldAxes: Axis.Set = []
    ) {
        self._configuration = _configuration
        self._anchors = _anchors
        self.oldAnchors = oldAnchors
        self.oldAxes = oldAxes
    }

    mutating func updateValue() {
        var anchors = _anchors.value
        let axes = _configuration.value.axes
        if anchors.defaultValue == nil {
            anchors.defaultValue = Self.defaultValue(axes: axes)
        }
        let bothAxes: Axis.Set = [.horizontal, .vertical]
        if !_SemanticFeature<Semantics_v8>.isEnabled,
           axes == bothAxes,
           anchors.anchors[.alignment] == nil {
            anchors.anchors[.alignment] = .center
        }
        if _AGGraph.currentStatefulOutput(ScrollAnchorStorage.self) == nil
            || oldAnchors != anchors
            || oldAxes != axes {
            _AGGraph.setStatefulOutput(anchors)
        }
        oldAnchors = anchors
        oldAxes = axes
    }

    static func defaultValue(axes: Axis.Set) -> UnitPoint {
        let bothAxes: Axis.Set = [.horizontal, .vertical]
        if axes == bothAxes {
            return _SemanticFeature<Semantics_v5>.isEnabled ? .topLeading : .center
        }
        if axes == .horizontal {
            return .leading
        }
        return .top
    }
}

/// Resolves target-behavior properties against only the environment values read by
/// the behavior's properties callback.
struct ScrollViewAdjustedBehaviorProperties: StatefulRule {
    typealias Value = ScrollTargetBehaviorProperties

    var _configuration: Attribute<ScrollViewConfiguration>
    var _environment: Attribute<EnvironmentValues>
    var _storage: Attribute<ScrollEnvironmentStorage>
    var tracker: _PropertyListTracker
    var oldBehavior: ResolvedScrollBehavior?
    var oldAxes: Axis.Set

    init(
        _configuration: Attribute<ScrollViewConfiguration>,
        _environment: Attribute<EnvironmentValues>,
        _storage: Attribute<ScrollEnvironmentStorage>,
        tracker: _PropertyListTracker = _PropertyListTracker(),
        oldBehavior: ResolvedScrollBehavior? = nil,
        oldAxes: Axis.Set = []
    ) {
        self._configuration = _configuration
        self._environment = _environment
        self._storage = _storage
        self.tracker = tracker
        self.oldBehavior = oldBehavior
        self.oldAxes = oldAxes
    }

    mutating func updateValue() {
        let environment = _environment.value
        let behavior = _storage.value.properties.scrollBehavior
        let axes = _configuration.value.axes
        let environmentChanged = tracker.hasDifferentUsedValues(environment._plist)
        guard _AGGraph.currentStatefulOutput(ScrollTargetBehaviorProperties.self) == nil
                || behavior != oldBehavior
                || axes != oldAxes
                || environmentChanged else {
            return
        }

        tracker.reset()
        let trackedEnvironment = EnvironmentValues(environment._plist, tracker: tracker)
        let properties = behavior?.base.properties(context: .init(
            environment: trackedEnvironment,
            axes: axes
        )) ?? ScrollTargetBehaviorProperties()
        _AGGraph.setStatefulOutput(properties)
        oldBehavior = behavior
        oldAxes = axes
    }
}

/// Applies the configuration and inherited environment to the platform-facing
/// scroll properties without changing target-behavior ownership.
struct ScrollViewAdjustedProperties: Rule {
    typealias Value = ScrollEnvironmentProperties

    var _configuration: Attribute<ScrollViewConfiguration>
    var _scrollStorage: Attribute<ScrollEnvironmentStorage>
    var _behaviorProperties: Attribute<ScrollTargetBehaviorProperties>
    var _layoutDirection: Attribute<LayoutDirection>
    var _isEnabled: Attribute<Bool>
    var _isContainedInPlatter: OptionalAttribute<Bool>

    var value: ScrollEnvironmentProperties {
        let configuration = _configuration.value
        var properties = _scrollStorage.value.properties
        properties.layoutDirection = _layoutDirection.value
        properties.isEnabled = _isEnabled.value && (configuration.isScrollEnabled ?? true)
        if !properties.isEnabled {
            properties.verticalBounceBehavior = ScrollBounceBehavior.Role(rawValue: 3)
            properties.horizontalBounceBehavior = ScrollBounceBehavior.Role(rawValue: 3)
        } else {
            if !configuration.axes.contains(.vertical),
               properties.verticalBounceBehavior.rawValue == ScrollBounceBehavior.automatic.role.rawValue {
                properties.verticalBounceBehavior = ScrollBounceBehavior.Role(rawValue: 3)
            }
            if !configuration.axes.contains(.horizontal),
               properties.horizontalBounceBehavior.rawValue == ScrollBounceBehavior.automatic.role.rawValue {
                properties.horizontalBounceBehavior = ScrollBounceBehavior.Role(rawValue: 3)
            }
        }
        if let isContainedInPlatter = _isContainedInPlatter.attribute?.value {
            properties.isContainedInPlatter = isContainedInPlatter
        }
        _ = _behaviorProperties.value
        properties.decelerationRate = .standard
        return properties
    }
}

/// Aligns undersized content inside the scroll container along active axes.
struct ScrollViewAlignmentAdjustment: Rule {
    typealias Value = CGSize

    var _configuration: Attribute<ScrollViewConfiguration>
    var _scrollAnchors: Attribute<ScrollAnchorStorage>
    var _contentFrame: Attribute<ViewFrame>
    var _size: Attribute<ViewSize>

    var value: CGSize {
        guard _SemanticFeature<Semantics_v6>.isEnabled else {
            return .zero
        }
        let axes = _configuration.value.axes
        let anchor = _scrollAnchors.value.alignment
        let contentSize = _contentFrame.value.size.value
        let containerSize = _size.value.value
        var adjustment = CGSize.zero
        if axes.contains(.horizontal), anchor.x != 0, contentSize.width < containerSize.width {
            adjustment.width = (containerSize.width - contentSize.width) * anchor.x
        }
        if axes.contains(.vertical), anchor.y != 0, contentSize.height < containerSize.height {
            adjustment.height = (containerSize.height - contentSize.height) * anchor.y
        }
        return adjustment
    }
}

/// Adds the leading-edge free-space correction used by a horizontal RTL host.
struct ScrollViewRTLAlignmentAdjustment: Rule {
    typealias Value = CGSize

    var _configuration: Attribute<ScrollViewConfiguration>
    var _scrollAnchors: Attribute<ScrollAnchorStorage>
    var _contentFrame: Attribute<ViewFrame>
    var _size: Attribute<ViewSize>
    var _layoutDirection: Attribute<LayoutDirection>

    var value: CGSize {
        guard _SemanticFeature<Semantics_v6>.isEnabled,
              _configuration.value.axes.contains(.horizontal),
              _layoutDirection.value == .rightToLeft,
              _scrollAnchors.value.alignment.x == 0 else {
            return .zero
        }
        let contentWidth = _contentFrame.value.size.value.width
        let containerWidth = _size.value.value.width
        guard contentWidth < containerWidth else {
            return .zero
        }
        return CGSize(width: containerWidth - contentWidth, height: 0)
    }
}

/// Extends the leading/top safe area by the current undersized-content alignment.
struct ScrollViewAdjustedSafeArea: Rule {
    typealias Value = EdgeInsets

    var _safeArea: Attribute<EdgeInsets>
    var _configuration: Attribute<ScrollViewConfiguration>
    var _alignmentAdjustment: Attribute<CGSize>
    var _rtlAdjustment: Attribute<CGSize>

    var value: EdgeInsets {
        var safeArea = _safeArea.value
        guard _SemanticFeature<Semantics_v6>.isEnabled else {
            return safeArea
        }
        let axes = _configuration.value.axes
        let adjustment = _alignmentAdjustment.value
        if axes.contains(.vertical) {
            safeArea.top += adjustment.height
        }
        if axes.contains(.horizontal) {
            safeArea.leading += adjustment.width
        }
        return safeArea
    }
}

/// Preserves one hosting object for the lifetime of its graph node.
struct MakeHostingScrollView: StatefulRule {
    typealias Value = HostingScrollView

    var _layoutState: Attribute<SystemScrollLayoutState>
    var _phaseState: Attribute<ScrollPhaseState>
    var _containerSize: Attribute<CGSize>
    var graphRef: _AGGraphContext

    init(
        _layoutState: Attribute<SystemScrollLayoutState>,
        _phaseState: Attribute<ScrollPhaseState>,
        _containerSize: Attribute<CGSize>? = nil,
        graphRef: _AGGraphContext
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("MakeHostingScrollView.init requires AG context")
        }
        self._layoutState = _layoutState
        self._phaseState = _phaseState
        self._containerSize = _containerSize ?? graph.makeInput(
            value: CGSize(width: -.infinity, height: -.infinity)
        )
        self.graphRef = graphRef
    }

    init(
        _layoutState: Attribute<SystemScrollLayoutState>,
        graphRef: _AGGraphContext
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("MakeHostingScrollView.init requires AG context")
        }
        self.init(
            _layoutState: _layoutState,
            _phaseState: graph.makeInput(value: ScrollPhaseState()),
            _containerSize: nil,
            graphRef: graphRef
        )
    }

    mutating func updateValue() {
        if let existing = _AGGraph.currentStatefulOutput(HostingScrollView.self) {
            _AGGraph.setStatefulOutput(existing)
            return
        }
        _AGGraph.setStatefulOutput(HostingScrollView(
            graphRef: graphRef,
            layoutState: _layoutState.asWeak(),
            phaseState: _phaseState.asWeak(),
            containerSize: _containerSize.asWeak()
        ))
    }
}

/// Retains the logical outer platform container for one attachment lifetime.
struct UpdatedScrollViewContainer: StatefulRule {
    typealias Value = HostingScrollView.PlatformContainer

    var _scrollView: Attribute<HostingScrollView>
    var container: HostingScrollView.PlatformContainer?

    init(
        _scrollView: Attribute<HostingScrollView>,
        container: HostingScrollView.PlatformContainer? = nil
    ) {
        self._scrollView = _scrollView
        self.container = container
    }

    mutating func updateValue() {
        if container == nil {
            let scrollView = _scrollView.value
            let newContainer = HostingScrollView.PlatformContainer(
                scrollView: scrollView
            )
            scrollView.parentContainer = newContainer
            container = newContainer
        }
        guard let container else {
            fatalError("UpdatedScrollViewContainer failed to create its container")
        }
        _AGGraph.setStatefulOutput(container)
    }
}

/// Computes the framed platform-group output at the scroll attachment boundary.
struct ScrollViewDisplayListFrame: Rule {
    typealias Value = CGRect

    var _configuration: Attribute<ScrollViewConfiguration>
    var _position: Attribute<CGPoint>
    var _containerPosition: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _safeAreaInsets: Attribute<EdgeInsets>
    var _alignmentAdjustment: Attribute<CGSize>
    var _rtlAdjustment: Attribute<CGSize>
    var _layoutDirection: Attribute<LayoutDirection>
    var _pixelLength: Attribute<CGFloat>

    var value: CGRect {
        let configuration = _configuration.value
        let insets = _safeAreaInsets.value
            .in(configuration.edgesToExpandDisplayListFrame)
            .xFlipIfRightToLeft { _layoutDirection.value }
            .adding(configuration.contentInsets)
        let position = _position.value
        let containerPosition = _containerPosition.value
        let size = _size.value
        var frame = CGRect(
            x: position.x - containerPosition.x - insets.leading,
            y: position.y - containerPosition.y - insets.top,
            width: size.value.width + insets.leading + insets.trailing,
            height: size.value.height + insets.top + insets.bottom
        )
        let rtlAdjustment = _rtlAdjustment.value
        frame.origin.x -= rtlAdjustment.width
        frame.origin.y -= rtlAdjustment.height
        frame.size.width += rtlAdjustment.width
        frame.size.height += rtlAdjustment.height
        frame = frame.standardized

        var rounded = ViewFrame(
            origin: frame.origin,
            size: ViewSize(frame.size)
        )
        rounded.round(toMultipleOf: _pixelLength.value)
        return CGRect(origin: rounded.origin, size: rounded.size.value)
    }
}

/// Replaces child display output with one stable logical platform-group item.
struct ScrollViewDisplayList: Rule {
    typealias Value = DisplayList

    var identity: _DisplayList_Identity
    var _scrollView: Attribute<HostingScrollView>
    var _frame: Attribute<CGRect>
    var _contentList: OptionalAttribute<DisplayList>

    var value: DisplayList {
        let contents = _contentList.attribute?.value ?? DisplayList()
        guard let container = _scrollView.value.parentContainer else {
            return contents
        }

        var item = DisplayList.Item(
            effect: .platformGroup(container),
            contents: contents,
            frame: _frame.value,
            identity: identity,
            version: DisplayList.Version(forUpdate: ())
        )
        item.canonicalize(options: .defaultValue)

        var result = DisplayList()
        result.items.append(item)
        result.recordInterpolationBounds(item.frame)
        result.numericValue = contents.numericValue
        return result
    }
}

private struct TrivialContentResponder: ContentResponder {
}

/// Responder mounted at the same logical platform-group boundary as display output.
final class HostingScrollViewResponder: MultiViewResponder, ResponderEventConsumer {
    private struct PanSession {
        var eventID: EventID?
        var wasActive = false
        var lastTranslation = CGSize.zero
        var lastTime = Time.zero
        var lastValue = PanGesture.Value(
            timestamp: .zero,
            translation: .zero,
            touchType: .indirect,
            velocity: _Velocity(valuePerSecond: .zero)
        )

        mutating func reset() {
            eventID = nil
            wasActive = false
            lastTranslation = .zero
            lastTime = .zero
        }
    }

    fileprivate var helper = ContentResponderHelper<TrivialContentResponder>()
    weak var representedView: HostingScrollView.PlatformGroupContainer?
    weak var hostContainer: HostingScrollView.PlatformContainer?
    let layoutResponder: DefaultLayoutViewResponder
    private var panSession = PanSession()

    init(layoutResponder: DefaultLayoutViewResponder) {
        self.layoutResponder = layoutResponder
        super.init()
        layoutResponder.parent = self
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
    }

    override func addContentPath(
        to path: inout Path,
        kind: ContentShapeKinds,
        in coordinateSpace: CoordinateSpace,
        observer: (any ContentPathObserver)?
    ) {
        helper.addContentPath(
            to: &path,
            kind: kind,
            in: coordinateSpace,
            observer: observer
        )
    }

    override func addObserver(_ observer: any ContentPathObserver) {
        helper.observers.add(observer: observer)
    }

    override var features: Features {
        var features = super.features
        features.insert(.platformViews)
        return features
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        guard let scrollView = hostContainer?.scrollView,
              scrollView.properties.isEnabled,
              scrollView.configuration.isScrollEnabled ?? true,
              !scrollView.configuration.axes.isEmpty else {
            return false
        }
        return eventType == SystemWheelEvent.self || eventType == ScrollEvent.self
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void> {
        guard let scrollView = hostContainer?.scrollView else {
            panSession.reset()
            return .failed
        }
        guard scrollView.properties.isEnabled,
              scrollView.configuration.isScrollEnabled ?? true,
              !scrollView.configuration.axes.isEmpty else {
            panSession.reset()
            scrollView.dispatchScrollGesturePhase(.failed)
            return .failed
        }

        var phases: [GesturePhase<Void>] = []
        for (eventID, event) in events.sorted(by: { $0.key.serial < $1.key.serial }) {
            if let wheel = event as? SystemWheelEvent {
                let phase: GesturePhase<ScrollGesture.Value>
                switch wheel.phase {
                case .began, .active:
                    phase = .active(.wheel(wheel.delta))
                case .ended:
                    phase = .ended(.wheel(wheel.delta))
                case .failed:
                    phase = .failed
                }
                scrollView.dispatchScrollGesturePhase(phase)
                phases.append(phase.map { _ in () })
            } else if let event = event as? ScrollEvent {
                let phase = consumePanEvent(
                    event,
                    id: eventID,
                    axes: scrollView.configuration.axes,
                    at: time
                )
                scrollView.dispatchScrollGesturePhase(phase)
                phases.append(phase.map { _ in () })
            }
        }

        if phases.contains(where: { $0.isActive }) { return .active(()) }
        if phases.contains(where: { $0.isEnded }) { return .ended(()) }
        if !phases.isEmpty && phases.allSatisfy({ $0.isFailed }) { return .failed }
        return .possible(nil)
    }

    private func consumePanEvent(
        _ event: ScrollEvent,
        id eventID: EventID,
        axes: Axis.Set,
        at time: Time
    ) -> GesturePhase<ScrollGesture.Value> {
        switch event.phase {
        case .began:
            panSession.reset()
            panSession.eventID = eventID
            return .possible(nil)

        case .active:
            guard panSession.eventID == eventID else {
                panSession.reset()
                return .failed
            }
            let translation = event.translation
            guard panSession.wasActive || acceptsPan(
                translation: translation,
                minimumDistance: 10,
                axes: axes
            ) else {
                return .possible(nil)
            }
            let elapsed = time.seconds - panSession.lastTime.seconds
            let delta = CGSize(
                width: translation.width - panSession.lastTranslation.width,
                height: translation.height - panSession.lastTranslation.height
            )
            let velocity: CGSize
            if panSession.wasActive, elapsed.isFinite, elapsed > 0 {
                velocity = CGSize(
                    width: delta.width / elapsed,
                    height: delta.height / elapsed
                )
            } else {
                velocity = delta
            }
            let value = PanGesture.Value(
                timestamp: time,
                translation: translation,
                touchType: event.touchType,
                velocity: _Velocity(valuePerSecond: velocity)
            )
            panSession.wasActive = true
            panSession.lastTranslation = translation
            panSession.lastTime = time
            panSession.lastValue = value
            return .active(.pan(value))

        case .ended:
            guard panSession.eventID == eventID, panSession.wasActive else {
                panSession.reset()
                return .failed
            }
            let value = PanGesture.Value(
                timestamp: time,
                translation: event.translation,
                touchType: event.touchType,
                velocity: panSession.lastValue.velocity
            )
            panSession.reset()
            return .ended(.pan(value))

        case .failed:
            panSession.reset()
            return .failed
        }
    }

    private func acceptsPan(
        translation: CGSize,
        minimumDistance: CGFloat,
        axes: Axis.Set
    ) -> Bool {
        guard hypot(translation.width, translation.height) >= minimumDistance else {
            return false
        }
        if abs(translation.width) >= abs(translation.height) {
            return axes.contains(.horizontal)
        }
        return axes.contains(.vertical)
    }
}

/// Retains one scroll responder and reconnects its geometry and child responders.
struct ScrollViewResponder: StatefulRule {
    typealias Value = [ViewResponder]

    var _scrollView: Attribute<HostingScrollView>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _children: Attribute<[ViewResponder]>
    var _responder: HostingScrollViewResponder?
    var layoutResponder: DefaultLayoutViewResponder

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        if _responder == nil {
            _responder = HostingScrollViewResponder(
                layoutResponder: layoutResponder
            )
        }
        guard let responder = _responder else {
            fatalError("ScrollViewResponder failed to create its responder")
        }

        let scrollView = _scrollView.value
        responder.representedView = scrollView.host
        responder.hostContainer = scrollView.parentContainer
        scrollView.responder = responder
        responder.helper.update(
            data: (
                value: TrivialContentResponder(),
                changed: isInitialValue
            ),
            size: (
                value: _size.value,
                changed: _AGGraph.currentStatefulInputChanged(_size.identifier)
            ),
            position: (
                value: _position.value,
                changed: _AGGraph.currentStatefulInputChanged(_position.identifier)
            ),
            transform: (
                value: _transform.value,
                changed: _AGGraph.currentStatefulInputChanged(_transform.identifier)
            ),
            parent: responder
        )
        if isInitialValue
            || _AGGraph.currentStatefulInputChanged(_children.identifier) {
            responder.children = _children.value
        }
        _AGGraph.setStatefulOutput([responder])
    }
}

/// Applies configuration-dependent insets while retaining host-originated state.
struct ScrollViewAdjustedState: StatefulRule {
    typealias Value = SystemScrollLayoutState

    var _size: Attribute<ViewSize>
    var _configuration: Attribute<ScrollViewConfiguration>
    var _defaultAnchors: Attribute<ScrollAnchorStorage>
    var _state: Attribute<SystemScrollLayoutState>
    var _phaseState: Attribute<ScrollPhaseState>
    var _contentFrame: Attribute<ViewFrame>
    var _pixelLength: Attribute<CGFloat>
    var _phase: Attribute<_GraphInputs.Phase>
    var _transaction: Attribute<Transaction>
    var _layoutDirection: Attribute<LayoutDirection>
    var _positionBinding: Binding<ScrollPosition>?

    var oldFrame: CGRect
    var oldSize: CGSize
    var oldOffset: CGPoint
    var hasScrolled: Bool
    var resetSeed: UInt32
    var _lastUpdateSeed: MutableBox<UInt32>

    init(
        _size: Attribute<ViewSize>,
        _configuration: Attribute<ScrollViewConfiguration>,
        _defaultAnchors: Attribute<ScrollAnchorStorage>,
        _state: Attribute<SystemScrollLayoutState>,
        _phaseState: Attribute<ScrollPhaseState>,
        _contentFrame: Attribute<ViewFrame>,
        _pixelLength: Attribute<CGFloat>,
        _phase: Attribute<_GraphInputs.Phase>,
        _transaction: Attribute<Transaction>,
        _layoutDirection: Attribute<LayoutDirection>,
        _positionBinding: Binding<ScrollPosition>? = nil,
        oldFrame: CGRect = .zero,
        oldSize: CGSize = .zero,
        oldOffset: CGPoint = .zero,
        hasScrolled: Bool = false,
        resetSeed: UInt32 = 0,
        _lastUpdateSeed: MutableBox<UInt32> = MutableBox(0)
    ) {
        self._size = _size
        self._configuration = _configuration
        self._defaultAnchors = _defaultAnchors
        self._state = _state
        self._phaseState = _phaseState
        self._contentFrame = _contentFrame
        self._pixelLength = _pixelLength
        self._phase = _phase
        self._transaction = _transaction
        self._layoutDirection = _layoutDirection
        self._positionBinding = _positionBinding
        self.oldFrame = oldFrame
        self.oldSize = oldSize
        self.oldOffset = oldOffset
        self.hasScrolled = hasScrolled
        self.resetSeed = resetSeed
        self._lastUpdateSeed = _lastUpdateSeed
    }

    mutating func updateValue() {
        let previous = _AGGraph.currentStatefulOutput(SystemScrollLayoutState.self)
        let stateChanged = _AGGraph.currentStatefulInputChanged(_state.identifier)
        var state = _state.value
        let inputOffset = state.contentOffset
        let stateChangedInSystemMode: Bool
        if case .system = state.contentOffsetMode {
            stateChangedInSystemMode = stateChanged
        } else {
            stateChangedInSystemMode = false
        }
        let configuration = _configuration.value
        state.contentInsets = configuration.contentInsets

        let rawSize = _size.value.value
        let contentFrameValue = _contentFrame.value
        let frame = CGRect(
            origin: contentFrameValue.origin,
            size: contentFrameValue.size.value
        )
        let phaseState = _phaseState.value
        let currentResetSeed = _phase.value.resetSeed
        let defaultAnchors = _defaultAnchors.value
        let pixelLength = _pixelLength.value
        let transaction = _transaction.value
        let layoutDirection = _layoutDirection.value
        let position = _positionBinding?.wrappedValue
        var adjustmentReason: ContentOffsetAdjustmentReason?
        var didReset = false

        if previous == nil || resetSeed != currentResetSeed {
            if let positionOffset = position?.initialContentOffset(
                containerSize: rawSize,
                contentFrame: frame,
                axes: configuration.axes,
                layoutDirection: layoutDirection
            ) {
                state.contentOffset = positionOffset
                adjustmentReason = .resetPosition
            } else {
                state.contentOffset = Self.initialOffset(
                    containerSize: rawSize,
                    contentFrame: frame,
                    axes: configuration.axes,
                    anchors: defaultAnchors,
                    layoutDirection: layoutDirection
                )
                adjustmentReason = .reset
            }
            resetSeed = currentResetSeed
            oldFrame = .zero
            oldSize = .zero
            oldOffset = .zero
            hasScrolled = false
            didReset = true
        }

        let systemInsets = state.systemContentInsets
        let size = CGSize(
            width: rawSize.width - systemInsets.leading - systemInsets.trailing,
            height: rawSize.height - systemInsets.top - systemInsets.bottom
        )
        let geometryChanged = oldSize != size || oldFrame != frame
        var didAdjust = false
        if geometryChanged && !transaction.scrollContentOffsetAdjustmentBehavior
            .disablesContentOffsetAdjustment {
            let alignHorizontal = configuration.axes != .horizontal || !defaultAnchors.isEmpty
            let alignVertical = configuration.axes != .vertical || !defaultAnchors.isEmpty

            if alignHorizontal {
                didAdjust = Self.alignIfNeeded(
                    &state.contentOffset,
                    axis: .horizontal,
                    newSize: size,
                    newContentFrame: frame,
                    anchors: defaultAnchors,
                    layoutDirection: layoutDirection,
                    oldFrame: oldFrame,
                    oldSize: oldSize,
                    oldOffset: oldOffset,
                    hasScrolled: hasScrolled,
                    pixelLength: pixelLength
                )
            }
            if alignVertical {
                didAdjust = Self.alignIfNeeded(
                    &state.contentOffset,
                    axis: .vertical,
                    newSize: size,
                    newContentFrame: frame,
                    anchors: defaultAnchors,
                    layoutDirection: layoutDirection,
                    oldFrame: oldFrame,
                    oldSize: oldSize,
                    oldOffset: oldOffset,
                    hasScrolled: hasScrolled,
                    pixelLength: pixelLength
                ) || didAdjust
            }
            if didAdjust {
                adjustmentReason = .alignment
            }
        }

        oldFrame = frame
        oldSize = size
        hasScrolled = hasScrolled
            || phaseState.isScrolling
            || (transaction.fromScrollView && stateChanged)

        let offsetChanged = inputOffset != state.contentOffset
        var didUpdateOffset = false
        if offsetChanged, let adjustmentReason {
            _lastUpdateSeed.value &+= 1
            state.updateContentOffset(
                mode: .adjustment(reason: adjustmentReason),
                updateSeed: _lastUpdateSeed.value
            )
            didUpdateOffset = true
        }
        if (stateChangedInSystemMode || didUpdateOffset), oldOffset != state.contentOffset {
            oldOffset = state.contentOffset
        }

        let contentInsetsChanged = previous?.contentInsets != state.contentInsets
        if previous == nil || stateChanged || didReset || didAdjust || contentInsetsChanged {
            _AGGraph.setStatefulOutput(state)
        }
    }

    static func initialOffset(
        containerSize: CGSize,
        contentFrame: CGRect,
        axes: Axis.Set,
        anchors: ScrollAnchorStorage,
        layoutDirection: LayoutDirection
    ) -> CGPoint {
        let anchor = anchors.adjustedAnchor(
            role: .initialOffset,
            layoutDirection: layoutDirection
        )
        var offset = CGPoint.zero
        if axes.contains(.horizontal) {
            offset.x = initialOffset(
                contentLength: contentFrame.width,
                containerLength: containerSize.width,
                anchor: anchor.x
            )
        }
        if axes.contains(.vertical) {
            offset.y = initialOffset(
                contentLength: contentFrame.height,
                containerLength: containerSize.height,
                anchor: anchor.y
            )
        }
        return offset
    }

    private static func initialOffset(
        contentLength: CGFloat,
        containerLength: CGFloat,
        anchor: CGFloat
    ) -> CGFloat {
        let anchoredOffset = contentLength * anchor - containerLength * anchor
        return min(max(anchoredOffset, 0), max(contentLength - containerLength, 0))
    }

    static func alignIfNeeded(
        _ offset: inout CGPoint,
        axis: Axis,
        newSize: CGSize,
        newContentFrame: CGRect,
        anchors: ScrollAnchorStorage,
        layoutDirection: LayoutDirection,
        oldFrame: CGRect,
        oldSize: CGSize,
        oldOffset: CGPoint,
        hasScrolled: Bool,
        pixelLength: CGFloat
    ) -> Bool {
        let initialAnchor = anchors.adjustedAnchor(
            role: .initialOffset,
            layoutDirection: layoutDirection
        )[axis]
        let sizeChangesAnchor = anchors.adjustedAnchor(
            role: .sizeChanges,
            layoutDirection: layoutDirection
        )[axis]
        let alignmentAnchor = anchors.adjustedAnchor(
            role: .alignment,
            layoutDirection: layoutDirection
        )[axis]

        let oldContentLength = oldFrame.size[axis]
        let oldContainerLength = oldSize[axis]
        let newContentLength = newContentFrame.size[axis]
        let newContainerLength = newSize[axis]
        let previousOffset = oldOffset[axis]

        if initialAnchor != 0, !hasScrolled {
            let oldSizeIsInvalid = oldSize.width == -.infinity
                && oldSize.height == -.infinity
            let contentSizeChanged = oldContentLength != newContentLength
            if oldSizeIsInvalid
                || (contentSizeChanged && _SemanticFeature<Semantics_v6>.isEnabled) {
                return applyAlignedOffset(
                    &offset,
                    axis: axis,
                    contentLength: newContentLength,
                    containerLength: newContainerLength,
                    anchor: initialAnchor,
                    previousOffset: previousOffset,
                    pixelLength: pixelLength
                )
            }
        }

        if alignmentAnchor != 0, oldContentLength < oldContainerLength {
            return applyAlignedOffset(
                &offset,
                axis: axis,
                contentLength: newContentLength,
                containerLength: newContainerLength,
                anchor: alignmentAnchor,
                previousOffset: previousOffset,
                pixelLength: pixelLength
            )
        }

        let oldAnchoredOffset = clampedAnchorOffset(
            contentLength: oldContentLength,
            containerLength: oldContainerLength,
            anchor: sizeChangesAnchor
        )
        if sizeChangesAnchor != 0,
           abs(previousOffset - oldAnchoredOffset) < 0.5 {
            return applyAlignedOffset(
                &offset,
                axis: axis,
                contentLength: newContentLength,
                containerLength: newContainerLength,
                anchor: sizeChangesAnchor,
                previousOffset: previousOffset,
                pixelLength: pixelLength
            )
        }

        if oldContentLength < oldContainerLength,
           oldContentLength > 0,
           sizeChangesAnchor == 0.5 {
            setAxisValue(0, in: &offset, axis: axis)
            roundAxisValue(in: &offset, axis: axis, pixelLength: pixelLength)
            return abs(previousOffset - offset[axis]) >= 0.5
        }
        return false
    }

    private static func applyAlignedOffset(
        _ offset: inout CGPoint,
        axis: Axis,
        contentLength: CGFloat,
        containerLength: CGFloat,
        anchor: CGFloat,
        previousOffset: CGFloat,
        pixelLength: CGFloat
    ) -> Bool {
        setAxisValue(
            clampedAnchorOffset(
                contentLength: contentLength,
                containerLength: containerLength,
                anchor: anchor
            ),
            in: &offset,
            axis: axis
        )
        roundAxisValue(in: &offset, axis: axis, pixelLength: pixelLength)
        return abs(previousOffset - offset[axis]) >= 0.5
    }

    private static func clampedAnchorOffset(
        contentLength: CGFloat,
        containerLength: CGFloat,
        anchor: CGFloat
    ) -> CGFloat {
        let anchored = contentLength * anchor - containerLength * anchor
        return min(max(anchored, 0), max(contentLength - containerLength, 0))
    }

    private static func roundAxisValue(
        in offset: inout CGPoint,
        axis: Axis,
        pixelLength: CGFloat
    ) {
        let value = offset[axis] + pixelLength * 0.5
        let rounded = pixelLength == 1
            ? floor(value)
            : floor(value / pixelLength) * pixelLength
        setAxisValue(rounded, in: &offset, axis: axis)
    }

    private static func setAxisValue(
        _ value: CGFloat,
        in point: inout CGPoint,
        axis: Axis
    ) {
        switch axis {
        case .horizontal:
            point.x = value
        case .vertical:
            point.y = value
        }
    }
}

private extension CGPoint {
    subscript(axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: x
        case .vertical: y
        }
    }
}

private extension CGSize {
    subscript(axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: width
        case .vertical: height
        }
    }
}

private extension UnitPoint {
    subscript(axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: x
        case .vertical: y
        }
    }
}

/// Pushes the adjusted graph state and current geometry into the hosting carrier.
struct UpdatedHostingScrollView: StatefulRule {
    typealias Value = HostingScrollView

    var _descendantScrollViewsAxes: OptionalAttribute<Axis.Set?>
    var _container: OptionalAttribute<HostingScrollView.PlatformContainer>
    var _scrollView: Attribute<HostingScrollView>
    var _configuration: Attribute<ScrollViewConfiguration>
    var _properties: Attribute<ScrollEnvironmentProperties>
    var _contentFrame: Attribute<ViewFrame>
    var _size: Attribute<CGSize>
    var _safeAreaInsets: Attribute<EdgeInsets>
    var _rtlAdjustment: Attribute<CGSize>
    var _adjustedState: Attribute<SystemScrollLayoutState>
    var _environment: Attribute<EnvironmentValues>
    var lastUpdateSeed: VersionSeed
    var tracker: _PropertyListTracker
    var oldProperties: ScrollEnvironmentProperties
    var oldMargins: ContentMarginProxy

    init(
        _descendantScrollViewsAxes: OptionalAttribute<Axis.Set?> = OptionalAttribute(),
        _container: OptionalAttribute<HostingScrollView.PlatformContainer> = OptionalAttribute(),
        _scrollView: Attribute<HostingScrollView>,
        _configuration: Attribute<ScrollViewConfiguration>,
        _properties: Attribute<ScrollEnvironmentProperties>,
        _contentFrame: Attribute<ViewFrame>,
        _size: Attribute<CGSize>,
        _safeAreaInsets: Attribute<EdgeInsets>,
        _rtlAdjustment: Attribute<CGSize>,
        _adjustedState: Attribute<SystemScrollLayoutState>,
        _environment: Attribute<EnvironmentValues>,
        lastUpdateSeed: VersionSeed = VersionSeed(),
        tracker: _PropertyListTracker = _PropertyListTracker(),
        oldProperties: ScrollEnvironmentProperties = ScrollEnvironmentProperties(),
        oldMargins: ContentMarginProxy = ContentMarginProxy()
    ) {
        self._descendantScrollViewsAxes = _descendantScrollViewsAxes
        self._container = _container
        self._scrollView = _scrollView
        self._configuration = _configuration
        self._properties = _properties
        self._contentFrame = _contentFrame
        self._size = _size
        self._safeAreaInsets = _safeAreaInsets
        self._rtlAdjustment = _rtlAdjustment
        self._adjustedState = _adjustedState
        self._environment = _environment
        self.lastUpdateSeed = lastUpdateSeed
        self.tracker = tracker
        self.oldProperties = oldProperties
        self.oldMargins = oldMargins
    }

    mutating func updateValue() {
        let previous = _AGGraph.currentStatefulOutput(HostingScrollView.self)
        let scrollView = _scrollView.value
        let configuration = _configuration.value
        let properties = _properties.value
        let frame = _contentFrame.value
        let state = _adjustedState.value
        let safeAreaInsets = _safeAreaInsets.value
        let rtlAdjustment = _rtlAdjustment.value
        let rawEnvironment = _environment.value
        if tracker.hasDifferentUsedValues(rawEnvironment._plist) {
            tracker.reset()
        }
        let trackedEnvironment = EnvironmentValues(rawEnvironment._plist, tracker: tracker)
        let margins = trackedEnvironment.contentMarginProxy

        if let descendantAxes = _descendantScrollViewsAxes.attribute?.value {
            scrollView.updateDescendantScrollableAxes(descendantAxes)
        }
        scrollView.updateConfiguration(configuration)
        if previous == nil || properties != oldProperties {
            scrollView.updateProperties(properties)
        }
        if previous == nil || margins != oldMargins {
            scrollView.updateContentMargins(margins)
        }
        scrollView.adoptEnvironment(trackedEnvironment)
        scrollView.updateSafeArea(
            safeAreaInsets,
            layoutDirection: properties.layoutDirection
        )
        _container.attribute?.value.updateSafeArea(
            safeAreaInsets,
            layoutDirection: properties.layoutDirection
        )
        scrollView.updateRTLAdjustment(rtlAdjustment)

        let offsetMode: SystemScrollLayoutState.ContentOffsetMode = lastUpdateSeed.matches(
            state.contentOffsetSeed
        ) ? .system : state.contentOffsetMode
        let updateIsPending = scrollView.updateContext(HostingScrollViewUpdateContext(
            contentOffset: state.contentOffset,
            contentFrame: CGRect(origin: frame.origin, size: frame.size.value),
            containingSize: _size.value,
            offsetMode: offsetMode,
            safeInsets: safeAreaInsets
        ))
        if !updateIsPending {
            lastUpdateSeed = state.contentOffsetSeed
        }
        oldProperties = properties
        oldMargins = margins
        _AGGraph.setStatefulOutput(scrollView)
    }
}

/// Advances host-owned inertial motion from the view graph's frame clock.
struct HostingScrollViewMotionUpdate: StatefulRule {
    typealias Value = HostingScrollView

    var _scrollView: Attribute<HostingScrollView>
    var _time: Attribute<Time>

    mutating func updateValue() {
        let scrollView = _scrollView.value
        _ = scrollView.updateMotion(at: _time.value)
        _AGGraph.setStatefulOutput(scrollView)
    }
}
