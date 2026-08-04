//
//  File: ModalWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

enum TransitionAnimationKey: String, Hashable {
    case scale
    case alpha
}

// Small keyframe container for modal overlay chrome. The animation system owns
// transaction timing; this type only maps transition progress to visual tracks.
struct TransitionAnimationConfiguration<Key: Hashable> {
    struct Track {
        let curve: UnitCurve
        let keyframes: [(value: CGFloat, time: Double)]

        func value(at rawProgress: Double) -> CGFloat {
            let progress = curve.value(at: rawProgress)
            guard keyframes.count >= 2 else { return 1.0 }
            if progress <= keyframes.first!.time { return keyframes.first!.value }
            if progress >= keyframes.last!.time { return keyframes.last!.value }

            for i in 0..<(keyframes.count - 1) {
                let k0 = keyframes[i]
                let k1 = keyframes[i + 1]
                if progress >= k0.time && progress <= k1.time {
                    let t = (progress - k0.time) / (k1.time - k0.time)
                    let p0 = keyframes[max(i - 1, 0)].value
                    let p1 = k0.value
                    let p2 = k1.value
                    let p3 = keyframes[min(i + 2, keyframes.count - 1)].value
                    let spline = SplineSegment<CGFloat>.catmullRom(p0: p0, p1: p1, p2: p2, p3: p3)
                    return CGFloat(spline.interpolate(Scalar(t)))
                }
            }
            return keyframes.last!.value
        }
    }

    let tracks: [Key: Track]
}

// Minimal presentation state for the preference-driven modal path.
final class ModalPresentationContext: @unchecked Sendable {
    typealias AnimationKey = TransitionAnimationKey
    typealias AnimationTrack = TransitionAnimationConfiguration<AnimationKey>.Track
    typealias AnimationConfiguration = TransitionAnimationConfiguration<AnimationKey>

    private enum TransitionPhase {
        case presenting
        case dismissing
    }

    private struct CompletionTokens: @unchecked Sendable {
        var regular: [AnimationCompletionToken] = []
        var logical: [AnimationCompletionToken] = []

        var isEmpty: Bool {
            regular.isEmpty && logical.isEmpty
        }
    }

    private struct TransitionAnimation: @unchecked Sendable {
        let phase: TransitionPhase
        let duration: Double
        let configuration: AnimationConfiguration
        var completionTokens: CompletionTokens
        var elapsed: Double = 0
        var completion: (() -> Void)?

        var progress: Double {
            guard duration > 0 else { return 1.0 }
            return min(elapsed / duration, 1.0)
        }
        var isComplete: Bool { elapsed >= duration }
    }

    private struct PendingDismissal: @unchecked Sendable {
        enum CompletionBoundary: @unchecked Sendable {
            case unresolved
            case timed(
                duration: Double,
                completionTokens: CompletionTokens
            )
            case nonfinishing(completionTokens: CompletionTokens)
        }

        var transaction: Transaction
        var completion: () -> Void
        var completionBoundary: CompletionBoundary = .unresolved
        var elapsed: Double = 0
    }

    private let padding: CGFloat = 4

    private weak var parentController: WindowController?
    private var windowSize: CGSize = .zero
    private var windowOffset: CGPoint = .zero
    private var needsInputPlacement = true
    private var transition: TransitionAnimation? = nil
    private var pendingDismissal: PendingDismissal?
    private let shadowFilter = GraphicsContext.Filter.shadow(radius: 8.0, x: 0, y: 0)

