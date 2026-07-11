//
//  File: PresentationChildWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

enum PresentationAvailableFrameSpace {
    // Overlay presentations are clipped by the render surface that hosts them.
    // The returned frame is in that host surface's content coordinate space.
    case hostSurface

    // Platform popup/menu presentations use the current display's visible
    // frame from VVD.Window.screen so reserved system UI such as taskbars is
    // avoided. The returned frame is in screen-space coordinates. A nil screen
    // falls back to the host window's content rect in screen coordinates.
    case platformVisibleScreen
}

struct PresentationFrameFitAxes: OptionSet {
    let rawValue: UInt8

    static let horizontal = PresentationFrameFitAxes(rawValue: 1 << 0)
    static let vertical = PresentationFrameFitAxes(rawValue: 1 << 1)
    static let all: PresentationFrameFitAxes = [.horizontal, .vertical]
}

extension WindowController {
    func availableFrameForPresentation(_ space: PresentationAvailableFrameSpace) -> CGRect? {
        runOnMainQueueSync {
            presentationAvailableFrame(for: self, in: space)
        }
    }
}

@MainActor
private func presentationAvailableFrame(for controller: WindowController,
                                        in space: PresentationAvailableFrameSpace) -> CGRect? {
    switch space {
    case .hostSurface:
        return presentationHostSurfaceFrame(for: controller)

    case .platformVisibleScreen:
        return presentationHostVisibleFrame(for: controller) ??
            presentationHostScreenFrame(for: controller)
    }
}

@MainActor
private func presentationHostVisibleFrame(for controller: WindowController) -> CGRect? {
    presentationHostWindow(for: controller)?.screen?.visibleFrame
}

@MainActor
private func presentationHostWindow(for controller: WindowController) -> (any PlatformWindow)? {
    if let platformWindow = controller.window {
        return platformWindow
    }
    if let parent = controller.parentWindow {
        return presentationHostWindow(for: parent)
    }
    return nil
}

@MainActor
private func presentationHostSurfaceFrame(for controller: WindowController) -> CGRect? {
    if let platformWindow = controller.window {
        return presentationContentSurfaceFrame(for: platformWindow,
                                               preferredSize: controller.cachedContentSize)
    }
    if let parent = controller.parentWindow {
        return presentationHostSurfaceFrame(for: parent)
    }
    return nil
}

@MainActor
private func presentationHostScreenFrame(for controller: WindowController) -> CGRect? {
    if let platformWindow = controller.window {
        return presentationContentScreenFrame(for: platformWindow,
                                              preferredSize: controller.cachedContentSize)
    }
    if let parent = controller.parentWindow {
        return presentationHostScreenFrame(for: parent)
    }
    return nil
}

@MainActor
private func presentationHostSurfacePoint(for controller: WindowController,
                                          localPoint: CGPoint) -> CGPoint? {
    if controller.window != nil {
        return localPoint
    }
    guard let parent = controller.parentWindow else { return nil }
    let pointInParent = controller.presentationPointInParent(forLocalPoint: localPoint)
    return presentationHostSurfacePoint(for: parent, localPoint: pointInParent)
}

@MainActor
private func presentationScreenPoint(for controller: WindowController,
                                     localPoint: CGPoint) -> CGPoint? {
    if let platformWindow = controller.window {
        return platformWindow.convertPointToScreen(localPoint)
    }
    guard let parent = controller.parentWindow else { return nil }
    let pointInParent = controller.presentationPointInParent(forLocalPoint: localPoint)
    return presentationScreenPoint(for: parent, localPoint: pointInParent)
}

@MainActor
private func presentationContentSize(for window: any PlatformWindow,
                                     preferredSize: CGSize) -> CGSize {
    let size: CGSize
    if preferredSize.width > 0 && preferredSize.height > 0 {
        size = preferredSize
    } else if window.contentSize.width > 0 && window.contentSize.height > 0 {
        size = window.contentSize
    } else {
        size = window.contentBounds.standardized.size
    }
    return size
}

