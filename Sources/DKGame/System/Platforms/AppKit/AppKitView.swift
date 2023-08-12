//
//  File: AppKitView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
import AppKit


private let LEFT_SHIFT_BIT = UInt(0x20002)
private let RIGHT_SHIFT_BIT = UInt(0x20004)
private let LEFT_CONTROL_BIT = UInt(0x40001)
private let RIGHT_CONTROL_BIT = UInt(0x42000)
private let LEFT_ALTERNATE_BIT = UInt(0x80020)
private let RIGHT_ALTERNATE_BIT = UInt(0x80040)
private let LEFT_COMMAND_BIT = UInt(0x100008)
private let RIGHT_COMMAND_BIT = UInt(0x100010)


class AppKitView: NSView, NSTextInputClient, NSWindowDelegate {

    var mouseLocked: Bool = false {
        didSet {
            CGAssociateMouseAndMouseCursorPosition( (!mouseLocked) ? 1 : 0 );
        }
    }

    var activated: Bool = false
    var visible: Bool = false

    var textInput: Bool = false
    var modifierKeyFlags: NSEvent.ModifierFlags = []
    var markedText: String = ""

    weak var proxyWindow: AppKitWindow?

    override var isFlipped: Bool { true } // upper-left is origin
    override var acceptsFirstResponder: Bool { true }

    var observers: [NSObjectProtocol] = []

