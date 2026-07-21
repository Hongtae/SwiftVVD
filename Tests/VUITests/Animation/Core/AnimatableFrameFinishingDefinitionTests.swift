import XCTest
@testable import VUI

final class AnimatableFrameFinishingDefinitionTests: XCTestCase {
    func testSmallViewFrameFluidSpringFinishesDuringActivationThroughAnimatorStateInstaller() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        harness.setFrame(
            position: .zero,
            size: ViewSize(width: 11.0, height: 21.0),
            transaction: Transaction(animation: Self.fluidSpring)
        )

        let frame = harness.currentFrame()
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 11.0, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.height, 21.0, accuracy: 0.000_001)

        harness.setTime(0.6)
        let laterFrame = harness.currentFrame()
        XCTAssertEqual(laterFrame.size.width, 11.0, accuracy: 0.000_001)
        XCTAssertEqual(laterFrame.size.height, 21.0, accuracy: 0.000_001)
    }

    func testLargerViewFrameFluidSpringStillSamplesPresentationAtFirstRealFrame() {
        let harness = AnimatableFrameAttributeHarness(
            initialPosition: .zero,
            initialSize: ViewSize(width: 10, height: 20)
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        harness.setFrame(
            position: CGPoint(x: 2, y: 0),
            size: ViewSize(width: 10, height: 20),
            transaction: Transaction(animation: Self.fluidSpring)
        )
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)
        harness.setTime(0.5)
        XCTAssertEqual(harness.currentFrame().origin.x, 0, accuracy: 0.000_001)

        harness.setTime(0.6)
        let frame = harness.currentFrame()
        XCTAssertGreaterThan(frame.origin.x, 0)
        XCTAssertLessThan(frame.origin.x, 2)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.width, 10, accuracy: 0.000_001)
        XCTAssertEqual(frame.size.height, 20, accuracy: 0.000_001)
    }

    private static var fluidSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.7)
    }
}
