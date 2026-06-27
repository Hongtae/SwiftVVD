import CoreGraphics
import XCTest
@testable import VUI

private struct ScrollableGeometryInputRecord: Equatable {
    var id: Int
    var position: CGPoint
    var size: CGSize
    var requestsLayoutComputer: Bool
}

private struct ScrollableProxyInputRecord: Equatable {
    var size: CGSize
    var visibleRect: CGRect
}

private final class ScrollableLayoutRecorder {
    var makeViewIDs: [Int] = []
    var measuredSizes: [CGSize] = []
    var templateMeasuredSizes: [CGSize] = []
    var geometryInputs: [ScrollableGeometryInputRecord] = []
    var proxyInputs: [ScrollableProxyInputRecord] = []
    var placements: [[Int]] = []
    var currentPlacement: [Int] = []

    func beginPlacement() {
        currentPlacement = []
    }

    func finishPlacement() {
        placements.append(currentPlacement)
    }
}

private struct ScrollableRecordingRow: View, _PrimitiveView {
    var id: Int
    var recorder: ScrollableLayoutRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollableRecordingRow._makeView called outside an active AttributeGraph context.")
        }
        let row = view._attribute.value
        row.recorder.makeViewIDs.append(row.id)
        let layout = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: CGSize(width: 30, height: 20))
                },
                place: { _, _, _ in
                    row.recorder.currentPlacement.append(row.id)
                    row.recorder.geometryInputs.append(
                        ScrollableGeometryInputRecord(
                            id: row.id,
                            position: inputs.position.value,
                            size: inputs.size.value.value,
                            requestsLayoutComputer: inputs.requestsLayoutComputer
                        )
                    )
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollableMeasuringRow: View, _PrimitiveView {
    var id: Int
    var recorder: ScrollableLayoutRecorder?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollableMeasuringRow._makeView called outside an active AttributeGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    let row = view._attribute.value
                    let resolved = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 30, height: 20))
                    let size = CGSize(
                        width: resolved.width + CGFloat(row.id),
                        height: resolved.height + CGFloat(row.id)
                    )
                    row.recorder?.templateMeasuredSizes.append(size)
                    return size
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct VisibleCountScrollableLayout: _ScrollableLayout {
    static func initialState() -> Int { 0 }

    func update(state: inout Int, proxy: inout _ScrollableLayoutProxy) {
        let visibleCount = proxy.size.height < 50 ? min(proxy.count, 1) : min(proxy.count, 3)
        var visible: [_ScrollableLayoutItem] = []
        for index in 0..<visibleCount {
            visible.append(
                _ScrollableLayoutItem(
                    id: proxy[index],
                    proposedSize: CGSize(width: 40, height: 20),
                    anchoring: .topLeading,
                    at: CGPoint(x: 0, y: CGFloat(index * 24))
                )
            )
        }
        proxy.visibleItems = visible
        proxy.contentSize = CGSize(width: proxy.size.width, height: CGFloat(max(visibleCount, 1) * 24))
        proxy.validRect = CGRect(origin: .zero, size: proxy.contentSize)
        state = visibleCount
    }
}

private struct MeasuringScrollableLayout: _ScrollableLayout {
    var recorder: ScrollableLayoutRecorder

    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
        guard proxy.count > 1 else { return }

        let measured = proxy.size(at: 1, in: CGSize(width: 40, height: 20))
        recorder.measuredSizes.append(measured)
        proxy.visibleItems = [
            _ScrollableLayoutItem(
                id: proxy[1],
                proposedSize: measured,
                anchoring: .topLeading,
                at: .zero
            )
        ]
        proxy.contentSize = measured
        proxy.validRect = CGRect(origin: .zero, size: measured)
    }
}