    // Overlay modals use the transition for drawing. Platform modals use the
    // same timing path to preserve transaction completion boundaries.
    private var transitionDuration: Double { 0.30 }
    private var transitionPresentAnimation: AnimationConfiguration {
        AnimationConfiguration(
            tracks: [
                .scale: AnimationTrack(
                    curve: .easeOut,
                    keyframes: [(0.2, 0.0), (1.1, 0.8), (1.0, 1.0)]
                ),
                .alpha: AnimationTrack(
                    curve: .easeInOut,
                    keyframes: [(0.0, 0.0), (1.0, 1.0)]
                )
            ]
        )
    }
    private var transitionDismissAnimation: AnimationConfiguration {
        AnimationConfiguration(
            tracks: [
                .scale: AnimationTrack(
                    curve: .easeIn,
                    keyframes: [(1.0, 0.0), (0.2, 1.0)]
                ),
                .alpha: AnimationTrack(
                    curve: .easeOut,
                    keyframes: [(1.0, 0.0), (0.0, 1.0)]
                )
            ]
        )
    }

    var isAnimating: Bool { transition != nil }

    init(parentController: WindowController) {
        self.parentController = parentController
    }

    private var animationProgress: Double {
        transition?.progress ?? 1.0
    }

    private func valueForProgress(_ rawProgress: Double, key: AnimationKey) -> CGFloat {
        guard let config = transition?.configuration,
              let track = config.tracks[key] else { return 1.0 }
        return track.value(at: rawProgress)
    }

    private func resolvedPresentDuration(for transaction: Transaction) -> Double {
        // An explicit nil animation keeps modal completion immediate. A
        // disabled transaction can still carry an explicit animation that
        // owns the modal timing boundary.
        if transaction.hasExplicitAnimationValue && transaction.animation == nil {
            return 0
        }
        guard let animation = transaction.effectiveAnimation else {
            return transitionDuration
        }
        guard animation.box.duration.isFinite else {
            return 0
        }
        let animationDuration = max(0, animation.box.duration)
        guard animationDuration > 0 else {
            return 0
        }
        return animationDuration + transitionDuration
    }

    private func resolvedDismissDuration(for transaction: Transaction) -> Double {
        if transaction.hasExplicitAnimationValue && transaction.animation == nil {
            return 0
        }
        guard let animation = transaction.effectiveAnimation else {
            return transitionDuration
        }
        guard animation.box.duration.isFinite else {
            return 0
        }
        let animationDuration = max(0, animation.box.duration)
        guard animationDuration > 0 else {
            return 0
        }
        return animationDuration + transitionDuration
    }

    private func completionTokens(
        for transaction: Transaction,
        duration: Double,
        registersDefaultCompletion: Bool
    ) -> CompletionTokens {
        // Platform modal children may not draw through this overlay path, but
        // they still register tokens so transaction completions wait for the
        // same modal timing boundary.
        guard duration > 0 else {
            return CompletionTokens()
        }
        if let animation = transaction.effectiveAnimation {
            guard animation.box.duration > 0 else {
                return CompletionTokens()
            }
        } else if !registersDefaultCompletion {
            return CompletionTokens()
        }
        return completionTokens(for: transaction)
    }

    private func completionTokens(for transaction: Transaction) -> CompletionTokens {
        CompletionTokens(
            regular: transaction.animationListener.map {
                [AnimationCompletionToken(listener: $0)]
            } ?? [],
            logical: transaction.animationLogicalListener.map {
                [AnimationCompletionToken(listener: $0)]
            } ?? []
        )
    }

    private func startCompletionTokens(_ tokens: CompletionTokens) {
        (tokens.regular + tokens.logical).forEach { $0.start() }
    }

    private func startNonfinishingCompletionTokens(
        for transaction: Transaction
    ) -> CompletionTokens? {
        guard let animation = transaction.effectiveAnimation,
              !animation.box.duration.isFinite else {
            return nil
        }
        let tokens = completionTokens(for: transaction)
        startCompletionTokens(tokens)
        return tokens
    }

    private func isDirectNegativeSpeedAnimation(_ animation: Animation) -> Bool {
        guard let speed = animation.box as? SpeedAnimationBox else {
            return false
        }
        return speed.speed < 0
    }

