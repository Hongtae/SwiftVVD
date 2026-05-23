//
//  File: PresentationChildWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

enum PresentationAvailableFrameSpace {
    // Overlay presentations are clipped by the render surface that owns them.
    case parentSurface

    // Platform popup/menu presentations should eventually use the current
    // display work-area from VVD. This currently falls back to parentSurface
    // until that backend display-geometry interface is designed.
    case platformVisibleScreen
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
    case .parentSurface:
        return presentationHostSurfaceFrame(for: controller)

    case .platformVisibleScreen:
        // TODO: Replace this with the current display/work-area rect after the
        // cross-platform window-display geometry API is settled.
        // This is the handoff point for platform popup edge placement.
        return presentationHostSurfaceFrame(for: controller)
    }
}

@MainActor
private func presentationHostSurfaceFrame(for controller: WindowController) -> CGRect? {
    if let child = controller as? PresentationChildWindowController {
        if let platformWindow = child.window {
            return presentationContentSurfaceFrame(for: platformWindow,
                                                   preferredSize: child.cachedContentSize)
        }
        if let parent = child.parentWindow {
            return presentationHostSurfaceFrame(for: parent)
        }
        return nil
    }
    guard let platformWindow = controller.window else { return nil }
    return presentationContentSurfaceFrame(for: platformWindow,
                                           preferredSize: controller.cachedContentSize)
}

@MainActor
private func presentationContentSurfaceFrame(for window: any PlatformWindow,
                                             preferredSize: CGSize) -> CGRect {
    let size: CGSize
    if preferredSize.width > 0 && preferredSize.height > 0 {
        size = preferredSize
    } else if window.contentSize.width > 0 && window.contentSize.height > 0 {
        size = window.contentSize
    } else {
        size = window.contentBounds.standardized.size
    }
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

    private let usesPlatformWindow: Bool
    private var frameInParent: CGRect
    private var didTearDown = false

    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: AttributeGraph,
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
        CGRect(origin: frameInParent.origin, size: size)
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
            if let platformWindow = window {
                return platformWindow.convertPointToScreen(point)
            }
            let pointInParent = point + frameInParent.origin
            if let parentChild = parentWindow as? PresentationChildWindowController {
                return parentChild.screenPoint(forLocalPoint: pointInParent)
            }
            if let parentWindow = parentWindow?.window {
                return parentWindow.convertPointToScreen(pointInParent)
            }
            return pointInParent
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
            super.drawFrame(offset: offset + frameInParent.origin, context)
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