    var contentBounds: CGRect {
        var rect = self.bounds
        if self.window != nil {
            rect = self.convert(rect, to: nil)
        }
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var windowFrame: CGRect {
        let rect = self.window?.frame ?? self.frame
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var contentScaleFactor: CGFloat {
        return self.window?.backingScaleFactor ?? 1.0
    }

    var mousePosition: CGPoint {
        get {
            // get mouse pos with screen-space
            let ptScreen = NSEvent.mouseLocation
            // convert pos to window-space
            let ptWindow = self.window?.convertPoint(fromScreen: ptScreen) ?? ptScreen
            // convert pos to view-space
            return self.convert(ptWindow, from: nil)
        }
        set(pt) {
            let ptInWindow = self.convert(pt, to: nil)
            let screenPos = self.window?.convertPoint(toScreen: ptInWindow) ?? ptInWindow

            let toMove = CGPoint(x: screenPos.x,
                                 y: CGFloat(CGDisplayPixelsHigh(CGMainDisplayID())) - screenPos.y)
            CGWarpMouseCursorPosition(toMove)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    func setup() {
        self.canDrawConcurrently = true
        let queue = OperationQueue.main
        let center = NotificationCenter.default
        self.observers = [
            center.addObserver(forName: NSApplication.didHideNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.applicationDidHide(notification)
                               },
            center.addObserver(forName: NSApplication.didUnhideNotification,
                               object: nil,
                               queue: queue) { [weak self](notification) in
                                   self?.applicationDidUnhide(notification)
                               }
        ]
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func draw(_ dirtyRect: NSRect) {
//        NSColor(red: 1, green: 1, blue: 1, alpha: 1).setFill()
//        dirtyRect.fill()

        self.postWindowEvent(type: .update)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Mouse Event
    override func mouseDown(with event: NSEvent)        { self.handleMouseDown(event: event) }
    override func rightMouseDown(with event: NSEvent)   { self.handleMouseDown(event: event) }
    override func otherMouseDown(with event: NSEvent)   { self.handleMouseDown(event: event) }

    override func mouseMoved(with event: NSEvent)           { self.handleMouseMove(event: event) }
    override func mouseDragged(with event: NSEvent)         { self.handleMouseMove(event: event) }
    override func rightMouseDragged(with event: NSEvent)    { self.handleMouseMove(event: event) }
    override func otherMouseDragged(with event: NSEvent)    { self.handleMouseMove(event: event) }

    override func mouseUp(with event: NSEvent)      { self.handleMouseUp(event: event) }
    override func rightMouseUp(with event: NSEvent) { self.handleMouseUp(event: event) }
    override func otherMouseUp(with event: NSEvent) { self.handleMouseUp(event: event) }

    override func scrollWheel(with event: NSEvent)  { self.postMouseEvent(event) }

//    override func mouseEntered(with event: NSEvent) {}
//    override func mouseExited(with event: NSEvent) {}

    func handleMouseDown(event: NSEvent) {
        if self.textInput { self.unmarkText() }
        self.postMouseEvent(event)
    }

    func handleMouseUp(event: NSEvent) {
        if self.textInput { self.unmarkText() }
        self.postMouseEvent(event)
    }

    func handleMouseMove(event: NSEvent) {
        if event.deltaX == 0 && event.deltaY == 0 { return }
        self.postMouseEvent(event)
    }

    // MARK: - Tablet Event
    override func pressureChange(with event: NSEvent)   { self.postMouseEvent(event) }
    override func tabletPoint(with event: NSEvent)      { self.postMouseEvent(event) }
    override func tabletProximity(with event: NSEvent)  { self.postMouseEvent(event) }

    // MARK: - Keyboard Event
    override func keyDown(with event: NSEvent) {
        if self.textInput {
            self.inputContext?.handleEvent(event)
        }
        if event.isARepeat == false {
            self.postKeyboardEvent(type: .keyDown, keyCode: event.keyCode)
        }
    }

    override func keyUp(with event: NSEvent) {
        if self.textInput {
        }
        self.postKeyboardEvent(type: .keyUp, keyCode: event.keyCode)
    }

    override func flagsChanged(with event: NSEvent) {
        self.updateModifier(flags: event.modifierFlags)
    }

    func updateModifier(flags: NSEvent.ModifierFlags) {
        let updateKey = { (modifier: NSEvent.ModifierFlags, virtualKey: VirtualKey) in
            if flags.contains(modifier) {
                if self.modifierKeyFlags.contains(modifier) == false {
                    self.postKeyboardEvent(type: .keyDown, mappedVKey: .capslock)
                }
            } else {
                if self.modifierKeyFlags.contains(modifier) {
                    self.postKeyboardEvent(type: .keyUp, mappedVKey: .capslock)
                }
            }
        }
        // capsLock
        updateKey(.capsLock, .capslock)
        // l-shift
        updateKey(.init(rawValue: LEFT_SHIFT_BIT), .leftShift)
        // r-shift
        updateKey(.init(rawValue: RIGHT_SHIFT_BIT), .rightShift)
        // l-option
        updateKey(.init(rawValue: LEFT_ALTERNATE_BIT), .leftOption)
        // r-option
        updateKey(.init(rawValue: RIGHT_ALTERNATE_BIT), .rightOption)
        // l-command
        updateKey(.init(rawValue: LEFT_COMMAND_BIT), .leftCommand)
        // r-command
        updateKey(.init(rawValue: RIGHT_COMMAND_BIT), .rightCommand)
        // fn
        updateKey(.function, .fn)

        self.modifierKeyFlags = flags
    }

    // MARK: - NSTextInputClient
    func insertText(_ string: Any, replacementRange: NSRange) {
        var str = ""
        if let string = string as? NSString {
            str = string as String
        } else if let string = string as? NSAttributedString {
            str = string.string as String
        }

        self.postTextInputEvent(str)

        if self.markedText.count > 0 {
            self.postTextCompositionEvent("")
        }

        self.markedText = ""
        self.inputContext?.discardMarkedText()
        self.inputContext?.invalidateCharacterCoordinates()
    }

    override func doCommand(by selector: Selector) {
        let textBySelector: [Selector: String] = [
            #selector(insertLineBreak(_:)): "\r",
            #selector(insertNewline(_:)): "\n",
            #selector(insertTab(_:)): "\t",
            #selector(deleteBackward(_:)): "\u{8}", // \b
            #selector(deleteBackwardByDecomposingPreviousCharacter(_:)): "\u{8}",
            #selector(cancelOperation(_:)): "\u{27}", // \e (esc)
        ]

        if let text = textBySelector[selector] {
            self.insertText(text, replacementRange:NSMakeRange(NSNotFound, 0))
        } else {
            let event = self.window!.currentEvent!
            let key = VirtualKey.from(code: event.keyCode)

            Log.err("[NSTextInput] doCommandBySelector:(\(selector)) for key:(\(key)) not processed.")
        }

        self.markedText = ""
        self.inputContext?.discardMarkedText()
        self.inputContext?.invalidateCharacterCoordinates()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if self.textInput {
            var str = ""
            if let string = string as? NSString {
                str = string as String
            } else if let string = string as? NSAttributedString {
                str = string.string as String
            }

            if str.isEmpty == false {
                self.markedText = str
                Log.debug("self.markedText: \(self.markedText)")

                self.postTextCompositionEvent(str)
            } else {
                self.postTextCompositionEvent("")

                self.markedText = ""
                self.inputContext?.discardMarkedText()
            }
            self.inputContext?.invalidateCharacterCoordinates() // recentering
        } else {
            self.markedText = ""
            self.inputContext?.discardMarkedText()
        }
    }

    func unmarkText() {
        if self.textInput && self.markedText.count > 0 {
            self.insertText(self.markedText, replacementRange: NSMakeRange(NSNotFound, 0))
        }
        self.markedText = ""
        self.inputContext?.discardMarkedText()
    }

    func selectedRange() -> NSRange {
        return NSMakeRange(NSNotFound, 0)
    }

    func markedRange() -> NSRange {
        if self.markedText.count > 0 {
            return NSMakeRange(0, self.markedText.count)
        }
        return NSMakeRange(NSNotFound, 0)
    }

    func hasMarkedText() -> Bool {
        return self.markedText.isEmpty == false
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        return .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        return NSNotFound
    }

    // MARK: - NSDraggingDestination
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return self.dragOperationCallback(sender) { (files, position) -> DragOperation in
            return self.proxyWindow!.delegate!.draggingEntered(target: self.proxyWindow!, position: position, files: files)
        }
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        return false
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return self.dragOperationCallback(sender) { (files, position) -> DragOperation in
            return self.proxyWindow!.delegate!.draggingUpdated(target: self.proxyWindow!, position: position, files: files)
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let sender = sender {
            _=self.dragOperationCallback(sender) { (files, position) -> DragOperation in
                self.proxyWindow!.delegate!.draggingExited(target: self.proxyWindow!, files: files)
                return .none
            }
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dragOperation = self.dragOperationCallback(sender) { (files, position) -> DragOperation in
            return self.proxyWindow!.delegate!.draggingDropped(target: self.proxyWindow!, position: position, files: files)
        }
        return dragOperation != []
    }

    func dragOperationCallback(_ sender: NSDraggingInfo,
                               _ callback: (_:[String], _:CGPoint) -> DragOperation) -> NSDragOperation {
        if let _ = self.proxyWindow?.delegate {
            if sender.draggingDestinationWindow === self.window {
                let pboard = sender.draggingPasteboard
                if pboard.availableType(from: [.fileURL]) == .fileURL {
                    if let fileURLs = pboard.propertyList(forType: .fileURL) as? [URL] {
                        let files = fileURLs.map{ $0.absoluteString }
                        let location = self.convert(sender.draggingLocation, from: nil)

                        var dragOperation = sender.draggingSourceOperationMask
                        switch callback(files, location) {
                        case .copy:
                            dragOperation = dragOperation.intersection(.copy)
                        case .move:
                            dragOperation = dragOperation.intersection(.move)
                        case .link:
                            dragOperation = dragOperation.intersection(.link)
                        case .none:
                            dragOperation = dragOperation.intersection([])
                        default:
                            dragOperation = dragOperation.intersection(.generic)
                        }
                        return dragOperation
                    }
                }
            }
        }
        return []
    }

    // MARK: - NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if self.window === sender {
           return self.proxyWindow?.delegate?.shouldClose(window: self.proxyWindow!) ?? true
        }
        return true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if self.window === sender {
            var contentRect = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize))
            if let size = self.proxyWindow?.delegate?.minimumContentSize(window: self.proxyWindow!) {
                contentRect.size.width = max(contentRect.size.width, size.width)
                contentRect.size.height = max(contentRect.size.height, size.height)
            }
            if let size = self.proxyWindow?.delegate?.maximumContentSize(window: self.proxyWindow!) {
                if size.width > 0 {
                    contentRect.size.width = min(contentRect.size.width, size.width)
                }
                if size.height > 0 {
                    contentRect.size.height = min(contentRect.size.height, size.height)
                }
            }

            let rect = sender.frameRect(forContentRect: contentRect)
            return NSSize(width: rect.width, height: rect.height)
        }
        return frameSize
    }

    func windowDidResize(_ notification: Notification) {
        //    NSRect rc = [[notification object] frame];
        //    NSRect rc = [self bounds];
        //    DKLog("Window resized. (%f x %f)\n", rc.size.width, rc.size.height);

        if notification.object as? NSWindow === self.window {
            self.postWindowEvent(type: .resized)
        }
     }

    func windowWillMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            self.postWindowEvent(type: .inactivated)
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            self.visible = false
            self.postWindowEvent(type: .minimized)
        }
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            self.visible = true
            self.postWindowEvent(type: .shown)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            self.activated = true
            self.visible = true
            let currentEvent = NSApp.currentEvent!
            self.postWindowEvent(type: .activated)
            self.updateModifier(flags: currentEvent.modifierFlags)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            if self.textInput {
                self.unmarkText()
            }
            self.activated = false
            self.postWindowEvent(type: .inactivated)
        }
    }

