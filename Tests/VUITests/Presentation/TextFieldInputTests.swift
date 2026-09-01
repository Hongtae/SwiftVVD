import XCTest
@testable import VUI
@testable import VVD

final class TextFieldInputTests: XCTestCase {
    // ASSERTIONS textSelectionStructureObserved
    func testTextSelectionStoresAutomaticAffinityAndInsertionState() {
        let text = "value"
        let insertion = TextSelection(insertionPoint: text.startIndex)
        let range = TextSelection(
            range: text.startIndex..<text.index(after: text.startIndex)
        )

        XCTAssertEqual(
            Mirror(reflecting: insertion).children.compactMap(\.label),
            ["indices", "affinity"]
        )
        XCTAssertEqual(insertion.affinity, .automatic)
        XCTAssertTrue(insertion.isInsertion)
        XCTAssertFalse(range.isInsertion)
    }

    // ASSERTIONS textFieldStructureObserved
    func testSimpleAndConfiguredInitializersPreserveActionStorageBoundary() {
        let text = Binding.constant("value")
        let simple = TextField("Simple", text: text)
        let configured = TextField(
            "Configured",
            text: text,
            prompt: Text("Prompt")
        )

        XCTAssertNotNil(simple.state.deprecatedActions)
        XCTAssertNil(configured.state.deprecatedActions)
    }

    // ASSERTIONS textFieldStructureObserved
    // ASSERTIONS textFieldSelectionBindingRuntimeObserved
    func testSelectionInitializerStoresTheExternalSelectionBinding() {
        let model = TextFieldSelectionModel(text: "value")
        let localizedField = TextField(
            "Selected",
            text: model.textBinding,
            selection: model.selectionBinding
        )
        let title = "Selected"
        let stringField = TextField(
            title,
            text: model.textBinding,
            selection: model.selectionBinding
        )
        let resourceField = TextField(
            LocalizedStringResource("Selected"),
            text: model.textBinding,
            selection: model.selectionBinding
        )

        XCTAssertNotNil(localizedField.selection)
        XCTAssertNil(localizedField.state.deprecatedActions)
        XCTAssertNotNil(stringField.selection)
        XCTAssertNil(stringField.state.deprecatedActions)
        XCTAssertNotNil(resourceField.selection)
        XCTAssertNil(resourceField.state.deprecatedActions)
    }

    // ASSERTIONS textFieldCompositionCommitBoundaryObserved
    func testDirectTextInputAppendsCommittedCharacters() {
        var text = ""
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)

        XCTAssertEqual(
            input.handleTextInput("H", committedText: &text),
            .changed
        )
        XCTAssertEqual(
            input.handleTextInput("i", committedText: &text),
            .changed
        )

