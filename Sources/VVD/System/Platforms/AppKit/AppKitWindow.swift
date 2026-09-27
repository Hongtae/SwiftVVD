//
//  File: AppKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
internal import AppKit

private final class _NativeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppKitWindow: Window {
    
    var activated: Bool { self.view?.activated ?? false }
    var visible: Bool { self.view?.visible ?? false }

    var resolution: CGSize {
        get {
            if let view {
                let pixelBounds = view.convertToBacking(view.bounds)
                return CGSize(width: pixelBounds.width, height: pixelBounds.height)
            }
            return .zero
        }
        set (value) {
            if view?.window?.contentView === self.view {
                let window = view!.window!
                let origin = self.origin
                let contentSize = window.convertFromBacking(
                    NSMakeRect(0, 0, value.width, value.height)).size
                window.setContentSize(contentSize)
                if origin == self.origin {
                    window.displayIfNeeded()
                } else {
                    self.origin = origin
                }
            } else {
                if let s = view?.convertFromBacking(value) {
                    view?.frame.size = s
                    view?.window?.layoutIfNeeded()
                }
            }
        }
    }

    var contentBounds: CGRect { self.view?.contentBounds ?? .zero }
    var windowFrame: CGRect { self.view?.windowFrame ?? .zero }
    var contentScaleFactor: CGFloat { self.view?.contentScaleFactor ?? 1.0 }

    var title: String {
        get { view?.window?.title ?? "" }
        set { view?.window?.title = newValue }
    }

    private var window: NSWindow?
    private(set) var view: AppKitView?
    private var _menuController: AppKitWindowMenuController?
    private var cursorOverride: Cursor?

    var menuController: (any WindowMenuController)? {
        guard let window else {
            return nil
        }
        // The controller retains the current snapshot, native callback targets,
        // and delegate relationship, so its identity must remain window-stable.
        if let _menuController {
            return _menuController
        }
        let controller = AppKitWindowMenuController(window: window)
        _menuController = controller
        return controller
    }

    var origin: CGPoint {
        get {
            if let view {
                if view.window?.contentView === self.view {
                    let frame = view.window!.frame
                    if let screen = view.window?.screen {
                        let referenceY = AppKitScreen.desktopTop(fallback: screen)
                        return AppKitScreen.topLeftRect(
                            fromNative: frame,
                            referenceY: referenceY
                        ).origin
                    }
                    return frame.origin
                } else {
                    return view.frame.origin
                }
            }
            return .zero
        }
        set(value) {
            if let view {
                if view.window?.contentView === self.view {
                    let window = view.window!
                    if let screen = window.screen {
                        let referenceY = AppKitScreen.desktopTop(fallback: screen)
                        let nativePoint = AppKitScreen.nativePoint(
                            fromTopLeft: value,
                            referenceY: referenceY
                        )
                        window.setFrameTopLeftPoint(nativePoint)
                    } else {
                        window.setFrameOrigin(value)
                    }
                    window.displayIfNeeded()
                } else {
                    view.frame.origin = value
                    view.window?.layoutIfNeeded()
                }
            }
        }
    }

    var contentSize: CGSize {
        get {
            if let view {
                var bounds = view.bounds
                if view.window != nil {
                    bounds = view.convert(bounds, to: nil)
                }
                return CGSize(width: bounds.width, height: bounds.height)
            }
            return .zero
        }
        set(value) {
            if let view {
                if view.window?.contentView === self.view {
                    let origin = self.origin
                    let window = view.window!
                    window.setContentSize(value)
                    if origin == self.origin {
                        window.displayIfNeeded()
                    } else {
                        self.origin = origin
                    }
                } else {
                    view.frame.size = value
                    view.window?.layoutIfNeeded()
                }
            }
        }
    }

    var delegate: WindowDelegate?
    var platformHandle: OpaquePointer? {
        if let view {
            return unsafeBitCast(view as AnyObject, to: OpaquePointer.self)
        }
        return nil
    }
    var isValid: Bool { view != nil }
    
    var eventObservers = WindowEventObserverContainer()

