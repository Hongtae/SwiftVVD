#if canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import CRT
import ucrt
import WinSDK
#endif
import Foundation
import XCTest
@testable import VUI

#if canImport(Darwin) || canImport(WinSDK)
private let swiftUIScrollViewContentOffsetBindingReadWarning =
    "ScrollView contentOffset binding has been read; this will cause grossly inefficient view performance as the ScrollView's content will be updated whenever its contentOffset changes. Read the contentOffset binding in a view that is not parented between the creator of the binding and the ScrollView to avoid this."

private enum StandardOutputCaptureError: Error {
    case duplicateFailed
    case pipeFailed
    case redirectFailed
}

#if canImport(Darwin)
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
#elseif canImport(WinSDK)
private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
    fflush(stdout)
    let standardOutput = _fileno(stdout)
    let original = _dup(standardOutput)
    guard original >= 0 else {
        throw StandardOutputCaptureError.duplicateFailed
    }

    var fileDescriptors = [Int32](repeating: 0, count: 2)
    guard _pipe(&fileDescriptors, 4096, _O_BINARY) == 0 else {
        _close(original)
        throw StandardOutputCaptureError.pipeFailed
    }

    guard _dup2(fileDescriptors[1], standardOutput) == 0 else {
        _close(original)
        _close(fileDescriptors[0])
        _close(fileDescriptors[1])
        throw StandardOutputCaptureError.redirectFailed
    }
    _close(fileDescriptors[1])

    var bodyError: Error?
    do {
        try body()
    } catch {
        bodyError = error
    }

    fflush(stdout)
    _dup2(original, standardOutput)
    _close(original)

    let data = FileHandle(fileDescriptor: fileDescriptors[0], closeOnDealloc: true).readDataToEndOfFile()
    if let bodyError {
        throw bodyError
    }
    return String(decoding: data, as: UTF8.self)
}
#endif
#endif

private struct ScrollableGeometryInputRecord: Equatable {
    var id: Int
    var position: CGPoint
    var size: CGSize
    var requestsLayoutComputer: Bool
}

private struct ScrollableGeometryProbe {
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var requestsLayoutComputer: Bool
}

private struct ScrollableProxyInputRecord: Equatable {
    var size: CGSize
    var visibleRect: CGRect
}

private final class ScrollableRowObservation {
    var recordedMaterialization = false
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
    var lifecycleEvents: [String] = []
    var geometryProbes: [Int: ScrollableGeometryProbe] = [:]

    func beginPlacement() {
        currentPlacement = []
    }

    func finishPlacement() {
        placements.append(currentPlacement)
    }

    func sampleGeometry(for ids: [Int], recordingInputs: Bool = true) {
        beginPlacement()
        for id in ids {
            guard let probe = geometryProbes[id] else { continue }
            currentPlacement.append(id)
            let position = probe.position.value
            let size = probe.size.value.value
            if recordingInputs {
                geometryInputs.append(
                    ScrollableGeometryInputRecord(
                        id: id,
                        position: position,
                        size: size,
                        requestsLayoutComputer: probe.requestsLayoutComputer
                    )
                )
            }
        }
        finishPlacement()
    }
}

private func makeTestScrollViewProxy(
    graph: _AGGraph,
    config: _ScrollViewConfig,
    contentOffset: CGPoint,
    contentSize: CGSize,
    pageSize: CGSize,
    seed: UInt32 = 0
) -> _ScrollViewProxy {
    let offset = graph.makeInput(value: contentOffset)
    let node = ScrollViewNode(
        graphRef: _AGGraphContext(graph: graph),
        contentOffset: offset,
        config: config,
        pixelLength: graph.makeInput(value: CGFloat(1))
    )
    node.isInitialized = true
    node.modelOffset = contentOffset
    node.presentationOffset = contentOffset
    node.contentSize = contentSize
    node.containerSize = pageSize
    return _ScrollViewProxy(node: node, seed: seed)
}

private final class ScrollableLayoutDelegateGraphHost: GraphHost {
    private let delegateRecorder: ScrollableLayoutGraphDelegateRecorder

    init(delegate: ScrollableLayoutGraphDelegateRecorder) {
        self.delegateRecorder = delegate
        super.init(data: Data())
        delegate.host = self
    }

    override var graphDelegate: (any GraphDelegate)? {
        delegateRecorder
    }
}

private final class ScrollableLayoutGraphDelegateRecorder: GraphDelegate {
    weak var host: GraphHost?
    private(set) var events: [String] = []

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let host else {
            fatalError("ScrollableLayoutGraphDelegateRecorder used before attaching a host.")
        }
        events.append("update")
        return body(host)
    }

    func graphDidChange() {
        events.append("change")
    }
}

private struct ScrollableRecordingRow: View, TestPrimitiveView {
    var id: Int
    var recorder: ScrollableLayoutRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollableRecordingRow._makeView called outside an active _AGGraph context.")
        }
        let subgraph = AGSubgraph.current
        let observation = ScrollableRowObservation()
        graph.makeSideEffectRule {
            let row = view._attribute.value
            if !observation.recordedMaterialization {
                observation.recordedMaterialization = true
                row.recorder.makeViewIDs.append(row.id)
            }
            if let subgraph {
                row.recorder.itemSubgraphs[row.id] = subgraph
            }
            row.recorder.geometryProbes[row.id] = ScrollableGeometryProbe(
                position: inputs.position,
                size: inputs.size,
                requestsLayoutComputer: inputs.requestsLayoutComputer
            )
            return ()
        }
        let layout = graph.makeRule {
            testLayoutComputer(
                sizeThatFits: { proposal in
                    proposal.fixingUnspecifiedDimensions(at: CGSize(width: 30, height: 20))
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollableLifecycleRow: View, TestPrimitiveView {
    var id: Int
    var recorder: ScrollableLayoutRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollableLifecycleRow._makeView called outside an active _AGGraph context.")
        }
        let subgraph = AGSubgraph.current
        let observation = ScrollableRowObservation()
        graph.makeSideEffectRule {
            let row = view._attribute.value
            if !observation.recordedMaterialization {
                observation.recordedMaterialization = true
                row.recorder.makeViewIDs.append(row.id)
            }
            if let subgraph {
                row.recorder.itemSubgraphs[row.id] = subgraph
            }
            row.recorder.geometryProbes[row.id] = ScrollableGeometryProbe(
                position: inputs.position,
                size: inputs.size,
                requestsLayoutComputer: inputs.requestsLayoutComputer
            )
            return ()
        }
        let modifier = graph.makeRule {
            let value = view._attribute.value
            return _AppearanceActionModifier(
                appear: { value.recorder.lifecycleEvents.append("\(value.id) appear") },
                disappear: { value.recorder.lifecycleEvents.append("\(value.id) disappear") }
            )
        }
        let effect = graph.makeStatefulRule(
            AppearanceEffect(modifier: modifier, phase: inputs.base.phase)
        )
        graph.makeSideEffectRule {
            _ = effect.value
            return ()
        }
        let layout = graph.makeRule {
            testLayoutComputer(
                sizeThatFits: { proposal in
                    proposal.fixingUnspecifiedDimensions(at: CGSize(width: 30, height: 20))
                }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollableOrdinaryPreferenceKey: PreferenceKey {
    static let defaultValue = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        value += nextValue()
    }
}

private struct ScrollableMaterializationPreferenceKey: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

private struct ScrollableOrdinaryPreferenceRow: View, TestPrimitiveView {
    var id: Int
    var recorder: ScrollableLayoutRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollableOrdinaryPreferenceRow._makeView called outside an active _AGGraph context.")
        }
        let observation = ScrollableRowObservation()
        graph.makeSideEffectRule {
            let row = view._attribute.value
            if !observation.recordedMaterialization {
                observation.recordedMaterialization = true
                row.recorder.makeViewIDs.append(row.id)
            }
            return ()
        }
        let layout = graph.makeRule {
            testLayoutComputer(
                sizeThatFits: { proposal in
                    proposal.fixingUnspecifiedDimensions(at: CGSize(width: 30, height: 20))
                }
            )
        }
        let ordinary = graph.makeRule {
            "\(view._attribute.value.id),"
        }
        var preferences = PreferencesOutputs()
        preferences.append(ScrollableOrdinaryPreferenceKey.self, node: ordinary.identifier)
        return _ViewOutputs(
            preferences: preferences,
            layoutComputer: OptionalAttribute(layout)
        )
    }
}

private struct ScrollViewInputRecordingContent: View, TestPrimitiveView {
    var recorder: ScrollableLayoutRecorder
    var fixedContentSize: CGSize?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewInputRecordingContent._makeView called outside an active _AGGraph context.")
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
    var resetCount = 0

    override func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func resetGesture() {
        resetCount += 1
    }

    override func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewTestResponder.makeGesture requires AG context.")
        }
        return _GestureOutputs(
            phase: graph.makeInput(value: GesturePhase<Void>.possible(nil))
        )
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        let count = min(points.count, 64)
        let mask = count == 64 ? UInt64.max : ((UInt64(1) << UInt64(count)) - 1)
        return ViewResponder.ContainsPointsResult(
            mask: BitVector64(rawValue: mask),
            priority: 16,
            children: []
        )
    }
}

private final class ScrollableGestureGraphTestResponder:
    ResponderNode,
    AnyGestureResponder
{
    var relatedAttribute: AGAttribute { .invalid }
    var inputs: _ViewInputs { fatalError("unused test responder input") }
    var childSubgraph: AGSubgraph?
    var childViewSubgraph: AGSubgraph?
    var viewSubgraph: AGSubgraph { gestureGraph.rootSubgraph }
    var eventSources: [any EventBindingSource] { [] }
    var gestureType: Any.Type { Self.self }
    var isValid: Bool { true }
    lazy var gestureGraph = GestureGraph(rootResponder: self)

    override var nextResponder: ResponderNode? { nil }

    func detachContainer() {}
}