        XCTAssertEqual(text, "Hi")
        XCTAssertEqual(input.composition, "")
        XCTAssertEqual(input.caretOffset, 2)
    }

    // ASSERTIONS textFieldCompositionReplacementObserved
    func testCompositionReplacesMarkedSnapshotWithoutChangingCommittedText() {
        var input = TextFieldInputState()
        let text = "seed"
        input.setFocused(true, committedText: text)

        input.replaceComposition(with: "ㄱ", committedText: text)
        XCTAssertEqual(input.composition, "ㄱ")
        XCTAssertEqual(input.segments(in: text).0, "seed")

        input.replaceComposition(with: "가", committedText: text)
        XCTAssertEqual(input.composition, "가")

        input.replaceComposition(with: "강", committedText: text)
        XCTAssertEqual(input.composition, "강")
        XCTAssertEqual(text, "seed")
    }

    // ASSERTIONS textFieldCompositionCommitBoundaryObserved
    func testKoreanCompositionCommitsOnlyThroughTextInput() {
        var text = ""
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)

        input.replaceComposition(with: "ㄱ", committedText: text)
        input.replaceComposition(with: "가", committedText: text)
        input.replaceComposition(with: "강", committedText: text)
        XCTAssertEqual(text, "")

        input.replaceComposition(with: "", committedText: text)
        XCTAssertEqual(
            input.handleTextInput("강", committedText: &text),
            .changed
        )
        XCTAssertEqual(
            input.handleTextInput(" ", committedText: &text),
            .changed
        )

        XCTAssertEqual(text, "강 ")
        XCTAssertEqual(input.composition, "")
        XCTAssertEqual(input.caretOffset, 2)
    }

    // ASSERTIONS textFieldCompositionReplacementObserved
    func testCompositionSnapshotMayContainMultipleCharacters() {
        var input = TextFieldInputState()
        input.setFocused(true, committedText: "prefix")

        input.replaceComposition(with: "にほん", committedText: "prefix")
        XCTAssertEqual(input.composition, "にほん")

        input.replaceComposition(with: "日本", committedText: "prefix")
        XCTAssertEqual(input.composition, "日本")
    }

    // ASSERTIONS textFieldCompositionReplacementObserved
    func testRawEditingKeysKeepCommittedAndLatestCompositionSnapshots() {
        var text = ""
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)

        input.replaceComposition(with: "ㄱ", committedText: text)
        input.replaceComposition(with: "가", committedText: text)
        input.replaceComposition(with: "ㄱ", committedText: text)

        XCTAssertFalse(input.handleKeyDown(
            .backspace,
            committedText: &text
        ))
        XCTAssertFalse(input.handleKeyDown(
            .delete,
            committedText: &text
        ))
        XCTAssertEqual(text, "")
        XCTAssertEqual(input.composition, "ㄱ")
        XCTAssertEqual(input.compositionReplacementRange, 0..<0)
    }

    // ASSERTIONS textFieldCompositionCommitBoundaryObserved
    func testCommittedInputWaitsForEmptyCompositionSnapshotToClearMarkedText() {
        var text = ""
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)
        input.replaceComposition(with: "가", committedText: text)

        XCTAssertEqual(
            input.handleTextInput("가", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "가")
        XCTAssertEqual(input.composition, "가")

        input.replaceComposition(with: "", committedText: text)
        XCTAssertEqual(input.composition, "")
    }

    // ASSERTIONS textFieldSelectionCompositionReplacementObserved
    func testCompositionTemporarilyReplacesSelectionUntilCommit() {
        var text = "Alpha beta gamma"
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)
        XCTAssertTrue(input.setSelection(
            0..<5,
            affinity: .upstream,
            committedText: text
        ))

        input.replaceComposition(with: "ㄱ", committedText: text)
        XCTAssertEqual(text, "Alpha beta gamma")
        XCTAssertEqual(input.compositionReplacementRange, 0..<5)
        XCTAssertEqual(input.selectionOffsets, 1..<1)
        XCTAssertEqual(input.displaySegments(in: text).leading, "")
        XCTAssertEqual(input.displaySegments(in: text).trailing, " beta gamma")

        input.replaceComposition(with: "가", committedText: text)
        XCTAssertEqual(text, "Alpha beta gamma")
        input.replaceComposition(with: "", committedText: text)
        XCTAssertEqual(input.selectionOffsets, 0..<0)
        XCTAssertEqual(input.selectionAffinity, .downstream)

        XCTAssertEqual(
            input.handleTextInput("가", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "가 beta gamma")
        XCTAssertNil(input.compositionReplacementRange)
        XCTAssertEqual(input.selectionOffsets, 1..<1)
        XCTAssertEqual(input.selectionAffinity, .upstream)
    }

    func testCaretNavigationAndInsertionUseCharacterBoundaries() {
        var text = "A강B"
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)

        XCTAssertTrue(input.handleKeyDown(.left, committedText: &text))
        XCTAssertEqual(
            input.handleTextInput("🙂", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "A강🙂B")

        XCTAssertEqual(
            input.handleTextInput("\u{8}", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "A강B")
        XCTAssertFalse(input.handleKeyDown(.backspace, committedText: &text))
        XCTAssertEqual(text, "A강B")
    }

    func testForwardDeleteUsesTextInputAndKeepsTheCharacterOffset() {
        var text = "A강🙂B"
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)

        XCTAssertTrue(input.handleKeyDown(.left, committedText: &text))
        XCTAssertTrue(input.handleKeyDown(.left, committedText: &text))

        XCTAssertEqual(
            input.handleTextInput("\u{F728}", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "A강B")
        XCTAssertEqual(input.caretOffset, 2)

        XCTAssertEqual(
            input.handleTextInput("\u{F728}", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "A강")
        XCTAssertEqual(input.caretOffset, 2)
        XCTAssertEqual(
            input.handleTextInput("\u{F728}", committedText: &text),
            .handled
        )
    }

    // ASSERTIONS textFieldSelectionBindingRuntimeObserved
    // ASSERTIONS textFieldTextEditingCommandsTransformationObserved
    func testSelectionReplacementAndTransformationsUseCharacterOffsets() {
        var text = "Alpha beta gamma"
        var input = TextFieldInputState()
        input.setFocused(true, committedText: text)

        XCTAssertTrue(input.setSelection(
            0..<5,
            affinity: .automatic,
            committedText: text
        ))
        XCTAssertEqual(
            input.handleTextInput("Omega", committedText: &text),
            .changed
        )
        XCTAssertEqual(text, "Omega beta gamma")
        XCTAssertEqual(input.selectionOffsets, 5..<5)
        XCTAssertEqual(input.selectionAffinity, .upstream)

        XCTAssertTrue(input.setSelection(
            7..<7,
            affinity: .automatic,
            committedText: text
        ))
        XCTAssertTrue(input.transformSelection(in: &text) {
            $0.uppercased()
        })
        XCTAssertEqual(text, "Omega BETA gamma")
        XCTAssertEqual(input.selectionOffsets, 6..<10)
        XCTAssertEqual(input.selectionAffinity, .upstream)
    }

    // ASSERTIONS textFieldCommandResponderOwnershipObserved
    // ASSERTIONS textFieldTextEditingCommandsValidationObserved
    // ASSERTIONS textFieldTextEditingCommandsTransformationObserved
    func testTextFieldResponderPublishesObservedFindAndTransformSemantics() {
        let model = TextFieldSelectionModel(text: "Alpha beta gamma")
        var fieldState = TextFieldState(displayText: model.text)
        var inputState = TextFieldInputState()
        inputState.setFocused(true, committedText: model.text)

        let responder = TextFieldResponder()
        responder.text = model.textBinding
        responder.selection = model.selectionBinding
        responder.fieldState = Binding(
            get: { fieldState },
            set: { fieldState = $0 }
        )
        responder.inputState = Binding(
            get: { inputState },
            set: { inputState = $0 }
        )

        let selectionEnd = model.text.index(
            model.text.startIndex,
            offsetBy: 5
        )
        model.selection = TextSelection(
            range: model.text.startIndex..<selectionEnd
        )
        responder.synchronizeSelection(model.selection)
        Update.dispatchActions()
        XCTAssertEqual(inputState.selectionOffsets, 0..<5)

        XCTAssertFalse(responder.canPerformTextEditingCommand(.find))
        XCTAssertFalse(responder.canPerformTextEditingCommand(
            .useSelectionForFind
        ))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.jumpToSelection))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.makeUpperCase))

        responder.performTextEditingCommand(.makeUpperCase)
        Update.dispatchActions()

        XCTAssertEqual(model.text, "ALPHA beta gamma")
        XCTAssertEqual(fieldState.displayText, model.text)
        XCTAssertEqual(inputState.selectionOffsets, 0..<5)
        XCTAssertEqual(
            model.selection,
            inputState.textSelection(in: model.text)
        )
    }

    // ASSERTIONS textFieldClipboardEditingRuntimeObserved
    func testTextFieldResponderValidatesAndPerformsClipboardCommands() throws {
        let clipboard = TextFieldTestClipboard()
        let context = TextFieldClipboardAppContext(clipboard: clipboard)
        let previousAppContext = appContext
        appContext = context
        defer { appContext = previousAppContext }

        let model = TextFieldSelectionModel(text: "Alpha beta gamma")
        var fieldState = TextFieldState(displayText: model.text)
        var inputState = TextFieldInputState()
        inputState.setFocused(true, committedText: model.text)

        let responder = TextFieldResponder()
        responder.text = model.textBinding
        responder.selection = model.selectionBinding
        responder.fieldState = Binding(
            get: { fieldState },
            set: { fieldState = $0 }
        )
        responder.inputState = Binding(
            get: { inputState },
            set: { inputState = $0 }
        )

        XCTAssertFalse(responder.canPerformTextEditingCommand(.copy))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.cut))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.paste))

        XCTAssertTrue(inputState.setSelection(
            0..<5,
            affinity: .upstream,
            committedText: model.text
        ))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.copy))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.cut))

        responder.performTextEditingCommand(.copy)
        Update.dispatchActions()
        XCTAssertEqual(
            try clipboard.data(
                forType: ClipboardContentType.utf8PlainText
            ),
            Data("Alpha".utf8)
        )
        XCTAssertEqual(model.text, "Alpha beta gamma")
        XCTAssertEqual(inputState.selectionOffsets, 0..<5)

        responder.performTextEditingCommand(.cut)
        Update.dispatchActions()
        XCTAssertEqual(model.text, " beta gamma")
        XCTAssertEqual(fieldState.displayText, model.text)
        XCTAssertEqual(inputState.selectionOffsets, 0..<0)
        XCTAssertEqual(inputState.selectionAffinity, .downstream)

        clipboard.representations = [
            ClipboardContentType.utf8PlainText: Data("Omega🙂".utf8)
        ]
        clipboard.dataRequestCount = 0
        XCTAssertTrue(responder.canPerformTextEditingCommand(.paste))
        XCTAssertEqual(clipboard.dataRequestCount, 0)
        responder.performTextEditingCommand(.paste)
        Update.dispatchActions()
        XCTAssertEqual(clipboard.dataRequestCount, 1)
        XCTAssertEqual(model.text, "Omega🙂 beta gamma")
        XCTAssertEqual(fieldState.displayText, model.text)
        XCTAssertEqual(inputState.selectionOffsets, 6..<6)
        XCTAssertEqual(inputState.selectionAffinity, .upstream)

        clipboard.representations = ["example/private": Data([0x01])]
        XCTAssertFalse(responder.canPerformTextEditingCommand(.paste))
        responder.performTextEditingCommand(.paste)
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Omega🙂 beta gamma")

        XCTAssertTrue(inputState.setSelection(
            0..<6,
            affinity: .upstream,
            committedText: model.text
        ))
        clipboard.rejectsWrites = true
        responder.performTextEditingCommand(.cut)
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Omega🙂 beta gamma")
        XCTAssertEqual(inputState.selectionOffsets, 0..<6)

        context.clipboard = nil
        XCTAssertFalse(responder.canPerformTextEditingCommand(.copy))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.cut))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.paste))
    }

    func testCaretMetricsUseFontLineHeightAndCompositionWidth() {
        XCTAssertEqual(
            TextFieldCaretMetrics(
                compositionWidth: nil,
                fontLineHeight: 18,
                defaultWidth: 1
            ).size,
            CGSize(width: 1, height: 18)
        )
        XCTAssertEqual(
            TextFieldCaretMetrics(
                compositionWidth: 24,
                fontLineHeight: 31,
                defaultWidth: 1
            ).size,
            CGSize(width: 24, height: 31)
        )
        XCTAssertEqual(
            TextFieldCaretMetrics(
                compositionWidth: 4,
                fontLineHeight: 31,
                defaultWidth: 8
            ).size,
            CGSize(width: 8, height: 31)
        )
    }

    func testCompositionCaretStyleSelectsInsertionPointOrEnclosure() {
        var environment = EnvironmentValues()
        XCTAssertEqual(
            environment.textFieldCompositionCaretStyle,
            .enclosing
        )
        XCTAssertEqual(
            TextFieldCaret.presentation(
                compositionText: "강",
                compositionStyle: environment.textFieldCompositionCaretStyle
            ),
            .enclosing("강")
        )

        environment.textFieldCompositionCaretStyle = .insertionPoint
        XCTAssertEqual(
            TextFieldCaret.presentation(
                compositionText: "にほん",
                compositionStyle: environment.textFieldCompositionCaretStyle
            ),
            .insertionPoint(
                compositionText: "にほん",
                blinks: false
            )
        )
        XCTAssertEqual(
            TextFieldCaret.presentation(
                compositionText: nil,
                compositionStyle: environment.textFieldCompositionCaretStyle
            ),
            .insertionPoint(compositionText: nil, blinks: true)
        )
    }

    func testOnlyInsertionCaretBlinks() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertTrue(TextFieldCaret.isBlinkVisible(at: start, from: start))
        XCTAssertTrue(TextFieldCaret.isBlinkVisible(
            at: start.addingTimeInterval(0.499),
            from: start
        ))
        XCTAssertFalse(TextFieldCaret.isBlinkVisible(
            at: start.addingTimeInterval(0.5),
            from: start
        ))
        XCTAssertTrue(TextFieldCaret.isBlinkVisible(
            at: start.addingTimeInterval(1),
            from: start
        ))
    }

    @MainActor
    func testMountedTextFieldRoutesCompositionAndTogglesPlatformInput() async throws {
        let model = TextFieldInputModel()
        let controller = TextFieldInputHostController(model: model)

        var redraw = false
        func renderFrame(_ tick: UInt64) {
            controller.updateView(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 420, height: 120),
                redraw: &redraw
            ) { _, _ in }
        }
        renderFrame(0)

        var textResponder: TextFieldResponder?
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextFieldResponder {
                textResponder = responder
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)

        controller.focusTextInputResponder(responder)
        Update.dispatchActions()
        await Task.yield()
        renderFrame(1)
        XCTAssertEqual(controller.testWindow.textInputChanges, [
            TextInputChange(enabled: true, deviceID: 0)
        ])

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textComposition,
            window: controller.testWindow,
            text: "ㄱ"
        )))
        Update.dispatchActions()
        renderFrame(2)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(responder.inputState?.wrappedValue.composition, "ㄱ")

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textComposition,
            window: controller.testWindow,
            text: "가"
        )))
        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textComposition,
            window: controller.testWindow,
            text: "ㄱ"
        )))
        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .keyDown,
            window: controller.testWindow,
            key: .backspace
        )))
        Update.dispatchActions()
        renderFrame(3)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(responder.inputState?.wrappedValue.composition, "ㄱ")

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textComposition,
            window: controller.testWindow,
            text: "강"
        )))
        Update.dispatchActions()
        renderFrame(4)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(responder.inputState?.wrappedValue.composition, "강")

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textComposition,
            window: controller.testWindow,
            text: ""
        )))
        Update.dispatchActions()
        renderFrame(5)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(responder.inputState?.wrappedValue.composition, "")

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textInput,
            window: controller.testWindow,
            text: "강"
        )))
        Update.dispatchActions()
        renderFrame(6)
        XCTAssertEqual(model.text, "강")
        XCTAssertEqual(responder.inputState?.wrappedValue.composition, "")

        controller.resignTextInputFocus(responder)
        Update.dispatchActions()
        await Task.yield()
        XCTAssertEqual(controller.testWindow.textInputChanges, [
            TextInputChange(enabled: true, deviceID: 0),
            TextInputChange(enabled: false, deviceID: 0)
        ])
    }

    @MainActor
    func testMountedTextFieldUsesIBeamCursorOnlyWhileHovered() async throws {
        let controller = TextFieldInputHostController(
            model: TextFieldInputModel()
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 120),
            redraw: &redraw
        ) { _, _ in }

        var textResponder: TextFieldResponder?
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextFieldResponder {
                textResponder = responder
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)
        let eventID = EventID(type: HoverEvent.self, serial: 1)

        XCTAssertTrue(responder.updateHoverEvent(
            id: eventID,
            at: CGPoint(x: 10, y: 10),
            time: .zero
        ))
        await Task.yield()
        XCTAssertEqual(controller.testWindow.cursorChanges, [.text(0)])

        XCTAssertTrue(responder.endHoverEvent(
            id: eventID,
            time: Time(seconds: 1)
        ))
        await Task.yield()
        XCTAssertEqual(
            controller.testWindow.cursorChanges,
            [.text(0), .platformDefault(0)]
        )
    }

    @MainActor
    func testMountedTextFieldCursorOptionDisablesIBeamRequest() async throws {
        let controller = TextFieldInputHostController(
            model: TextFieldInputModel(),
            isTextFieldCursorEnabled: false
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 120),
            redraw: &redraw
        ) { _, _ in }

        var textResponder: TextFieldResponder?
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextFieldResponder {
                textResponder = responder
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)

        XCTAssertFalse(responder.updateHoverEvent(
            id: EventID(type: HoverEvent.self, serial: 2),
            at: CGPoint(x: 10, y: 10),
            time: .zero
        ))
        await Task.yield()
        XCTAssertEqual(controller.testWindow.cursorChanges, [])
    }

    // ASSERTIONS textFieldSelectionBindingRuntimeObserved
    func testBackspaceAfterCaretRoundTripKeepsSelectionIndicesValid() throws {
        let model = TextFieldSelectionModel(text: "")
        var fieldState = TextFieldState(displayText: model.text)
        var inputState = TextFieldInputState()
        inputState.setFocused(true, committedText: model.text)

        let responder = TextFieldResponder()
        responder.selection = model.selectionBinding
        responder.fieldState = Binding(
            get: { fieldState },
            set: { fieldState = $0 }
        )
        responder.inputState = Binding(
            get: { inputState },
            set: { inputState = $0 }
        )
        responder.text = Binding(
            get: { model.text },
            set: { value in
                let contractsText = value.count < model.text.count
                model.text = value
                if contractsText {
                    responder.synchronizeSelection(model.selection)
                }
            }
        )

        func send(_ event: KeyboardEvent) {
            XCTAssertTrue(responder.handleTextInputEvent(event))
            Update.dispatchActions()
        }

        for character in ["1", "2", "3", "4"] {
            send(KeyboardEvent(
                type: .textInput,
                window: nil,
                deviceID: 0,
                key: .none,
                text: character
            ))
        }
        send(KeyboardEvent(
            type: .keyDown,
            window: nil,
            deviceID: 0,
            key: .left,
            text: ""
        ))
        send(KeyboardEvent(
            type: .keyDown,
            window: nil,
            deviceID: 0,
            key: .right,
            text: ""
        ))
        send(KeyboardEvent(
            type: .textInput,
            window: nil,
            deviceID: 0,
            key: .none,
            text: "\u{8}"
        ))

        XCTAssertEqual(model.text, "123")
        XCTAssertEqual(inputState.selectionOffsets, 3..<3)
        guard case .selection(let range) = model.selection?.indices else {
            return XCTFail("Expected a single insertion selection")
        }
        XCTAssertEqual(range.lowerBound, model.text.endIndex)
        XCTAssertEqual(range.upperBound, model.text.endIndex)
    }

    @MainActor
    // ASSERTIONS textFieldCommandResponderOwnershipObserved
    // ASSERTIONS textFieldClipboardEditingRuntimeObserved
    // ASSERTIONS textFieldFocusSelectionRuntimeObserved
    func testProductionTextFieldCommandResponderFollowsFocusTransfer() throws {
        let clipboard = TextFieldTestClipboard()
        let previousAppContext = appContext
        appContext = TextFieldClipboardAppContext(clipboard: clipboard)
        defer { appContext = previousAppContext }

        let model = TextFieldCommandFocusModel()
        let controller = TextFieldCommandFocusHostController(model: model)

        var redraw = false
        func renderFrame(_ tick: UInt64) {
            controller.updateView(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 420, height: 180),
                redraw: &redraw
            ) { _, _ in }
        }
        renderFrame(0)

        var responders: [TextFieldResponder] = []
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextFieldResponder {
                responders.append(responder)
            }
            return .next
        }
        XCTAssertEqual(responders.count, 2)
        let first = try XCTUnwrap(responders.first {
            $0.text?.wrappedValue == model.first
        })
        let second = try XCTUnwrap(responders.first {
            $0.text?.wrappedValue == model.second
        })

        model.firstSelection = selection(
            in: model.first,
            offsets: 0..<5,
            affinity: .upstream
        )
        controller.focusTextInputResponder(first)
        Update.dispatchActions()
        XCTAssertEqual(first.inputState?.wrappedValue.selectionOffsets, 0..<5)
        controller.performTextEditingCommand(.makeUpperCase)
        Update.dispatchActions()
        XCTAssertEqual(model.first, "ALPHA")
        XCTAssertEqual(model.second, "bravo")
        controller.performTextEditingCommand(.copy)
        Update.dispatchActions()
        XCTAssertEqual(
            try clipboard.data(
                forType: ClipboardContentType.utf8PlainText
            ),
            Data("ALPHA".utf8)
        )

        model.secondSelection = selection(
            in: model.second,
            offsets: 0..<5,
            affinity: .upstream
        )
        controller.focusTextInputResponder(second)
        Update.dispatchActions()
        XCTAssertEqual(first.inputState?.wrappedValue.selectionOffsets, 0..<0)
        XCTAssertEqual(first.inputState?.wrappedValue.selectionAffinity, .downstream)
        XCTAssertEqual(second.inputState?.wrappedValue.selectionOffsets, 0..<5)
        controller.performTextEditingCommand(.copy)
        Update.dispatchActions()
        XCTAssertEqual(
            try clipboard.data(
                forType: ClipboardContentType.utf8PlainText
            ),
            Data("bravo".utf8)
        )
        controller.performTextEditingCommand(.makeUpperCase)
        Update.dispatchActions()

        XCTAssertFalse(first.canPerformTextEditingCommand(.makeUpperCase))
        XCTAssertTrue(second.canPerformTextEditingCommand(.makeUpperCase))
        XCTAssertEqual(model.first, "ALPHA")
        XCTAssertEqual(model.second, "BRAVO")
    }

    @MainActor
    // ASSERTIONS commandsFocusStoreTransferRuntimeObserved
    // ASSERTIONS commandsFocusStoreRootPublicationRuntimeObserved
    func testFocusStateStorePreservesInternalAndExternalTextFieldLayers() throws {
        let model = TextFieldFocusStateModel()
        let controller = TextFieldFocusStateHostController(model: model)

        var redraw = false
        func renderFrame(_ tick: UInt64) {
            controller.updateView(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 420, height: 180),
                redraw: &redraw
            ) { _, _ in }
            Update.dispatchActions()
        }

        renderFrame(0)
        renderFrame(1)

        let binding = try XCTUnwrap(model.focusBinding)
        var responders: [TextFieldResponder] = []
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextFieldResponder {
                responders.append(responder)
            }
            return .next
        }
        XCTAssertEqual(responders.count, 2)
        let first = try XCTUnwrap(responders.first {
            $0.text?.wrappedValue == model.first
        })
        let second = try XCTUnwrap(responders.first {
            $0.text?.wrappedValue == model.second
        })

        func externalValues(in store: FocusStore) -> Set<TextFieldFocusTarget> {
            guard let plist = store.plists[binding.propertyID] else {
                return []
            }
            var values: Set<TextFieldFocusTarget> = []
            plist.forEachValue(
                forKey: FocusStore.Key<TextFieldFocusTarget?>.self
            ) { entry, _ in
                if let value = entry?.value {
                    values.insert(value)
                }
            }
            return values
        }

        func itemCount(in store: FocusStore) -> Int {
            store.plists.values.reduce(into: 0) { count, plist in
                count += Int(plist.elements?.length ?? 0)
            }
        }

        XCTAssertEqual(controller.resolvedFocusStore.plists.count, 3)
        XCTAssertEqual(itemCount(in: controller.resolvedFocusStore), 4)
        XCTAssertEqual(
            externalValues(in: controller.resolvedFocusStore),
            [.first, .second]
        )
        XCTAssertTrue(controller.resolvedFocusStore.focusedResponders.isEmpty)

        binding.wrappedValue = .first
        renderFrame(2)
        renderFrame(3)
        renderFrame(4)
        XCTAssertTrue(controller.focusedResponder === first)
        XCTAssertEqual(binding.wrappedValue, .first)
        XCTAssertEqual(controller.resolvedFocusStore.plists.count, 3)
        XCTAssertEqual(itemCount(in: controller.resolvedFocusStore), 4)
        XCTAssertEqual(controller.resolvedFocusStore.focusedResponders.count, 2)

        binding.wrappedValue = .second
        renderFrame(5)
        renderFrame(6)
        renderFrame(7)
        XCTAssertTrue(controller.focusedResponder === second)
        XCTAssertEqual(binding.wrappedValue, .second)
        XCTAssertEqual(controller.resolvedFocusStore.plists.count, 3)
        XCTAssertEqual(itemCount(in: controller.resolvedFocusStore), 4)
        XCTAssertEqual(controller.resolvedFocusStore.focusedResponders.count, 2)

        let showsSecond = try XCTUnwrap(model.showsSecondBinding)
        showsSecond.wrappedValue = false
        renderFrame(8)
        renderFrame(9)
        renderFrame(10)
        renderFrame(11)
        XCTAssertNil(controller.focusedResponder)
        XCTAssertNil(binding.wrappedValue)
        XCTAssertEqual(controller.resolvedFocusStore.plists.count, 2)
        XCTAssertEqual(itemCount(in: controller.resolvedFocusStore), 2)
        XCTAssertEqual(
            externalValues(in: controller.resolvedFocusStore),
            [.first]
        )
        XCTAssertTrue(controller.resolvedFocusStore.focusedResponders.isEmpty)

        let currentBinding = try XCTUnwrap(model.focusBinding)
        XCTAssertEqual(currentBinding.propertyID, binding.propertyID)
        let currentLocation = try XCTUnwrap(
            currentBinding._binding.location
                as? FocusStoreLocation<TextFieldFocusTarget?>
        )
        currentBinding.wrappedValue = .second
        renderFrame(12)
        renderFrame(13)
        XCTAssertNil(controller.focusedResponder)
        XCTAssertNil(currentBinding.wrappedValue)
        XCTAssertEqual(currentLocation.deferredUpdate?.0, .second)
        XCTAssertEqual(
            currentLocation.deferredUpdate?.1,
            currentLocation.store.version
        )

        showsSecond.wrappedValue = true
        renderFrame(14)
        renderFrame(15)
        renderFrame(16)
        XCTAssertEqual(controller.resolvedFocusStore.plists.count, 3)
        XCTAssertEqual(itemCount(in: controller.resolvedFocusStore), 4)
        XCTAssertEqual(
            externalValues(in: controller.resolvedFocusStore),
            [.first, .second]
        )
        XCTAssertTrue(controller.resolvedFocusStore.focusedResponders.isEmpty)

        XCTAssertEqual(currentLocation.store.plists.count, 3)
        XCTAssertNotEqual(
            currentLocation.deferredUpdate?.1,
            currentLocation.store.version
        )
        var currentEntries: [FocusStore.Entry<TextFieldFocusTarget?>] = []
        currentLocation.store.plists[currentBinding.propertyID]?.forEachValue(
            forKey: FocusStore.Key<TextFieldFocusTarget?>.self
        ) { entry, _ in
            if let entry {
                currentEntries.append(entry)
            }
        }
        XCTAssertEqual(currentEntries.count, 2)
        let secondEntry = try XCTUnwrap(currentEntries.first {
            $0.value == .second
        })
        XCTAssertTrue(secondEntry.isValid)

        currentLocation.performDeferredUpdate()
        renderFrame(17)
        renderFrame(18)
        renderFrame(19)
        XCTAssertNil(currentLocation.deferredUpdate)
        XCTAssertEqual(currentLocation.store.plists.count, 3)
        XCTAssertFalse(try XCTUnwrap(secondEntry.responder).children.isEmpty)
        var replacementSecond: TextFieldResponder?
        _ = controller.responderNode?.visit { responder in
            guard let responder = responder as? TextFieldResponder,
                  responder.text?.wrappedValue == model.second else {
                return .next
            }
            replacementSecond = responder
            return .cancel
        }
        let focusedReplacementSecond = try XCTUnwrap(replacementSecond)
        XCTAssertTrue(controller.focusedResponder === focusedReplacementSecond)
        XCTAssertEqual(currentBinding.wrappedValue, .second)
        XCTAssertEqual(controller.resolvedFocusStore.focusedResponders.count, 2)

        binding.wrappedValue = nil
        renderFrame(20)
        renderFrame(21)
        renderFrame(22)
        XCTAssertNil(controller.focusedResponder)
        XCTAssertNil(binding.wrappedValue)
        XCTAssertEqual(controller.resolvedFocusStore.plists.count, 3)
        XCTAssertEqual(itemCount(in: controller.resolvedFocusStore), 4)
        XCTAssertTrue(controller.resolvedFocusStore.focusedResponders.isEmpty)
    }

    private func selection(
        in text: String,
        offsets: Range<Int>,
        affinity: TextSelectionAffinity
    ) -> TextSelection {
        let lower = text.index(text.startIndex, offsetBy: offsets.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: offsets.upperBound)
        var selection = TextSelection(range: lower..<upper)
        selection.affinity = affinity
        return selection
    }

    private func keyboardEvent(
        _ type: KeyboardEventType,
        window: any VVD.Window,
        key: VirtualKey = .none,
        text: String = ""
    ) -> KeyboardEvent {
        KeyboardEvent(
            type: type,
            window: window,
            deviceID: 0,
            key: key,
            text: text,
            isRepeat: false,
            modifiers: []
        )
    }
}

