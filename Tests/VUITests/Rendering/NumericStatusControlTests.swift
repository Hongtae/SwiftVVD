import XCTest
@testable import VUI
@testable import VVD

final class NumericStatusControlTests: XCTestCase {
    // ASSERTIONS: numericStatusPublicStructure27Observed
    // ASSERTIONS: sliderNormalization27Observed
    // ASSERTIONS: stepperActionOwnership27Observed
    // ASSERTIONS: progressFractionSemantics27Observed
    func testPublicNumericAndStatusControlsTypeCheck() {
        var sliderValue = 0.25
        var stepperValue = 2
        let sliderBinding = Binding(
            get: { sliderValue },
            set: { sliderValue = $0 }
        )
        let stepperBinding = Binding(
            get: { stepperValue },
            set: { stepperValue = $0 }
        )

        _ = Slider(value: sliderBinding, in: 0...1, step: 0.1) {
            Text("Gain")
        }
        _ = Stepper(value: stepperBinding, in: 0...4, step: 2) {
            Text("Count")
        }
        _ = ProgressView(value: 3.0, total: 8.0) {
            Text("Loading")
        } currentValueLabel: {
            Text("Three")
        }
        _ = ProgressView().progressViewStyle(.linear)
        _ = ProgressView().progressViewStyle(.circular)
    }

    // ASSERTIONS: numericStatusPublicStructure27Observed
    func testExtendedInitializerFamiliesAndTickBuilderTypeCheck() {
        let value = Binding.constant(0.5)
        _ = Slider(
            value: value,
            in: 0.0...1.0,
            neutralValue: 0.5,
            enabledBounds: 0.1...0.9
        ) {
            Text("Gain")
        } currentValueLabel: {
            Text("Half")
        }
        _ = Slider(
            value: value,
            in: 0.0...1.0,
            neutralValue: 0.5
        ) {
            Text("Gain")
        } ticks: {
            SliderTick("Quarter", 0.25)
            SliderTick("Three quarters", 0.75)
        }
        _ = Slider(
            value: value,
            in: 0.0...1.0,
            step: 0.25
        ) {
            Text("Gain")
        } tick: {
            $0 == 0.5 ? SliderTick("Half", $0) : nil
        }
        _ = SliderTickContentForEach(
            [0.25, 0.5, 0.75],
            id: \.self
        ) {
            SliderTick($0)
        }

        _ = Stepper(
            value: value,
            in: 0.0...1.0,
            step: 0.1,
            format: FloatingPointFormatStyle<Double>.number
        ) {
            Text("Gain")
        }
        _ = ProgressView(Foundation.Progress(totalUnitCount: 10))
        _ = ProgressView(
            timerInterval: Date()...Date(timeIntervalSinceNow: 10)
        )
    }

