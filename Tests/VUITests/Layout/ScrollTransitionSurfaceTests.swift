import XCTest
@testable import VUI

private struct ScrollTransitionDisplaySource: View, TestPrimitiveView {
    typealias Body = Never

    var size = CGSize(width: 40, height: 40)

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollTransitionDisplaySource._makeView requires an active graph.")
        }
        let size = view._attribute.value.size
        let displayList = graph.makeRule {
            var list = DisplayList()
            list.appendCustomItem(
                bounds: CGRect(origin: .zero, size: size),
                isOpaque: false,
                colorMode: .nonLinear,
                rendersAsynchronously: false
            ) { _ in }
            return list
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(size)
        }
        var outputs = _ViewOutputs(
            layoutComputer: OptionalAttribute(layout)
        )
        outputs.preferences.append(
            DisplayList.Key.self,
            node: displayList.identifier
        )
        return outputs
    }
}

final class ScrollTransitionSurfaceTests: XCTestCase {
    // ASSERTIONS scrollTransitionCarrierRuntimeObserved
    func testPublicConfigurationAndModifierCarriersUseObservedStructure() throws {
        XCTAssertEqual(
            Mirror(reflecting: ScrollTransitionConfiguration.identity)
                .children.map(\.label),
            ["threshold", "mode"]
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.identity)
                .contains("visibility(1.0)")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.interactive)
                .contains("visibility(1.0)")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.animated)
                .contains("visibility(0.5)")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.identity.animation(.linear))
                .contains("identity")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.interactive.animation(.linear))
                .contains("animation: Optional")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.animated.animation(.linear))
                .contains("animated(animation:")
        )

        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.Threshold.visible)
                .contains("visibility(1.0)")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.Threshold.hidden)
                .contains("visibility(0.0)")
        )
        XCTAssertTrue(
            String(describing: ScrollTransitionConfiguration.Threshold.centered)
                .contains("center")
        )
        let insetDescription = String(describing:
            ScrollTransitionConfiguration.Threshold.visible.inset(by: 12)
        )
        XCTAssertTrue(insetDescription.contains("inset(12.0"))
        XCTAssertTrue(insetDescription.contains("visibility(1.0)"))
        XCTAssertTrue(
            String(describing:
                ScrollTransitionConfiguration.Threshold.visible.interpolated(
                    towards: .hidden,
                    amount: 0.3
                )
            ).contains("amount: 0.3")
        )

        XCTAssertEqual(ScrollTransitionPhase.topLeading.value, -1)
        XCTAssertEqual(ScrollTransitionPhase.identity.value, 0)
        XCTAssertEqual(ScrollTransitionPhase.bottomTrailing.value, 1)
        XCTAssertFalse(ScrollTransitionPhase.topLeading.isIdentity)
        XCTAssertTrue(ScrollTransitionPhase.identity.isIdentity)
        XCTAssertFalse(ScrollTransitionPhase.bottomTrailing.isIdentity)

        let symmetric = EmptyView().scrollTransition(
            .interactive,
            axis: .vertical
        ) { effect, phase in
            effect.opacity(phase.isIdentity ? 1 : 0)
        }
        let modifier = try XCTUnwrap(
            Mirror(reflecting: symmetric).children.first {
                $0.label == "modifier"
            }?.value
        )
        XCTAssertEqual(
            Mirror(reflecting: modifier).children.map(\.label),
            ["transition", "topLeading", "bottomTrailing", "axis"]
        )
    }

    // ASSERTIONS scrollTransitionDisassemblyObserved
    func testThresholdsResolveVisibilityInsetInterpolationAndCenterDistances() throws {
        let cases: [(
            label: String,
            threshold: ScrollTransitionConfiguration.Threshold,
            boundary: CGFloat
        )] = [
            ("visible", .visible, 0),
            ("hidden", .hidden, 40),
            ("centered", .centered, -30),
            ("inset", .visible.inset(by: 10), -10),
            (
                "interpolated",
                .visible.interpolated(towards: .hidden, amount: 0.5),
                20
            ),
            ("unclamped visibility", .visible(1.25), -10),
            (
                "unclamped interpolation",
                .visible.interpolated(towards: .hidden, amount: 1.5),
                60
            ),
        ]

        for testCase in cases {
            let configuration = ScrollTransitionConfiguration
                .animated(.linear(duration: 1))
                .threshold(testCase.threshold)
            XCTAssertEqual(
                try opacity(
                    at: testCase.boundary,
                    topLeading: configuration,
                    bottomTrailing: .identity
                ),
                0.6,
                accuracy: 0.000_001,
                testCase.label
            )
            XCTAssertEqual(
                try opacity(
                    at: testCase.boundary + 0.001,
                    topLeading: configuration,
                    bottomTrailing: .identity
                ),
                0.2,
                accuracy: 0.000_001,
                testCase.label
            )
        }
    }

    // ASSERTIONS scrollTransitionProgressRuntimeObserved
    func testInteractiveProgressInterpolatesBothEdgesTowardIdentity() throws {
        let configuration = ScrollTransitionConfiguration.interactive(
            timingCurve: .linear
        )

        XCTAssertEqual(
            try opacity(
                at: 40,
                topLeading: configuration,
                bottomTrailing: configuration
            ),
            0.2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: 20,
                topLeading: configuration,
                bottomTrailing: configuration
            ),
            0.4,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: -30,
                topLeading: configuration,
                bottomTrailing: configuration
            ),
            0.6,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: -80,
                topLeading: configuration,
                bottomTrailing: configuration
            ),
            0.8,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: -100,
                topLeading: configuration,
                bottomTrailing: configuration
            ),
            1.0,
            accuracy: 0.000_001
        )
    }

    // ASSERTIONS scrollTransitionProgressRuntimeObserved
    func testInteractiveProgressCombinesOverlappingTallTargetStages() throws {
        let configuration = ScrollTransitionConfiguration.interactive(
            timingCurve: .linear
        )
        XCTAssertEqual(
            try opacity(
                at: 0,
                topLeading: configuration,
                bottomTrailing: configuration,
                targetSize: CGSize(width: 40, height: 160)
            ),
            0.75,
            accuracy: 0.000_001
        )
    }

    // ASSERTIONS scrollTransitionProgressRuntimeObserved
    func testAnimatedAndIdentityModesUseThresholdAndIdentityFractions() throws {
        XCTAssertEqual(
            try opacity(
                at: 19,
                topLeading: .animated(.linear(duration: 1)),
                bottomTrailing: .identity
            ),
            0.6,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: 21,
                topLeading: .animated(.linear(duration: 1)),
                bottomTrailing: .identity
            ),
            0.2,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: 40,
                topLeading: .identity,
                bottomTrailing: .identity
            ),
            0.6,
            accuracy: 0.000_001
        )
    }

    // ASSERTIONS scrollTransitionProgressRuntimeObserved
    func testNilAxisUsesHorizontalOnlyForAnExactlyHorizontalNearestScrollView() throws {
        let configuration = ScrollTransitionConfiguration.interactive(
            timingCurve: .linear
        )
        XCTAssertEqual(
            try opacity(
                at: 20,
                topLeading: configuration,
                bottomTrailing: configuration,
                axis: nil,
                nearestAxes: .horizontal,
                coordinateSpaceAxis: .horizontal
            ),
            0.4,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try opacity(
                at: 20,
                topLeading: configuration,
                bottomTrailing: configuration,
                axis: nil,
                nearestAxes: [.horizontal, .vertical],
                coordinateSpaceAxis: .vertical
            ),
            0.4,
            accuracy: 0.000_001
        )
    }

    // ASSERTIONS scrollTransitionTransactionDisassemblyObserved
    func testConfigurationAnimationAnimatesTheProgressNode() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let configuration = ScrollTransitionConfiguration.interactive(
                timingCurve: .linear
            ).animation(.linear(duration: 1))
            let view = ScrollTransitionDisplaySource().scrollTransition(
                topLeading: configuration,
                bottomTrailing: .identity,
                axis: .vertical
            ) { effect, phase in
                effect.opacity(phase == .topLeading ? 0.2 : 0.6)
            }
            let source = graph.makeInput(value: view)
            let inputs = makeViewInputs(
                graph: graph,
                coordinate: -30,
                nearestAxes: .vertical,
                coordinateSpaceAxis: .vertical
            )
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )
            let outputID = try XCTUnwrap(
                outputs.preferences.value(for: DisplayList.Key.self)
            )
            let output = Attribute<DisplayList>(outputID)

            XCTAssertEqual(
                try opacity(in: output.value),
                0.6,
                accuracy: 0.000_001
            )

            inputs.position.setValue(CGPoint(x: 0, y: -40))
            XCTAssertEqual(
                try opacity(in: output.value),
                0.6,
                accuracy: 0.000_001
            )

            advance(
                output: output,
                time: inputs.base.time,
                from: 0,
                to: 0.5
            )
            let halfwayOpacity = try opacity(in: output.value)
            XCTAssertGreaterThan(halfwayOpacity, 0.39)
            XCTAssertLessThan(halfwayOpacity, 0.42)

            advance(
                output: output,
                time: inputs.base.time,
                from: 0.5,
                to: 1.1
            )
            XCTAssertEqual(
                try opacity(in: output.value),
                0.2,
                accuracy: 0.000_001
            )
        }
    }

    private func advance(
        output: Attribute<DisplayList>,
        time: Attribute<Time>,
        from start: Double,
        to end: Double
    ) {
        let frameInterval = 1.0 / 120.0
        var sample = start + frameInterval
        while sample < end {
            time.setValue(Time(seconds: sample))
            _ = output.value
            sample += frameInterval
        }
        time.setValue(Time(seconds: end))
    }

    private func opacity(
        at coordinate: CGFloat,
        topLeading: ScrollTransitionConfiguration,
        bottomTrailing: ScrollTransitionConfiguration,
        axis: Axis? = .vertical,
        nearestAxes: Axis.Set = .vertical,
        coordinateSpaceAxis: Axis = .vertical,
        targetSize: CGSize = CGSize(width: 40, height: 40)
    ) throws -> Double {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        return try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let view = ScrollTransitionDisplaySource(size: targetSize).scrollTransition(
                topLeading: topLeading,
                bottomTrailing: bottomTrailing,
                axis: axis
            ) { effect, phase in
                let amount: Double
                switch phase {
                case .topLeading:
                    amount = 0.2
                case .identity:
                    amount = 0.6
                case .bottomTrailing:
                    amount = 1.0
                }
                return effect.opacity(amount)
            }
            let source = graph.makeInput(value: view)
            let inputs = makeViewInputs(
                graph: graph,
                coordinate: coordinate,
                nearestAxes: nearestAxes,
                coordinateSpaceAxis: coordinateSpaceAxis,
                targetSize: targetSize
            )
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )
            let outputID = try XCTUnwrap(
                outputs.preferences.value(for: DisplayList.Key.self)
            )
            return try opacity(
                in: Attribute<DisplayList>(outputID).value
            )
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        coordinate: CGFloat,
        nearestAxes: Axis.Set,
        coordinateSpaceAxis: Axis,
        targetSize: CGSize = CGSize(width: 40, height: 40)
    ) -> _ViewInputs {
        var environment = EnvironmentValues()
        environment.nearestScrollableAxes = nearestAxes

        var transform = ViewTransform.identity
        transform.appendPosition(.zero)
        switch coordinateSpaceAxis {
        case .horizontal:
            transform.appendSizedSpace(
                id: ScrollCoordinateSpace.horizontal.id,
                size: CGSize(width: 100, height: 100)
            )
        case .vertical:
            transform.appendSizedSpace(
                id: ScrollCoordinateSpace.vertical.id,
                size: CGSize(width: 100, height: 100)
            )
        }

        let position: CGPoint
        switch coordinateSpaceAxis {
        case .horizontal:
            position = CGPoint(x: -coordinate, y: 0)
        case .vertical:
            position = CGPoint(x: 0, y: -coordinate)
        }

        var preferenceKeys = PreferenceKeys()
        preferenceKeys.add(DisplayList.Key.self)
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: environment),
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: preferenceKeys,
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: transform),
            position: graph.makeInput(value: position),
            containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(targetSize)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func opacity(in list: DisplayList) throws -> Double {
        guard let item = list.items.first,
              case let .content(content) = item.value else {
            throw ScrollTransitionTestError.missingOpacity
        }
        switch content.value {
        case let .style(value):
            guard case let .opacity(amount) = value.style else {
                throw ScrollTransitionTestError.missingOpacity
            }
            return amount
        case let .backend(command, _):
            guard case .custom = command else {
                throw ScrollTransitionTestError.missingOpacity
            }
            return 1
        default:
            throw ScrollTransitionTestError.missingOpacity
        }
    }
}

private enum ScrollTransitionTestError: Error {
    case missingOpacity
}
