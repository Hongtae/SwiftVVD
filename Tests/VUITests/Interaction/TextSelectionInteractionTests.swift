import XCTest
@testable import VUI
@testable import VVD

final class TextSelectionInteractionTests: XCTestCase {
    // ASSERTIONS textSelectionInteraction27Observed
    @MainActor
    func testStaticTextDragHighlightsAndCopiesThroughBothRendererOrders() throws {
        let clipboard = StaticTextSelectionClipboard()
        let previousAppContext = appContext
        appContext = StaticTextSelectionAppContext(clipboard: clipboard)
        defer { appContext = previousAppContext }

        for fixture in StaticTextSelectionFixture.Case.allCases {
            clipboard.representations = [:]
            let capture = StaticTextSelectionCapture()
            let controller = WindowController(
                content: StaticTextSelectionFixture(
                    fixture: fixture,
                    capture: capture
                ),
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(StaticTextSelectionFixture.self)
                )
            )
            var tick: UInt64 = 0
            var redraw = false

            func renderFrame() {
                controller.updateView(
                    tick: tick,
                    delta: 0,
                    date: controller.date,
                    contentSize: CGSize(width: 640, height: 140),
                    redraw: &redraw
                ) { _, _ in }
                tick += 1
                Update.dispatchActions()
            }

            renderFrame()
            renderFrame()

            let before = capture.snapshot()
            let wordBounds = try XCTUnwrap(
                before.wordBounds,
                fixture.rawValue
            )
            let beforeFills = try controller.viewGraph.data.withCurrent {
                shapeFillRecords(
                    in: try XCTUnwrap(
                        controller.viewGraph.rootDisplayList?.value
                    )
                )
            }
            let start = CGPoint(
                x: 20 + wordBounds.minX + 1,
                y: 70
            )
            let end = CGPoint(
                x: 20 + wordBounds.maxX - 1,
                y: 70
            )
            let down = controller.handleMouseEvent(event: VVD.MouseEvent(
                type: .buttonDown,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: start,
                timestamp: 0
            ))
            let drag = controller.handleMouseEvent(event: VVD.MouseEvent(
                type: .move,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: end,
                timestamp: 0.01
            ))
            let up = controller.handleMouseEvent(event: VVD.MouseEvent(
                type: .buttonUp,
                device: .genericMouse,
                deviceID: 0,
                buttonID: 0,
                location: end,
                timestamp: 0.02
            ))
            Update.dispatchActions()
            renderFrame()
            renderFrame()

            let after = capture.snapshot()
            let afterFills = try controller.viewGraph.data.withCurrent {
                shapeFillRecords(
                    in: try XCTUnwrap(
                        controller.viewGraph.rootDisplayList?.value
                    )
                )
            }

            if fixture.allowsSelection {
                XCTAssertTrue(down, fixture.rawValue)
                XCTAssertTrue(drag, fixture.rawValue)
                XCTAssertTrue(up, fixture.rawValue)
                XCTAssertTrue(
                    controller.canPerformTextEditingCommand(.copy),
                    fixture.rawValue
                )
                controller.performTextEditingCommand(.copy)
                Update.dispatchActions()
                XCTAssertEqual(
                    clipboard.representations[
                        ClipboardContentType.utf8PlainText
                    ],
                    Data("Bravo".utf8),
                    fixture.rawValue
                )
                let addedFills = afterFills.filter { record in
                    !beforeFills.contains { $0.frame == record.frame }
                }
                let highlightCandidate = addedFills.first { record in
                    abs(record.frame.width - wordBounds.width) < 0.001
                }
                let highlightRecord = try XCTUnwrap(
                    highlightCandidate,
                    fixture.rawValue
                )
                let highlight = highlightRecord.frame
                XCTAssertEqual(
                    highlight.height,
                    before.layoutBounds.height,
                    accuracy: 0.001,
                    fixture.rawValue
                )
                let color = highlightRecord.color.renderingComponents()
                XCTAssertEqual(
                    color.red,
                    186.0 / 255.0,
                    accuracy: 0.000_001,
                    fixture.rawValue
                )
                XCTAssertEqual(
                    color.green,
                    214.0 / 255.0,
                    accuracy: 0.000_001,
                    fixture.rawValue
                )
                XCTAssertEqual(
                    color.blue,
                    251.0 / 255.0,
                    accuracy: 0.000_001,
                    fixture.rawValue
                )
                XCTAssertEqual(
                    color.alpha,
                    1,
                    accuracy: 0.000_001,
                    fixture.rawValue
                )
            } else {
                XCTAssertFalse(down, fixture.rawValue)
                XCTAssertFalse(drag, fixture.rawValue)
                XCTAssertFalse(up, fixture.rawValue)
                XCTAssertFalse(
                    controller.canPerformTextEditingCommand(.copy),
                    fixture.rawValue
                )
                controller.performTextEditingCommand(.copy)
                Update.dispatchActions()
                XCTAssertTrue(clipboard.representations.isEmpty)
                XCTAssertEqual(afterFills, beforeFills, fixture.rawValue)
            }

            XCTAssertEqual(after.drawCalls, before.drawCalls, fixture.rawValue)
            XCTAssertEqual(after.wordBounds, before.wordBounds, fixture.rawValue)
            XCTAssertEqual(after.layoutBounds, before.layoutBounds, fixture.rawValue)
            XCTAssertEqual(
                before.returnedSize.width,
                before.baseSize.width + 80,
                accuracy: 0.001,
                fixture.rawValue
            )
        }
    }

    private struct ShapeFillRecord: Equatable {
        var frame: CGRect
        var color: VUI.Color
    }

    private func shapeFillRecords(
        in list: DisplayList
    ) -> [ShapeFillRecord] {
        var result = list.itemRecords.compactMap { record -> ShapeFillRecord? in
            guard record.kind == .shapeFill,
                  let frame = record.bounds,
                  case let .color(color)? = record.shapeStyle else {
                return nil
            }
            return ShapeFillRecord(frame: frame, color: color)
        }
        for effect in list.effects {
            result.append(contentsOf: shapeFillRecords(in: effect.contents))
        }
        return result
    }
}