    private struct ModalQueueEntry {
        let window: AppKitWindow
        let completionHandler: (()->Void)?
    }
    private var modalWindowQueue: [ModalQueueEntry] = []

    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {
        var styleMask: NSWindow.StyleMask = []
        let backingStoreType: NSWindow.BackingStoreType = .buffered
        let contentRect = NSMakeRect(0, 0, 640, 480)
        
        if style.contains(.title)           { styleMask.insert(.titled) }
        if style.contains(.closeButton)     { styleMask.insert(.closable) }
        if style.contains(.minimizeButton)  { styleMask.insert(.miniaturizable) }
        if style.contains(.maximizeButton)  {  }
        if style.contains(.resizableBorder) { styleMask.insert(.resizable) }
        
        var windowType: NSWindow.Type = _NativeWindow.self
        
        let isPopupWindow = style.contains(.popupWindow)
        if isPopupWindow {
            styleMask.insert(.borderless)
            styleMask.insert(.nonactivatingPanel)
            windowType = NSPanel.self
        } else if style.contains(.utilityWindow) {
            styleMask.insert(.utilityWindow)
            windowType = NSPanel.self
        }
        
        let window = windowType.init(contentRect: contentRect,
                                     styleMask: styleMask,
                                     backing: backingStoreType,
                                     defer: true)
        self.window = window
        self.delegate = delegate
        let view = AppKitView(frame: contentRect)
        self.view = view
        view.proxyWindow = self
        
        window.contentView = view
        window.delegate = view
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.allowsConcurrentViewDrawing = true
        window.title = name
        window.hasShadow = true
        if isPopupWindow, let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.worksWhenModal = true
        }
        
