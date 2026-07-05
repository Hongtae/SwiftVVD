import CoreGraphics
import XCTest
@testable import VUI

private final class ScrollViewInputRecorder {
    var sawScrollablePreferenceKey = false
    var sawUpdateScrollStateRequestKey = false
    var sawScrollPhasePreferenceKey = false
    var sawScrollGeometryPreferenceKey = false
    var scrollableAttribute: AGAttribute?
    var phaseStateAttribute: AGAttribute?
    var transform: Attribute<ViewTransform>?
    var safeAreaInsets: Attribute<SafeAreaInsets>?
}

private struct ScrollViewRecordingContent: View, _PrimitiveView {
    var recorder: ScrollViewInputRecorder
    var size = CGSize(width: 17, height: 23)

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewRecordingContent._makeView called outside an active _AGGraph context.")
        }

        let recorder = view._attribute.value.recorder
        recorder.sawScrollablePreferenceKey = inputs.preferences.keys.contains(ScrollablePreferenceKey.self)
        recorder.sawUpdateScrollStateRequestKey = inputs.preferences.keys.contains(UpdateScrollStateRequestKey.self)
        recorder.sawScrollPhasePreferenceKey = inputs.preferences.keys.contains(ScrollPhasePreferenceKey.self)
        recorder.sawScrollGeometryPreferenceKey = inputs.preferences.keys.contains(ScrollGeometryPreferenceKey.self)
        recorder.scrollableAttribute = inputs.scrollable.attribute?.identifier
        recorder.phaseStateAttribute = inputs.base.scrollPhaseState.attribute?.identifier
        recorder.transform = inputs.transform
        recorder.safeAreaInsets = inputs.safeAreaInsets.attribute

        let layout = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollViewChildScrollableContent: View, _PrimitiveView {
    var recorder: ScrollViewInputRecorder
    var child: ScrollViewChildCollectionScrollable

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewChildScrollableContent._makeView called outside an active _AGGraph context.")
        }

        let current = view._attribute.value
        current.recorder.sawScrollablePreferenceKey = inputs.preferences.keys.contains(ScrollablePreferenceKey.self)
        current.recorder.sawUpdateScrollStateRequestKey = inputs.preferences.keys.contains(UpdateScrollStateRequestKey.self)
        current.recorder.scrollableAttribute = inputs.scrollable.attribute?.identifier

        let child: Attribute<any Scrollable> = graph.makeRule {
            view._attribute.value.child as any Scrollable
        }
        let scrollables: Attribute<[any Scrollable]> = graph.makeRule(
            UnaryScrollablePreferenceProvider(scrollable: child)
        )
        var outputs = _ViewOutputs()
        outputs.preferences.append(ScrollablePreferenceKey.self, node: scrollables.identifier)
        return outputs
    }
}

private final class ScrollViewChildCollectionScrollable: ScrollableCollection {
    var scrolledCollectionIDs: [_ViewList_ID.Canonical] = []
    var scrolledCollectionAnchors: [UnitPoint?] = []
    var observedTransactions: [Transaction] = []

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        [_ViewList_ID(explicitID: AnyHashable("child")).canonicalID]
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
    }

    func subviewClosest(to rect: CGRect) -> ScrollableCollectionSubview? {
        nil
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        nil
    }

    static func hasMultipleViews(in axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        nil
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        false
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        nil
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        scrolledCollectionIDs.append(id)
        scrolledCollectionAnchors.append(anchor)
        observedTransactions.append(Transaction.current)
        return true
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        false
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

private final class ScrollViewBehaviorCollection: ScrollableCollection {
    var subviews: [ScrollableCollectionSubview]

    init(subviews: [ScrollableCollectionSubview]) {
        self.subviews = subviews
    }

    var visibleCollectionViewIDs: [_ViewList_ID.Canonical] {
        subviews.map { $0.id.canonicalID }
    }

    func forEachVisibleSubview(_ body: (ScrollableCollectionSubview, inout Bool) -> Void) {
        for subview in subviews {
            var stop = false
            body(subview, &stop)
            if stop { break }
        }
    }

    func subviewClosest(to rect: CGRect) -> ScrollableCollectionSubview? {
        subviews.min { lhs, rhs in
            lhs.frame.midpointDistance(to: rect) < rhs.frame.midpointDistance(to: rect)
        }
    }

    func nextVisibleCollectionViewID(
        towards point: UnitPoint,
        from id: _ViewList_ID.Canonical,
        border: CGSize,
        ignoring pinnedViews: PinnedScrollableViews
    ) -> _ViewList_ID.Canonical? {
        nil
    }

    static func hasMultipleViews(in axis: Axis) -> Bool {
        false
    }

    func firstCollectionViewIndex(of id: _ViewList_ID.Canonical) -> Int? {
        visibleCollectionViewIDs.firstIndex(of: id)
    }

    func applyCollectionViewIDs(
        from index: inout Int,
        to body: (_ViewList_ID.Canonical, inout Bool) -> Void
    ) -> Bool {
        let ids = visibleCollectionViewIDs
        guard index < ids.count else { return false }
        while index < ids.count {
            var stop = false
            body(ids[index], &stop)
            index += 1
            if stop { return false }
        }
        return true
    }

    func collectionViewID(for subgraph: AGSubgraph) -> _ViewList_ID.Canonical? {
        nil
    }

    func scroll(toCollectionViewID id: _ViewList_ID.Canonical, anchor: UnitPoint?) -> Bool {
        false
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        false
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

private extension CGRect {
    func midpointDistance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return (dx * dx + dy * dy).squareRoot()
    }
}

private func viewAlignedSubview(id: AnyHashable, frame: CGRect) -> ScrollableCollectionSubview {
    ScrollableCollectionSubview(
        id: _ViewList_ID(explicitID: id),
        frame: frame,
        frameInContent: frame,
        transform: ViewTransform()
    )
}

private final class ScrollViewTargetSubgraphRecorder {
    var itemSubgraphs: [Int: AGSubgraph] = [:]
}

private struct ScrollViewTargetRow: View, _PrimitiveView {
    var id: Int
    var subgraphRecorder: ScrollViewTargetSubgraphRecorder?

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollViewTargetRow._makeView called outside an active _AGGraph context.")
        }
        let row = view._attribute.value
        if let subgraph = AGSubgraph.current {
            row.subgraphRecorder?.itemSubgraphs[row.id] = subgraph
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 40, height: 20))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollViewTargetLayout: _ScrollableLayout {
    func update(state: inout Void, proxy: inout _ScrollableLayoutProxy) {
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
        proxy.validRect = CGRect(origin: .zero, size: proxy.contentSize)
    }
}

private struct DynamicScrollTargetLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout Void
    ) -> CGSize {
        CGSize(
            width: proposal.width ?? 100,
            height: subviews.isEmpty ? 0 : CGFloat((subviews.count - 1) * 100 + 20)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout Void
    ) {
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index * 100)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: 40, height: 20)
            )
        }
    }
}

private final class ScrollViewParentScrollable: Scrollable {
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

private struct ScrollEnvironmentProbeTransform: ScrollEnvironmentTransform {
    var seed: UInt32

    func update(properties: inout ScrollEnvironmentProperties) {
        properties.indicatorFlashSeed = seed
        properties.edgeEffectHidden[.bottom] = true
    }
}

private struct RecordingScrollTargetBehavior: ScrollTargetBehavior {
    var token: Int

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
    }
}

private final class ScrollBehaviorEnvironmentRecorder {
    var behaviors: [ResolvedScrollBehavior?] = []
    var environment: Attribute<EnvironmentValues>?
}

private struct ScrollBehaviorEnvironmentContent: View, _PrimitiveView {
    var recorder: ScrollBehaviorEnvironmentRecorder
    var size = CGSize(width: 11, height: 13)

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollBehaviorEnvironmentContent._makeView called outside an active _AGGraph context.")
        }

        let current = view._attribute.value
        let environment = inputs.base.cachedEnvironment.value.environment
        current.recorder.environment = environment
        current.recorder.behaviors.append(environment.value.scrollEnvironmentStorage.properties.scrollBehavior)

        let layout = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ScrollBehaviorRoleContent: View, _PrimitiveView {
    var recorder: ScrollBehaviorEnvironmentRecorder
    var rows: [ScrollViewTargetRow]

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollBehaviorRoleContent._makeView called outside an active _AGGraph context.")
        }

        let current = view._attribute.value
        let environment = inputs.base.cachedEnvironment.value.environment
        current.recorder.environment = environment
        current.recorder.behaviors.append(environment.value.scrollEnvironmentStorage.properties.scrollBehavior)

        let targetContent = _ScrollableLayoutView(
            data: current.rows,
            layout: ScrollViewTargetLayout()
        )
        .scrollTargetLayout()
        let targetAttribute = graph.makeInput(value: targetContent)
        return type(of: targetContent)._makeView(
            view: _GraphValue(_attribute: targetAttribute),
            inputs: inputs
        )
    }
}

final class ScrollViewSurfaceTests: XCTestCase {
    private let recordingContentSize = CGSize(width: 17, height: 23)

