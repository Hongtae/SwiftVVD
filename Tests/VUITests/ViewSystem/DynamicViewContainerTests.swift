import XCTest
@testable import VUI

private final class DynamicViewConstructionRecorder {
    var events: [String] = []
}

private struct DynamicViewProbeA: View, TestPrimitiveView {
    typealias Body = Never

    var width: CGFloat
    var preference: String
    var recorder: DynamicViewConstructionRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicViewProbeA._makeView requires an active graph.")
        }
        view._attribute.value.recorder.events.append("A")
        let layout = graph.makeRule {
            let value = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: value.width, height: 10))
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(
            DynamicViewProbePreferenceKey.self,
            node: view[\.preference]._attribute.identifier
        )
        return outputs
    }
}

private struct DynamicViewProbeB: View, TestPrimitiveView {
    typealias Body = Never

    var width: CGFloat
    var preference: String
    var recorder: DynamicViewConstructionRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicViewProbeB._makeView requires an active graph.")
        }
        view._attribute.value.recorder.events.append("B")
        let layout = graph.makeRule {
            let value = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: value.width, height: 20))
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(
            DynamicViewProbePreferenceKey.self,
            node: view[\.preference]._attribute.identifier
        )
        return outputs
    }
}

private struct DynamicViewProbePreferenceKey: PreferenceKey {
    static let defaultValue = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        value += nextValue()
    }
}

private struct DynamicListProbeA: View, TestPrimitiveView {
    typealias Body = Never

    var recorder: DynamicViewConstructionRecorder

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        view._attribute.value.recorder.events.append("list-A")
        return .unaryViewList(view: view, inputs: inputs)
    }
}

private struct DynamicListProbeB: View, TestPrimitiveView {
    typealias Body = Never

    var recorder: DynamicViewConstructionRecorder

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        view._attribute.value.recorder.events.append("list-B")
        return .unaryViewList(view: view, inputs: inputs)
    }
}

final class DynamicViewContainerTests: XCTestCase {
    func testConditionalListUsesLeafIdentityAndRebuildsOnlyForLeafReplacement() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = DynamicViewConstructionRecorder()