private final class StaticTextSelectionCapture: @unchecked Sendable {
    struct Snapshot {
        var sizeCalls = 0
        var drawCalls = 0
        var baseSize = CGSize.zero
        var returnedSize = CGSize.zero
        var wordBounds: CGRect?
        var layoutBounds = CGRect.zero
    }

    private let lock = NSLock()
    private var value = Snapshot()

    func recordSize(base: CGSize, returned: CGSize) {
        lock.lock()
        defer { lock.unlock() }
        value.sizeCalls += 1
        value.baseSize = base
        value.returnedSize = returned
    }

    func recordDraw(_ layout: Text.Layout) {
        lock.lock()
        defer { lock.unlock() }
        value.drawCalls += 1
        var word = CGRect.null
        var complete = CGRect.null
        for line in layout {
            complete = complete.union(line.typographicBounds.rect)
            for run in line {
                for glyph in run where glyph.characterIndices.contains(
                    where: { (6..<11).contains($0.value) }
                ) {
                    word = word.union(glyph.typographicBounds.rect)
                }
            }
        }
        value.wordBounds = word.isNull ? nil : word
        value.layoutBounds = complete.isNull ? .zero : complete
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct StaticTextSelectionRenderer: TextRenderer {
    var capture: StaticTextSelectionCapture

    func sizeThatFits(
        proposal: ProposedViewSize,
        text: TextProxy
    ) -> CGSize {
        let base = text.sizeThatFits(proposal)
        let returned = CGSize(width: base.width + 80, height: base.height)
        capture.recordSize(base: base, returned: returned)
        return returned
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        capture.recordDraw(layout)
        for line in layout {
            context.draw(line)
        }
    }
}

private struct StaticTextSelectionFixture: View {
    enum Case: String, CaseIterable {
        case rendererThenEnabled
        case enabledThenRenderer
        case rendererThenDisabled
        case disabledThenRenderer

        var allowsSelection: Bool {
            switch self {
            case .rendererThenEnabled, .enabledThenRenderer:
                true
            case .rendererThenDisabled, .disabledThenRenderer:
                false
            }
        }
    }

    var fixture: Case
    var capture: StaticTextSelectionCapture

    @ViewBuilder
    var body: some View {
        switch fixture {
        case .rendererThenEnabled:
            text
                .textRenderer(
                    StaticTextSelectionRenderer(capture: capture)
                )
                .textSelection(.enabled)
                .frame(width: 600, height: 100, alignment: .leading)
                .padding(20)
        case .enabledThenRenderer:
            text
                .textSelection(.enabled)
                .textRenderer(
                    StaticTextSelectionRenderer(capture: capture)
                )
                .frame(width: 600, height: 100, alignment: .leading)
                .padding(20)
        case .rendererThenDisabled:
            text
                .textRenderer(
                    StaticTextSelectionRenderer(capture: capture)
                )
                .textSelection(.disabled)
                .frame(width: 600, height: 100, alignment: .leading)
                .padding(20)
        case .disabledThenRenderer:
            text
                .textSelection(.disabled)
                .textRenderer(
                    StaticTextSelectionRenderer(capture: capture)
                )
                .frame(width: 600, height: 100, alignment: .leading)
                .padding(20)
        }
    }

    private var text: some View {
        Text(verbatim: "Alpha Bravo Charlie Delta")
            .font(.system(size: 32))
            .environment(\.defaultFontRenderingMode, .vector())
    }
}

private final class StaticTextSelectionClipboard: Clipboard {
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

private final class StaticTextSelectionAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    let clipboard: (any Clipboard)?
    let appWindowsController: AppWindowsController? = nil

    init(clipboard: (any Clipboard)?) {
        self.clipboard = clipboard
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