@MainActor
private func presentationContentSurfaceFrame(for window: any PlatformWindow,
                                             preferredSize: CGSize) -> CGRect {
    let size = presentationContentSize(for: window,
                                       preferredSize: preferredSize)
    return CGRect(origin: .zero, size: size)
}

@MainActor
private func presentationContentScreenFrame(for window: any PlatformWindow,
                                            preferredSize: CGSize) -> CGRect {
    let size = presentationContentSize(for: window,
                                       preferredSize: preferredSize)
    let p0 = window.convertPointToScreen(.zero)
    let p1 = window.convertPointToScreen(CGPoint(x: size.width, y: size.height))
    return CGRect(x: min(p0.x, p1.x),
                  y: min(p0.y, p1.y),
                  width: abs(p1.x - p0.x),
                  height: abs(p1.y - p0.y))
}

// Shared base for parent-owned presentation child windows.
//
// This is the common path for transient children that are owned by another
// WindowController instead of AppWindowsController:
// - regular utility/popover-like children
// - popup/menu-like children
// - overlay fallback children when the platform-window attach path is disabled
//
// Keep layout, cross-graph content, overlay drawing, platform-window attach,
// parent-child lifetime, and event forwarding here. Leaf subclasses own their
// final WindowController.style and can opt into a platform-kind support check.
// Do not add a second popup or utility/popup controller stack for the same
// mechanics.
class PresentationChildWindowController: WindowController, @unchecked Sendable {
    override var observesRootFittedSizeForLayoutUpdates: Bool { true }
    var prefersPlatformWindowPresentation: Bool { usesPlatformWindow }

    // Ordinary platform windows need no special style support check. Utility and
    // popup subclasses override this with their required backend kind.
    var requiredPlatformWindowStyle: PlatformWindowStyle? { nil }

    // These are presentation policies, not stored init flags. A regular
    // utility window should not inherit popup dismissal behavior by accident,
    // while popup-like leaves can opt in without duplicating lifecycle code.
    var dismissesOnParentDeactivation: Bool { false }
    var dismissesOnParentMove: Bool { false }
    var presentationFrameFitAxes: PresentationFrameFitAxes { [] }

    func drawOverlayPresentationChrome(in frame: CGRect,
                                       context: GraphicsContext) {}

    private let usesPlatformWindow: Bool
    private var frameInParent: CGRect
    private var didTearDown = false

