import XCTest
@testable import VUI
@testable import VVD

final class TextEditorInputTests: XCTestCase {
    @MainActor
    func testMountedEditorReleasesRendererHostGraphResponderAndResources() {
        let previousContext = appContext
        appContext = TextEditorTestAppContext()
        defer { appContext = previousContext }
        weak var controllerReference: WindowController?
        weak var graphReference: ViewGraph?
        weak var storageReference: _AGGraph?
        weak var responderReference: TextEditorResponder?
        weak var resourcesReference: SceneResources?
        func populate() {
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            let controller = WindowController(
                content: TextEditor(text: .constant("First line\nSecond line"))
                    .frame(width: 200, height: 100),
                environment: environment,
                scene: WindowKey(namespace: .app,
                    sceneID: SceneID(TextEditorInputTests.self)))
            controllerReference = controller
            graphReference = controller.viewGraph
            storageReference = controller.viewGraph.data.graph
            resourcesReference = controller.sceneResources
            var redraw = false
            for tick in 0..<3 {
                controller.updateView(tick: UInt64(tick), delta: 0,
                    date: controller.date, contentSize: CGSize(width: 240, height: 160),
                    redraw: &redraw) { _, _ in }
                Update.dispatchActions()
            }
            _ = controller.responderNode?.visit { responder in
                if let responder = responder as? TextEditorResponder {
                    responderReference = responder
                    return .cancel
                }
                return .next
            }
            XCTAssertNotNil(responderReference)
        }
        populate()
        Update.dispatchActions()
        XCTAssertNil(controllerReference)
        XCTAssertNil(graphReference)
        XCTAssertNil(storageReference)
        XCTAssertNil(responderReference)
        XCTAssertNil(resourcesReference)
    }

    // ASSERTIONS textEditorStorageObserved
    // ASSERTIONS textEditorBodyRoutingObserved
    func testStringInitializersPreserveOptionalSelectionBinding() {
        let model = TextEditorInputModel(text: "value")
        let basic = TextEditor(text: model.textBinding)
        let selected = TextEditor(
            text: model.textBinding,
            selection: model.selectionBinding
        )

        guard case .string(let basicStorage) = basic.storage,
              case .string(let selectedStorage) = selected.storage else {
            XCTFail("String initializers must use String storage")
            return
        }
        XCTAssertEqual(basicStorage.0.wrappedValue, "value")
        XCTAssertNil(basicStorage.1)
        XCTAssertEqual(selectedStorage.0.wrappedValue, "value")
        XCTAssertNotNil(selectedStorage.1)
        XCTAssertTrue(selected.body is ResolvedTextEditorStyle)
    }

    // ASSERTIONS textEditorStyleStructureObserved
    func testStyleConfigurationAndAutomaticBodyRetainStringStorage() {
        let model = TextEditorInputModel(text: "value")
        let editor = TextEditor(text: model.textBinding)
        let configuration = TextEditorStyleConfiguration(
            storage: editor.storage
        )
        let automaticBody = AutomaticTextEditorStyle()
            .makeBody(configuration: configuration)

        XCTAssertEqual(
            Mirror(reflecting: configuration).children.compactMap(\.label),
            ["storage"]
        )
        XCTAssertEqual(
            Mirror(reflecting: automaticBody).children.compactMap(\.label),
            ["configuration"]
        )
    }

    // ASSERTIONS textEditorFocusSelectionObserved
    // ASSERTIONS textEditorReturnBehaviorObserved
    func testFocusStartsAtEndAndReturnInsertsNewlineWithoutSubmission() {
        var text = "Alpha"
        var state = TextEditorInputState()

        state.setFocused(true, text: text)
        XCTAssertTrue(state.isFocused)
        XCTAssertEqual(state.selectionOffsets, 5..<5)
        XCTAssertEqual(state.selectionAffinity, .upstream)

        XCTAssertTrue(state.handleTextInput("\r", text: &text))
        XCTAssertEqual(text, "Alpha\n")
        XCTAssertEqual(state.selectionOffsets, 6..<6)
        XCTAssertEqual(state.selectionAffinity, .downstream)
        XCTAssertTrue(state.isFocused)
    }