    private func handleImmediatePresentCompletion(
        transaction: Transaction,
        duration: Double
    ) {
        guard duration <= 0,
              transaction.hasExplicitAnimationValue,
              let animation = transaction.animation else {
            return
        }
        let tokens = completionTokens(for: transaction)
        startCompletionTokens(tokens)
        if animation.box.duration.isFinite ||
            isDirectNegativeSpeedAnimation(animation) {
            finishCompletionTokens(tokens)
        }
    }

    private func handleImmediateDismissal(
        transaction: Transaction,
        duration: Double,
        completion: @escaping () -> Void
    ) {
        guard duration <= 0,
              transaction.hasExplicitAnimationValue,
              let animation = transaction.animation else {
              completion()
            return
        }
        let tokens = completionTokens(for: transaction)
        startCompletionTokens(tokens)
        if animation.box.duration.isFinite,
           !isDirectNegativeSpeedAnimation(animation) {
            finishCompletionTokens(tokens)
        }
        completion()
    }

    func onViewLoaded() {
    }

    func onViewLayoutChanged(controller: WindowController) {
        guard let layoutComputer = controller.viewGraph.rootLayoutComputer else {
            fatalError("ModalWindowController: rootLayoutComputer not set: AG wiring incomplete!")
        }

        let fittedSize = fittedContentSize(controller: controller,
                                           layoutComputer: layoutComputer)

        let sizeChanged = fittedSize != windowSize
        windowSize = fittedSize
        setRootSize(controller: controller, fittedSize: fittedSize)
        needsInputPlacement = false

        if let platformWindow = controller.window {
            let shouldAutoResize = controller.style.contains(.autoResize)
            if sizeChanged && shouldAutoResize {
                Task { @MainActor in
                    platformWindow.contentSize = fittedSize
                }
            }
        } else {
            updateOverlayPlacement(controller: controller)
        }
    }

    @discardableResult
    func updateOverlayPlacement(controller: WindowController) -> Bool {
        guard controller.window == nil,
              windowSize != .zero,
              let parentSize = parentController?.cachedContentSize else {
            return false
        }
        // Attached modals remain centered while fitting and keep their top
        // edge reachable when their fitted height exceeds the parent.
        let offset = CGPoint(
            x: (parentSize.width - windowSize.width) * 0.5,
            y: max((parentSize.height - windowSize.height) * 0.5, 0)
        )
        guard offset != windowOffset else { return false }
        windowOffset = offset
        return true
    }

    func prepareForInput(controller: WindowController) {
        guard needsInputPlacement || windowSize == .zero else { return }
        guard let layoutComputer = controller.viewGraph.rootLayoutComputer else { return }
        if windowSize == .zero {
            windowSize = fittedContentSize(controller: controller,
                                           layoutComputer: layoutComputer)
        }
        setRootSize(controller: controller, fittedSize: windowSize)
        needsInputPlacement = false
    }

    func layoutContentSize(controller: WindowController,
                           platformContentSize: CGSize) -> CGSize {
        guard windowSize != .zero else {
            return platformContentSize
        }
        return windowSize
    }

    private func fittedContentSize(controller: WindowController,
                                   layoutComputer: Attribute<LayoutComputer>) -> CGSize {
        var fittedSize = controller.cachedRootFittedSize
            ?? layoutComputer.value.sizeThatFits(.unspecified)
        fittedSize.width = max(fittedSize.width, 1) + padding * 2
        fittedSize.height = max(fittedSize.height, 1) + padding * 2
        return fittedSize
    }

    /// Publishes the fitted host size as the root proposal. `RootGeometry`
    /// owns content measurement and positioning through graph invalidation.
    private func setRootSize(
        controller: WindowController,
        fittedSize: CGSize
    ) {
        controller.viewGraph.data.withCurrent {
            controller.viewGraph.sizeAttr?.setValue(ViewSize(fittedSize))
        }
    }

