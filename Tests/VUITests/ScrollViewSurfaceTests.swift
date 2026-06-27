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
}

private struct ScrollViewRecordingContent: View, _PrimitiveView {
    var recorder: ScrollViewInputRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ScrollViewRecordingContent._makeView called outside an active AttributeGraph context.")
        }

        let recorder = view._attribute.value.recorder
        recorder.sawScrollablePreferenceKey = inputs.preferences.keys.contains(ScrollablePreferenceKey.self)
        recorder.sawUpdateScrollStateRequestKey = inputs.preferences.keys.contains(UpdateScrollStateRequestKey.self)
        recorder.sawScrollPhasePreferenceKey = inputs.preferences.keys.contains(ScrollPhasePreferenceKey.self)
        recorder.sawScrollGeometryPreferenceKey = inputs.preferences.keys.contains(ScrollGeometryPreferenceKey.self)
        recorder.scrollableAttribute = inputs.scrollable.attribute?.identifier
        recorder.phaseStateAttribute = inputs.base.scrollPhaseState.attribute?.identifier

        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 17, height: 23))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

final class ScrollViewSurfaceTests: XCTestCase {
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

    func testSystemScrollViewMakeViewInstallsScrollableInputsAndPreferenceProvider() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
                    contentSize: size,
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
        }
    }

    func testContainerBodyConfiguresPhaseStateAndResetsChildPreferenceRequests() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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

    func testScrollActionDispatcherUsesLastGeometryWhenRequested() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

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
        graph: AttributeGraph,
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
