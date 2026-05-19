//
//  File: AuxiliaryWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// Base controller for preference-driven auxiliary windows.
//
// Auxiliary windows are non-modal: they do not block input to the parent window.
// They are normally nonactivating, but may become key/active when a workflow such
// as text input requires keyboard focus.
class AuxiliaryWindowController: WindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle {
        [isPopupWindow ? .popupWindow : .auxiliaryWindow, .autoResize]
    }
    override var observesRootFittedSizeForLayoutUpdates: Bool { true }
    var auxiliaryPrefersPlatformWindow: Bool { usesPlatformWindow }

    private let usesPlatformWindow: Bool
    // Selects the transient popup presentation style. Keyboard focus/text-input
    // behavior is a separate policy and can apply to either popup or regular aux
    // windows.
    let isPopupWindow: Bool
    // Cross-platform fallback dismissal for parent-window lifecycle changes.
    // This intentionally does not decide what aux-window own activation means.
    let dismissOnDeactivated: Bool
    private var frameInParent: CGRect
    private var didTearDown = false

    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: AttributeGraph,
         scene: WindowKey,
         usesPlatformWindow: Bool,
         isPopupWindow: Bool = false,
         dismissOnDeactivated: Bool = false,
         frameInParent: CGRect = .zero) {
        self.usesPlatformWindow = usesPlatformWindow
        self.isPopupWindow = isPopupWindow
        self.dismissOnDeactivated = dismissOnDeactivated
        self.frameInParent = frameInParent
        super.init(crossGraphContent: contentAttr,
                   sourceGraph: sourceGraph,
                   scene: scene)
    }

    func auxiliaryFrame(forContentSize size: CGSize) -> CGRect {
        CGRect(origin: frameInParent.origin, size: size)
    }

    func resolveAuxiliaryWindowAttachment(_ attach: WindowController.AttachWindow?) {
        Task { @MainActor [weak self] in
            guard let attach, let self else { return }
            guard self.usesPlatformWindow else { return }
            let requiredStyle: PlatformWindowStyle = self.isPopupWindow ? .popupWindow : .auxiliaryWindow
            guard Platform.factory.supportedWindowStyles(requiredStyle)
                .contains(requiredStyle) else {
                Log.error("AuxiliaryWindowController: \(self.isPopupWindow ? "popupWindow" : "auxiliaryWindow") style not supported on this platform")
                return
            }
            guard let childWindow = self.makeWindow() else {
                Log.error("AuxiliaryWindowController: failed to create platform auxiliary window")
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

    override func onViewLayoutUpdated() {
        guard let layoutComputer = viewGraph.rootLayoutComputer else { return }
        let fittedSize = viewGraph.rootFittedSize?.value ??
            layoutComputer.value.sizeThatFits(.unspecified)
        let size = CGSize(width: max(1, fittedSize.width),
                          height: max(1, fittedSize.height))
        let frame = auxiliaryFrame(forContentSize: size)
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
        parentWindow?.updateAuxiliary(child: self, frame: frame)
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

    func onAuxiliarySessionInitiated() {}

    func overlayHitTest(_ locationInParent: CGPoint) -> Bool {
        CGRect(origin: .zero, size: frameInParent.size).contains(locationInParent)
    }

    @MainActor
    override func handleWindowEvent(event: WindowEvent) {
        switch event.type {
        case .closed:
            enqueueInputAction { [weak self] in
                self?.onAuxiliaryWindowClosed()
            }
        case .activated:
            enqueueInputAction { [weak self] in
                self?.onAuxiliaryWindowActivated()
            }
        case .inactivated:
            enqueueInputAction { [weak self] in
                self?.onAuxiliaryWindowInactivated()
            }
        case .geometryInvalidated, .resizeBegan, .moved, .resized:
            enqueueInputAction { [weak self] in
                self?.onAuxiliaryWindowMoved()
            }
        default:
            break
        }
        super.handleWindowEvent(event: event)
    }

    // Parent-window lifecycle fallback. A click outside the parent can only be
    // observed portably when it deactivates the parent window.
    override func onParentWindowInactivated() {
        super.onParentWindowInactivated()
        if dismissOnDeactivated {
            dismiss()
        }
    }

    override func onParentWindowMoved() {
        super.onParentWindowMoved()
        if dismissOnDeactivated {
            dismiss()
        }
    }

    // Logical aux activation hooks. For platform aux windows these can reflect
    // the aux window's own key/active state; for overlay children the parent
    // input router also uses the inactive hook when another target receives the
    // pointer down. Leave dismissal/text-input policy to subclasses.
    func onAuxiliaryWindowActivated() {}
    func onAuxiliaryWindowInactivated() {}
    func onAuxiliaryWindowMoved() {}

    func onAuxiliaryWindowClosed() {
        dismiss()
    }

    func dismiss() {
        if let parentWindow {
            parentWindow.removeAuxiliary(child: self)
        } else {
            endPresentationSession()
        }
    }

    override func endPresentationSession() {
        super.endPresentationSession()
        tearDownAuxiliarySession()
    }

    private func tearDownAuxiliarySession() {
        guard !didTearDown else { return }
        didTearDown = true
    }
}

private struct AuxiliaryWindowUsingPlatformWindow: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var auxiliaryWindowUsingPlatformWindow: Bool {
        get { self[AuxiliaryWindowUsingPlatformWindow.self] }
        set { self[AuxiliaryWindowUsingPlatformWindow.self] = newValue }
    }
}