    func drawFrame(for controller: WindowController,
                   parentOffset: CGPoint,
                   context: GraphicsContext,
                   drawBody: (CGPoint, GraphicsContext) -> Void) {
        guard controller.window == nil else {
            drawBody(parentOffset, context)
            return
        }

        let contentOffset = windowOffset + parentOffset
        guard windowSize.width > .zero, windowSize.height > .zero else {
            drawBody(contentOffset, context)
            return
        }

        let progress = animationProgress
        let alpha = valueForProgress(progress, key: .alpha)
        let scale = valueForProgress(progress, key: .scale)
        let frame = CGRect(origin: contentOffset, size: windowSize)
        let center = CGPoint(x: frame.midX, y: frame.midY)

        var context = context
        context.opacity = alpha
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -center.x, y: -center.y)

        // Overlay modal controllers draw into the full parent area so they can
        // paint modal chrome, such as the shadow, before the child content.
        let path = RoundedRectangle(cornerRadius: 5).path(in: frame)
        var shadowContext = context
        shadowContext.addFilter(shadowFilter)
        shadowContext.fill(path, with: .color(.white))
        context.stroke(path, with: .color(.black.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1))

        if alpha < 1.0 {
            context.drawLayer { context in
                drawBody(contentOffset, context)
            }
        } else {
            drawBody(contentOffset, context)
        }
    }

    func localLocation(for controller: WindowController, parentLocation: CGPoint) -> CGPoint {
        guard controller.window == nil else { return parentLocation }
        return parentLocation - windowOffset
    }

    func parentLocation(for controller: WindowController, localLocation: CGPoint) -> CGPoint {
        guard controller.window == nil else { return localLocation }
        return localLocation + windowOffset
    }

    func beginPresentAnimation(controller: WindowController,
                               transaction: Transaction) {
        pendingDismissal = nil
        let duration = resolvedPresentDuration(for: transaction)
        let completionTokens = completionTokens(
            for: transaction,
            duration: duration,
            registersDefaultCompletion: true
        )
        guard duration > 0 || !completionTokens.isEmpty else {
            transition = nil
            handleImmediatePresentCompletion(
                transaction: transaction,
                duration: duration
            )
            return
        }
        startCompletionTokens(completionTokens)
        transition = TransitionAnimation(
            phase: .presenting,
            duration: duration,
            configuration: transitionPresentAnimation,
            completionTokens: completionTokens
        )
    }

    private func beginDismissAnimation(transaction: Transaction,
                                       completion: @escaping () -> Void) {
        let duration = resolvedDismissDuration(for: transaction)
        let completionTokens = completionTokens(
            for: transaction,
            duration: duration,
            registersDefaultCompletion: true
        )
        guard duration > 0 || !completionTokens.isEmpty else {
            transition = nil
            handleImmediateDismissal(
                transaction: transaction,
                duration: duration,
                completion: completion
            )
            return
        }
        startCompletionTokens(completionTokens)
        transition = TransitionAnimation(
            phase: .dismissing,
            duration: duration,
            configuration: transitionDismissAnimation,
            completionTokens: completionTokens,
            completion: completion
        )
    }

    private func makePendingDismissal(transaction: Transaction,
                                      completion: @escaping () -> Void) -> PendingDismissal {
        let duration = resolvedDismissDuration(for: transaction)
        if duration <= 0,
           let completionTokens = startNonfinishingCompletionTokens(
               for: transaction
           ) {
            return PendingDismissal(
                transaction: transaction,
                completion: completion,
                completionBoundary: .nonfinishing(
                    completionTokens: completionTokens
                )
            )
        }
        let completionTokens = completionTokens(
            for: transaction,
            duration: duration,
            registersDefaultCompletion: true
        )
        if duration > 0 || !completionTokens.isEmpty {
            startCompletionTokens(completionTokens)
            return PendingDismissal(
                transaction: transaction,
                completion: completion,
                completionBoundary: .timed(
                    duration: duration,
                    completionTokens: completionTokens
                ),
                elapsed: 0
            )
        }
        return PendingDismissal(transaction: transaction, completion: completion)
    }

    private func beginDismissAnimation(_ dismissal: PendingDismissal) {
        switch dismissal.completionBoundary {
        case .unresolved:
            beginDismissAnimation(
                transaction: dismissal.transaction,
                completion: dismissal.completion
            )
        case .nonfinishing:
            transition = nil
            dismissal.completion()
        case let .timed(duration, completionTokens):
            transition = TransitionAnimation(
                phase: .dismissing,
                duration: duration,
                configuration: transitionDismissAnimation,
                completionTokens: completionTokens,
                elapsed: min(dismissal.elapsed, duration),
                completion: dismissal.completion
            )
        }
    }

    func requestDismissal(controller: WindowController,
                          reason: ModalDismissReason,
                          transaction: Transaction,
                          completion: @escaping () -> Void) -> Bool {
        guard reason == .dismissed || reason == .userAction else { return false }
        if let transition {
            switch transition.phase {
            case .presenting:
                // Finish the presentation animation before starting dismissal.
                // Reversing nonlinear scale/alpha tracks would require value-to-time
                // inversion and is not part of a confirmed modal contract.
                if pendingDismissal == nil {
                    pendingDismissal = makePendingDismissal(
                        transaction: transaction,
                        completion: completion
                    )
                }
                return true
            case .dismissing:
                return true
            }
        }
        beginDismissAnimation(transaction: transaction, completion: completion)
        return true
    }

    func updateAnimation(delta: Double) -> Bool {
        guard var transition else { return false }
        transition.elapsed += delta
        if transition.phase == .presenting, pendingDismissal != nil {
            pendingDismissal?.elapsed += delta
        }
        if transition.isComplete {
            switch transition.phase {
            case .presenting:
                if case .nonfinishing = pendingDismissal?.completionBoundary {
                    finishLogicalCompletionTokens(transition.completionTokens)
                } else {
                    finishCompletionTokens(transition.completionTokens)
                }
                if let dismissal = pendingDismissal {
                    pendingDismissal = nil
                    // Present completion drains before the deferred dismissal
                    // begins, preserving one transaction boundary at a time.
                    beginDismissAnimation(dismissal)
                } else {
                    self.transition = nil
                }
            case .dismissing:
                self.transition = nil
                transition.completion?()
                finishCompletionTokens(transition.completionTokens)
            }
        } else {
            self.transition = transition
        }
        return true
    }

    private func finishCompletionTokens(_ tokens: CompletionTokens) {
        tokens.regular.forEach { $0.finish() }
        finishLogicalCompletionTokens(tokens)
    }

    private func finishLogicalCompletionTokens(_ tokens: CompletionTokens) {
        tokens.logical.forEach { $0.finish() }
    }

    func onModalSessionDismissedByUser() {
    }

    func onModalSessionDismissedByParent() {
    }

    func onModalSessionCancelled() {
    }
}