private final class TextFieldInputModel {
    var text = ""
}

private final class TextFieldSelectionModel {
    var text: String
    var selection: TextSelection?

    init(text: String) {
        self.text = text
    }

    var textBinding: Binding<String> {
        Binding(
            get: { self.text },
            set: { self.text = $0 }
        )
    }

    var selectionBinding: Binding<TextSelection?> {
        Binding(
            get: { self.selection },
            set: { self.selection = $0 }
        )
    }
}

private final class TextFieldTestClipboard: Clipboard {
    private enum Failure: Error {
        case rejectedWrite
    }

    var representations: [String: Data] = [:]
    var dataRequestCount = 0
    var rejectsWrites = false

    var types: [String] {
        Array(representations.keys)
    }

    func setData(_ representations: [String: Data]) throws {
        if rejectsWrites {
            throw Failure.rejectedWrite
        }
        self.representations = representations
    }

    func data(forType type: String) throws -> Data? {
        dataRequestCount += 1
        return representations[type]
    }
}

private final class TextFieldClipboardAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var clipboard: (any Clipboard)?
    let appWindowsController: AppWindowsController? = nil

    init(clipboard: (any Clipboard)?) {
        self.clipboard = clipboard
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {}

    func checkWindowActivities() {}
}

private final class TextFieldCommandFocusModel {
    var first = "alpha"
    var firstSelection: TextSelection?
    var second = "bravo"
    var secondSelection: TextSelection?
}