    // ASSERTIONS: numericStatusPublicStructure27Observed
    // ASSERTIONS: numericStatusFieldMetadata27Observed
    // ASSERTIONS: numericStatusOwnerLowering27Observed
    func testControlStorageAndResolvedOwnersRetainObservedShape() {
        let slider = Slider(
            value: Binding.constant(0.25),
            in: 0.0...1.0,
            step: 0.1
        ) {
            Text("Gain")
        } minimumValueLabel: {
            Text("Low")
        } maximumValueLabel: {
            Text("High")
        }
        XCTAssertEqual(
            Mirror(reflecting: slider).children.compactMap(\.label),
            [
                "_value", "neutralValue", "enabledBounds",
                "onEditingChanged", "skipDistance",
                "discreteValueCount", "marks", "ticks",
                "_minimumValueLabel", "_maximumValueLabel",
                "hasCustomMinMaxValueLabels", "label",
                "accessibilityValue",
            ]
        )
        let sliderBody = String(reflecting: type(of: slider.body))
        XCTAssertTrue(sliderBody.contains("ResolvedSliderStyle"))
        XCTAssertTrue(sliderBody.contains("StaticSourceWriter"))
        let sliderConfiguration = SliderStyleConfiguration(
            label: .init(),
            minimumValueLabel: .init(),
            maximumValueLabel: .init(),
            _value: slider._value,
            neutralValue: slider.neutralValue,
            enabledBounds: slider.enabledBounds,
            onEditingChanged: slider.onEditingChanged,
            skipDistance: slider.skipDistance,
            discreteValueCount: slider.discreteValueCount,
            ticks: slider.ticks,
            marks: slider.marks,
            hasCustomMinMaxValueLabels:
                slider.hasCustomMinMaxValueLabels,
            accessibilityValue: slider.accessibilityValue
        )
        XCTAssertEqual(
            Mirror(reflecting: sliderConfiguration)
                .children.compactMap(\.label),
            [
                "label", "minimumValueLabel", "maximumValueLabel",
                "_value", "neutralValue", "enabledBounds",
                "onEditingChanged", "skipDistance",
                "discreteValueCount", "ticks", "marks",
                "hasCustomMinMaxValueLabels", "accessibilityValue",
            ]
        )

        let stepper = Stepper(
            label: { Text("Actions") },
            onIncrement: {},
            onDecrement: {}
        )
        XCTAssertEqual(
            Mirror(reflecting: stepper).children.compactMap(\.label),
            ["configuration", "label", "accessibilityValue"]
        )
        let stepperBody = String(reflecting: type(of: stepper.body))
        XCTAssertTrue(stepperBody.contains("StepperBody"))
        XCTAssertTrue(stepperBody.contains("StaticSourceWriter"))
        XCTAssertEqual(
            Mirror(reflecting: stepper.configuration)
                .children.compactMap(\.label),
            [
                "currentValueField", "onIncrement", "onDecrement",
                "onEditingChanged",
            ]
        )

        let progress = ProgressView(value: 3.0, total: 8.0)
        XCTAssertEqual(
            Mirror(reflecting: progress).children.compactMap(\.label),
            ["base"]
        )
        let progressConfiguration = ProgressViewStyleConfiguration(
            value: .absolute(
                fractionCompleted: 0.375,
                alwaysIndeterminate: false
            ),
            hasLabel: true,
            hasCurrentValueLabel: true,
            hasActions: false
        )
        XCTAssertEqual(
            Mirror(reflecting: progressConfiguration)
                .children.compactMap(\.label),
            [
                "value", "fractionCompleted", "alwaysIndeterminate",
                "label", "currentValueLabel", "actions",
            ]
        )
        let resolvedProgress = ResolvedProgressView(
            value: .absolute(
                fractionCompleted: 0.375,
                alwaysIndeterminate: false
            ),
            _label: OptionalViewAlias(true),
            _currentValueLabel: OptionalViewAlias(true),
            _actions: OptionalViewAlias(false)
        )
        XCTAssertEqual(
            Mirror(reflecting: resolvedProgress)
                .children.compactMap(\.label),
            ["value", "_label", "_currentValueLabel", "_actions"]
        )
        let resolvedStyle = ResolvedProgressViewStyle(
            configuration: progressConfiguration
        )
        XCTAssertEqual(
            Mirror(reflecting: resolvedStyle)
                .children.compactMap(\.label),
            ["configuration"]
        )
    }

