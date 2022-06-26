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

    var holdMouse: Bool = false
    var textInput: Bool = false
    var modifierKeyFlags: NSEvent.ModifierFlags = []
    var markedText: String = ""

    weak var proxyWindow: AppKitWindow?

    var isFliped: Bool { true } // upper-left is origin

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
            self.postTextCompositingEvent("")
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

                self.postTextCompositingEvent(str)
            } else {
                self.postTextCompositingEvent("")

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
    // MARK: - Event
    func postWindowEvent(type: WindowEventType) {
    }

    func postMouseEvent(_ event: NSEvent) {
        if let window = self.proxyWindow {
            var deviceType: MouseEventDevice = .genericMouse
            var eventType: MouseEventType
            var pressure: Float = 0.0
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
                pressure = event.pressure
                tilt = event.tilt
            case .pressure:
                deviceType = .stylus
                eventType = .pointing
                pressure = event.pressure
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

    func postTextCompositingEvent(_ text: String) {
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