    func windowDidMove(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            self.postWindowEvent(type: .moved)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === self.window {
            DispatchQueue.main.async {
                self.postWindowEvent(type: .closed)
            }
        }
    }

    // MARK: - NSApplication Notifications
    func applicationDidHide(_ notification: Notification) {
        if self.window?.isVisible == true {
            self.activated = false
            self.visible = false
            self.postWindowEvent(type: .hidden)
        }
    }

    func applicationDidUnhide(_ notification: Notification) {
        if self.window?.isVisible == true {
            self.visible = true
            self.postWindowEvent(type: .shown)
            if self.window?.isKeyWindow == true {
                self.activated = true
                self.postWindowEvent(type: .activated)
            }
        }
    }

    // MARK: - Event
    func postWindowEvent(type: WindowEventType) {
        if let window = self.proxyWindow {
            window.postWindowEvent(
                WindowEvent(type: type,
                            window: window,
                            windowFrame: self.windowFrame,
                            contentBounds: self.contentBounds,
                            contentScaleFactor: self.contentScaleFactor))
        }
    }

    func postMouseEvent(_ event: NSEvent) {
        if let window = self.proxyWindow {
            var deviceType: MouseEventDevice = .genericMouse
            var eventType: MouseEventType
            var pressure: CGFloat = 0.0
            var tilt: CGPoint = .zero

            switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                eventType = .buttonDown
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                eventType = .buttonUp
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                eventType = .move
            case .scrollWheel:
                eventType = .wheel
            case .tabletPoint, .tabletProximity:
                deviceType = .stylus
                eventType = .pointing
                pressure = CGFloat(event.pressure)
                tilt = event.tilt
            case .pressure:
                deviceType = .stylus
                eventType = .pointing
                pressure = CGFloat(event.pressure)
            default:    // unsupported event
                return
            }

            let location = self.convert(event.locationInWindow, from: nil)
            var delta: CGPoint = .zero
            if eventType == .move {
                delta.x = event.deltaX
                delta.y = event.deltaY
            } else if eventType == .wheel {
                delta.x = event.scrollingDeltaX
                delta.y = event.scrollingDeltaY
            }

            let deviceID = 0;
            let buttonID = event.buttonNumber

            window.postMouseEvent(MouseEvent(type: eventType,
                                             window: window,
                                             device: deviceType,
                                             deviceID: deviceID,
                                             buttonID: buttonID,
                                             location: location,
                                             delta: delta,
                                             tilt: tilt,
                                             pressure: pressure))
        }
    }

    func postKeyboardEvent(type: KeyboardEventType, keyCode: UInt16) {
        let mappedVKey = VirtualKey.from(code: keyCode)
        if mappedVKey != .none {
            self.postKeyboardEvent(type: type, mappedVKey: mappedVKey)
        }
    }

    func postKeyboardEvent(type: KeyboardEventType, mappedVKey: VirtualKey) {
        if let window = self.proxyWindow {
            window.postKeyboardEvent(KeyboardEvent(type: type,
                                                   window: window,
                                                   deviceID: 0,
                                                   key: mappedVKey,
                                                   text: ""))
        }
    }

    func postTextInputEvent(_ text: String) {
        if let window = self.proxyWindow {
            window.postKeyboardEvent(KeyboardEvent(type: .textInput,
                                                   window: window,
                                                   deviceID: 0,
                                                   key: .none,
                                                   text: text))
        }
    }

    func postTextCompositionEvent(_ text: String) {
        if let window = self.proxyWindow {
            window.postKeyboardEvent(KeyboardEvent(type: .textComposition,
                                                   window: window,
                                                   deviceID: 0,
                                                   key: .none,
                                                   text: text))
        }
    }

}
#endif //if ENABLE_APPKIT
