import XCTest
@testable import VUI

final class DefaultCombiningAnimationTests: XCTestCase {
    func testCombineAnimationMovesPreviousStateIntoChildAndFreshensOuterState() throws {
        var animation = Animation(UnitLinearAnimation(duration: 1.0))
        var state = AnimationState<Double>()
        state[CombinedOuterStateMarker.self] = 42

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        XCTAssertEqual(state[CombinedOuterStateMarker.self], -1)
        let firstChildState = try XCTUnwrap(state.combinedState.entries.first?.state)
        XCTAssertEqual(firstChildState[CombinedOuterStateMarker.self], 42)
    }

    func testCombineAnimationUsesReplacementNewValueAsAccumulatedTarget() throws {
        var animation = Animation(UnitLinearAnimation(duration: 1.0))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 15.0, time: 0.75, context: &context)
        )

        XCTAssertEqual(sample, 11.25, accuracy: 0.000_001)
    }

    func testRepeatedCombineAnimationAppendsAccumulatedReplacementEntry() throws {
        var animation = Animation(UnitLinearAnimation(duration: 1.0))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )
        combineAnimation(
            into: &animation,
            state: &state,
            value: 15.0,
            elapsed: 0.50,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: -3.0
        )

        let box = try XCTUnwrap(animation.box as? CustomAnimationBox<DefaultCombiningAnimation>)
        XCTAssertEqual(box.base.entries.count, 3)
        XCTAssertEqual(box.base.entries.map(\.elapsed), [0.0, 0.25, 0.50])
        XCTAssertEqual(state.combinedState.entries.map(\.value), [10.0, 15.0, 12.0])

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 12.0, time: 0.75, context: &context)
        )

        XCTAssertEqual(sample, 11.4375, accuracy: 0.000_001)
    }

    func testCompletedChildKeepsAccumulatedContribution() throws {
        var animation = Animation(UnitLinearAnimation(duration: 0.2))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 15.0, time: 0.5, context: &context)
        )

        XCTAssertEqual(sample, 11.25, accuracy: 0.000_001)
    }

    func testLastChildNilTerminatesCombinedAnimation() {
        var animation = Animation(UnitLinearAnimation(duration: 0.2))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(UnitLinearAnimation(duration: 1.0)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)

        XCTAssertNil(animation.animate(value: 15.0, time: 1.25, context: &context))
        XCTAssertTrue(context.isLogicallyComplete)
    }

    func testReplacementChildLogicalFlagPropagatesBeforeNil() throws {
        var animation = Animation(LogicalFlagAnimation(duration: 2.0, logicalAt: nil))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(LogicalFlagAnimation(duration: 2.0, logicalAt: 0.50)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 15.0, time: 0.80, context: &context)
        )

        XCTAssertEqual(sample, 7.025, accuracy: 0.000_001)
        XCTAssertTrue(context.isLogicallyComplete)
    }

    func testOldChildLogicalFlagDoesNotPropagateToReplacementGeneration() throws {
        var animation = Animation(LogicalFlagAnimation(duration: 2.0, logicalAt: 0.20))
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(LogicalFlagAnimation(duration: 2.0, logicalAt: nil)),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        let sample = try XCTUnwrap(
            animation.animate(value: 15.0, time: 0.80, context: &context)
        )

        XCTAssertEqual(sample, 7.025, accuracy: 0.000_001)
        XCTAssertFalse(context.isLogicallyComplete)
    }

    func testReplacementLogicalFlagPersistsIntoLaterVisibleChildren() throws {
        let recorder = LogicalFlagContextRecorder()
        var animation = Animation(
            ContextRecordingLogicalFlagAnimation(
                label: "old",
                duration: 2.0,
                logicalAt: nil,
                recorder: recorder
            )
        )
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(
                ContextRecordingLogicalFlagAnimation(
                    label: "replacement",
                    duration: 2.0,
                    logicalAt: 0.50,
                    recorder: recorder
                )
            ),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        _ = try XCTUnwrap(animation.animate(value: 15.0, time: 0.80, context: &context))
        XCTAssertTrue(context.isLogicallyComplete)

        recorder.removeAll()
        _ = try XCTUnwrap(animation.animate(value: 15.0, time: 0.90, context: &context))

        XCTAssertTrue(
            recorder.events.contains {
                $0.label == "old" && $0.logicalAtEntry
            }
        )
        XCTAssertTrue(
            recorder.events.contains {
                $0.label == "replacement" && $0.logicalAtEntry
            }
        )
    }

    func testOldLogicalFlagDoesNotReachLaterReplacementChildContext() throws {
        let recorder = LogicalFlagContextRecorder()
        var animation = Animation(
            ContextRecordingLogicalFlagAnimation(
                label: "old",
                duration: 2.0,
                logicalAt: 0.20,
                recorder: recorder
            )
        )
        var state = AnimationState<Double>()

        combineAnimation(
            into: &animation,
            state: &state,
            value: 10.0,
            elapsed: 0.25,
            newAnimation: Animation(
                ContextRecordingLogicalFlagAnimation(
                    label: "replacement",
                    duration: 2.0,
                    logicalAt: nil,
                    recorder: recorder
                )
            ),
            newValue: 5.0
        )

        var context = AnimationContext(state: state)
        _ = try XCTUnwrap(animation.animate(value: 15.0, time: 0.80, context: &context))

        XCTAssertFalse(context.isLogicallyComplete)
        XCTAssertTrue(
            recorder.events.contains {
                $0.label == "old" && !$0.logicalAtEntry
            }
        )
        XCTAssertTrue(
            recorder.events.contains {
                $0.label == "replacement" && !$0.logicalAtEntry
            }
        )
    }
}

private struct CombinedOuterStateMarker: AnimationStateKey {
    static let defaultValue = -1
}

private struct LogicalFlagAnimation: CustomAnimation {
    var duration: TimeInterval
    var logicalAt: TimeInterval?

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        if let logicalAt, time >= logicalAt {
            context.isLogicallyComplete = true
        }
        guard time < duration else {
            return nil
        }

        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }
}

private final class LogicalFlagContextRecorder: @unchecked Sendable {
    struct Event: Equatable {
        var label: String
        var logicalAtEntry: Bool
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(label: String, logicalAtEntry: Bool) {
        lock.lock()
        storage.append(Event(label: label, logicalAtEntry: logicalAtEntry))
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

private struct ContextRecordingLogicalFlagAnimation: CustomAnimation {
    var label: String
    var duration: TimeInterval
    var logicalAt: TimeInterval?
    var recorder: LogicalFlagContextRecorder

    static func == (
        lhs: ContextRecordingLogicalFlagAnimation,
        rhs: ContextRecordingLogicalFlagAnimation
    ) -> Bool {
        lhs.label == rhs.label &&
            lhs.duration == rhs.duration &&
            lhs.logicalAt == rhs.logicalAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(duration)
        hasher.combine(logicalAt)
    }

    nonisolated func animate<Value>(
        value: Value,
        time: TimeInterval,
        context: inout AnimationContext<Value>
    ) -> Value? where Value: VectorArithmetic {
        recorder.record(label: label, logicalAtEntry: context.isLogicallyComplete)
        if let logicalAt, time >= logicalAt {
            context.isLogicallyComplete = true
        }
        guard time < duration else {
            return nil
        }

        var output = value
        output.scale(by: max(time / duration, 0))
        return output
    }
}