private struct ProxyRecordingScrollableLayout: _ScrollableLayout {
    var recorder: ScrollableLayoutRecorder

    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
        recorder.proxyInputs.append(
            ScrollableProxyInputRecord(
                size: proxy.size,
                visibleRect: proxy.visibleRect
            )
        )
        guard proxy.count > 0 else { return }
        proxy.visibleItems = [
            _ScrollableLayoutItem(
                id: proxy[0],
                proposedSize: CGSize(width: 20, height: 10),
                anchoring: .topLeading,
                at: .zero
            )
        ]
        proxy.contentSize = CGSize(width: 200, height: 220)
        proxy.validRect = CGRect(x: -50, y: -50, width: 300, height: 320)
    }
}

final class ScrollableLayoutSurfaceTests: XCTestCase {
    func testScrollViewConfigDefaultsMatchPublicSurface() {
        let config = _ScrollViewConfig()

        switch config.contentOffset {
        case .initially(let point):
            XCTAssertEqual(point, .zero)
        case .binding:
            XCTFail("default contentOffset should be initially(.zero)")
        }
        XCTAssertEqual(_ScrollViewConfig.decelerationRateNormal, 0.998)
        XCTAssertEqual(_ScrollViewConfig.decelerationRateFast, 0.99)
        XCTAssertEqual(config.contentInsets, EdgeInsets())
        XCTAssertEqual(config.decelerationRate, 0.995)
        XCTAssertFalse(config.alwaysBounceVertical)
        XCTAssertFalse(config.alwaysBounceHorizontal)
        XCTAssertFalse(config.stopDraggingImmediately)
        XCTAssertTrue(config.isScrollEnabled)
        XCTAssertTrue(config.showsHorizontalIndicator)
        XCTAssertTrue(config.showsVerticalIndicator)
        XCTAssertEqual(config.indicatorInsets, EdgeInsets())
    }

    func testScrollableLayoutProxyIndexesAndCachesSizesByIdentifier() {
        let storage = _ScrollableLayoutProxy.Storage()
        var callCount = 0
        var proxy = _ScrollableLayoutProxy(
            data: ["a", "b", "c"],
            size: CGSize(width: 100, height: 50),
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            contentSeed: 1,
            storage: storage
        ) { _, proposal in
            callCount += 1
            return CGSize(width: proposal.width + CGFloat(callCount), height: proposal.height + CGFloat(callCount))
        }

        XCTAssertEqual(proxy.startIndex, 0)
        XCTAssertEqual(proxy.endIndex, 3)
        XCTAssertEqual(proxy[0], AnyHashable(0))
        XCTAssertEqual(proxy[2], AnyHashable(2))

        let proposal = CGSize(width: 12, height: 34)
        XCTAssertEqual(proxy.size(at: 1, in: proposal), CGSize(width: 13, height: 35))
        XCTAssertEqual(proxy.size(of: AnyHashable(1), in: proposal), CGSize(width: 13, height: 35))
        XCTAssertEqual(callCount, 1)

        var nextProxy = _ScrollableLayoutProxy(
            data: ["a", "b", "c"],
            size: CGSize(width: 100, height: 50),
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            contentSeed: 2,
            storage: storage
        ) { _, proposal in
            callCount += 1
            return CGSize(width: proposal.width + CGFloat(callCount), height: proposal.height + CGFloat(callCount))
        }
        XCTAssertEqual(nextProxy.size(of: AnyHashable(1), in: proposal, validatingContent: false), CGSize(width: 13, height: 35))
        XCTAssertEqual(nextProxy.size(of: AnyHashable(1), in: proposal), CGSize(width: 14, height: 36))
        XCTAssertEqual(callCount, 2)

        proxy.removeSize(of: AnyHashable(1))
        XCTAssertEqual(proxy.size(at: 1, in: CGSize(width: 20, height: 30)), CGSize(width: 23, height: 33))
        proxy.removeAllSizes()
        XCTAssertEqual(proxy.size(at: 1, in: CGSize(width: 7, height: 8)), CGSize(width: 11, height: 12))
    }

    func testScrollableLayoutProxyMeasuresTemplateContent() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            let rows = [
                ScrollableMeasuringRow(id: 7),
                ScrollableMeasuringRow(id: 11),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: MeasuringScrollableLayout(recorder: recorder))
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            let inputs = makeViewInputs(graph: graph, size: sizeAttr)