        try context.withCurrent {
            typealias Content = _ConditionalContent<DynamicListProbeA, DynamicListProbeB>
            let source = graph.makeInput(
                value: Content(
                    storage: .trueContent(DynamicListProbeA(recorder: recorder))
                )
            )
            let outputs = Content._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph).listInputs
            )
            let list = try dynamicListAttribute(from: outputs)
            let initialID = try firstID(in: list.value)
            XCTAssertTrue(list.value.traits[CanTransitionTraitKey.self])
            XCTAssertEqual(recorder.events, ["list-A"])

            source.setValue(
                Content(storage: .trueContent(DynamicListProbeA(recorder: recorder)))
            )
            XCTAssertEqual(try firstID(in: list.value), initialID)
            XCTAssertEqual(recorder.events, ["list-A"])

            source.setValue(
                Content(storage: .falseContent(DynamicListProbeB(recorder: recorder)))
            )
            let secondID = try firstID(in: list.value)
            XCTAssertNotEqual(secondID, initialID)
            let replacementTransaction = TransactionID(graph: graph)
            XCTAssertEqual(
                list.value.edit(forID: initialID, since: replacementTransaction),
                .removed
            )
            XCTAssertEqual(
                list.value.edit(forID: secondID, since: replacementTransaction),
                .inserted
            )
            XCTAssertEqual(recorder.events, ["list-A", "list-B"])

            source.setValue(
                Content(storage: .trueContent(DynamicListProbeA(recorder: recorder)))
            )
            XCTAssertEqual(try firstID(in: list.value), initialID)
            XCTAssertEqual(recorder.events, ["list-A", "list-B", "list-A"])
        }
    }

    func testAnyViewListDispatchesToConcreteChildAndKeepsGeneratedIdentityForSameType() throws {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        let recorder = DynamicViewConstructionRecorder()

        try context.withCurrent {
            let source = graph.makeInput(
                value: AnyView(DynamicListProbeA(recorder: recorder))
            )
            let outputs = AnyView._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph).listInputs
            )
            let list = try dynamicListAttribute(from: outputs)
            let initialID = try firstID(in: list.value)
            XCTAssertFalse(list.value.traits[CanTransitionTraitKey.self])
            XCTAssertEqual(recorder.events, ["list-A"])

            source.setValue(AnyView(DynamicListProbeA(recorder: recorder)))
            XCTAssertEqual(try firstID(in: list.value), initialID)
            XCTAssertEqual(recorder.events, ["list-A"])

            source.setValue(AnyView(DynamicListProbeB(recorder: recorder)))
            XCTAssertNotEqual(try firstID(in: list.value), initialID)
            XCTAssertEqual(recorder.events, ["list-A", "list-B"])
        }
    }

    func testNestedConditionalFlattensLeafIDsAndReplacesEqualConcreteTypes() throws {
        let graph = _AGGraph()
        let recorder = DynamicViewConstructionRecorder()

        try _AGGraph.withCurrent(graph) {
            typealias Inner = _ConditionalContent<DynamicViewProbeA, DynamicViewProbeA>
            typealias Content = _ConditionalContent<Inner, DynamicViewProbeB>
            let metadata = Content.makeConditionalMetadata(ViewDescriptor.self)
            XCTAssertEqual(metadata.desc.count, 3)
            XCTAssertEqual(metadata.ids.count, 3)

            func first(_ width: CGFloat, _ preference: String) -> Content {
                Content(
                    storage: .trueContent(
                        Inner(
                            storage: .trueContent(
                                DynamicViewProbeA(
                                    width: width,
                                    preference: preference,
                                    recorder: recorder
                                )
                            )
                        )
                    )
                )
            }
            func second(_ width: CGFloat, _ preference: String) -> Content {
                Content(
                    storage: .trueContent(
                        Inner(
                            storage: .falseContent(
                                DynamicViewProbeA(
                                    width: width,
                                    preference: preference,
                                    recorder: recorder
                                )
                            )
                        )
                    )
                )
            }

            let firstInfo = first(10, "first").childInfo(metadata: metadata)
            let secondInfo = second(20, "second").childInfo(metadata: metadata)
            XCTAssertTrue(firstInfo.type == DynamicViewProbeA.self)
            XCTAssertTrue(secondInfo.type == DynamicViewProbeA.self)
            XCTAssertNotEqual(firstInfo.id, secondInfo.id)

            let source = graph.makeInput(value: first(10, "first"))
            let outputs = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
            let layoutID = try XCTUnwrap(outputs._layoutComputer.attribute).identifier
            let preferenceID = try XCTUnwrap(
                outputs.preferences.value(for: DynamicViewProbePreferenceKey.self)
            )

            XCTAssertEqual(size(of: outputs), CGSize(width: 10, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "first")
            XCTAssertEqual(recorder.events, ["A"])

            source.setValue(second(24, "second"))
            XCTAssertEqual(size(of: outputs), CGSize(width: 24, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "second")
            XCTAssertEqual(recorder.events, ["A", "A"])
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)
        }
    }

    func testNestedOptionalAssignsDistinctLeafIDsToEachEmptyCase() {
        typealias Content = Optional<Optional<DynamicViewProbeA>>
        let metadata = Content.makeConditionalMetadata(ViewDescriptor.self)
        XCTAssertEqual(metadata.desc.count, 3)
        XCTAssertEqual(metadata.ids.count, 3)

        let outerNone = Content.none.childInfo(metadata: metadata)
        let innerNone = Content.some(.none).childInfo(metadata: metadata)
        XCTAssertTrue(outerNone.type == EmptyView.self)
        XCTAssertTrue(innerNone.type == EmptyView.self)
        XCTAssertNotEqual(outerNone.id, innerNone.id)
    }

    func testConditionalKeepsChildForMatchingTypeAndReplacesItForBranchSwitch() throws {
        let graph = _AGGraph()
        let recorder = DynamicViewConstructionRecorder()

        try _AGGraph.withCurrent(graph) {
            typealias Content = _ConditionalContent<DynamicViewProbeA, DynamicViewProbeB>
            let source = graph.makeInput(
                value: Content(
                    storage: .trueContent(
                        DynamicViewProbeA(
                            width: 10,
                            preference: "a0",
                            recorder: recorder
                        )
                    )
                )
            )
            let outputs = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
            let layoutID = try XCTUnwrap(outputs._layoutComputer.attribute).identifier
            let preferenceID = try XCTUnwrap(
                outputs.preferences.value(for: DynamicViewProbePreferenceKey.self)
            )

            XCTAssertEqual(size(of: outputs).width, 10)
            XCTAssertEqual(Attribute<String>(preferenceID).value, "a0")
            XCTAssertEqual(recorder.events, ["A"])

            source.setValue(
                Content(
                    storage: .trueContent(
                        DynamicViewProbeA(
                            width: 25,
                            preference: "a1",
                            recorder: recorder
                        )
                    )
                )
            )
            XCTAssertEqual(size(of: outputs).width, 25)
            XCTAssertEqual(Attribute<String>(preferenceID).value, "a1")
            XCTAssertEqual(recorder.events, ["A"])
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)

            source.setValue(
                Content(
                    storage: .falseContent(
                        DynamicViewProbeB(
                            width: 40,
                            preference: "b0",
                            recorder: recorder
                        )
                    )
                )
            )
            XCTAssertEqual(size(of: outputs), CGSize(width: 40, height: 20))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "b0")
            XCTAssertEqual(recorder.events, ["A", "B"])
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)

            source.setValue(
                Content(
                    storage: .trueContent(
                        DynamicViewProbeA(
                            width: 55,
                            preference: "a2",
                            recorder: recorder
                        )
                    )
                )
            )
            XCTAssertEqual(size(of: outputs), CGSize(width: 55, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "a2")
            XCTAssertEqual(recorder.events, ["A", "B", "A"])
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)
        }
    }

    func testOptionalKeepsFixedOutputsAcrossSomeNoneSomeReplacement() throws {
        let graph = _AGGraph()
        let recorder = DynamicViewConstructionRecorder()

        try _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(
                value: Optional<DynamicViewProbeA>.some(
                    DynamicViewProbeA(
                        width: 12,
                        preference: "some0",
                        recorder: recorder
                    )
                )
            )
            let outputs = Optional<DynamicViewProbeA>._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
            let layoutID = try XCTUnwrap(outputs._layoutComputer.attribute).identifier
            let preferenceID = try XCTUnwrap(
                outputs.preferences.value(for: DynamicViewProbePreferenceKey.self)
            )

            XCTAssertEqual(size(of: outputs), CGSize(width: 12, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "some0")
            XCTAssertEqual(recorder.events, ["A"])

            source.setValue(nil)
            XCTAssertEqual(size(of: outputs), CGSize(width: 10, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "")
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)

            source.setValue(
                DynamicViewProbeA(
                    width: 33,
                    preference: "some1",
                    recorder: recorder
                )
            )
            XCTAssertEqual(size(of: outputs), CGSize(width: 33, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "some1")
            XCTAssertEqual(recorder.events, ["A", "A"])
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)
        }
    }

    func testAnyViewKeepsConcreteChildForSameTypeAndReplacesOnTypeChange() throws {
        let graph = _AGGraph()
        let recorder = DynamicViewConstructionRecorder()

        try _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(
                value: AnyView(
                    DynamicViewProbeA(
                        width: 15,
                        preference: "a0",
                        recorder: recorder
                    )
                )
            )
            let outputs = AnyView._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
            let layoutID = try XCTUnwrap(outputs._layoutComputer.attribute).identifier
            let preferenceID = try XCTUnwrap(
                outputs.preferences.value(for: DynamicViewProbePreferenceKey.self)
            )

            XCTAssertEqual(size(of: outputs), CGSize(width: 15, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "a0")
            XCTAssertEqual(recorder.events, ["A"])

            source.setValue(
                AnyView(
                    DynamicViewProbeA(
                        width: 28,
                        preference: "a1",
                        recorder: recorder
                    )
                )
            )
            XCTAssertEqual(size(of: outputs), CGSize(width: 28, height: 10))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "a1")
            XCTAssertEqual(recorder.events, ["A"])

            source.setValue(
                AnyView(
                    DynamicViewProbeB(
                        width: 45,
                        preference: "b0",
                        recorder: recorder
                    )
                )
            )
            XCTAssertEqual(size(of: outputs), CGSize(width: 45, height: 20))
            XCTAssertEqual(Attribute<String>(preferenceID).value, "b0")
            XCTAssertEqual(recorder.events, ["A", "B"])
            XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layoutID)
        }
    }

    private func size(of outputs: _ViewOutputs) -> CGSize {
        outputs._layoutComputer.attribute?.value.sizeThatFits(.unspecified) ?? .zero
    }

    private func dynamicListAttribute(
        from outputs: _ViewListOutputs
    ) throws -> Attribute<any ViewList> {
        guard case .dynamicList(let list, _) = outputs.views else {
            throw DynamicViewTestError.expectedDynamicList
        }
        return list
    }

    private func firstID(in list: any ViewList) throws -> _ViewList_ID {
        var result: _ViewList_ID?
        var from = 0
        _ = list.applyNodes(
            from: &from,
            style: _ViewList_IteratorStyle(),
            list: nil,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, node, transform in
            guard case .sublist(var sublist) = node else { return true }
            transform.apply(to: &sublist)
            result = sublist.id
            return false
        }
        guard let result else {
            throw DynamicViewTestError.missingSublist
        }
        return result
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        var keys = PreferenceKeys()
        keys.add(DynamicViewProbePreferenceKey.self)
        let environment = graph.makeInput(value: EnvironmentValues.tracking())
        let graphInputs = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: graphInputs,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: keys,
                hostKeys: graph.makeInput(value: keys)
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
}

private enum DynamicViewTestError: Error {
    case expectedDynamicList
    case missingSublist
}
