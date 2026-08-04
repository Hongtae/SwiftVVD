import XCTest
@testable import VUI

private struct KeyframeRootValue: Animatable {
    var x: Double
    var y: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }
}

final class KeyframeTimelineTests: XCTestCase {
    // ASSERTIONS keyframePublicSurfaceObserved
    func testConcreteStorageAndBuilderCarriersMatchObservedShape() {
        typealias Conditional = KeyframeTrackContentBuilder<Double>.Conditional<
            Double,
            LinearKeyframe<Double>,
            MoveKeyframe<Double>
        >
        XCTAssertTrue(Conditional.Body.self == Conditional.self)

        let move = MoveKeyframe(4.0)
        XCTAssertEqual(Mirror(reflecting: move).children.map(\.label), ["value"])

        let linear = LinearKeyframe(4.0, duration: 2)
        let cubic = CubicKeyframe(
            4.0,
            duration: 2,
            startVelocity: 1.5,
            endVelocity: -0.5
        )
        let spring = SpringKeyframe(
            4.0,
            duration: 2,
            spring: .smooth,
            startVelocity: 1.5
        )
        XCTAssertEqual(Mirror(reflecting: linear).children.map(\.label), ["segment"])
        XCTAssertEqual(Mirror(reflecting: cubic).children.map(\.label), ["segment"])
        XCTAssertEqual(Mirror(reflecting: spring).children.map(\.label), ["segment"])

        let timeline = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(1.0, duration: 1)
            CubicKeyframe(2.0, duration: 1)
            SpringKeyframe(3.0, duration: 1)
        }
        XCTAssertEqual(Mirror(reflecting: timeline).children.map(\.label), [
            "initialValue",
            "content",
        ])
        XCTAssertEqual(Mirror(reflecting: timeline.content).children.map(\.label), ["tracks"])
        XCTAssertEqual(timeline.content.tracks.count, 1)
        XCTAssertEqual(Mirror(reflecting: timeline.content.tracks[0]).children.map(\.label), [
            "duration",
            "update",
            "updateVelocity",
        ])
    }

    // ASSERTIONS keyframeTimelineBasicSemanticsObserved
    func testMoveAndLinearEndpointSemantics() {
        let move = KeyframeTimeline(initialValue: 0.0) {
            MoveKeyframe(4.0)
        }
        XCTAssertEqual(move.duration, 0)
        for time in [-1.0, 0, 0.5, 1] {
            XCTAssertEqual(move.value(time: time), 4)
        }
        for progress in [-0.25, 0, 0.25, 0.5, 0.75, 1, 1.25] {
            XCTAssertEqual(move.value(progress: progress), 4)
        }

        let linear = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(4.0, duration: 2)
        }
        XCTAssertEqual(linear.duration, 2)
        assertSamples(
            linear,
            times: [-1, 0, 0.5, 1, 1.5, 2, 3],
            expected: [0, 0, 1, 2, 3, 4, 4]
        )
        assertProgressSamples(
            linear,
            progresses: [-0.25, 0, 0.25, 0.5, 0.75, 1, 1.25],
            expected: [0, 0, 1, 2, 3, 4, 4]
        )
    }

    func testEasedCubicAndSpringSamplesMatchObservedValues() {
        let eased = KeyframeTimeline(initialValue: 0.0) {
            LinearKeyframe(4.0, duration: 2, timingCurve: .easeInOut)
        }
        assertSamples(
            eased,
            times: [0.5, 1, 1.5],
            expected: [0.5166473388671875, 2, 3.4833526611328125],
            accuracy: 0.000_001
        )

        let cubic = KeyframeTimeline(initialValue: 0.0) {
            CubicKeyframe(
                4.0,
                duration: 2,
                startVelocity: 1.5,
                endVelocity: -0.5
            )
        }
        assertSamples(
            cubic,
            times: [-1, 0, 0.5, 1, 1.5, 2, 3],
            expected: [0, 0, 1.09375, 2.5, 3.65625, 4, 4]
        )

        let spring = KeyframeTimeline(initialValue: 0.0) {
            SpringKeyframe(
                4.0,
                duration: 2,
                spring: .smooth,
                startVelocity: 1.5
            )
        }
        assertSamples(
            spring,
            times: [-1, 0, 0.5, 1, 1.5, 2, 3],
            expected: [
                12_836_564.877865782,
                0,
                3.946996856186481,
                3.99981598869808,
                3.9999994975789717,
                3.9999999987652255,
                3.9999999987652255,
            ],
            accuracy: 0.000_001
        )
    }

    func testConditionalArrayAndMultipleRootTracksResolveInSourceOrder() {
        func conditional(_ useLinear: Bool) -> KeyframeTimeline<Double> {
            KeyframeTimeline(initialValue: 0.0) {
                if useLinear {
                    LinearKeyframe(4.0, duration: 2)
                } else {
                    MoveKeyframe(4.0)
                }
            }
        }
        XCTAssertEqual(conditional(true).duration, 2)
        XCTAssertEqual(conditional(true).value(time: 1), 2)
        XCTAssertEqual(conditional(false).duration, 0)
        XCTAssertEqual(conditional(false).value(time: -1), 4)

        let array = KeyframeTimeline(initialValue: 0.0) {
            for value in [1.0, 2.0, 3.0] {
                LinearKeyframe(value, duration: 1)
            }
        }
        XCTAssertEqual(array.duration, 3)
        XCTAssertEqual(array.value(time: 0.5), 0.5)
        XCTAssertEqual(array.value(time: 1.5), 1.5)
        XCTAssertEqual(array.value(time: 2.5), 2.5)

        let root = KeyframeTimeline(initialValue: KeyframeRootValue(x: 0, y: 0)) {
            KeyframeTrack(\KeyframeRootValue.x) {
                LinearKeyframe(10.0, duration: 2)
            }
            KeyframeTrack(\KeyframeRootValue.y) {
                MoveKeyframe(5.0)
                LinearKeyframe(9.0, duration: 1)
            }
        }
        XCTAssertEqual(root.duration, 2)
        let expected = [
            KeyframeRootValue(x: 0, y: 5),
            KeyframeRootValue(x: 0, y: 5),
            KeyframeRootValue(x: 2.5, y: 7),
            KeyframeRootValue(x: 5, y: 9),
            KeyframeRootValue(x: 7.5, y: 9),
            KeyframeRootValue(x: 10, y: 9),
            KeyframeRootValue(x: 10, y: 9),
        ]
        for (time, expectedValue) in zip([-1.0, 0, 0.5, 1, 1.5, 2, 3], expected) {
            let value = root.value(time: time)
            XCTAssertEqual(value.x, expectedValue.x, accuracy: 0.000_001)
            XCTAssertEqual(value.y, expectedValue.y, accuracy: 0.000_001)
        }
    }

    // ASSERTIONS keyframeTimelineVelocityInitialValueSeedObserved
    func testVelocitySeedsUntrackedComponentsFromInitialValue() {
        let timeline = KeyframeTimeline(
            initialValue: KeyframeRootValue(x: 10, y: 20)
        ) {
            KeyframeTrack(\KeyframeRootValue.x) {
                LinearKeyframe(100.0, duration: 1)
            }
        }

        let velocity = timeline.velocity(time: 0.25)
        XCTAssertEqual(velocity.x, 90, accuracy: 0.000_001)
        XCTAssertEqual(velocity.y, 20, accuracy: 0.000_001)
    }

    private func assertSamples(
        _ timeline: KeyframeTimeline<Double>,
        times: [Double],
        expected: [Double],
        accuracy: Double = 0.000_000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(times.count, expected.count, file: file, line: line)
        for (time, expectedValue) in zip(times, expected) {
            XCTAssertEqual(
                timeline.value(time: time),
                expectedValue,
                accuracy: accuracy,
                "time=\(time)",
                file: file,
                line: line
            )
        }
    }

    private func assertProgressSamples(
        _ timeline: KeyframeTimeline<Double>,
        progresses: [Double],
        expected: [Double],
        accuracy: Double = 0.000_000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(progresses.count, expected.count, file: file, line: line)
        for (progress, expectedValue) in zip(progresses, expected) {
            XCTAssertEqual(
                timeline.value(progress: progress),
                expectedValue,
                accuracy: accuracy,
                "progress=\(progress)",
                file: file,
                line: line
            )
        }
    }
}