        if style.contains(.acceptFileDrop) {
            view.registerForDraggedTypes([.fileURL])
        }
        if isPopupWindow {
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        } else if style.contains(.utilityWindow) {
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.utilityWindow)))
        }

        window.center()
        
        self.postWindowEvent(
            WindowEvent(type: .created,
                        window: self,
                        windowFrame: self.windowFrame,
                        contentBounds: self.contentBounds,
                        contentScaleFactor: self.contentScaleFactor))
    }

    func show() {
        if let window = view?.window {
            if window.styleMask.contains(.nonactivatingPanel) {
                window.orderFrontRegardless()
            } else {
                window.orderFront(nil)
            }

            self.postWindowEvent(type: .shown)
        }
    }

    func hide() {
        if let window = view?.window {
            window.resignKey()
            window.orderOut(nil)

            self.postWindowEvent(type: .hidden)
        }
    }

    func activate() {
        if let window = view?.window {
            if window.styleMask.contains(.nonactivatingPanel) {
                window.orderFrontRegardless()
            } else if window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
            if let view {
                view.visible = true
                view.activated = true
            }

            if window.isKeyWindow == false {
                if window.isVisible {
                    // failed to become key window, but displayed.
                    self.postWindowEvent(type: .shown)
                }
            }
        }
    }

    func minimize() {
        view?.window?.miniaturize(nil)
    }

    func center() {
        view?.window?.center()
    }

    func requestToClose() -> Bool {
        var close = true
        if self.isValid {
            close = self.delegate?.shouldClose(window: self) ?? true
        }
        if close {
            self.close()
        }
        return close
    }

    func close() {
        if let window {
            _menuController?.invalidate()
            _menuController = nil

            // close all modal windows
            let entries = self.modalWindowQueue
            self.modalWindowQueue.removeAll()
            let completionHandlers = entries.compactMap { $0.completionHandler }
            entries.forEach {
                let modalWindow = $0.window
                modalWindow.removeEventObserver(self)
                if let nsWindow = modalWindow.window {
                    window.endSheet(nsWindow)
                }
                modalWindow.close()
            }
            if !completionHandlers.isEmpty {
                Task { completionHandlers.forEach { $0() } }
            }

            window.close()
            self.view = nil
            self.window = nil
        }
    }
    
    private static var hideCursorCount = 0

    func showMouse(_ show: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            if show {
                if CGDisplayShowCursor(CGMainDisplayID()) == .success {
                    Self.hideCursorCount -= 1
                }
            } else {
                if CGDisplayHideCursor(CGMainDisplayID()) == .success {
                    Self.hideCursorCount += 1
                }
            }
        }
    }

    func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return Self.hideCursorCount <= 0
        }
        return false
    }

    func setCursor(_ cursor: Cursor?, forDeviceID deviceID: Int) {
        guard deviceID == 0 else { return }

        let nativeCursor = cursor.flatMap(makeAppKitCursor)
        if cursor != nil && nativeCursor == nil {
            Log.error("Unable to create AppKit cursor for window: \(title)")
            return
        }

        let previousNativeCursor = view?.cursorOverride
        cursorOverride = cursor
        view?.cursorOverride = nativeCursor
        if cursor == nil,
           let previousNativeCursor,
           NSCursor.current === previousNativeCursor {
            NSCursor.arrow.set()
        }
    }

    func cursor(forDeviceID deviceID: Int) -> Cursor? {
        deviceID == 0 ? cursorOverride : nil
    }

    func lockMouse(_ hold: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view?.mouseLocked = hold
        }
    }

    func isMouseLocked(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.view?.mouseLocked ?? false
        }
        return false
    }

    func setMousePosition(_ pos: CGPoint, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view?.mousePosition = pos
        }
    }

    func mousePosition(forDeviceID deviceID: Int) -> CGPoint? {
        if deviceID == 0 {
            return self.view?.mousePosition
        }
        return nil
    }
 
    func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            self.view?.textInput = enable
        }
    }
    
    func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return self.view?.textInput ?? false
        }
        return false
    }

    func resetTextComposition(
        _ emitEvents: Bool,
        forDeviceID deviceID: Int
    ) -> String? {
        guard deviceID == 0 else { return nil }
        return self.view?.resetTextComposition(emitEvents)
    }
    
    func convertPointToScreen(_ point: CGPoint) -> CGPoint {
        if let view, let window {
            let ptWindow = view.convert(point, to: nil)
            let ptScreen = window.convertPoint(toScreen: ptWindow)
            if let screen = window.screen {
                let referenceY = AppKitScreen.desktopTop(fallback: screen)
                return AppKitScreen.topLeftPoint(
                    fromNative: ptScreen,
                    referenceY: referenceY
                )
            }
            return ptScreen
        }
        return point
    }
    
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint {
        if let view, let window {
            var nativePoint = point
            if let screen = window.screen {
                let referenceY = AppKitScreen.desktopTop(fallback: screen)
                nativePoint = AppKitScreen.nativePoint(
                    fromTopLeft: point,
                    referenceY: referenceY
                )
            }
            let ptWindow = window.convertPoint(fromScreen: nativePoint)
            return view.convert(ptWindow, from: nil)
        }
        return point
    }

    var canPresentModalWindow: Bool {
        self.window != nil
    }

    var modalWindows: [any Window] {
        self.modalWindowQueue.map { $0.window }
    }

    func presentModalWindow(_ window: any Window, completionHandler: (()->Void)?) -> Bool {
        guard let modalWindow = window as? AppKitWindow else {
            Log.err("Window.presentModalWindow failed: incompatible window type.")
            return false
        }

        if let host = self.window, let modal = modalWindow.window {
            self.modalWindowQueue.append(
                ModalQueueEntry(window: modalWindow,
                                completionHandler: completionHandler))
            // modalWindow is held strongly by modalWindowQueue, so it cannot be nil here.
            host.beginSheet(modal) { [weak self, modalWindow] response in
                Log.debug("Modal window sheet ended with response: \(response.rawValue)")
                guard let self else { return }
                if let index = self.modalWindowQueue
                    .firstIndex(where: { $0.window === modalWindow }) {
                    // remove all entries up to and including the matched entry
                    // (earlier entries may have been orphaned if NSWindow skipped their callbacks)
                    let handlers = self.modalWindowQueue[...index].compactMap { $0.completionHandler }
                    self.modalWindowQueue.removeSubrange(...index)
                    handlers.forEach { $0() }
                }
            }
            return true
        }
        Log.err("Window.presentModalWindow failed: invalid window.")
        return false
    }

    func dismissModalWindow(_ window: any Window) -> Bool {
        guard let modalWindow = window as? AppKitWindow else {
            Log.err("Window.dismissModalWindow failed: incompatible window type.")
            return false
        }

        if let host = self.window, let modalWindow = modalWindow.window {
            host.endSheet(modalWindow)
            return true
        }
        Log.err("Window.dismissModalWindow failed: invalid window.")
        return false
    }

    var screen: (any Screen)? {
        if let screen = window?.screen {
            return AppKitScreen(screen)
        }
        return nil
    }
}

#endif //if ENABLE_APPKIT
