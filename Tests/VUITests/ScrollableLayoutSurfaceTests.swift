import CoreGraphics
import Darwin
import Foundation
import XCTest
@testable import VUI

private let swiftUIScrollViewContentOffsetBindingReadWarning =
    "ScrollView contentOffset binding has been read; this will cause grossly inefficient view performance as the ScrollView's content will be updated whenever its contentOffset changes. Read the contentOffset binding in a view that is not parented between the creator of the binding and the ScrollView to avoid this."

private enum StandardOutputCaptureError: Error {
    case duplicateFailed
    case pipeFailed
    case redirectFailed
}

private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
    fflush(stdout)
    let original = dup(STDOUT_FILENO)
    guard original >= 0 else {
        throw StandardOutputCaptureError.duplicateFailed
    }

    var fileDescriptors = [Int32](repeating: 0, count: 2)
    guard pipe(&fileDescriptors) == 0 else {
        close(original)
        throw StandardOutputCaptureError.pipeFailed
    }

    guard dup2(fileDescriptors[1], STDOUT_FILENO) >= 0 else {
        close(original)
        close(fileDescriptors[0])
        close(fileDescriptors[1])
        throw StandardOutputCaptureError.redirectFailed
    }
    close(fileDescriptors[1])

    var bodyError: Error?
    do {
        try body()
    } catch {
        bodyError = error
    }

    fflush(stdout)
    dup2(original, STDOUT_FILENO)
    close(original)

    let data = FileHandle(fileDescriptor: fileDescriptors[0], closeOnDealloc: true).readDataToEndOfFile()
    if let bodyError {
        throw bodyError
    }
    return String(decoding: data, as: UTF8.self)
}

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
    var itemSubgraphs: [Int: AGSubgraph] = [:]

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
        if let subgraph = AGSubgraph.current {
            row.recorder.itemSubgraphs[row.id] = subgraph
        }
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

private struct ScrollViewInputRecordingContent: View, _PrimitiveView {
    var recorder: ScrollableLayoutRecorder
    var fixedContentSize: CGSize?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollViewInputRecordingContent._makeView called outside an active AttributeGraph context.")
        }
        let content = view._attribute.value
        content.recorder.geometryInputs.append(
            ScrollableGeometryInputRecord(
                id: -1,
                position: inputs.position.value,
                size: inputs.size.value.value,
                requestsLayoutComputer: inputs.requestsLayoutComputer
            )
        )
        let layout = graph.makeRule {
            LayoutComputer.fixed(content.fixedContentSize ?? inputs.size.value.value)
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollViewInputRecordingProvider: _ScrollableContentProvider {
    var recorder: ScrollableLayoutRecorder
    var fixedContentSize: CGSize?

    var scrollableContent: ScrollViewInputRecordingContent {
        ScrollViewInputRecordingContent(
            recorder: recorder,
            fixedContentSize: fixedContentSize
        )
    }
}

private final class ScrollViewTestResponder: ViewResponder {
    let hitTestKey: UInt32 = 0xFEED
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }
    var resetCount = 0

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func resetGesture() {
        resetCount += 1
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        let count = min(points.count, 64)
        let mask = count == 64 ? UInt64.max : ((UInt64(1) << UInt64(count)) - 1)
        return ContainsPointsResult(mask: mask, priority: 16, children: [])
    }
}

private struct ScrollViewResponderContent: View, _PrimitiveView {
    var responder: ScrollViewTestResponder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollViewResponderContent._makeView called outside an active AttributeGraph context.")
        }
        let content = view._attribute.value
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 30, height: 20))
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        if inputs.preferences.keys.contains(ViewRespondersKey.self) {
            let responders: Attribute<[any ViewResponder]> = graph.makeInput(value: [content.responder])
            outputs.preferences.append(ViewRespondersKey.self, node: responders.identifier)
        }
        return outputs
    }
}

private struct ScrollViewResponderProvider: _ScrollableContentProvider {
    var responder: ScrollViewTestResponder

    var scrollableContent: ScrollViewResponderContent {
        ScrollViewResponderContent(responder: responder)
    }
}

private struct FixedSizeRecordingRow: View, _PrimitiveView {
    var id: Int
    var size: CGSize
    var recorder: ScrollableLayoutRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("FixedSizeRecordingRow._makeView called outside an active AttributeGraph context.")
        }
        let row = view._attribute.value
        let layout = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { _ in row.size },
                place: { _, _, _ in
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

private final class ScrollableLayoutChildScrollable: Scrollable {
    var contentTargets: [(ScrollGeometry, LayoutDirection) -> ScrollTarget?] = []
    var shouldSetContentTarget = false

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        false
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        contentTargets.append(target)
        return shouldSetContentTarget
    }

    var allowsContentOffsetAdjustments: Bool {
        false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        false
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
    }
}

private final class ScrollableLayoutParentScrollable: Scrollable {
    var contentTargets: [(ScrollGeometry, LayoutDirection) -> ScrollTarget?] = []
    var shouldSetContentTarget = true

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        false
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        contentTargets.append(target)
        return shouldSetContentTarget
    }

    var allowsContentOffsetAdjustments: Bool {
        false
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        false
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        nil
    }
}