    init<Content: View>(content: Content,
                        scene: WindowKey,
                        usesPlatformWindow: Bool,
                        frameInParent: CGRect = .zero) {
        self.usesPlatformWindow = usesPlatformWindow
        self.frameInParent = frameInParent
        super.init(content: content, scene: scene)
    }

    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: _AGGraph,
         scene: WindowKey,
         usesPlatformWindow: Bool,
         frameInParent: CGRect = .zero) {
        self.usesPlatformWindow = usesPlatformWindow
        self.frameInParent = frameInParent
        super.init(crossGraphContent: contentAttr,
                   sourceGraph: sourceGraph,
                   scene: scene)
    }

    func presentationFrame(forContentSize size: CGSize) -> CGRect {
        let frame = CGRect(origin: frameInParent.origin, size: size)
        return frameByFittingPresentationFrame(frame,
                                               axes: presentationFrameFitAxes)
    }

    var presentationAvailableFrameSpace: PresentationAvailableFrameSpace {
        runOnMainQueueSync {
            window != nil ? .platformVisibleScreen : .hostSurface
        }
    }

    func availableFrameForPresentationPlacement(in space: PresentationAvailableFrameSpace? = nil) -> CGRect? {
        runOnMainQueueSync {
            parentWindow?.availableFrameForPresentation(space ?? presentationAvailableFrameSpace)
        }
    }

    func comparisonFrameForPresentationPlacement(_ rect: CGRect,
                                                 in space: PresentationAvailableFrameSpace? = nil) -> CGRect? {
        switch space ?? presentationAvailableFrameSpace {
        case .hostSurface:
            return hostSurfaceRectInParentCoordinates(rect)

        case .platformVisibleScreen:
            return screenRectInParentCoordinates(rect)
        }
    }

    func frameByFittingPresentationFrame(_ frame: CGRect,
                                         axes: PresentationFrameFitAxes) -> CGRect {
        guard !axes.isEmpty,
              let available = availableFrameForPresentationPlacement(),
              let comparisonFrame = comparisonFrameForPresentationPlacement(frame) else {
            return frame
        }
        return frameByFittingPresentationFrame(frame,
                                               comparisonFrame: comparisonFrame,
                                               availableFrame: available,
                                               axes: axes)
    }

    func frameByFittingPresentationFrame(_ frame: CGRect,
                                         comparisonFrame: CGRect,
                                         availableFrame: CGRect,
                                         axes: PresentationFrameFitAxes) -> CGRect {
        guard !axes.isEmpty else { return frame }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if axes.contains(.horizontal) {
            if comparisonFrame.maxX > availableFrame.maxX {
                dx = availableFrame.maxX - comparisonFrame.maxX
            }
            if comparisonFrame.minX + dx < availableFrame.minX {
                dx += availableFrame.minX - (comparisonFrame.minX + dx)
            }
        }
        if axes.contains(.vertical) {
            if comparisonFrame.maxY > availableFrame.maxY {
                dy = availableFrame.maxY - comparisonFrame.maxY
            }
            if comparisonFrame.minY + dy < availableFrame.minY {
                dy += availableFrame.minY - (comparisonFrame.minY + dy)
            }
        }
        return frame.offsetBy(dx: dx, dy: dy)
    }

    private func hostSurfaceRectInParentCoordinates(_ rect: CGRect) -> CGRect? {
        runOnMainQueueSync {
            guard let parentWindow else { return nil }
            let p0 = presentationHostSurfacePoint(for: parentWindow,
                                                  localPoint: rect.origin)
            let p1 = presentationHostSurfacePoint(
                for: parentWindow,
                localPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            guard let p0, let p1 else { return nil }
            return CGRect(x: min(p0.x, p1.x),
                          y: min(p0.y, p1.y),
                          width: abs(p1.x - p0.x),
                          height: abs(p1.y - p0.y))
        }
    }

    private func screenRectInParentCoordinates(_ rect: CGRect) -> CGRect? {
        runOnMainQueueSync {
            guard let parentWindow else { return nil }
            let p0 = presentationScreenPoint(for: parentWindow,
                                             localPoint: rect.origin)
            let p1 = presentationScreenPoint(
                for: parentWindow,
                localPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            guard let p0, let p1 else { return nil }
            return CGRect(x: min(p0.x, p1.x),
                          y: min(p0.y, p1.y),
                          width: abs(p1.x - p0.x),
                          height: abs(p1.y - p0.y))
        }
    }

    // Creates an actual platform child window when requested. If platform-window
    // presentation is disabled or unsupported, WindowController keeps this child
    // as an overlay and drives it through the same layout/event hooks.
    func resolvePresentationWindowAttachment(_ attach: WindowController.AttachWindow?) {
        Task { @MainActor [weak self] in
            guard let attach, let self else { return }
            guard self.usesPlatformWindow else { return }
            if let requiredStyle = self.requiredPlatformWindowStyle {
                guard Platform.factory.supportedWindowStyles(requiredStyle)
                    .contains(requiredStyle) else {
                    Log.error("\(type(of: self)): \(requiredStyle) style not supported on this platform")
                    return
                }
            }
            guard let childWindow = self.makeWindow() else {
                Log.error("\(type(of: self)): failed to create platform presentation window")
                return
            }
            let size = self.frameInParent.size == .zero
                ? CGSize(width: 10, height: 10)
                : self.frameInParent.size
            childWindow.contentSize = size
            childWindow.origin = self.platformOrigin(for: self.frameInParent.origin)
            attach(childWindow)
            childWindow.activate()
        }
    }

    @MainActor
    private func platformOrigin(for origin: CGPoint) -> CGPoint {
        guard let parentWindow = parentWindow?.window else { return origin }
        return parentWindow.convertPointToScreen(origin)
    }

    func screenPoint(forLocalPoint point: CGPoint) -> CGPoint {
        runOnMainQueueSync {
            presentationScreenPoint(for: self, localPoint: point) ??
                presentationPointInParent(forLocalPoint: point)
        }
    }

    func screenRect(forLocalRect rect: CGRect) -> CGRect {
        let p0 = screenPoint(forLocalPoint: rect.origin)
        let p1 = screenPoint(forLocalPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(p0.x, p1.x),
                      y: min(p0.y, p1.y),
                      width: abs(p1.x - p0.x),
                      height: abs(p1.y - p0.y))
    }

    func hostSurfacePoint(forLocalPoint point: CGPoint) -> CGPoint {
        runOnMainQueueSync {
            presentationHostSurfacePoint(for: self, localPoint: point) ??
                presentationPointInParent(forLocalPoint: point)
        }
    }

    override func presentationPointInParent(forLocalPoint point: CGPoint) -> CGPoint {
        guard window == nil else { return point }
        return point + frameInParent.origin
    }

    override func presentationPointInLocal(fromParentPoint point: CGPoint) -> CGPoint {
        guard window == nil else { return point }
        return point - frameInParent.origin
    }

    func hostSurfaceRect(forLocalRect rect: CGRect) -> CGRect {
        let p0 = hostSurfacePoint(forLocalPoint: rect.origin)
        let p1 = hostSurfacePoint(forLocalPoint: CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(p0.x, p1.x),
                      y: min(p0.y, p1.y),
                      width: abs(p1.x - p0.x),
                      height: abs(p1.y - p0.y))
    }

    override func onViewLayoutUpdated() {
        guard let layoutComputer = viewGraph.rootLayoutComputer else { return }
        let fittedSize = viewGraph.rootFittedSize?.value ??
            layoutComputer.value.sizeThatFits(.unspecified)
        let size = CGSize(width: max(1, fittedSize.width),
                          height: max(1, fittedSize.height))
        let frame = presentationFrame(forContentSize: size)
        frameInParent = frame

        viewGraph.data.withCurrent {
            viewGraph.sizeAttr?.setValue(ViewSize(size))
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            layoutComputer.value.place(at: center,
                                       anchor: .center,
                                       proposal: ProposedViewSize(width: size.width,
                                                                  height: size.height))
        }

        if let platformWindow = window {
            Task { @MainActor [platformWindow, frame] in
                platformWindow.contentSize = frame.size
                platformWindow.origin = self.platformOrigin(for: frame.origin)
            }
        }
        parentWindow?.updatePresentationChild(child: self, frame: frame)
    }

    override func layoutContentSize(from contentSize: CGSize) -> CGSize {
        frameInParent.size == .zero ? contentSize : frameInParent.size
    }

    override func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        if window == nil {
            let contentOffset = offset + frameInParent.origin
            if frameInParent.width > .zero && frameInParent.height > .zero {
                let frame = CGRect(origin: contentOffset, size: frameInParent.size)
                drawOverlayPresentationChrome(in: frame, context: context)
            }
            super.drawFrame(offset: contentOffset, context)
        } else {
            super.drawFrame(offset: offset, context)
        }
    }

    // Called after the parent records this child as an active overlay or after a
    // platform-window attach resolver confirms the child window was attached.
    func onPresentationChildSessionInitiated() {}

    // Overlay children participate in the parent input pass. Platform children
    // receive their own window events through handleWindowEvent instead.
    func overlayHitTest(_ locationInParent: CGPoint) -> Bool {
        CGRect(origin: .zero, size: frameInParent.size).contains(locationInParent)
    }

    @MainActor
    override func handleWindowEvent(event: WindowEvent) {
        switch event.type {
        case .closed:
            enqueueInputAction { [weak self] in
                self?.onPresentationChildWindowClosed()
            }
        case .activated:
            enqueueInputAction { [weak self] in
                self?.onPresentationChildWindowActivated()
            }
        case .inactivated:
            enqueueInputAction { [weak self] in
                self?.onPresentationChildWindowInactivated()
            }
        case .geometryInvalidated, .resizeBegan, .moved, .resized:
            enqueueInputAction { [weak self] in
                self?.onPresentationChildWindowMoved()
            }
        default:
            break
        }
        super.handleWindowEvent(event: event)
    }

    // Parent-window lifecycle hooks.
    //
    // Deactivation and movement are intentionally separate policies:
    // - deactivation is focus/lifecycle loss
    // - movement/resizing invalidates screen-space anchors for popup-like UI
    // A platform can move an active window without deactivating it, so do not
    // fold these cases back into one "dismiss on deactivate" flag.
    override func onParentWindowInactivated() {
        super.onParentWindowInactivated()
        if dismissesOnParentDeactivation {
            dismiss()
        }
    }

    override func onParentWindowMoved() {
        super.onParentWindowMoved()
        if dismissesOnParentMove {
            dismiss()
        }
    }

    // Logical child activation hooks. For platform child windows these can
    // reflect the child window's own key/active state; for overlay children the
    // parent input router also uses the inactive hook when another target
    // receives the pointer down. Leave dismissal/text-input policy to subclasses.
    func onPresentationChildWindowActivated() {}
    func onPresentationChildWindowInactivated() {}
    func onPresentationChildWindowMoved() {}

    func onPresentationChildWindowClosed() {
        dismiss()
    }

    func dismiss() {
        if let parentWindow {
            parentWindow.removePresentationChild(child: self)
        } else {
            endPresentationSession()
        }
    }

    override func endPresentationSession() {
        super.endPresentationSession()
        tearDownPresentationChildSession()
    }

    private func tearDownPresentationChildSession() {
        guard !didTearDown else { return }
        didTearDown = true
    }
}