// WindowController subclass for preference-driven modal windows.
//
// The preference layer currently stores `AnyView`, so this controller is
// intentionally non-generic. `AnyView.storage.view` keeps the wrapped `any View`,
// so a later pass can reopen the concrete type and restore a typed root graph.
// Do not spell this as `ModalWindowController<AnyView>`: that suggests a concrete
// Content path was restored. The erased bridge should be replaced after the
// sheet storage and type-change lifecycle are reconstructed.
final class ModalWindowController: WindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle { [.autoResize] }
    override var observesRootFittedSizeForLayoutUpdates: Bool { true }
    var modalSessionPrefersPlatformWindow: Bool { usesPlatformWindow }

    private let presentationContext: ModalPresentationContext
    private let usesPlatformWindow: Bool

    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: _AGGraph,
         environment: EnvironmentValues = .tracking(),
         viewPhase: ViewGraphHost.Phase = ViewGraphHost.Phase(),
         scene: WindowKey,
         parentController: WindowController,
         usesPlatformWindow: Bool) {
        self.presentationContext = ModalPresentationContext(parentController: parentController)
        self.usesPlatformWindow = usesPlatformWindow
        super.init(crossGraphContent: contentAttr,
                   sourceGraph: sourceGraph,
                   environment: environment,
                   viewPhase: viewPhase,
                   scene: scene)
    }

    func resolveModalWindowAttachment(_ attach: WindowController.AttachWindow?) {
        Task { @MainActor [weak self] in
            guard let attach, let self else { return }
            guard self.usesPlatformWindow else { return }
            guard let childWindow = self.makeWindow() else {
                Log.error("ModalWindowController: failed to create platform modal window")
                return
            }
            childWindow.contentSize = CGSize(width: 10, height: 10)
            childWindow.origin = .zero
            attach(childWindow)
        }
    }

    override func onViewLoaded() {
        presentationContext.onViewLoaded()
    }

    override func onViewLayoutUpdated() {
        presentationContext.onViewLayoutChanged(controller: self)
    }

    override func layoutContentSize(from contentSize: CGSize) -> CGSize {
        presentationContext.layoutContentSize(controller: self,
                                              platformContentSize: contentSize)
    }

    override func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        presentationContext.drawFrame(for: self,
                                      parentOffset: offset,
                                      context: context) { offset, context in
            self.drawModalBody(offset: offset, context)
        }
    }

    private func drawModalBody(offset: CGPoint, _ context: GraphicsContext) {
        super.drawFrame(offset: offset, context)
    }

    override func updateView(tick: UInt64, delta: Double, date: Date,
                             contentSize: CGSize, redraw: inout Bool,
                             _ withGC: WindowContext.WithGraphicsContext) {
        if presentationContext.updateOverlayPlacement(controller: self) {
            redraw = true
        }
        super.updateView(tick: tick, delta: delta, date: date,
                         contentSize: contentSize, redraw: &redraw, withGC)
        if presentationContext.updateAnimation(delta: animationDelta) {
            redraw = true
        }
    }

    override func handleMouseEvent(event: PlatformMouseEvent) -> Bool {
        presentationContext.prepareForInput(controller: self)
        if presentationContext.isAnimating { return true }
        return super.handleMouseEvent(event: event)
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        presentationContext.prepareForInput(controller: self)
        if presentationContext.isAnimating { return true }
        return super.handleMouseWheel(at: location, delta: delta)
    }

    override func handleMouseHover(at location: CGPoint,
                                   deviceID: Int,
                                   isTopMost: Bool) -> Bool {
        presentationContext.prepareForInput(controller: self)
        if presentationContext.isAnimating { return true }
        return super.handleMouseHover(at: location,
                                      deviceID: deviceID,
                                      isTopMost: isTopMost)
    }

    override func presentationPointInParent(forLocalPoint point: CGPoint) -> CGPoint {
        presentationContext.parentLocation(for: self, localLocation: point)
    }

    override func presentationPointInLocal(fromParentPoint point: CGPoint) -> CGPoint {
        presentationContext.prepareForInput(controller: self)
        return presentationContext.localLocation(for: self, parentLocation: point)
    }

    func requestModalDismissal(reason: ModalDismissReason,
                               transaction: Transaction,
                               completion: @escaping () -> Void) -> Bool {
        presentationContext.requestDismissal(controller: self,
                                             reason: reason,
                                             transaction: transaction,
                                             completion: completion)
    }

    func onModalSessionInitiated(transaction: Transaction) {
        presentationContext.beginPresentAnimation(controller: self,
                                                 transaction: transaction)
    }

    func onModalSessionDismissedByUser() {
        presentationContext.onModalSessionDismissedByUser()
    }

    func onModalSessionDismissedByParent() {
        presentationContext.onModalSessionDismissedByParent()
    }

    func onModalSessionCancelled() {
        presentationContext.onModalSessionCancelled()
    }
}

private struct ModalSessionUsingPlatformWindow: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var modalSessionUsingPlatformWindow: Bool {
        get { self[ModalSessionUsingPlatformWindow.self] }
        set { self[ModalSessionUsingPlatformWindow.self] = newValue }
    }
}