private enum TextFieldFocusTarget: Hashable {
    case first
    case second
}

private final class TextFieldFocusStateModel {
    var first = "alpha"
    var second = "bravo"
    var focusBinding: FocusState<TextFieldFocusTarget?>.Binding?
    var showsSecondBinding: Binding<Bool>?

    func capture(
        focus binding: FocusState<TextFieldFocusTarget?>.Binding,
        showsSecond: Binding<Bool>
    ) {
        focusBinding = binding
        showsSecondBinding = showsSecond
    }

    var firstBinding: Binding<String> {
        Binding(
            get: { self.first },
            set: { self.first = $0 }
        )
    }

    var secondBinding: Binding<String> {
        Binding(
            get: { self.second },
            set: { self.second = $0 }
        )
    }
}

private struct TextFieldFocusStateHost: View {
    let model: TextFieldFocusStateModel
    @FocusState private var focused: TextFieldFocusTarget?
    @State private var showsSecond = true

    var body: some View {
        let _ = model.capture(
            focus: $focused,
            showsSecond: $showsSecond
        )
        VStack {
            TextField("First", text: model.firstBinding)
                .focused($focused, equals: .first)
            if showsSecond {
                TextField("Second", text: model.secondBinding)
                    .focused($focused, equals: .second)
            }
        }
        .frame(width: 300)
        .environment(\.defaultFontRenderingMode, .vector())
    }
}