private struct RecordingLayoutGestureEventBindingCall: Equatable {
    var eventCount: Int
    var proxyCount: Int
    var firstChildContainsEventLocation: Bool
}

private enum RecordingLayoutGestureEventBindingStore {
    nonisolated(unsafe) static var calls: [RecordingLayoutGestureEventBindingCall] = []

    static func reset() {
        calls = []
    }
}

private func layoutTestEvent(
    location: CGPoint,
    phase: EventPhase
) -> VUI.MouseEvent {
    VUI.MouseEvent(
        timestamp: .zero,
        binding: nil,
        button: .primary,
        phase: phase,
        location: location,
        globalLocation: location,
        modifiers: []
    )
}

private func testResponderGroup(_ children: [ViewResponder]) -> MultiViewResponder {
    let responder = MultiViewResponder()
    responder.children = children
    return responder
}

private struct LayoutGesturePreferenceKey: PreferenceKey {
    static var defaultValue: [String] { [] }

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

private final class LayoutGesturePreferenceResponder: MultiViewResponder {
    var value: String
    var makeGestureCount = 0

    init(hitTestKey: UInt32, value: String) {
        _ = hitTestKey
        self.value = value
        super.init()
    }

    override func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        let count = min(points.count, 64)
        let mask = count == 64 ? UInt64.max : ((UInt64(1) << UInt64(count)) - 1)
        return ViewResponder.ContainsPointsResult(
            mask: BitVector64(rawValue: mask),
            priority: 16,
            children: []
        )
    }

    override func makeGesture(inputs: _GestureInputs) -> _GestureOutputs<()> {
        guard let graph = _AGGraph.current else {
            fatalError("LayoutGesturePreferenceResponder.makeGesture requires AG context.")
        }
        makeGestureCount += 1
        let phase: Attribute<GesturePhase<Void>> = graph.makeInput(value: .possible(nil))
        var outputs = _GestureOutputs(phase: phase)
        if inputs.preferences.keys.contains(LayoutGesturePreferenceKey.self) {
            let preference = graph.makeRule {
                [self.value]
            }
            outputs.preferences.append(LayoutGesturePreferenceKey.self, node: preference.identifier)
        }
        return outputs
    }
}

private struct RecordingLayoutGesture: LayoutGesture {
    var responder: MultiViewResponder

    typealias Value = Void
    typealias Body = Never

    static func updateEventBindings(
        _ eventBindings: inout [EventID: any EventType],
        proxy: LayoutGestureChildProxy
    ) {
        var firstChildContainsEventLocation = false
        if let (eventID, event) = eventBindings.first,
           proxy.indices.contains(0) {
            _ = proxy.bindChild(index: 0, event: event, id: eventID)
            if let event = event as? any HitTestableEventType {
                firstChildContainsEventLocation = proxy[0].containsGlobalLocation(
                    event.hitTestLocation
                )
            }
        }
        RecordingLayoutGestureEventBindingStore.calls.append(
            RecordingLayoutGestureEventBindingCall(
                eventCount: eventBindings.count,
                proxyCount: proxy.count,
                firstChildContainsEventLocation: firstChildContainsEventLocation
            )
        )
    }
}

private struct RecordingPreferenceLayoutGesture: LayoutGesture {
    var responder: MultiViewResponder

    typealias Value = Void
    typealias Body = Never

    static func updateEventBindings(
        _ eventBindings: inout [EventID: any EventType],
        proxy: LayoutGestureChildProxy
    ) {
        for index in proxy.indices {
            guard let match = eventBindings.first(where: { $0.key.serial == index + 1 }) else {
                continue
            }
            _ = proxy.bindChild(index: index, event: match.value, id: match.key)
        }
    }
}

