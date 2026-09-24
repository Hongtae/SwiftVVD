import Foundation
import XCTest
import VVD
@testable import VUI

// ASSERTIONS viewLineLimitPublic27Observed

final class ViewLineLimitOwnerTests: XCTestCase {
    private typealias RangeView = ModifiedContent<EmptyView, LineLimitModifier>
    private typealias OptionalModifier = _EnvironmentKeyWritingModifier<Int?>
    private typealias OptionalView = ModifiedContent<EmptyView, OptionalModifier>
    private var previousContext: (any AppContext)?

    override func setUp() {
        previousContext = appContext
        appContext = ViewLineLimitTestAppContext()
    }

    override func tearDown() {
        appContext = previousContext
        previousContext = nil
    }

    func testRangeProducersStoreObservedRawBounds() throws {
        let closed = try rangeView(EmptyView().lineLimit(2...4))
        XCTAssertEqual(closed.modifier.lowerLimit, 2)
        XCTAssertEqual(closed.modifier.upperLimit, 4)

        let from = try rangeView(EmptyView().lineLimit(2...))
        XCTAssertEqual(from.modifier.lowerLimit, 2)
        XCTAssertNil(from.modifier.upperLimit)

        let through = try rangeView(EmptyView().lineLimit(...4))
        XCTAssertNil(through.modifier.lowerLimit)
        XCTAssertEqual(through.modifier.upperLimit, 4)

        let reserved = try rangeView(
            EmptyView().lineLimit(3, reservesSpace: true)
        )
        XCTAssertEqual(reserved.modifier.lowerLimit, 3)
        XCTAssertEqual(reserved.modifier.upperLimit, 3)

        let unreserved = try rangeView(
            EmptyView().lineLimit(3, reservesSpace: false)
        )
        XCTAssertNil(unreserved.modifier.lowerLimit)
        XCTAssertEqual(unreserved.modifier.upperLimit, 3)

        let negativeClosed = try rangeView(EmptyView().lineLimit(-2...0))
        XCTAssertEqual(negativeClosed.modifier.lowerLimit, -2)
        XCTAssertEqual(negativeClosed.modifier.upperLimit, 0)

        let negativeFrom = try rangeView(
            EmptyView().lineLimit((-2)...)
        )
        XCTAssertEqual(negativeFrom.modifier.lowerLimit, -2)
        XCTAssertNil(negativeFrom.modifier.upperLimit)

        let zeroThrough = try rangeView(EmptyView().lineLimit(...0))
        XCTAssertNil(zeroThrough.modifier.lowerLimit)
        XCTAssertEqual(zeroThrough.modifier.upperLimit, 0)

        let negativeReserved = try rangeView(
            EmptyView().lineLimit(-2, reservesSpace: true)
        )
        XCTAssertEqual(negativeReserved.modifier.lowerLimit, -2)
        XCTAssertEqual(negativeReserved.modifier.upperLimit, -2)
    }

