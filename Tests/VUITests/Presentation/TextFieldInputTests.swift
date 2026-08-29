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
        XCTAssertTrue(input.handleKeyDown(.backspace, committedText: &text))
        XCTAssertEqual(text, "A강B")
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
            text: "강"
        )))
        Update.dispatchActions()
        renderFrame(3)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(responder.inputState?.wrappedValue.composition, "강")

        XCTAssertTrue(controller.handleKeyboardEvent(event: keyboardEvent(
            .textInput,
            window: controller.testWindow,
            text: "강"
        )))
        Update.dispatchActions()
        renderFrame(4)
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

@MainActor
private final class TextFieldInputHostController: WindowController,
    @unchecked Sendable {
    let testWindow = TextFieldInputTestWindow()

    override var window: (any VVD.Window)? { testWindow }

    init(model: TextFieldInputModel) {
        let binding = Binding<String>(
            get: { model.text },
            set: { model.text = $0 }
        )
        super.init(
            content: TextField("Input", text: binding)
                .frame(width: 300)
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

    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}