    // ASSERTIONS: sliderNormalization27Observed
    func testSliderProjectionNormalizesQuantizesAndRetainsRawEnabledBounds() {
        let continuous = Slider(value: Binding.constant(0.25))
        XCTAssertEqual(continuous.neutralValue, 0)
        XCTAssertEqual(continuous.skipDistance, 0.1)
        XCTAssertEqual(continuous.discreteValueCount, 0)
        XCTAssertNil(continuous.ticks)

        var value: Float = 12
        var writes: [Float] = []
        let slider: Slider<Text, Text> = Slider(
            value: Binding(
                get: { value },
                set: {
                    value = $0
                    writes.append($0)
                }
            ),
            in: Float(10)...Float(20),
            step: 2,
            neutralValue: 14,
            enabledBounds: Float(12)...Float(18)
        ) {
            Text("Value")
        } currentValueLabel: {
            Text("Twelve")
        } minimumValueLabel: {
            Text("Ten")
        } maximumValueLabel: {
            Text("Twenty")
        } tick: { value in
            value == 14 ? SliderTick("Neutral", value) : nil
        }

        XCTAssertEqual(slider._value.wrappedValue, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(slider.neutralValue, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(slider.enabledBounds?.lowerBound, 12)
        XCTAssertEqual(slider.enabledBounds?.upperBound, 18)
        XCTAssertEqual(slider.skipDistance, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(slider.discreteValueCount, 6)
        let tickValues = slider.ticks?.map(\.value) ?? []
        XCTAssertEqual(tickValues.count, 6)
        for (actual, expected) in zip(
            tickValues,
            [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
        ) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }

        slider._value.wrappedValue = 0.55
        XCTAssertEqual(value, 16)
        XCTAssertEqual(writes, [16])
    }

    // ASSERTIONS: stepperActionOwnership27Observed
    func testBoundedStepperKeepsSeparateOvershootingActions() throws {
        var value = 2
        var writes: [Int] = []
        let stepper = Stepper(
            value: Binding(
                get: { value },
                set: {
                    value = $0
                    writes.append($0)
                }
            ),
            in: 0...4,
            step: 2
        ) {
            Text("Count")
        }

        let increment = try XCTUnwrap(stepper.configuration.onIncrement)
        let decrement = try XCTUnwrap(stepper.configuration.onDecrement)
        increment()
        increment()
        increment()
        decrement()
        decrement()
        decrement()

        XCTAssertEqual(writes, [4, 6, 6, 2, 0, -2])
        XCTAssertEqual(value, -2)
    }

    // ASSERTIONS: progressFractionSemantics27Observed
    // ASSERTIONS: progressStyleLowering27Observed
    func testProgressFractionsAndPublicStyleDispatch() {
        XCTAssertNil(progressFraction(ProgressView()))
        XCTAssertTrue(progressAlwaysIndeterminate(ProgressView()))
        XCTAssertEqual(
            progressFraction(ProgressView(value: 3.0, total: 8.0)),
            0.375
        )
        XCTAssertFalse(progressAlwaysIndeterminate(
            ProgressView(value: 3.0, total: 8.0)
        ))
        let negative = ProgressView(value: -2.0, total: 8.0)
        XCTAssertNil(progressFraction(negative))
        XCTAssertFalse(progressAlwaysIndeterminate(negative))
        XCTAssertEqual(
            progressFraction(ProgressView(value: 10.0, total: 8.0)),
            1
        )
        XCTAssertEqual(
            progressFraction(ProgressView(value: 2.0, total: 0.0)),
            1
        )
        let notANumber = ProgressView(value: Double.nan, total: 8.0)
        XCTAssertNil(progressFraction(notANumber))
        XCTAssertFalse(progressAlwaysIndeterminate(notANumber))

        let recorder = ProgressStyleRecorder()
        render(
            ProgressView(value: 3.0, total: 8.0)
                .progressViewStyle(
                    RecordingProgressViewStyle(recorder: recorder)
                )
        )
        XCTAssertEqual(recorder.fractions, [0.375])
        XCTAssertEqual(recorder.labels, [false])
        XCTAssertEqual(recorder.currentValueLabels, [false])

        render(
            ProgressView(value: 3.0, total: 8.0) {
                Text("Loading")
            } currentValueLabel: {
                Text("Three")
            }
            .progressViewStyle(
                RecordingProgressViewStyle(recorder: recorder)
            )
        )
        XCTAssertEqual(recorder.fractions, [0.375, 0.375])
        XCTAssertEqual(recorder.labels, [false, true])
        XCTAssertEqual(recorder.currentValueLabels, [false, true])

        render(
            ProgressView(value: 3.0, total: 8.0) {
                Text("Loading")
            } currentValueLabel: {
                Text("Three")
            }
            .progressViewStyle(.linear)
        )
        render(ProgressView().progressViewStyle(.circular))
    }

    // ASSERTIONS: sliderPointerEditing27Observed
    @MainActor
    func testMountedSliderPointerWritesAndBracketsEditing() {
        let store = SliderPointerStore()
        let controller = WindowController(
            content: SliderPointerRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(SliderPointerRoot.self)
            )
        )
        var redraw = false
        let size = CGSize(width: 320, height: 64)
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 64, y: 32),
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .move,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 256, y: 32),
            timestamp: 0.01
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: CGPoint(x: 256, y: 32),
            timestamp: 0.02
        )))
        Update.dispatchActions()

        XCTAssertEqual(store.writes.count, 2)
        XCTAssertEqual(store.writes[0], 0.2, accuracy: 0.000_001)
        XCTAssertEqual(store.writes[1], 0.8, accuracy: 0.000_001)
        XCTAssertEqual(store.editing, [true, false])
    }

    // ASSERTIONS: stepperPointerWriteback27Observed
    @MainActor
    func testMountedStepperPointerUsesSeparateActionsWithoutEditingCallbacks() {
        let store = StepperPointerStore()
        let controller = WindowController(
            content: StepperPointerRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(StepperPointerRoot.self)
            )
        )
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 320, height: 64),
            redraw: &redraw
        ) { _, _ in }

        let controls = stepperControlPoints(
            in: controller,
            size: CGSize(width: 320, height: 64)
        )
        XCTAssertNotNil(controls)
        guard let controls else { return }

        for _ in 0..<2 {
            XCTAssertTrue(
                pointerClick(controller, at: controls.increment)
            )
        }
        for _ in 0..<3 {
            XCTAssertTrue(
                pointerClick(controller, at: controls.decrement)
            )
        }

        XCTAssertEqual(store.writes, [4, 6, 2, 0, -2])
        XCTAssertTrue(store.editing.isEmpty)
    }

    @MainActor
    private func pointerClick(
        _ controller: WindowController,
        at location: CGPoint
    ) -> Bool {
        let down = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0
        ))
        let up = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: 0.01
        ))
        Update.dispatchActions()
        return down && up
    }

    @MainActor
    private func stepperControlPoints(
        in controller: WindowController,
        size: CGSize
    ) -> (increment: CGPoint, decrement: CGPoint)? {
        var hitsByX: [Int: [Int]] = [:]
        for x in stride(from: 0, through: Int(size.width), by: 2) {
            for y in stride(from: 0, through: Int(size.height), by: 2) {
                let point = CGPoint(x: x, y: y)
                guard controller.gestureEnvironment
                    .eventBinding(
                        at: point,
                        accepting: VUI.MouseEvent.self
                    )?.responder is any AnyGestureResponder else {
                    continue
                }
                hitsByX[x, default: []].append(y)
            }
        }
        guard let column = hitsByX.max(by: {
            $0.value.count < $1.value.count
        }),
        let minimum = column.value.min(),
        let maximum = column.value.max(),
        maximum > minimum else {
            return nil
        }
        let upperY = minimum + (maximum - minimum) / 4
        let lowerY = maximum - (maximum - minimum) / 4
        return (
            CGPoint(x: column.key, y: upperY),
            CGPoint(x: column.key, y: lowerY)
        )
    }

    private func progressFraction<L, C>(
        _ progress: ProgressView<L, C>
    ) -> Double? where L: View, C: View {
        switch progress.base {
        case .custom(let custom):
            custom.value.fractionCompleted
        case .observing(let observed):
            observed.progress.isIndeterminate
                ? nil
                : observed.progress.fractionCompleted
        }
    }

    private func progressAlwaysIndeterminate<L, C>(
        _ progress: ProgressView<L, C>
    ) -> Bool where L: View, C: View {
        switch progress.base {
        case .custom(let custom):
            custom.value.alwaysIndeterminate
        case .observing(let observed):
            observed.progress.isIndeterminate
        }
    }

    private func render<Content: View>(_ root: Content) {
        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: Content.self,
            content: root,
            rendererHost: renderer,
            requestedOutputs: []
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 240, height: 120))
        graph.updateOutputs(at: .zero)
    }
}