    // ASSERTIONS textEditorIMECompositionPolicyObserved
    func testCompositionPublishesMarkedTextAndHandlesAppKitEventOrder() {
        var text = ""
        var state = TextEditorInputState()
        state.setFocused(true, text: text)

        XCTAssertTrue(state.replaceComposition(with: "ㅎ", in: &text))
        XCTAssertEqual(text, "ㅎ")
        XCTAssertTrue(state.replaceComposition(with: "한", in: &text))
        XCTAssertEqual(text, "한")

        XCTAssertTrue(state.handleTextInput("한", text: &text))
        XCTAssertEqual(text, "한")
        XCTAssertFalse(state.replaceComposition(with: "", in: &text))
        XCTAssertEqual(text, "한")
        XCTAssertNil(state.compositionRange)
        XCTAssertNil(state.pendingCompositionRange)
    }

    // ASSERTIONS textEditorIMECompositionPolicyObserved
    func testCompositionHandlesWin32ClearBeforeCommittedInput() {
        var text = ""
        var state = TextEditorInputState()
        state.setFocused(true, text: text)

        XCTAssertTrue(state.replaceComposition(with: "한", in: &text))
        XCTAssertFalse(state.replaceComposition(with: "", in: &text))
        XCTAssertEqual(state.pendingCompositionRange, 0..<1)

        XCTAssertTrue(state.handleTextInput("한", text: &text))
        XCTAssertEqual(text, "한")
        XCTAssertEqual(state.selectionOffsets, 1..<1)
        XCTAssertNil(state.compositionRange)
        XCTAssertNil(state.pendingCompositionRange)
    }

    // ASSERTIONS textEditorIMECompositionPolicyObserved
    func testFocusLossPreservesAndFinalizesPublishedComposition() {
        var text = "prefix "
        var state = TextEditorInputState()
        state.setFocused(true, text: text)
        XCTAssertTrue(state.replaceComposition(with: "한글", in: &text))

        state.setFocused(false, text: text)

        XCTAssertEqual(text, "prefix 한글")
        XCTAssertFalse(state.isFocused)
        XCTAssertNil(state.compositionRange)
        XCTAssertNil(state.pendingCompositionRange)
    }

    // ASSERTIONS textEditorFocusSelectionObserved
    // ASSERTIONS textEditorReturnBehaviorObserved
    // ASSERTIONS textEditorIMECompositionPolicyObserved
    func testResponderPublishesFocusCompositionNewlineAndBlur() {
        let model = TextEditorInputModel(text: "Alpha")
        var inputState = TextEditorInputState()
        let responder = TextEditorResponder()
        responder.text = model.textBinding
        responder.selection = model.selectionBinding
        responder.inputState = Binding(
            get: { inputState },
            set: { inputState = $0 }
        )

        responder.textInputFocusDidChange(true)
        Update.dispatchActions()
        XCTAssertTrue(inputState.isFocused)
        XCTAssertEqual(inputState.selectionOffsets, 5..<5)
        XCTAssertEqual(
            model.selection,
            inputState.textSelection(in: model.text)
        )

        XCTAssertTrue(responder.handleTextInputEvent(KeyboardEvent(
            type: .textComposition,
            window: nil,
            deviceID: 0,
            key: .none,
            text: "ㅎ"
        )))
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Alphaㅎ")
        XCTAssertEqual(inputState.compositionRange, 5..<6)

        XCTAssertTrue(responder.handleTextInputEvent(KeyboardEvent(
            type: .textComposition,
            window: nil,
            deviceID: 0,
            key: .none,
            text: "한"
        )))
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Alpha한")

        XCTAssertTrue(responder.handleTextInputEvent(KeyboardEvent(
            type: .textInput,
            window: nil,
            deviceID: 0,
            key: .none,
            text: "한"
        )))
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Alpha한")

        XCTAssertTrue(responder.handleTextInputEvent(KeyboardEvent(
            type: .textComposition,
            window: nil,
            deviceID: 0,
            key: .none,
            text: ""
        )))
        Update.dispatchActions()
        XCTAssertNil(inputState.compositionRange)

        XCTAssertTrue(responder.handleTextInputEvent(KeyboardEvent(
            type: .textInput,
            window: nil,
            deviceID: 0,
            key: .return,
            text: "\r"
        )))
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Alpha한\n")
        XCTAssertEqual(inputState.selectionOffsets, 7..<7)
        XCTAssertEqual(inputState.selectionAffinity, .downstream)

        responder.textInputFocusDidChange(false)
        Update.dispatchActions()
        XCTAssertFalse(inputState.isFocused)
        XCTAssertNil(inputState.compositionRange)
        XCTAssertNil(inputState.pendingCompositionRange)
        XCTAssertNil(inputState.preferredHorizontalOffset)
    }

