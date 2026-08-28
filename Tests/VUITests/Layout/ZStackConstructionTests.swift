import XCTest
@testable import VUI

#if canImport(Darwin)
import Darwin
#endif

final class ZStackConstructionTests: XCTestCase {
    func testDeepErasureBaselineBuilds() {
        let graph = render(deeplyErasedSystemImage)

        XCTAssertEqual(paddingLayoutComputerCount(in: graph), 10)
    }

    func testUnaryHStackWithDeepErasureBuilds() {
        let graph = render(
            HStack {
                deeplyErasedSystemImage
            }
        )

        XCTAssertEqual(paddingLayoutComputerCount(in: graph), 10)
    }

    func testUnaryVStackWithDeepErasureBuilds() {
        let graph = render(
            VStack {
                deeplyErasedSystemImage
            }
        )

        XCTAssertEqual(paddingLayoutComputerCount(in: graph), 10)
    }

    func testUnaryZStackWithDeepErasureBuilds() {
        let graph = render(
            ZStack {
                deeplyErasedSystemImage
            }
        )

        XCTAssertEqual(paddingLayoutComputerCount(in: graph), 10)
    }

    func testUnaryZStackLayoutWithDeepErasureBuilds() {
        let graph = render(
            ZStackLayout() {
                deeplyErasedSystemImage
            }
        )

        // A dynamic-list modifier chain must be materialized exactly once.
        XCTAssertEqual(paddingLayoutComputerCount(in: graph), 10)
    }

    func testZStackLayoutMaterializesDirectDynamicChildModifierOnce() {
        let graph = render(
            ZStackLayout() {
                AnyView(Image(systemName: "play"))
                    .padding(0)
            }
        )

        XCTAssertEqual(paddingLayoutComputerCount(in: graph), 1)
    }