// Regular utility presentation child.
//
// Characteristics:
// - uses the platform .utilityWindow style when attached as a child window
// - can also run as a parent overlay through PresentationChildWindowController
// - stays alive across parent deactivation/move by default
// - should be the base for popover/tool-window-like surfaces that are not menus
class UtilityWindowController: PresentationChildWindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle { [.utilityWindow, .autoResize] }
    override var requiredPlatformWindowStyle: PlatformWindowStyle? { .utilityWindow }
}

// Transient popup presentation child.
//
// Characteristics:
// - uses the platform .popupWindow style when attached as a child window
// - shares all cross-graph/overlay/layout/event plumbing with utility children
// - dismisses when the parent deactivates because transient menu-like UI should
//   not survive focus loss
// - dismisses when the parent moves/resizes because the popup anchor is no
//   longer reliable; this is independent from deactivation
// - should be the base for context-menu, submenu, and menu-popup controllers
class PopupWindowController: PresentationChildWindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle { [.popupWindow, .autoResize] }
    override var requiredPlatformWindowStyle: PlatformWindowStyle? { .popupWindow }
    override var dismissesOnParentDeactivation: Bool { true }
    override var dismissesOnParentMove: Bool { true }
    private let overlayShadowFilter = GraphicsContext.Filter.shadow(
        color: Color(.sRGBLinear, white: 0, opacity: 0.24),
        radius: 10,
        x: 0,
        y: 2)

    // Menu-like popup windows stay inside the available host/screen frame
    // before nested submenu edge placement is resolved.
    override var presentationFrameFitAxes: PresentationFrameFitAxes { .all }

    override func drawOverlayPresentationChrome(in frame: CGRect,
                                                context: GraphicsContext) {
        let path = RoundedRectangle(cornerRadius: 6).path(in: frame)
        var shadowContext = context
        shadowContext.addFilter(overlayShadowFilter)
        shadowContext.fill(path, with: .color(.white))
    }
}

private struct PresentationChildUsingPlatformWindow: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var presentationChildUsingPlatformWindow: Bool {
        get { self[PresentationChildUsingPlatformWindow.self] }
        set { self[PresentationChildUsingPlatformWindow.self] = newValue }
    }
}