private struct ScrollablePreferenceRow: View, _PrimitiveView {
    var id: Int
    var child: ScrollableLayoutChildScrollable?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollablePreferenceRow._makeView called outside an active AttributeGraph context.")
        }

        let layout = graph.makeRule {
            LayoutComputer(
                sizeThatFits: { proposal in
                    proposal.replacingUnspecifiedDimensions(by: CGSize(width: 30, height: 20))
                }
            )
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        if view._attribute.value.child != nil {
            let child: Attribute<any Scrollable> = graph.makeRule {
                view._attribute.value.child! as any Scrollable
            }
            let scrollables: Attribute<[any Scrollable]> = graph.makeRule(
                UnaryScrollablePreferenceProvider(scrollable: child)
            )
            outputs.preferences.append(ScrollablePreferenceKey.self, node: scrollables.identifier)
        }
        return outputs
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

private struct CenteredScrollableLayout: _ScrollableLayout {
    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
        guard proxy.count > 0 else { return }
        proxy.visibleItems = [
            _ScrollableLayoutItem(
                id: proxy[0],
                proposedSize: CGSize(width: 40, height: 20),
                anchoring: .center,
                at: CGPoint(x: 50, y: 60)
            ),
        ]
        proxy.contentSize = CGSize(width: 100, height: 100)
        proxy.validRect = CGRect(origin: .zero, size: proxy.contentSize)
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

private struct TargetRecordingScrollableLayout: _ScrollableLayout {
    var recorder: ScrollableLayoutRecorder

    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
        recorder.proxyInputs.append(
            ScrollableProxyInputRecord(
                size: proxy.size,
                visibleRect: proxy.visibleRect
            )
        )
        proxy.visibleItems = (0..<proxy.count).map { index in
            _ScrollableLayoutItem(
                id: proxy[index],
                proposedSize: CGSize(width: 40, height: 20),
                anchoring: .topLeading,
                at: CGPoint(x: 0, y: CGFloat(index * 100))
            )
        }
        proxy.contentSize = CGSize(
            width: max(proxy.size.width, 40),
            height: proxy.count > 0 ? CGFloat((proxy.count - 1) * 100 + 20) : 0
        )
        proxy.validRect = proxy.visibleRect
    }
}

final class ScrollableLayoutSurfaceTests: XCTestCase {
    private func labels(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

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

    func testScrollViewAnimationModeTransactionSurface() {
        XCTAssertEqual(Transaction()._scrollViewAnimates, .never)
        XCTAssertEqual(
            Set<_ScrollViewAnimationMode>([.never, .discreteChanges, .always]).count,
            3
        )

        var transaction = Transaction()
        transaction._scrollViewAnimates = .discreteChanges
        XCTAssertEqual(transaction._scrollViewAnimates, .discreteChanges)
        transaction._scrollViewAnimates = .always
        XCTAssertEqual(transaction._scrollViewAnimates, .always)
    }

    func testScrollViewBehaviorStorageShapeAndIdleCompletionDispatch() {
        let graph = AttributeGraph()
        var completions: [Bool] = []

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: pixelLength
            )

            XCTAssertEqual(labels(of: ScrollViewBehavior()), [
                "phase",
                "seed",
                "containers",
            ])
            XCTAssertEqual(labels(of: ScrollViewBehavior.DragState(
                offset: .zero,
                beganOffset: .zero,
                translation: .zero,
                velocity: _Velocity(valuePerSecond: .zero),
                scrollingVertically: false,
                scrollingHorizontally: false,
                ended: false
            )), [
                "offset",
                "beganOffset",
                "translation",
                "velocity",
                "scrollingVertically",
                "scrollingHorizontally",
                "ended",
            ])
            let zeroSimulation = Deceleration2D(
                offset: .zero,
                velocity: _Velocity(valuePerSecond: .zero),
                decelerationRate: config.decelerationRate
            )
            XCTAssertEqual(labels(of: zeroSimulation), [
                "_v",
            ])
            XCTAssertEqual(labels(of: zeroSimulation.x), [
                "time",
                "offset",
                "velocity",
                "drag",
                "force",
                "bounceStiffness",
                "bounceDrag",
                "springStiffness",
                "springTarget",
                "stoppedVelocity",
                "bounced",
            ])
            XCTAssertEqual(labels(of: ScrollViewBehavior.DecelerationState(
                targetOffset: nil,
                beginTime: nil,
                completion: nil,
                simulation: zeroSimulation
            )), [
                "targetOffset",
                "beginTime",
                "completion",
                "simulation",
            ])
            XCTAssertEqual(labels(of: node), [
                "host",
                "attribute",
                "uniqueId",
                "modelOffset",
                "presentationOffset",
                "behavior",
                "isInitialized",
                "resetSeed",
                "config",
                "contentSize",
                "containerSize",
                "decelerationTarget",
                "container",
                "topScrollIndicatorFollowsContentOffset",
                "pixelLength",
                "propertySeed",
            ])

            var behavior = ScrollViewBehavior()
            let changed = behavior.updateDeceleration(
                node: node,
                target: CGPoint(x: 10, y: 20),
                velocity: nil
            ) { completed in
                completions.append(completed)
            }

            XCTAssertFalse(changed)
            XCTAssertEqual(completions, [true])
            XCTAssertEqual(behavior.seed, 0)
            guard case .idle = behavior.phase else {
                return XCTFail("no-op deceleration should leave phase idle")
            }
        }
    }

    func testScrollViewCommitInfoStoresInTransactionByNodeID() throws {
        let completion: ScrollViewBehavior.Completion = { _ in }
        let info = ScrollViewCommitInfo(
            contentOffset: (
                CGPoint(x: 12, y: 34),
                bindingValue: CGPoint(x: 10, y: 30)
            ),
            targetOffset: (
                CGPoint(x: 56, y: 78),
                bindingValue: CGPoint(x: 50, y: 70),
                velocity: _Velocity(valuePerSecond: CGSize(width: 3, height: 4)),
                completion: completion
            )
        )

        XCTAssertEqual(labels(of: info), [
            "contentOffset",
            "targetOffset",
        ])
        XCTAssertEqual(labels(of: info.contentOffset), [
            ".0",
            "bindingValue",
        ])
        let target = try XCTUnwrap(info.targetOffset)
        XCTAssertEqual(labels(of: target), [
            ".0",
            "bindingValue",
            "velocity",
            "completion",
        ])

        var transaction = Transaction()
        transaction[scrollInfo: 7] = info

        let stored = try XCTUnwrap(transaction[scrollInfo: 7])
        XCTAssertEqual(stored.contentOffset.0, CGPoint(x: 12, y: 34))
        XCTAssertEqual(stored.contentOffset.bindingValue, CGPoint(x: 10, y: 30))
        XCTAssertEqual(stored.targetOffset?.0, CGPoint(x: 56, y: 78))
        XCTAssertEqual(stored.targetOffset?.bindingValue, CGPoint(x: 50, y: 70))
        XCTAssertEqual(stored.targetOffset?.velocity?.valuePerSecond, CGSize(width: 3, height: 4))
        XCTAssertNil(transaction[scrollInfo: 8])

        transaction[scrollInfo: 7] = nil
        XCTAssertNil(transaction[scrollInfo: 7])
    }

    func testScrollViewNodeConsumesDirectCommitInfoTransaction() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: pixelLength
            )
            node.isInitialized = true
            node.behavior.phase = .decelerating(ScrollViewBehavior.DecelerationState(
                targetOffset: CGPoint(x: 99, y: 100),
                beginTime: nil,
                completion: nil,
                simulation: Deceleration2D(
                    offset: CGPoint(x: 10, y: 20),
                    velocity: _Velocity(valuePerSecond: CGSize(width: 3, height: 4)),
                    decelerationRate: config.decelerationRate,
                    target: CGPoint(x: 99, y: 100)
                )
            ))

            var transaction = Transaction()
            transaction[scrollInfo: node.uniqueId] = ScrollViewCommitInfo(
                contentOffset: (
                    CGPoint(x: 30, y: 40),
                    bindingValue: CGPoint(x: 25, y: 35)
                )
            )

            XCTAssertTrue(node.updateContentOffset(in: transaction, bindingOffset: nil))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 25, y: 35))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 30, y: 40))
            XCTAssertEqual(node.behavior.seed, 1)
            guard case .idle = node.behavior.phase else {
                return XCTFail("direct commit should reset deceleration")
            }

            XCTAssertFalse(node.updateContentOffset(in: transaction, bindingOffset: nil))
        }
    }

    func testScrollViewNodeConsumesTargetCommitInfoTransaction() {
        let graph = AttributeGraph()
        var completions: [Bool] = []

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: pixelLength
            )
            node.isInitialized = true

            var transaction = Transaction()
            transaction[scrollInfo: node.uniqueId] = ScrollViewCommitInfo(
                contentOffset: (
                    CGPoint(x: 30, y: 40),
                    bindingValue: CGPoint(x: 25, y: 35)
                ),
                targetOffset: (
                    CGPoint(x: 70, y: 80),
                    bindingValue: CGPoint(x: 65, y: 75),
                    velocity: _Velocity(valuePerSecond: CGSize(width: 11, height: 13)),
                    completion: { completed in
                        completions.append(completed)
                    }
                )
            )

            XCTAssertTrue(node.updateContentOffset(
                in: transaction,
                bindingOffset: (value: CGPoint(x: 65, y: 75), changed: true)
            ))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 65, y: 75))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 10, y: 20))
            guard case .decelerating(let state) = node.behavior.phase else {
                return XCTFail("target commit should enter deceleration")
            }
            XCTAssertEqual(state.targetOffset, CGPoint(x: 70, y: 80))
            XCTAssertEqual(state.simulation.x.initialVelocity, 11)
            XCTAssertEqual(state.simulation.y.initialVelocity, 13)
            XCTAssertEqual(state.simulation.x.target, 70)
            XCTAssertEqual(state.simulation.y.target, 80)
            XCTAssertTrue(completions.isEmpty)
        }
    }

    func testScrollViewNodeBindingChangesUseScrollViewAnimationModeGate() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: pixelLength
            )
            node.isInitialized = true

            XCTAssertTrue(node.updateContentOffset(
                in: Transaction(),
                bindingOffset: (value: CGPoint(x: 30, y: 40), changed: true)
            ))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 30, y: 40))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 30, y: 40))
            guard case .idle = node.behavior.phase else {
                return XCTFail("default .never mode should write directly")
            }

            var animated = Transaction(animation: .linear(duration: 0.25))
            animated._scrollViewAnimates = .always
            XCTAssertTrue(node.updateContentOffset(
                in: animated,
                bindingOffset: (value: CGPoint(x: 70, y: 80), changed: true)
            ))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 70, y: 80))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 30, y: 40))
            guard case .decelerating(let animatedState) = node.behavior.phase else {
                return XCTFail(".always mode should route binding changes through deceleration")
            }
            XCTAssertEqual(animatedState.targetOffset, CGPoint(x: 70, y: 80))

            var continuous = Transaction(animation: .linear(duration: 0.25))
            continuous._scrollViewAnimates = .discreteChanges
            continuous.isContinuous = true
            XCTAssertTrue(node.updateContentOffset(
                in: continuous,
                bindingOffset: (value: CGPoint(x: 90, y: 100), changed: true)
            ))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 90, y: 100))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 90, y: 100))
            guard case .idle = node.behavior.phase else {
                return XCTFail("continuous discreteChanges should write directly")
            }
        }
    }

    func testScrollViewBehaviorBuildsAndReplacesDecelerationState() {
        let graph = AttributeGraph()
        var completions: [Bool] = []

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: pixelLength
            )

            var behavior = ScrollViewBehavior(phase: .dragging(ScrollViewBehavior.DragState(
                offset: CGPoint(x: 7, y: 8),
                beganOffset: CGPoint(x: 1, y: 2),
                translation: CGSize(width: 3, height: 4),
                velocity: _Velocity(valuePerSecond: CGSize(width: 5, height: -6)),
                scrollingVertically: true,
                scrollingHorizontally: false,
                ended: false
            )))
            XCTAssertTrue(behavior.updateDeceleration(
                node: node,
                target: CGPoint(x: 70, y: 80),
                velocity: nil
            ) { completed in
                completions.append(completed)
            })

            guard case .decelerating(let firstState) = behavior.phase else {
                return XCTFail("dragging update should enter decelerating phase")
            }
            XCTAssertEqual(behavior.seed, 1)
            XCTAssertEqual(firstState.targetOffset, CGPoint(x: 70, y: 80))
            XCTAssertEqual(firstState.simulation.x.initialValue, 7)
            XCTAssertEqual(firstState.simulation.y.initialValue, 8)
            XCTAssertEqual(firstState.simulation.x.initialVelocity, -5)
            XCTAssertEqual(firstState.simulation.y.initialVelocity, 6)
            XCTAssertEqual(firstState.simulation.x.target, 70)
            XCTAssertEqual(firstState.simulation.y.target, 80)

            XCTAssertTrue(behavior.updateDeceleration(
                node: node,
                target: nil,
                velocity: _Velocity(valuePerSecond: CGSize(width: 11, height: 13)),
                completion: nil
            ))

            guard case .decelerating(let secondState) = behavior.phase else {
                return XCTFail("existing deceleration should stay decelerating")
            }
            XCTAssertEqual(behavior.seed, 2)
            XCTAssertEqual(completions, [false])
            XCTAssertNil(secondState.targetOffset)
            XCTAssertNil(secondState.simulation.x.target)
            XCTAssertNil(secondState.simulation.y.target)
            XCTAssertEqual(secondState.simulation.x.initialVelocity, -5)
            XCTAssertEqual(secondState.simulation.y.initialVelocity, 6)
        }
    }

    func testScalarDecelerationIteratesStopsAndSnapsTargets() {
        var moving = ScalarDeceleration(
            time: 0,
            offset: 10,
            velocity: _Velocity(valuePerSecond: 120),
            drag: 0.1,
            bounceStiffness: 0,
            bounceDrag: 0,
            stoppedVelocity: _Velocity(valuePerSecond: 2.5)
        )

        XCTAssertFalse(moving.iter(1.0 / 120.0, minValue: nil, maxValue: nil))
        XCTAssertEqual(moving.time, 1.0 / 120.0, accuracy: 0.0000000001)
        XCTAssertEqual(moving.offset, 10.9995833333, accuracy: 0.0000000001)
        XCTAssertEqual(moving.velocity.valuePerSecond, 119.9000208333, accuracy: 0.0000000001)
        XCTAssertEqual(moving.force, -11.995, accuracy: 0.0000000001)

        var untargeted = ScalarDeceleration(
            time: 0,
            offset: 12.6,
            velocity: _Velocity(valuePerSecond: 0),
            drag: 0.1,
            bounceStiffness: 0,
            bounceDrag: 0,
            stoppedVelocity: _Velocity(valuePerSecond: 2.5)
        )
        XCTAssertTrue(untargeted.iter(0, minValue: nil, maxValue: nil))
        XCTAssertEqual(untargeted.offset, 13)

        var targeted = ScalarDeceleration(
            time: 0,
            offset: 69.7,
            velocity: _Velocity(valuePerSecond: 0),
            drag: 17,
            bounceStiffness: 0,
            bounceDrag: 0,
            springStiffness: 100,
            springTarget: 70,
            stoppedVelocity: _Velocity(valuePerSecond: 2.5)
        )
        XCTAssertTrue(targeted.iter(0, minValue: nil, maxValue: nil))
        XCTAssertEqual(targeted.offset, 70)
        XCTAssertEqual(targeted.velocity.valuePerSecond, 0)
        XCTAssertEqual(targeted.force, 0)
    }

    func testScrollViewRubberBandingResidueUsesSwiftUIFormula() {
        let residue = _scrollViewAddRubberBandingToResidue(
            CGSize(width: 40, height: -30),
            range: CGSize(width: 100, height: 150)
        )

        XCTAssertEqual(residue.width, 3.846153846153843, accuracy: 0.0000000001)
        XCTAssertEqual(residue.height, -2.941176470588229, accuracy: 0.0000000001)
        XCTAssertEqual(
            _scrollViewAddRubberBandingToResidue(
                CGSize(width: .ulpOfOne / 2, height: 12),
                range: CGSize(width: 100, height: .ulpOfOne / 2)
            ),
            CGSize(width: .ulpOfOne / 2, height: 12)
        )
    }

    func testScrollViewBehaviorOverflowContentOffsetRubberBandsDraggingAxes() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.alwaysBounceHorizontal = true
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            node.contentSize = CGSize(width: 50, height: 50)
            node.containerSize = CGSize(width: 100, height: 100)

            var behavior = ScrollViewBehavior(phase: .dragging(ScrollViewBehavior.DragState(
                offset: CGPoint(x: -40, y: -40),
                beganOffset: .zero,
                translation: .zero,
                velocity: _Velocity(valuePerSecond: .zero),
                scrollingVertically: true,
                scrollingHorizontally: true,
                ended: false
            )))

            let offset = behavior.overflowContentOffset(CGPoint(x: -40, y: -40), node: node)
            XCTAssertEqual(offset.x, -3.846153846153843, accuracy: 0.0000000001)
            XCTAssertEqual(offset.y, 0, accuracy: 0.0000000001)
        }
    }

    func testScrollViewBehaviorOverflowContentOffsetPropagatesResidueToContainers() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let rootNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: CGPoint(x: 100, y: 0)),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            rootNode.contentSize = CGSize(width: 200, height: 100)
            rootNode.containerSize = CGSize(width: 100, height: 100)

            let childNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: CGPoint(x: 20, y: 0)),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            childNode.contentSize = CGSize(width: 300, height: 100)
            childNode.containerSize = CGSize(width: 100, height: 100)
            childNode.isInitialized = true
            childNode.modelOffset = CGPoint(x: 20, y: 0)
            childNode.presentationOffset = CGPoint(x: 20, y: 0)

            var behavior = ScrollViewBehavior(
                containers: [
                    ScrollViewBehavior.ContainerInfo(
                        node: childNode,
                        offset: CGPoint(x: 20, y: 0),
                        seed: childNode.behavior.seed
                    ),
                ]
            )

            let offset = behavior.overflowContentOffset(CGPoint(x: 150, y: 0), node: rootNode)
            XCTAssertEqual(offset, CGPoint(x: 100, y: 0))
            XCTAssertEqual(childNode.presentationOffset, CGPoint(x: 70, y: 0))
        }
    }

    func testScrollViewBehaviorReloadsParentNodeContainersForIdleDeceleration() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let parentNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: CGPoint(x: 30, y: 40)),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            parentNode.presentationOffset = CGPoint(x: 30, y: 40)

            let childNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            childNode.container = parentNode

            var behavior = ScrollViewBehavior()
            XCTAssertTrue(behavior.updateDeceleration(
                node: childNode,
                target: CGPoint(x: 10, y: 20),
                velocity: _Velocity(valuePerSecond: .zero),
                completion: nil
            ))
            XCTAssertEqual(behavior.containers.count, 1)
            XCTAssertTrue(behavior.containers[0].node === parentNode)
            XCTAssertEqual(behavior.containers[0].offset, CGPoint(x: 30, y: 40))
            XCTAssertEqual(behavior.containers[0].seed, parentNode.behavior.seed)

            var stoppingConfig = config
            stoppingConfig.stopDraggingImmediately = true
            let stoppingParent = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: stoppingConfig,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            let stoppedChild = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            stoppedChild.container = stoppingParent

            var stoppedBehavior = ScrollViewBehavior()
            XCTAssertTrue(stoppedBehavior.updateDeceleration(
                node: stoppedChild,
                target: CGPoint(x: 10, y: 20),
                velocity: _Velocity(valuePerSecond: .zero),
                completion: nil
            ))
            XCTAssertTrue(stoppedBehavior.containers.isEmpty)
        }
    }

    func testScrollViewBehaviorReloadRevalidatesParentContainersBeforeReset() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            let config = _ScrollViewConfig()
            let grandparentNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(0.5))
            )
            grandparentNode.contentSize = CGSize(width: 120, height: 140)
            grandparentNode.containerSize = CGSize(width: 40, height: 50)
            grandparentNode.isInitialized = true
            grandparentNode.modelOffset = .zero
            grandparentNode.presentationOffset = .zero

            let parentNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: CGPoint(x: 30, y: 40)),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            parentNode.presentationOffset = CGPoint(x: 30, y: 40)
            parentNode.behavior = ScrollViewBehavior(
                containers: [
                    ScrollViewBehavior.ContainerInfo(
                        node: grandparentNode,
                        offset: CGPoint(x: 100.2, y: 110.2),
                        seed: grandparentNode.behavior.seed
                    ),
                ]
            )

            let childNode = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            childNode.container = parentNode

            var behavior = ScrollViewBehavior()
            XCTAssertTrue(behavior.updateDeceleration(
                node: childNode,
                target: CGPoint(x: 10, y: 20),
                velocity: _Velocity(valuePerSecond: .zero),
                completion: nil
            ))

            XCTAssertEqual(grandparentNode.presentationOffset, CGPoint(x: 80, y: 90))
            XCTAssertTrue(parentNode.behavior.containers.isEmpty)
            XCTAssertEqual(parentNode.behavior.seed, 1)
            XCTAssertEqual(behavior.containers.count, 1)
            XCTAssertTrue(behavior.containers[0].node === parentNode)
            XCTAssertEqual(behavior.containers[0].seed, parentNode.behavior.seed)
        }
    }

    func testScrollViewBehaviorEstimatedDecelerationAndIterationTick() {
        let graph = AttributeGraph()

        AttributeGraph.$current.withValue(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offsetAttribute = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: AttributeGraphRef(graph: graph),
                contentOffset: offsetAttribute,
                config: config,
                pixelLength: pixelLength
            )
            node.contentSize = CGSize(width: 500, height: 400)
            node.containerSize = CGSize(width: 100, height: 100)

            let dragging = ScrollViewBehavior(phase: .dragging(ScrollViewBehavior.DragState(
                offset: CGPoint(x: 10, y: 20),
                beganOffset: .zero,
                translation: .zero,
                velocity: _Velocity(valuePerSecond: CGSize(width: 100, height: -50)),
                scrollingVertically: true,
                scrollingHorizontally: true,
                ended: false
            )))

            let estimated = dragging.estimatedDeceleration(from: .zero, node: node)
            XCTAssertEqual(estimated.x, 9.1225, accuracy: 0.0000000001)
            XCTAssertEqual(estimated.y, 20.4275, accuracy: 0.0000000001)

            var behavior = ScrollViewBehavior(phase: .decelerating(ScrollViewBehavior.DecelerationState(
                targetOffset: nil,
                beginTime: nil,
                completion: nil,
                simulation: Deceleration2D(
                    time: 0,
                    offset: CGSize(width: 10, height: 20),
                    velocity: _Velocity(valuePerSecond: CGSize(width: 10, height: 0)),
                    drag: 0.1,
                    bounceStiffness: 0,
                    bounceDrag: 0,
                    stoppedVelocity: _Velocity(valuePerSecond: CGFloat(2.5))
                )
            )))
            var tickOffset = CGPoint.zero

            XCTAssertFalse(behavior.iterateDeceleration(
                node: node,
                time: Time(seconds: 1.0 / 60.0),
                offset: &tickOffset,
                estimatedTarget: CGPoint(x: 40, y: 50)
            ))
            XCTAssertGreaterThan(tickOffset.x, 10)
            XCTAssertEqual(tickOffset.y, 20)
            XCTAssertEqual(behavior.seed, 1)
            guard case .decelerating(let state) = behavior.phase else {
                return XCTFail("unfinished tick should keep the decelerating phase")
            }
            XCTAssertEqual(state.beginTime?.seconds, 0)
            XCTAssertEqual(state.simulation.x.springTarget, 40)
            XCTAssertEqual(state.simulation.x.drag, 10)
            XCTAssertGreaterThan(state.simulation.x.springStiffness, 20)
            XCTAssertEqual(state.simulation.y.springTarget, 50)
            XCTAssertEqual(state.simulation.y.springStiffness, 30)
        }
    }

    func testScrollViewMainGeometryRewriteAppliesContentInsets() {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            var config = _ScrollViewConfig()
            config.contentOffset = .initially(CGPoint(x: 12, y: 34))
            config.contentInsets = EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 15)

            let provider = ScrollViewInputRecordingProvider(recorder: recorder)
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.position = graph.makeInput(value: CGPoint(x: 100, y: 200))

            _ = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )

            XCTAssertEqual(
                recorder.geometryInputs,
                [
                    ScrollableGeometryInputRecord(
                        id: -1,
                        position: CGPoint(x: 93, y: 176),
                        size: CGSize(width: 80, height: 50),
                        requestsLayoutComputer: true
                    ),
                ]
            )
        }
    }

    func testScrollViewMainWrapsChildRespondersInDefaultLayoutResponder() throws {
        let graph = AttributeGraph()
        let childResponder = ScrollViewTestResponder()

        try AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewResponderProvider>

            let provider = ScrollViewResponderProvider(responder: childResponder)
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: _ScrollViewConfig())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ViewRespondersKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let respondersID = try XCTUnwrap(outputs.preferences.value(for: ViewRespondersKey.self))
            let responders = Attribute<ViewRespondersKey.Value>(respondersID).value
            XCTAssertEqual(responders.count, 1)

            let responder = try XCTUnwrap(responders.first as? DefaultLayoutViewResponder)
            XCTAssertEqual(responder.responders.count, 1)
            XCTAssertTrue(responder.responders.first === childResponder)
            XCTAssertTrue(childResponder.nextResponder === responder)

            let result = responder.containsGlobalPoints(
                [CGPoint(x: 10, y: 10)],
                cacheKey: nil,
                options: ContainsPointsOptions()
            )
            XCTAssertEqual(result.mask, 1)
            XCTAssertEqual(result.priority, 0)
            XCTAssertEqual(result.children.count, 1)
            XCTAssertTrue(result.children.first === childResponder)

            let target = responder.scrollTarget(
                in: ScrollGeometry(
                    contentOffset: .zero,
                    contentSize: CGSize(width: 100, height: 120),
                    containerSize: CGSize(width: 100, height: 80)
                ),
                layoutDirection: .leftToRight
            )
            XCTAssertNil(target)
        }
    }

    func testDefaultLayoutResponderResetClearsScrollTargetAndChildren() {
        let childResponder = ScrollViewTestResponder()
        let responder = DefaultLayoutViewResponder(
            responders: [childResponder],
            scrollTarget: { geometry, _ in
                ScrollTarget(
                    rect: CGRect(origin: geometry.contentOffset, size: geometry.containerSize),
                    anchor: .topLeading
                )
            }
        )

        let initialTarget = responder.scrollTarget(
            in: ScrollGeometry(
                contentOffset: CGPoint(x: 4, y: 8),
                contentSize: CGSize(width: 100, height: 120),
                containerSize: CGSize(width: 40, height: 30)
            ),
            layoutDirection: .leftToRight
        )
        XCTAssertNotNil(initialTarget)

        responder.resetGesture()

        let resetTarget = responder.scrollTarget(
            in: ScrollGeometry(
                contentOffset: CGPoint(x: 4, y: 8),
                contentSize: CGSize(width: 100, height: 120),
                containerSize: CGSize(width: 40, height: 30)
            ),
            layoutDirection: .leftToRight
        )
        XCTAssertNil(resetTarget)
        XCTAssertEqual(childResponder.resetCount, 1)
    }

    func testGestureGraphResetEventsResetsRootResponders() {
        let gestureGraph = GestureGraph()
        let responder = ScrollViewTestResponder()

        gestureGraph.updateResponders([responder])
        gestureGraph.resetEvents()

        XCTAssertEqual(responder.resetCount, 1)
    }

    func testScrollViewProxyDerivedGeometryAppliesContentInsets() {
        var config = _ScrollViewConfig()
        config.contentInsets = EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 15)
        let proxy = _ScrollViewProxy(
            config: config,
            contentOffset: CGPoint(x: 12, y: 34),
            contentSize: CGSize(width: 200, height: 160),
            pageSize: CGSize(width: 100, height: 80)
        )

        XCTAssertEqual(proxy.minContentOffset, .zero)
        XCTAssertEqual(proxy.maxContentOffset, CGPoint(x: 120, y: 110))
        XCTAssertEqual(
            proxy.visibleRect,
            CGRect(x: 7, y: 24, width: 100, height: 80)
        )
    }

    func testScrollViewMainContentSizeChangeClampsContentOffset() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            var config = _ScrollViewConfig()
            config.contentOffset = .initially(CGPoint(x: 100, y: 100))
            config.contentInsets = EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 15)

            let provider = ScrollViewInputRecordingProvider(
                recorder: recorder,
                fixedContentSize: CGSize(width: 120, height: 110)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]

            var capturedGeometry: ScrollGeometry?
            XCTAssertFalse(
                scrollable.setContentTarget { geometry, _ in
                    capturedGeometry = geometry
                    return nil
                }
            )

            let geometry = try XCTUnwrap(capturedGeometry)
            XCTAssertEqual(geometry.contentOffset, CGPoint(x: 40, y: 60))
            XCTAssertEqual(geometry.contentSize, CGSize(width: 120, height: 110))
        }
    }

    func testScrollViewMainBindingOffsetCommitRoundsToPixelLength() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero
        var bindingWrites: [CGPoint] = []

        try AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            let binding = Binding<CGPoint>(
                get: { storedOffset },
                set: { value, _ in
                    storedOffset = value
                    bindingWrites.append(value)
                }
            )
            var config = _ScrollViewConfig()
            config.contentOffset = .binding(binding)

            let provider = ScrollViewInputRecordingProvider(
                recorder: recorder,
                fixedContentSize: CGSize(width: 200, height: 200)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var environment = EnvironmentValues.tracking()
            environment.defaultPixelLength = 0.5
            let environmentAttr = graph.makeInput(value: environment)
            var inputs = makeViewInputs(
                graph: graph,
                size: sizeAttr,
                environment: environmentAttr
            )
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]

            XCTAssertTrue(
                scrollable.setContentTarget { geometry, _ in
                    ScrollTarget(
                        rect: CGRect(
                            origin: CGPoint(x: 12.3, y: 34.7),
                            size: geometry.containerSize
                        )
                    )
                }
            )

            XCTAssertEqual(storedOffset, CGPoint(x: 12.5, y: 34.5))
            XCTAssertEqual(bindingWrites, [CGPoint(x: 12.5, y: 34.5)])

            var capturedGeometry: ScrollGeometry?
            XCTAssertFalse(
                scrollable.setContentTarget { geometry, _ in
                    capturedGeometry = geometry
                    return nil
                }
            )
            XCTAssertEqual(capturedGeometry?.contentOffset, CGPoint(x: 12.5, y: 34.5))
        }
    }

    func testScrollViewUpdateConsumesChangedBindingOffsetThroughStatefulRule() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero

        try AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            let binding = Binding<CGPoint>(
                get: { storedOffset },
                set: { value, _ in storedOffset = value }
            )
            var config = _ScrollViewConfig()
            config.contentOffset = .binding(binding)

            let provider = ScrollViewInputRecordingProvider(
                recorder: recorder,
                fixedContentSize: CGSize(width: 200, height: 200)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            let transactionAttr = inputs.base.transaction
            let timeAttr = inputs.base.time
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]

            var capturedGeometry: ScrollGeometry?
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, .zero)

            storedOffset = CGPoint(x: 20, y: 30)
            timeAttr.setValue(Time(seconds: 1))
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, CGPoint(x: 20, y: 30))

            storedOffset = CGPoint(x: 40, y: 50)
            var animated = Transaction(animation: .linear(duration: 0.25))
            animated._scrollViewAnimates = .always
            transactionAttr.setValue(animated)
            timeAttr.setValue(Time(seconds: 2))
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, CGPoint(x: 20, y: 30))
        }
    }

    func testScrollViewUpdateWarnsWithSwiftUIContentOffsetBindingReadMessage() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()
        let location = StoredLocationBase<CGPoint>(initialValue: .zero)

        let output = try captureStandardOutput {
            try AttributeGraph.$current.withValue(graph) {
                typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

                let binding = Binding<CGPoint>(location: location)
                _ = binding.wrappedValue
                var config = _ScrollViewConfig()
                config.contentOffset = .binding(binding)

                let provider = ScrollViewInputRecordingProvider(
                    recorder: recorder,
                    fixedContentSize: CGSize(width: 200, height: 200)
                )
                let mainAttr = graph.makeInput(
                    value: Scroll.Main(contentProvider: provider, config: config)
                )
                let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
                var inputs = makeViewInputs(graph: graph, size: sizeAttr)
                inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

                let outputs = Scroll.Main._makeView(
                    view: _GraphValue(_attribute: mainAttr),
                    inputs: inputs
                )
                let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
                let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]

                var capturedGeometry: ScrollGeometry?
                XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                    capturedGeometry = geometry
                    return nil
                })
                XCTAssertEqual(capturedGeometry?.contentOffset, .zero)
            }
        }

        XCTAssertTrue(
            output.contains(swiftUIScrollViewContentOffsetBindingReadWarning),
            output
        )
    }

    func testScrollViewUpdateUsesInheritedTransactionAfterSourceCommitTransaction() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero

        try AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            let binding = Binding<CGPoint>(
                get: { storedOffset },
                set: { value, _ in storedOffset = value }
            )
            var config = _ScrollViewConfig()
            config.contentOffset = .binding(binding)

            let provider = ScrollViewInputRecordingProvider(
                recorder: recorder,
                fixedContentSize: CGSize(width: 200, height: 200)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            let transactionAttr = inputs.base.transaction
            let timeAttr = inputs.base.time
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]

            var capturedGeometry: ScrollGeometry?
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, .zero)

            var staleAnimated = Transaction(animation: .linear(duration: 0.25))
            staleAnimated._scrollViewAnimates = .always
            withTransaction(staleAnimated) {
                XCTAssertTrue(scrollable.setContentTarget { geometry, _ in
                    ScrollTarget(
                        rect: CGRect(
                            origin: CGPoint(x: 10, y: 12),
                            size: geometry.containerSize
                        )
                    )
                })
            }
            XCTAssertEqual(storedOffset, CGPoint(x: 10, y: 12))

            storedOffset = CGPoint(x: 30, y: 40)
            transactionAttr.setValue(Transaction())
            timeAttr.setValue(Time(seconds: 1))
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, CGPoint(x: 30, y: 40))
        }
    }

    func testScrollViewUpdateDoesNotDependOnTransactionAttribute() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            var config = _ScrollViewConfig()
            config.contentOffset = .initially(.zero)

            let provider = ScrollViewInputRecordingProvider(
                recorder: recorder,
                fixedContentSize: CGSize(width: 200, height: 200)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            let transactionAttr = inputs.base.transaction
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]

            var capturedGeometry: ScrollGeometry?
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, .zero)

            let settledCounter = graph.graphCounter(lane: 1)
            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(graph.graphCounter(lane: 1), settledCounter)

            var transaction = Transaction(animation: .linear(duration: 0.25))
            transaction._scrollViewAnimates = .always
            transactionAttr.setValue(transaction)

            XCTAssertFalse(scrollable.setContentTarget { geometry, _ in
                capturedGeometry = geometry
                return nil
            })
            XCTAssertEqual(capturedGeometry?.contentOffset, .zero)
            XCTAssertEqual(graph.graphCounter(lane: 1), settledCounter)
        }
    }

    func testScrollableLayoutViewPublishesCollectionScrollableAndUpdateRequests() throws {
        let host = GraphHost()
        let child = ScrollableLayoutChildScrollable()
        var scrollablesID: AGAttribute!
        var requestsID: AGAttribute!

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = [
                ScrollablePreferenceRow(id: 0, child: child),
                ScrollablePreferenceRow(id: 1, child: nil),
                ScrollablePreferenceRow(id: 2, child: nil),
                ScrollablePreferenceRow(id: 3, child: nil),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var stored = ScrollPosition(id: 1)
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let bindingAttr = graph.makeInput(value: binding)
            let anchorAttr = graph.makeInput(value: Optional<UnitPoint>.some(.bottom))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)
            inputs.preferences.keys.insert(UpdateScrollStateRequestKey.self)
            inputs.base.setScrollPosition(storage: .binding(bindingAttr), kind: .scrollContent)
            inputs.base.setScrollPositionAnchor(OptionalAttribute(anchorAttr), kind: .scrollContent)

            let outputs = _ScrollableLayoutView<[ScrollablePreferenceRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)

            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr
            let requestsAttr = try XCTUnwrap(outputs.preferences.value(for: UpdateScrollStateRequestKey.self))
            requestsID = requestsAttr

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(Attribute<UpdateScrollStateRequestKey.Value>(requestsAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            XCTAssertEqual(scrollables.count, 2)
            XCTAssertTrue(scrollables.contains { ($0 as? ScrollableLayoutChildScrollable) === child })

            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)
            let visibleIDs = collection.visibleCollectionViewIDs
            XCTAssertEqual(
                visibleIDs,
                [0, 1, 2].map { _ViewList_ID(explicitID: AnyHashable($0)).canonicalID }
            )
            let allIDs = [0, 1, 2, 3].map {
                _ViewList_ID(explicitID: AnyHashable($0)).canonicalID
            }
            XCTAssertEqual(
                collection.firstCollectionViewIndex(of: _ViewList_ID(explicitID: AnyHashable(1)).canonicalID),
                1
            )
            XCTAssertEqual(
                collection.firstCollectionViewIndex(of: _ViewList_ID(explicitID: AnyHashable(3)).canonicalID),
                3
            )

            var index = 1
            var appliedIDs: [_ViewList_ID.Canonical] = []
            XCTAssertTrue(collection.applyCollectionViewIDs(from: &index) { id, stop in
                appliedIDs.append(id)
                stop = false
            })
            XCTAssertEqual(appliedIDs, Array(allIDs.dropFirst()))
            XCTAssertEqual(index, allIDs.count)

            var stoppedIndex = 0
            var stoppedIDs: [_ViewList_ID.Canonical] = []
            XCTAssertFalse(collection.applyCollectionViewIDs(from: &stoppedIndex) { id, stop in
                stoppedIDs.append(id)
                stop = id == _ViewList_ID(explicitID: AnyHashable(1)).canonicalID
            })
            XCTAssertEqual(stoppedIDs, Array(allIDs.prefix(2)))
            XCTAssertEqual(stoppedIndex, 2)

            let closest = try XCTUnwrap(
                collection.subviewClosest(to: CGRect(x: 0, y: 48, width: 40, height: 20))
            )
            XCTAssertEqual(closest.id.canonicalID, _ViewList_ID(explicitID: AnyHashable(2)).canonicalID)
            XCTAssertEqual(closest.frame, CGRect(x: 0, y: 48, width: 40, height: 20))
            XCTAssertEqual(closest.frameInContent, closest.frame)

            let requests = Attribute<UpdateScrollStateRequestKey.Value>(requestsID).value
            XCTAssertEqual(requests.count, 1)
            let request = try XCTUnwrap(requests.first as? UpdateScrollStateRequest)
            XCTAssertEqual(request.newPosition._anyViewID, AnyHashable(1))
            XCTAssertEqual(request.newPosition, ScrollPosition(_scrollPositionID: AnyHashable(1), anchor: .bottom))
            XCTAssertTrue(request.hasUpdate)
        }
    }

    func testScrollableLayoutCollectionRecoversCollectionIDFromItemSubgraph() throws {
        let host = GraphHost()
        let recorder = ScrollableLayoutRecorder()
        var scrollablesID: AGAttribute!
        var subgraph: AGSubgraph!

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = (0..<3).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableRecordingRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr
            subgraph = try XCTUnwrap(recorder.itemSubgraphs[1])

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)

            XCTAssertEqual(
                collection.collectionViewID(for: subgraph),
                _ViewList_ID(explicitID: AnyHashable(1)).canonicalID
            )
            XCTAssertNil(collection.collectionViewID(for: AGSubgraph()))
        }
    }

    func testScrollableLayoutCollectionNavigationReturnsNilForVisibleFacade() throws {
        let host = GraphHost()
        var scrollablesID: AGAttribute!

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = (0..<3).map { ScrollableRecordingRow(id: $0, recorder: ScrollableLayoutRecorder()) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableRecordingRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)
            let id = _ViewList_ID(explicitID: AnyHashable(1)).canonicalID

            XCTAssertNil(
                collection.nextVisibleCollectionViewID(
                    towards: .bottom,
                    from: id,
                    border: .zero,
                    ignoring: [.sectionHeaders, .sectionFooters]
                )
            )
            XCTAssertFalse(collection.isLazy)
        }
    }

    func testScrollableLayoutComputerPublishesVisibleChildGeometries() throws {
        let host = GraphHost()
        let recorder = ScrollableLayoutRecorder()
        var scrollablesID: AGAttribute!
        var geometryFrames: [CGRect] = []

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = (0..<4).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.position = graph.makeInput(value: CGPoint(x: 5, y: 7))
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableRecordingRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            let geometries = layoutAttr.value.childGeometries(
                at: ViewSize(width: 100, height: 80),
                origin: CGPoint(x: 5, y: 7)
            )
            geometryFrames = geometries.map {
                CGRect(origin: $0.origin, size: $0.dimensions.size.value)
            }
            XCTAssertEqual(geometryFrames, [
                CGRect(x: 5, y: 7, width: 40, height: 20),
                CGRect(x: 5, y: 31, width: 40, height: 20),
                CGRect(x: 5, y: 55, width: 40, height: 20),
            ])

            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)
            XCTAssertEqual(collection.visibleSubviews.map(\.frame), geometryFrames)
        }
    }

    func testScrollableLayoutCollectionRoutesVisibleIDTargetToParentScrollable() throws {
        let host = GraphHost()
        let parent = ScrollableLayoutParentScrollable()
        var scrollablesID: AGAttribute!

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = [
                ScrollablePreferenceRow(id: 0, child: nil),
                ScrollablePreferenceRow(id: 1, child: nil),
                ScrollablePreferenceRow(id: 2, child: nil),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let parentAttr: Attribute<any Scrollable> = graph.makeInput(value: parent as any Scrollable)
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)
            inputs.scrollable = OptionalAttribute(parentAttr)

            let outputs = _ScrollableLayoutView<[ScrollablePreferenceRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)

            let targetID = _ViewList_ID(explicitID: AnyHashable(1)).canonicalID
            XCTAssertTrue(collection.scroll(toCollectionViewID: targetID, anchor: .bottom))
            XCTAssertEqual(parent.contentTargets.count, 1)

            let geometry = ScrollGeometry(
                contentOffset: .zero,
                contentSize: CGSize(width: 100, height: 120),
                containerSize: CGSize(width: 100, height: 80)
            )
            let target = try XCTUnwrap(parent.contentTargets[0](geometry, .leftToRight))
            XCTAssertEqual(target.rect, CGRect(x: 0, y: 24, width: 40, height: 20))
            XCTAssertEqual(target.anchor, .bottom)

            let missingID = _ViewList_ID(explicitID: AnyHashable(99)).canonicalID
            XCTAssertFalse(collection.scroll(toCollectionViewID: missingID, anchor: .center))
            XCTAssertEqual(parent.contentTargets.count, 1)
        }
    }

    func testScrollableLayoutCollectionFallsBackToChildContentTarget() throws {
        let host = GraphHost()
        let parent = ScrollableLayoutParentScrollable()
        let child = ScrollableLayoutChildScrollable()
        var scrollablesID: AGAttribute!

        parent.shouldSetContentTarget = false
        child.shouldSetContentTarget = true

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = [
                ScrollablePreferenceRow(id: 0, child: child),
                ScrollablePreferenceRow(id: 1, child: nil),
                ScrollablePreferenceRow(id: 2, child: nil),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let parentAttr: Attribute<any Scrollable> = graph.makeInput(value: parent as any Scrollable)
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)
            inputs.scrollable = OptionalAttribute(parentAttr)

            let outputs = _ScrollableLayoutView<[ScrollablePreferenceRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)

            XCTAssertTrue(collection.setContentTarget { geometry, _ in
                ScrollTarget(rect: CGRect(origin: geometry.contentOffset, size: geometry.containerSize))
            })
            XCTAssertEqual(parent.contentTargets.count, 1)
            XCTAssertEqual(child.contentTargets.count, 1)

            parent.shouldSetContentTarget = true
            XCTAssertTrue(collection.setContentTarget { geometry, _ in
                ScrollTarget(rect: CGRect(origin: geometry.contentOffset, size: geometry.containerSize))
            })
            XCTAssertEqual(parent.contentTargets.count, 2)
            XCTAssertEqual(child.contentTargets.count, 1)
        }
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
        let host = GraphHost()
        let recorder = ScrollableLayoutRecorder()

        try host.data.withCurrent {
            let graph = host.data.graph
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

    func testScrollViewMainScrollableShellRoutesCollectionTargetThroughProxyOffset() throws {
        let host = GraphHost()
        let recorder = ScrollableLayoutRecorder()
        var layoutAttr: Attribute<LayoutComputer>!
        var scrollablesID: AGAttribute!
        var stored = ScrollPosition(idType: Int.self)
        let target = ScrollPosition(id: 2)

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = (0..<3).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            typealias LayoutView = _ScrollableLayoutView<[ScrollableRecordingRow], TargetRecordingScrollableLayout>
            typealias Scroll = _ScrollView<LayoutView>

            let provider = LayoutView(
                data: rows,
                layout: TargetRecordingScrollableLayout(recorder: recorder)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: _ScrollViewConfig())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.insert(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            _ = layoutAttr.value.sizeThatFits(ProposedViewSize(CGSize(width: 100, height: 80)))

            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value
            XCTAssertEqual(scrollables.count, 1)
            XCTAssertFalse(scrollables[0] is any ScrollableCollection)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let graph = host.data.graph
            let scrollableAttr: Attribute<any Scrollable> = graph.makeRule {
                Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value[0]
            }
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .bottomLeading,
                id: ObjectIdentifier(graph),
                value: target,
                baseTransaction: Transaction()
            )
            request.updateScrollable(scrollableAttr)

            XCTAssertTrue(request.update())
            XCTAssertEqual(stored, target)

            _ = layoutAttr.value.sizeThatFits(ProposedViewSize(CGSize(width: 100, height: 80)))
            XCTAssertEqual(
                recorder.proxyInputs.last,
                ScrollableProxyInputRecord(
                    size: CGSize(width: 100, height: 80),
                    visibleRect: CGRect(x: 0, y: 140, width: 100, height: 80)
                )
            )
        }
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

    func testScrollableItemGeometryUsesPlacementAnchorAndResolvedChildSize() throws {
        let graph = AttributeGraph()
        let recorder = ScrollableLayoutRecorder()

        try AttributeGraph.$current.withValue(graph) {
            let rows = [
                FixedSizeRecordingRow(
                    id: 0,
                    size: CGSize(width: 30, height: 10),
                    recorder: recorder
                ),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: CenteredScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.position = graph.makeInput(value: CGPoint(x: 7, y: 11))
            inputs.needsGeometry = true

            let outputs = _ScrollableLayoutView<[FixedSizeRecordingRow], CenteredScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            layoutAttr.value.place(at: CGPoint(x: 7, y: 11), proposal: ProposedViewSize(CGSize(width: 100, height: 80)))
        }

        XCTAssertEqual(recorder.geometryInputs, [
            ScrollableGeometryInputRecord(
                id: 0,
                position: CGPoint(x: 42, y: 66),
                size: CGSize(width: 30, height: 10),
                requestsLayoutComputer: true
            ),
        ])
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
        size: Attribute<ViewSize>,
        environment: Attribute<EnvironmentValues>? = nil
    ) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                customInputs: PropertyList(),
                time: graph.makeInput(value: Time()),
                cachedEnvironment: MutableBox(
                    CachedEnvironment(
                        environment: environment ?? graph.makeInput(value: EnvironmentValues.tracking())
                    )
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