    private func bytes<T>(of value: T) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    private func optionalCGFloat(_ value: Any) -> CGFloat? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else {
                return nil
            }
            return child.value as? CGFloat
        }
        return value as? CGFloat
    }

    private func optionalInsetValues(_ value: Any) -> [String: CGFloat?] {
        var result: [String: CGFloat?] = [:]
        for child in Mirror(reflecting: value).children {
            guard let label = child.label else {
                continue
            }
            result.updateValue(optionalCGFloat(child.value), forKey: label)
        }
        return result
    }

    func testEdgeInsetsInsetByRectangleCornerInsetsUsesAdjacentCornerMaxima() {
        let base = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
        let corners = RectangleCornerInsets(
            topLeading: CGSize(width: 1, height: 2),
            topTrailing: CGSize(width: 3, height: 4),
            bottomLeading: CGSize(width: 5, height: 6),
            bottomTrailing: CGSize(width: 7, height: 8)
        )

        XCTAssertEqual(
            base.inset(by: corners),
            EdgeInsets(top: 14, leading: 25, bottom: 38, trailing: 47)
        )
        XCTAssertEqual(
            base.inset(by: corners, edges: .vertical),
            EdgeInsets(top: 14, leading: 20, bottom: 38, trailing: 40)
        )
        XCTAssertEqual(
            base.inset(by: corners, edges: .horizontal),
            EdgeInsets(top: 10, leading: 25, bottom: 30, trailing: 47)
        )
        XCTAssertEqual(base.inset(by: corners, edges: []), base)

        let negativeBase = EdgeInsets(top: -10, leading: -20, bottom: -30, trailing: -40)
        let negativeCorners = RectangleCornerInsets(
            topLeading: CGSize(width: -1, height: -2),
            topTrailing: CGSize(width: -3, height: -4),
            bottomLeading: CGSize(width: -5, height: -6),
            bottomTrailing: CGSize(width: -7, height: -8)
        )
        XCTAssertEqual(
            negativeBase.inset(by: negativeCorners),
            EdgeInsets(top: -12, leading: -21, bottom: -36, trailing: -43)
        )
    }

    func testAbsoluteRectangleCornerInsetsConvertsLeadingCornersByLayoutDirection() {
        let corners = RectangleCornerInsets(
            topLeading: CGSize(width: 1, height: 2),
            topTrailing: CGSize(width: 3, height: 4),
            bottomLeading: CGSize(width: 5, height: 6),
            bottomTrailing: CGSize(width: 7, height: 8)
        )

        XCTAssertEqual(
            AbsoluteRectangleCornerInsets(corners, layoutDirection: .leftToRight),
            AbsoluteRectangleCornerInsets(
                topLeft: corners.topLeading,
                topRight: corners.topTrailing,
                bottomLeft: corners.bottomLeading,
                bottomRight: corners.bottomTrailing
            )
        )
        XCTAssertEqual(
            AbsoluteRectangleCornerInsets(corners, layoutDirection: .rightToLeft),
            AbsoluteRectangleCornerInsets(
                topLeft: corners.topTrailing,
                topRight: corners.topLeading,
                bottomLeft: corners.bottomTrailing,
                bottomRight: corners.bottomLeading
            )
        )
    }

    func testScrollViewStoresContentAndConfiguration() {
        var view = ScrollView(.horizontal, showsIndicators: false) {
            Text("row")
        }

        XCTAssertEqual(Mirror(reflecting: view).children.map(\.label), ["content", "configuration"])
        XCTAssertEqual(Mirror(reflecting: view.configuration).children.map(\.label), [
            "axes",
            "showsIndicators",
            "contentInsets",
            "isScrollEnabled",
            "automaticallyAdjustsContentInsets",
            "interactionActivityTag",
        ])
        XCTAssertEqual(view.axes, .horizontal)
        XCTAssertFalse(view.showsIndicators)
        XCTAssertEqual(view._contentInsets, EdgeInsets())
        XCTAssertTrue(view._automaticallyAdjustsContentInsets)

        view.axes = [.horizontal, .vertical]
        view.showsIndicators = true
        view._contentInsets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        view._automaticallyAdjustsContentInsets = false

        XCTAssertEqual(view.configuration.axes, [.horizontal, .vertical])
        XCTAssertTrue(view.configuration.showsIndicators)
        XCTAssertEqual(
            view.configuration.contentInsets,
            EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        )
        XCTAssertNil(view.configuration.isScrollEnabled)
        XCTAssertFalse(view.configuration.automaticallyAdjustsContentInsets)
        XCTAssertNil(view.configuration.interactionActivityTag)
    }

    func testScrollViewBodyRoutesThroughSystemContainer() {
        let view = ScrollView(.vertical, showsIndicators: true) {
            Text("body")
        }
        let body = view.body

        XCTAssertTrue(String(reflecting: type(of: body)).contains("SystemScrollViewContainer"))
        XCTAssertEqual(Mirror(reflecting: body).children.map(\.label), ["configuration", "content"])
        XCTAssertEqual(body.configuration.axes, .vertical)
        XCTAssertTrue(body.configuration.showsIndicators)

        let containerBody = body.body
        let containerBodyType = String(reflecting: type(of: containerBody))
        XCTAssertTrue(containerBodyType.contains("_UnaryViewAdaptor"))
        XCTAssertTrue(containerBodyType.contains("SystemScrollView"))
        XCTAssertTrue(containerBodyType.contains("StyleContextWriter"))
        XCTAssertTrue(containerBodyType.contains("ScrollViewStyleContext"))
        XCTAssertTrue(containerBodyType.contains("ResetScrollInputsModifier"))
        XCTAssertTrue(containerBodyType.contains("ResetContentMarginModifier"))
        XCTAssertTrue(containerBodyType.contains("EnvironmentAxesModifier"))
        XCTAssertTrue(containerBodyType.contains("ResolvedScrollBehaviorModifier"))
        XCTAssertTrue(containerBodyType.contains("ScrollPhaseStateConfigurationModifier"))
        XCTAssertEqual(Mirror(reflecting: containerBody).children.map(\.label), ["content"])
    }

    func testScrollTargetBehaviorModifierSurface() {
        let pagingView = Text("x").scrollTargetBehavior(.paging)
        let pagingType = String(reflecting: type(of: pagingView))
        XCTAssertTrue(pagingType.contains("ScrollBehaviorModifier"))
        XCTAssertTrue(pagingType.contains("PagingScrollTargetBehavior"))
        XCTAssertEqual(Mirror(reflecting: pagingView).children.map(\.label), ["content", "modifier"])

        let pagingModifier = Mirror(reflecting: pagingView).descendant("modifier")!
        XCTAssertEqual(Mirror(reflecting: pagingModifier).children.map(\.label), ["behavior"])

        let alignedView = Text("x").scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByFew))
        let alignedType = String(reflecting: type(of: alignedView))
        XCTAssertTrue(alignedType.contains("ScrollBehaviorModifier"))
        XCTAssertTrue(alignedType.contains("ViewAlignedScrollTargetBehavior"))
        XCTAssertEqual(Mirror(reflecting: alignedView).children.map(\.label), ["content", "modifier"])

        let alignedModifier = Mirror(reflecting: alignedView).descendant("modifier")!
        XCTAssertEqual(Mirror(reflecting: alignedModifier).children.map(\.label), ["behavior"])
    }

    func testScrollTargetLayoutModifierSurface() {
        let enabled = Text("x").scrollTargetLayout()
        let enabledType = String(reflecting: type(of: enabled))
        XCTAssertTrue(enabledType.contains("ScrollTargetModifier"))
        XCTAssertEqual(Mirror(reflecting: enabled).children.map(\.label), ["content", "modifier"])

        let enabledModifier = Mirror(reflecting: enabled).descendant("modifier")!
        XCTAssertEqual(Mirror(reflecting: enabledModifier).children.map(\.label), ["role"])
        let enabledRole = Mirror(reflecting: enabledModifier).descendant("role")!
        XCTAssertEqual(Mirror(reflecting: enabledRole).children.map(\.label), ["some"])
        XCTAssertTrue(String(reflecting: enabledRole).contains("ScrollTargetRole.Role.container"))

        let disabled = Text("x").scrollTargetLayout(isEnabled: false)
        let disabledType = String(reflecting: type(of: disabled))
        XCTAssertTrue(disabledType.contains("ScrollTargetModifier"))
        XCTAssertEqual(Mirror(reflecting: disabled).children.map(\.label), ["content", "modifier"])

        let disabledModifier = Mirror(reflecting: disabled).descendant("modifier")!
        XCTAssertEqual(Mirror(reflecting: disabledModifier).children.map(\.label), ["role"])
        let disabledRole = Mirror(reflecting: disabledModifier).descendant("role")!
        XCTAssertTrue(Mirror(reflecting: disabledRole).children.isEmpty)
        XCTAssertEqual(String(reflecting: disabledRole), "nil")
    }

    func testScrollableLayoutPublishesScrollTargetRoleContentKey() {
        let host = GraphHost()
        var layoutsID: AGAttribute!

        host.data.withCurrent {
            let graph = host.data.graph
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollTargetRole.ContentKey.self)
            let rows = (0..<2).map { ScrollViewTargetRow(id: $0) }
            let view = _ScrollableLayoutView(data: rows, layout: ScrollViewTargetLayout())
                .scrollTargetLayout()
            let viewAttribute = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            )

            guard let outputLayoutsID = outputs.preferences.value(for: ScrollTargetRole.ContentKey.self) else {
                XCTFail("expected ScrollTargetRole.ContentKey output")
                return
            }
            layoutsID = outputLayoutsID

            XCTAssertTrue(Attribute<ScrollTargetRole.ContentKey.Value>(outputLayoutsID).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            let layouts = Attribute<ScrollTargetRole.ContentKey.Value>(layoutsID).value
            XCTAssertEqual(layouts[.container]?.count, 1)
            XCTAssertNil(layouts[.target])
        }
    }

    func testDisabledScrollableLayoutPublishesEmptyScrollTargetRoleContentKey() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollTargetRole.ContentKey.self)
            let rows = (0..<2).map { ScrollViewTargetRow(id: $0) }
            let view = _ScrollableLayoutView(data: rows, layout: ScrollViewTargetLayout())
                .scrollTargetLayout(isEnabled: false)
            let viewAttribute = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            )

            guard let layoutsID = outputs.preferences.value(for: ScrollTargetRole.ContentKey.self) else {
                XCTFail("expected ScrollTargetRole.ContentKey output")
                return
            }

            let layouts = Attribute<ScrollTargetRole.ContentKey.Value>(layoutsID).value
            XCTAssertTrue(layouts.isEmpty)
        }
    }

    func testScrollTargetBehaviorModifierPublishesResolvedBehaviorEnvironment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let recorder = ScrollBehaviorEnvironmentRecorder()
            let view = ScrollBehaviorEnvironmentContent(recorder: recorder)
                .scrollTargetBehavior(RecordingScrollTargetBehavior(token: 11))
            let viewAttribute = graph.makeInput(value: view)

            _ = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: makeViewInputs(graph: graph)
            )

            guard let recorded = recorder.behaviors.last else {
                XCTFail("expected scroll behavior environment to be read")
                return
            }
            guard let behavior = recorded else {
                XCTFail("expected resolved scroll behavior")
                return
            }

            XCTAssertTrue(behavior.base is RecordingScrollTargetBehavior)
            XCTAssertEqual((behavior.base as? RecordingScrollTargetBehavior)?.token, 11)
            XCTAssertEqual(behavior.baseSeed, 0)
            XCTAssertNil(behavior.axes)
            XCTAssertFalse(behavior._collections.isInvalid)
            XCTAssertFalse(behavior._targets.isInvalid)

            let environment = recorder.environment
            viewAttribute.setValue(
                ScrollBehaviorEnvironmentContent(recorder: recorder)
                    .scrollTargetBehavior(RecordingScrollTargetBehavior(token: 12))
            )

            let updated = environment?.value.scrollEnvironmentStorage.properties.scrollBehavior
            XCTAssertEqual((updated?.base as? RecordingScrollTargetBehavior)?.token, 12)
            XCTAssertEqual(updated?.baseSeed, 1)
        }
    }

    func testScrollTargetBehaviorModifierFiltersRoleBackedCollections() {
        let host = GraphHost()
        var behavior: ResolvedScrollBehavior!

        host.data.withCurrent {
            let graph = host.data.graph
            let recorder = ScrollBehaviorEnvironmentRecorder()
            let rows = (0..<2).map { ScrollViewTargetRow(id: $0) }
            let view = ScrollBehaviorRoleContent(recorder: recorder, rows: rows)
                .scrollTargetBehavior(RecordingScrollTargetBehavior(token: 27))
            let viewAttribute = graph.makeInput(value: view)

            _ = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: makeViewInputs(graph: graph)
            )

            guard let recorded = recorder.behaviors.last, let resolved = recorded else {
                XCTFail("expected resolved scroll behavior")
                return
            }
            behavior = resolved

            XCTAssertTrue(resolved._collections.toStrong().value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            let collections = behavior._collections.toStrong().value
            let targets = behavior._targets.toStrong().value
            XCTAssertEqual(collections.count, 1)
            XCTAssertTrue(String(reflecting: type(of: collections[0])).contains("ScrollableLayoutCollection"))
            XCTAssertTrue(targets.isEmpty)
        }
    }

    func testDynamicLayoutPublishesScrollTargetRoleContentKey() {
        let host = GraphHost()
        var layoutsID: AGAttribute!

        host.data.withCurrent {
            let graph = host.data.graph
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollTargetRole.ContentKey.self)
            let view = AnyLayout(DynamicScrollTargetLayout()) {
                ForEach(Array(0..<2), id: \.self) { row in
                    ScrollViewTargetRow(id: row)
                }
            }
            .scrollTargetLayout()
            let viewAttribute = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            )

            guard let outputLayoutsID = outputs.preferences.value(for: ScrollTargetRole.ContentKey.self) else {
                XCTFail("expected ScrollTargetRole.ContentKey output")
                return
            }
            layoutsID = outputLayoutsID

            XCTAssertTrue(Attribute<ScrollTargetRole.ContentKey.Value>(outputLayoutsID).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            let layouts = Attribute<ScrollTargetRole.ContentKey.Value>(layoutsID).value
            XCTAssertEqual(layouts[.container]?.count, 1)
            XCTAssertTrue(String(reflecting: type(of: layouts[.container]![0])).contains("DynamicLayoutScrollable"))
            XCTAssertNil(layouts[.target])
        }
    }

    func testDynamicLayoutScrollableUsesAllGeometryForCollectionTarget() throws {
        let host = GraphHost()
        let parent = ScrollViewParentScrollable()
        let recorder = ScrollViewTargetSubgraphRecorder()
        var scrollablesID: AGAttribute!

        try host.data.withCurrent {
            let graph = host.data.graph
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollablePreferenceKey.self)
            let view = AnyLayout(DynamicScrollTargetLayout()) {
                ForEach(Array(0..<4), id: \.self) { row in
                    ScrollViewTargetRow(id: row, subgraphRecorder: recorder)
                }
            }
            let viewAttribute = graph.makeInput(value: view)
            let parentAttr: Attribute<any Scrollable> = graph.makeInput(value: parent as any Scrollable)
            var contentTransform = ViewTransform.identity
            contentTransform.appendTranslation(CGSize(width: 400, height: 400))
            contentTransform.appendSizedSpace(
                id: ScrollCoordinateSpace.content.id,
                size: CGSize(width: 100, height: 400)
            )
            contentTransform.appendTranslation(CGSize(width: -12, height: -18))
            var inputs = makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            inputs.scrollable = OptionalAttribute(parentAttr)
            inputs.transform = graph.makeInput(value: contentTransform)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 100, height: 80)))

            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: inputs
            )
            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr

            XCTAssertTrue(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let collection = try XCTUnwrap(scrollables.compactMap { $0 as? any ScrollableCollection }.first)
            let targetID = _ViewList_ID(explicitID: AnyHashable(3)).canonicalID
            let itemSubgraph = try XCTUnwrap(recorder.itemSubgraphs[2])

            XCTAssertEqual(collection.firstCollectionViewIndex(of: targetID), 3)
            XCTAssertEqual(
                collection.collectionViewID(for: itemSubgraph),
                _ViewList_ID(explicitID: AnyHashable(2)).canonicalID
            )
            XCTAssertNil(collection.collectionViewID(for: AGSubgraph()))
            XCTAssertTrue(collection.scroll(toCollectionViewID: targetID, anchor: .bottom))
            XCTAssertEqual(parent.contentTargets.count, 1)

            let geometry = ScrollGeometry(
                contentOffset: .zero,
                contentSize: CGSize(width: 100, height: 400),
                containerSize: CGSize(width: 100, height: 80)
            )
            let target = try XCTUnwrap(parent.contentTargets[0](geometry, .leftToRight))
            XCTAssertEqual(target.rect, CGRect(x: -12, y: 282, width: 40, height: 20))
            XCTAssertEqual(target.anchor, .bottom)
        }
    }

    func testScrollViewResolvedBehaviorModifierClearsBehaviorForEmptyAxes() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let recorder = ScrollBehaviorEnvironmentRecorder()
            let view = ScrollView(Axis.Set()) {
                ScrollBehaviorEnvironmentContent(recorder: recorder)
            }
            .scrollTargetBehavior(RecordingScrollTargetBehavior(token: 19))
            let viewAttribute = graph.makeInput(value: view)

            _ = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttribute),
                inputs: makeViewInputs(graph: graph)
            )

            guard let recorded = recorder.behaviors.last else {
                XCTFail("expected scroll view content environment to be read")
                return
            }
            XCTAssertNil(recorded)
        }
    }

    func testScrollTargetBehaviorStorageShapes() {
        XCTAssertEqual(MemoryLayout<PagingScrollTargetBehavior>.size, 0)
        XCTAssertEqual(MemoryLayout<PagingScrollTargetBehavior>.stride, 1)
        XCTAssertEqual(Mirror(reflecting: PagingScrollTargetBehavior()).children.map(\.label), [])

        XCTAssertEqual(MemoryLayout<ViewAlignedScrollTargetBehavior.LimitBehavior>.size, 1)
        XCTAssertEqual(MemoryLayout<ViewAlignedScrollTargetBehavior.LimitBehavior>.stride, 1)
        XCTAssertEqual(bytes(of: ViewAlignedScrollTargetBehavior.LimitBehavior.automatic), [0])
        XCTAssertEqual(bytes(of: ViewAlignedScrollTargetBehavior.LimitBehavior.always), [1])
        XCTAssertEqual(bytes(of: ViewAlignedScrollTargetBehavior.LimitBehavior.alwaysByFew), [2])
        XCTAssertEqual(bytes(of: ViewAlignedScrollTargetBehavior.LimitBehavior.alwaysByOne), [1])
        XCTAssertEqual(bytes(of: ViewAlignedScrollTargetBehavior.LimitBehavior.never), [3])

        let viewAligned = ViewAlignedScrollTargetBehavior(limitBehavior: .always)
        XCTAssertEqual(Mirror(reflecting: viewAligned).children.map(\.label), ["limitBehavior", "anchor"])
        XCTAssertEqual(bytes(of: Mirror(reflecting: viewAligned).descendant("limitBehavior") as! ViewAlignedScrollTargetBehavior.LimitBehavior), [1])

        let anchored = ViewAlignedScrollTargetBehavior(anchor: .center)
        XCTAssertEqual(Mirror(reflecting: anchored).children.map(\.label), ["limitBehavior", "anchor"])
        XCTAssertEqual(bytes(of: Mirror(reflecting: anchored).descendant("limitBehavior") as! ViewAlignedScrollTargetBehavior.LimitBehavior), [0])

        let properties = ScrollTargetBehaviorProperties()
        XCTAssertEqual(Mirror(reflecting: properties).children.map(\.label), [
            "_limitsScrolls",
            "_bouncesScrolls",
            "_deceleratesLinearly",
        ])
        XCTAssertFalse(Mirror(reflecting: properties).descendant("_limitsScrolls") as! Bool)
        XCTAssertFalse(Mirror(reflecting: properties).descendant("_bouncesScrolls") as! Bool)
        XCTAssertFalse(Mirror(reflecting: properties).descendant("_deceleratesLinearly") as! Bool)

        let boxed = AnyScrollTargetBehavior(PagingScrollTargetBehavior())
        XCTAssertEqual(Mirror(reflecting: boxed).children.map(\.label), ["base"])
    }

    func testPagingScrollTargetBehaviorUpdateTargetSamples() {
        func run(
            targetX: CGFloat,
            targetY: CGFloat = 0,
            originalX: CGFloat = 0,
            originalY: CGFloat = 0,
            velocity: CGVector = .zero,
            axes: Axis.Set = [.horizontal],
            layoutDirection: LayoutDirection = .leftToRight,
            contentSize: CGSize = CGSize(width: 1_000, height: 1_000),
            containerSize: CGSize = CGSize(width: 200, height: 200)
        ) -> ScrollTarget {
            var environment = EnvironmentValues()
            environment.layoutDirection = layoutDirection
            let geometry = ScrollGeometry(
                contentOffset: .zero,
                contentSize: contentSize,
                contentInsets: EdgeInsets(),
                containerSize: containerSize
            )
            var target = ScrollTarget(
                rect: CGRect(origin: CGPoint(x: targetX, y: targetY), size: containerSize)
            )
            let context = ScrollTargetBehaviorContext(
                originalTarget: ScrollTarget(
                    rect: CGRect(origin: CGPoint(x: originalX, y: originalY), size: containerSize)
                ),
                velocity: velocity,
                geometry: geometry,
                axes: axes,
                environment: environment
            )
            PagingScrollTargetBehavior().updateTarget(&target, context: context)
            return target
        }

        XCTAssertEqual(run(targetX: 99).rect.origin.x, 0)
        XCTAssertEqual(run(targetX: 100).rect.origin.x, 200)
        XCTAssertEqual(run(targetX: 300).rect.origin.x, 400)
        XCTAssertEqual(run(targetX: -1).rect.origin.x, -1)
        XCTAssertEqual(run(targetX: 800).rect.origin.x, 800)
        XCTAssertEqual(run(targetX: 801).rect.origin.x, 801)

        XCTAssertEqual(run(targetX: 80, velocity: CGVector(dx: 1, dy: 0)).rect.origin.x, 200)
        XCTAssertEqual(run(targetX: 80, velocity: CGVector(dx: -1, dy: 0)).rect.origin.x, 80)
        XCTAssertEqual(run(targetX: 220, originalX: 200, velocity: CGVector(dx: -1, dy: 0)).rect.origin.x, 0)
        XCTAssertEqual(run(targetX: 220, originalX: 200, velocity: CGVector(dx: 1, dy: 0)).rect.origin.x, 400)

        XCTAssertEqual(
            run(targetX: 80, velocity: CGVector(dx: -1, dy: 0), layoutDirection: .rightToLeft).rect.origin.x,
            200
        )
        XCTAssertEqual(
            run(targetX: 80, velocity: CGVector(dx: 1, dy: 0), layoutDirection: .rightToLeft).rect.origin.x,
            80
        )

        let vertical = run(
            targetX: 260,
            targetY: 300,
            axes: [.horizontal, .vertical]
        )
        XCTAssertEqual(vertical.rect.origin, CGPoint(x: 200, y: 400))
    }

    func testViewAlignedScrollTargetBehaviorNoLayoutDoesNotMutateTarget() {
        func run(
            behavior: ViewAlignedScrollTargetBehavior = .viewAligned,
            targetRect: CGRect,
            axes: Axis.Set = [.vertical]
        ) -> ScrollTarget {
            let geometry = ScrollGeometry(
                contentOffset: .zero,
                contentSize: CGSize(width: 1_000, height: 1_000),
                contentInsets: EdgeInsets(),
                containerSize: CGSize(width: 200, height: 200)
            )
            var target = ScrollTarget(rect: targetRect)
            let context = ScrollTargetBehaviorContext(
                originalTarget: ScrollTarget(rect: targetRect),
                velocity: .zero,
                geometry: geometry,
                axes: axes
            )
            behavior.updateTarget(&target, context: context)
            return target
        }

        let vertical = CGRect(x: 0, y: 123, width: 200, height: 200)
        XCTAssertEqual(run(targetRect: vertical).rect, vertical)

        let horizontal = CGRect(x: 123, y: 0, width: 200, height: 200)
        XCTAssertEqual(run(targetRect: horizontal, axes: [.horizontal]).rect, horizontal)

        XCTAssertEqual(
            run(behavior: .viewAligned(anchor: .center), targetRect: vertical).rect,
            vertical
        )
    }

    func testViewAlignedScrollTargetBehaviorUsesVisibleCollectionCandidatesAndAnchor() {
        let subviews = [
            viewAlignedSubview(id: "first", frame: CGRect(x: 0, y: 0, width: 80, height: 40)),
            viewAlignedSubview(id: "target", frame: CGRect(x: 0, y: 120, width: 80, height: 40)),
            viewAlignedSubview(id: "third", frame: CGRect(x: 0, y: 260, width: 80, height: 40)),
        ]
        let collection = ScrollViewBehaviorCollection(subviews: subviews)
        let geometry = ScrollGeometry(
            contentOffset: .zero,
            contentSize: CGSize(width: 100, height: 400),
            contentInsets: EdgeInsets(),
            containerSize: CGSize(width: 100, height: 100)
        )
        var target = ScrollTarget(rect: CGRect(x: 0, y: 135, width: 100, height: 100))
        let context = ScrollTargetBehaviorContext(
            originalTarget: target,
            velocity: .zero,
            geometry: geometry,
            axes: .vertical,
            collections: [collection]
        )

        ViewAlignedScrollTargetBehavior(anchor: .center).updateTarget(&target, context: context)

        XCTAssertEqual(target.rect.origin, CGPoint(x: 0, y: 150))
        XCTAssertEqual(target.rect.size, CGSize(width: 100, height: 100))
    }

    func testViewAlignedScrollTargetBehaviorFiltersOversizedVisibleCandidates() {
        let subviews = [
            viewAlignedSubview(id: "oversized", frame: CGRect(x: 0, y: 150, width: 80, height: 120)),
            viewAlignedSubview(id: "target", frame: CGRect(x: 0, y: 170, width: 80, height: 40)),
        ]
        let collection = ScrollViewBehaviorCollection(subviews: subviews)
        let geometry = ScrollGeometry(
            contentOffset: .zero,
            contentSize: CGSize(width: 100, height: 400),
            contentInsets: EdgeInsets(),
            containerSize: CGSize(width: 100, height: 100)
        )
        var target = ScrollTarget(rect: CGRect(x: 0, y: 150, width: 100, height: 100))
        let context = ScrollTargetBehaviorContext(
            originalTarget: target,
            velocity: .zero,
            geometry: geometry,
            axes: .vertical,
            collections: [collection]
        )

        ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context)

        XCTAssertEqual(target.rect.origin.y, 170)
    }

    func testScrollEnvironmentSupportStorageShapes() {
        XCTAssertEqual(MemoryLayout<ScrollIndicatorVisibility>.size, 1)
        XCTAssertEqual(MemoryLayout<ScrollIndicatorVisibility>.stride, 1)
        XCTAssertEqual(Mirror(reflecting: ScrollIndicatorVisibility.automatic).children.map(\.label), ["role"])
        XCTAssertEqual(bytes(of: ScrollIndicatorVisibility.automatic), [0])
        XCTAssertEqual(bytes(of: ScrollIndicatorVisibility.visible), [1])
        XCTAssertEqual(bytes(of: ScrollIndicatorVisibility.hidden), [2])
        XCTAssertEqual(bytes(of: ScrollIndicatorVisibility.never), [3])

        XCTAssertEqual(MemoryLayout<ScrollEdgeEffectStyle>.size, 1)
        XCTAssertEqual(MemoryLayout<ScrollEdgeEffectStyle>.stride, 1)
        XCTAssertEqual(Mirror(reflecting: ScrollEdgeEffectStyle.automatic).children.map(\.label), ["role"])
        XCTAssertEqual(bytes(of: ScrollEdgeEffectStyle.automatic), [0])
        XCTAssertEqual(bytes(of: ScrollEdgeEffectStyle.hard), [1])
        XCTAssertEqual(bytes(of: ScrollEdgeEffectStyle.soft), [2])

        XCTAssertEqual(MemoryLayout<ScrollDismissesKeyboardMode>.size, 1)
        XCTAssertEqual(MemoryLayout<ScrollDismissesKeyboardMode>.stride, 1)
        XCTAssertEqual(Mirror(reflecting: ScrollDismissesKeyboardMode.automatic).children.map(\.label), ["role"])
        XCTAssertEqual(bytes(of: ScrollDismissesKeyboardMode.automatic), [0])
        XCTAssertEqual(bytes(of: ScrollDismissesKeyboardMode.immediately), [1])
        XCTAssertEqual(bytes(of: ScrollDismissesKeyboardMode.interactively), [2])
        XCTAssertEqual(bytes(of: ScrollDismissesKeyboardMode.never), [3])

        XCTAssertEqual(MemoryLayout<ScrollBounceBehavior>.size, 1)
        XCTAssertEqual(MemoryLayout<ScrollBounceBehavior>.stride, 1)
        XCTAssertEqual(Mirror(reflecting: ScrollBounceBehavior.automatic).children.map(\.label), ["role"])
        XCTAssertEqual(bytes(of: ScrollBounceBehavior.automatic), [0])
        XCTAssertEqual(bytes(of: ScrollBounceBehavior.always), [1])
        XCTAssertEqual(bytes(of: ScrollBounceBehavior.basedOnSize), [2])

        XCTAssertEqual(bytes(of: ScrollClipDisabledBehavior.automatic), [0])
        XCTAssertEqual(bytes(of: ScrollClipDisabledBehavior.expandsVisibleRegion), [1])
        XCTAssertEqual(Mirror(reflecting: ScrollIndicatorConfiguration()).children.map(\.label), [
            "visibility",
            "options",
            "style",
        ])
        XCTAssertEqual(Mirror(reflecting: ScrollIndicatorStyle.automatic).children.map(\.label), ["value"])
    }

    func testScrollEnvironmentPropertiesStorageAndTransform() {
        var properties = ScrollEnvironmentProperties()
        XCTAssertEqual(Mirror(reflecting: properties).children.map(\.label), [
            "isEnabled",
            "isClippingEnabled",
            "clipDisabledBehavior",
            "dismissKeyboardMode",
            "scrollBehavior",
            "decelerationRate",
            "layoutDirection",
            "options",
            "indicatorFlashSeed",
            "accessoryEdge",
            "accessoryVisibility",
            "edgeEffectStyle",
            "edgeEffectHidden",
            "edgeEffectDisabled",
            "verticalIndicator",
            "verticalBounceBehavior",
            "horizontalIndicator",
            "horizontalBounceBehavior",
            "allowedAutoScrollAxes",
            "autoScrollAllowsPaginated",
            "isContainedInPlatter",
            "crownScrollingAxis",
            "handGestureShortcutPaginationDirection",
            "navigationBarScrollMetrics",
            "gradientMaskLengths",
            "gradientMaskEdgeInsets",
        ])

        properties.layoutDirection = .leftToRight
        properties.edgeEffectStyle[.top] = .hard
        properties.gradientMaskLengths = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)

        let storage = ScrollEnvironmentStorage(
            properties,
            transform: ScrollEnvironmentProbeTransform(seed: 17)
        )
        XCTAssertEqual(Mirror(reflecting: storage).children.map(\.label), [
            "_baseProperties",
            "_transform",
            "_$observationRegistrar",
        ])

        let transformed = storage.properties
        XCTAssertEqual(transformed.indicatorFlashSeed, 17)
        XCTAssertEqual(transformed.edgeEffectStyle[.top], .hard)
        XCTAssertEqual(transformed.edgeEffectHidden[.bottom], true)
        XCTAssertEqual(
            transformed.gradientMaskLengths,
            EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        )

        var values = EnvironmentValues()
        values.layoutDirection = .rightToLeft
        values.scrollEnvironmentStorage = storage

        let inherited = ScrollEnvironmentProperties(environment: values)
        XCTAssertEqual(inherited.layoutDirection, .rightToLeft)
        XCTAssertEqual(inherited.indicatorFlashSeed, 17)
        XCTAssertEqual(inherited.edgeEffectStyle[.top], .hard)
        XCTAssertEqual(inherited.edgeEffectHidden[.bottom], true)
    }

    func testScrollTargetBehaviorContextStorageAndProjection() {
        var environment = EnvironmentValues()
        environment.layoutDirection = .rightToLeft
        let target = ScrollTarget(
            rect: CGRect(x: 7, y: 11, width: 13, height: 17),
            anchor: .bottomTrailing
        )
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 3, y: 5),
            contentSize: CGSize(width: 101, height: 203),
            contentInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
            containerSize: CGSize(width: 29, height: 31)
        )
        let context = ScrollTargetBehaviorContext(
            originalTarget: target,
            velocity: CGVector(dx: 19, dy: 23),
            geometry: geometry,
            axes: [.horizontal, .vertical],
            environment: environment
        )

        XCTAssertEqual(Mirror(reflecting: context).children.map(\.label), [
            "_originalTarget",
            "_velocity",
            "geometry",
            "_axes",
            "decelerationRate",
            "collections",
            "targets",
            "environment",
        ])
        XCTAssertEqual(context.originalTarget, target)
        XCTAssertEqual(context.velocity, CGVector(dx: 19, dy: 23))
        XCTAssertEqual(context.contentSize, CGSize(width: 101, height: 203))
        XCTAssertEqual(context.containerSize, CGSize(width: 29, height: 31))
        XCTAssertEqual(context.axes, [.horizontal, .vertical])
        XCTAssertEqual(context.contentInsets, EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        XCTAssertEqual(context.contentOffset, CGPoint(x: 3, y: 5))
        XCTAssertEqual(context.viewportSize, CGSize(width: 29, height: 31))
        XCTAssertEqual(context.layoutDirection, .rightToLeft)
    }

    func testContentMarginPlacementSurfaceUsesRoleByte() {
        XCTAssertEqual(MemoryLayout<ContentMarginPlacement>.size, 1)
        XCTAssertEqual(MemoryLayout<ContentMarginPlacement>.stride, 1)
        XCTAssertEqual(MemoryLayout<ContentMarginPlacement>.alignment, 1)
        XCTAssertEqual(Mirror(reflecting: ContentMarginPlacement.automatic).children.map(\.label), ["role"])

        XCTAssertEqual(bytes(of: ContentMarginPlacement.automatic), [0])
        XCTAssertEqual(bytes(of: ContentMarginPlacement.scrollContent), [1])
        XCTAssertEqual(bytes(of: ContentMarginPlacement.scrollIndicators), [2])
    }

    func testContentMarginsBuildsContentMarginModifierShape() {
        let lengthView = Text("x").contentMargins(.horizontal, 12, for: .scrollContent)
        let lengthMirror = Mirror(reflecting: lengthView)
        XCTAssertEqual(lengthMirror.children.map(\.label), ["content", "modifier"])

        guard let lengthModifier = lengthMirror.descendant("modifier") else {
            XCTFail("expected content margin modifier")
            return
        }
        let lengthModifierMirror = Mirror(reflecting: lengthModifier)
        XCTAssertEqual(lengthModifierMirror.children.map(\.label), ["edges", "insets", "placement"])
        XCTAssertEqual(lengthModifierMirror.descendant("edges") as? Edge.Set, .horizontal)
        XCTAssertEqual(bytes(of: lengthModifierMirror.descendant("placement") as! ContentMarginPlacement), [1])

        let lengthInsets = optionalInsetValues(lengthModifierMirror.descendant("insets")!)
        XCTAssertNil(lengthInsets["top"]!)
        XCTAssertEqual(lengthInsets["leading"]!, 12)
        XCTAssertNil(lengthInsets["bottom"]!)
        XCTAssertEqual(lengthInsets["trailing"]!, 12)

        let edgeInsetView = Text("x").contentMargins(
            .vertical,
            EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
            for: .scrollIndicators
        )
        let edgeInsetModifier = Mirror(reflecting: edgeInsetView).descendant("modifier")!
        let edgeInsetModifierMirror = Mirror(reflecting: edgeInsetModifier)
        XCTAssertEqual(edgeInsetModifierMirror.descendant("edges") as? Edge.Set, .vertical)
        XCTAssertEqual(bytes(of: edgeInsetModifierMirror.descendant("placement") as! ContentMarginPlacement), [2])

        let edgeInsets = optionalInsetValues(edgeInsetModifierMirror.descendant("insets")!)
        XCTAssertEqual(edgeInsets["top"]!, 1)
        XCTAssertEqual(edgeInsets["leading"]!, 2)
        XCTAssertEqual(edgeInsets["bottom"]!, 3)
        XCTAssertEqual(edgeInsets["trailing"]!, 4)
    }

    func testContentMarginEnvironmentProxyMergesPlacementAndAutomaticFallback() {
        var values = EnvironmentValues()
        values.setContentMargins(
            OptionalEdgeInsets(edges: .all, length: 5),
            in: .all,
            for: .automatic
        )
        values.setContentMargins(
            OptionalEdgeInsets(edges: .horizontal, length: 12),
            in: .horizontal,
            for: .scrollContent
        )

        let proxy = values.contentMarginProxy
        XCTAssertEqual(
            proxy.margins(for: .scrollContent, in: .all, allowAutomatic: true),
            EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        )
        XCTAssertEqual(
            proxy.margins(for: .scrollContent, in: .all, allowAutomatic: false),
            EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        )
        XCTAssertEqual(
            proxy.margins(for: .automatic, in: .vertical, allowAutomatic: true),
            EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
        )
    }

    func testContentMarginModifierAndResetPublishTrackedEnvironment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var inputs = makeViewInputs(graph: graph)
            let contentMarginModifier = graph.makeInput(value: ContentMarginModifier(
                edges: .all,
                insets: OptionalEdgeInsets(edges: .all, length: 8),
                placement: .automatic
            ))
            ContentMarginModifier._makeInputs(
                modifier: _GraphValue(_attribute: contentMarginModifier),
                inputs: &inputs.base
            )

            let scrollContentModifier = graph.makeInput(value: ContentMarginModifier(
                edges: .horizontal,
                insets: OptionalEdgeInsets(edges: .horizontal, length: 13),
                placement: .scrollContent
            ))
            ContentMarginModifier._makeInputs(
                modifier: _GraphValue(_attribute: scrollContentModifier),
                inputs: &inputs.base
            )

            let proxy = inputs.base.contentMarginProxy
            XCTAssertEqual(
                proxy.value.margins(for: .scrollContent, in: .all, allowAutomatic: true),
                EdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13)
            )
            XCTAssertEqual(inputs.base.contentMarginProxy.identifier, proxy.identifier)

            let resetModifier = graph.makeInput(value: ResetContentMarginModifier(placements: [
                .automatic,
                .scrollContent,
            ]))
            ResetContentMarginModifier._makeInputs(
                modifier: _GraphValue(_attribute: resetModifier),
                inputs: &inputs.base
            )

            XCTAssertEqual(
                inputs.base.contentMarginProxy.value.margins(
                    for: .scrollContent,
                    in: .all,
                    allowAutomatic: true
                ),
                EdgeInsets()
            )
        }
    }

    func testEnvironmentAxesModifierPublishesScrollableAxesEnvironment() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var inputs = makeViewInputs(graph: graph)
            let parentEnvironment = inputs.base.cachedEnvironment.value.environment
            var parentValues = parentEnvironment.value
            parentValues.allScrollableAxes = .horizontal
            parentEnvironment.setValue(parentValues)

            let modifierAttribute = graph.makeInput(
                value: EnvironmentAxesModifier(scrollableAxes: .vertical)
            )
            EnvironmentAxesModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifierAttribute),
                inputs: &inputs.base
            )

            let nearest = inputs.base.nearestScrollableAxes
            let all = inputs.base.allScrollableAxes

            XCTAssertEqual(nearest.value, .vertical)
            XCTAssertEqual(all.value, [.horizontal, .vertical])
            XCTAssertEqual(inputs.base.nearestScrollableAxes.identifier, nearest.identifier)
            XCTAssertEqual(inputs.base.allScrollableAxes.identifier, all.identifier)

            var updatedModifier = modifierAttribute.value
            updatedModifier.scrollableAxes = .horizontal
            modifierAttribute.setValue(updatedModifier)

            XCTAssertEqual(nearest.value, .horizontal)
            XCTAssertEqual(all.value, .horizontal)
        }
    }

    func testSystemScrollViewMakeViewInstallsScrollableInputsAndPreferenceProvider() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollablePreferenceKey.self)
            let recorder = ScrollViewInputRecorder()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            let outputs = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            )

            XCTAssertTrue(recorder.sawScrollablePreferenceKey)
            XCTAssertTrue(recorder.sawUpdateScrollStateRequestKey)
            XCTAssertNotNil(recorder.scrollableAttribute)
            XCTAssertNotNil(recorder.phaseStateAttribute)

            guard let scrollablePreference = outputs.preferences.value(for: ScrollablePreferenceKey.self) else {
                XCTFail("expected ScrollablePreferenceKey output")
                return
            }

            let scrollables = Attribute<[any Scrollable]>(scrollablePreference).value
            XCTAssertEqual(scrollables.count, 1)
            XCTAssertTrue(String(reflecting: type(of: scrollables[0])).contains("ScrollViewScrollable"))
        }
    }

    func testSystemScrollViewMakeViewKeepsScrollablePreferenceInternalWhenUnrequested() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let recorder = ScrollViewInputRecorder()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            let outputs = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph)
            )

            XCTAssertTrue(recorder.sawScrollablePreferenceKey)
            XCTAssertTrue(recorder.sawUpdateScrollStateRequestKey)
            XCTAssertNotNil(recorder.scrollableAttribute)
            XCTAssertNil(outputs.preferences.value(for: ScrollablePreferenceKey.self))
        }
    }

    func testSystemScrollViewMakeViewPublishesGeometryPreferenceWhenRequested() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollGeometryPreferenceKey.self)
            let recorder = ScrollViewInputRecorder()
            let contentInsets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(axes: .horizontal, contentInsets: contentInsets),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            let position = CGPoint(x: 7, y: 9)
            let size = CGSize(width: 80, height: 120)
            var transform = ViewTransform.identity
            transform.appendTranslation(CGSize(width: 3, height: 4))
            var inputs = makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            inputs.position = graph.makeInput(value: position)
            inputs.size = graph.makeInput(value: ViewSize(size))
            inputs.transform = graph.makeInput(value: transform)

            let outputs = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            guard let geometryPreference = outputs.preferences.value(for: ScrollGeometryPreferenceKey.self) else {
                XCTFail("expected ScrollGeometryPreferenceKey output")
                return
            }

            let states = Attribute<[ScrollGeometryState]>(geometryPreference).value
            XCTAssertEqual(states.count, 1)
            XCTAssertEqual(
                states[0].geometry,
                ScrollGeometry(
                    contentOffset: .zero,
                    contentSize: recordingContentSize,
                    contentInsets: contentInsets,
                    containerSize: size,
                    visibleRect: CGRect(
                        origin: .zero,
                        size: CGSize(
                            width: size.width + contentInsets.leading + contentInsets.trailing,
                            height: size.height + contentInsets.top + contentInsets.bottom
                        )
                    )
                )
            )
            XCTAssertEqual(states[0].scrollableAxes, .horizontal)

            var expectedTransform = transform
            expectedTransform.appendPosition(position)
            XCTAssertEqual(states[0].transform, expectedTransform)
            XCTAssertNotNil(recorder.scrollableAttribute)

            var updatedView = view
            let updatedInsets = EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8)
            updatedView.configuration.contentInsets = updatedInsets
            viewAttr.setValue(updatedView)

            let updatedStates = Attribute<[ScrollGeometryState]>(geometryPreference).value
            XCTAssertEqual(updatedStates.first?.geometry.contentInsets, updatedInsets)
            XCTAssertEqual(updatedStates.first?.geometry.contentSize, recordingContentSize)

            var resizedView = updatedView
            let resizedContent = CGSize(width: 31, height: 47)
            resizedView.content.size = resizedContent
            viewAttr.setValue(resizedView)

            let resizedStates = Attribute<[ScrollGeometryState]>(geometryPreference).value
            XCTAssertEqual(resizedStates.first?.geometry.contentInsets, updatedInsets)
            XCTAssertEqual(resizedStates.first?.geometry.contentSize, resizedContent)
        }
    }

    func testSystemScrollViewContentTransformSuppliesScrollGeometryWindows() throws {
        let previous = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previous }

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let recorder = ScrollViewInputRecorder()
            let contentInsets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(contentInsets: contentInsets),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            let position = CGPoint(x: 19, y: 29)
            let size = CGSize(width: 80, height: 120)
            let parentSafeAreaInsets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            var inputs = makeViewInputs(graph: graph)
            inputs.position = graph.makeInput(value: position)
            inputs.size = graph.makeInput(value: ViewSize(size))
            inputs.safeAreaInsets = OptionalAttribute(graph.makeInput(value: SafeAreaInsets(parentSafeAreaInsets)))

            _ = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            let transform = try XCTUnwrap(recorder.transform).value
            let containing = try XCTUnwrap(transform.containingScrollGeometry)
            let nearest = try XCTUnwrap(transform.nearestScrollGeometry)
            var resetPosition: CGPoint?
            var resetPrecedesScrollGeometry = false
            var sawReset = false
            transform.forEach(inverted: false) { item, stop in
                switch item {
                case .resetPosition(let point):
                    resetPosition = point
                    sawReset = true
                case .scrollGeometry where sawReset:
                    resetPrecedesScrollGeometry = true
                    stop = true
                default:
                    break
                }
            }
            XCTAssertEqual(transform.globalPosition, position)
            XCTAssertEqual(resetPosition, position)
            XCTAssertTrue(resetPrecedesScrollGeometry)

            XCTAssertEqual(containing.contentOffset, .zero)
            XCTAssertTrue(containing.contentSize.width.isInfinite)
            XCTAssertTrue(containing.contentSize.height.isInfinite)
            XCTAssertEqual(containing.containerSize, size)
            XCTAssertEqual(containing.visibleRect, CGRect(origin: .zero, size: size))

            XCTAssertEqual(nearest.contentOffset, .zero)
            XCTAssertEqual(nearest.contentSize, recordingContentSize)
            XCTAssertEqual(nearest.contentInsets, contentInsets)
            XCTAssertEqual(nearest.containerSize, size)
            XCTAssertEqual(
                nearest.visibleRect,
                CGRect(
                    x: -contentInsets.leading,
                    y: -contentInsets.top,
                    width: size.width + contentInsets.leading + contentInsets.trailing,
                    height: size.height + contentInsets.top + contentInsets.bottom
                )
            )

            XCTAssertEqual(transform.scrollCoordinateSpaces, [
                .all,
                .vertical,
                .content,
                .safeArea,
            ])
            let spaceSizes = transform.scrollCoordinateSpaceSizes
            XCTAssertEqual(spaceSizes.count, 4)
            XCTAssertEqual(spaceSizes[0].0, .all)
            XCTAssertEqual(spaceSizes[0].1, size)
            XCTAssertEqual(spaceSizes[1].0, .vertical)
            XCTAssertEqual(spaceSizes[1].1, size)
            XCTAssertEqual(spaceSizes[2].0, .content)
            XCTAssertEqual(spaceSizes[2].1, recordingContentSize)
            XCTAssertEqual(spaceSizes[3].0, .safeArea)
            XCTAssertEqual(
                spaceSizes[3].1,
                CGSize(
                    width: size.width + contentInsets.leading + contentInsets.trailing,
                    height: size.height + contentInsets.top + contentInsets.bottom
                )
            )
            XCTAssertEqual(Array(transform.translations.suffix(3)), [
                CGSize.zero,
                CGSize(width: parentSafeAreaInsets.leading, height: 0),
                CGSize(width: -parentSafeAreaInsets.leading, height: 0),
            ])
            let childSafeAreaInsets = try XCTUnwrap(recorder.safeAreaInsets?.value)
            XCTAssertEqual(childSafeAreaInsets.space, ScrollCoordinateSpace.safeArea.id)
            XCTAssertEqual(childSafeAreaInsets.next, .empty)
            XCTAssertEqual(childSafeAreaInsets.elements.count, 1)
            let childSafeAreaElement = try XCTUnwrap(childSafeAreaInsets.elements.first)
            XCTAssertEqual(childSafeAreaElement.regions, .container)
            XCTAssertNil(childSafeAreaElement.cornerInsets)
            XCTAssertEqual(
                childSafeAreaElement.insets,
                EdgeInsets(
                    top: 0,
                    leading: parentSafeAreaInsets.leading,
                    bottom: 0,
                    trailing: parentSafeAreaInsets.trailing
                )
            )
            XCTAssertEqual(childSafeAreaInsets.value, childSafeAreaElement.insets)

            let scrollableID = try XCTUnwrap(recorder.scrollableAttribute)
            var stored = ScrollPosition(idType: String.self)
            let target = ScrollPosition(idType: String.self, point: CGPoint(x: 12, y: 34))
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: nil,
                id: ObjectIdentifier(recorder),
                value: target,
                baseTransaction: Transaction()
            )
            request.updateScrollable(Attribute<any Scrollable>(scrollableID))

            XCTAssertTrue(request.update())
            let updatedTranslations = try XCTUnwrap(recorder.transform?.value.translations)
            XCTAssertEqual(Array(updatedTranslations.suffix(3)).first, CGSize(width: 12, height: 34))
        }
    }

    func testSystemScrollViewChildPositionUsesVerticalOriginEdgesForRightToLeftVerticalScroll() throws {
        let previous = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previous }

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let recorder = ScrollViewInputRecorder()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(axes: .vertical),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            let parentSafeAreaInsets = EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)
            var environment = EnvironmentValues.tracking()
            environment.layoutDirection = .rightToLeft
            var inputs = makeViewInputs(graph: graph)
            inputs.base.cachedEnvironment = MutableBox(
                CachedEnvironment(environment: graph.makeInput(value: environment))
            )
            inputs.safeAreaInsets = OptionalAttribute(graph.makeInput(value: SafeAreaInsets(parentSafeAreaInsets)))

            _ = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            let transform = try XCTUnwrap(recorder.transform).value
            XCTAssertEqual(Array(transform.translations.suffix(2)), [CGSize.zero, CGSize.zero])
            let childSafeAreaInsets = try XCTUnwrap(recorder.safeAreaInsets?.value)
            XCTAssertEqual(childSafeAreaInsets.space, ScrollCoordinateSpace.safeArea.id)
            XCTAssertEqual(childSafeAreaInsets.next, .empty)
            XCTAssertEqual(childSafeAreaInsets.elements.count, 1)
            let childSafeAreaElement = try XCTUnwrap(childSafeAreaInsets.elements.first)
            XCTAssertEqual(childSafeAreaElement.regions, .container)
            XCTAssertNil(childSafeAreaElement.cornerInsets)
            XCTAssertEqual(
                childSafeAreaElement.insets,
                EdgeInsets(
                    top: 0,
                    leading: parentSafeAreaInsets.trailing,
                    bottom: 0,
                    trailing: parentSafeAreaInsets.leading
                )
            )
            XCTAssertEqual(childSafeAreaInsets.value, childSafeAreaElement.insets)
        }
    }

    func testScrollViewContentTransformUsesSafeAreaPositionForSafeAreaSpace() {
        let previous = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previous }

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let geometry = ScrollGeometry(
                contentOffset: CGPoint(x: 6, y: 7),
                contentSize: CGSize(width: 140, height: 240),
                contentInsets: insets,
                containerSize: CGSize(width: 50, height: 60)
            )
            let safeAreaPosition = CGPoint(x: 9, y: 11)
            let provider = ScrollViewContentTransformProvider(
                transform: graph.makeInput(value: ViewTransform.identity),
                position: graph.makeInput(value: CGPoint(x: 100, y: 200)),
                safeAreaPosition: graph.makeInput(value: safeAreaPosition),
                geometry: graph.makeInput(value: geometry),
                axes: graph.makeInput(value: Axis.Set.vertical)
            )

            let transform = provider.updateValue()
            XCTAssertEqual(transform.globalPosition, CGPoint(x: 100, y: 200))
            XCTAssertEqual(transform.scrollCoordinateSpaces, [
                .all,
                .vertical,
                .content,
                .safeArea,
            ])
            XCTAssertEqual(Array(transform.translations.suffix(3)), [
                CGSize(width: geometry.contentOffset.x, height: geometry.contentOffset.y),
                CGSize(width: safeAreaPosition.x, height: safeAreaPosition.y),
                CGSize(width: -safeAreaPosition.x, height: -safeAreaPosition.y),
            ])
            XCTAssertEqual(transform.scrollCoordinateSpaceSizes.last?.0, .safeArea)
            XCTAssertEqual(
                transform.scrollCoordinateSpaceSizes.last?.1,
                CGSize(
                    width: geometry.containerSize.width + insets.leading + insets.trailing,
                    height: geometry.containerSize.height + insets.top + insets.bottom
                )
            )
        }
    }

    func testSystemScrollViewContentTransformOmitsSafeAreaBeforeV6Semantics() throws {
        let previous = Semantics.overrides
        Semantics.overrides = Semantics.Overrides(build: .v5, runtime: previous.runtime)
        defer { Semantics.overrides = previous }

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            let recorder = ScrollViewInputRecorder()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(
                    contentInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
                ),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            var inputs = makeViewInputs(graph: graph)
            inputs.position = graph.makeInput(value: CGPoint(x: 19, y: 29))
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 80, height: 120)))

            _ = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            let transform = try XCTUnwrap(recorder.transform).value
            XCTAssertEqual(transform.scrollCoordinateSpaces, [
                .all,
                .vertical,
                .content,
            ])
            XCTAssertEqual(transform.translations.last, Optional(CGSize.zero))
            let childSafeAreaInsets = try XCTUnwrap(recorder.safeAreaInsets?.value)
            XCTAssertEqual(childSafeAreaInsets.space, ScrollCoordinateSpace.safeArea.id)
            XCTAssertEqual(childSafeAreaInsets.next, .empty)
            XCTAssertTrue(childSafeAreaInsets.elements.isEmpty)
            XCTAssertEqual(childSafeAreaInsets.value, EdgeInsets())
        }
    }

    func testSystemScrollViewScrollableAppliesScrollToPointRequestToGeometryState() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollablePreferenceKey.self)
            preferenceKeys.insert(ScrollGeometryPreferenceKey.self)
            let recorder = ScrollViewInputRecorder()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            var inputs = makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 80, height: 120)))

            let outputs = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            guard let scrollableID = recorder.scrollableAttribute,
                  let geometryPreference = outputs.preferences.value(for: ScrollGeometryPreferenceKey.self) else {
                XCTFail("expected scrollable and geometry outputs")
                return
            }

            let geometryAttribute = Attribute<[ScrollGeometryState]>(geometryPreference)
            XCTAssertEqual(geometryAttribute.value.first?.geometry.contentOffset, .zero)

            var stored = ScrollPosition(idType: String.self)
            let target = ScrollPosition(idType: String.self, point: CGPoint(x: 12, y: 34))
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: nil,
                id: ObjectIdentifier(recorder),
                value: target,
                baseTransaction: Transaction()
            )
            request.updateScrollable(Attribute<any Scrollable>(scrollableID))

            XCTAssertTrue(request.update())
            XCTAssertEqual(stored, target)

            let updatedGeometry = geometryAttribute.value.first?.geometry
            XCTAssertEqual(updatedGeometry?.contentOffset, CGPoint(x: 12, y: 34))
            XCTAssertEqual(updatedGeometry?.visibleRect.origin, CGPoint(x: 12, y: 34))
        }
    }

    func testSystemScrollViewScrollableAppliesAxisTargetsAndOffsetAdjustmentsToGeometryState() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollablePreferenceKey.self)
            preferenceKeys.insert(ScrollGeometryPreferenceKey.self)
            let recorder = ScrollViewInputRecorder()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let viewAttr = graph.makeInput(value: view)
            var inputs = makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 80, height: 120)))

            let outputs = SystemScrollView<ScrollViewRecordingContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            guard let scrollableID = recorder.scrollableAttribute,
                  let geometryPreference = outputs.preferences.value(for: ScrollGeometryPreferenceKey.self) else {
                XCTFail("expected scrollable and geometry outputs")
                return
            }

            let scrollableAttribute = Attribute<any Scrollable>(scrollableID)
            let scrollable = scrollableAttribute.value
            let geometryAttribute = Attribute<[ScrollGeometryState]>(geometryPreference)
            var stored = ScrollPosition(idType: String.self)
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )

            func apply(_ target: ScrollPosition) {
                var request = ScrollToScrollStateRequest(
                    binding: binding,
                    anchor: nil,
                    id: ObjectIdentifier(recorder),
                    value: target,
                    baseTransaction: Transaction()
                )
                request.updateScrollable(scrollableAttribute)
                XCTAssertTrue(request.update())
                XCTAssertEqual(stored, target)
            }

            apply(ScrollPosition(idType: String.self, x: 14))
            XCTAssertEqual(
                geometryAttribute.value.first?.geometry.contentOffset,
                CGPoint(x: 14, y: 0)
            )

            apply(ScrollPosition(idType: String.self, y: 28))
            XCTAssertEqual(
                geometryAttribute.value.first?.geometry.contentOffset,
                CGPoint(x: 14, y: 28)
            )

            XCTAssertTrue(scrollable.allowsContentOffsetAdjustments)
            XCTAssertTrue(scrollable.adjustContentOffset(by: CGSize(width: -4, height: 6), reason: .scrollPosition))

            let adjustedGeometry = geometryAttribute.value.first?.geometry
            XCTAssertEqual(adjustedGeometry?.contentOffset, CGPoint(x: 10, y: 34))
            XCTAssertEqual(adjustedGeometry?.visibleRect.origin, CGPoint(x: 10, y: 34))
        }
    }

    func testSystemScrollViewScrollableRoutesViewIDRequestToChildScrollablePreference() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollablePreferenceKey.self)
            let recorder = ScrollViewInputRecorder()
            let child = ScrollViewChildCollectionScrollable()
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(),
                content: ScrollViewChildScrollableContent(recorder: recorder, child: child)
            )
            let viewAttr = graph.makeInput(value: view)
            _ = SystemScrollView<ScrollViewChildScrollableContent>._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            )

            guard let scrollableID = recorder.scrollableAttribute else {
                XCTFail("expected scrollable input")
                return
            }

            var stored = ScrollPosition(idType: String.self)
            var bindingTransactions: [Transaction] = []
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, transaction in
                    stored = value
                    bindingTransactions.append(transaction)
                }
            )
            let target = ScrollPosition(id: "child")
            var request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: .bottom,
                id: ObjectIdentifier(recorder),
                value: target,
                baseTransaction: Transaction()
            )
            request.updateScrollable(Attribute<any Scrollable>(scrollableID))

            XCTAssertTrue(request.update())
            XCTAssertEqual(stored, target)
            XCTAssertEqual(child.scrolledCollectionIDs.count, 1)
            XCTAssertEqual(child.scrolledCollectionIDs[0].explicitID, AnyHashable("child"))
            XCTAssertEqual(child.scrolledCollectionAnchors, [.bottom])
            XCTAssertEqual(child.observedTransactions.map(\.scrollTargetAnchor), [.bottom])
            XCTAssertEqual(bindingTransactions.map(\.scrollTargetAnchor), [nil])
        }
    }

    func testSystemScrollViewScrollableAppliesChildCollectionViewIDTargetToGeometryState() {
        let host = GraphHost()
        var scrollablePreference: AGAttribute!
        var geometryPreference: AGAttribute!

        host.data.withCurrent {
            let graph = host.data.graph
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollablePreferenceKey.self)
            preferenceKeys.insert(ScrollGeometryPreferenceKey.self)
            let rows = (0..<3).map { ScrollViewTargetRow(id: $0) }
            let view = SystemScrollView(
                configuration: ScrollViewConfiguration(),
                content: _ScrollableLayoutView(data: rows, layout: ScrollViewTargetLayout())
            )
            let viewAttr = graph.makeInput(value: view)
            var inputs = makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            inputs.size = graph.makeInput(value: ViewSize(CGSize(width: 100, height: 80)))

            let outputs = SystemScrollView<
                _ScrollableLayoutView<[ScrollViewTargetRow], ScrollViewTargetLayout>
            >._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: inputs
            )

            guard let outputScrollablePreference = outputs.preferences.value(for: ScrollablePreferenceKey.self),
                  let outputGeometryPreference = outputs.preferences.value(for: ScrollGeometryPreferenceKey.self) else {
                XCTFail("expected scrollable and geometry outputs")
                return
            }
            scrollablePreference = outputScrollablePreference
            geometryPreference = outputGeometryPreference

            _ = Attribute<[any Scrollable]>(outputScrollablePreference).value
        }

        host.flushTransactions()

        host.data.withCurrent {
            let graph = host.data.graph
            let scrollableAttribute = graph.makeRule {
                Attribute<[any Scrollable]>(scrollablePreference).value[0]
            }
            let geometryAttribute = Attribute<[ScrollGeometryState]>(geometryPreference)
            var stored = ScrollPosition(idType: Int.self)
            let target = ScrollPosition(id: 2)
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
            request.updateScrollable(scrollableAttribute)

            XCTAssertTrue(request.update())
            XCTAssertEqual(stored, target)

            let updatedGeometry = geometryAttribute.value.first?.geometry
            XCTAssertEqual(updatedGeometry?.contentOffset, CGPoint(x: 0, y: 140))
            XCTAssertEqual(updatedGeometry?.visibleRect.origin, CGPoint(x: 0, y: 140))
        }
    }

    func testContainerBodyConfiguresPhaseStateAndResetsChildPreferenceRequests() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var preferenceKeys = PreferenceKeys()
            preferenceKeys.insert(ScrollPhasePreferenceKey.self)
            preferenceKeys.insert(ScrollGeometryPreferenceKey.self)
            let recorder = ScrollViewInputRecorder()
            let container = SystemScrollViewContainer(
                configuration: ScrollViewConfiguration(),
                content: ScrollViewRecordingContent(recorder: recorder)
            )
            let body = container.body
            let bodyAttr = graph.makeInput(value: body)
            let outputs = type(of: body)._makeView(
                view: _GraphValue(_attribute: bodyAttr),
                inputs: makeViewInputs(graph: graph, preferenceKeys: preferenceKeys)
            )

            XCTAssertNotNil(recorder.phaseStateAttribute)
            XCTAssertFalse(recorder.sawScrollPhasePreferenceKey)
            XCTAssertFalse(recorder.sawScrollGeometryPreferenceKey)

            guard let phasePreference = outputs.preferences.value(for: ScrollPhasePreferenceKey.self) else {
                XCTFail("expected ScrollPhasePreferenceKey output")
                return
            }
            XCTAssertEqual(Attribute<[ScrollPhaseState]>(phasePreference).value, [ScrollPhaseState()])
        }
    }

    func testScrollActionModifiersRequestExpectedPreferences() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let phaseRecorder = ScrollViewInputRecorder()
            let phaseView = ScrollViewRecordingContent(recorder: phaseRecorder)
                .onScrollPhaseChange { _, _ in }
            let phaseAttr = graph.makeInput(value: phaseView)
            _ = type(of: phaseView)._makeView(
                view: _GraphValue(_attribute: phaseAttr),
                inputs: makeViewInputs(graph: graph)
            )
            XCTAssertTrue(phaseRecorder.sawScrollPhasePreferenceKey)
            XCTAssertFalse(phaseRecorder.sawScrollGeometryPreferenceKey)

            let contextRecorder = ScrollViewInputRecorder()
            let contextView = ScrollViewRecordingContent(recorder: contextRecorder)
                .onScrollPhaseChange { _, _, _ in }
            let contextAttr = graph.makeInput(value: contextView)
            _ = type(of: contextView)._makeView(
                view: _GraphValue(_attribute: contextAttr),
                inputs: makeViewInputs(graph: graph)
            )
            XCTAssertTrue(contextRecorder.sawScrollPhasePreferenceKey)
            XCTAssertTrue(contextRecorder.sawScrollGeometryPreferenceKey)

            let geometryRecorder = ScrollViewInputRecorder()
            let geometryView = ScrollViewRecordingContent(recorder: geometryRecorder)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, _ in }
            let geometryAttr = graph.makeInput(value: geometryView)
            _ = type(of: geometryView)._makeView(
                view: _GraphValue(_attribute: geometryAttr),
                inputs: makeViewInputs(graph: graph)
            )
            XCTAssertFalse(geometryRecorder.sawScrollPhasePreferenceKey)
            XCTAssertTrue(geometryRecorder.sawScrollGeometryPreferenceKey)
        }
    }

    func testScrollActionDispatcherQueuesPhaseActionsAfterInitialOutput() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var calls: [(ScrollPhase, ScrollPhase)] = []
            let modifier = graph.makeInput(
                value: OnScrollPhaseChangeModifier { oldPhase, newPhase in
                    calls.append((oldPhase, newPhase))
                }
            )
            let phaseValues = graph.makeInput(value: [ScrollPhaseState(phase: .idle)])
            let viewPhase = graph.makeInput(value: Phase())
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: OnScrollPhaseChangeModifier.PhaseActionProvider(modifier: modifier),
                    inputs: phaseValues,
                    viewPhase: viewPhase,
                    prefersLast: OptionalAttribute()
                )
            )

            _ = dispatcher.value
            XCTAssertTrue(calls.isEmpty)

            phaseValues.setValue([ScrollPhaseState(phase: .interacting)])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].0, .idle)
            XCTAssertEqual(calls[0].1, .interacting)

            var resetPhase = Phase()
            resetPhase.resetSeed = 1
            viewPhase.setValue(resetPhase)
            phaseValues.setValue([ScrollPhaseState(phase: .decelerating)])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)

            phaseValues.setValue([ScrollPhaseState(phase: .idle)])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 2)
            XCTAssertEqual(calls[1].0, .decelerating)
            XCTAssertEqual(calls[1].1, .idle)
        }
    }

    func testScrollActionDispatcherStoresExpectedFieldShape() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let modifier = graph.makeInput(
                value: OnScrollPhaseChangeModifier { _, _ in }
            )
            let dispatcher = ScrollActionDispatcher(
                provider: OnScrollPhaseChangeModifier.PhaseActionProvider(modifier: modifier),
                inputs: graph.makeInput(value: [ScrollPhaseState(phase: .idle)]),
                viewPhase: graph.makeInput(value: Phase()),
                prefersLast: OptionalAttribute()
            )

            XCTAssertEqual(Mirror(reflecting: dispatcher).children.compactMap(\.label), [
                "provider",
                "inputs",
                "viewPhase",
                "prefersLast",
                "cycleDetector",
                "oldResetSeed",
                "oldOutput",
                "viewGraph",
            ])
        }
    }

    func testScrollActionDispatcherCycleDetectorSuppressesThirdSameSeedAction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var calls: [(ScrollPhase, ScrollPhase)] = []
            let modifier = graph.makeInput(
                value: OnScrollPhaseChangeModifier { oldPhase, newPhase in
                    calls.append((oldPhase, newPhase))
                }
            )
            let phaseValues = graph.makeInput(value: [ScrollPhaseState(phase: .idle)])
            let viewPhase = graph.makeInput(value: Phase())
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: OnScrollPhaseChangeModifier.PhaseActionProvider(modifier: modifier),
                    inputs: phaseValues,
                    viewPhase: viewPhase,
                    prefersLast: OptionalAttribute()
                )
            )

            _ = dispatcher.value
            phaseValues.setValue([ScrollPhaseState(phase: .tracking)])
            _ = dispatcher.value
            phaseValues.setValue([ScrollPhaseState(phase: .interacting)])
            _ = dispatcher.value
            phaseValues.setValue([ScrollPhaseState(phase: .decelerating)])
            _ = dispatcher.value

            XCTAssertEqual(calls.map(\.0), [.idle, .tracking])
            XCTAssertEqual(calls.map(\.1), [.tracking, .interacting])

            var resetPhase = Phase()
            resetPhase.resetSeed = 1
            viewPhase.setValue(resetPhase)
            phaseValues.setValue([ScrollPhaseState(phase: .animating)])
            _ = dispatcher.value
            phaseValues.setValue([ScrollPhaseState(phase: .idle)])
            _ = dispatcher.value

            XCTAssertEqual(calls.map(\.0), [.idle, .tracking, .animating])
            XCTAssertEqual(calls.map(\.1), [.tracking, .interacting, .idle])
        }
    }

    func testScrollActionDispatcherClearsOutputWhenSourceDisappears() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var calls: [(CGFloat, CGFloat)] = []
            let modifier = graph.makeInput(
                value: OnScrollGeometryChangeModifier<CGFloat>(
                    transform: { $0.contentOffset.x },
                    action: { oldOffset, newOffset in
                        calls.append((oldOffset, newOffset))
                    },
                    prefersLast: false
                )
            )
            let geometryValues = graph.makeInput(value: [
                makeScrollGeometryState(offsetX: 1),
            ])
            let viewPhase = graph.makeInput(value: Phase())
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: OnScrollGeometryChangeModifier<CGFloat>.GeometryActionProvider(modifier: modifier),
                    inputs: geometryValues,
                    viewPhase: viewPhase,
                    prefersLast: OptionalAttribute()
                )
            )

            _ = dispatcher.value
            XCTAssertTrue(calls.isEmpty)

            geometryValues.setValue([makeScrollGeometryState(offsetX: 2)])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].0, 1)
            XCTAssertEqual(calls[0].1, 2)

            geometryValues.setValue([])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)

            geometryValues.setValue([makeScrollGeometryState(offsetX: 10)])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)

            geometryValues.setValue([makeScrollGeometryState(offsetX: 11)])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 2)
            XCTAssertEqual(calls[1].0, 10)
            XCTAssertEqual(calls[1].1, 11)
        }
    }

    func testScrollActionDispatcherUsesLastGeometryWhenRequested() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var calls: [(CGFloat, CGFloat)] = []
            let modifier = graph.makeInput(
                value: OnScrollGeometryChangeModifier<CGFloat>(
                    transform: { $0.contentOffset.x },
                    action: { oldOffset, newOffset in
                        calls.append((oldOffset, newOffset))
                    },
                    prefersLast: true
                )
            )
            let geometryValues = graph.makeInput(value: [
                makeScrollGeometryState(offsetX: 1),
                makeScrollGeometryState(offsetX: 10),
            ])
            let viewPhase = graph.makeInput(value: Phase())
            let prefersLast = graph.makeInput(value: true)
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: OnScrollGeometryChangeModifier<CGFloat>.GeometryActionProvider(modifier: modifier),
                    inputs: geometryValues,
                    viewPhase: viewPhase,
                    prefersLast: OptionalAttribute(prefersLast)
                )
            )

            _ = dispatcher.value
            XCTAssertTrue(calls.isEmpty)

            geometryValues.setValue([
                makeScrollGeometryState(offsetX: 2),
                makeScrollGeometryState(offsetX: 11),
            ])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].0, 10)
            XCTAssertEqual(calls[0].1, 11)
        }
    }

    func testScrollPhaseContextDispatcherBuildsContextFromGeometryState() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var calls: [(old: ScrollPhase, new: ScrollPhase, context: ScrollPhaseChangeContext)] = []
            let modifier = graph.makeInput(
                value: OnScrollPhaseContextChangeModifier { oldPhase, newPhase, context in
                    calls.append((oldPhase, newPhase, context))
                }
            )
            let phaseValues = graph.makeInput(value: [ScrollPhaseState(phase: .idle)])
            let geometryValues = graph.makeInput(value: [makeScrollGeometryState(offsetX: 42)])
            let viewPhase = graph.makeInput(value: Phase())
            let dispatcher: Attribute<Void> = graph.makeStatefulRule(
                ScrollActionDispatcher(
                    provider: OnScrollPhaseContextChangeModifier.PhaseContextActionProvider(
                        modifier: modifier,
                        geometryStates: OptionalAttribute(geometryValues)
                    ),
                    inputs: phaseValues,
                    viewPhase: viewPhase,
                    prefersLast: OptionalAttribute()
                )
            )

            _ = dispatcher.value
            XCTAssertTrue(calls.isEmpty)

            phaseValues.setValue([
                ScrollPhaseState(phase: .tracking, velocity: CGVector(dx: 3, dy: 4))
            ])
            _ = dispatcher.value
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].old, .idle)
            XCTAssertEqual(calls[0].new, .tracking)
            XCTAssertEqual(calls[0].context.geometry.contentOffset.x, 42)
            XCTAssertEqual(calls[0].context.velocity, CGVector(dx: 3, dy: 4))
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        preferenceKeys: PreferenceKeys = PreferenceKeys()
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
                keys: preferenceKeys,
                hostKeys: graph.makeInput(value: preferenceKeys)
            ),
            transform: graph.makeInput(value: ViewTransform.identity),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(.zero)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func makeScrollGeometryState(offsetX: CGFloat) -> ScrollGeometryState {
        ScrollGeometryState(
            geometry: ScrollGeometry(
                contentOffset: CGPoint(x: offsetX, y: 0),
                contentSize: CGSize(width: 100, height: 100),
                contentInsets: EdgeInsets(),
                containerSize: CGSize(width: 50, height: 50)
            ),
            scrollableAxes: [.horizontal, .vertical],
            transform: WeakAttribute()
        )
    }
}