@MainActor
private final class TextFieldFocusStateHostController: WindowController,
    @unchecked Sendable {
    init(model: TextFieldFocusStateModel) {
        super.init(
            content: TextFieldFocusStateHost(model: model),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TextFieldFocusStateHostController.self)
            )
        )
    }
}

@MainActor
private final class TextFieldCommandFocusHostController: WindowController,
    @unchecked Sendable {
    init(model: TextFieldCommandFocusModel) {
        let firstText = Binding<String>(
            get: { model.first },
            set: { model.first = $0 }
        )
        let firstSelection = Binding<TextSelection?>(
            get: { model.firstSelection },
            set: { model.firstSelection = $0 }
        )
        let secondText = Binding<String>(
            get: { model.second },
            set: { model.second = $0 }
        )
        let secondSelection = Binding<TextSelection?>(
            get: { model.secondSelection },
            set: { model.secondSelection = $0 }
        )
        super.init(
            content: VStack {
                TextField(
                    "First",
                    text: firstText,
                    selection: firstSelection
                )
                TextField(
                    "Second",
                    text: secondText,
                    selection: secondSelection
                )
            }
            .frame(width: 300)
            .environment(\.defaultFontRenderingMode, .vector()),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TextFieldCommandFocusHostController.self)
            )
        )
    }
}