private struct ScrollViewResponderContent: View, TestPrimitiveView {
    var responder: ScrollViewTestResponder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewResponderContent._makeView called outside an active _AGGraph context.")
        }
        let content = view._attribute.value
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 30, height: 20))
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        if inputs.preferences.keys.contains(ViewRespondersKey.self) {
            let responders: Attribute<[ViewResponder]> = graph.makeInput(value: [content.responder])
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

private struct FixedSizeRecordingRow: View, TestPrimitiveView {
    var id: Int
    var size: CGSize
    var recorder: ScrollableLayoutRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("FixedSizeRecordingRow._makeView called outside an active _AGGraph context.")
        }
        graph.makeSideEffectRule {
            let row = view._attribute.value
            row.recorder.geometryProbes[row.id] = ScrollableGeometryProbe(
                position: inputs.position,
                size: inputs.size,
                requestsLayoutComputer: inputs.requestsLayoutComputer
            )
            return ()
        }
        let layout = graph.makeRule {
            let row = view._attribute.value
            return testLayoutComputer(
                sizeThatFits: { _ in row.size }
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollableMeasuringRow: View, TestPrimitiveView {
    var id: Int
    var recorder: ScrollableLayoutRecorder?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollableMeasuringRow._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            testLayoutComputer(
                sizeThatFits: { proposal in
                    let row = view._attribute.value
                    let resolved = proposal.fixingUnspecifiedDimensions(at: CGSize(width: 30, height: 20))
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

private final class ScrollableLayoutLookupMarker {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private final class ScrollableLayoutChildScrollable: Scrollable {
    var contentTargets: [(ScrollGeometry, LayoutDirection) -> ScrollTarget?] = []
    var shouldSetContentTarget = false
    var firstChildMarker: ScrollableLayoutLookupMarker?
    var mapFirstChildCallCount = 0

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
        mapFirstChildCallCount += 1
        if let marker = firstChildMarker as? A {
            return body(marker)
        }
        return nil
    }
}

private final class ScrollableLayoutParentScrollable: Scrollable {
    var contentTargets: [(ScrollGeometry, LayoutDirection) -> ScrollTarget?] = []
    var shouldSetContentTarget = true
    var firstChildMarker: ScrollableLayoutLookupMarker?
    var mapFirstChildCallCount = 0

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
        mapFirstChildCallCount += 1
        if let marker = firstChildMarker as? A {
            return body(marker)
        }
        return nil
    }
}

private struct ScrollablePreferenceRow: View, TestPrimitiveView {
    var id: Int
    var child: ScrollableLayoutChildScrollable?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollablePreferenceRow._makeView called outside an active _AGGraph context.")
        }

        let layout = graph.makeRule {
            testLayoutComputer(
                sizeThatFits: { proposal in
                    proposal.fixingUnspecifiedDimensions(at: CGSize(width: 30, height: 20))
                }
            )
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        let scrollables: Attribute<[any Scrollable]> = graph.makeRule {
            guard let child = view._attribute.value.child else {
                return []
            }
            return [child]
        }
        outputs.preferences.append(ScrollablePreferenceKey.self, node: scrollables.identifier)
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

private struct OffsetSensitiveValidRectScrollableLayout: _ScrollableLayout {
    var recorder: ScrollableLayoutRecorder

    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
        recorder.proxyInputs.append(
            ScrollableProxyInputRecord(
                size: proxy.size,
                visibleRect: proxy.visibleRect
            )
        )

        let rowStride: CGFloat = 24
        let lowerBound = max(Int((proxy.visibleRect.minY / rowStride).rounded(.down)), 0)
        let upperBound = min(proxy.count, lowerBound + 3)
        proxy.visibleItems = (lowerBound..<upperBound).map { index in
            _ScrollableLayoutItem(
                id: proxy[index],
                proposedSize: CGSize(width: 40, height: 20),
                anchoring: .topLeading,
                at: CGPoint(x: 0, y: CGFloat(index) * rowStride)
            )
        }
        proxy.contentSize = CGSize(
            width: proxy.size.width,
            height: CGFloat(max(proxy.count, 1)) * rowStride
        )
        proxy.validRect = CGRect(origin: .zero, size: proxy.contentSize)
    }
}

private struct NonVisibleTargetScrollableLayout: _ScrollableLayout {
    var recorder: ScrollableLayoutRecorder

    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
        recorder.proxyInputs.append(
            ScrollableProxyInputRecord(
                size: proxy.size,
                visibleRect: proxy.visibleRect
            )
        )

        let rowHeight: CGFloat = 30
        let rowStride: CGFloat = 34
        let paddedVisibleRect = proxy.visibleRect.insetBy(dx: 0, dy: -80)
        var visibleItems: [_ScrollableLayoutItem] = []
        for index in 0..<proxy.count {
            let rect = CGRect(
                x: 0,
                y: CGFloat(index) * rowStride,
                width: proxy.size.width,
                height: rowHeight
            )
            guard rect.intersects(paddedVisibleRect) else { continue }
            visibleItems.append(
                _ScrollableLayoutItem(
                    id: proxy[index],
                    proposedSize: rect.size,
                    anchoring: .topLeading,
                    at: rect.origin
                )
            )
        }

        let contentSize = CGSize(
            width: proxy.size.width,
            height: CGFloat(proxy.count) * rowStride
        )
        proxy.visibleItems = visibleItems
        proxy.contentSize = contentSize
        proxy.validRect = paddedVisibleRect.intersection(
            CGRect(origin: .zero, size: contentSize)
        )
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

private struct ScrollableDecelerationCall: Equatable {
    var contentOffset: CGPoint
    var originalContentOffset: CGPoint
    var velocity: _Velocity<CGSize>
    var size: CGSize
}

private final class ScrollableDecelerationRecorder {
    var calls: [ScrollableDecelerationCall] = []
}

private struct DecelerationForwardingScrollableLayout: _ScrollableLayout {
    var recorder: ScrollableDecelerationRecorder

    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
    }

    func decelerationTarget(
        contentOffset: CGPoint,
        originalContentOffset: CGPoint,
        velocity: _Velocity<CGSize>,
        size: CGSize
    ) -> CGPoint? {
        recorder.calls.append(
            ScrollableDecelerationCall(
                contentOffset: contentOffset,
                originalContentOffset: originalContentOffset,
                velocity: velocity,
                size: size
            )
        )
        return CGPoint(x: 111, y: 222)
    }
}

final class ScrollableLayoutSurfaceTests: XCTestCase {
    private static func flushGraphActions(_ graph: _AGGraph) {
        graph.drainActionOutbox()
    }

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

    func testScrollableLayoutViewForwardsDecelerationTargetToLayout() {
        let recorder = ScrollableDecelerationRecorder()
        let velocity = _Velocity(valuePerSecond: CGSize(width: 7, height: -8))
        let view = _ScrollableLayoutView(
            data: [Text("row")],
            layout: DecelerationForwardingScrollableLayout(recorder: recorder)
        )

        let target = view.decelerationTarget(
            contentOffset: CGPoint(x: 1, y: 2),
            originalContentOffset: CGPoint(x: 3, y: 4),
            velocity: velocity,
            size: CGSize(width: 5, height: 6)
        )

        XCTAssertEqual(target, CGPoint(x: 111, y: 222))
        XCTAssertEqual(recorder.calls, [
            ScrollableDecelerationCall(
                contentOffset: CGPoint(x: 1, y: 2),
                originalContentOffset: CGPoint(x: 3, y: 4),
                velocity: velocity,
                size: CGSize(width: 5, height: 6)
            )
        ])
    }

    func testScrollViewBehaviorStorageShapeAndIdleCompletionDispatch() {
        let graph = _AGGraph()
        var completions: [Bool] = []

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()
        var completions: [Bool] = []

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()
        var completions: [Bool] = []

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offset = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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

    func testScrollDecelerationRateUsesFrameConvertedDrag() {
        XCTAssertEqual(
            _scrollViewDecelerationDrag(decelerationRate: 0.998),
            1.9853950944093768,
            accuracy: 0.0000000001
        )
        XCTAssertEqual(
            _scrollViewDecelerationDrag(decelerationRate: 0.99),
            9.640971753730314,
            accuracy: 0.0000000001
        )
        XCTAssertEqual(
            _scrollViewDecelerationDrag(decelerationRate: 0.9999),
            1,
            accuracy: 0.0000000001
        )

        var simulation = Deceleration2D(
            offset: .zero,
            velocity: _Velocity(
                valuePerSecond: CGSize(width: 0, height: 100)
            ),
            decelerationRate: 0.998
        )
        XCTAssertFalse(simulation.iter(
            1,
            minValue: .zero,
            maxValue: CGPoint(x: 1_000, y: 1_000)
        ))
        XCTAssertTrue(simulation.iter(
            3,
            minValue: .zero,
            maxValue: CGPoint(x: 1_000, y: 1_000)
        ))
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.alwaysBounceHorizontal = true
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let rootNode = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: graph.makeInput(value: CGPoint(x: 100, y: 0)),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            rootNode.contentSize = CGSize(width: 200, height: 100)
            rootNode.containerSize = CGSize(width: 100, height: 100)

            let childNode = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let parentNode = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: graph.makeInput(value: CGPoint(x: 30, y: 40)),
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            parentNode.presentationOffset = CGPoint(x: 30, y: 40)

            let childNode = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: graph.makeInput(value: .zero),
                config: stoppingConfig,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            let stoppedChild = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let config = _ScrollViewConfig()
            let grandparentNode = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
                graphRef: _AGGraphContext(graph: graph),
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
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.decelerationRate = 0.9
            let offsetAttribute = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
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
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        _AGGraph.withCurrent(graph) {
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

    func testScrollViewChildModifierRewritesContentGeometry() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.contentOffset = .initially(CGPoint(x: 12, y: 34))
            config.contentInsets = EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 15)

            let contentOffset = graph.makeInput(value: CGPoint(x: 12, y: 34))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: contentOffset,
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            node.isInitialized = true
            node.contentSize = CGSize(width: 200, height: 160)
            node.containerSize = CGSize(width: 100, height: 80)
            let proxy = graph.makeInput(value: _ScrollViewProxy(
                node: node,
                seed: node.propertySeed &+ node.behavior.seed
            ))
            let modifier: Attribute<ScrollViewChildModifier.Value> = graph.makeRule(
                ScrollViewChildModifier(_proxy: proxy, node: node)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.position = graph.makeInput(value: CGPoint(x: 100, y: 200))
            inputs[ContainingScrollViewInput.self] = _ContainingScrollView(
                proxy: proxy,
                contentOffset: contentOffset
            )

            var childPosition: CGPoint?
            var childSize: CGSize?
            _ = ScrollViewChildModifier.Value._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, rewrittenInputs in
                childPosition = rewrittenInputs.position.value
                childSize = rewrittenInputs.size.value.value
                return _ViewOutputs()
            }

            XCTAssertEqual(childPosition, CGPoint(x: 93, y: 176))
            XCTAssertEqual(childSize, CGSize(width: 80, height: 50))
        }
    }

    func testScrollViewMainWrapsChildRespondersInDefaultLayoutResponder() throws {
        let graph = _AGGraph()
        let childResponder = ScrollViewTestResponder()

        try _AGGraph.withCurrent(graph) {
            let subgraph = AGSubgraph()
            try AGSubgraph.withCurrent(subgraph) {
                typealias Scroll = _ScrollView<ScrollViewResponderProvider>

                let provider = ScrollViewResponderProvider(responder: childResponder)
                let mainAttr = graph.makeInput(
                    value: Scroll.Main(contentProvider: provider, config: _ScrollViewConfig())
                )
                let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
                var inputs = makeViewInputs(graph: graph, size: sizeAttr)
                inputs.preferences.keys.add(ViewRespondersKey.self)

                let outputs = Scroll.Main._makeView(
                    view: _GraphValue(_attribute: mainAttr),
                    inputs: inputs
                )
                let respondersID = try XCTUnwrap(
                    outputs.preferences.value(for: ViewRespondersKey.self)
                )
                let responders = Attribute<ViewRespondersKey.Value>(respondersID).value
                XCTAssertEqual(responders.count, 1)

                let responder = try XCTUnwrap(
                    responders.first as? DefaultLayoutViewResponder
                )
                let gestureResponder = try XCTUnwrap(
                    responder.children.first as? GestureResponder<ScrollViewGesture>
                )
                let contentShapeResponder = try XCTUnwrap(
                    gestureResponder.children.first as? ContentShapeResponder<Rectangle>
                )
                XCTAssertEqual(responder.children.count, 1)
                XCTAssertTrue(gestureResponder.parent === responder)
                XCTAssertEqual(gestureResponder.children.count, 1)
                XCTAssertTrue(contentShapeResponder.parent === gestureResponder)
                XCTAssertEqual(contentShapeResponder.children.count, 1)
                XCTAssertTrue(contentShapeResponder.children.first === childResponder)
                XCTAssertTrue(childResponder.parent === contentShapeResponder)

                let result = responder.containsGlobalPoints(
                    [CGPoint(x: 10, y: 10)],
                    cacheKey: nil,
                    options: ViewResponder.ContainsPointsOptions()
                )
                XCTAssertEqual(result.mask.rawValue, 1)
                XCTAssertEqual(result.priority, 16)
                XCTAssertEqual(result.children.count, 1)
                XCTAssertTrue(result.children.first === gestureResponder)
            }
        }
    }

    func testDefaultLayoutResponderFilterUpdatesStableResponderFromChildrenAttribute() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let firstChild = ScrollViewTestResponder()
            let secondChild = ScrollViewTestResponder()
            let children: Attribute<[ViewResponder]> = graph.makeInput(
                value: [firstChild as ViewResponder]
            )
            let responder = MultiViewResponder()
            let output: Attribute<[ViewResponder]> = graph.makeStatefulRule(
                DefaultLayoutResponderFilter(children: children, responder: responder)
            )

            let initialOutput = output.value
            XCTAssertEqual(initialOutput.count, 1)
            XCTAssertTrue(initialOutput.first === responder)
            XCTAssertEqual(responder.children.count, 1)
            XCTAssertTrue(responder.children.first === firstChild)
            XCTAssertTrue(firstChild.parent === responder)

            children.setValue([secondChild as ViewResponder])

            let updatedOutput = output.value
            XCTAssertEqual(updatedOutput.count, 1)
            XCTAssertTrue(updatedOutput.first === responder)
            XCTAssertEqual(responder.children.count, 1)
            XCTAssertTrue(responder.children.first === secondChild)
            XCTAssertTrue(secondChild.parent === responder)

            let manualChild = ScrollViewTestResponder()
            responder.children = [manualChild]
            graph.invalidateAttribute(output.identifier)

            let invalidatedOutput = output.value
            XCTAssertEqual(invalidatedOutput.count, 1)
            XCTAssertTrue(invalidatedOutput.first === responder)
            XCTAssertEqual(responder.children.count, 1)
            XCTAssertTrue(responder.children.first === manualChild)
        }
    }

    func testMultiViewResponderResetGesturePropagatesToChildren() {
        let responder = ScrollViewTestResponder()
        let root = testResponderGroup([responder])

        root.resetGesture()

        XCTAssertEqual(responder.resetCount, 1)
    }

    func testDefaultLayoutGestureUpdateEventBindingsDefaultIsNoOp() {
        let firstID = EventID(type: VUI.MouseEvent.self, serial: 1)
        let secondID = EventID(type: VUI.MouseEvent.self, serial: 2)
        var events: [EventID: any EventType] = [
            firstID: layoutTestEvent(location: CGPoint(x: 1, y: 2), phase: .began),
            secondID: layoutTestEvent(location: CGPoint(x: 3, y: 4), phase: .active)
        ]

        DefaultLayoutGesture.updateEventBindings(&events, proxy: LayoutGestureChildProxy())

        XCTAssertEqual(Set(events.keys), [firstID, secondID])
        XCTAssertEqual(events.count, 2)
    }

    func testLayoutGestureMakeGestureRoutesEventsThroughUpdateEventBindings() {
        RecordingLayoutGestureEventBindingStore.reset()
        defer { RecordingLayoutGestureEventBindingStore.reset() }

        let gestureResponder = ScrollableGestureGraphTestResponder()
        let gestureGraph = gestureResponder.gestureGraph
        let child = ScrollViewTestResponder()
        let root = testResponderGroup([child])
        let eventID = EventID(type: VUI.MouseEvent.self, serial: 31)

        gestureGraph.data.withCurrent {
            func assertPossibleNil(_ phase: GesturePhase<Void>, file: StaticString = #filePath, line: UInt = #line) {
                guard case .possible(nil) = phase else {
                    XCTFail("expected possible(nil)", file: file, line: line)
                    return
                }
            }

            let graph = gestureGraph.data.graph
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            let viewInputs = makeViewInputs(graph: graph, size: sizeAttr)
            let events = graph.makeInput(value: [
                eventID: layoutTestEvent(location: CGPoint(x: 4, y: 5), phase: .began)
            ] as [EventID: any EventType])
            let resetSeed = graph.makeInput(value: UInt32(0))
            let inheritedPhase = graph.makeInput(value: _GestureInputs.InheritedPhase.defaultValue)
            let preferenceKeys = graph.makeInput(value: PreferenceKeys())
            var inputs = _GestureInputs(
                viewInputs,
                viewSubgraph: nil,
                events: events,
                time: viewInputs.base.time,
                resetSeed: resetSeed,
                inheritedPhase: inheritedPhase,
                gesturePreferenceKeys: preferenceKeys
            )
            inputs.options = .gestureGraph

            let gesture = graph.makeInput(value: RecordingLayoutGesture(responder: root))
            let outputs = RecordingLayoutGesture._makeGesture(
                gesture: _GraphValue(_attribute: gesture),
                inputs: inputs
            )

            XCTAssertTrue(RecordingLayoutGestureEventBindingStore.calls.isEmpty)
            assertPossibleNil(outputs.phase.value)
            XCTAssertEqual(RecordingLayoutGestureEventBindingStore.calls, [
                RecordingLayoutGestureEventBindingCall(
                    eventCount: 1,
                    proxyCount: 1,
                    firstChildContainsEventLocation: true
                )
            ])
            XCTAssertTrue(gestureGraph.eventBindingManager.eventBindings[eventID]?.responder === child)

            assertPossibleNil(outputs.phase.value)
            XCTAssertEqual(RecordingLayoutGestureEventBindingStore.calls.count, 1)

            events.setValue([
                eventID: layoutTestEvent(location: CGPoint(x: 6, y: 7), phase: .active)
            ])
            assertPossibleNil(outputs.phase.value)
            XCTAssertEqual(RecordingLayoutGestureEventBindingStore.calls.count, 2)
        }
    }

    func testLayoutGestureCombinesChildGesturePreferences() throws {
        let gestureResponder = ScrollableGestureGraphTestResponder()
        let gestureGraph = gestureResponder.gestureGraph
        let first = LayoutGesturePreferenceResponder(hitTestKey: 91, value: "first")
        let second = LayoutGesturePreferenceResponder(hitTestKey: 92, value: "second")
        let root = testResponderGroup([first, second])
        let firstID = EventID(type: VUI.MouseEvent.self, serial: 1)
        let secondID = EventID(type: VUI.MouseEvent.self, serial: 2)

        try gestureGraph.data.withCurrent {
            let graph = gestureGraph.data.graph
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            let viewInputs = makeViewInputs(graph: graph, size: sizeAttr)
            let events = graph.makeInput(value: [
                firstID: layoutTestEvent(location: CGPoint(x: 4, y: 5), phase: .began),
                secondID: layoutTestEvent(location: CGPoint(x: 6, y: 7), phase: .began)
            ] as [EventID: any EventType])
            let resetSeed = graph.makeInput(value: UInt32(0))
            let inheritedPhase = graph.makeInput(value: _GestureInputs.InheritedPhase.defaultValue)
            let preferenceKeys = graph.makeInput(value: PreferenceKeys())
            var inputs = _GestureInputs(
                viewInputs,
                viewSubgraph: nil,
                events: events,
                time: viewInputs.base.time,
                resetSeed: resetSeed,
                inheritedPhase: inheritedPhase,
                gesturePreferenceKeys: preferenceKeys
            )
            inputs.options = .gestureGraph
            inputs.preferences.keys.add(LayoutGesturePreferenceKey.self)

            let gesture = graph.makeInput(value: RecordingPreferenceLayoutGesture(responder: root))
            let outputs = RecordingPreferenceLayoutGesture._makeGesture(
                gesture: _GraphValue(_attribute: gesture),
                inputs: inputs
            )

            let preferenceID = try XCTUnwrap(outputs.preferences.value(for: LayoutGesturePreferenceKey.self))
            XCTAssertEqual(Attribute<LayoutGesturePreferenceKey.Value>(preferenceID).value, ["first", "second"])
            XCTAssertEqual(first.makeGestureCount, 1)
            XCTAssertEqual(second.makeGestureCount, 1)

            XCTAssertEqual(Attribute<LayoutGesturePreferenceKey.Value>(preferenceID).value, ["first", "second"])
            XCTAssertEqual(first.makeGestureCount, 1)
            XCTAssertEqual(second.makeGestureCount, 1)
        }
    }

    func testLayoutGestureChildProxyCollectionUsesResponderChildren() {
        let first = ScrollViewTestResponder()
        let second = ScrollViewTestResponder()
        let root = testResponderGroup([first, second])
        let proxy = LayoutGestureChildProxy(responder: root)

        XCTAssertEqual(proxy.startIndex, 0)
        XCTAssertEqual(proxy.endIndex, 2)
        XCTAssertTrue(proxy[0].containsGlobalLocation(CGPoint(x: 1, y: 2)))
        XCTAssertTrue(proxy[1].binds(EventBinding(responder: second)))
        XCTAssertFalse(proxy[0].binds(EventBinding(responder: second)))
    }

    func testLayoutGestureChildProxyBindChildRoutesThroughEventBindingManager() {
        let child = ScrollViewTestResponder()
        let root = testResponderGroup([child])
        let eventBindingManager = EventBindingManager()
        let proxy = LayoutGestureChildProxy(
            responder: root,
            eventBindingManager: eventBindingManager
        )
        let eventID = EventID(type: VUI.MouseEvent.self, serial: 7)

        let result = proxy.bindChild(
            index: 0,
            event: layoutTestEvent(location: CGPoint(x: 4, y: 5), phase: .began),
            id: eventID
        )

        XCTAssertNil(result?.from)
        XCTAssertTrue(result?.to?.responder === child)
        XCTAssertTrue(eventBindingManager.eventBindings[eventID]?.responder === child)
        XCTAssertNil(LayoutGestureChildProxy(responder: root).bindChild(
            index: 0,
            event: layoutTestEvent(location: CGPoint(x: 4, y: 5), phase: .began),
            id: eventID
        ))
    }

    func testLayoutGestureBoxStoresChildEventsThroughUpdateEventBindings() {
        RecordingLayoutGestureEventBindingStore.reset()
        defer { RecordingLayoutGestureEventBindingStore.reset() }

        let eventBindingManager = EventBindingManager()
        let child = ScrollViewTestResponder()
        let root = testResponderGroup([child])
        let box = LayoutGestureBox(eventBindingManager: eventBindingManager)
        let eventID = EventID(type: VUI.MouseEvent.self, serial: 41)

        box.updateResponder(root)

        let initialGeneration = box.generation
        let initialSeed = box.childSeed(at: 0)

        box.willSendEvents([
            eventID: layoutTestEvent(location: CGPoint(x: 3, y: 4), phase: .began)
        ], gesture: RecordingLayoutGesture(responder: root))

        XCTAssertEqual(RecordingLayoutGestureEventBindingStore.calls, [
            RecordingLayoutGestureEventBindingCall(
                eventCount: 1,
                proxyCount: 1,
                firstChildContainsEventLocation: true
            )
        ])
        XCTAssertTrue(eventBindingManager.eventBindings[eventID]?.responder === child)
        XCTAssertEqual(Set(box.childEvents(at: 0).keys), [eventID])
        XCTAssertEqual(box.childSeed(at: 0), initialSeed)
        XCTAssertGreaterThan(box.generation, initialGeneration)
    }

    func testLayoutGestureBoxBumpsPreviousChildSeedWhenBindingMoves() {
        let eventBindingManager = EventBindingManager()
        let first = ScrollViewTestResponder()
        let second = ScrollViewTestResponder()
        let root = testResponderGroup([first, second])
        let box = LayoutGestureBox(eventBindingManager: eventBindingManager)
        let proxy = LayoutGestureChildProxy(box: box)
        let eventID = EventID(type: VUI.MouseEvent.self, serial: 42)

        box.updateResponder(root)
        eventBindingManager.rebindEvent(eventID, to: first)

        let firstSeed = box.childSeed(at: 0)
        let secondSeed = box.childSeed(at: 1)
        let generation = box.generation

        let movement = proxy.bindChild(
            index: 1,
            event: layoutTestEvent(location: CGPoint(x: 8, y: 9), phase: .active),
            id: eventID
        )

        XCTAssertTrue(movement?.from?.responder === first)
        XCTAssertTrue(movement?.to?.responder === second)
        XCTAssertTrue(eventBindingManager.eventBindings[eventID]?.responder === second)
        XCTAssertGreaterThan(box.childSeed(at: 0), firstSeed)
        XCTAssertEqual(box.childSeed(at: 1), secondSeed)
        XCTAssertGreaterThan(box.generation, generation)
    }

    func testLayoutGestureBoxUpdateResetSeedInvalidatesChildSubgraphs() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let child = MultiViewResponder()
            let root = testResponderGroup([child])
            let box = LayoutGestureBox()
            let childSubgraph = AGSubgraph()

            box.updateResponder(root)
            box.setChildSubgraph(childSubgraph, at: 0)

            let seed = box.childSeed(at: 0)
            let generation = box.generation
            XCTAssertTrue(box.childSubgraph(at: 0) === childSubgraph)
            XCTAssertTrue(AGSubgraphIsValid(childSubgraph))

            box.updateResetSeed(1)

            XCTAssertNil(box.childSubgraph(at: 0))
            XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
            XCTAssertGreaterThan(box.childSeed(at: 0), seed)
            XCTAssertGreaterThan(box.generation, generation)
        }
    }

    func testLayoutGestureBoxUpdateResponderInvalidatesRemovedChildSubgraphs() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let removed = MultiViewResponder()
            let kept = MultiViewResponder()
            let initialRoot = testResponderGroup([removed, kept])
            let updatedRoot = testResponderGroup([kept])
            let box = LayoutGestureBox()
            let removedSubgraph = AGSubgraph()
            let keptSubgraph = AGSubgraph()

            box.updateResponder(initialRoot)
            box.setChildSubgraph(removedSubgraph, at: 0)
            box.setChildSubgraph(keptSubgraph, at: 1)

            XCTAssertTrue(box.childSubgraph(at: 0) === removedSubgraph)
            XCTAssertTrue(box.childSubgraph(at: 1) === keptSubgraph)
            XCTAssertTrue(AGSubgraphIsValid(removedSubgraph))
            XCTAssertTrue(AGSubgraphIsValid(keptSubgraph))

            box.updateResponder(updatedRoot)

            XCTAssertEqual(box.childCount, 1)
            XCTAssertTrue(box.childSubgraph(at: 0) === keptSubgraph)
            XCTAssertFalse(AGSubgraphIsValid(removedSubgraph))
            XCTAssertTrue(AGSubgraphIsValid(keptSubgraph))
        }
    }

    func testLayoutGestureBoxUpdateResponderReordersChildrenByIdentity() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let first = MultiViewResponder()
            let second = MultiViewResponder()
            let initialRoot = testResponderGroup([first, second])
            let updatedRoot = testResponderGroup([second, first])
            let box = LayoutGestureBox()
            let firstSubgraph = AGSubgraph()
            let secondSubgraph = AGSubgraph()

            box.updateResponder(initialRoot)
            box.setChildSubgraph(firstSubgraph, at: 0)
            box.setChildSubgraph(secondSubgraph, at: 1)

            let firstSeed = box.childSeed(at: 0)
            let secondSeed = box.childSeed(at: 1)
            let generation = box.generation

            box.updateResponder(updatedRoot)

            XCTAssertEqual(box.childCount, 2)
            XCTAssertTrue(box.child(at: 0).binds(EventBinding(responder: second)))
            XCTAssertTrue(box.child(at: 1).binds(EventBinding(responder: first)))
            XCTAssertTrue(box.childSubgraph(at: 0) === secondSubgraph)
            XCTAssertTrue(box.childSubgraph(at: 1) === firstSubgraph)
            XCTAssertEqual(box.childSeed(at: 0), secondSeed)
            XCTAssertEqual(box.childSeed(at: 1), firstSeed)
            XCTAssertGreaterThan(box.generation, generation)
            XCTAssertTrue(AGSubgraphIsValid(firstSubgraph))
            XCTAssertTrue(AGSubgraphIsValid(secondSubgraph))
        }
    }

    func testLayoutGestureBoxResetsTerminalChildren() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let child = MultiViewResponder()
            let root = testResponderGroup([child])
            let box = LayoutGestureBox()
            let childSubgraph = AGSubgraph()

            box.updateResponder(root)
            box.setChildSubgraph(childSubgraph, at: 0)
            box.setChildPhase(.ended(()), at: 0)

            guard case .ended = box.phase() else {
                XCTFail("expected ended phase before terminal reset")
                return
            }

            let seed = box.childSeed(at: 0)
            let generation = box.generation
            XCTAssertTrue(box.childSubgraph(at: 0) === childSubgraph)
            XCTAssertTrue(AGSubgraphIsValid(childSubgraph))

            box.resetTerminalChildren()

            guard case .possible(nil) = box.phase() else {
                XCTFail("expected possible(nil) phase after terminal reset")
                return
            }
            XCTAssertNil(box.childSubgraph(at: 0))
            XCTAssertFalse(AGSubgraphIsValid(childSubgraph))
            XCTAssertGreaterThan(box.childSeed(at: 0), seed)
            XCTAssertGreaterThan(box.generation, generation)
        }
    }

    func testDefaultLayoutResponderChildrenChangeInvalidatesStoredLayoutGesture() throws {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let initialChild = ScrollViewTestResponder()
            let updatedChild = ScrollViewTestResponder()
            let children: Attribute<[ViewResponder]> = graph.makeInput(
                value: [initialChild as ViewResponder]
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            let viewInputs = makeViewInputs(graph: graph, size: sizeAttr)
            let viewSubgraph = AGSubgraph()
            let responder = DefaultLayoutViewResponder(
                inputs: viewInputs,
                viewSubgraph: viewSubgraph
            )
            let output: Attribute<[ViewResponder]> = graph.makeStatefulRule(
                DefaultLayoutResponderFilter(children: children, responder: responder)
            )

            XCTAssertTrue(output.value.first === responder)
            XCTAssertFalse(host.hasPendingTransactions)

            let events = graph.makeInput(value: [:] as [EventID: any EventType])
            let resetSeed = graph.makeInput(value: UInt32(0))
            let inheritedPhase = graph.makeInput(value: _GestureInputs.InheritedPhase.defaultValue)
            let preferenceKeys = graph.makeInput(value: PreferenceKeys())
            var gestureInputs = _GestureInputs(
                viewInputs,
                viewSubgraph: viewSubgraph,
                events: events,
                time: viewInputs.base.time,
                resetSeed: resetSeed,
                inheritedPhase: inheritedPhase,
                gesturePreferenceKeys: preferenceKeys
            )
            gestureInputs.options = .gestureGraph

            let gestureOutputs = responder.makeGesture(inputs: gestureInputs)
            guard case .possible(nil) = gestureOutputs.phase.value else {
                XCTFail("expected possible(nil)")
                return
            }
            XCTAssertFalse(host.hasPendingTransactions)

            children.setValue([updatedChild as ViewResponder])
            XCTAssertTrue(output.value.first === responder)
            XCTAssertEqual(responder.children.count, 1)
            XCTAssertTrue(responder.children.first === updatedChild)
            XCTAssertTrue(host.hasPendingTransactions)
        }
    }

    func testScrollViewProxyDerivedGeometryAppliesContentInsets() {
        let graph = _AGGraph()
        var config = _ScrollViewConfig()
        config.contentInsets = EdgeInsets(top: 10, leading: 5, bottom: 20, trailing: 15)
        _AGGraph.withCurrent(graph) {
            let proxy = makeTestScrollViewProxy(
                graph: graph,
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
    }

    func testEventDirectionsRawValuesMatchSwiftUIAxisBits() {
        XCTAssertTrue(type(of: _EventDirections.left.rawValue) == Int8.self)
        XCTAssertEqual(_EventDirections.left.rawValue, 1)
        XCTAssertEqual(_EventDirections.right.rawValue, 2)
        XCTAssertEqual(_EventDirections.up.rawValue, 4)
        XCTAssertEqual(_EventDirections.down.rawValue, 8)
        XCTAssertEqual(_EventDirections.horizontal.rawValue, 3)
        XCTAssertEqual(_EventDirections.vertical.rawValue, 12)
        XCTAssertEqual(_EventDirections.all.rawValue, 15)
    }

    func testScrollViewProxyNextPageUsesInsetViewportAndClampsToContent() {
        let graph = _AGGraph()
        var config = _ScrollViewConfig()
        config.contentInsets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        _AGGraph.withCurrent(graph) {
            var proxy = makeTestScrollViewProxy(
                graph: graph,
                config: config,
                contentOffset: CGPoint(x: 300, y: 300),
                contentSize: CGSize(width: 1_000, height: 800),
                pageSize: CGSize(width: 300, height: 200)
            )

            XCTAssertEqual(proxy.contentOffsetOfNextPage(.left), CGPoint(x: 60, y: 300))
            XCTAssertEqual(proxy.contentOffsetOfNextPage(.right), CGPoint(x: 540, y: 300))
            XCTAssertEqual(proxy.contentOffsetOfNextPage(.up), CGPoint(x: 300, y: 140))
            XCTAssertEqual(proxy.contentOffsetOfNextPage(.down), CGPoint(x: 300, y: 460))
            XCTAssertEqual(
                proxy.contentOffsetOfNextPage([.right, .down]),
                CGPoint(x: 540, y: 460)
            )

            proxy.contentOffset = CGPoint(x: 900, y: 700)
            XCTAssertEqual(proxy.contentOffsetOfNextPage([.right, .down]), proxy.maxContentOffset)
        }
    }

    func testScrollViewProxyScrollRectUsesMinimalInsetViewportAdjustment() {
        let graph = _AGGraph()
        var config = _ScrollViewConfig()
        config.contentInsets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        _AGGraph.withCurrent(graph) {
            let proxy = makeTestScrollViewProxy(
                graph: graph,
                config: config,
                contentOffset: CGPoint(x: 100, y: 100),
                contentSize: CGSize(width: 1_000, height: 800),
                pageSize: CGSize(width: 300, height: 200)
            )
            var completions: [Bool] = []

            proxy.scrollRectToVisible(
                CGRect(x: 100, y: 120, width: 40, height: 40),
                animated: false
            ) { completions.append($0) }
            XCTAssertEqual(proxy.contentOffset, CGPoint(x: 100, y: 100))
            XCTAssertEqual(completions, [true])

            proxy.scrollRectToVisible(
                CGRect(x: 400, y: 300, width: 50, height: 40),
                animated: false
            ) { completions.append($0) }
            XCTAssertEqual(proxy.contentOffset, CGPoint(x: 210, y: 180))
            XCTAssertEqual(completions, [true, false])

            proxy.scrollRectToVisible(
                CGRect(x: 100, y: 50, width: 400, height: 300),
                animated: false
            )
            XCTAssertEqual(proxy.contentOffset, CGPoint(x: 100, y: 50))
        }
    }

    func testScrollViewProxyLiveNodeRoutesAnimatedAndDiscreteCommits() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let offset = graph.makeInput(value: CGPoint.zero)
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: offset,
                config: _ScrollViewConfig(),
                pixelLength: pixelLength
            )
            node.containerSize = CGSize(width: 100, height: 80)
            node.contentSize = CGSize(width: 100, height: 500)
            let proxy = _ScrollViewProxy(node: node, seed: 7)
            XCTAssertEqual(labels(of: proxy), ["node", "seed"])
            XCTAssertEqual(proxy, _ScrollViewProxy(node: node, seed: 7))
            XCTAssertNotEqual(proxy, _ScrollViewProxy(node: node, seed: 8))
            var completions: [Bool] = []

            proxy.setContentOffset(CGPoint(x: 0, y: 180), animated: false) {
                completions.append($0)
            }
            XCTAssertEqual(proxy.contentOffset, CGPoint(x: 0, y: 180))
            XCTAssertEqual(offset.value, CGPoint(x: 0, y: 180))
            XCTAssertEqual(completions, [false])

            proxy.setContentOffset(CGPoint(x: 0, y: 180), animated: false) {
                completions.append($0)
            }
            XCTAssertEqual(completions, [false, true])

            proxy.setContentOffset(CGPoint(x: 0, y: 300), animated: true) {
                completions.append($0)
            }
            guard case .decelerating(let state) = node.behavior.phase else {
                XCTFail("expected animated proxy commit to enter deceleration")
                return
            }
            XCTAssertEqual(state.targetOffset, CGPoint(x: 0, y: 300))
            XCTAssertEqual(completions, [false, true])

            proxy.setContentOffset(CGPoint(x: 0, y: 200), animated: false) {
                completions.append($0)
            }
            XCTAssertEqual(proxy.contentOffset, CGPoint(x: 0, y: 200))
            XCTAssertEqual(offset.value, CGPoint(x: 0, y: 200))
            XCTAssertEqual(completions, [false, true, false, false])
        }
    }

    func testScrollGestureWheelPhaseSelectionMatchesSwiftUIBranching() {
        let panValue = PanGesture.Value(
            timestamp: Time(seconds: 1),
            translation: CGSize(width: 4, height: 8),
            touchType: .indirect,
            velocity: _Velocity(valuePerSecond: CGSize(width: 40, height: 80))
        )
        let wheel = WheelEvent(
            timestamp: Time(seconds: 2),
            phase: .active,
            binding: nil,
            offset: 12
        )

        XCTAssertEqual(
            ScrollGesture.selectPhase(
                pan: .active(panValue),
                wheel: .possible(nil)
            ),
            .active(.pan(panValue))
        )
        XCTAssertEqual(
            ScrollGesture.selectPhase(
                pan: .failed,
                wheel: .possible(wheel)
            ),
            .possible(.wheel(CGSize(width: 0, height: -12)))
        )
        XCTAssertEqual(
            ScrollGesture.selectPhase(
                pan: .failed,
                wheel: .active(wheel)
            ),
            .active(.wheel(CGSize(width: 0, height: -12)))
        )
        XCTAssertEqual(
            ScrollGesture.selectPhase(
                pan: .failed,
                wheel: .ended(wheel)
            ),
            .ended(.wheel(CGSize(width: 0, height: -12)))
        )
        XCTAssertEqual(
            ScrollGesture.selectPhase(
                pan: .ended(panValue),
                wheel: .failed
            ),
            .ended(.pan(panValue))
        )
    }

    func testScrollViewGestureDispatchTracksDragAndStartsDeceleration() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let initial = CGPoint(x: 0, y: 100)
            let offset = graph.makeInput(value: initial)
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: offset,
                config: _ScrollViewConfig(),
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            node.isInitialized = true
            node.modelOffset = initial
            node.presentationOffset = initial
            node.containerSize = CGSize(width: 200, height: 100)
            node.contentSize = CGSize(width: 200, height: 800)
            let proxy = _ScrollViewProxy(
                node: node,
                seed: node.propertySeed &+ node.behavior.seed
            )
            let active = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -30),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            )

            proxy._dispatchScrollGesturePhase(.active(.pan(active)))

            XCTAssertTrue(proxy.isDragging)
            XCTAssertFalse(proxy.isDecelerating)
            XCTAssertFalse(proxy.isScrollingHorizontally)
            XCTAssertTrue(proxy.isScrollingVertically)
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 0, y: 130))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 0, y: 130))
            XCTAssertEqual(offset.value, CGPoint(x: 0, y: 130))

            proxy._dispatchScrollGesturePhase(.ended(.pan(active)))

            XCTAssertFalse(proxy.isDragging)
            XCTAssertTrue(proxy.isDecelerating)
            guard case .decelerating(let deceleration) = node.behavior.phase else {
                XCTFail("expected terminal pan to start deceleration")
                return
            }
            XCTAssertNotNil(deceleration.targetOffset)
            XCTAssertEqual(
                deceleration.simulation.velocity.valuePerSecond.height,
                300,
                accuracy: 0.001
            )
        }
    }

    func testScrollViewGestureTerminalUsesContentProviderDecelerationTarget() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var config = _ScrollViewConfig()
            config.contentInsets = EdgeInsets(
                top: 10,
                leading: 20,
                bottom: 30,
                trailing: 40
            )
            let offset = graph.makeInput(value: CGPoint(x: 50, y: 60))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            node.isInitialized = true
            node.modelOffset = CGPoint(x: 50, y: 60)
            node.presentationOffset = CGPoint(x: 50, y: 60)
            node.containerSize = CGSize(width: 300, height: 200)
            node.contentSize = CGSize(width: 1_000, height: 800)

            var calls: [(CGPoint, CGPoint, CGSize, CGSize)] = []
            node.decelerationTarget = { current, original, velocity, size in
                calls.append((current, original, velocity.valuePerSecond, size))
                return CGPoint(x: 400, y: 500)
            }
            let proxy = _ScrollViewProxy(
                node: node,
                seed: node.propertySeed &+ node.behavior.seed
            )
            let active = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: -30, height: -40),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: -200, height: -300))
            )

            proxy._dispatchScrollGesturePhase(.active(.pan(active)))
            proxy._dispatchScrollGesturePhase(.ended(.pan(active)))

            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].0, CGPoint(x: 80, y: 100))
            XCTAssertEqual(calls[0].1, CGPoint(x: 50, y: 60))
            XCTAssertEqual(calls[0].2, CGSize(width: -200, height: -300))
            XCTAssertEqual(calls[0].3, CGSize(width: 240, height: 160))
            guard case .decelerating(let state) = node.behavior.phase else {
                return XCTFail("expected provider target to start deceleration")
            }
            XCTAssertEqual(state.targetOffset, CGPoint(x: 400, y: 500))
        }
    }

    func testScrollViewProxyAnimatedCommitSeparatesBindingAndPresentationUntilCompletion() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var bindingValue = CGPoint(x: 0, y: 490)
            let binding = Binding<CGPoint>(
                get: { bindingValue },
                set: { value, _ in bindingValue = value }
            )
            var config = _ScrollViewConfig()
            config.contentOffset = .binding(binding)
            let offset = graph.makeInput(value: bindingValue)
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: offset,
                config: config,
                pixelLength: graph.makeInput(value: CGFloat(1))
            )
            node.isInitialized = true
            node.containerSize = CGSize(width: 240, height: 140)
            node.contentSize = CGSize(width: 240, height: 2_720)
            node.modelOffset = bindingValue
            node.presentationOffset = bindingValue
            let proxy = _ScrollViewProxy(
                node: node,
                seed: node.propertySeed &+ node.behavior.seed
            )
            var completions: [Bool] = []

            proxy.setContentOffset(CGPoint(x: 0, y: 900), animated: true) {
                completions.append($0)
            }

            XCTAssertEqual(bindingValue, CGPoint(x: 0, y: 900))
            XCTAssertEqual(node.modelOffset, CGPoint(x: 0, y: 900))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 0, y: 490))
            XCTAssertTrue(completions.isEmpty)

            guard case .decelerating(let state) = node.behavior.phase,
                  let beginTime = state.beginTime else {
                return XCTFail("expected a time-based animated proxy commit")
            }

            var maxPresentationY = node.presentationOffset.y
            var completionElapsed: Double?
            for step in 1...60 {
                var behavior = node.behavior
                var presentation = node.presentationOffset
                let elapsed = Double(step) * 0.05
                _ = behavior.iterateDeceleration(
                    node: node,
                    time: Time(seconds: beginTime.seconds + elapsed),
                    offset: &presentation,
                    estimatedTarget: nil
                )
                node.behavior = behavior
                node.presentationOffset = presentation
                maxPresentationY = max(maxPresentationY, presentation.y)
                if completionElapsed == nil, !completions.isEmpty {
                    completionElapsed = elapsed
                }
            }

            XCTAssertEqual(node.presentationOffset.y, 900, accuracy: 0.001)
            XCTAssertGreaterThan(maxPresentationY, 900)
            XCTAssertEqual(completions, [true])
            XCTAssertGreaterThanOrEqual(completionElapsed ?? 0, 0.5)
            XCTAssertLessThanOrEqual(completionElapsed ?? .infinity, 1.5)
        }
    }

    func testScrollViewProxyLiveDragRejectsProgrammaticOffset() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let offset = graph.makeInput(value: CGPoint(x: 20, y: 30))
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let node = ScrollViewNode(
                graphRef: _AGGraphContext(graph: graph),
                contentOffset: offset,
                config: _ScrollViewConfig(),
                pixelLength: pixelLength
            )
            node.isInitialized = true
            node.containerSize = CGSize(width: 100, height: 80)
            node.contentSize = CGSize(width: 300, height: 500)
            node.behavior.phase = .dragging(ScrollViewBehavior.DragState(
                offset: CGPoint(x: 20, y: 30),
                beganOffset: CGPoint(x: 20, y: 30),
                translation: .zero,
                velocity: _Velocity(valuePerSecond: .zero),
                scrollingVertically: false,
                scrollingHorizontally: false,
                ended: false
            ))
            let proxy = _ScrollViewProxy(
                node: node,
                seed: node.propertySeed &+ node.behavior.seed
            )
            var completions: [Bool] = []

            proxy.setContentOffset(CGPoint(x: 70, y: 90), animated: false) {
                completions.append($0)
            }

            XCTAssertEqual(node.modelOffset, CGPoint(x: 20, y: 30))
            XCTAssertEqual(node.presentationOffset, CGPoint(x: 20, y: 30))
            XCTAssertEqual(offset.value, CGPoint(x: 20, y: 30))
            XCTAssertEqual(completions, [false])
        }
    }

    func testScrollViewMainContentSizeChangeClampsContentOffset() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
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
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

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

    func testScrollViewUpdatePublishesProxySeedForContainerAndConfigChanges() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
            typealias Scroll = _ScrollView<ScrollViewInputRecordingProvider>

            var config = _ScrollViewConfig()
            config.contentOffset = .initially(.zero)
            let provider = ScrollViewInputRecordingProvider(
                recorder: recorder,
                fixedContentSize: CGSize(width: 300, height: 500)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(
                outputs.preferences.value(for: ScrollablePreferenceKey.self)
            )
            let scrollable = Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value[0]
            let node = try XCTUnwrap(
                Mirror(reflecting: scrollable).children
                    .first(where: { $0.label == "node" })?.value as? ScrollViewNode
            )

            let initialProxy = try XCTUnwrap(node.currentProxy)
            let initialPropertySeed = node.propertySeed
            XCTAssertEqual(initialProxy.pageSize, CGSize(width: 100, height: 80))

            sizeAttr.setValue(ViewSize(width: 140, height: 90))
            let resizedProxy = try XCTUnwrap(node.currentProxy)
            XCTAssertTrue(initialProxy.node === resizedProxy.node)
            XCTAssertEqual(node.propertySeed, initialPropertySeed &+ 1)
            XCTAssertEqual(resizedProxy.seed, initialProxy.seed &+ 1)
            XCTAssertNotEqual(initialProxy, resizedProxy)
            XCTAssertEqual(resizedProxy.pageSize, CGSize(width: 140, height: 90))

            config.contentInsets = EdgeInsets(
                top: 3,
                leading: 5,
                bottom: 7,
                trailing: 11
            )
            mainAttr.setValue(Scroll.Main(contentProvider: provider, config: config))
            let configuredProxy = try XCTUnwrap(node.currentProxy)
            XCTAssertTrue(resizedProxy.node === configuredProxy.node)
            XCTAssertEqual(node.propertySeed, initialPropertySeed &+ 2)
            XCTAssertEqual(configuredProxy.seed, resizedProxy.seed &+ 1)
            XCTAssertNotEqual(resizedProxy, configuredProxy)
            XCTAssertEqual(configuredProxy.config.contentInsets, config.contentInsets)

            // ASSERTIONS: scrollViewUpdateInputSeedPropagationObserved
        }
    }

    func testScrollViewMainBindingOffsetCommitRoundsToPixelLength() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero
        var bindingWrites: [CGPoint] = []

        try _AGGraph.withCurrent(graph) {
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
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

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
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero

        try _AGGraph.withCurrent(graph) {
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
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

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

    #if canImport(Darwin) || canImport(WinSDK)
    func testScrollViewUpdateWarnsWithSwiftUIContentOffsetBindingReadMessage() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()
        let location = TestStoredLocation<CGPoint>(initialValue: .zero)

        let output = try captureStandardOutput {
            try _AGGraph.withCurrent(graph) {
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
                inputs.preferences.keys.add(ScrollablePreferenceKey.self)

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
    #endif

    func testScrollViewUpdateUsesInheritedTransactionAfterSourceCommitTransaction() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero

        try _AGGraph.withCurrent(graph) {
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
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

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
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
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
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

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

    func testScrollableLayoutComputerPublishesContentSizeWhileItemsOwnGeometry() throws {
        let host = GraphHost()
        let recorder = ScrollableLayoutRecorder()

        try host.data.withCurrent {
            let graph = host.data.graph
            let rows = (0..<4).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.position = graph.makeInput(value: CGPoint(x: 5, y: 7))
            inputs.needsGeometry = true
            inputs.requestsLayoutComputer = true
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableRecordingRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            _ = try materializeDynamicItems(in: outputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
            XCTAssertEqual(
                layoutAttr.value.sizeThatFits(_ProposedSize(CGSize(width: 100, height: 80))),
                CGSize(width: 100, height: 72)
            )

            recorder.sampleGeometry(for: [0, 1, 2])
            let geometryFrames = recorder.geometryInputs.map {
                CGRect(origin: $0.position, size: $0.size)
            }
            XCTAssertEqual(geometryFrames, [
                CGRect(x: 5, y: 7, width: 40, height: 20),
                CGRect(x: 5, y: 31, width: 40, height: 20),
                CGRect(x: 5, y: 55, width: 40, height: 20),
            ])
        }

        host.flushTransactions()
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
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
            let rows = [
                ScrollableMeasuringRow(id: 7),
                ScrollableMeasuringRow(id: 11),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: MeasuringScrollableLayout(recorder: recorder))
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.requestsLayoutComputer = true

            let outputs = _ScrollableLayoutView<[ScrollableMeasuringRow], MeasuringScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)

            let measuredContentSize = layoutAttr.value.sizeThatFits(
                _ProposedSize(CGSize(width: 100, height: 80))
            )
            XCTAssertEqual(measuredContentSize, CGSize(width: 51, height: 31))
        }

        XCTAssertEqual(recorder.measuredSizes, [CGSize(width: 51, height: 31)])
    }

    func testScrollableLayoutProxyContentSeedIgnoresGeometryOnlyUpdates() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
            let rows = [
                ScrollableMeasuringRow(id: 7, recorder: recorder),
                ScrollableMeasuringRow(id: 11, recorder: recorder),
            ]
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: MeasuringScrollableLayout(recorder: recorder))
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.requestsLayoutComputer = true

            let outputs = _ScrollableLayoutView<[ScrollableMeasuringRow], MeasuringScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)

            _ = layoutAttr.value.sizeThatFits(_ProposedSize(CGSize(width: 100, height: 80)))
            XCTAssertEqual(recorder.templateMeasuredSizes, [CGSize(width: 51, height: 31)])

            sizeAttr.setValue(ViewSize(width: 140, height: 80))
            _ = layoutAttr.value.sizeThatFits(_ProposedSize(CGSize(width: 100, height: 80)))
            XCTAssertEqual(recorder.templateMeasuredSizes, [CGSize(width: 51, height: 31)])

            let changedRows = [
                ScrollableMeasuringRow(id: 7, recorder: recorder),
                ScrollableMeasuringRow(id: 17, recorder: recorder),
            ]
            viewAttr.setValue(
                _ScrollableLayoutView(data: changedRows, layout: MeasuringScrollableLayout(recorder: recorder))
            )
            _ = layoutAttr.value.sizeThatFits(_ProposedSize(CGSize(width: 100, height: 80)))
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
                layoutAttr.value.sizeThatFits(_ProposedSize(CGSize(width: 100, height: 80))),
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

    func testScrollableLayoutViewOffsetInsideValidRectReusesVisibleItems() throws {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = ScrollableLayoutRecorder()
        var storedOffset = CGPoint.zero

        try host.data.withCurrent {
            let binding = Binding<CGPoint>(
                get: { storedOffset },
                set: { value, _ in storedOffset = value }
            )
            var config = _ScrollViewConfig()
            config.contentOffset = .binding(binding)

            typealias LayoutView = _ScrollableLayoutView<
                [ScrollableRecordingRow],
                OffsetSensitiveValidRectScrollableLayout
            >
            typealias Scroll = _ScrollView<LayoutView>

            let rows = (0..<8).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            let provider = LayoutView(
                data: rows,
                layout: OffsetSensitiveValidRectScrollableLayout(recorder: recorder)
            )
            let mainAttr = graph.makeInput(
                value: Scroll.Main(contentProvider: provider, config: config)
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.needsGeometry = true
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)
            let timeAttr = inputs.base.time

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: mainAttr),
                inputs: inputs
            )
            let materialization = try materializeDynamicItems(in: outputs)

            func sampleVisibleGeometry() {
                _ = materialization.value
                recorder.sampleGeometry(for: [0, 1, 2], recordingInputs: false)
            }

            sampleVisibleGeometry()
            XCTAssertEqual(recorder.proxyInputs, [
                ScrollableProxyInputRecord(
                    size: CGSize(width: 100, height: 80),
                    visibleRect: CGRect(x: 0, y: 0, width: 100, height: 80)
                ),
            ])
            XCTAssertEqual(recorder.placements, [[0, 1, 2]])

            storedOffset = CGPoint(x: 0, y: 48)
            timeAttr.setValue(Time(seconds: 1))
            sampleVisibleGeometry()

            XCTAssertEqual(recorder.proxyInputs.count, 1)
            XCTAssertEqual(recorder.placements, [
                [0, 1, 2],
                [0, 1, 2],
            ])
            XCTAssertFalse(recorder.makeViewIDs.contains(3))
            XCTAssertFalse(recorder.makeViewIDs.contains(4))
        }
    }

    func testScrollableLayoutPrivateProxyTargetRealizesNonVisibleAdaptorItem() throws {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = ScrollableLayoutRecorder()

        try host.data.withCurrent {
            typealias LayoutView = _ScrollableLayoutView<
                [ScrollableRecordingRow],
                NonVisibleTargetScrollableLayout
            >
            typealias Scroll = _ScrollView<LayoutView>

            let rows = (0..<120).map {
                ScrollableRecordingRow(id: $0, recorder: recorder)
            }
            let provider = LayoutView(
                data: rows,
                layout: NonVisibleTargetScrollableLayout(recorder: recorder)
            )
            let main = graph.makeInput(
                value: Scroll.Main(
                    contentProvider: provider,
                    config: _ScrollViewConfig()
                )
            )
            let size = graph.makeInput(value: ViewSize(width: 240, height: 140))
            var inputs = makeViewInputs(graph: graph, size: size)
            inputs.needsGeometry = true
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

            let outputs = Scroll.Main._makeView(
                view: _GraphValue(_attribute: main),
                inputs: inputs
            )
            let materialization = try materializeDynamicItems(in: outputs)
            XCTAssertFalse(recorder.makeViewIDs.contains(100))
            XCTAssertLessThan(recorder.makeViewIDs.count, 20)

            let scrollablesID = try XCTUnwrap(
                outputs.preferences.value(for: ScrollablePreferenceKey.self)
            )
            let scrollable = try XCTUnwrap(
                Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value.first
            )
            XCTAssertTrue(
                scrollable.setContentTarget { geometry, _ in
                    ScrollTarget(
                        rect: CGRect(
                            x: 0,
                            y: 3_290,
                            width: geometry.containerSize.width,
                            height: geometry.containerSize.height
                        )
                    )
                }
            )

            _ = materialization.value
            XCTAssertEqual(recorder.proxyInputs.last?.visibleRect.minY, 3_290)
            XCTAssertNotNil(recorder.geometryProbes[100])
            recorder.sampleGeometry(for: [100], recordingInputs: false)
            XCTAssertEqual(recorder.placements.last, [100])
            XCTAssertLessThan(Set(recorder.makeViewIDs).count, 20)
        }

        host.flushTransactions()

        // ASSERTIONS: scrollableLayoutPrivateProxyTargetRealizationObserved,
        // scrollableLayoutPrivateProxyHostFlowObserved,
        // scrollViewProxyNodeSeedIdentityObserved,
        // scrollableLayoutPrivateRuleConformancesObserved
    }

    func testScrollableLayoutViewRetainsMarkerAndProviderRoles() {
        typealias LayoutView = _ScrollableLayoutView<
            [ScrollableRecordingRow],
            NonVisibleTargetScrollableLayout
        >
        let erasedType: Any.Type = LayoutView.self

        XCTAssertTrue(erasedType is any PrimitiveView.Type)
        XCTAssertTrue(erasedType is any UnaryView.Type)
        XCTAssertTrue(erasedType is any _ScrollableContentProvider.Type)
        XCTAssertFalse(erasedType is any Scrollable.Type)
        XCTAssertFalse(erasedType is any ScrollableCollection.Type)

        // ASSERTIONS: scrollableLayoutMarkerProtocolsObserved,
        // scrollableLayoutDedicatedCollectionProducerAbsentObserved
    }

    func testScrollableLayoutViewPlacesVisibleItemsAndReusesOneUnusedItem() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
            let rows = (0..<4).map { ScrollableRecordingRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.needsGeometry = true
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableRecordingRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let materialization = try materializeDynamicItems(in: outputs)

            recorder.sampleGeometry(for: [0, 1, 2])

            sizeAttr.setValue(ViewSize(width: 100, height: 40))
            _ = materialization.value
            recorder.sampleGeometry(for: [0])

            sizeAttr.setValue(ViewSize(width: 100, height: 80))
            _ = materialization.value
            recorder.sampleGeometry(for: [0, 1, 2])
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

    func testScrollableLayoutViewReusedUnusedItemRunsDisappearAndAppear() throws {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = ScrollableLayoutRecorder()

        try host.data.withCurrent {
            let rows = (0..<4).map { ScrollableLifecycleRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.needsGeometry = true
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableLifecycleRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let materialization = try materializeDynamicItems(in: outputs)

            XCTAssertEqual(
                recorder.lifecycleEvents.filter { $0.hasPrefix("1 ") || $0.hasPrefix("2 ") },
                ["1 appear", "2 appear"]
            )

            sizeAttr.setValue(ViewSize(width: 100, height: 40))
            _ = materialization.value
            XCTAssertEqual(
                recorder.lifecycleEvents.filter { $0.hasPrefix("1 ") || $0.hasPrefix("2 ") },
                ["1 appear", "2 appear", "1 disappear", "2 disappear"]
            )

            sizeAttr.setValue(ViewSize(width: 100, height: 80))
            _ = materialization.value
            // Reused and rebuilt rows need the same per-row lifecycle, not
            // a shared sibling callback order.
            for id in 1...2 {
                XCTAssertEqual(
                    recorder.lifecycleEvents.filter { $0.hasPrefix("\(id) ") },
                    ["\(id) appear", "\(id) disappear", "\(id) appear"]
                )
            }
        }

        XCTAssertEqual(recorder.makeViewIDs.filter { $0 == 1 }.count, 1)
        XCTAssertEqual(recorder.makeViewIDs.filter { $0 == 2 }.count, 2)
    }

    func testScrollableLayoutViewRetainedUnusedReinsertNotifiesGraphDelegate() throws {
        let delegate = ScrollableLayoutGraphDelegateRecorder()
        let host = ScrollableLayoutDelegateGraphHost(delegate: delegate)
        let graph = host.data.graph
        let recorder = ScrollableLayoutRecorder()

        try host.data.withCurrent {
            let rows = (0..<4).map { ScrollableLifecycleRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.needsGeometry = true
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)

            let outputs = _ScrollableLayoutView<[ScrollableLifecycleRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            let materialization = try materializeDynamicItems(in: outputs)

            XCTAssertEqual(delegate.events, [])

            sizeAttr.setValue(ViewSize(width: 100, height: 40))
            _ = materialization.value
            XCTAssertEqual(delegate.events, [])

            sizeAttr.setValue(ViewSize(width: 100, height: 80))
            _ = materialization.value
            XCTAssertEqual(delegate.events, ["change"])
        }
    }

    func testScrollableLayoutViewFiltersRetainedUnusedOrdinaryPreferences() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
            let rows = (0..<4).map { ScrollableOrdinaryPreferenceRow(id: $0, recorder: recorder) }
            let viewAttr = graph.makeInput(
                value: _ScrollableLayoutView(data: rows, layout: VisibleCountScrollableLayout())
            )
            let sizeAttr = graph.makeInput(value: ViewSize(width: 100, height: 80))
            var inputs = makeViewInputs(graph: graph, size: sizeAttr)
            inputs.preferences.keys.add(ScrollableOrdinaryPreferenceKey.self)
            inputs.needsGeometry = true

            let outputs = _ScrollableLayoutView<[ScrollableOrdinaryPreferenceRow], VisibleCountScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            XCTAssertNil(outputs._layoutComputer.attribute)
            let ordinaryAttr = Attribute<String>(
                try XCTUnwrap(outputs.preferences.value(for: ScrollableOrdinaryPreferenceKey.self))
            )

            XCTAssertEqual(ordinaryAttr.value, "0,1,2,")

            sizeAttr.setValue(ViewSize(width: 100, height: 40))
            XCTAssertEqual(ordinaryAttr.value, "0,")

            sizeAttr.setValue(ViewSize(width: 100, height: 80))
            XCTAssertEqual(ordinaryAttr.value, "0,1,2,")
        }

        XCTAssertEqual(recorder.makeViewIDs.filter { $0 == 1 }.count, 1)
        XCTAssertEqual(recorder.makeViewIDs.filter { $0 == 2 }.count, 2)
    }

    func testScrollableItemGeometryUsesPlacementAnchorAndResolvedChildSize() throws {
        let graph = _AGGraph()
        let recorder = ScrollableLayoutRecorder()

        try _AGGraph.withCurrent(graph) {
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
            inputs.preferences.keys.add(ScrollableMaterializationPreferenceKey.self)

            let outputs = _ScrollableLayoutView<[FixedSizeRecordingRow], CenteredScrollableLayout>
                ._makeView(view: _GraphValue(_attribute: viewAttr), inputs: inputs)
            _ = try materializeDynamicItems(in: outputs)
            recorder.sampleGeometry(for: [0])
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
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
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

    @discardableResult
    private func materializeDynamicItems(
        in outputs: _ViewOutputs
    ) throws -> Attribute<ScrollableMaterializationPreferenceKey.Value> {
        let identifier = try XCTUnwrap(
            outputs.preferences.value(for: ScrollableMaterializationPreferenceKey.self)
        )
        let value = Attribute<ScrollableMaterializationPreferenceKey.Value>(identifier)
        _ = value.value
        return value
    }

    private func makeViewInputs(
        graph: _AGGraph,
        size: Attribute<ViewSize>,
        environment: Attribute<EnvironmentValues>? = nil,
        transform: Attribute<ViewTransform>? = nil
    ) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time()),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: environment ?? graph.makeInput(value: EnvironmentValues.tracking()),
                transaction: graph.makeInput(value: Transaction())
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: transform ?? graph.makeInput(value: ViewTransform.identity),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: size,
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