    func testDynamicListModifierDefersMaterializationToConsumer() {
        // ASSERTIONS dynamicListModifierSingleMaterializationObserved
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let inputs = makeViewListInputs(graph: graph)
            let source = graph.makeInput(
                value: EmptyViewList() as any ViewList
            )
            let modifier = graph.makeInput(
                value: _PaddingLayout(insets: EdgeInsets())
            )
            var outputs = _ViewListOutputs(
                views: .dynamicList(source, nil),
                nextImplicitID: 0,
                staticCount: nil
            )

            outputs.multiModifier(
                _GraphValue(_attribute: modifier),
                inputs: inputs
            )

            guard case .dynamicList(
                let storedSource,
                let modifierChain
            ) = outputs.views else {
                return XCTFail("Expected dynamic-list modifier staging.")
            }
            XCTAssertEqual(storedSource.identifier, source.identifier)
            XCTAssertNotNil(modifierChain)
            let materialized = outputs.makeAttribute(inputs: inputs)
            XCTAssertNotEqual(materialized.identifier, source.identifier)
            XCTAssertEqual(modifiedViewListDepth(materialized.value), 1)
        }
    }

    func testDynamicListModifierHelperMaterializesAtMostOnce() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let inputs = makeViewListInputs(graph: graph)
            let source = graph.makeInput(
                value: EmptyViewList() as any ViewList
            )
            let modifier = graph.makeInput(
                value: _PaddingLayout(insets: EdgeInsets())
            )
            let chain = ListModifier(
                pred: nil,
                modifier: modifier,
                inputs: inputs.base
            )

            let passthrough = _ViewListOutputs.makeModifiedList(
                list: source,
                modifier: nil
            )
            XCTAssertEqual(passthrough.identifier, source.identifier)

            let materialized = _ViewListOutputs.makeModifiedList(
                list: source,
                modifier: chain
            )
            XCTAssertNotEqual(materialized.identifier, source.identifier)
            XCTAssertEqual(modifiedViewListDepth(materialized.value), 1)
        }
    }

    func testDynamicListViewInputsMaterializesModifierOnce() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let listInputs = makeViewListInputs(graph: graph)
            let source = graph.makeInput(
                value: EmptyViewList() as any ViewList
            )
            let modifier = graph.makeInput(
                value: _PaddingLayout(insets: EdgeInsets())
            )
            let chain = ListModifier(
                pred: nil,
                modifier: modifier,
                inputs: listInputs.base
            )
            let outputs = _ViewListOutputs(
                views: .dynamicList(source, chain),
                nextImplicitID: 0,
                staticCount: nil
            )

            let materialized = outputs.makeAttribute(
                viewInputs: makeViewInputs(graph: graph)
            )

            XCTAssertNotEqual(materialized.identifier, source.identifier)
            XCTAssertEqual(modifiedViewListDepth(materialized.value), 1)
        }
    }

    func testStaticViewInputsDeriveInitialImplicitIDFromOutputEnd() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var listInputs = makeViewListInputs(graph: graph)
            listInputs.implicitID = 6
            let view = graph.makeInput(value: Text("Child"))
            let outputs = _ViewListOutputs.unaryViewList(
                view: _GraphValue(_attribute: view),
                inputs: listInputs
            )

            XCTAssertEqual(outputs.nextImplicitID, 7)
            let materialized = outputs.makeAttribute(
                viewInputs: makeViewInputs(graph: graph)
            )
            guard let list = materialized.value as? BaseViewList else {
                return XCTFail("Expected a static BaseViewList.")
            }
            XCTAssertEqual(list.implicitID, 6)
        }
    }

    func testStaticListAttributesCarryStableIdentityScope() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            var listInputs = makeViewListInputs(graph: graph)
            var viewInputs = makeViewInputs(graph: graph)
            let root = _DisplayList_StableIdentityRoot()
            let scope = graph.makeInput(
                value: _DisplayList_StableIdentityScope(root: root)
            )
            let weakScope = WeakAttribute(scope)
            listInputs.base.options.insert(.needsStableDisplayListIDs)
            viewInputs.base.options.insert(.needsStableDisplayListIDs)
            listInputs.base[_DisplayList_StableIdentityScope.self] = weakScope
            viewInputs.base[_DisplayList_StableIdentityScope.self] = weakScope
            let view = graph.makeInput(value: Text("Child"))
            let outputs = _ViewListOutputs.unaryViewList(
                view: _GraphValue(_attribute: view),
                inputs: listInputs
            )

            let listMaterialized = try XCTUnwrap(
                outputs.makeAttribute(inputs: listInputs).value as? BaseViewList
            )
            let viewMaterialized = try XCTUnwrap(
                outputs.makeAttribute(viewInputs: viewInputs).value as? BaseViewList
            )

            XCTAssertEqual(
                listMaterialized.traits[_DisplayList_StableIdentityScope.self],
                weakScope
            )
            XCTAssertEqual(
                viewMaterialized.traits[_DisplayList_StableIdentityScope.self],
                weakScope
            )
        }
    }

    func testConcatKeepsMergedElementsStaticOnly() {
        // ASSERTIONS mergedElementsStaticOutputsOnlyObserved
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let inputs = makeViewListInputs(graph: graph)
            let firstView = graph.makeInput(value: Text("First"))
            let secondView = graph.makeInput(value: Text("Second"))
            let first = _ViewListOutputs.unaryViewList(
                view: _GraphValue(_attribute: firstView),
                inputs: inputs
            )
            let second = _ViewListOutputs.unaryViewList(
                view: _GraphValue(_attribute: secondView),
                inputs: inputs
            )

            let staticConcat = _ViewListOutputs.concat(
                [first, second],
                inputs: inputs
            )
            guard case .staticList(.merged(let merged)) =
                staticConcat.views else {
                return XCTFail("Expected a static merged carrier.")
            }
            XCTAssertTrue(
                merged.allSatisfy {
                    if case .staticList = $0.views { return true }
                    return false
                }
            )

            let dynamicSource = graph.makeInput(
                value: EmptyViewList() as any ViewList
            )
            let dynamic = _ViewListOutputs(
                views: .dynamicList(dynamicSource, nil),
                nextImplicitID: 0,
                staticCount: nil
            )
            let mixedConcat = _ViewListOutputs.concat(
                [first, dynamic],
                inputs: inputs
            )
            guard case .dynamicList(_, let modifier) =
                mixedConcat.views else {
                return XCTFail("Expected mixed outputs to promote to dynamic.")
            }
            XCTAssertNil(modifier)
        }
    }

    private var deeplyErasedSystemImage: AnyView {
        var view = AnyView(Image(systemName: "play"))
        for _ in 0..<10 {
            view = AnyView(view.padding(0))
        }
        return view
    }

    @discardableResult
    private func render<V: View>(_ view: V) -> ViewGraph {
#if canImport(Darwin)
        print(
            "ZSTACK_CONSTRUCTION_STACK_SIZE " +
                "\(pthread_get_stacksize_np(pthread_self()))"
        )
#endif
        let host = TestViewRendererHost()
        let graph = ViewGraph(
            replaceableContent: view,
            rendererHost: host
        )
        host.storage = graph

        graph.updateOutputs(at: .zero)

        XCTAssertNotNil(graph.rootLayoutComputer)
        return graph
    }

    private func paddingLayoutComputerCount(in viewGraph: ViewGraph) -> Int {
        ruleBodyCount(in: viewGraph) { name in
            name.contains("UnaryLayoutComputer<VUI._PaddingLayout>")
        }
    }

    private func ruleBodyCount(
        in viewGraph: ViewGraph,
        matching predicate: (String) -> Bool
    ) -> Int {
        viewGraph.data.graph.slots.reduce(into: 0) { count, slot in
            guard let node = slot.node else { return }
            let bodyType: Any.Type?
            switch node.pointee.kind {
            case .ruleBody(let box):
                bodyType = box.bodyType
            case .stateful(let box):
                bodyType = box.bodyType
            case .lowLevelBody(let box):
                bodyType = box.bodyType
            default:
                bodyType = nil
            }
            guard let bodyType else { return }
            let name = String(reflecting: bodyType)
            if predicate(name) {
                count += 1
            }
        }
    }

    private func makeViewListInputs(graph: _AGGraph) -> _ViewListInputs {
        _ViewListInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(
                    value: EnvironmentValues.tracking()
                ),
                transaction: graph.makeInput(value: Transaction())
            ),
            implicitID: 0,
            options: [],
            _traits: OptionalAttribute(),
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(
                    value: EnvironmentValues.tracking()
                ),
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

    private func modifiedViewListDepth(_ list: any ViewList) -> Int {
        guard let modified = list as? ModifiedViewList else { return 0 }
        return 1 + modifiedViewListDepth(modified.list)
    }
}