@MainActor
private final class TextFieldInputHostController: WindowController,
    @unchecked Sendable {
    let testWindow = TextFieldInputTestWindow()

    override var window: (any VVD.Window)? { testWindow }

    init(
        model: TextFieldInputModel,
        isTextFieldCursorEnabled: Bool = true
    ) {
        let binding = Binding<String>(
            get: { model.text },
            set: { model.text = $0 }
        )
        super.init(
            content: TextField("Input", text: binding)
                .frame(width: 300)
                .environment(
                    \.isTextFieldCursorEnabled,
                    isTextFieldCursorEnabled
                )
                .environment(\.defaultFontRenderingMode, .vector()),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TextFieldInputHostController.self)
            )
        )
    }
}

private struct TextInputChange: Equatable {
    var enabled: Bool
    var deviceID: Int
}

private enum TextInputCursorChange: Equatable {
    case text(Int)
    case platformDefault(Int)
    case other(Int)
}

@MainActor
private final class TextFieldInputTestWindow: VVD.Window {
    var activated = true
    var visible = true
    var contentBounds = CGRect(x: 0, y: 0, width: 420, height: 120)
    var windowFrame = CGRect(x: 0, y: 0, width: 420, height: 120)
    var contentScaleFactor: CGFloat = 1
    var resolution = CGSize(width: 420, height: 120)
    var origin = CGPoint.zero
    var contentSize = CGSize(width: 420, height: 120)
    var title = "Text Input Test"
    weak var delegate: WindowDelegate?
    var screen: (any VVD.Screen)? { nil }
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()
    var textInputChanges: [TextInputChange] = []
    var cursorChanges: [TextInputCursorChange] = []
    private var cursors: [Int: Cursor] = [:]