    // ASSERTIONS textEditorCommandPolicyObserved
    func testResponderValidatesAndPerformsFocusedEditingCommands() throws {
        let clipboard = TextEditorTestClipboard()
        let context = TextEditorClipboardAppContext(clipboard: clipboard)
        let previousAppContext = appContext
        appContext = context
        defer { appContext = previousAppContext }

        let model = TextEditorInputModel(text: "Alpha beta\ngamma")
        var inputState = TextEditorInputState()
        inputState.setFocused(true, text: model.text)
        _ = inputState.setSelection(
            6..<10,
            affinity: .upstream,
            text: model.text
        )
        let responder = TextEditorResponder()
        responder.text = model.textBinding
        responder.selection = model.selectionBinding
        responder.inputState = Binding(
            get: { inputState },
            set: { inputState = $0 }
        )

        XCTAssertTrue(responder.canPerformTextEditingCommand(.copy))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.cut))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.paste))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.delete))
        XCTAssertTrue(responder.canPerformTextEditingCommand(.selectAll))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.find))

        responder.performTextEditingCommand(.copy)
        Update.dispatchActions()
        XCTAssertEqual(
            try clipboard.data(
                forType: ClipboardContentType.utf8PlainText
            ),
            Data("beta".utf8)
        )
        XCTAssertEqual(model.text, "Alpha beta\ngamma")

        responder.performTextEditingCommand(.cut)
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Alpha \ngamma")
        XCTAssertEqual(inputState.selectionOffsets, 6..<6)

        clipboard.representations = [
            ClipboardContentType.utf8PlainText: Data("one\ntwo".utf8)
        ]
        XCTAssertTrue(responder.canPerformTextEditingCommand(.paste))
        responder.performTextEditingCommand(.paste)
        Update.dispatchActions()
        XCTAssertEqual(model.text, "Alpha one\ntwo\ngamma")
        XCTAssertEqual(inputState.selectionAffinity, .upstream)

        responder.performTextEditingCommand(.selectAll)
        Update.dispatchActions()
        XCTAssertEqual(inputState.selectionOffsets, 0..<model.text.count)
        XCTAssertEqual(
            model.selection,
            inputState.textSelection(in: model.text)
        )

        responder.textInputFocusDidChange(false)
        Update.dispatchActions()
        XCTAssertFalse(responder.canPerformTextEditingCommand(.selectAll))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.copy))
        XCTAssertFalse(responder.canPerformTextEditingCommand(.paste))
    }

    // ASSERTIONS textEditorViewportOwnershipObserved
    func testExternalSelectionDoesNotRevealButJumpCommandDoes() {
        let model = TextEditorInputModel(text: "a\nb\nc\nd\ne\nf")
        var inputState = TextEditorInputState()
        inputState.setFocused(true, text: model.text)
        inputState.collapseSelection(
            to: 0,
            affinity: .upstream,
            text: model.text
        )
        let geometry = ScrollGeometry(
            contentOffset: .zero,
            contentSize: CGSize(width: 10, height: 120),
            containerSize: CGSize(width: 10, height: 30)
        )
        let graph = _AGGraph()
        let graphContext = _AGGraphContext(graph: graph)
        let scrollable = TextEditorRecordingScrollable(geometry: geometry)
        let scrollables = graphContext.withCurrent {
            graph.makeInput(value: [scrollable as any Scrollable]).asWeak()
        }
        let responder = TextEditorResponder()
        responder.text = model.textBinding
        responder.selection = model.selectionBinding
        responder.inputState = Binding(
            get: { inputState },
            set: { inputState = $0 }
        )
        responder.scrollGeometry = geometry
        responder.scrollables = scrollables
        responder.selectionLayout = TextEditorSelectionLayout(
            lines: (0..<6).map { line in
                let lower = line * 2
                return .init(
                    characterRange: lower..<(lower + 1),
                    logicalSelectionEnd: min(lower + 2, model.text.count),
                    characterOffsets: [0, 10],
                    frame: CGRect(
                        x: 0,
                        y: CGFloat(line * 20),
                        width: 10,
                        height: 20
                    )
                )
            },
            contentSize: CGSize(width: 10, height: 120)
        )

        let end = model.text.endIndex
        model.selection = TextSelection(range: end..<end)
        responder.synchronizeSelection(model.selection)
        Update.dispatchActions()

        XCTAssertEqual(
            inputState.selectionOffsets,
            model.text.count..<model.text.count
        )
        XCTAssertTrue(scrollable.targets.isEmpty)

        XCTAssertTrue(responder.canPerformTextEditingCommand(.jumpToSelection))
        responder.performTextEditingCommand(.jumpToSelection)
        Update.dispatchActions()
        XCTAssertEqual(scrollable.targets.last?.rect.origin.y, 100)
        XCTAssertEqual(scrollable.targets.last?.rect.height, 20)
        XCTAssertEqual(scrollable.targets.last?.anchor, .center)
    }

    // ASSERTIONS textEditorVisualLineNavigationObserved
    // ASSERTIONS textEditorPointerKeyboardSelectionObserved
    func testVisualLineNavigationUsesLineRangesAndPreservesPreferredX() {
        let text = "abc\nd\nefg"
        let layout = TextEditorSelectionLayout(
            lines: [
                .init(
                    characterRange: 0..<3,
                    logicalSelectionEnd: 4,
                    characterOffsets: [0, 10, 20, 30],
                    frame: CGRect(x: 0, y: 0, width: 30, height: 20)
                ),
                .init(
                    characterRange: 4..<5,
                    logicalSelectionEnd: 6,
                    characterOffsets: [0, 10],
                    frame: CGRect(x: 0, y: 20, width: 10, height: 20)
                ),
                .init(
                    characterRange: 6..<9,
                    logicalSelectionEnd: 9,
                    characterOffsets: [0, 10, 20, 30],
                    frame: CGRect(x: 0, y: 40, width: 30, height: 20)
                ),
            ],
            contentSize: CGSize(width: 30, height: 60)
        )
        var state = TextEditorInputState()
        state.setFocused(true, text: text)
        state.collapseSelection(to: 2, affinity: .upstream, text: text)

        XCTAssertTrue(state.handleKeyDown(
            .down,
            modifiers: [.shift],
            text: text,
            layout: layout,
            viewportHeight: 40
        ))
        XCTAssertEqual(state.selectionOffsets, 2..<5)
        XCTAssertEqual(state.preferredHorizontalOffset, 20)

        XCTAssertTrue(state.handleKeyDown(
            .down,
            modifiers: [.shift],
            text: text,
            layout: layout,
            viewportHeight: 40
        ))
        XCTAssertEqual(state.selectionOffsets, 2..<8)
        XCTAssertEqual(state.preferredHorizontalOffset, 20)

        state.collapseSelection(to: 8, affinity: .upstream, text: text)
        XCTAssertTrue(state.handleKeyDown(
            .home,
            modifiers: [.shift],
            text: text,
            layout: layout,
            viewportHeight: 40
        ))
        XCTAssertEqual(state.selectionOffsets, 6..<8)
        XCTAssertEqual(state.selectionAffinity, .upstream)
    }

    // ASSERTIONS textEditorPointerKeyboardSelectionObserved
    func testWordAndLogicalLineSelectionUseMultilineBoundaries() {
        let text = "Alpha beta\ngamma"
        let state = TextEditorInputState()

        XCTAssertEqual(state.wordRange(at: 7, in: text), 6..<10)
        XCTAssertEqual(state.logicalLineRange(at: 2, in: text), 0..<11)
        XCTAssertEqual(state.logicalLineRange(at: 13, in: text), 11..<16)
    }

    // ASSERTIONS textEditorMultilineLayoutObserved
    // ASSERTIONS textEditorPointerKeyboardSelectionObserved
    func testSelectionGeometryUsesGlyphMidpointsAcrossLines() {
        let layout = TextEditorSelectionLayout(
            lines: [
                .init(
                    characterRange: 0..<3,
                    logicalSelectionEnd: 4,
                    characterOffsets: [0, 10, 20, 30],
                    frame: CGRect(x: 0, y: 0, width: 30, height: 18)
                ),
                .init(
                    characterRange: 4..<7,
                    logicalSelectionEnd: 7,
                    characterOffsets: [0, 12, 24, 36],
                    frame: CGRect(x: 0, y: 18, width: 36, height: 18)
                ),
            ],
            contentSize: CGSize(width: 36, height: 36)
        )

        XCTAssertEqual(layout.characterOffset(at: CGPoint(x: 6, y: 2)), 1)
        XCTAssertEqual(layout.characterOffset(at: CGPoint(x: 19, y: 20)), 6)
        XCTAssertEqual(
            layout.caretRect(at: 5, affinity: .downstream),
            CGRect(x: 12, y: 18, width: 1, height: 18)
        )

        let rects = layout.selectionRects(for: 2..<6)
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0], CGRect(x: 20, y: 0, width: 10, height: 18))
        XCTAssertEqual(rects[1], CGRect(x: 30, y: 0, width: 2, height: 18))
        XCTAssertEqual(rects[2], CGRect(x: 0, y: 18, width: 24, height: 18))
    }

    @MainActor
    // ASSERTIONS textEditorStyleResolutionObserved
    // ASSERTIONS textEditorNativeOwnerObserved
    func testMountedAutomaticStyleCreatesMultilineResponder() throws {
        let previousAppContext = appContext
        appContext = TextEditorTestAppContext()
        defer { appContext = previousAppContext }

        let model = TextEditorInputModel(text: String(
            repeating: "Alpha beta gamma delta ",
            count: 12
        ) + "\nlast line")
        let controller = TextEditorHostController(model: model)
        var redraw = false

        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 240, height: 100),
            redraw: &redraw
        ) { _, _ in }
        Update.dispatchActions()
        controller.updateView(
            tick: 1,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 240, height: 100),
            redraw: &redraw
        ) { _, _ in }
        Update.dispatchActions()

        var textResponder: TextEditorResponder?
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextEditorResponder {
                textResponder = responder
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)
        XCTAssertEqual(responder.text?.wrappedValue, model.text)
        XCTAssertGreaterThan(
            responder.selectionLayout.lines.count,
            2,
            "responder size: \(responder.helper.size), "
                + "content size: \(responder.selectionLayout.contentSize)"
        )
        XCTAssertGreaterThan(
            responder.selectionLayout.contentSize.height,
            responder.helper.size.height
        )
        XCTAssertLessThanOrEqual(
            responder.selectionLayout.contentSize.width,
            responder.helper.size.width
        )
    }

    @MainActor
    // ASSERTIONS textEditorViewportOwnershipObserved
    func testMountedCommittedInputRequestsCaretReveal() throws {
        let previousAppContext = appContext
        appContext = TextEditorTestAppContext()
        defer { appContext = previousAppContext }

        let capture = TextEditorStateBindingCapture()
        let controller = TextEditorStateHostController(capture: capture)
        for tick in 0..<3 {
            controller.updateFrame(
                tick: UInt64(tick),
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 100),
                shouldDrawFrame: false
            ) { _, _ in }
        }

        var textResponder: TextEditorResponder?
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextEditorResponder {
                textResponder = responder
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)
        responder.textInputFocusDidChange(true)
        Update.dispatchActions()
        XCTAssertGreaterThan(responder.scrollGeometry.containerSize.height, 0)

        let input = "\n" + (3...12).map { "Line \($0)" }
            .joined(separator: "\n")
        var tick: UInt64 = 3
        for character in input {
            XCTAssertTrue(responder.handleTextInputEvent(KeyboardEvent(
                type: .textInput,
                window: nil,
                deviceID: 0,
                key: .none,
                text: String(character)
            )))
            Update.dispatchActions()
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 100),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }

        XCTAssertEqual(
            capture.text?.wrappedValue,
            "First line\nSecond line" + input
        )

        for _ in 0..<4 {
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 100),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }
        var updatedResponder: TextEditorResponder?
        _ = controller.responderNode?.visit { candidate in
            if let candidate = candidate as? TextEditorResponder {
                updatedResponder = candidate
                return .cancel
            }
            return .next
        }
        XCTAssertTrue(updatedResponder === responder)
        var hostingScrollResponder: HostingScrollViewResponder?
        _ = controller.responderNode?.visit { candidate in
            if let candidate = candidate as? HostingScrollViewResponder {
                hostingScrollResponder = candidate
                return .cancel
            }
            return .next
        }
        let hostContentOffset = try XCTUnwrap(
            hostingScrollResponder?.hostContainer?.scrollView.pendingContext
        ).contentOffset
        func platformGroups(
            in list: DisplayList
        ) -> [(factory: any PlatformGroupFactory, contents: DisplayList)] {
            var result: [(factory: any PlatformGroupFactory, contents: DisplayList)] = []
            for item in list.items {
                switch item.value {
                case let .effect(effect, contents):
                    if case let .platformGroup(factory) = effect {
                        result.append((factory, contents))
                    }
                    result.append(contentsOf: platformGroups(in: contents))
                case let .states(states):
                    for (_, contents) in states {
                        result.append(contentsOf: platformGroups(in: contents))
                    }
                case .content, .empty:
                    break
                }
            }
            return result
        }
        let rootDisplayList = try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(controller.viewGraph.rootDisplayList?.value)
        }
        let groups = platformGroups(in: rootDisplayList)
        let displayedGroups = groups.filter {
            $0.factory.platformGroupContainer
                === hostingScrollResponder?.representedView
        }
        XCTAssertEqual(displayedGroups.count, 1)
        XCTAssertTrue(
            displayedGroups.first?.factory
                === hostingScrollResponder?.hostContainer
        )
        let displayedGroup = try XCTUnwrap(
            displayedGroups.first?.factory.platformGroupContainer
                as? HostingScrollView.PlatformGroupContainer
        )
        XCTAssertEqual(displayedGroup.bounds.origin, hostContentOffset)
        let updatedState = responder.inputState?.wrappedValue
        let caretRect = updatedState.map {
            responder.selectionLayout.caretRect(
                at: $0.caretOffset,
                affinity: $0.selectionAffinity
            )
        }
        XCTAssertGreaterThan(
            responder.scrollGeometry.contentOffset.y,
            0,
            "geometry: \(responder.scrollGeometry), "
                + "layout: \(responder.selectionLayout.contentSize), "
                + "state: \(String(describing: updatedState)), "
                + "caret: \(String(describing: caretRect)), "
                + "outbox: \(controller.viewGraph.data.graph.actionOutbox.count)"
        )
        XCTAssertGreaterThan(hostContentOffset.y, 0)
    }

    @MainActor
    // ASSERTIONS textEditorViewportOwnershipObserved
    func testQueuedWindowInputKeepsCommittedInputCaretVisible() throws {
        let previousAppContext = appContext
        appContext = TextEditorTestAppContext()
        defer { appContext = previousAppContext }

        let capture = TextEditorStateBindingCapture()
        let controller = TextEditorStateHostController(capture: capture)
        var tick: UInt64 = 0
        for _ in 0..<3 {
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 100),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }

        var textResponder: TextEditorResponder?
        var hostingScrollResponder: HostingScrollViewResponder?
        _ = controller.responderNode?.visit { responder in
            if let responder = responder as? TextEditorResponder {
                textResponder = responder
            }
            if let responder = responder as? HostingScrollViewResponder {
                hostingScrollResponder = responder
            }
            if textResponder != nil, hostingScrollResponder != nil {
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)
        let hostingResponder = try XCTUnwrap(hostingScrollResponder)
        controller.focusTextInputResponder(responder)

        let input = "\n" + (3...12).map { "Line \($0)" }
            .joined(separator: "\n")
        for character in input {
            let text = String(character)
            controller.enqueueInputAction {
                _ = controller.handleKeyboardEvent(event: KeyboardEvent(
                    type: .textInput,
                    window: nil,
                    deviceID: 0,
                    key: .none,
                    text: text
                ))
            }
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 100),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }

        for _ in 0..<3 {
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 100),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }

        XCTAssertEqual(
            capture.text?.wrappedValue,
            "First line\nSecond line" + input
        )
        let hostingScrollView = try XCTUnwrap(
            hostingResponder.hostContainer?.scrollView
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(hostingScrollView.pendingContext).contentOffset.y,
            0,
            "Queued input must reveal the caret without pulling the responder tree again."
        )
        XCTAssertGreaterThan(
            hostingScrollView.host.bounds.origin.y,
            0,
            "The presented scroll group must consume the requested content offset."
        )
    }

    @MainActor
    // ASSERTIONS textEditorViewportOwnershipObserved
    func testPresentedEditorKeepsCommittedInputCaretVisible() throws {
        let previousAppContext = appContext
        appContext = TextEditorTestAppContext()
        defer { appContext = previousAppContext }

        let capture = TextEditorStateBindingCapture()
        var environment = EnvironmentValues()
        environment.defaultPresentationHostMode = .overlay
        environment.defaultFontRenderingMode = .vector()
        let controller = WindowController(
            content: Color.clear.frame(width: 80, height: 40),
            environment: environment,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TextEditorInputTests.self)
            )
        )
        controller.viewGraph.updateOutputs(at: .zero)
        let child: ModalWindowController = controller.viewGraph.data.withCurrent {
            let graph = controller.viewGraph.data.graph
            let content = AnyView(
                TextEditorStateHost(capture: capture)
                    .frame(width: 200, height: 100)
            )
            let contentAttribute = graph.makeInput(value: content)
            let child = ModalWindowController(
                crossGraphContent: contentAttribute,
                sourceGraph: graph,
                environment: environment,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(TextEditorStateHost.self, index: 1)
                ),
                parentController: controller,
                usesPlatformWindow: false
            )
            controller.addModal(
                child: child,
                session: .sheet(SheetPreference(
                    content: content,
                    onDismiss: nil,
                    namespaceID: Namespace.ID(id: 90_002),
                    itemID: nil,
                    drawsBackground: true,
                    placement: .automatic,
                    activeInspector: nil,
                    usesPlatformWindow: false,
                    presentationEnvironment: environment
                ))
            )
            return child
        }

        var tick: UInt64 = 0
        for _ in 0..<4 {
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 160),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }

        var textResponder: TextEditorResponder?
        var hostingScrollResponder: HostingScrollViewResponder?
        _ = child.responderNode?.visit { responder in
            if let responder = responder as? TextEditorResponder {
                textResponder = responder
            }
            if let responder = responder as? HostingScrollViewResponder {
                hostingScrollResponder = responder
            }
            if textResponder != nil, hostingScrollResponder != nil {
                return .cancel
            }
            return .next
        }
        let responder = try XCTUnwrap(textResponder)
        let hostingResponder = try XCTUnwrap(hostingScrollResponder)
        child.focusTextInputResponder(responder)
        Update.dispatchActions()

        let input = "\n" + (3...12).map { "Line \($0)" }
            .joined(separator: "\n")
        for character in input {
            let text = String(character)
            child.enqueueInputAction {
                _ = child.handleKeyboardEvent(event: KeyboardEvent(
                    type: .textInput,
                    window: nil,
                    deviceID: 0,
                    key: .none,
                    text: text
                ))
            }
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 160),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }

        XCTAssertEqual(
            capture.text?.wrappedValue,
            "First line\nSecond line" + input
        )
        for _ in 0..<4 {
            controller.updateFrame(
                tick: tick,
                delta: 0,
                date: controller.date,
                contentSize: CGSize(width: 240, height: 160),
                shouldDrawFrame: false
            ) { _, _ in }
            tick += 1
        }
        let hostingScrollView = try XCTUnwrap(
            hostingResponder.hostContainer?.scrollView
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(hostingScrollView.pendingContext).contentOffset.y,
            0
        )
        XCTAssertGreaterThan(
            hostingScrollView.host.bounds.origin.y,
            0
        )
        let rootDisplayList = try child.viewGraph.data.withCurrent {
            try XCTUnwrap(child.viewGraph.rootDisplayList?.value)
        }
        func containsPlatformGroup(
            _ container: AnyObject,
            in list: DisplayList
        ) -> Bool {
            for item in list.items {
                switch item.value {
                case let .effect(effect, contents):
                    if case let .platformGroup(factory) = effect,
                       factory.platformGroupContainer === container {
                        return true
                    }
                    if containsPlatformGroup(container, in: contents) {
                        return true
                    }
                case let .states(states):
                    if states.contains(where: {
                        containsPlatformGroup(container, in: $0.1)
                    }) {
                        return true
                    }
                case .content, .empty:
                    break
                }
            }
            return false
        }
        XCTAssertTrue(
            containsPlatformGroup(
                try XCTUnwrap(hostingResponder.representedView),
                in: rootDisplayList
            )
        )
    }
}

