//
//  File: AppKitView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
import AppKit

class AppKitView: NSView, NSTextInputClient, NSWindowDelegate {

    var holdMouse: Bool = false
    var textInput: Bool = false
    var modifierKeyFlags: UInt = 0
    var markedText: String = ""

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

    // MARK: - Event
    func postTextInputEvent(_: String) {
    }

    func postTextCompositingEvent(_: String) {
    }
}
#endif //if ENABLE_APPKIT
