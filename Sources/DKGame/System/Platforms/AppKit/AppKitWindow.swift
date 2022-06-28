//
//  File: AppKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
import AppKit

class MainKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

public class AppKitWindow: Window {
    public var activated: Bool = false
    public var visible: Bool = false
    public var resolution: CGSize = .zero

    public var contentBounds: CGRect {
        var rect = view!.bounds
        if view!.window != nil {
            rect = view!.convert(rect, to: nil)
        }
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    public var windowFrame: CGRect {
        let rect = view!.window?.frame ?? view!.frame
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    public var contentScaleFactor: CGFloat {
        return view!.window?.backingScaleFactor ?? 1.0
    }

    var window: NSWindow?
    var view: NSView?

    public var origin: CGPoint {
        get { .zero }
        set(value) {
        }
    }
    public var contentSize: CGSize {
        get { .zero }
        set(value) {
        }
    }

    public private(set) var delegate: WindowDelegate?

    public required init(name: String, style: WindowStyle, delegate: WindowDelegate?) {
        var styleMask: NSWindow.StyleMask = []
        let backingStoreType: NSWindow.BackingStoreType = .buffered
        let contentRect = NSMakeRect(0, 0, 640, 480)

        if style.contains(.title)           { styleMask.insert(.titled) }
        if style.contains(.closeButton)     { styleMask.insert(.closable) }
        if style.contains(.minimizeButton)  { styleMask.insert(.miniaturizable) }
        if style.contains(.maximizeButton)  {  }
        if style.contains(.resizableBorder) { styleMask.insert(.resizable) }

        self.window = MainKeyWindow(contentRect: contentRect,
                                    styleMask: styleMask,
                                    backing: backingStoreType,
                                    defer: true)

        let view = AppKitView(frame: contentRect)
        view.proxyWindow = self
        self.view = view

        window!.contentView = view
        window!.delegate = view
        window!.isReleasedWhenClosed = false
        window!.acceptsMouseMovedEvents = true
        window!.title = name

        if style.contains(.acceptFileDrop) {
            view.registerForDraggedTypes([.fileURL])
        }

        self.postWindowEvent(WindowEvent(type: .created,
                                         window: self,
                                         windowFrame: self.windowFrame,
                                         contentBounds: self.contentBounds,
                                         contentScaleFactor: self.contentScaleFactor))
    }

    public func show() {

    }
    public func hide() {

    }
    public func activate() {

    }
    public func minimize() {

    }

    public func showMouse(_: Bool, forDeviceID: Int) {

    }
    public func isMouseVisible(forDeviceID: Int) -> Bool {
        false
    }
    public func holdMouse(_: Bool, forDeviceID: Int) {

    }
    public func isMouseHeld(forDeviceID: Int) -> Bool {
        false
    }
    public func setMousePosition(_: CGPoint, forDeviceID: Int) {

    }
    public func mousePosition(forDeviceID: Int) -> CGPoint {
        .zero
    }
 
    public func enableTextInput(_: Bool, forDeviceID: Int) {

    }
    public func isTextInputEnabled(forDeviceID: Int) -> Bool {
        false
    }

    public func addEventObserver(_: AnyObject, handler: @escaping (WindowEvent) -> Void) {
    }

    public func addEventObserver(_: AnyObject, handler: @escaping (MouseEvent) -> Void) {
    }

    public func addEventObserver(_: AnyObject, handler: @escaping (KeyboardEvent) -> Void) {
    }

    public func removeEventObserver(_: AnyObject) {
    }

    func postWindowEvent(_ event: WindowEvent) {
    }

    func postKeyboardEvent(_ event: KeyboardEvent) {
    }

    func postMouseEvent(_ event: MouseEvent) {
    }
}

#endif //if ENABLE_APPKIT