    required init?(
        name: String,
        style: WindowStyle,
        delegate: WindowDelegate?,
        data: [String: Any]
    ) {
        title = name
        self.delegate = delegate
    }

    init() {}

    func show() {}
    func hide() {}
    func activate() {}
    func minimize() {}
    func requestToClose() -> Bool { true }
    func close() {}

    func enableTextInput(_ enable: Bool, forDeviceID deviceID: Int) {
        textInputChanges.append(TextInputChange(
            enabled: enable,
            deviceID: deviceID
        ))
    }

    func isTextInputEnabled(forDeviceID deviceID: Int) -> Bool {
        textInputChanges.last.map { change in
            change.deviceID == deviceID && change.enabled
        } ?? false
    }

    func setCursor(_ cursor: Cursor?, forDeviceID deviceID: Int) {
        if let cursor {
            cursors[deviceID] = cursor
        } else {
            cursors.removeValue(forKey: deviceID)
        }
        switch cursor {
        case .some(.text):
            cursorChanges.append(.text(deviceID))
        case .none:
            cursorChanges.append(.platformDefault(deviceID))
        default:
            cursorChanges.append(.other(deviceID))
        }
    }

    func cursor(forDeviceID deviceID: Int) -> Cursor? {
        cursors[deviceID]
    }

    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}