private final class TextEditorTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    let appWindowsController: AppWindowsController? = nil
    private var resources: [URL: any DataProtocol] = [:]

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }
}

private final class TextEditorInputModel {
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

private final class TextEditorRecordingScrollable: Scrollable {
    var geometry: ScrollGeometry
    var targets: [ScrollTarget] = []

    init(geometry: ScrollGeometry) {
        self.geometry = geometry
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        false
    }

    func setContentTarget(
        _ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?
    ) -> Bool {
        guard let target = target(geometry, .leftToRight) else { return false }
        targets.append(target)
        geometry.contentOffset = target.rect.origin
        return true
    }

    var allowsContentOffsetAdjustments: Bool { false }

    func adjustContentOffset(
        by offset: CGSize,
        reason: ContentOffsetAdjustmentReason
    ) -> Bool {
        false
    }

    func mapFirstChild<A, B>(
        ofType type: A.Type,
        body: (A) -> B
    ) -> B? {
        nil
    }
}

private final class TextEditorTestClipboard: Clipboard {
    var representations: [String: Data] = [:]

    var types: [String] {
        Array(representations.keys)
    }

    func setData(_ representations: [String: Data]) throws {
        self.representations = representations
    }

    func data(forType type: String) throws -> Data? {
        representations[type]
    }
}

private final class TextEditorClipboardAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var clipboard: (any Clipboard)?
    let appWindowsController: AppWindowsController? = nil

    init(clipboard: (any Clipboard)?) {
        self.clipboard = clipboard
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}

private final class TextEditorStateBindingCapture {
    var text: Binding<String>?
}

private struct TextEditorStateHost: View {
    let capture: TextEditorStateBindingCapture
    @State private var text = "First line\nSecond line"

    var body: some View {
        let _ = capture.text = $text
        VStack {
            TextEditor(text: $text)
                .frame(width: 160, height: 70)
            Text("\(text.count)")
        }
        .environment(\.defaultFontRenderingMode, .vector())
    }
}

@MainActor
private final class TextEditorHostController: WindowController,
    @unchecked Sendable {
    init(model: TextEditorInputModel) {
        super.init(
            content: TextEditor(
                text: model.textBinding,
                selection: model.selectionBinding
            )
            .frame(width: 160, height: 70)
            .environment(\.defaultFontRenderingMode, .vector()),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TextEditorHostController.self)
            )
        )
    }
}

@MainActor
private final class TextEditorStateHostController: WindowController,
    @unchecked Sendable {
    init(capture: TextEditorStateBindingCapture) {
        super.init(
            content: TextEditorStateHost(capture: capture),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TextEditorStateHostController.self)
            )
        )
    }
}
