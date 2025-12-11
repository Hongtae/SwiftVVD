//
//  File: AppKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
@_implementationOnly import AppKit

nonisolated(unsafe) private var hideCursorCount = 0

@MainActor
final class AppKitWindow: Window {
    
    var activated: Bool { self.view?.activated ?? false }
    var visible: Bool { self.view?.visible ?? false }
    
    var resolution: CGSize {
        get {
            if let nsView {
                let pixelBounds = nsView.convertToBacking(nsView.bounds)
                return CGSize(width: pixelBounds.width, height: pixelBounds.height)
            }
            return .zero
        }
        set (value) {
            if nsView?.window?.contentView === self.view {
                let window = nsView!.window!
                let origin = self.origin
                let pixelBounds = window.convertFromBacking(
                    NSMakeRect(0, 0, value.width, value.height))
                let rect = CGRect(origin: .zero,
                                  size: CGSize(width: pixelBounds.width,
                                               height: pixelBounds.height))
                let frame = window.frameRect(forContentRect: rect)
                window.setContentSize(frame.size)
                if origin == self.origin {
                    window.displayIfNeeded()
                } else {
                    self.origin = origin
                }
            } else {
                if let s = nsView?.convertFromBacking(value) {
                    nsView?.frame.size = s
                    nsView?.window?.layoutIfNeeded()
                }
            }
        }
    }

    var contentBounds: CGRect { self.view?.contentBounds ?? .zero }
    var windowFrame: CGRect { self.view?.windowFrame ?? .zero }
    var contentScaleFactor: CGFloat { self.view?.contentScaleFactor ?? 1.0 }

    var title: String {
        get { nsView?.window?.title ?? "" }
        set { nsView?.window?.title = newValue }
    }

    private var window: NSWindow?
    private var view: AppKitView?
    var nsView: NSView? { view as? NSView }

    var origin: CGPoint {
        get {
            if let nsView {
                if nsView.window?.contentView === self.view {
                    let frame = nsView.window!.frame
                    if let screen = nsView.window?.screen {
                        let height = screen.frame.height
                        return CGPoint(x: frame.minX, y: height - frame.maxY)
                    }
                    return frame.origin
                } else {
                    return nsView.frame.origin
                }
            }
            return .zero
        }
        set(value) {
            if let nsView {
                if nsView.window?.contentView === self.view {
                    let window = nsView.window!
                    if let screen = window.screen {
                        let height = screen.frame.height
                        let y = height - value.y
                        window.setFrameTopLeftPoint(NSPoint(x: value.x, y: y))
                    } else {
                        window.setFrameOrigin(value)
                    }
                    window.displayIfNeeded()
                } else {
                    nsView.frame.origin = value
                    nsView.window?.layoutIfNeeded()
                }
            }
        }
    }

    var contentSize: CGSize {
        get {
            if let nsView {
                var bounds = nsView.bounds
                if nsView.window != nil {
                    bounds = nsView.convert(bounds, to: nil)
                }
                return CGSize(width: bounds.width, height: bounds.height)
            }
            return .zero
        }
        set(value) {
            if let nsView {
                if nsView.window?.contentView === self.view {
                    let origin = self.origin
                    let window = nsView.window!
                    let rect = CGRect(origin: .zero, size: value)
                    let frame = window.frameRect(forContentRect: rect)
                    window.setContentSize(frame.size)
                    if origin == self.origin {
                        window.displayIfNeeded()
                    } else {
                        self.origin = origin
                    }
                } else {
                    nsView.frame.size = value
                    nsView.window?.layoutIfNeeded()
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
    
    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {
        var styleMask: NSWindow.StyleMask = []
        let backingStoreType: NSWindow.BackingStoreType = .buffered
        let contentRect = NSMakeRect(0, 0, 640, 480)
        
        if style.contains(.title)           { styleMask.insert(.titled) }
        if style.contains(.closeButton)     { styleMask.insert(.closable) }
        if style.contains(.minimizeButton)  { styleMask.insert(.miniaturizable) }
        if style.contains(.maximizeButton)  {  }
        if style.contains(.resizableBorder) { styleMask.insert(.resizable) }
        
        var windowType: NSWindow.Type = NSWindow.self
        
        if style.contains(.auxiliaryWindow) {
            styleMask.insert(.utilityWindow)
            windowType = NSPanel.self
        }
        
        let window = windowType.init(contentRect: contentRect,
                                     styleMask: styleMask,
                                     backing: backingStoreType,
                                     defer: true)
        self.window = window
        self.delegate = delegate
        let view = makeAppKitView(frame: contentRect)
        self.view = view
        view.proxyWindow = self
        
        window.contentView = (view as! NSView)
        window.delegate = (view as! NSWindowDelegate)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.allowsConcurrentViewDrawing = true
        window.title = name
        window.hasShadow = true
        
        if style.contains(.acceptFileDrop) {
            (view as! NSView).registerForDraggedTypes([.fileURL])
        }
        if style.contains(.auxiliaryWindow) {
            let levelKey: CGWindowLevelKey = .utilityWindow
            window.level = .init(Int(levelKey.rawValue))
        }
        
        self.postWindowEvent(
            WindowEvent(type: .created,
                        window: self,
                        windowFrame: self.windowFrame,
                        contentBounds: self.contentBounds,
                        contentScaleFactor: self.contentScaleFactor))
    }

    func show() {
        if let window = nsView?.window {
            window.orderFront(nil)

            self.postWindowEvent(type: .shown)
        }
    }

    func hide() {
        if let window = nsView?.window {
            window.resignKey()
            window.orderOut(nil)

            self.postWindowEvent(type: .hidden)
        }
    }

    func activate() {
        if let window = nsView?.window {
            if window.canBecomeKey {
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
        nsView?.window?.miniaturize(nil)
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
            window.close()
            self.view = nil
            self.window = nil

            self.postWindowEvent(type: .closed)
        }
    }
    
    func showMouse(_ show: Bool, forDeviceID deviceID: Int) {
        if deviceID == 0 {
            if show {
                if CGDisplayShowCursor(CGMainDisplayID()) == .success {
                    hideCursorCount -= 1
                }
            } else {
                if CGDisplayHideCursor(CGMainDisplayID()) == .success {
                    hideCursorCount += 1
                }
            }
        }
    }

    func isMouseVisible(forDeviceID deviceID: Int) -> Bool {
        if deviceID == 0 {
            return hideCursorCount >= 0
        }
        return false
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
    
    func convertPointToScreen(_ point: CGPoint) -> CGPoint {
        if let nsView, let window {
            let ptWindow = nsView.convert(point, to: nil)
            var ptScreen = window.convertPoint(toScreen: ptWindow)
            if let frame = window.screen?.frame {
                ptScreen.y = frame.height - ptScreen.y
            }
            return ptScreen
        }
        return point
    }
    
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint {
        if let nsView, let window {
            var point = point
            if let frame = window.screen?.frame {
                point.y = frame.minY + (frame.height - point.y)
            }
            let ptWindow = window.convertPoint(fromScreen: point)
            return nsView.convert(ptWindow, from: nil)
        }
        return point
    }
}

#endif //if ENABLE_APPKIT
