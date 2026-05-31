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
private final class ModalPresentationContext: @unchecked Sendable {
    typealias AnimationKey = TransitionAnimationKey
    typealias AnimationTrack = TransitionAnimationConfiguration<AnimationKey>.Track
    typealias AnimationConfiguration = TransitionAnimationConfiguration<AnimationKey>

    private enum TransitionPhase {
        case presenting
        case dismissing
    }

    private struct TransitionAnimation: @unchecked Sendable {
        let phase: TransitionPhase
        let duration: Double
        let configuration: AnimationConfiguration
        var elapsed: Double = 0
        var completion: (() -> Void)?

        var progress: Double {
            min(elapsed / duration, 1.0)
        }
        var isComplete: Bool { elapsed >= duration }
    }

    private let padding: CGFloat = 4

    private weak var parentController: WindowController?
    private var windowSize: CGSize = .zero
    private var windowOffset: CGPoint = .zero
    private var needsInputPlacement = true
    private var transition: TransitionAnimation? = nil
    private var pendingDismissalCompletion: (() -> Void)?
    private let shadowFilter = GraphicsContext.Filter.shadow(radius: 8.0, x: 0, y: 0)

    // Overlay modals need an engine-side transition when no platform window or
    // alert animation owns presentation.
    private var transitionDuration: Double { 0.25 }
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
        placeRoot(controller: controller,
                  layoutComputer: layoutComputer,
                  fittedSize: fittedSize)
        needsInputPlacement = false

        if let platformWindow = controller.window {
            let shouldAutoResize = controller.style.contains(.autoResize)
            if sizeChanged && shouldAutoResize {
                Task { @MainActor in
                    platformWindow.contentSize = fittedSize
                }
            }
        } else {
            if let parentSize = parentController?.cachedContentSize {
                windowOffset = CGPoint(
                    x: (parentSize.width - fittedSize.width) * 0.5,
                    y: (parentSize.height - fittedSize.height) * 0.5)
            }
        }
    }

    func prepareForInput(controller: WindowController) {
        guard needsInputPlacement || windowSize == .zero else { return }
        guard let layoutComputer = controller.viewGraph.rootLayoutComputer else { return }
        if windowSize == .zero {
            windowSize = fittedContentSize(controller: controller,
                                           layoutComputer: layoutComputer)
        }
        placeRoot(controller: controller,
                  layoutComputer: layoutComputer,
                  fittedSize: windowSize)
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

    private func placeRoot(controller: WindowController,
                           layoutComputer: Attribute<LayoutComputer>,
                           fittedSize: CGSize) {
        controller.viewGraph.data.withCurrent {
            controller.viewGraph.sizeAttr?.setValue(ViewSize(fittedSize))
            let center = CGPoint(x: fittedSize.width * 0.5,
                                 y: fittedSize.height * 0.5)
            layoutComputer.value.place(at: center,
                                       anchor: .center,
                                       proposal: ProposedViewSize(fittedSize))
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

    func beginPresentAnimation(controller: WindowController) {
        guard controller.window == nil else { return }
        pendingDismissalCompletion = nil
        transition = TransitionAnimation(
            phase: .presenting,
            duration: transitionDuration,
            configuration: transitionPresentAnimation
        )
    }

    private func beginDismissAnimation(completion: @escaping () -> Void) {
        transition = TransitionAnimation(
            phase: .dismissing,
            duration: transitionDuration,
            configuration: transitionDismissAnimation,
            completion: completion
        )
    }

    func requestDismissal(controller: WindowController,
                          reason: ModalDismissReason,
                          completion: @escaping () -> Void) -> Bool {
        guard controller.window == nil else { return false }
        guard reason == .dismissed || reason == .userAction else { return false }
        if let transition {
            switch transition.phase {
            case .presenting:
                // Finish the presentation animation before starting dismissal.
                // Reversing nonlinear scale/alpha tracks would require value-to-time
                // inversion and is not part of a confirmed modal contract.
                if pendingDismissalCompletion == nil {
                    pendingDismissalCompletion = completion
                }
                return true
            case .dismissing:
                return true
            }
        }
        beginDismissAnimation(completion: completion)
        return true
    }

    func updateAnimation(delta: Double) -> Bool {
        guard var transition else { return false }
        transition.elapsed += delta
        if transition.isComplete {
            switch transition.phase {
            case .presenting:
                if let completion = pendingDismissalCompletion {
                    pendingDismissalCompletion = nil
                    beginDismissAnimation(completion: completion)
                } else {
                    self.transition = nil
                }
            case .dismissing:
                self.transition = nil
                transition.completion?()
            }
        } else {
            self.transition = transition
        }
        return true
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
         sourceGraph: AttributeGraph,
         scene: WindowKey,
         parentController: WindowController,
         usesPlatformWindow: Bool) {
        self.presentationContext = ModalPresentationContext(parentController: parentController)
        self.usesPlatformWindow = usesPlatformWindow
        super.init(crossGraphContent: contentAttr,
                   sourceGraph: sourceGraph,
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
        super.updateView(tick: tick, delta: delta, date: date,
                         contentSize: contentSize, redraw: &redraw, withGC)
        if presentationContext.updateAnimation(delta: delta) {
            redraw = true
        }
    }

    override func handleMouseEvent(event: MouseEvent) -> Bool {
        presentationContext.prepareForInput(controller: self)
        if presentationContext.isAnimating { return true }
        var event = event
        event.location = presentationContext.localLocation(for: self,
                                                           parentLocation: event.location)
        return super.handleMouseEvent(event: event)
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        presentationContext.prepareForInput(controller: self)
        if presentationContext.isAnimating { return true }
        let location = presentationContext.localLocation(for: self,
                                                         parentLocation: location)
        return super.handleMouseWheel(at: location, delta: delta)
    }

    override func handleMouseHover(at location: CGPoint,
                                   deviceID: Int,
                                   isTopMost: Bool) -> Bool {
        presentationContext.prepareForInput(controller: self)
        if presentationContext.isAnimating { return true }
        let location = presentationContext.localLocation(for: self,
                                                         parentLocation: location)
        return super.handleMouseHover(at: location,
                                      deviceID: deviceID,
                                      isTopMost: isTopMost)
    }

    func requestModalDismissal(reason: ModalDismissReason,
                               completion: @escaping () -> Void) -> Bool {
        presentationContext.requestDismissal(controller: self,
                                             reason: reason,
                                             completion: completion)
    }

    func onModalSessionInitiated() {
        presentationContext.beginPresentAnimation(controller: self)
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
