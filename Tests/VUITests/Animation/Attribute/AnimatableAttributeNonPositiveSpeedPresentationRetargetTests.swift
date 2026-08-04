import XCTest
@testable import VUI

final class AnimatableAttributeNonPositiveSpeedPresentationRetargetTests: XCTestCase {
    func testLinearRetargetedToSpeedZeroKeepsOldPresentationVisible() {
        assertLinearOldPresentationRemainsVisible(
            replacement: Animation.linear(duration: 0.45).speed(0),
            label: "speedZero"
        )
    }

    func testLinearRetargetedToNegativeSpeedKeepsOldPresentationVisible() {
        assertLinearOldPresentationRemainsVisible(
            replacement: Animation.linear(duration: 0.45).speed(-1),
            label: "negativeSpeed"
        )
    }

    func testSpeedZeroOldRetargetsFromHeldValue() {
        assertHeldOldSpeedRetargetsToLinear(
            oldAnimation: Animation.linear(duration: 0.45).speed(0),
            label: "speedZero"
        )
    }

    func testNegativeSpeedOldRetargetsFromHeldValue() {
        assertHeldOldSpeedRetargetsToLinear(
            oldAnimation: Animation.linear(duration: 0.45).speed(-1),
            label: "negativeSpeed"
        )
    }

    private func assertLinearOldPresentationRemainsVisible(
        replacement: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.24

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, label, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: Transaction(animation: Animation.linear(duration: 0.80))
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, label, file: file, line: line)
        harness.finalizeTransactionBody()

        sampleFrames(harness, through: retargetTime)
        let retargetStart = harness.currentValue().opacity
        XCTAssertGreaterThan(retargetStart, 0.20, label, file: file, line: line)
        XCTAssertLessThan(retargetStart, 0.40, label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: Transaction(animation: replacement)
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()

        harness.advanceTime(to: retargetTime + 0.21)
        let midRetarget = harness.currentValue().opacity
        XCTAssertGreaterThan(midRetarget, retargetStart + 0.15, label, file: file, line: line)
        XCTAssertGreaterThan(midRetarget, 0.45, label, file: file, line: line)

        harness.advanceTime(to: 1.0)
        let finalOldPresentation = harness.currentValue().opacity
        XCTAssertEqual(finalOldPresentation, 1.0, accuracy: 0.000_001, label, file: file, line: line)
    }

    private func assertHeldOldSpeedRetargetsToLinear(
        oldAnimation: Animation,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let harness = AnimatableAttributeHarness(
            initialValue: _OpacityEffect(opacity: 0)
        )
        let retargetTime = 0.24
        let replacementAnimation = Animation.linear(duration: 0.45)

        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, label, file: file, line: line)
        harness.setSource(
            _OpacityEffect(opacity: 1),
            transaction: Transaction(animation: oldAnimation)
        )
        XCTAssertEqual(harness.currentValue().opacity, 0, accuracy: 0.000_001, label, file: file, line: line)
        harness.finalizeTransactionBody()

        sampleFrames(harness, through: retargetTime)
        let heldStart = harness.currentValue().opacity
        XCTAssertEqual(heldStart, 0, accuracy: 0.000_001, label, file: file, line: line)

        harness.setSource(
            _OpacityEffect(opacity: -0.5),
            transaction: Transaction(animation: replacementAnimation)
        )
        _ = harness.currentValue()
        harness.finalizeTransactionBody()
        harness.flushCompletionActions()

        harness.advanceTime(to: retargetTime + 0.20)
        let midRetarget = harness.currentValue().opacity
        XCTAssertLessThan(midRetarget, -0.15, label, file: file, line: line)
        XCTAssertGreaterThan(midRetarget, -0.35, label, file: file, line: line)

        harness.advanceTime(to: retargetTime + 0.50)
        let finalReplacement = harness.currentValue().opacity
        XCTAssertEqual(finalReplacement, -0.5, accuracy: 0.000_001, label, file: file, line: line)
    }

    private func sampleFrames(
        _ harness: AnimatableAttributeHarness,
        through endTime: Double
    ) {
        var time = 1.0 / 60.0
        while time <= endTime {
            harness.advanceTime(to: time)
            _ = harness.currentValue()
            time += 1.0 / 60.0
        }
    }
}