    func testRangeModifierReplacesBothEnvironmentBounds() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        try context.withCurrent {
            var environment = EnvironmentValues()
            environment.lineLimit = 9
            environment.lowerLineLimit = 8

            try apply(
                rangeView(EmptyView().lineLimit(2...4)).modifier,
                in: graph,
                to: &environment
            )
            XCTAssertEqual(environment.lineLimit, 4)
            XCTAssertEqual(environment.lowerLineLimit, 2)

            try apply(
                rangeView(EmptyView().lineLimit(...1)).modifier,
                in: graph,
                to: &environment
            )
            XCTAssertEqual(environment.lineLimit, 1)
            XCTAssertNil(environment.lowerLineLimit)

            try apply(
                rangeView(EmptyView().lineLimit(3...)).modifier,
                in: graph,
                to: &environment
            )
            XCTAssertNil(environment.lineLimit)
            XCTAssertEqual(environment.lowerLineLimit, 3)

            try apply(
                rangeView(
                    EmptyView().lineLimit(5, reservesSpace: false)
                ).modifier,
                in: graph,
                to: &environment
            )
            XCTAssertEqual(environment.lineLimit, 5)
            XCTAssertNil(environment.lowerLineLimit)
        }
    }

    func testOptionalProducerWritesOnlyUpperBoundInSourceOrder() throws {
        typealias RangeThenOptional = ModifiedContent<RangeView, OptionalModifier>
        typealias OptionalThenRange = ModifiedContent<OptionalView, LineLimitModifier>

        let rangeThenOptional = try XCTUnwrap(
            EmptyView()
                .lineLimit(2...4)
                .lineLimit(Optional(1)) as? RangeThenOptional
        )
        let optionalThenRange = try XCTUnwrap(
            EmptyView()
                .lineLimit(Optional(1))
                .lineLimit(2...4) as? OptionalThenRange
        )

        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        try context.withCurrent {
            var first = EnvironmentValues()
            first[keyPath: rangeThenOptional.modifier.keyPath] =
                rangeThenOptional.modifier.value
            try apply(
                rangeThenOptional.content.modifier,
                in: graph,
                to: &first
            )
            XCTAssertEqual(first.lineLimit, 4)
            XCTAssertEqual(first.lowerLineLimit, 2)

            var second = EnvironmentValues()
            try apply(
                optionalThenRange.modifier,
                in: graph,
                to: &second
            )
            second[keyPath: optionalThenRange.content.modifier.keyPath] =
                optionalThenRange.content.modifier.value
            XCTAssertEqual(second.lineLimit, 1)
            XCTAssertEqual(second.lowerLineLimit, 2)
        }
    }

    func testLayoutPropertiesNormalizeBoundsWithoutReconcilingThem() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        try context.withCurrent {
            var environment = EnvironmentValues()
            try apply(
                rangeView(EmptyView().lineLimit(-2...0)).modifier,
                in: graph,
                to: &environment
            )
            var properties = TextLayoutProperties(from: environment)
            XCTAssertEqual(properties.lineLimit, 1)
            XCTAssertEqual(properties.lowerLineLimit, 0)

            try apply(
                rangeView(
                    EmptyView().lineLimit(3, reservesSpace: true)
                ).modifier,
                in: graph,
                to: &environment
            )
            environment.lineLimit = 1
            properties = TextLayoutProperties(from: environment)
            XCTAssertEqual(properties.lineLimit, 1)
            XCTAssertEqual(properties.lowerLineLimit, 3)
        }
    }

    func testLowerBoundReservesMeasuredHeightWithoutAddingLayoutLines() throws {
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: host
        )
        host.storage = viewGraph

        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        var environment = EnvironmentValues()
        environment.font = .file(root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"
        ), size: 20)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            func engine<Content: View>(_ content: Content) throws -> StyledTextLayoutEngine {
                let outputs = Content._makeView(
                    view: _GraphValue(_attribute: graph.makeInput(value: content)),
                    inputs: makeInputs(graph: graph, environment: environment)
                )
                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                return try XCTUnwrap(
                    computer.box as? LayoutEngineBox<StyledTextLayoutEngine>
                ).engine
            }

            let plain = try engine(
                Text(verbatim: "A").textRenderer(ViewLineLimitRenderer())
            )
            let lowerTwo = try engine(
                Text(verbatim: "A")
                    .lineLimit(2...)
                    .textRenderer(ViewLineLimitRenderer())
            )
            let reserveThree = try engine(
                Text(verbatim: "A")
                    .lineLimit(3, reservesSpace: true)
                    .textRenderer(ViewLineLimitRenderer())
            )
            let noReserve = try engine(
                Text(verbatim: "A")
                    .lineLimit(3, reservesSpace: false)
                    .textRenderer(ViewLineLimitRenderer())
            )
            let negativeReserve = try engine(
                Text(verbatim: "A")
                    .lineLimit(-2, reservesSpace: true)
                    .textRenderer(ViewLineLimitRenderer())
            )
            let barePlain = try engine(Text(verbatim: "A"))
            let bareLowerTwo = try engine(
                Text(verbatim: "A").lineLimit(2...)
            )

            let proposal = _ProposedSize(width: 100, height: nil)
            let plainSize = plain.sizeThatFits(proposal)
            let lowerTwoSize = lowerTwo.sizeThatFits(proposal)
            let reserveThreeSize = reserveThree.sizeThatFits(proposal)
            let noReserveSize = noReserve.sizeThatFits(proposal)
            let negativeReserveSize = negativeReserve.sizeThatFits(proposal)
            let barePlainSize = barePlain.sizeThatFits(proposal)
            let bareLowerTwoSize = bareLowerTwo.sizeThatFits(proposal)

            func reservedHeight(_ layout: StyledTextLayoutEngine, lines: Int) -> CGFloat {
                let metrics = layout.text.maxFontMetrics
                let lineHeight = metrics.ascender - metrics.descender
                let height = lineHeight * CGFloat(lines)
                    + metrics.leading * CGFloat(lines - 1)
                return ceil(height * environment.displayScale) / environment.displayScale
            }

            XCTAssertEqual(
                lowerTwoSize.height,
                max(plainSize.height, reservedHeight(lowerTwo, lines: 2))
            )
            XCTAssertEqual(
                reserveThreeSize.height,
                max(plainSize.height, reservedHeight(reserveThree, lines: 3))
            )
            XCTAssertEqual(noReserveSize.height, plainSize.height)
            XCTAssertEqual(negativeReserveSize.height, plainSize.height)
            XCTAssertEqual(
                bareLowerTwoSize.height,
                max(
                    barePlainSize.height,
                    reservedHeight(bareLowerTwo, lines: 2)
                )
            )

            XCTAssertTrue(plain.text is ResolvedStyledText.TextLayoutManager)
            XCTAssertTrue(barePlain.text is ResolvedStyledText.StringDrawing)

            for layout in [
                plain,
                lowerTwo,
                reserveThree,
                noReserve,
                negativeReserve,
                barePlain,
                bareLowerTwo,
            ] {
                let size = layout.sizeThatFits(proposal)
                XCTAssertEqual(
                    layout.text.metrics(in: size, layoutMargins: nil).numberOfLines,
                    1
                )
            }
        }
    }

    private func makeInputs(
        graph: _AGGraph,
        environment: EnvironmentValues
    ) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: environment),
                transaction: graph.makeInput(value: Transaction())
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func rangeView<V: View>(_ value: V) throws -> RangeView {
        try XCTUnwrap(value as? RangeView)
    }

    private func apply(
        _ modifier: LineLimitModifier,
        in graph: _AGGraph,
        to environment: inout EnvironmentValues
    ) throws {
        let attribute = graph.makeInput(value: modifier)
        LineLimitModifier.makeEnvironment(
            modifier: attribute,
            environment: &environment
        )
    }
}

private struct ViewLineLimitRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {}
}

private final class ViewLineLimitTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }

    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
