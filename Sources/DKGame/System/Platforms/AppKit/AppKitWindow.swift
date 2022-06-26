//
//  File: AppKitWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
import AppKit

public class AppKitWindow: Window {
    public var activated: Bool = false
    public var visible: Bool = false
    public var resolution: CGSize = .zero

    public private(set) var contentBounds: CGRect = .null
    public private(set) var windowFrame: CGRect = .null
    public private(set) var contentScaleFactor: CGFloat = 0.0

    var window: NSWindow?

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