private final class ProgressStyleRecorder: @unchecked Sendable {
    var fractions: [Double?] = []
    var labels: [Bool] = []
    var currentValueLabels: [Bool] = []
}

private struct RecordingProgressViewStyle: ProgressViewStyle {
    var recorder: ProgressStyleRecorder

    func makeBody(configuration: Configuration) -> some View {
        recorder.fractions.append(configuration.fractionCompleted)
        recorder.labels.append(configuration.label != nil)
        recorder.currentValueLabels.append(
            configuration.currentValueLabel != nil
        )
        return Text("Progress")
    }
}

private final class SliderPointerStore: @unchecked Sendable {
    var value = 0.5
    var writes: [Double] = []
    var editing: [Bool] = []
}

private struct SliderPointerRoot: View {
    var store: SliderPointerStore

    var body: some View {
        Slider(
            value: Binding(
                get: { store.value },
                set: {
                    store.value = $0
                    store.writes.append($0)
                }
            ),
            in: 0.0...1.0,
            onEditingChanged: { store.editing.append($0) }
        )
        .frame(width: 320, height: 64)
    }
}

private final class StepperPointerStore: @unchecked Sendable {
    var value = 2
    var writes: [Int] = []
    var editing: [Bool] = []
}

private struct StepperPointerRoot: View {
    var store: StepperPointerStore

    var body: some View {
        Stepper(
            value: Binding(
                get: { store.value },
                set: {
                    store.value = $0
                    store.writes.append($0)
                }
            ),
            in: 0...4,
            step: 2
        ) {
            Text("Count")
        } onEditingChanged: {
            store.editing.append($0)
        }
        .frame(width: 320, height: 64)
    }
}