            let outputs = _ScrollableLayoutView<[ScrollableMeasuringRow], MeasuringScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)

            let measuredContentSize = layoutAttr.value.sizeThatFits(
                ProposedViewSize(CGSize(width: 100, height: 80))
            )
            XCTAssertEqual(measuredContentSize, CGSize(width: 51, height: 31))
        }

        XCTAssertEqual(recorder.measuredSizes, [CGSize(width: 51, height: 31)])
    }

    func testScrollableLayoutProxyContentSeedIgnoresGeometryOnlyUpdates() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            let rows = [
                ScrollableMeasuringRow(id: 7, recorder: recorder),
                ScrollableMeasuringRow(id: 11, recorder: recorder),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: MeasuringScrollableLayout(recorder: recorder))
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            let inputs = makeViewInputs(graph: graph, size: sizeAttr)

            let outputs = _ScrollableLayoutView<[ScrollableMeasuringRow], MeasuringScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)

            _ = layoutAttr.value.sizeThatFits(ProposedViewSize(CGSize(width: 100, height: 80)))
            XCTAssertEqual(recorder.templateMeasuredSizes, [CGSize(width: 51, height: 31)])

            sizeAttr.setValue(ViewSize(width: 140, height: 80))
            _ = layoutAttr.value.sizeThatFits(ProposedViewSize(CGSize(width: 100, height: 80)))
            XCTAssertEqual(recorder.templateMeasuredSizes, [CGSize(width: 51, height: 31)])

            let changedRows = [
                ScrollableMeasuringRow(id: 7, recorder: recorder),
                ScrollableMeasuringRow(id: 17, recorder: recorder),
            ]
            viewAttr.setValue(
                _ScrollableLayoutView(data: changedRows, layout: MeasuringScrollableLayout(recorder: recorder))
            )
            _ = layoutAttr.value.sizeThatFits(ProposedViewSize(CGSize(width: 100, height: 80)))
            XCTAssertEqual(recorder.templateMeasuredSizes, [
                CGSize(width: 51, height: 31),
                CGSize(width: 57, height: 37),
            ])
        }
    }

    func testScrollableLayoutStateUsesScrollProxyOffsetAndInsets() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            let rows = [ScrollableRecordingRow(id: 0, recorder: recorder)]
            var config = _ScrollViewConfig()
            config.contentOffset = .initially(CGPoint(x: 30, y: 40))
            config.contentInsets = EdgeInsets(top: 5, leading: 7, bottom: 11, trailing: 13)

            typealias LayoutView = _ScrollableLayoutView<[ScrollableRecordingRow], ProxyRecordingScrollableLayout>
            typealias Scroll = _ScrollView<LayoutView>

            let provider = LayoutView(data: rows, layout: ProxyRecordingScrollableLayout(recorder: recorder))
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            let inputs = makeViewInputs(graph: graph, size: sizeAttr)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)

            XCTAssertEqual(
                layoutAttr.value.sizeThatFits(ProposedViewSize(CGSize(width: 100, height: 80))),
                CGSize(width: 200, height: 220)
            )
        }

        XCTAssertEqual(recorder.proxyInputs, [
            ScrollableProxyInputRecord(
                size: CGSize(width: 80, height: 64),
                visibleRect: CGRect(x: 23, y: 35, width: 80, height: 64)
            ),
        ])
    }

    func testScrollableLayoutViewPlacesVisibleItemsAndReusesOneUnusedItem() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            let rows = (0..<4).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.needsGeometry = true

            let outputs = _ScrollableLayoutView<[ScrollableRecordingRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)

            recorder.beginPlacement()
            layoutAttr.value.place(at: .zero, proposal: ProposedViewSize(CGSize(width: 100, height: 80)))
            recorder.finishPlacement()

            sizeAttr.setValue(ViewSize(width: 100, height: 40))
            recorder.beginPlacement()
            layoutAttr.value.place(at: .zero, proposal: ProposedViewSize(CGSize(width: 100, height: 40)))
            recorder.finishPlacement()

            sizeAttr.setValue(ViewSize(width: 100, height: 80))
            recorder.beginPlacement()
            layoutAttr.value.place(at: .zero, proposal: ProposedViewSize(CGSize(width: 100, height: 80)))
            recorder.finishPlacement()
        }

        XCTAssertEqual(recorder.placements, [
            [0, 1, 2],
            [0],
            [0, 1, 2],
        ])
        XCTAssertEqual(recorder.geometryInputs, [
            ScrollableGeometryInputRecord(
                id: 0,
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
            ScrollableGeometryInputRecord(
                id: 1,
                position: CGPoint(x: 0, y: 24),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
            ScrollableGeometryInputRecord(
                id: 2,
                position: CGPoint(x: 0, y: 48),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
            ScrollableGeometryInputRecord(
                id: 0,
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
            ScrollableGeometryInputRecord(
                id: 0,
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
            ScrollableGeometryInputRecord(
                id: 1,
                position: CGPoint(x: 0, y: 24),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
            ScrollableGeometryInputRecord(
                id: 2,
                position: CGPoint(x: 0, y: 48),
                size: CGSize(width: 40, height: 20),
                requestsLayoutComputer: true
            ),
        ])
        XCTAssertEqual(recorder.makeViewIDs.filter { $0 == 1 }.count, 1)
        XCTAssertEqual(recorder.makeViewIDs.filter { $0 == 2 }.count, 2)
    }

    func testViewInputsGeometryOptionBits() {
        let graph = AttributeGraph()
        AttributeGraph.$current.withValue(graph) {
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)

            XCTAssertFalse(inputs.needsGeometry)
            XCTAssertFalse(inputs.requestsLayoutComputer)

            inputs.needsGeometry = true
            XCTAssertTrue(inputs.needsGeometry)

            inputs.requestsLayoutComputer = true
            XCTAssertTrue(inputs.requestsLayoutComputer)

            inputs.needsGeometry = false
            inputs.requestsLayoutComputer = false
            XCTAssertFalse(inputs.needsGeometry)
            XCTAssertFalse(inputs.requestsLayoutComputer)
        }
    }

    func testScrollableIdentifierContextUsesDynamicContainerInfo() {
        let graph = AttributeGraph()
        AttributeGraph.$current.withValue(graph) {
            let layoutDirection = graph.makeInput(value: LayoutDirection.leftToRight)
            let context = ScrollableLayoutItemGeometryContext(
                layoutDirection: layoutDirection,
                placement: { _ in nil }
            )
            let rowID = _ViewList_ID(explicitID: AnyHashable("row")).canonicalID
            let recoveredIndex = AnyHashable(3)

            XCTAssertNil(context.identifier(for: rowID))

            let item = DynamicContainer.ItemInfo(
                subgraph: AGSubgraph(),
                uniqueId: rowID,
                viewCount: 1,
                outputs: _ViewOutputs(),
                layoutAttributes: [],
                preferenceOutputs: [],
                item: recoveredIndex
            )
            var info = DynamicContainer.Info()
            info.replaceItems(active: [item])
            context.containerInfo = graph.makeInput(value: info)

            XCTAssertEqual(context.identifier(for: rowID), recoveredIndex)
            XCTAssertNil(context.identifier(for: _ViewList_ID(explicitID: AnyHashable("missing")).canonicalID))
        }
    }

    private func makeViewInputs(
        graph: AttributeGraph,
        size: Attribute<ViewSize>
    ) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                customInputs: PropertyList(),
                time: graph.makeInput(value: Time()),
                cachedEnvironment: MutableBox(
                    CachedEnvironment(environment: graph.makeInput(value: EnvironmentValues.tracking()))
                ),
                phase: graph.makeInput(value: Phase()),
                transaction: graph.makeInput(value: Transaction()),
                changedDebugProperties: 0,
                options: [],
                mergedInputs: []
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform.identity),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: size,
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
